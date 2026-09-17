import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { fixtureKey, signedAssertion, APP_PREFIX, TEST_GATE, TEST_BODY_HASH, TEST_TRANSACTION_HASH } from './auth-fixtures.js';
import { challengeToken, assertionPayload, VERSION, hash, attestKey } from '../src/coach-auth-crypto.js';
import { CoachAuthenticationState, RETENTION_MS } from '../src/coach-auth-state.js';
vi.mock('../src/coach-auth-crypto.js',async original => ({...await original(), attestKey:vi.fn()}));

// Transaction double serializes commits and rolls back on failure, matching the contract verified
// separately with actual SQLite workerd storage. Only attestation enrollment is a trusted-key double.
class Storage {
  record; alarm; chain=Promise.resolve(); writes=0;
  get=async () => structuredClone(this.record);
  put=async (_, value) => {this.record=structuredClone(value);this.writes++;};
  setAlarm=async value => {this.alarm=value;};
  delete=async () => {this.record=undefined;};
  transaction(action) {
    const result=this.chain.then(async()=>{
      const previous=structuredClone(this.record);const alarm=this.alarm;
      try {return await action(this);}catch(error){this.record=previous;this.alarm=alarm;throw error;}
    }); this.chain=result.catch(()=>{}); return result;
  }
}
describe('atomic security metadata lifecycle',()=>{
  let storage, object, key, now;
  beforeEach(()=>{
    now=1_800_000_000_000;vi.spyOn(Date,'now').mockImplementation(()=>now);
    key=fixtureKey();storage=new Storage();
    // @ts-expect-error Deliberately partial transaction double; actual platform is separately tested.
    object=new CoachAuthenticationState({storage},{CLIENT_SHARED_SECRET:TEST_GATE,APP_ATTEST_APP_PREFIX:APP_PREFIX});
    vi.mocked(attestKey).mockResolvedValue(key.publicKey);
  });
  afterEach(()=>vi.restoreAllMocks());
  const call=async (target,input)=>target.fetch(new Request('https://security.invalid/',{method:'POST',body:JSON.stringify(input)}));
  const enroll=()=>({operation:'enroll',keyId:key.keyId,challenge:challengeToken(key.keyId,TEST_GATE,now),attestation:'AA=='});
  const authorize=async (counter=1,operation='reply')=>{
    const challenge=challengeToken(key.keyId,TEST_GATE,now);
    expect((await call(object,{operation:'challenge',keyId:key.keyId,challenge})).status).toBe(200);
    return {operation,keyId:key.keyId,challenge,bodyHash:TEST_BODY_HASH,transactionHash:TEST_TRANSACTION_HASH,
      assertion:signedAssertion(key,assertionPayload(operation,key.keyId,challenge,TEST_BODY_HASH,TEST_TRANSACTION_HASH),counter).toString('base64')};
  };
  it('stores only bounded security fields and prevents duplicate enrollment/counter reset',async()=>{
    const input=enroll();expect((await call(object,input)).status).toBe(200);
    expect(Object.keys(storage.record).sort()).toEqual(['counter','expiresAt','publicKey','v']);
    expect(JSON.stringify(storage.record).length).toBeLessThan(2048);
    expect(storage.alarm).toBe(now+RETENTION_MS);
    expect((await call(object,input)).status).toBe(401);expect(storage.record.counter).toBe(0);
    const assertion=await authorize();expect((await call(object,assertion)).status).toBe(200);
    expect((await call(object,input)).status).toBe(401);expect(storage.record.counter).toBe(1);
  });
  it('bounds/rejects unverified enrollment before any storage write',async()=>{
    vi.mocked(attestKey).mockRejectedValue(new Error('private verifier detail'));
    expect((await call(object,enroll())).status).toBe(503);expect(storage.writes).toBe(0);
    expect((await call(object,{...enroll(),attestation:'A'.repeat(12000)})).status).toBe(401);expect(storage.writes).toBe(0);
  });
  it('atomically consumes a nonce exactly once under concurrent assertions',async()=>{
    await call(object,enroll());const input=await authorize();
    const results=await Promise.all([call(object,input),call(object,input)]);
    expect(results.map(r=>r.status).sort()).toEqual([200,401]);expect(storage.record.counter).toBe(1);
    expect(storage.record.pendingNonceHash).toBeUndefined();
  });
  it('rejects reuse of the same consumed challenge even with a newer genuine signature',async()=>{
    await call(object,enroll());const input=await authorize();await call(object,input);
    input.assertion=signedAssertion(key,assertionPayload('reply',key.keyId,input.challenge,TEST_BODY_HASH,TEST_TRANSACTION_HASH),2).toString('base64');
    expect((await call(object,input)).status).toBe(401);expect(storage.record.counter).toBe(1);
  });
  it('replaces pending challenges without extending inactivity retention',async()=>{
    await call(object,enroll());const first=await authorize();const expiry=storage.record.expiresAt;now+=1;
    const second=await authorize();expect(storage.record.expiresAt).toBe(expiry);
    expect(storage.record.pendingNonceHash).toBe(hash(second.challenge));
    expect((await call(object,first)).status).toBe(401);expect((await call(object,second)).status).toBe(200);
  });
  it.each(['bodyHash','transactionHash'])('rejects substituted %s without consuming correct proof',async field=>{
    await call(object,enroll());const input=await authorize();
    expect((await call(object,{...input,[field]:hash('substitution')})).status).toBe(401);
    expect(storage.record.counter).toBe(0);expect((await call(object,input)).status).toBe(200);
  });
  it('expires keys and prevents stale captured enrollment re-use after expiry',async()=>{
    const input=enroll();await call(object,input);now+=RETENTION_MS;
    expect((await call(object,{operation:'challenge',keyId:key.keyId,challenge:challengeToken(key.keyId,TEST_GATE,now)})).status).toBe(401);
    await object.alarm();expect(storage.record).toBeUndefined();
    expect((await call(object,input)).status).toBe(401);expect(storage.record).toBeUndefined();
  });
  it('deletes metadata with a short tombstone that blocks still-valid captured enrollment',async()=>{
    const captured=enroll();await call(object,captured);const input=await authorize(1,'delete');
    expect((await call(object,input)).status).toBe(200);
    expect(Object.keys(storage.record)).toEqual(['tombstoneUntil']);
    expect((await call(object,captured)).status).toBe(401);
    now+=60000;await object.alarm();expect(storage.record).toBeUndefined();
    expect((await call(object,captured)).status).toBe(401);
  });
  it('rejects expired pending challenge and fails closed on storage error',async()=>{
    await call(object,enroll());const input=await authorize();now+=60000;
    expect((await call(object,input)).status).toBe(401);
    storage.transaction=async()=>{throw new Error('private storage detail');};
    const response=await call(object,{operation:'challenge',keyId:key.keyId,challenge:challengeToken(key.keyId,TEST_GATE,now)});
    expect(response.status).toBe(503);expect(await response.text()).toBe('{"error":"auth_unavailable"}');
  });
});

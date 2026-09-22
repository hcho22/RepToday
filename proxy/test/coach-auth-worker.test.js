import {beforeEach,afterEach,describe,expect,it,vi} from 'vitest';
import {handleRuntimeCoach} from '../src/coach-auth-worker.js';
import {ORIGIN,challengeToken,CoachAuthFailure} from '../src/coach-auth-crypto.js';
import {fixtureKey,APP_PREFIX,TEST_GATE} from './auth-fixtures.js';
const key=fixtureKey();
const env={COACH_AUTH_MODE:'app-attest-storekit-v1',COACH_AUTH_STATE:{},CLIENT_SHARED_SECRET:TEST_GATE,
  APP_ATTEST_APP_PREFIX:APP_PREFIX,APP_STORE_APP_ID:'1',APP_STORE_KEY_ID:APP_PREFIX,
  APP_STORE_ISSUER_ID:'00000000-0000-4000-8000-000000000000',APP_STORE_PRIVATE_KEY:'TEST-ONLY-INVALID',OPENAI_API_KEY:'test-only-not-a-provider-key'};
const body={context:{phase:'discipline',requestedMinutes:20,chainPositions:[],recentPatterns:[],consistency:{currentScore:63,direction:'rising'}},
  message:'Why did I get squats?',safetyIdentifier:'coach-00000000-0000-4000-8000-000000000001'};
const proof=()=>({operation:'reply',keyId:key.keyId,challenge:challengeToken(key.keyId,TEST_GATE,Date.now()),assertion:'AA==',transactionJws:'test.purchase.proof'});
/** @param {any} [auth] @param {string} [data] */
const request=(auth=proof(),data=JSON.stringify(body))=>new Request(ORIGIN,{method:'POST',body:data,headers:auth?{'X-RepToday-Coach-Auth':JSON.stringify(auth)}:{}});
describe('gateway rejects failures before paid model transport',()=>{
  let upstream,state,premium,logs;
  beforeEach(()=>{
    state=vi.fn(async()=>({authorized:true,ready:true,enrolled:true}));premium=vi.fn(async()=>{});
    upstream=vi.fn(async()=>({ok:true,json:async()=>({status:'completed',error:null,output:[{type:'message',content:[{type:'output_text',text:'Fixture reply'}]}]})}));
    vi.stubGlobal('fetch',upstream);logs=[vi.spyOn(console,'log'),vi.spyOn(console,'warn'),vi.spyOn(console,'error')].map(spy=>spy.mockImplementation(()=>{}));
  });afterEach(()=>{vi.useRealTimers();vi.unstubAllGlobals();vi.restoreAllMocks();});
  const run=(r=request(),e=env)=>handleRuntimeCoach(r,e,{state,premium});
  it('passes only the original coach body to the reviewed provider path after both gates',async()=>{
    expect((await run()).status).toBe(200);expect(state).toHaveBeenCalledOnce();expect(premium).toHaveBeenCalledOnce();expect(upstream).toHaveBeenCalledOnce();
    expect(state.mock.invocationCallOrder[0]).toBeLessThan(premium.mock.invocationCallOrder[0]);
    expect(premium.mock.invocationCallOrder[0]).toBeLessThan(upstream.mock.invocationCallOrder[0]);
    const payload=upstream.mock.calls[0][1].body;
    expect(payload).toContain('squats');expect(payload).not.toContain('test.purchase.proof');expect(payload).not.toContain(key.keyId);
    logs.forEach(log=>expect(log).not.toHaveBeenCalled());
  });
  it.each(['COACH_AUTH_MODE','COACH_AUTH_STATE','CLIENT_SHARED_SECRET','APP_ATTEST_APP_PREFIX','APP_STORE_APP_ID','APP_STORE_KEY_ID','APP_STORE_ISSUER_ID','APP_STORE_PRIVATE_KEY'])('missing %s fails closed',async field=>{
    expect((await run(request(),{...env,[field]:undefined})).status).toBe(503);expect(state).not.toHaveBeenCalled();expect(upstream).not.toHaveBeenCalled();
  });
  it.each([null,{}, {...proof(),keyId:fixtureKey().keyId},{...proof(),challenge:'forged'}, {...proof(),transactionJws:'x'.repeat(12001)},{...proof(),assertion:'AB=='}])('rejects incomplete/forged/substituted/oversized proof',async auth=>{
    expect((await run(request(auth))).status).toBe(401);expect(state).not.toHaveBeenCalled();expect(upstream).not.toHaveBeenCalled();
  });
  it('bounds coach/enrollment bytes before state allocation or verification',async()=>{
    expect((await run(request(null,' '.repeat(32769)))).status).toBe(413);expect(state).not.toHaveBeenCalled();expect(upstream).not.toHaveBeenCalled();
  });
  it('unknown enrollment challenges allocate no security record',async()=>{
    const r=await run(request(null,JSON.stringify({operation:'challenge',kind:'enroll',keyId:key.keyId})));
    expect(r.status).toBe(200);expect(state).not.toHaveBeenCalled();expect(upstream).not.toHaveBeenCalled();
  });
  it.each(['state','premium'])('%s failure stops before provider and suppresses arbitrary diagnostics',async boundary=>{
    ({state,premium})[boundary].mockRejectedValue(new Error('private proof/token/server detail'));
    const r=await run();expect(r.status).toBe(503);expect(await r.text()).not.toContain('private');expect(upstream).not.toHaveBeenCalled();
    if(boundary==='state')expect(premium).not.toHaveBeenCalled();
  });
  it('revoked/nonpremium purchase never reaches provider after counter consumption',async()=>{
    premium.mockRejectedValue(new CoachAuthFailure());expect((await run()).status).toBe(401);expect(upstream).not.toHaveBeenCalled();
  });
  it('a hung premium lookup stops at the total authentication deadline and late completion cannot call the model',async()=>{
    vi.useFakeTimers();
    let complete=()=>{};
    premium.mockImplementation(()=>new Promise(resolve=>{complete=()=>resolve(undefined);}));
    const response=run();
    await vi.advanceTimersByTimeAsync(20_001);
    expect((await response).status).toBe(503);expect(upstream).not.toHaveBeenCalled();
    complete();await Promise.resolve();expect(upstream).not.toHaveBeenCalled();
  });
  it('missing/wrong operator authorization fails before provider',async()=>{
    const r=new Request(ORIGIN,{method:'POST',body:JSON.stringify(body),headers:{Authorization:'Bearer wrong-fixture'}});
    expect((await run(r)).status).toBe(401);expect(upstream).not.toHaveBeenCalled();
  });
  it('the proof-only empty body is unavailable to even the valid operator bearer',async()=>{
    const r=new Request(ORIGIN,{method:'POST',body:'{}',headers:{Authorization:'Bearer '+TEST_GATE}});
    const result=await run(r);
    expect(result.status).toBe(401);expect(await result.json()).toEqual({error:'unauthorized'});
    expect(state).not.toHaveBeenCalled();expect(premium).not.toHaveBeenCalled();expect(upstream).not.toHaveBeenCalled();
  });
  it('empty runtime reply reaches invalid_context only after both authentication gates',async()=>{
    const result=await run(request(proof(),'{}'));
    expect(result.status).toBe(400);expect(await result.json()).toEqual({error:'invalid_context'});
    expect(state).toHaveBeenCalledOnce();expect(premium).toHaveBeenCalledOnce();expect(upstream).not.toHaveBeenCalled();
    expect(state.mock.invocationCallOrder[0]).toBeLessThan(premium.mock.invocationCallOrder[0]);
  });
  it.each(['state','premium'])('empty runtime reply cannot reach invalid_context with failed %s',async boundary=>{
    ({state,premium})[boundary].mockRejectedValue(new CoachAuthFailure());
    const result=await run(request(proof(),'{}'));
    expect(result.status).toBe(401);expect(await result.json()).toEqual({error:'unauthorized'});
    if(boundary==='state')expect(premium).not.toHaveBeenCalled();
    expect(upstream).not.toHaveBeenCalled();
  });
  it('metadata deletion uses a device assertion without a purchase/provider call',async()=>{
    const auth={...proof(),operation:'delete',transactionJws:''};
    expect((await run(request(auth,'{}'))).status).toBe(200);expect(premium).not.toHaveBeenCalled();expect(upstream).not.toHaveBeenCalled();
    expect((await run(request(auth,'{ }'))).status).toBe(401);
  });
  it('query/foreign endpoint is never authorized',async()=>{
    const r=new Request(ORIGIN+'?extra=1',{method:'POST',body:'{}'});expect((await run(r)).status).toBe(404);expect(upstream).not.toHaveBeenCalled();
  });
});

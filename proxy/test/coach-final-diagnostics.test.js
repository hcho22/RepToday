// Synthetic evidence only: generated local key + Apple workflow doubles. No genuine-device proof.
import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest';
import cbor from 'cbor';
import { handleRuntimeCoach } from '../src/coach-auth-worker.js';
import { CoachAuthenticationState, RETENTION_MS } from '../src/coach-auth-state.js';
import { emitFinalAuthDiagnostic } from '../src/coach-auth-diagnostics.js';
import { VERSION, ORIGIN, BUNDLE, hash, assertionPayload, assertKey, premiumEntitlement, CoachAuthFailure } from '../src/coach-auth-crypto.js';
import { fixtureKey, signedAssertion, APP_PREFIX, TEST_GATE, TEST_JWS } from './auth-fixtures.js';
const { verify, lookup } = vi.hoisted(() => ({ verify: vi.fn(), lookup: vi.fn() }));
vi.mock('@apple/app-store-server-library', () => ({
  Environment: { PRODUCTION: 'Production', SANDBOX: 'Sandbox' },
  VerificationException: class extends Error {}, VerificationStatus: { INVALID_ENVIRONMENT: 4 },
  SignedDataVerifier: class { verifyAndDecodeTransaction(jws) { return verify(jws); } },
  AppStoreServerAPIClient: class { getAllSubscriptionStatuses(id) { return lookup(id); } },
}));
const base = 1_800_000_000_000;
class Storage {
  record; writes = 0; lag = 0;
  get = async () => { clock -= this.lag; return structuredClone(this.record); };
  put = async (_, value) => { this.writes++; this.record = structuredClone(value); };
  setAlarm = async () => {};
  transaction = async action => {
    const old = structuredClone(this.record), writes = this.writes;
    try { return await action(this); } catch (e) { this.record = old; this.writes = writes; throw e; }
  };
}
let clock, key, storage, env, object, logs, network, doLag, presented, current, statuses;
const row = (stage, reason) => ({ event: 'coach_final_auth_guard', stage, reason });
const stateDenied = row('worker_state', 'denied');
beforeEach(() => {
  clock = base; doLag = 0; vi.clearAllMocks();
  vi.spyOn(Date, 'now').mockImplementation(() => clock);
  network = vi.fn(() => { throw Error('FORBIDDEN EXTERNAL FETCH'); }); vi.stubGlobal('fetch', network);
  logs = vi.spyOn(console, 'log').mockImplementation(() => {});
  key = fixtureKey(); storage = new Storage();
  storage.record = { v: VERSION, publicKey: key.publicKey, counter: 0, expiresAt: base + RETENTION_MS };
  env = { COACH_AUTH_MODE: 'app-attest-storekit-v1', CLIENT_SHARED_SECRET: TEST_GATE,
    APP_ATTEST_APP_PREFIX: APP_PREFIX, APP_STORE_APP_ID: '1', APP_STORE_KEY_ID: APP_PREFIX,
    APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000', APP_STORE_PRIVATE_KEY: 'PRIVATE-KEY-SENTINEL',
    COACH_AUTH_STATE: { idFromName: () => 'local-object', get: () => ({ fetch: async (url, options) => {
      const input = JSON.parse(options.body), old = clock;
      if (input.operation === 'reply') clock -= doLag;
      try { return await object.fetch(new Request(url, options)); } finally { clock = old; }
    } }) } };
  // @ts-expect-error Existing Node double; no platform/storage semantics are asserted by this scout.
  object = new CoachAuthenticationState({ storage }, env);
  presented = { bundleId: BUNDLE, environment: 'Production', type: 'Auto-Renewable Subscription',
    productId: 'com.reptoday.app.premium.monthly', transactionId: '1234', originalTransactionId: '1230',
    purchaseDate: base - 1000, signedDate: base - 500, expiresDate: base + 100_000 };
  current = { ...presented };
  statuses = { bundleId: BUNDLE, environment: 'Production', appAppleId: 1,
    data: [{ lastTransactions: [{ originalTransactionId: '1230', status: 1, signedTransactionInfo: 'current.fixture.proof' }] }] };
  verify.mockImplementation(async proof => proof === TEST_JWS ? presented : current);
  lookup.mockImplementation(async () => statuses);
});
afterEach(() => { expect(network).not.toHaveBeenCalled(); vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.useRealTimers(); });
const call = (body, proof) => handleRuntimeCoach(new Request(ORIGIN, { method: 'POST', body,
  headers: proof ? { 'X-RepToday-Coach-Auth': JSON.stringify(proof) } : {} }), env);
const challenge = async () => {
  const result = await call(JSON.stringify({ operation: 'challenge', kind: 'assert', keyId: key.keyId }), null);
  expect(result.status).toBe(200); return (await result.json()).challenge;
};
const proof = (token, counter = 1) => ({ operation: 'reply', keyId: key.keyId, challenge: token, transactionJws: TEST_JWS,
  assertion: signedAssertion(key, assertionPayload('reply', key.keyId, token, hash('{}'), hash(TEST_JWS)), counter).toString('base64') });
const cases = [
  { name: 'accepted no-model control', status: 400, error: 'invalid_context', writes: 2, counter: 1 },
  { name: 'missing proof', stage: 'worker_envelope', reason: 'missing_proof' },
  { name: 'extra proof field', stage: 'worker_envelope', reason: 'proof_envelope' },
  { name: 'invalid assertion encoding', stage: 'worker_envelope', reason: 'assertion_encoding' },
  { name: 'worker future token', stage: 'worker_token', reason: 'token_future' },
  { name: 'DO future token', stage: 'do_token_entry', reason: 'token_future' },
  { name: 'DO transaction future token', stage: 'do_token_transaction', reason: 'token_future' },
  { name: 'replaced nonce', stage: 'do_state', reason: 'pending_challenge', writes: 2 },
  { name: 'expired nonce', stage: 'do_state', reason: 'pending_challenge' },
  { name: 'malformed assertion', stage: 'do_assertion', reason: 'assertion_cbor' },
  { name: 'extended assertion', stage: 'do_assertion', reason: 'assertion_shape' },
  { name: 'counter not increasing', stage: 'do_assertion', reason: 'assertion_counter' },
  { name: 'altered request bytes', stage: 'do_assertion', reason: 'assertion_signature' },
  { name: 'status identity', stage: 'worker_premium', reason: 'status_identity', writes: 2, counter: 1 },
  { name: 'inactive status', stage: 'worker_premium', reason: 'status_match', writes: 2, counter: 1 },
  { name: 'expired presented transaction', stage: 'worker_premium', reason: 'premium_policy', writes: 2, counter: 1 },
  { name: 'missing record', error: 'key_unavailable' },
  { name: 'Apple API exception', status: 503, error: 'auth_unavailable', writes: 2, counter: 1 },
];
describe('final diagnostic labels preserve real local Worker/DO/crypto outcomes', () => {
  for (const flag of [undefined, '1', '0', 'true', true, 1]) it.each(cases)(`flag=${flag}: $name`, async c => {
    const enabled = flag === '1'; env.COACH_FINAL_AUTH_DIAGNOSTICS = flag;
    const token = await challenge(); let p = proof(token), body = '{}';
    switch (c.name) {
      case 'missing proof': p = null; break;
      case 'extra proof field': p = Object.assign(p, { privateText: 'PRIVATE-PROMPT-SENTINEL' }); break;
      case 'invalid assertion encoding': p.assertion = '!'; break;
      case 'worker future token': clock--; break;
      case 'DO future token': doLag = 1; break;
      case 'DO transaction future token': storage.lag = 1; break;
      case 'replaced nonce': await challenge(); break;
      case 'expired nonce': storage.record.pendingExpiresAt = base; break;
      case 'malformed assertion': p.assertion = Buffer.from('PRIVATE-CBOR-SENTINEL').toString('base64'); break;
      case 'extended assertion': p.assertion = signedAssertion(key,
        assertionPayload('reply', key.keyId, token, hash(body), hash(TEST_JWS)), 1, APP_PREFIX,
        { flags: 0x80, extensions: cbor.encode({ synthetic: true }) }).toString('base64'); break;
      case 'counter not increasing': p = proof(token, 0); break;
      case 'altered request bytes': body = '{ }'; break;
      case 'status identity': statuses.appAppleId = undefined; break;
      case 'inactive status': statuses.data[0].lastTransactions[0].status = 2; break;
      case 'expired presented transaction': presented.expiresDate = base; break;
      case 'missing record': storage.record = undefined; break;
      case 'Apple API exception': lookup.mockRejectedValueOnce(Error('PRIVATE-API-EXCEPTION')); break;
    }
    const before = structuredClone(storage.record);
    const response = await call(body, p);
    expect(response.status).toBe(c.status ?? 401); expect(await response.json()).toEqual({ error: c.error ?? 'unauthorized' });
    expect(response.headers.get('Cache-Control')).toBe(c.status === 400 ? null : 'no-store');
    expect(storage.writes).toBe(c.writes ?? 1);
    expect(storage.record?.counter ?? 0).toBe(c.counter ?? 0);
    const expected = enabled && c.reason ? [row(c.stage, c.reason), ...(c.stage.startsWith('do_') ? [stateDenied] : [])] : [];
    expect(logs.mock.calls.map(([line]) => JSON.parse(line))).toEqual(expected);
    const emitted = JSON.stringify(logs.mock.calls);
    for (const sentinel of [key.keyId, key.publicKey, TEST_GATE, TEST_JWS, token, 'PRIVATE-PROMPT-SENTINEL',
      'PRIVATE-CBOR-SENTINEL', 'PRIVATE-KEY-SENTINEL', 'PRIVATE-API-EXCEPTION']) expect(emitted).not.toContain(sentinel);
    if (!c.counter) expect(storage.record).toEqual(before);
    if (!c.counter) expect(lookup).not.toHaveBeenCalled();
  });
  it('one-variable counterfactual: byte-identical signed body restores admission on same pending nonce', async () => {
    env.COACH_FINAL_AUTH_DIAGNOSTICS = '1'; const p = proof(await challenge());
    expect((await call('{ }', p)).status).toBe(401);
    expect(logs.mock.calls.map(([l]) => JSON.parse(l))).toEqual([row('do_assertion', 'assertion_signature'), stateDenied]);
    expect((await call('{}', p)).status).toBe(400); expect(storage.record.counter).toBe(1);
  });
  it('challenge-only flag cannot observe the final rejection; final flag leaves challenges silent', async () => {
    env.COACH_AUTH_GUARD_DIAGNOSTICS = '1'; const p = proof(await challenge());
    await call('{ }', p); expect(logs).not.toHaveBeenCalled();
    delete env.COACH_AUTH_GUARD_DIAGNOSTICS; env.COACH_FINAL_AUTH_DIAGNOSTICS = '1';
    object.env = { ...env, APP_ATTEST_APP_PREFIX: 'bad' };
    const response = await call(JSON.stringify({ operation: 'challenge', kind: 'assert', keyId: key.keyId }), null);
    expect(response.status).toBe(401); expect(logs).not.toHaveBeenCalled();
  });
  it('logger/callback exceptions cannot alter denial', async () => {
    env.COACH_FINAL_AUTH_DIAGNOSTICS = '1'; const p = proof(await challenge());
    logs.mockImplementation(() => { throw Error('PRIVATE-LOGGER-FAILURE'); });
    expect((await call('{ }', p)).status).toBe(401);
    expect(() => assertKey(Buffer.from('bad'), '', 0, Buffer.alloc(0), APP_PREFIX, () => { throw Error('PRIVATE'); })).toThrow();
    statuses.appAppleId = undefined;
    await expect(premiumEntitlement(TEST_JWS, env, () => base, () => { throw Error('PRIVATE'); }))
      .rejects.toMatchObject({ code: 'unauthorized' });
  });
  it('recognized deletion remains silent and malformed proof gets only a fixed envelope label', async () => {
    env.COACH_FINAL_AUTH_DIAGNOSTICS = '1';
    const p = { ...proof(await challenge()), operation: 'delete' };
    expect((await call('{}', p)).status).toBe(401); expect(logs).not.toHaveBeenCalled();
    const response = await handleRuntimeCoach(new Request(ORIGIN, { method: 'POST', body: '{}',
      headers: { 'X-RepToday-Coach-Auth': 'PRIVATE-MALFORMED-PROOF' } }), env);
    expect(response.status).toBe(401);
    expect(logs.mock.calls).toEqual([[JSON.stringify(row('worker_envelope', 'proof_envelope'))]]);
  });
  it('emitter only accepts exact opt-in and fixed stage/reason pairs, discards extra input', () => {
    for (const flag of [undefined, false, true, 0, 1, '0', 'true'])
      emitFinalAuthDiagnostic({ COACH_FINAL_AUTH_DIAGNOSTICS: flag }, 'do_assertion', 'assertion_shape');
    const enabled = { COACH_FINAL_AUTH_DIAGNOSTICS: '1' };
    emitFinalAuthDiagnostic(enabled, 'PRIVATE-STAGE', 'assertion_shape');
    emitFinalAuthDiagnostic(enabled, '__proto__', 'PRIVATE');
    emitFinalAuthDiagnostic(enabled, 'worker_envelope', 'assertion_signature');
    emitFinalAuthDiagnostic(enabled, 'do_assertion', 'PRIVATE-REASON');
    expect(logs).not.toHaveBeenCalled();
    // @ts-expect-error Deliberate surplus argument: it must never reach output.
    emitFinalAuthDiagnostic(enabled, 'do_assertion', 'assertion_shape', { secret: 'PRIVATE' });
    expect(logs.mock.calls).toEqual([[JSON.stringify(row('do_assertion', 'assertion_shape'))]]);
  });
});

describe('diagnostic disable and in-flight ownership', () => {
  it('enable then disable emits no cached diagnostic on the next denial', async () => {
    const p = proof(await challenge());
    env.COACH_FINAL_AUTH_DIAGNOSTICS = '1';
    expect((await call('{ }', p)).status).toBe(401);
    logs.mockClear(); delete env.COACH_FINAL_AUTH_DIAGNOSTICS;
    expect((await call('{ }', p)).status).toBe(401);
    expect(logs).not.toHaveBeenCalled(); expect(storage.record.counter).toBe(0);
  });
  it('disabling while the DO awaits storage silences both catches, preserving nonce and counter', async () => {
    const p = proof(await challenge()), before = structuredClone(storage.record);
    env.COACH_FINAL_AUTH_DIAGNOSTICS = '1';
    let release = value => {}, entered = () => {};
    const pending = new Promise(resolve => { entered = () => resolve(undefined); });
    storage.get = () => { entered(); return new Promise(resolve => { release = () => resolve(structuredClone(storage.record)); }); };
    const response = call('{ }', p);
    await pending; env.COACH_FINAL_AUTH_DIAGNOSTICS = '0'; release(undefined);
    expect((await response).status).toBe(401);
    expect(storage.record).toEqual(before); expect(logs).not.toHaveBeenCalled();
  });
  it('disabling during Premium verification preserves the consumed counter and public denial', async () => {
    const p = proof(await challenge());
    env.COACH_FINAL_AUTH_DIAGNOSTICS = '1';
    let release = value => {}, entered = () => {};
    const pending = new Promise(resolve => { entered = () => resolve(undefined); });
    lookup.mockImplementationOnce(() => { entered(); return new Promise(resolve => { release = resolve; }); });
    const response = call('{}', p);
    await pending; delete env.COACH_FINAL_AUTH_DIAGNOSTICS;
    release({ ...statuses, appAppleId: undefined });
    expect((await response).status).toBe(401);
    expect(storage.record.counter).toBe(1); expect(logs).not.toHaveBeenCalled();
  });
  it('an authorization deadline stays silent even when a late Premium callback denies', async () => {
    const p = proof(await challenge()); env.COACH_FINAL_AUTH_DIAGNOSTICS = '1';
    vi.useFakeTimers();
    let rejectLate = () => {}, entered = () => {};
    const pending = new Promise(resolve => { entered = () => resolve(undefined); });
    const response = handleRuntimeCoach(new Request(ORIGIN, { method: 'POST', body: '{}',
      headers: { 'X-RepToday-Coach-Auth': JSON.stringify(p) } }), env, {
      state: async () => ({ authorized: true }),
      premium: (_jws, _env, _now, note) => { entered(); return new Promise((_, reject) => {
        rejectLate = () => { note('premium_policy'); reject(new CoachAuthFailure()); };
      }); },
    });
    await pending; await vi.advanceTimersByTimeAsync(20_001);
    expect((await response).status).toBe(503);
    rejectLate(); await Promise.resolve(); expect(logs).not.toHaveBeenCalled();
  });
  it('readiness probes reach Worker and DO without stored writes or Apple/model calls', async () => {
    // Same public request shapes as the portable operator's coverage probes.
    const keyId = Buffer.alloc(32).toString('base64');
    const c = await call(JSON.stringify({ operation: 'challenge', kind: 'enroll', keyId }), null);
    const { challenge: token } = await c.json(); expect(c.status).toBe(200);
    env.COACH_FINAL_AUTH_DIAGNOSTICS = '1';
    const denied = await call(JSON.stringify({ operation: 'enroll', keyId, challenge: token, attestation: 'AA==' }), null);
    expect(denied.status).toBe(401); expect(await denied.json()).toEqual({ error: 'unauthorized' });
    expect(storage.writes).toBe(0); expect(lookup).not.toHaveBeenCalled(); expect(verify).not.toHaveBeenCalled();
    expect(logs).not.toHaveBeenCalled();
  });
});

// Staging-only 503 step labels: every `503 auth_unavailable` names the step it failed at, from a
// closed vocabulary, and only on a staging Worker with COACH_STAGING_LABELS=1. Synthetic keys and
// Apple workflow doubles only; no network.
import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest';
import { handleRuntimeCoach } from '../src/coach-auth-worker.js';
import legacyWorker from '../src/worker.js';
import { CoachAuthenticationState, RETENTION_MS } from '../src/coach-auth-state.js';
import { UNAVAILABLE_STEPS, unavailableLabel, allDiagnosticLabels } from '../src/coach-auth-diagnostics.js';
import { CoachAuthFailure, VERSION, ORIGIN, BUNDLE, hash, assertionPayload, premiumEntitlement } from '../src/coach-auth-crypto.js';
import { fixtureKey, signedAssertion, APP_PREFIX, TEST_GATE, TEST_JWS } from './auth-fixtures.js';
const { verify, lookup } = vi.hoisted(() => ({ verify: vi.fn(), lookup: vi.fn() }));
vi.mock('@apple/app-store-server-library', () => ({
  Environment: { PRODUCTION: 'Production', SANDBOX: 'Sandbox' },
  VerificationException: class extends Error {}, VerificationStatus: { INVALID_ENVIRONMENT: 4 },
  SignedDataVerifier: class { verifyAndDecodeTransaction(jws) { return verify(jws); } },
  AppStoreServerAPIClient: class { getAllSubscriptionStatuses(id) { return lookup(id); } },
}));

const base = 1_800_000_000_000;
const STAGING = 'https://reptoday-coach-staging.fixture-account.workers.dev/coach';
const HEADER = 'X-RepToday-Coach-Diagnostic';
const UNAVAILABLE_BODY = '{"error":"auth_unavailable"}';
// Shaped like what a real failure could carry (a signed proof, a key, Apple diagnostics); must never leave the Worker.
const SENTINEL = 'PRIVATE-SENTINEL eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMTIzNCJ9.c2ln -----BEGIN PRIVATE KEY----- 4040001';
const leak = () => Object.assign(new Error(SENTINEL), { code: SENTINEL, step: 'handler', label: SENTINEL });
class Storage {
  record; fail = false;
  get = async () => { if (this.fail) throw leak(); return structuredClone(this.record); };
  put = async (_, value) => { this.record = structuredClone(value); };
  setAlarm = async () => {};
  transaction = async action => {
    const old = structuredClone(this.record);
    try { return await action(this); } catch (e) { this.record = old; throw e; }
  };
}
let clock, key, storage, env, object, presented, statuses, stateFetch;
function build(extra = {}) {
  env = { COACH_AUTH_MODE: 'app-attest-storekit-v1', CLIENT_SHARED_SECRET: TEST_GATE,
    APP_ATTEST_APP_PREFIX: APP_PREFIX, APP_STORE_APP_ID: '1', APP_STORE_KEY_ID: APP_PREFIX,
    APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000', APP_STORE_PRIVATE_KEY: 'PRIVATE-KEY-SENTINEL', ...extra,
    COACH_AUTH_STATE: { idFromName: () => 'local-object', get: () => ({ fetch: (url, options) => stateFetch(url, options) }) } };
  // @ts-expect-error Partial Durable Object state double; workerd covers platform semantics.
  object = new CoachAuthenticationState({ storage }, env);
}
const staging = () => build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: '1' });
function reset(extra = {}) {
  vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.clearAllMocks();
  clock = base;
  vi.spyOn(Date, 'now').mockImplementation(() => clock);
  vi.stubGlobal('fetch', vi.fn(() => { throw Error('FORBIDDEN EXTERNAL FETCH'); }));
  vi.spyOn(console, 'log').mockImplementation(() => {});
  key = fixtureKey(); storage = new Storage();
  storage.record = { v: VERSION, publicKey: key.publicKey, counter: 0, expiresAt: base + RETENTION_MS };
  presented = { bundleId: BUNDLE, environment: 'Production', type: 'Auto-Renewable Subscription',
    productId: 'com.reptoday.app.premium.monthly', transactionId: '1234', originalTransactionId: '1230',
    purchaseDate: base - 1000, signedDate: base - 500, expiresDate: base + 100_000 };
  statuses = { bundleId: BUNDLE, environment: 'Production', appAppleId: 1,
    data: [{ lastTransactions: [{ originalTransactionId: '1230', status: 1, signedTransactionInfo: 'current.fixture.proof' }] }] };
  verify.mockImplementation(async () => presented);
  lookup.mockImplementation(async () => statuses);
  stateFetch = (url, options) => object.fetch(new Request(url, options));
  build(extra);
}
beforeEach(() => reset());
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

const post = (url, body, proof, deps) => handleRuntimeCoach(new Request(url, { method: 'POST', body,
  headers: proof ? { 'X-RepToday-Coach-Auth': JSON.stringify(proof) } : {} }), env, deps);
const assertChallenge = url => post(url, JSON.stringify({ operation: 'challenge', kind: 'assert', keyId: key.keyId }));
const challenge = async url => {
  const result = await assertChallenge(url);
  expect(result.status).toBe(200); return (await result.json()).challenge;
};
const proof = (token, counter = 1, body = '{}') => ({ operation: 'reply', keyId: key.keyId, challenge: token, transactionJws: TEST_JWS,
  assertion: signedAssertion(key, assertionPayload('reply', key.keyId, token, hash(body), hash(TEST_JWS)), counter).toString('base64') });
const reply = async (url, deps) => post(url, '{}', proof(await challenge(url)), deps);
const never = () => new Promise(() => {});

// Each case arranges one real failure through the Worker, the Durable Object or the Premium check.
const cases = [
  { name: 'a required binding is missing', step: 'config', run: async url => { env.APP_STORE_KEY_ID = 'bad'; return post(url, '{}'); } },
  { name: 'the request body stream fails', step: 'request',
    // Node needs `duplex` for a stream body; the Workers RequestInit type does not declare it.
    run: async url => handleRuntimeCoach(new Request(url, /** @type {any} */ ({ method: 'POST', duplex: 'half',
      body: new ReadableStream({ pull(controller) { controller.error(leak()); } }) })), env) },
  { name: 'the Durable Object fails internally on a challenge', step: 'state',
    run: async url => { storage.fail = true; return assertChallenge(url); } },
  { name: 'the Durable Object fails internally on the reply', step: 'state',
    run: async url => { const p = proof(await challenge(url)); storage.fail = true; return post(url, '{}', p); } },
  { name: 'the Durable Object call rejects', step: 'state',
    run: async url => { const p = proof(await challenge(url)); stateFetch = async () => { throw leak(); }; return post(url, '{}', p); } },
  { name: 'the Durable Object answers non-JSON', step: 'state',
    run: async url => { const p = proof(await challenge(url)); stateFetch = async () => new Response(SENTINEL, { status: 200 }); return post(url, '{}', p); } },
  { name: 'enrollment state fails', step: 'state',
    run: async url => {
      const enroll = await post(url, JSON.stringify({ operation: 'challenge', kind: 'enroll', keyId: key.keyId }));
      stateFetch = async () => { throw leak(); };
      return post(url, JSON.stringify({ operation: 'enroll', keyId: key.keyId, challenge: (await enroll.json()).challenge, attestation: 'AA==' }));
    } },
  { name: 'Apple transaction verification throws', step: 'premium_verify',
    run: async url => { verify.mockImplementation(async () => { throw leak(); }); return reply(url); } },
  { name: 'the subscription status lookup throws', step: 'premium_status',
    run: async url => { lookup.mockImplementation(async () => { throw leak(); }); return reply(url); } },
  { name: 'the status response is malformed', step: 'premium_status',
    run: async url => { statuses.data = [null]; return reply(url); } },
  { name: 'the current transaction check throws', step: 'premium_current',
    run: async url => { verify.mockImplementationOnce(async () => presented).mockImplementation(async () => { throw leak(); }); return reply(url); } },
  { name: 'the deadline elapses during the state call', step: 'deadline',
    run: async url => { const p = proof(await challenge(url)); stateFetch = () => { clock += 20_000; return never(); }; return post(url, '{}', p); } },
  { name: 'the deadline elapses during the Premium check', step: 'deadline',
    run: async url => reply(url, { premium: () => { clock += 20_000; return never(); } }) },
  { name: 'the deadline has passed after the Premium check', step: 'deadline',
    run: async url => reply(url, { premium: async () => { clock += 20_000; } }) },
  { name: 'the Coach handler throws', step: 'handler',
    run: async url => { vi.spyOn(legacyWorker, 'fetch').mockImplementation(async () => { throw leak(); }); return reply(url); } },
  { name: 'the operator handler throws', step: 'handler',
    run: async url => {
      vi.spyOn(legacyWorker, 'fetch').mockImplementation(async () => { throw leak(); });
      return handleRuntimeCoach(new Request(url, { method: 'POST', body: JSON.stringify({ message: 'fixture' }),
        headers: { Authorization: 'Bearer wrong-fixture' } }), env);
    } },
];
const headerNames = response => { const names = []; response.headers.forEach((_, name) => names.push(name)); return names.sort(); };
const noLeak = async response => {
  const text = await response.clone().text();
  expect(text).not.toContain('PRIVATE'); expect(text).not.toContain('eyJ');
  response.headers.forEach(value => { expect(value).not.toContain('PRIVATE'); expect(value).not.toContain('eyJ'); });
};

it('every vocabulary value has at least one real path', () => {
  expect([...new Set(cases.map(c => c.step))].sort()).toEqual([...UNAVAILABLE_STEPS].sort());
});

describe('a staging Worker names the step of every 503 auth_unavailable', () => {
  beforeEach(staging);
  it.each(cases)('$name -> step $step', async c => {
    const response = await c.run(STAGING);
    expect(response.status).toBe(503);
    expect(await response.clone().text()).toBe(UNAVAILABLE_BODY);
    expect(response.headers.get(HEADER)).toBe(`worker_unavailable/${c.step}`);
    expect(headerNames(response)).toEqual(['cache-control', 'content-type', HEADER.toLowerCase()]);
    await noLeak(response);
  });
});

describe('production 503 responses are byte-identical without the staging bindings', () => {
  it.each(cases)('$name: no label header, exact body', async c => {
    const response = await c.run(ORIGIN);
    expect(response.status).toBe(503);
    expect(await response.clone().text()).toBe(UNAVAILABLE_BODY);
    expect(headerNames(response)).toEqual(['cache-control', 'content-type']);
    await noLeak(response);
  });
  it.each(['true', '0', '', 1, true])('a staging Worker with COACH_STAGING_LABELS=%j adds no header', async flag => {
    for (const c of cases) {
      reset({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: flag });
      const response = await c.run(STAGING);
      expect(response.status, c.name).toBe(503);
      expect(await response.text(), c.name).toBe(UNAVAILABLE_BODY);
      expect(headerNames(response), c.name).toEqual(['cache-control', 'content-type']);
    }
  });
});

describe('the 503 label comes only from the closed vocabulary', () => {
  beforeEach(staging);
  it('a foreign exception carrying step/code/label fields is never read', async () => {
    // The thrown object claims step 'handler'; the Worker reports the step it was actually in.
    const response = await reply(STAGING, { premium: async () => { throw leak(); } });
    expect(response.headers.get(HEADER)).toBe('worker_unavailable/premium_verify');
    await noLeak(response);
  });
  it.each([SENTINEL, 'constructor', '__proto__', '', 'worker_unavailable/state', 7])(
    'an out-of-vocabulary step %j adds no header', async value => {
      const response = await reply(STAGING, { premium: async () => { throw new CoachAuthFailure('auth_unavailable', /** @type {any} */ (value)); } });
      expect(response.status).toBe(503); expect(await response.text()).toBe(UNAVAILABLE_BODY);
      expect(response.headers.get(HEADER)).toBeNull();
    });
  it('the Premium check names its own step, including an invalid App Store binding', async () => {
    await expect(premiumEntitlement(TEST_JWS, { ...env, APP_STORE_KEY_ID: 'bad' })).rejects.toMatchObject({ code: 'auth_unavailable', step: 'config' });
    verify.mockImplementation(async () => { throw leak(); });
    const error = await premiumEntitlement(TEST_JWS, env).catch(e => e);
    expect(error).toBeInstanceOf(CoachAuthFailure);
    expect(error).toMatchObject({ code: 'auth_unavailable', step: 'premium_verify', message: 'Coach authentication failed' });
  });
  it('a Premium denial stays a 401 with its rejection label, not a step label', async () => {
    statuses.data[0].lastTransactions[0].status = 2;
    const response = await reply(STAGING);
    expect(response.status).toBe(401); expect(await response.text()).toBe('{"error":"unauthorized"}');
    expect(response.headers.get(HEADER)).toBe('worker_premium/status_match');
  });
  it('the vocabulary is closed and part of the client contract', () => {
    expect(UNAVAILABLE_STEPS).toEqual(['config', 'request', 'state', 'premium_verify', 'premium_status', 'premium_current', 'deadline', 'handler']);
    for (const value of [SENTINEL, 'constructor', 'toString', 'State', null, undefined, 1]) expect(unavailableLabel(value)).toBeNull();
    for (const step of UNAVAILABLE_STEPS) expect(allDiagnosticLabels()).toContain(`worker_unavailable/${step}`);
    expect(allDiagnosticLabels()).toContain('do_assertion/assertion_signature');
  });
});

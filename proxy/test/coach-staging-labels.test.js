// Staging-only response labels and origin. Synthetic keys and Apple workflow doubles only.
import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest';
import { handleRuntimeCoach } from '../src/coach-auth-worker.js';
import { CoachAuthenticationState, RETENTION_MS } from '../src/coach-auth-state.js';
import { diagnosticLabel, parseDiagnosticLabel, parseAssertionDigest } from '../src/coach-auth-diagnostics.js';
import { VERSION, ORIGIN, BUNDLE, CHALLENGE_CLOCK_SKEW_MS, hash, assertionPayload } from '../src/coach-auth-crypto.js';
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
class Storage {
  record; lag = 0;
  get = async () => { clock -= this.lag; return structuredClone(this.record); };
  put = async (_, value) => { this.record = structuredClone(value); };
  setAlarm = async () => {};
  transaction = async action => {
    const old = structuredClone(this.record);
    try { return await action(this); } catch (e) { this.record = old; throw e; }
  };
}
let clock, key, storage, env, object, doLag, presented, statuses;
function build(extra = {}) {
  env = { COACH_AUTH_MODE: 'app-attest-storekit-v1', CLIENT_SHARED_SECRET: TEST_GATE,
    APP_ATTEST_APP_PREFIX: APP_PREFIX, APP_STORE_APP_ID: '1', APP_STORE_KEY_ID: APP_PREFIX,
    APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000', APP_STORE_PRIVATE_KEY: 'PRIVATE-KEY-SENTINEL', ...extra,
    COACH_AUTH_STATE: { idFromName: () => 'local-object', get: () => ({ fetch: async (url, options) => {
      const old = clock; clock -= doLag;
      try { return await object.fetch(new Request(url, options)); } finally { clock = old; }
    } }) } };
  // @ts-expect-error Partial Durable Object state double; workerd covers platform semantics.
  object = new CoachAuthenticationState({ storage }, env);
}
beforeEach(() => {
  clock = base; doLag = 0; vi.clearAllMocks();
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
  build();
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

const post = (url, body, proof) => handleRuntimeCoach(new Request(url, { method: 'POST', body,
  headers: proof ? { 'X-RepToday-Coach-Auth': JSON.stringify(proof) } : {} }), env);
const operatorPost = url => handleRuntimeCoach(new Request(url, { method: 'POST', body: JSON.stringify({ message: 'fixture' }),
  headers: { Authorization: 'Bearer wrong-fixture' } }), env);
const challenge = async url => {
  const result = await post(url, JSON.stringify({ operation: 'challenge', kind: 'assert', keyId: key.keyId }));
  expect(result.status).toBe(200); return (await result.json()).challenge;
};
const proof = (token, counter = 1, body = '{}') => ({ operation: 'reply', keyId: key.keyId, challenge: token, transactionJws: TEST_JWS,
  assertion: signedAssertion(key, assertionPayload('reply', key.keyId, token, hash(body), hash(TEST_JWS)), counter).toString('base64') });
const enrollChallenge = async url => {
  const result = await post(url, JSON.stringify({ operation: 'challenge', kind: 'enroll', keyId: key.keyId }));
  expect(result.status).toBe(200); return (await result.json()).challenge;
};
const corrupt = token => {
  const [payload, mac] = token.split('.');
  return `${payload}.${mac[0] === 'A' ? 'B' : 'A'}${mac.slice(1)}`;
};

// Each case arranges one real rejection through the Worker, Durable Object and crypto paths.
const cases = [
  { name: 'operator authorization', label: 'worker_operator/authorization', run: operatorPost },
  { name: 'empty request body', label: 'worker_envelope/envelope',
    run: async url => handleRuntimeCoach(new Request(url, { method: 'POST' }), env) },
  { name: 'missing proof', label: 'worker_envelope/missing_proof', run: async url => post(url, '{}') },
  { name: 'malformed enrollment envelope', label: 'worker_envelope/enrollment_envelope',
    run: async url => post(url, JSON.stringify({ operation: 'enroll', keyId: key.keyId })) },
  { name: 'invalid enrollment token', label: 'worker_token/token_mac', run: async url => post(url, JSON.stringify({
    operation: 'enroll', keyId: key.keyId, challenge: corrupt(await enrollChallenge(url)), attestation: 'AA==',
  })) },
  { name: 'invalid enrollment attestation encoding', label: 'worker_envelope/attestation_encoding',
    run: async url => post(url, JSON.stringify({ operation: 'enroll', keyId: key.keyId,
      challenge: await enrollChallenge(url), attestation: 'AB==' })) },
  { name: 'invalid enrollment attestation', label: 'do_attestation/attestation_cbor',
    run: async url => post(url, JSON.stringify({ operation: 'enroll', keyId: key.keyId,
      challenge: await enrollChallenge(url), attestation: 'AA==' })) },
  { name: 'extra proof field', label: 'worker_envelope/proof_envelope',
    run: async url => post(url, '{}', { ...proof(await challenge(url)), extra: 'PRIVATE-SENTINEL' }) },
  { name: 'invalid delete token', label: 'worker_token/token_mac', run: async url => post(url, '{}', {
    ...proof(corrupt(await challenge(url))), operation: 'delete', transactionJws: '',
  }) },
  { name: 'invalid delete assertion encoding', label: 'worker_envelope/assertion_encoding',
    run: async url => post(url, '{}', { ...proof(await challenge(url)), operation: 'delete', transactionJws: '', assertion: 'AB==' }) },
  { name: 'invalid delete envelope', label: 'worker_envelope/delete_envelope',
    run: async url => post(url, '{ }', { ...proof(await challenge(url)), operation: 'delete', transactionJws: '' }) },
  { name: 'future token at the Worker', label: 'worker_token/token_future',
    run: async url => { const p = proof(await challenge(url)); clock -= CHALLENGE_CLOCK_SKEW_MS + 1; return post(url, '{}', p); } },
  { name: 'altered request body', label: 'do_assertion/assertion_signature',
    run: async url => post(url, '{ }', proof(await challenge(url))) },
  { name: 'replaced pending nonce', label: 'do_state/pending_challenge',
    run: async url => { const p = proof(await challenge(url)); await challenge(url); return post(url, '{}', p); } },
  { name: 'transaction clock reversal', label: 'do_token_transaction/token_future',
    run: async url => { const p = proof(await challenge(url)); storage.lag = CHALLENGE_CLOCK_SKEW_MS + 1; return post(url, '{}', p); } },
  { name: 'inactive subscription', label: 'worker_premium/status_match',
    run: async url => { statuses.data[0].lastTransactions[0].status = 2; return post(url, '{}', proof(await challenge(url))); } },
  { name: 'assert challenge behind the Durable Object clock', label: 'do_token_entry/token_future',
    run: async url => { doLag = CHALLENGE_CLOCK_SKEW_MS + 1; return post(url, JSON.stringify({ operation: 'challenge', kind: 'assert', keyId: key.keyId })); } },
];

describe('production responses are byte-identical without the staging bindings', () => {
  it.each(cases)('$name: no label header, exact body', async c => {
    const response = await c.run(ORIGIN);
    expect(response.status).toBe(401);
    expect(await response.text()).toBe('{"error":"unauthorized"}');
    const names = []; response.headers.forEach((_, name) => names.push(name));
    expect(names.sort()).toEqual(c.name === 'operator authorization' ? ['content-type'] : ['cache-control', 'content-type']);
  });
  it('the Durable Object never adds a label field and a workers.dev URL is not served', async () => {
    const direct = await object.fetch(new Request('https://coach-security.invalid/', { method: 'POST',
      body: JSON.stringify({ operation: 'challenge', keyId: key.keyId, challenge: 'x.y' }) }));
    expect(await direct.text()).toBe('{"error":"unauthorized"}');
    expect((await post(STAGING, '{}')).status).toBe(404);
  });
});

describe('a staging Worker labels each rejection with one closed stage/reason pair', () => {
  beforeEach(() => build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: '1' }));
  it.each(cases)('$name -> $label', async c => {
    const response = await c.run(STAGING);
    expect(response.status).toBe(401);
    expect(await response.text()).toBe('{"error":"unauthorized"}');
    expect(response.headers.get(HEADER)).toBe(c.label);
  });
  it('serves only its own workers.dev origin', async () => {
    expect((await post(ORIGIN, '{}')).status).toBe(404);
    expect((await post(STAGING, '{}')).status).toBe(401);
  });
  it('adds no label to success, key_unavailable or auth_unavailable', async () => {
    const accepted = await post(STAGING, '{}', proof(await challenge(STAGING)));
    expect(accepted.status).toBe(400); expect(accepted.headers.get(HEADER)).toBeNull();
    const coachBody = JSON.stringify({
      context: { phase: 'discipline', requestedMinutes: 20, chainPositions: [], recentPatterns: [],
        consistency: { currentScore: 63, direction: 'rising' } },
      message: 'Why did I get squats?', safetyIdentifier: 'coach-00000000-0000-4000-8000-000000000001',
    });
    const noModel = await post(STAGING, coachBody, proof(await challenge(STAGING), 2, coachBody));
    expect(noModel.status).toBe(500); expect(await noModel.json()).toEqual({ error: 'not_configured' });
    expect(noModel.headers.get(HEADER)).toBeNull();
    storage.record = undefined;
    const missing = await post(STAGING, JSON.stringify({ operation: 'challenge', kind: 'assert', keyId: key.keyId }));
    expect(await missing.json()).toEqual({ error: 'key_unavailable' }); expect(missing.headers.get(HEADER)).toBeNull();
    build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: '1', APP_STORE_KEY_ID: 'bad' });
    const unavailable = await post(STAGING, '{}');
    expect(unavailable.status).toBe(503); expect(unavailable.headers.get(HEADER)).toBeNull();
  });
  it('labels require the exact flag value', async () => {
    for (const flag of ['true', '0', 1, true]) {
      build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: flag });
      expect((await post(STAGING, '{}')).headers.get(HEADER)).toBeNull();
    }
  });
});

describe('staging origin and label vocabulary fail closed', () => {
  it.each(['https://evil.example/coach', 'https://reptoday-coach-staging.x.workers.dev/other',
    'http://reptoday-coach-staging.x.workers.dev/coach', 'https://reptoday-variety-language-proxy.x.workers.dev/coach', ''])(
    'an unexpected COACH_STAGING_ORIGIN %j serves nothing', async origin => {
      build({ COACH_STAGING_ORIGIN: origin, COACH_STAGING_LABELS: '1' });
      expect((await post(ORIGIN, '{}')).status).toBe(404);
      if (origin) expect((await post(origin, '{}')).status).toBe(404);
    });
  it('accepts only known stage/reason pairs', () => {
    expect(diagnosticLabel('do_assertion', 'assertion_signature')).toBe('do_assertion/assertion_signature');
    expect(diagnosticLabel('worker_envelope', 'envelope')).toBe('worker_envelope/envelope');
    for (const [stage, reason] of [['do_assertion', 'PRIVATE'], ['__proto__', 'constructor'], ['worker_premium', 'token_mac'], [1, 2]])
      expect(diagnosticLabel(stage, reason)).toBeNull();
    for (const label of ['do_state/pending_challenge/x', 'do_state', 'x'.repeat(100), null, 'constructor/toString'])
      expect(parseDiagnosticLabel(label)).toBeNull();
    expect(parseDiagnosticLabel('do_state/pending_challenge')).toBe('do_state/pending_challenge');
  });
  it('a Durable Object label outside the vocabulary never reaches the client', async () => {
    build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: '1' });
    env.COACH_AUTH_STATE = { idFromName: () => 'x', get: () => ({ fetch: async () =>
      new Response(JSON.stringify({ error: 'unauthorized', label: 'PRIVATE/SENTINEL' }), { status: 401 }) }) };
    const response = await post(STAGING, JSON.stringify({ operation: 'challenge', kind: 'assert', keyId: key.keyId }));
    expect(response.headers.get(HEADER)).toBe('worker_state/denied');
  });
});

describe('a staging assertion rejection also returns non-secret digests of what the server verified', () => {
  const DIGEST = 'X-RepToday-Coach-Assertion-Digest';
  const digestOf = (token, body) => `payload=${hash(assertionPayload('reply', key.keyId, token, hash(body), hash(TEST_JWS))).slice(0, 16)} ` +
    `body=${hash(body).slice(0, 16)} transaction=${hash(TEST_JWS).slice(0, 16)} challenge=${token.slice(0, 8)}`;
  it('names the reconstructed payload, received body and transaction hashes and the challenge prefix', async () => {
    build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: '1' });
    const token = await challenge(STAGING);
    const response = await post(STAGING, '{ }', proof(token));
    expect(response.status).toBe(401); expect(await response.text()).toBe('{"error":"unauthorized"}');
    expect(response.headers.get(HEADER)).toBe('do_assertion/assertion_signature');
    // The client signed '{}' but the server received '{ }': the body digest shows exactly that.
    expect(response.headers.get(DIGEST)).toBe(digestOf(token, '{ }'));
    expect(response.headers.get(DIGEST)).not.toContain(hash('{}').slice(0, 16));
  });
  it('is absent in production, on non-assertion rejections and on success', async () => {
    let token = await challenge(ORIGIN);
    expect((await post(ORIGIN, '{ }', proof(token))).headers.get(DIGEST)).toBeNull();
    build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: '1' });
    token = await challenge(STAGING);
    const replaced = proof(token); await challenge(STAGING);
    const pending = await post(STAGING, '{}', replaced);
    expect(pending.headers.get(HEADER)).toBe('do_state/pending_challenge'); expect(pending.headers.get(DIGEST)).toBeNull();
    const accepted = await post(STAGING, '{}', proof(await challenge(STAGING)));
    expect(accepted.status).toBe(400); expect(accepted.headers.get(DIGEST)).toBeNull();
  });
  it('the Durable Object reply stays within the Worker bound and a malformed digest never reaches the client', async () => {
    build({ COACH_STAGING_ORIGIN: STAGING, COACH_STAGING_LABELS: '1' });
    const token = await challenge(STAGING);
    const assertion = signedAssertion(key, assertionPayload('reply', key.keyId, token, hash('{}'), hash(TEST_JWS)), 1).toString('base64');
    const direct = await object.fetch(new Request('https://coach-security.invalid/', { method: 'POST', body: JSON.stringify({
      operation: 'reply', keyId: key.keyId, challenge: token, assertion, bodyHash: hash('{ }'), transactionHash: hash(TEST_JWS) }) }));
    const text = await direct.text();
    expect(Buffer.byteLength(text)).toBeLessThanOrEqual(256);
    expect(JSON.parse(text).digest).toBe(digestOf(token, '{ }'));
    const forgedToken = await challenge(STAGING);
    env.COACH_AUTH_STATE = { idFromName: () => 'x', get: () => ({ fetch: async () => new Response(JSON.stringify({
      error: 'unauthorized', label: 'do_assertion/assertion_signature', digest: 'payload=PRIVATE body=x' }), { status: 401 }) }) };
    const forged = await post(STAGING, '{}', proof(forgedToken));
    expect(forged.headers.get(HEADER)).toBe('do_assertion/assertion_signature'); expect(forged.headers.get(DIGEST)).toBeNull();
    for (const value of ['payload=0123456789abcdef body=0123456789abcdef transaction=0123456789abcdef challenge=eyJ2Ijoi',
      'payload=0123456789ABCDEF body=0123456789abcdef transaction=0123456789abcdef challenge=eyJ2Ijoi', null, 'x'])
      expect(parseAssertionDigest(value)).toBe(value === null || value === 'x' || value.includes('ABCDEF') ? null : value);
  });
});

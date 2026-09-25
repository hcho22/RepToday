import { afterEach, describe, expect, it, vi } from 'vitest';
import { createHmac } from 'node:crypto';
import { handleRuntimeCoach } from '../src/coach-auth-worker.js';
import { CoachAuthenticationState } from '../src/coach-auth-state.js';
import { emitAuthGuardDiagnostic } from '../src/coach-auth-diagnostics.js';
import { CoachAuthFailure, VERSION, ORIGIN, challengeToken, verifyChallenge } from '../src/coach-auth-crypto.js';

const base = 1_800_000_000_000;
const keyId = Buffer.alloc(32, 7).toString('base64');
const secret = '0'.repeat(64);
const goodRecord = () => ({ v: VERSION, publicKey: 'TEST-PUBLIC-KEY-SENTINEL', counter: 0, expiresAt: base + 100_000 });
const cases = [
  { name: 'healthy', status: 200, reads: 1, writes: 1 },
  { name: 'missing record', record: null, status: 401, error: 'key_unavailable', reads: 1 },
  { name: 'expired record', record: { ...goodRecord(), expiresAt: base }, status: 401, error: 'key_unavailable', reads: 1 },
  { name: 'old schema', record: { ...goodRecord(), v: 'old' }, status: 401, error: 'key_unavailable', reads: 1 },
  { name: 'tombstone', record: { tombstoneUntil: base + 100_000 }, status: 401, error: 'key_unavailable', reads: 1 },
  { name: 'future by 1ms', skew: -1, status: 401, error: 'unauthorized', stage: 'do_token_entry', reason: 'token_future', deltaMs: 1 },
  { name: 'clock equal', skew: 0, status: 200, reads: 1, writes: 1 },
  { name: 'clock ahead', skew: 1, status: 200, reads: 1, writes: 1 },
  { name: 'expired token', skew: 60_000, status: 401, error: 'unauthorized', stage: 'do_token_entry', reason: 'token_expired', deltaMs: -60_000 },
  { name: 'secret mismatch', doSecret: '1'.repeat(64), status: 401, error: 'unauthorized', stage: 'do_token_entry', reason: 'token_mac' },
  { name: 'prefix invalid', prefix: '', status: 401, error: 'unauthorized', stage: 'do_preflight', reason: 'prefix_format' },
  { name: 'storage fails', storageError: true, status: 503, error: 'auth_unavailable' },
  { name: 'extra field', extra: { extra: 'PRIVATE-INPUT-SENTINEL' }, status: 401, error: 'unauthorized', stage: 'worker_envelope', reason: 'envelope' },
  { name: 'missing expiresAt remains accepted', record: { v: VERSION, publicKey: 'TEST-PUBLIC-KEY-SENTINEL', counter: 0 }, status: 200, reads: 1, writes: 1 },
  { name: 'transaction clock reversal', commitSkew: -1, status: 401, error: 'unauthorized', reads: 1, stage: 'do_token_transaction', reason: 'token_future', deltaMs: 1 },
];

async function exercise(testCase, enabled) {
  let now = base, reads = 0, writes = 0;
  let record = 'record' in testCase ? testCase.record : goodRecord();
  vi.spyOn(Date, 'now').mockImplementation(() => now);
  const storage = {
    get: async () => { reads++; if ('commitSkew' in testCase) now = base + testCase.commitSkew; return structuredClone(record); },
    put: async (_key, value) => { writes++; record = structuredClone(value); },
    transaction: async fn => { if (testCase.storageError) throw Error('PRIVATE-STORAGE-ERROR'); return fn(storage); },
  };
  const diagnosticEnv = enabled ? { COACH_AUTH_GUARD_DIAGNOSTICS: '1' } : {};
  // @ts-expect-error Partial storage double. The real workerd integration runs separately.
  const object = new CoachAuthenticationState({ storage }, { ...diagnosticEnv, CLIENT_SHARED_SECRET: testCase.doSecret ?? secret,
    APP_ATTEST_APP_PREFIX: testCase.prefix ?? 'FIXTURE001' });
  const env = { ...diagnosticEnv, COACH_AUTH_MODE: 'app-attest-storekit-v1', CLIENT_SHARED_SECRET: secret,
    APP_ATTEST_APP_PREFIX: 'FIXTURE001', APP_STORE_APP_ID: '1', APP_STORE_KEY_ID: 'FIXTURE001',
    APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000', APP_STORE_PRIVATE_KEY: 'PRIVATE-API-KEY-SENTINEL',
    COACH_AUTH_STATE: { idFromName: name => name, get: () => ({ fetch: async (url, init) => {
      now = base + (testCase.skew ?? 0); return object.fetch(new Request(url, init));
    } }) },
  };
  const response = await handleRuntimeCoach(new Request(ORIGIN, { method: 'POST', body: JSON.stringify({
    operation: 'challenge', kind: 'assert', keyId, ...testCase.extra,
  }) }), env);
  return { status: response.status, data: await response.json(), reads, writes };
}

afterEach(() => vi.restoreAllMocks());
describe('temporary auth diagnostics preserve public challenge behavior', () => {
  for (const enabled of [false, true]) {
    it.each(cases)(`flag ${enabled}: $name`, async testCase => {
      const logs = vi.spyOn(console, 'log').mockImplementation(() => {});
      const result = await exercise(testCase, enabled);
      expect(result.status).toBe(testCase.status);
      expect(result.reads).toBe(testCase.reads ?? 0);
      expect(result.writes).toBe(testCase.writes ?? 0);
      if (testCase.error) expect(result.data).toEqual({ error: testCase.error });
      else { expect(Object.keys(result.data)).toEqual(['challenge']); expect(typeof result.data.challenge).toBe('string'); }
      const expected = enabled && testCase.reason ? [{ event: 'coach_auth_guard', stage: testCase.stage, reason: testCase.reason,
        ...('deltaMs' in testCase ? { deltaMs: testCase.deltaMs } : {}) }] : [];
      if (expected.length && testCase.stage !== 'worker_envelope')
        expected.push({ event: 'coach_auth_guard', stage: 'worker_state', reason: 'denied' });
      expect(logs.mock.calls.map(([line]) => JSON.parse(line))).toEqual(expected);
      const emitted = JSON.stringify(logs.mock.calls);
      for (const sensitive of [keyId, secret, 'FIXTURE001', 'PRIVATE-INPUT-SENTINEL', 'TEST-PUBLIC-KEY-SENTINEL',
        'PRIVATE-STORAGE-ERROR', 'PRIVATE-API-KEY-SENTINEL']) expect(emitted).not.toContain(sensitive);
    });
  }
  it('logger rejects unknown labels and requires exact opt-in', () => {
    const logs = vi.spyOn(console, 'log').mockImplementation(() => {});
    for (const flag of [undefined, false, true, 1, 'true', '0'])
      emitAuthGuardDiagnostic({ COACH_AUTH_GUARD_DIAGNOSTICS: flag }, 'do_token_entry', 'token_future', 1);
    emitAuthGuardDiagnostic({ COACH_AUTH_GUARD_DIAGNOSTICS: '1' }, 'PRIVATE-STAGE', 'token_mac');
    emitAuthGuardDiagnostic({ COACH_AUTH_GUARD_DIAGNOSTICS: '1' }, 'do_token_entry', 'PRIVATE-REASON');
    expect(logs).not.toHaveBeenCalled();
  });
  it('logger never emits arbitrary payload fields or unbounded/non-temporal deltas', () => {
    const logs = vi.spyOn(console, 'log').mockImplementation(() => {});
    const env = { COACH_AUTH_GUARD_DIAGNOSTICS: '1' };
    for (const delta of [Infinity, NaN, 60_001, -60_001, 'PRIVATE-DELTA', 0.5])
      emitAuthGuardDiagnostic(env, 'do_token_entry', 'token_future', delta);
    emitAuthGuardDiagnostic(env, 'do_token_entry', 'token_mac', 123);
    for (const [line] of logs.mock.calls) expect(Object.keys(JSON.parse(line))).toEqual(['event', 'stage', 'reason']);
  });
  it('console failure does not replace the public unauthorized result', async () => {
    vi.spyOn(console, 'log').mockImplementation(() => { throw Error('PRIVATE-CONSOLE-FAILURE'); });
    const result = await exercise(cases.find(testCase => testCase.name === 'future by 1ms'), true);
    expect(result.status).toBe(401); expect(result.data).toEqual({ error: 'unauthorized' });
  });
});

const signClaims = claims => {
  const payload = Buffer.from(JSON.stringify(claims)).toString('base64url');
  return payload + '.' + createHmac('sha256', secret).update(VERSION + '.' + payload).digest('base64url');
};
describe('challenge diagnostic reason contains authenticated bounded metadata only', () => {
  const claims = { v: VERSION, k: keyId, n: '00000000-0000-4000-8000-000000000000', i: base, e: base + 60_000 };
  it.each([
    ['syntax', 'PRIVATE-TOKEN-SENTINEL', secret, base, 'token_syntax', undefined],
    ['MAC', signClaims(claims), '1'.repeat(64), base - 1, 'token_mac', undefined],
    ['claims', signClaims({ ...claims, extra: 'PRIVATE-CLAIM' }), secret, base - 1, 'token_claims', undefined],
    ['fractional time', signClaims({ ...claims, i: base + .5, e: base + 60_000.5 }), secret, base, 'token_claims', undefined],
    ['future clamped', signClaims(claims), secret, base - 100_000, 'token_future', 60_000],
    ['expired clamped', signClaims(claims), secret, base + 100_000, 'token_expired', -60_000],
  ])('%s', (_name, token, verificationSecret, now, reason, delta) => {
    const denied = vi.fn();
    expect(() => verifyChallenge(token, keyId, verificationSecret, now, denied)).toThrow(CoachAuthFailure);
    expect(denied.mock.calls).toEqual([[reason, delta]]);
  });
  it('successful verification emits nothing and callback failure cannot alter rejection', () => {
    const denied = vi.fn(); const token = challengeToken(keyId, secret, base);
    expect(verifyChallenge(token, keyId, secret, base, denied).k).toBe(keyId); expect(denied).not.toHaveBeenCalled();
    expect(() => verifyChallenge(token, keyId, secret, base - 1, () => { throw Error('PRIVATE-CALLBACK'); }))
      .toThrow(CoachAuthFailure);
  });
});

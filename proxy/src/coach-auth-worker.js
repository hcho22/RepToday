import { emitAuthGuardDiagnostic, emitFinalAuthDiagnostic, stagingLabelsEnabled, diagnosticLabel, parseDiagnosticLabel, parseAssertionDigest } from './coach-auth-diagnostics.js';
import { Buffer } from 'node:buffer';
import legacyWorker from './worker.js';
import { CoachAuthFailure, ORIGIN, VERSION, keyIDValid, appIDValid, issuerIDValid, hash, fromBase64, challengeToken, verifyChallenge, premiumEntitlement } from './coach-auth-crypto.js';
import { CoachAuthenticationState, readBounded } from './coach-auth-state.js';
export { CoachAuthenticationState };

const json = (data, status = 200, extra = {}) => new Response(JSON.stringify(data),
  { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra } });
// A separate staging Worker answers only at its own workers.dev URL; production has no such binding,
// and a present but unexpected value serves nothing.
const STAGING_ORIGIN = /^https:\/\/reptoday-coach-staging\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.workers\.dev\/coach$/;
const servedOrigin = env => env.COACH_STAGING_ORIGIN === undefined ? ORIGIN :
  typeof env.COACH_STAGING_ORIGIN === 'string' && STAGING_ORIGIN.test(env.COACH_STAGING_ORIGIN) ? env.COACH_STAGING_ORIGIN : null;
const exactKeys = (object, keys) => object && Object.keys(object).sort().join(',') === keys;
const labelUnauthorized = (response, env, stage, reason) => {
  const label = response.status === 401 && stagingLabelsEnabled(env) ? diagnosticLabel(stage, reason) : null;
  if (!label) return response;
  const headers = new Headers(response.headers);
  headers.set('X-RepToday-Coach-Diagnostic', label);
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
};

function ready(env) {
  return env.COACH_AUTH_MODE === 'app-attest-storekit-v1' && env.COACH_AUTH_STATE &&
    /^[0-9a-f]{64}$/.test(env.CLIENT_SHARED_SECRET ?? '') && /^[A-Z0-9]{10}$/.test(env.APP_ATTEST_APP_PREFIX ?? '') &&
    appIDValid(env.APP_STORE_APP_ID) && env.APP_STORE_PRIVATE_KEY &&
    /^[A-Z0-9]{10}$/.test(env.APP_STORE_KEY_ID ?? '') && issuerIDValid(env.APP_STORE_ISSUER_ID);
}
export async function authWithin(promise, milliseconds) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new CoachAuthFailure('auth_unavailable')), milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}

async function stateRequest(env, input) {
  const object = env.COACH_AUTH_STATE.get(env.COACH_AUTH_STATE.idFromName(VERSION + ':' + hash(input.keyId)));
  const result = await object.fetch('https://coach-security.invalid/', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input), signal: AbortSignal.timeout(10_000) });
  const bytes = await readBounded(result, 256);
  const data = JSON.parse(Buffer.from(bytes).toString('utf8'));
  // A staging Durable Object may add its inner label and assertion digest; both are validated before any use.
  if (!result.ok) throw Object.assign(new CoachAuthFailure(['unauthorized', 'key_unavailable'].includes(data.error) ? data.error : 'auth_unavailable'),
    typeof data.label === 'string' ? { label: data.label } : {}, typeof data.digest === 'string' ? { digest: data.digest } : {});
  return data;
}

// Dependencies are injectable only for local unit tests; the published fetch entry never passes them.
export async function handleRuntimeCoach(request, env, { state = stateRequest, premium = premiumEntitlement } = {}) {
  let challengeStage;
  const finalDiagnostic = { stage: '', reason: '' };
  const stagingDiagnostic = { stage: '', reason: '' };
  const noteFinal = (stage, reason) => { finalDiagnostic.stage = stage; finalDiagnostic.reason = reason; };
  const noteStaging = (stage, reason) => { stagingDiagnostic.stage = stage; stagingDiagnostic.reason = reason; };
  try {
    const deadline = Date.now() + 20_000;
    const authorize = promise => authWithin(promise, Math.max(1, deadline - Date.now()));
    if (request.url !== servedOrigin(env)) return json({ error: 'not_found' }, 404);
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
    if (!ready(env)) throw new CoachAuthFailure('auth_unavailable');
    // Retained operator-only administration/QA credential; never distributed to an iOS app.
    // The reviewed legacy gate performs its constant-time comparison before any provider call.
    if (request.headers.get('Authorization')?.startsWith('Bearer ')) {
      noteStaging('worker_operator', 'request_shape');
      const operatorBytes = await readBounded(request, 32 * 1024);
      // Reserve the exact empty-body admission exchange for device proof + fresh Premium.
      // An operator's body-validation error must never masquerade as those two gates passing.
      if (operatorBytes.toString('utf8') === '{}') throw new CoachAuthFailure();
      return labelUnauthorized(await legacyWorker.fetch(
        new Request(ORIGIN, { method: 'POST', headers: request.headers, body: operatorBytes }), env),
      env, 'worker_operator', 'authorization');
    }
    const auth = request.headers.get('X-RepToday-Coach-Auth');
    const bytes = await readBounded(request, 32 * 1024);
    if (!auth) {
      noteStaging('worker_envelope', 'missing_proof');
      let input; try { input = JSON.parse(bytes.toString('utf8')); } catch {
        noteStaging('worker_envelope', 'envelope'); throw new CoachAuthFailure();
      }
      if (input?.operation === 'challenge') {
        challengeStage = 'worker_envelope'; noteStaging('worker_envelope', 'envelope');
      }
      if (input?.operation === 'enroll') noteStaging('worker_envelope', 'enrollment_envelope');
      if (exactKeys(input, 'keyId,kind,operation') && input.operation === 'challenge' && ['enroll', 'assert'].includes(input.kind) && keyIDValid(input.keyId)) {
        const challenge = challengeToken(input.keyId, env.CLIENT_SHARED_SECRET, Date.now());
        if (input.kind === 'assert') {
          challengeStage = 'worker_state';
          noteStaging('worker_state', 'denied');
          await authorize(state(env, { operation: 'challenge', keyId: input.keyId, challenge }));
        }
        return json({ challenge }); // Unknown-key enrollment challenges create no stored record.
      }
      if (exactKeys(input, 'attestation,challenge,keyId,operation') && input.operation === 'enroll' && keyIDValid(input.keyId)) {
        verifyChallenge(input.challenge, input.keyId, env.CLIENT_SHARED_SECRET, Date.now(),
          reason => noteStaging('worker_token', reason));
        noteStaging('worker_envelope', 'attestation_encoding');
        fromBase64(input.attestation, 8192);
        noteStaging('worker_state', 'denied');
        await authorize(state(env, input)); return json({ enrolled: true });
      }
      if (!['challenge', 'enroll'].includes(input?.operation)) noteFinal('worker_envelope', 'missing_proof');
      throw new CoachAuthFailure();
    }
    noteFinal('worker_envelope', 'proof_envelope');
    noteStaging('worker_envelope', 'proof_envelope');
    if (auth.length > 20_000) throw new CoachAuthFailure();
    let proof; try { proof = JSON.parse(auth); } catch { throw new CoachAuthFailure(); }
    if (proof?.operation === 'delete') finalDiagnostic.stage = '';
    if (!exactKeys(proof, 'assertion,challenge,keyId,operation,transactionJws') || !keyIDValid(proof.keyId) ||
        !['reply', 'delete'].includes(proof.operation) || typeof proof.transactionJws !== 'string' || proof.transactionJws.length > 12_000) throw new CoachAuthFailure();
    verifyChallenge(proof.challenge, proof.keyId, env.CLIENT_SHARED_SECRET, Date.now(), reason => {
      noteStaging('worker_token', reason);
      if (proof.operation === 'reply') noteFinal('worker_token', reason);
    });
    if (proof.operation === 'reply') noteFinal('worker_envelope', 'assertion_encoding');
    noteStaging('worker_envelope', 'assertion_encoding');
    fromBase64(proof.assertion, 1024);
    if (proof.operation === 'delete') {
      noteStaging('worker_envelope', 'delete_envelope');
      if (bytes.length !== 2 || bytes.toString('utf8') !== '{}' || proof.transactionJws !== '') throw new CoachAuthFailure();
    }
    if (proof.operation === 'reply') noteFinal('worker_state', 'denied');
    noteStaging('worker_state', 'denied');
    const accepted = await authorize(state(env, { operation: proof.operation, keyId: proof.keyId, challenge: proof.challenge, assertion: proof.assertion,
      bodyHash: hash(bytes), transactionHash: hash(proof.transactionJws) }));
    if (proof.operation === 'reply') noteFinal('worker_state', 'not_authorized');
    noteStaging('worker_state', 'not_authorized');
    if (accepted.authorized !== true) throw new CoachAuthFailure();
    if (proof.operation === 'delete') return json({ deleted: true }); // Erasure needs key proof, not an active subscription.
    noteFinal('worker_premium', 'denied');
    noteStaging('worker_premium', 'denied');
    await authorize(premium(proof.transactionJws, env, () => Date.now(),
      reason => { noteFinal('worker_premium', reason); noteStaging('worker_premium', reason); })); // Same gates; fixed reason only on denial.
    if (Date.now() >= deadline) throw new CoachAuthFailure('auth_unavailable');
    const headers = new Headers(request.headers);
    headers.delete('X-RepToday-Coach-Auth'); headers.set('Authorization', 'Bearer ' + env.CLIENT_SHARED_SECRET);
    // The exact verified raw bytes are passed to the existing bounded Coach handler; auth proof
    // never reaches its context/prompt/OpenAI payload. No network request to another Worker.
    return labelUnauthorized(await legacyWorker.fetch(new Request(ORIGIN, { method: 'POST', headers, body: bytes }), env),
      env, 'worker_handler', 'authorization');
  } catch (error) {
    const code = error instanceof CoachAuthFailure ? error.code : 'auth_unavailable';
    if (challengeStage && code === 'unauthorized')
      emitAuthGuardDiagnostic(env, challengeStage, challengeStage === 'worker_envelope' ? 'envelope' : 'denied');
    if (finalDiagnostic.stage && code === 'unauthorized')
      emitFinalAuthDiagnostic(env, finalDiagnostic.stage, finalDiagnostic.reason);
    // Staging only: name the rejecting guard, preferring the Durable Object's inner label.
    const label = code === 'unauthorized' && stagingLabelsEnabled(env) ? parseDiagnosticLabel(error?.label) ??
      (stagingDiagnostic.stage ? diagnosticLabel(stagingDiagnostic.stage, stagingDiagnostic.reason) :
        finalDiagnostic.stage ? diagnosticLabel(finalDiagnostic.stage, finalDiagnostic.reason) :
        challengeStage ? diagnosticLabel(challengeStage, challengeStage === 'worker_envelope' ? 'envelope' : 'denied') :
          diagnosticLabel('worker_envelope', 'envelope')) : null;
    const digest = label?.startsWith('do_assertion/') ? parseAssertionDigest(error?.digest) : null;
    return json({ error: code }, code === 'payload_too_large' ? 413 : code === 'auth_unavailable' ? 503 : 401,
      label ? { 'X-RepToday-Coach-Diagnostic': label, ...(digest ? { 'X-RepToday-Coach-Assertion-Digest': digest } : {}) } : {});
  }
}

export default { fetch: (request, env) => handleRuntimeCoach(request, env) };

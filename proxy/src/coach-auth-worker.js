import { Buffer } from 'node:buffer';
import legacyWorker from './worker.js';
import { CoachAuthFailure, ORIGIN, VERSION, keyIDValid, appIDValid, issuerIDValid, hash, fromBase64, challengeToken, verifyChallenge, premiumEntitlement } from './coach-auth-crypto.js';
import { CoachAuthenticationState, readBounded } from './coach-auth-state.js';
export { CoachAuthenticationState };

const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const exactKeys = (object, keys) => object && Object.keys(object).sort().join(',') === keys;

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
  if (!result.ok) throw new CoachAuthFailure(['unauthorized', 'key_unavailable'].includes(data.error) ? data.error : 'auth_unavailable');
  return data;
}

// Dependencies are injectable only for local unit tests; the published fetch entry never passes them.
export async function handleRuntimeCoach(request, env, { state = stateRequest, premium = premiumEntitlement } = {}) {
  try {
    const deadline = Date.now() + 20_000;
    const authorize = promise => authWithin(promise, Math.max(1, deadline - Date.now()));
    if (request.url !== ORIGIN) return json({ error: 'not_found' }, 404);
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
    if (!ready(env)) throw new CoachAuthFailure('auth_unavailable');
    // Retained operator-only administration/QA credential; never distributed to an iOS app.
    // The reviewed legacy gate performs its constant-time comparison before any provider call.
    if (request.headers.get('Authorization')?.startsWith('Bearer ')) {
      const operatorBytes = await readBounded(request, 32 * 1024);
      // Reserve the exact empty-body admission exchange for device proof + fresh Premium.
      // An operator's body-validation error must never masquerade as those two gates passing.
      if (operatorBytes.toString('utf8') === '{}') throw new CoachAuthFailure();
      return legacyWorker.fetch(new Request(ORIGIN, { method: 'POST', headers: request.headers, body: operatorBytes }), env);
    }
    const auth = request.headers.get('X-RepToday-Coach-Auth');
    const bytes = await readBounded(request, 32 * 1024);
    if (!auth) {
      let input; try { input = JSON.parse(bytes.toString('utf8')); } catch { throw new CoachAuthFailure(); }
      if (exactKeys(input, 'keyId,kind,operation') && input.operation === 'challenge' && ['enroll', 'assert'].includes(input.kind) && keyIDValid(input.keyId)) {
        const challenge = challengeToken(input.keyId, env.CLIENT_SHARED_SECRET, Date.now());
        if (input.kind === 'assert') await authorize(state(env, { operation: 'challenge', keyId: input.keyId, challenge }));
        return json({ challenge }); // Unknown-key enrollment challenges create no stored record.
      }
      if (exactKeys(input, 'attestation,challenge,keyId,operation') && input.operation === 'enroll' && keyIDValid(input.keyId)) {
        verifyChallenge(input.challenge, input.keyId, env.CLIENT_SHARED_SECRET, Date.now());
        fromBase64(input.attestation, 8192);
        await authorize(state(env, input)); return json({ enrolled: true });
      }
      throw new CoachAuthFailure();
    }
    if (auth.length > 20_000) throw new CoachAuthFailure();
    let proof; try { proof = JSON.parse(auth); } catch { throw new CoachAuthFailure(); }
    if (!exactKeys(proof, 'assertion,challenge,keyId,operation,transactionJws') || !keyIDValid(proof.keyId) ||
        !['reply', 'delete'].includes(proof.operation) || typeof proof.transactionJws !== 'string' || proof.transactionJws.length > 12_000) throw new CoachAuthFailure();
    verifyChallenge(proof.challenge, proof.keyId, env.CLIENT_SHARED_SECRET, Date.now());
    fromBase64(proof.assertion, 1024);
    if (proof.operation === 'delete' && (bytes.length !== 2 || bytes.toString('utf8') !== '{}' || proof.transactionJws !== '')) throw new CoachAuthFailure();
    const accepted = await authorize(state(env, { operation: proof.operation, keyId: proof.keyId, challenge: proof.challenge, assertion: proof.assertion,
      bodyHash: hash(bytes), transactionHash: hash(proof.transactionJws) }));
    if (accepted.authorized !== true) throw new CoachAuthFailure();
    if (proof.operation === 'delete') return json({ deleted: true }); // Erasure needs key proof, not an active subscription.
    await authorize(premium(proof.transactionJws, env)); // Fail before provider on absent/revoked/expired/invalid/unavailable purchase.
    if (Date.now() >= deadline) throw new CoachAuthFailure('auth_unavailable');
    const headers = new Headers(request.headers);
    headers.delete('X-RepToday-Coach-Auth'); headers.set('Authorization', 'Bearer ' + env.CLIENT_SHARED_SECRET);
    // The exact verified raw bytes are passed to the existing bounded Coach handler; auth proof
    // never reaches its context/prompt/OpenAI payload. No network request to another Worker.
    return legacyWorker.fetch(new Request(ORIGIN, { method: 'POST', headers, body: bytes }), env);
  } catch (error) {
    const code = error instanceof CoachAuthFailure ? error.code : 'auth_unavailable';
    return json({ error: code }, code === 'payload_too_large' ? 413 : code === 'auth_unavailable' ? 503 : 401);
  }
}

export default { fetch: (request, env) => handleRuntimeCoach(request, env) };

import { Buffer } from 'node:buffer';
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import cbor from 'cbor';
import * as asn1js from 'asn1js';
import * as pkijs from 'pkijs';
import { verifyAttestation, verifyAssertion } from 'node-app-attest';
import { appAttest, storeG2, storeG3 } from './apple-trust-roots.js';
import { evaluateVerifiedPremiumEntitlement } from './runtime-entitlement-policy.js';

export const BUNDLE = 'com.reptoday.app';
export const ORIGIN = 'https://coach.reptoday.app/coach';
export const VERSION = 'reptoday-coach-auth-v1';
export class CoachAuthFailure extends Error {
  constructor(code = 'unauthorized') { super('Coach authentication failed'); this.code = code; }
}
export const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export const keyIDValid = value => typeof value === 'string' && /^[A-Za-z0-9+/]{43}=$/.test(value) &&
  Buffer.from(value, 'base64').toString('base64') === value;
export const appIDValid = value => typeof value === 'string' && /^[1-9][0-9]{0,15}$/.test(value) && Number.isSafeInteger(Number(value));
export const issuerIDValid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export function fromBase64(value, maximum) {
  if (typeof value !== 'string' || value.length > Math.ceil(maximum / 3) * 4 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) throw new CoachAuthFailure();
  const bytes = Buffer.from(value, 'base64');
  if (!bytes.length || bytes.length > maximum || bytes.toString('base64') !== value) throw new CoachAuthFailure();
  return bytes;
}

export function challengeToken(keyId, secret, nowMs, random = crypto.randomUUID()) {
  if (!keyIDValid(keyId) || typeof secret !== 'string' || secret.length < 32 || !Number.isFinite(nowMs)) throw new CoachAuthFailure('auth_unavailable');
  const payload = Buffer.from(JSON.stringify({ v: VERSION, k: keyId, n: random, i: nowMs, e: nowMs + 60_000 })).toString('base64url');
  const mac = createHmac('sha256', secret).update(VERSION + '.' + payload).digest('base64url');
  return `${payload}.${mac}`;
}
export function verifyChallenge(token, keyId, secret, nowMs, onDenied = (reason, deltaMs) => {}) {
  let reason = 'token_syntax';
  let deltaMs;
  try {
    if (typeof token !== 'string' || token.length > 512 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$/.test(token)) throw new CoachAuthFailure();
    const [payload, signature] = token.split('.');
    reason = 'token_mac';
    const expected = createHmac('sha256', secret).update(VERSION + '.' + payload).digest();
    const provided = Buffer.from(signature, 'base64url');
    if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) throw new CoachAuthFailure();
    reason = 'token_claims';
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (Object.keys(claims).sort().join(',') !== 'e,i,k,n,v' || claims.v !== VERSION || claims.k !== keyId ||
        typeof claims.n !== 'string' || !/^[0-9a-f-]{36}$/.test(claims.n) || !Number.isSafeInteger(claims.i) ||
        claims.e !== claims.i + 60_000) throw new CoachAuthFailure();
    // Emitted only after MAC and claim-shape checks, bounded and without identifiers.
    if (Number.isSafeInteger(nowMs) && Number.isSafeInteger(claims.i - nowMs))
      deltaMs = Math.max(-60_000, Math.min(60_000, claims.i - nowMs));
    if (claims.i > nowMs) { reason = 'token_future'; throw new CoachAuthFailure(); }
    if (nowMs >= claims.e) { reason = 'token_expired'; throw new CoachAuthFailure(); }
    return claims;
  } catch {
    try { onDenied(reason, deltaMs); } catch {} // Diagnostics cannot change authorization.
    throw new CoachAuthFailure();
  }
}

export function assertionPayload(operation, keyId, challenge, bodyHash, transactionHash) {
  return Buffer.from(JSON.stringify([VERSION, 'POST', ORIGIN, operation, keyId, challenge, bodyHash, transactionHash]), 'utf8');
}

function decodeObject(bytes, keys) {
  const objects = cbor.decodeAllSync(bytes, { max_depth: 8 });
  if (objects.length !== 1 || !objects[0] || Object.keys(objects[0]).sort().join(',') !== keys) throw new CoachAuthFailure();
  return objects[0];
}
function certificate(bytes) {
  const parsed = asn1js.fromBER(Uint8Array.from(bytes).buffer);
  if (parsed.offset !== bytes.length) throw new CoachAuthFailure();
  return new pkijs.Certificate({ schema: parsed.result });
}
const attestRootPEM = Buffer.from(appAttest, 'base64').toString('utf8');
const attestRootDER = Buffer.from(attestRootPEM.replace(/-----[^-]+-----|\s/g, ''), 'base64');

export async function attestKey(attestation, keyId, challenge, appPrefix, nowMs) {
  try {
    if (!/^[A-Z0-9]{10}$/.test(appPrefix) || !keyIDValid(keyId)) throw new CoachAuthFailure();
    const decoded = decodeObject(attestation, 'attStmt,authData,fmt');
    if (decoded.fmt !== 'apple-appattest' || !Buffer.isBuffer(decoded.authData) || decoded.authData.length > 512 ||
        !Array.isArray(decoded.attStmt?.x5c) || decoded.attStmt.x5c.length !== 2 ||
        decoded.attStmt.x5c.some(cert => !Buffer.isBuffer(cert) || cert.length > 4096)) throw new CoachAuthFailure();
    // The protocol library checks Apple signatures/nonces/identity. PKI.js additionally verifies
    // the full chain and current validity; the library alone omits validity-date checks.
    const chain = new pkijs.CertificateChainValidationEngine({
      trustedCerts: [certificate(attestRootDER)], certs: decoded.attStmt.x5c.map(certificate), checkDate: new Date(nowMs),
    });
    if (!(await chain.verify()).result) throw new CoachAuthFailure();
    const verified = verifyAttestation({ attestation, challenge, keyId, bundleIdentifier: BUNDLE,
      teamIdentifier: appPrefix, allowDevelopmentEnvironment: false });
    if (verified.keyId !== keyId || typeof verified.publicKey !== 'string' || Buffer.byteLength(verified.publicKey) > 1024) throw new CoachAuthFailure();
    return verified.publicKey;
  } catch { throw new CoachAuthFailure(); }
}

export function assertKey(assertion, publicKey, previousCounter, payload, appPrefix) {
  try {
    const decoded = decodeObject(assertion, 'authenticatorData,signature');
    if (!Buffer.isBuffer(decoded.authenticatorData) || decoded.authenticatorData.length !== 37 ||
        !Buffer.isBuffer(decoded.signature) || decoded.signature.length > 80) throw new CoachAuthFailure();
    // node-app-attest uses a signed 32-bit counter; fail closed at that ceiling, requiring fresh enrollment.
    const counter = decoded.authenticatorData.readUInt32BE(33);
    if (counter > 0x7fffffff || !Number.isInteger(previousCounter) || previousCounter < 0 || counter <= previousCounter) throw new CoachAuthFailure();
    const verified = verifyAssertion({ assertion, payload, publicKey, bundleIdentifier: BUNDLE, teamIdentifier: appPrefix, signCount: previousCounter });
    if (verified.signCount !== counter) throw new CoachAuthFailure();
    return counter;
  } catch { throw new CoachAuthFailure(); }
}

export async function premiumEntitlement(jws, env, now = () => Date.now()) {
  try {
    if (typeof jws !== 'string' || jws.length > 12_000 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(jws) ||
        !appIDValid(env.APP_STORE_APP_ID) || !env.APP_STORE_PRIVATE_KEY ||
        !/^[A-Z0-9]{10}$/.test(env.APP_STORE_KEY_ID ?? '') || !issuerIDValid(env.APP_STORE_ISSUER_ID)) throw new CoachAuthFailure('auth_unavailable');
    // Apple's OCSP dependency initializes randomness. Import inside the request context;
    // workerd correctly prohibits that operation at module initialization.
    const { AppStoreServerAPIClient, SignedDataVerifier, Environment, VerificationException, VerificationStatus } =
      await import('@apple/app-store-server-library');
    const roots = [Buffer.from(storeG2, 'base64'), Buffer.from(storeG3, 'base64')];
    let environment = Environment.PRODUCTION;
    let verifier = new SignedDataVerifier(roots, true, environment, BUNDLE, Number(env.APP_STORE_APP_ID));
    let presented;
    try {
      presented = await verifier.verifyAndDecodeTransaction(jws);
    } catch (error) {
      // Apple's verifier authenticates the signature and bundle before reporting INVALID_ENVIRONMENT.
      // Only that typed evidence permits selecting Sandbox; verifier/API/transport failures never do.
      if (!(error instanceof VerificationException) || error.status !== VerificationStatus.INVALID_ENVIRONMENT) throw error;
      environment = Environment.SANDBOX;
      // The installed official SDK requires appAppleId for Production and omission for Sandbox.
      verifier = new SignedDataVerifier(roots, true, environment, BUNDLE);
      presented = await verifier.verifyAndDecodeTransaction(jws);
    }
    if (presented.environment !== environment) throw new CoachAuthFailure();
    if (!/^[0-9]{1,32}$/.test(presented.originalTransactionId ?? '')) throw new CoachAuthFailure();
    const client = new AppStoreServerAPIClient(env.APP_STORE_PRIVATE_KEY, env.APP_STORE_KEY_ID, env.APP_STORE_ISSUER_ID, BUNDLE, environment);
    const statuses = await client.getAllSubscriptionStatuses(presented.originalTransactionId);
    const fetchedAt = now();
    if (statuses.bundleId !== BUNDLE || statuses.environment !== environment || Number(statuses.appAppleId) !== Number(env.APP_STORE_APP_ID) ||
        !Array.isArray(statuses.data) || statuses.data.length > 8) throw new CoachAuthFailure();
    const candidates = statuses.data.flatMap(group => group.lastTransactions ?? []);
    if (candidates.length > 32) throw new CoachAuthFailure();
    const matches = candidates.filter(row => row.originalTransactionId === presented.originalTransactionId);
    if (matches.length !== 1 || matches[0].status !== 1 || typeof matches[0].signedTransactionInfo !== 'string' || matches[0].signedTransactionInfo.length > 12_000) throw new CoachAuthFailure();
    const current = await verifier.verifyAndDecodeTransaction(matches[0].signedTransactionInfo);
    if (!evaluateVerifiedPremiumEntitlement({ ...presented }, { ...current }, matches[0].status, fetchedAt, now(), environment)) throw new CoachAuthFailure();
  } catch (error) {
    if (error instanceof CoachAuthFailure) throw error;
    // SDK exceptions may contain a signed proof/API diagnostics; never forward or log them.
    throw new CoachAuthFailure('auth_unavailable');
  }
}

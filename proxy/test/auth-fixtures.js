import { Buffer } from 'node:buffer';
import { readFileSync } from 'node:fs';
import { X509Certificate, createHash, generateKeyPairSync, sign } from 'node:crypto';
import cbor from 'cbor';
import { BUNDLE, hash } from '../src/coach-auth-crypto.js';

// Generated test keys are never Apple attestation or purchase proofs and cannot enroll in production.
export const APP_PREFIX = 'FIXTURE001';
export const TEST_GATE = '0'.repeat(64);
export function fixtureKey() {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const point = publicKey.export({ format: 'der', type: 'spki' }).subarray(-65);
  return { keyId: createHash('sha256').update(point).digest('base64'), privateKey,
    publicKey: publicKey.export({ format: 'pem', type: 'spki' }).toString() };
}
/**
 * @param {any} key
 * @param {Buffer} payload
 * @param {number} [counter]
 * @param {string} [prefix]
 * @param {{extensions?: Buffer, flags?: number}} [options]
 */
export function signedAssertion(key, payload, counter = 1, prefix = APP_PREFIX,
  {extensions = Buffer.alloc(0), flags = 0} = {}) {
  const authenticatorData = Buffer.alloc(37 + extensions.length);
  createHash('sha256').update(prefix + '.' + BUNDLE).digest().copy(authenticatorData);
  authenticatorData[32] = flags;
  authenticatorData.writeUInt32BE(counter, 33);
  extensions.copy(authenticatorData, 37);
  const clientHash = createHash('sha256').update(payload).digest();
  const nonce = createHash('sha256').update(Buffer.concat([authenticatorData, clientHash])).digest();
  return cbor.encode({ authenticatorData, signature: sign('sha256', nonce, key.privateKey) });
}
export const TEST_BODY = Buffer.from('{}');
export const TEST_JWS = 'fixture.purchase.proof';
export const TEST_BODY_HASH = hash(TEST_BODY);
export const TEST_TRANSACTION_HASH = hash(TEST_JWS);

/**
 * A real App Attest enrollment and first assertion from a genuine device (CoachStaging build,
 * staging-only key, 2026-09-29). It holds Apple certificates, the device key, the assertion and the
 * SHA-256 of the signed payload; no message, body or purchase content. The payload itself was not
 * captured, so it proves the signature primitive and the enrolled key rather than a whole request.
 */
export function deviceAssertionFixture() {
  const raw = JSON.parse(readFileSync(new URL('./fixtures/device-assertion-2026-09-29.json', import.meta.url), 'utf8'));
  const attestation = cbor.decodeFirstSync(Buffer.from(raw.attestation, 'base64'));
  const { authenticatorData, signature } = cbor.decodeFirstSync(Buffer.from(raw.assertion, 'base64'));
  const credentialLength = attestation.authData.readUInt16BE(53);
  const clientDataHash = Buffer.from(raw.clientDataHash, 'hex');
  const certificate = new X509Certificate(attestation.attStmt.x5c[0]);
  return {
    attestation, authenticatorData, signature, clientDataHash, certificate,
    credentialId: attestation.authData.subarray(55, 55 + credentialLength).toString('base64'),
    // node-app-attest's verifyAttestation returns exactly this, and the Durable Object stores it.
    publicKey: certificate.publicKey.export({ type: 'spki', format: 'pem' }).toString(),
    nonce: createHash('sha256').update(Buffer.concat([authenticatorData, clientDataHash])).digest(),
  };
}

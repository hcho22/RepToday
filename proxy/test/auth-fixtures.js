import { Buffer } from 'node:buffer';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
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
export function signedAssertion(key, payload, counter = 1, prefix = APP_PREFIX) {
  const authenticatorData = Buffer.alloc(37);
  createHash('sha256').update(prefix + '.' + BUNDLE).digest().copy(authenticatorData);
  authenticatorData.writeUInt32BE(counter, 33);
  const clientHash = createHash('sha256').update(payload).digest();
  const nonce = createHash('sha256').update(Buffer.concat([authenticatorData, clientHash])).digest();
  return cbor.encode({ authenticatorData, signature: sign('sha256', nonce, key.privateKey) });
}
export const TEST_BODY = Buffer.from('{}');
export const TEST_JWS = 'fixture.purchase.proof';
export const TEST_BODY_HASH = hash(TEST_BODY);
export const TEST_TRANSACTION_HASH = hash(TEST_JWS);

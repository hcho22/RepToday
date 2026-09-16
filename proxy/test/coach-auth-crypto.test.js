import { describe, expect, it } from 'vitest';
import { Buffer } from 'node:buffer';
import cbor from 'cbor';
import { assertKey, attestKey, assertionPayload, challengeToken, verifyChallenge, fromBase64, premiumEntitlement, hash } from '../src/coach-auth-crypto.js';
import { fixtureKey, signedAssertion, APP_PREFIX, TEST_GATE, TEST_BODY_HASH, TEST_TRANSACTION_HASH } from './auth-fixtures.js';
import { storeG2, storeG3 } from '../src/apple-trust-roots.js';

describe('real cryptographic request binding', () => {
  const key = fixtureKey(); const now = 1_800_000_000_000;
  const challenge = challengeToken(key.keyId, TEST_GATE, now);
  const payload = assertionPayload('reply', key.keyId, challenge, TEST_BODY_HASH, TEST_TRANSACTION_HASH);
  const assertion = signedAssertion(key, payload);
  it('verifies a genuine generated-key signature and monotonic counter', () => {
    expect(assertKey(assertion, key.publicKey, 0, payload, APP_PREFIX)).toBe(1);
    expect(() => assertKey(assertion, key.publicKey, 1, payload, APP_PREFIX)).toThrow();
  });
  it.each([
    ['delete', key.keyId, challenge, TEST_BODY_HASH, TEST_TRANSACTION_HASH],
    ['reply', fixtureKey().keyId, challenge, TEST_BODY_HASH, TEST_TRANSACTION_HASH],
    ['reply', key.keyId, challenge + 'x', TEST_BODY_HASH, TEST_TRANSACTION_HASH],
    ['reply', key.keyId, challenge, hash('different body'), TEST_TRANSACTION_HASH],
    ['reply', key.keyId, challenge, TEST_BODY_HASH, hash('different purchase proof')],
  ])('rejects operation/key/challenge/body/transaction substitution %s', (...parts) => {
    expect(() => assertKey(assertion, key.publicKey, 0, assertionPayload(...parts), APP_PREFIX)).toThrow();
  });
  it('rejects foreign app identity, public key, altered signature and malformed CBOR', () => {
    expect(() => assertKey(assertion, key.publicKey, 0, payload, 'OTHERAPP01')).toThrow();
    expect(() => assertKey(assertion, fixtureKey().publicKey, 0, payload, APP_PREFIX)).toThrow();
    const tampered = Buffer.from(assertion); tampered[tampered.length - 1] ^= 1;
    expect(() => assertKey(tampered, key.publicKey, 0, payload, APP_PREFIX)).toThrow();
    expect(() => assertKey(Buffer.concat([assertion, assertion]), key.publicKey, 0, payload, APP_PREFIX)).toThrow();
    expect(() => assertKey(Buffer.from('garbage'), key.publicKey, 0, payload, APP_PREFIX)).toThrow();
  });
  it.each([0, 0x80000000, 0xffffffff])('rejects zero or unsupported counter %d', counter => {
    expect(() => assertKey(signedAssertion(key, payload, counter), key.publicKey, 0, payload, APP_PREFIX)).toThrow();
  });
  it('bounds challenge expiry exactly and rejects forged/substituted challenges', () => {
    expect(verifyChallenge(challenge, key.keyId, TEST_GATE, now + 59999).k).toBe(key.keyId);
    for (const clock of [now - 1, now + 60000]) expect(() => verifyChallenge(challenge, key.keyId, TEST_GATE, clock)).toThrow();
    expect(() => verifyChallenge(challenge, fixtureKey().keyId, TEST_GATE, now)).toThrow();
    expect(() => verifyChallenge(challenge + 'x', key.keyId, TEST_GATE, now)).toThrow();
    expect(() => verifyChallenge(challenge, key.keyId, '1'.repeat(64), now)).toThrow();
  });
  it.each(['', ' AA==', 'AB==', 'AAAA=', 'AA===', '_A==', 'A'.repeat(100)])('rejects noncanonical/oversized base64', value => {
    expect(() => fromBase64(value, 4)).toThrow();
  });
  it('rejects a non-Apple-attestation chain without trusting client certificates', async () => {
    const forged = cbor.encode({fmt:'apple-appattest', authData:Buffer.alloc(100), attStmt:{receipt:Buffer.from('fixture'),
      x5c:[Buffer.from(storeG2,'base64'),Buffer.from(storeG3,'base64')]}});
    await expect(attestKey(forged,key.keyId,challenge,APP_PREFIX,now)).rejects.toThrow();
  });
  it('rejects malformed purchase proof with the actual official Apple verifier', async () => {
    await expect(premiumEntitlement('a.b.c',{APP_STORE_APP_ID:'1',APP_STORE_KEY_ID:APP_PREFIX,
      APP_STORE_ISSUER_ID:'00000000-0000-4000-8000-000000000000',APP_STORE_PRIVATE_KEY:'TEST-ONLY-INVALID'})).rejects.toThrow('Coach authentication failed');
  });
});

import { describe, expect, it } from 'vitest';
import { Buffer } from 'node:buffer';
import cbor from 'cbor';
import { assertKey, attestKey, assertionPayload, challengeToken, verifyChallenge, fromBase64, premiumEntitlement, hash, CHALLENGE_CLOCK_SKEW_MS } from '../src/coach-auth-crypto.js';
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
  it.each([
    {validationCategory:2,bundleVersion:'1'},
    {apple_validation_category_01:2,apple_bundle_version_01:'1'},
    {validationCategory:Buffer.from([2,0,0,0]),bundleVersion:'1'},
    {validationCategory:Buffer.from([0,0,0,2]),bundleVersion:'1'},
    {validationCategory:3,bundleVersion:'1'},
    {validationCategory:5,bundleVersion:'1'},
    {validationCategory:99,bundleVersion:'1'},
    {validationCategory:2,apple_validation_category_01:4,bundleVersion:'1'},
    {},
  ])('refuses unsupported signed extension candidates before beta admission %j', extensions => {
    // These generated-key signatures are not Apple/TestFlight evidence. Until the actual
    // assertion protocol is established, no alias, byte order or distribution may be guessed.
    for (const flags of [0,0x80]) {
      const candidate=signedAssertion(key,payload,1,APP_PREFIX,{extensions:cbor.encode(extensions),flags});
      expect(()=>assertKey(candidate,key.publicKey,0,payload,APP_PREFIX)).toThrow();
    }
  });
  it('bounds challenge expiry exactly and rejects forged/substituted challenges', () => {
    expect(verifyChallenge(challenge, key.keyId, TEST_GATE, now + 59999).k).toBe(key.keyId);
    for (const clock of [now - CHALLENGE_CLOCK_SKEW_MS - 1, now + 60000]) expect(() => verifyChallenge(challenge, key.keyId, TEST_GATE, clock)).toThrow();
    expect(() => verifyChallenge(challenge, fixtureKey().keyId, TEST_GATE, now)).toThrow();
    expect(() => verifyChallenge(challenge + 'x', key.keyId, TEST_GATE, now)).toThrow();
    expect(() => verifyChallenge(challenge, key.keyId, '1'.repeat(64), now)).toThrow();
  });
  it('accepts an issue time at most the bounded skew ahead of a trailing verifier clock', () => {
    // The Worker mints and a Durable Object on another machine verifies; neither clock is authoritative.
    expect(CHALLENGE_CLOCK_SKEW_MS).toBe(5000);
    for (const lag of [1, 25, CHALLENGE_CLOCK_SKEW_MS]) expect(verifyChallenge(challenge, key.keyId, TEST_GATE, now - lag).k).toBe(key.keyId);
    expect(() => verifyChallenge(challenge, key.keyId, TEST_GATE, now - CHALLENGE_CLOCK_SKEW_MS - 1)).toThrow();
    // The tolerance never excuses authenticity, binding or expiry.
    for (const lag of [1, CHALLENGE_CLOCK_SKEW_MS]) {
      expect(() => verifyChallenge(challengeToken(key.keyId, '1'.repeat(64), now), key.keyId, TEST_GATE, now - lag)).toThrow();
      expect(() => verifyChallenge(challenge, fixtureKey().keyId, TEST_GATE, now - lag)).toThrow();
    }
    expect(() => verifyChallenge(challengeToken(key.keyId, TEST_GATE, now - 60000 - CHALLENGE_CLOCK_SKEW_MS), key.keyId, TEST_GATE, now)).toThrow();
  });
  it.each(['', ' AA==', 'AB==', 'AAAA=', 'AA===', '_A==', 'A'.repeat(100)])('rejects noncanonical/oversized base64', value => {
    expect(() => fromBase64(value, 4)).toThrow();
  });
  it.each([
    [Buffer.from('garbage'), 'attestation_cbor'],
    [cbor.encode({ fmt: 'apple-appattest' }), 'attestation_shape'],
    [cbor.encode({ fmt: 'apple-appattest', authData: Buffer.alloc(100), attStmt: { x5c: [Buffer.from('bad'), Buffer.from('bad')] } }),
      'attestation_certificate'],
  ])('classifies a rejected App Attest check', async (attestation, reason) => {
    const denied = [];
    await expect(attestKey(attestation, key.keyId, challenge, APP_PREFIX, now, value => denied.push(value))).rejects.toThrow();
    expect(denied).toEqual([reason]);
  });
  it('rejects a non-Apple-attestation chain without trusting client certificates', async () => {
    const forged = cbor.encode({fmt:'apple-appattest', authData:Buffer.alloc(100), attStmt:{receipt:Buffer.from('fixture'),
      x5c:[Buffer.from(storeG2,'base64'),Buffer.from(storeG3,'base64')]}});
    const denied = [];
    await expect(attestKey(forged,key.keyId,challenge,APP_PREFIX,now,reason => denied.push(reason))).rejects.toThrow();
    expect(denied).toEqual(['attestation_chain']);
  });
  it('rejects malformed purchase proof with the actual official Apple verifier', async () => {
    await expect(premiumEntitlement('a.b.c',{APP_STORE_APP_ID:'1',APP_STORE_KEY_ID:APP_PREFIX,
      APP_STORE_ISSUER_ID:'00000000-0000-4000-8000-000000000000',APP_STORE_PRIVATE_KEY:'TEST-ONLY-INVALID'})).rejects.toThrow('Coach authentication failed');
  });
});

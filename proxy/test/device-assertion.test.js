import { describe, expect, it } from 'vitest';
import { Buffer } from 'node:buffer';
import { createHash, createVerify } from 'node:crypto';
import cbor from 'cbor';
import { deviceAssertionFixture } from './auth-fixtures.js';

// The captain's staging capture was rejected as do_assertion/assertion_signature. These checks pin
// that the device side was correct, so the rejection belonged to the deployed runtime's crypto.
describe('genuine device App Attest capture', () => {
  const device = deviceAssertionFixture();

  it('enrolls a key whose id is the certificate key and the attested credential', () => {
    const { x, y } = device.certificate.publicKey.export({ format: 'jwk' });
    const point = Buffer.concat([Buffer.from([4]), Buffer.from(x, 'base64url'), Buffer.from(y, 'base64url')]);
    expect(createHash('sha256').update(point).digest('base64')).toBe(device.credentialId);
    const cose = cbor.decodeFirstSync(device.attestation.authData.subarray(55 + Buffer.from(device.credentialId, 'base64').length));
    expect(Buffer.compare(cose.get(-2), Buffer.from(x, 'base64url'))).toBe(0);
    expect(Buffer.compare(cose.get(-3), Buffer.from(y, 'base64url'))).toBe(0);
    expect(device.attestation.authData.readUInt32BE(33)).toBe(0);
  });

  it('asserts for the same app with the first counter', () => {
    expect(device.authenticatorData.length).toBe(37);
    expect(Buffer.compare(device.authenticatorData.subarray(0, 32), device.attestation.authData.subarray(0, 32))).toBe(0);
    expect(device.authenticatorData.readUInt32BE(33)).toBe(1);
  });

  it('signs SHA-256 over nonce = SHA-256(authenticatorData || clientDataHash), as node-app-attest verifies', () => {
    expect(createVerify('SHA256').update(device.nonce).verify(device.publicKey, device.signature)).toBe(true);
    // Not the prehashed-nonce reading, and a single flipped bit fails.
    const message = Buffer.concat([device.authenticatorData, device.clientDataHash]);
    expect(createVerify('SHA256').update(message).verify(device.publicKey, device.signature)).toBe(false);
    const forged = Buffer.from(device.signature); forged[forged.length - 1] ^= 1;
    expect(createVerify('SHA256').update(device.nonce).verify(device.publicKey, forged)).toBe(false);
  });
});

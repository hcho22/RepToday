import { describe, expect, it } from 'vitest';
import { evaluateVerifiedPremiumEntitlement } from '../src/runtime-entitlement-policy.js';

// Verified-payload decision fixtures, not fabricated Apple signature proofs. No network/credentials.
const now = 1_800_000_000_000;
const transaction = () => ({ bundleId: 'com.reptoday.app', environment: 'Production',
  type: 'Auto-Renewable Subscription', productId: 'com.reptoday.app.premium.monthly',
  transactionId: '1234', originalTransactionId: '1230', purchaseDate: now - 60_000,
  expiresDate: now + 60_000, signedDate: now - 1_000 });
const decide = (presented = transaction(), current = transaction(), status = 1, fetched = now, clock = now) =>
  evaluateVerifiedPremiumEntitlement(presented, current, status, fetched, clock);

describe('verified premium decision slice (not a production authentication boundary)', () => {
  it('accepts active monthly/yearly and trial purchases without sign-in or price claims', () => {
    expect(decide()).toBe(true);
    const yearly = { ...transaction(), productId: 'com.reptoday.app.premium.yearly', offerType: 1, price: 0 };
    expect(decide(yearly, yearly)).toBe(true);
  });
  it.each([null, {}, { isPremium: true }, [], 'signed-proof-looking-text'])('rejects absent/client-asserted/malformed claims %j', value => {
    // @ts-expect-error Intentionally adversarial shapes.
    expect(decide(value)).toBe(false);
  });
  it.each([
    ['bundleId', 'other.app'], ['environment', 'Sandbox'], ['environment', 'Xcode'],
    ['environment', 'LocalTesting'], ['type', 'Non-Consumable'], ['productId', 'other.premium'],
    ['transactionId', ''], ['transactionId', 1234], ['originalTransactionId', 'not-an-id'],
    ['expiresDate', now], ['expiresDate', now - 1], ['expiresDate', String(now + 1)],
    ['expiresDate', NaN], ['expiresDate', Infinity], ['revocationDate', now - 1],
    ['revocationDate', now + 1], ['revocationDate', 'invalid'], ['isUpgraded', true], ['isUpgraded', 'false'],
    ['purchaseDate', now + 1], ['purchaseDate', -1], ['signedDate', now + 30_001], ['signedDate', now - 60_001],
  ])('rejects disallowed %s on either verified transaction', (field, value) => {
    const bad = { ...transaction(), [String(field)]: value };
    expect(decide(bad)).toBe(false); expect(decide(transaction(), bad)).toBe(false);
  });
  it.each([0, 2, 3, 4, 5, 6, '1', null, undefined])('rejects missing/expired/retry/grace/revoked/unknown server status %j', status => {
    expect(evaluateVerifiedPremiumEntitlement(transaction(), transaction(), status, now, now)).toBe(false);
  });
  it('rejects transaction substitution across original purchase chains', () => {
    expect(decide(transaction(), { ...transaction(), originalTransactionId: '9999' })).toBe(false);
  });
  it('accepts a latest renewal in the same active chain, including an allowed product switch', () => {
    expect(decide(transaction(), { ...transaction(), transactionId: '5678', productId: 'com.reptoday.app.premium.yearly' })).toBe(true);
  });
  it('checks expiry, status freshness and future signed-date clock boundaries exactly', () => {
    expect(decide({ ...transaction(), expiresDate: now + 1 })).toBe(true);
    expect(decide(transaction(), transaction(), 1, now - 5_000)).toBe(true);
    expect(decide(transaction(), transaction(), 1, now - 5_001)).toBe(false);
    expect(decide(transaction(), transaction(), 1, now + 1)).toBe(false);
    expect(decide({ ...transaction(), signedDate: now + 30_000 })).toBe(true);
  });
  it.each([NaN, Infinity, -1])('fails closed on an invalid server clock %j', clock => {
    expect(decide(transaction(), transaction(), 1, now, clock)).toBe(false);
    expect(decide(transaction(), transaction(), 1, clock)).toBe(false);
  });
  it('does not mistake the decision policy for a cryptographic verifier', () => {
    // Plain fixtures can satisfy this predicate. Only trusted verifier/status outputs are valid inputs.
    expect(decide()).toBe(true);
  });
});

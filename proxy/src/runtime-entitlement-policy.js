// Pure entitlement decision, not a signature verifier or a public authentication boundary.
// The deployed runtime gateway supplies inputs from Apple's trusted
// server-side SignedDataVerifier and a fresh authenticated App Store Server API status lookup.
const BUNDLE = 'com.reptoday.app';
const PRODUCTS = new Set(['com.reptoday.app.premium.monthly', 'com.reptoday.app.premium.yearly']);
const ENVIRONMENTS = new Set(['Production', 'Sandbox']);
const numericID = value => typeof value === 'string' && /^[0-9]{1,32}$/.test(value);

/** @param {Record<string, unknown> | null} transaction @param {string} environment @param {number} nowMs */
function activeTransaction(transaction, environment, nowMs) {
  return transaction !== null && typeof transaction === 'object' && !Array.isArray(transaction) &&
    transaction.bundleId === BUNDLE && transaction.environment === environment &&
    transaction.type === 'Auto-Renewable Subscription' && typeof transaction.productId === 'string' &&
    PRODUCTS.has(transaction.productId) && numericID(transaction.transactionId) && numericID(transaction.originalTransactionId) &&
    typeof transaction.expiresDate === 'number' && Number.isFinite(transaction.expiresDate) && transaction.expiresDate > nowMs &&
    typeof transaction.purchaseDate === 'number' && Number.isFinite(transaction.purchaseDate) &&
    transaction.purchaseDate >= 0 && transaction.purchaseDate <= nowMs && transaction.purchaseDate < transaction.expiresDate &&
    typeof transaction.signedDate === 'number' && Number.isFinite(transaction.signedDate) &&
    transaction.signedDate >= transaction.purchaseDate && transaction.signedDate <= nowMs + 30_000 &&
    (transaction.revocationDate === undefined || transaction.revocationDate === null) &&
    (transaction.isUpgraded === undefined || transaction.isUpgraded === false);
}

/**
 * Pure decision after verification. Never pass client-decoded claims, a client premium boolean,
 * a client status/fetch timestamp, or an unverified JWS here. A true result alone is not authorization:
 * production also requires App Attest request binding and atomic nonce/counter consumption.
 * @param {Record<string, unknown> | null} presentedTransaction
 * @param {Record<string, unknown> | null} currentTransaction
 * @param {unknown} serverSubscriptionStatus
 * @param {number} serverStatusFetchedAtMs Timestamp measured by the server after its own API lookup.
 * @param {number} nowMs Server clock immediately before deciding; no entitlement cache in this slice.
 * @param {unknown} environment Environment selected from a successfully Apple-verified presented JWS.
 */
export function evaluateVerifiedPremiumEntitlement(presentedTransaction, currentTransaction,
  serverSubscriptionStatus, serverStatusFetchedAtMs, nowMs, environment) {
  return typeof environment === 'string' && ENVIRONMENTS.has(environment) &&
    Number.isFinite(nowMs) && nowMs >= 0 && Number.isFinite(serverStatusFetchedAtMs) &&
    serverStatusFetchedAtMs >= 0 && serverStatusFetchedAtMs <= nowMs && nowMs - serverStatusFetchedAtMs <= 5_000 &&
    serverSubscriptionStatus === 1 && activeTransaction(presentedTransaction, environment, nowMs) &&
    activeTransaction(currentTransaction, environment, nowMs) &&
    presentedTransaction.originalTransactionId === currentTransaction.originalTransactionId;
}

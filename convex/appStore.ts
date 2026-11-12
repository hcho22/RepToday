import { v, type Infer } from "convex/values";
import { AppStoreVerificationError, decodeUnverifiedPayload, derFromBase64, MAX_JWS_LENGTH, verifyAppleSignedData } from "./appStoreJws";
import { APPLE_ROOT_CA_G2, APPLE_ROOT_CA_G3 } from "./appleRoots";

/**
 * What the backend accepts as App Store evidence of a Premium subscription (M4, US-CA02, ADR-0017),
 * and the verified facts it keeps from it.
 *
 * Two kinds of signed data arrive: App Store Server Notifications V2 (`POST /appStore/notifications`,
 * `convex/http.ts`), which keep the entitlement current as subscriptions renew, lapse, are refunded or
 * revoked; and a StoreKit 2 transaction's `jwsRepresentation`, which the app sends after a purchase or
 * a restore to link the subscription to the signed-in account (`entitlements:linkTransaction`).
 * Both are verified against Apple's pinned roots (`convex/appStoreJws.ts`) and then checked for this
 * app's bundle id, an accepted environment and a Premium product before anything is stored.
 *
 * Which environments a deployment accepts is deployment configuration, so no client can choose it:
 *
 * - `APPSTORE_ENVIRONMENTS`: a comma-separated list of `Production` and/or `Sandbox`. The dev
 *   deployment sets `Sandbox`; production sets `Production,Sandbox`, because App Review buys in the
 *   Sandbox against the production build. Unset means the deployment accepts no App Store data at all
 *   (fail closed: `entitlement_unavailable`).
 * - `APPSTORE_ALLOW_XCODE`: `1` on a development deployment only. A StoreKit test transaction made in
 *   Xcode or the Simulator is signed by Xcode's local key, not Apple's, so it can never verify; Apple's
 *   own `SignedDataVerifier` accepts the `Xcode` environment unverified for exactly this reason. With
 *   this flag a transaction whose payload says `Xcode` is accepted the same way, so a Simulator
 *   purchase can be walked end to end. It never applies to notifications and must never be set on
 *   production.
 */

declare const process: { readonly env: Readonly<Record<string, string | undefined>> };

/** The app's bundle id; every accepted payload must name it. */
export const APPSTORE_BUNDLE_ID = "com.reptoday.app";

/** The Premium products (`ios/RepToday/RepToday/Models/SubscriptionPlan.swift`). */
export const PREMIUM_PRODUCT_IDS: ReadonlySet<string> = new Set([
  "com.reptoday.app.premium.monthly",
  "com.reptoday.app.premium.yearly",
]);

export type VerifiedEnvironment = "Production" | "Sandbox";
export type AcceptedEnvironment = VerifiedEnvironment | "Xcode";

export type AppStoreConfig = {
  environments: ReadonlySet<VerifiedEnvironment>;
  allowXcode: boolean;
  trustedRoots: Uint8Array[];
};

/** The deployment's App Store configuration, or `null` when it accepts no App Store data. */
export function appStoreConfig(env: Readonly<Record<string, string | undefined>> = process.env): AppStoreConfig | null {
  const listed = (env.APPSTORE_ENVIRONMENTS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value): value is VerifiedEnvironment => value === "Production" || value === "Sandbox");
  if (listed.length === 0) {
    return null;
  }
  return {
    environments: new Set(listed),
    allowXcode: env.APPSTORE_ALLOW_XCODE === "1",
    trustedRoots: [derFromBase64(APPLE_ROOT_CA_G3), derFromBase64(APPLE_ROOT_CA_G2)],
  };
}

/** Why App Store data was refused. Fixed labels; never the payload. */
export type AppStoreRefusal =
  | "unverifiable"
  | "wrong_bundle"
  | "wrong_environment"
  | "not_premium_product"
  | "not_subscription"
  | "malformed";

export class AppStoreRefusalError extends Error {
  constructor(readonly refusal: AppStoreRefusal) {
    super(`App Store data refused: ${refusal}`);
  }
}

/** The facts kept from one verified subscription transaction. */
export const transactionFacts = v.object({
  originalTransactionId: v.string(),
  transactionId: v.string(),
  productId: v.string(),
  environment: v.union(v.literal("Production"), v.literal("Sandbox"), v.literal("Xcode")),
  /** When this period ends (ms since the epoch). */
  expiresAt: v.number(),
  /** Set when Apple refunded or revoked the purchase. */
  revokedAt: v.optional(v.number()),
  /** The account token the purchase was made with, when the app set one. */
  appAccountToken: v.optional(v.string()),
  /** When Apple signed this transaction: orders updates so an older one never replaces a newer one. */
  signedAt: v.number(),
});
export type TransactionFacts = Infer<typeof transactionFacts>;

/** The facts kept from one verified notification. */
export type NotificationFacts = {
  notificationUUID: string;
  notificationType: string;
  subtype?: string;
  environment: VerifiedEnvironment;
  transaction?: TransactionFacts;
  /** The end of a billing grace period from the renewal info, when one is running. */
  gracePeriodExpiresAt?: number;
};

/**
 * Verifies a StoreKit 2 transaction's JWS and returns its facts. Refuses anything that is not a
 * Premium auto-renewable subscription of this app in an accepted environment.
 */
export async function verifiedTransaction(jws: string, config: AppStoreConfig, now: number): Promise<TransactionFacts> {
  let payload: Record<string, unknown>;
  if (config.allowXcode && isXcodePayload(jws)) {
    payload = decodeUnverifiedPayload(jws);
  } else {
    payload = await verifyOrRefuse(jws, config, now);
  }
  return transactionFromPayload(payload, config);
}

/** Verifies a notification's `signedPayload` and the transaction and renewal info inside it. */
export async function verifiedNotification(signedPayload: string, config: AppStoreConfig, now: number): Promise<NotificationFacts> {
  const payload = await verifyOrRefuse(signedPayload, config, now);
  const data = asRecord(payload.data);
  const notificationUUID = stringField(payload.notificationUUID);
  const notificationType = stringField(payload.notificationType);
  if (data === undefined || notificationUUID === undefined || notificationType === undefined || notificationUUID.length > 64) {
    throw new AppStoreRefusalError("malformed");
  }
  if (data.bundleId !== APPSTORE_BUNDLE_ID) {
    throw new AppStoreRefusalError("wrong_bundle");
  }
  const environment = data.environment;
  if (environment !== "Production" && environment !== "Sandbox") {
    throw new AppStoreRefusalError("wrong_environment");
  }
  if (!config.environments.has(environment)) {
    throw new AppStoreRefusalError("wrong_environment");
  }
  const facts: NotificationFacts = {
    notificationUUID,
    notificationType,
    environment,
    ...(stringField(payload.subtype) === undefined ? {} : { subtype: stringField(payload.subtype) }),
  };
  const signedTransaction = jwsField(data.signedTransactionInfo);
  if (signedTransaction !== undefined) {
    const transaction = transactionFromPayload(await verifyOrRefuse(signedTransaction, config, now), config);
    if (transaction.environment !== environment) {
      throw new AppStoreRefusalError("wrong_environment");
    }
    facts.transaction = transaction;
  }
  const signedRenewal = jwsField(data.signedRenewalInfo);
  if (signedRenewal !== undefined) {
    const renewal = await verifyOrRefuse(signedRenewal, config, now);
    if (renewal.environment !== environment) {
      throw new AppStoreRefusalError("wrong_environment");
    }
    const grace = numberField(renewal.gracePeriodExpiresDate);
    if (grace !== undefined) {
      facts.gracePeriodExpiresAt = grace;
    }
  }
  return facts;
}

async function verifyOrRefuse(jws: string, config: AppStoreConfig, now: number): Promise<Record<string, unknown>> {
  try {
    return await verifyAppleSignedData(jws, { trustedRoots: config.trustedRoots, now: () => now });
  } catch (error) {
    if (error instanceof AppStoreVerificationError) {
      throw new AppStoreRefusalError(error.reason === "malformed" ? "malformed" : "unverifiable");
    }
    throw error;
  }
}

function isXcodePayload(jws: string): boolean {
  try {
    return decodeUnverifiedPayload(jws).environment === "Xcode";
  } catch {
    return false;
  }
}

function transactionFromPayload(payload: Record<string, unknown>, config: AppStoreConfig): TransactionFacts {
  if (payload.bundleId !== APPSTORE_BUNDLE_ID) {
    throw new AppStoreRefusalError("wrong_bundle");
  }
  const environment = payload.environment;
  const accepted =
    environment === "Xcode" ? config.allowXcode : (environment === "Production" || environment === "Sandbox") && config.environments.has(environment);
  if (!accepted) {
    throw new AppStoreRefusalError("wrong_environment");
  }
  if (payload.type !== "Auto-Renewable Subscription") {
    throw new AppStoreRefusalError("not_subscription");
  }
  const productId = stringField(payload.productId);
  if (productId === undefined || !PREMIUM_PRODUCT_IDS.has(productId)) {
    throw new AppStoreRefusalError("not_premium_product");
  }
  const originalTransactionId = idField(payload.originalTransactionId);
  const transactionId = idField(payload.transactionId);
  const expiresAt = numberField(payload.expiresDate);
  const signedAt = numberField(payload.signedDate);
  if (originalTransactionId === undefined || transactionId === undefined || expiresAt === undefined || signedAt === undefined) {
    throw new AppStoreRefusalError("malformed");
  }
  const revokedAt = numberField(payload.revocationDate);
  const token = stringField(payload.appAccountToken);
  const appAccountToken = token !== undefined && UUID_PATTERN.test(token) ? token.toLowerCase() : undefined;
  return {
    originalTransactionId,
    transactionId,
    productId,
    environment: environment as AcceptedEnvironment,
    expiresAt,
    signedAt,
    ...(revokedAt === undefined ? {} : { revokedAt }),
    ...(appAccountToken === undefined ? {} : { appAccountToken }),
  };
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
}

function stringField(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 && value.length <= 256 ? value : undefined;
}

function jwsField(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 && value.length <= MAX_JWS_LENGTH ? value : undefined;
}

function idField(value: unknown): string | undefined {
  return typeof value === "string" && /^[0-9]{1,32}$/.test(value) ? value : undefined;
}

function numberField(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;
}

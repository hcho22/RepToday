import { convexTest } from "convex-test";
import { afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import { base64, mintChain, signJws, unsignedJws, type TestChain } from "./appStoreFixtures.testkit";

/**
 * The per-account Premium entitlement (M4, US-CA02): App Store Server Notifications at
 * `POST /appStore/notifications` and the app's own link of a verified transaction.
 *
 * Every payload is a real ES256 JWS over a minted Apple-shaped chain. The pinned Apple roots are
 * swapped for that chain's root through the module mock below - the production code reads its trust
 * anchors from `./appleRoots` and has no test hook - so forgeries, wrong environments and wrong
 * bundles are refused by the same verifier production runs.
 */

const roots = vi.hoisted(() => ({ value: "" }));
vi.mock("./appleRoots", () => ({
  get APPLE_ROOT_CA_G3() {
    return roots.value;
  },
  get APPLE_ROOT_CA_G2() {
    return roots.value;
  },
}));

declare const process: { env: Record<string, string | undefined> };

const modules: Record<string, () => Promise<any>> = Object.fromEntries(
  Object.entries({
    ...import.meta.glob("./**/*.ts"),
    ...import.meta.glob("./**/*.js"),
  }).filter(([path]) => !path.endsWith(".d.ts") && !path.endsWith(".test.ts")),
);

const ALICE = { subject: "user_alice", tokenIdentifier: "https://clerk.test|user_alice", issuer: "https://clerk.test" };
const BOB = { subject: "user_bob", tokenIdentifier: "https://clerk.test|user_bob", issuer: "https://clerk.test" };

const DAY = 24 * 60 * 60 * 1000;
let chain: TestChain;
const savedEnv = { ...process.env };

beforeAll(async () => {
  chain = await mintChain();
  roots.value = base64(chain.rootDer);
});

beforeEach(() => {
  process.env.APPSTORE_ENVIRONMENTS = "Sandbox";
  delete process.env.APPSTORE_ALLOW_XCODE;
});

afterEach(() => {
  for (const key of ["APPSTORE_ENVIRONMENTS", "APPSTORE_ALLOW_XCODE"]) {
    if (savedEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedEnv[key];
  }
});

function transaction(overrides: Record<string, unknown> = {}) {
  const now = Date.now();
  return {
    transactionId: "2000000001",
    originalTransactionId: "1000000001",
    bundleId: "com.reptoday.app",
    productId: "com.reptoday.app.premium.monthly",
    type: "Auto-Renewable Subscription",
    environment: "Sandbox",
    purchaseDate: now - DAY,
    expiresDate: now + 30 * DAY,
    signedDate: now - 1000,
    ...overrides,
  };
}

async function notification(
  type: string,
  tx: Record<string, unknown> | null,
  options: { uuid?: string; environment?: string; bundleId?: string; renewal?: Record<string, unknown>; signer?: TestChain } = {},
) {
  const signer = options.signer ?? chain;
  const data: Record<string, unknown> = { bundleId: options.bundleId ?? "com.reptoday.app", environment: options.environment ?? "Sandbox" };
  if (tx !== null) data.signedTransactionInfo = await signJws(tx, signer);
  if (options.renewal !== undefined) data.signedRenewalInfo = await signJws(options.renewal, signer);
  return await signJws(
    { notificationType: type, notificationUUID: options.uuid ?? crypto.randomUUID(), signedDate: Date.now() - 500, version: "2.0", data },
    signer,
  );
}

async function post(t: ReturnType<typeof convexTest>, signedPayload: string) {
  const response = await t.fetch("/appStore/notifications", { method: "POST", body: JSON.stringify({ signedPayload }) });
  return { status: response.status, body: (await response.json()) as { outcome: string } };
}

async function premium(t: ReturnType<typeof convexTest>, who: typeof ALICE) {
  return (await t.withIdentity(who).query(api.entitlements.status, {})).premium;
}

async function token(t: ReturnType<typeof convexTest>, who: typeof ALICE) {
  return await t.withIdentity(who).mutation(api.entitlements.appAccountToken, {});
}

async function entitlementRows(t: ReturnType<typeof convexTest>) {
  return await t.run(async (ctx) => await ctx.db.query("entitlements").collect());
}

async function expectRefusal(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toSatisfy((error: any) => error?.data?.code === code);
}

describe("ownership", () => {
  test("every public entitlement function refuses an unauthenticated caller", async () => {
    const t = convexTest(schema, modules);
    await expectRefusal(t.query(api.entitlements.status, {}), "unauthenticated");
    await expectRefusal(t.mutation(api.entitlements.appAccountToken, {}), "unauthenticated");
    await expectRefusal(t.action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) }), "unauthenticated");
  });

  test("an account's App Store token is a stable UUID of its own", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    expect(alice).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    expect(await token(t, ALICE)).toBe(alice);
    expect(await token(t, BOB)).not.toBe(alice);
  });
});

describe("App Store Server Notifications keep the entitlement current", () => {
  test("free: an account Apple has said nothing about is not Premium", async () => {
    const t = convexTest(schema, modules);
    expect(await premium(t, ALICE)).toBe(false);
  });

  test("active: a purchase made with the account's token makes that account Premium, and only it", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    const result = await post(t, await notification("SUBSCRIBED", transaction({ appAccountToken: alice })));
    expect(result).toEqual({ status: 200, body: { outcome: "applied" } });
    expect(await premium(t, ALICE)).toBe(true);
    expect(await premium(t, BOB)).toBe(false);
  });

  test("renewal moves the end of the period on; a lapse lets it pass (expired)", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    const now = Date.now();
    await post(t, await notification("SUBSCRIBED", transaction({ appAccountToken: alice, expiresDate: now + DAY, signedDate: now - 3000 })));
    await post(t, await notification("DID_RENEW", transaction({ appAccountToken: alice, expiresDate: now + 31 * DAY, signedDate: now - 2000 })));
    expect((await entitlementRows(t))[0].expiresAt).toBe(now + 31 * DAY);
    await post(t, await notification("EXPIRED", transaction({ appAccountToken: alice, expiresDate: now - 1000, signedDate: now - 1000 })));
    expect(await premium(t, ALICE)).toBe(false);
  });

  test("revoked: a refund or revocation ends Premium even inside the period", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    await post(t, await notification("SUBSCRIBED", transaction({ appAccountToken: alice, signedDate: Date.now() - 3000 })));
    expect(await premium(t, ALICE)).toBe(true);
    await post(t, await notification("REFUND", transaction({ appAccountToken: alice, revocationDate: Date.now() - 100, signedDate: Date.now() - 100 })));
    expect(await premium(t, ALICE)).toBe(false);
  });

  test("a billing grace period keeps Premium until it ends", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    const now = Date.now();
    await post(
      t,
      await notification("DID_FAIL_TO_RENEW", transaction({ appAccountToken: alice, expiresDate: now - DAY }), {
        renewal: { environment: "Sandbox", originalTransactionId: "1000000001", gracePeriodExpiresDate: now + 3 * DAY, signedDate: now - 500 },
      }),
    );
    expect(await premium(t, ALICE)).toBe(true);
  });

  test("Apple's retry of a notification is applied once", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    const signed = await notification("SUBSCRIBED", transaction({ appAccountToken: alice }), { uuid: "11111111-2222-4333-8444-555555555555" });
    expect((await post(t, signed)).body.outcome).toBe("applied");
    expect((await post(t, signed)).body.outcome).toBe("duplicate");
    expect(await entitlementRows(t)).toHaveLength(1);
  });

  test("an update older than the one applied never replaces it", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    const now = Date.now();
    await post(t, await notification("DID_RENEW", transaction({ appAccountToken: alice, expiresDate: now + 30 * DAY, signedDate: now - 1000 })));
    const late = await post(t, await notification("EXPIRED", transaction({ appAccountToken: alice, expiresDate: now - DAY, signedDate: now - 5000 })));
    expect(late.body.outcome).toBe("stale");
    expect(await premium(t, ALICE)).toBe(true);
  });

  test("a TEST notification carries no subscription and changes nothing", async () => {
    const t = convexTest(schema, modules);
    expect(await post(t, await notification("TEST", null))).toEqual({ status: 200, body: { outcome: "no_transaction" } });
    expect(await entitlementRows(t)).toHaveLength(0);
  });

  test("a forged notification is refused and stores nothing", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    const signed = await notification("SUBSCRIBED", transaction({ appAccountToken: alice }));
    const [header, payload, signature] = signed.split(".");
    const tampered = `${header}.${payload.slice(0, -4)}AAAA.${signature}`;
    expect((await post(t, tampered)).status).toBe(400);
    const other = await mintChain();
    expect(await post(t, await notification("SUBSCRIBED", transaction({ appAccountToken: alice }), { signer: other }))).toEqual({
      status: 400,
      body: { outcome: "unverifiable" },
    });
    expect(await entitlementRows(t)).toHaveLength(0);
    expect(await premium(t, ALICE)).toBe(false);
  });

  test("a notification from an environment this deployment does not accept is refused", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    const production = await notification("SUBSCRIBED", transaction({ appAccountToken: alice, environment: "Production" }), { environment: "Production" });
    expect(await post(t, production)).toEqual({ status: 400, body: { outcome: "wrong_environment" } });
    const mixed = await notification("SUBSCRIBED", transaction({ appAccountToken: alice, environment: "Production" }));
    expect((await post(t, mixed)).status).toBe(400);
    expect(await premium(t, ALICE)).toBe(false);
  });

  test("a notification for another app, or a product that is not Premium, is refused", async () => {
    const t = convexTest(schema, modules);
    expect(await post(t, await notification("SUBSCRIBED", transaction(), { bundleId: "com.example.other" }))).toEqual({
      status: 400,
      body: { outcome: "wrong_bundle" },
    });
    expect((await post(t, await notification("SUBSCRIBED", transaction({ productId: "com.reptoday.app.tip" })))).body.outcome).toBe("not_premium_product");
    expect(await entitlementRows(t)).toHaveLength(0);
  });

  test("a deployment configured for no environment refuses everything with 503", async () => {
    const t = convexTest(schema, modules);
    delete process.env.APPSTORE_ENVIRONMENTS;
    expect((await post(t, await notification("SUBSCRIBED", transaction()))).status).toBe(503);
  });

  test("malformed bodies are refused before any verification", async () => {
    const t = convexTest(schema, modules);
    const response = await t.fetch("/appStore/notifications", { method: "POST", body: "not json" });
    expect(response.status).toBe(400);
    const empty = await t.fetch("/appStore/notifications", { method: "POST", body: JSON.stringify({}) });
    expect(empty.status).toBe(400);
  });
});

describe("linkTransaction: purchase and Restore Purchases link a subscription to the account", () => {
  test("restored: a verified transaction with no token links to the caller", async () => {
    const t = convexTest(schema, modules);
    const result = await t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) });
    expect(result.premium).toBe(true);
    expect(await premium(t, ALICE)).toBe(true);
    // A later notification for the same subscription reaches the linked account without a token.
    await post(t, await notification("REVOKE", transaction({ revocationDate: Date.now(), signedDate: Date.now() })));
    expect(await premium(t, ALICE)).toBe(false);
  });

  test("a notification that arrived before the link is picked up by it", async () => {
    const t = convexTest(schema, modules);
    await post(t, await notification("SUBSCRIBED", transaction({ signedDate: Date.now() - 5000 })));
    expect(await premium(t, ALICE)).toBe(false);
    await t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) });
    expect(await premium(t, ALICE)).toBe(true);
    expect(await entitlementRows(t)).toHaveLength(1);
  });

  test("a subscription linked to another live account is never moved", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) });
    await expectRefusal(t.withIdentity(BOB).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) }), "linked_to_other_account");
    expect(await premium(t, BOB)).toBe(false);
    expect(await premium(t, ALICE)).toBe(true);
  });

  test("a purchase made with another account's token cannot be claimed", async () => {
    const t = convexTest(schema, modules);
    const alice = await token(t, ALICE);
    await expectRefusal(
      t.withIdentity(BOB).action(api.entitlements.linkTransaction, { jws: await signJws(transaction({ appAccountToken: alice }), chain) }),
      "linked_to_other_account",
    );
  });

  test("an unverifiable or foreign transaction is refused", async () => {
    const t = convexTest(schema, modules);
    const other = await mintChain();
    await expectRefusal(t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), other) }), "invalid_transaction");
    await expectRefusal(
      t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction({ bundleId: "com.example.other" }), chain) }),
      "invalid_transaction",
    );
    await expectRefusal(
      t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction({ environment: "Production" }), chain) }),
      "invalid_transaction",
    );
    expect(await premium(t, ALICE)).toBe(false);
  });

  test("an Xcode StoreKit test transaction is accepted only where APPSTORE_ALLOW_XCODE is set", async () => {
    const t = convexTest(schema, modules);
    const xcode = unsignedJws(transaction({ environment: "Xcode" }));
    await expectRefusal(t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: xcode }), "invalid_transaction");
    process.env.APPSTORE_ALLOW_XCODE = "1";
    expect((await t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: xcode })).premium).toBe(true);
    // The flag never lets an unsigned Sandbox payload through.
    await expectRefusal(
      t.withIdentity(BOB).action(api.entitlements.linkTransaction, { jws: unsignedJws(transaction({ originalTransactionId: "1000000009" })) }),
      "invalid_transaction",
    );
  });

  test("a deployment configured for no environment refuses links", async () => {
    const t = convexTest(schema, modules);
    delete process.env.APPSTORE_ENVIRONMENTS;
    await expectRefusal(t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) }), "entitlement_unavailable");
  });

  test("deleting the account removes its entitlement and token, freeing the subscription", async () => {
    const t = convexTest(schema, modules);
    process.env.CLERK_SECRET_KEY = "sk_test_placeholder";
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 200 })));
    await token(t, ALICE);
    await t.withIdentity(ALICE).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) });
    await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {});
    expect(await t.run(async (ctx) => await ctx.db.query("appAccountTokens").collect())).toHaveLength(0);
    expect(await entitlementRows(t)).toHaveLength(0);
    expect((await t.withIdentity(BOB).action(api.entitlements.linkTransaction, { jws: await signJws(transaction(), chain) })).premium).toBe(true);
    vi.unstubAllGlobals();
    if (savedEnv.CLERK_SECRET_KEY === undefined) delete process.env.CLERK_SECRET_KEY;
    else process.env.CLERK_SECRET_KEY = savedEnv.CLERK_SECRET_KEY;
  });
});

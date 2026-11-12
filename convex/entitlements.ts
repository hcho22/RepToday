import { v } from "convex/values";
import { action, internalMutation, internalQuery, mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import { accountError, findAccount, requireOwner, writableAccount } from "./ownership";
import { appStoreConfig, AppStoreRefusalError, transactionFacts, verifiedTransaction, type NotificationFacts, type TransactionFacts } from "./appStore";

/**
 * The per-account Premium entitlement (M4, US-CA02, ADR-0017).
 *
 * Premium is decided here, on the server, from App Store data Apple signed - never from anything the
 * app claims. The Coach reads `premiumForOwner` on every turn (`convex/coach.ts`).
 *
 * - **Kept current by Apple.** `POST /appStore/notifications` (`convex/http.ts`) verifies each App
 *   Store Server Notification and applies its transaction here (`applyNotification`): a renewal moves
 *   `expiresAt` on, a lapse lets it pass, a refund or revocation sets `revokedAt`, and a billing grace
 *   period extends access until it ends. A delivery Apple retries is applied once, and an update older
 *   than the one already applied is ignored.
 * - **Linked to the account.** A notification reaches an account through its `appAccountToken` (the
 *   random UUID `appAccountToken` hands the app to pass to StoreKit with each purchase) or through a
 *   subscription the account already holds. A purchase made before accounts, or on another device,
 *   is linked when the app sends its verified transaction (`linkTransaction`, after a purchase and
 *   on Restore Purchases).
 * - **One account per subscription.** A subscription linked to another account that still exists is
 *   never moved by a restore (`linked_to_other_account`); deleting that account frees it.
 */

/** Whether an entitlement row grants Premium at `now`. */
export function entitlementIsActive(row: Pick<Doc<"entitlements">, "expiresAt" | "gracePeriodExpiresAt" | "revokedAt">, now: number): boolean {
  if (row.revokedAt !== undefined) {
    return false;
  }
  return Math.max(row.expiresAt, row.gracePeriodExpiresAt ?? 0) > now;
}

async function ownerEntitlements(ctx: QueryCtx, ownerId: string): Promise<Doc<"entitlements">[]> {
  return await ctx.db
    .query("entitlements")
    .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
    .take(20);
}

/** The owner's Premium state at `now`: active, and until when. */
export async function premiumState(ctx: QueryCtx, ownerId: string, now: number): Promise<{ premium: boolean; expiresAt: number | null; productId: string | null }> {
  const active = (await ownerEntitlements(ctx, ownerId)).filter((row) => entitlementIsActive(row, now));
  if (active.length === 0) {
    return { premium: false, expiresAt: null, productId: null };
  }
  const longest = active.reduce((best, row) =>
    Math.max(row.expiresAt, row.gracePeriodExpiresAt ?? 0) > Math.max(best.expiresAt, best.gracePeriodExpiresAt ?? 0) ? row : best,
  );
  return { premium: true, expiresAt: Math.max(longest.expiresAt, longest.gracePeriodExpiresAt ?? 0), productId: longest.productId };
}

/** The caller's Premium state, as the server decides it. */
export const status = query({
  args: {},
  handler: async (ctx) => {
    const owner = await requireOwner(ctx);
    const account = await findAccount(ctx, owner.ownerId);
    if (account?.deletionStartedAt !== undefined) {
      throw accountError("account_deleting", "This account is being deleted.");
    }
    return await premiumState(ctx, owner.ownerId, Date.now());
  },
});

/** Whether an owner has Premium right now. Read by the Coach on every turn. */
export const premiumForOwner = internalQuery({
  args: { ownerId: v.string(), now: v.number() },
  handler: async (ctx, { ownerId, now }) => (await premiumState(ctx, ownerId, now)).premium,
});

/**
 * The caller's `appAccountToken`, created on first use. The app passes it to StoreKit with every
 * purchase so Apple names it in that subscription's notifications.
 */
export const appAccountToken = mutation({
  args: {},
  handler: async (ctx) => {
    const owner = await requireOwner(ctx);
    await writableAccount(ctx, owner);
    const existing = await ctx.db
      .query("appAccountTokens")
      .withIndex("by_ownerId", (q) => q.eq("ownerId", owner.ownerId))
      .first();
    if (existing !== null) {
      return existing.token;
    }
    const token = crypto.randomUUID().toLowerCase();
    await ctx.db.insert("appAccountTokens", { ownerId: owner.ownerId, token });
    return token;
  },
});

/**
 * Link a verified StoreKit 2 transaction to the caller's account and return the resulting Premium
 * state. The app calls it after a purchase and on Restore Purchases with the transaction's
 * `jwsRepresentation`; the signature, bundle id, environment and product are checked before anything
 * is written.
 */
export const linkTransaction = action({
  args: { jws: v.string() },
  handler: async (ctx, { jws }): Promise<{ premium: boolean; expiresAt: number | null; productId: string | null }> => {
    const owner = await requireOwner(ctx);
    const config = appStoreConfig();
    if (config === null) {
      throw accountError("entitlement_unavailable", "This deployment does not accept App Store purchases.");
    }
    let facts: TransactionFacts;
    try {
      facts = await verifiedTransaction(jws, config, Date.now());
    } catch (error) {
      if (error instanceof AppStoreRefusalError) {
        throw accountError("invalid_transaction", "That purchase could not be verified.");
      }
      throw error;
    }
    return await ctx.runMutation(internal.entitlements.linkVerified, { ownerId: owner.ownerId, clerkUserId: owner.clerkUserId, facts });
  },
});

/** Applies a verified transaction to the owner's entitlement, refusing one held by another account. */
export const linkVerified = internalMutation({
  args: { ownerId: v.string(), clerkUserId: v.string(), facts: transactionFacts },
  handler: async (ctx, { ownerId, clerkUserId, facts }) => {
    await writableAccount(ctx, { ownerId, clerkUserId });
    const existing = await ctx.db
      .query("entitlements")
      .withIndex("by_originalTransactionId", (q) => q.eq("originalTransactionId", facts.originalTransactionId))
      .unique();
    if (existing?.ownerId !== undefined && existing.ownerId !== ownerId && (await isLiveAccount(ctx, existing.ownerId))) {
      throw accountError("linked_to_other_account", "This subscription belongs to another Rep Today account.");
    }
    if (facts.appAccountToken !== undefined) {
      const tokenOwner = await ownerOfToken(ctx, facts.appAccountToken);
      if (tokenOwner !== null && tokenOwner !== ownerId && (await isLiveAccount(ctx, tokenOwner))) {
        throw accountError("linked_to_other_account", "This subscription belongs to another Rep Today account.");
      }
    }
    await upsert(ctx, existing, ownerId, facts, undefined);
    return await premiumState(ctx, ownerId, Date.now());
  },
});

/** What became of one App Store notification. */
export type NotificationOutcome = "applied" | "duplicate" | "stale" | "no_transaction";

/**
 * Applies one verified App Store Server Notification. Idempotent by `notificationUUID`; an update
 * older than what the row already holds is recorded but changes nothing.
 */
export const applyNotification = internalMutation({
  args: {
    notificationUUID: v.string(),
    notificationType: v.string(),
    transaction: v.optional(transactionFacts),
    gracePeriodExpiresAt: v.optional(v.number()),
  },
  handler: async (ctx, args): Promise<NotificationOutcome> => {
    const seen = await ctx.db
      .query("appStoreNotifications")
      .withIndex("by_notificationUUID", (q) => q.eq("notificationUUID", args.notificationUUID))
      .unique();
    if (seen !== null) {
      return "duplicate";
    }
    await ctx.db.insert("appStoreNotifications", {
      notificationUUID: args.notificationUUID,
      notificationType: args.notificationType,
      receivedAt: Date.now(),
    });
    const facts = args.transaction;
    if (facts === undefined) {
      return "no_transaction";
    }
    const existing = await ctx.db
      .query("entitlements")
      .withIndex("by_originalTransactionId", (q) => q.eq("originalTransactionId", facts.originalTransactionId))
      .unique();
    if (existing !== null && existing.lastSignedAt > facts.signedAt) {
      return "stale";
    }
    let ownerId = existing?.ownerId;
    if (ownerId === undefined && facts.appAccountToken !== undefined) {
      ownerId = (await ownerOfToken(ctx, facts.appAccountToken)) ?? undefined;
    }
    await upsert(ctx, existing, ownerId, facts, args.gracePeriodExpiresAt);
    return "applied";
  },
});

/** The notification facts an HTTP delivery hands `applyNotification`. */
export function notificationArgs(facts: NotificationFacts) {
  return {
    notificationUUID: facts.notificationUUID,
    notificationType: facts.notificationType,
    ...(facts.transaction === undefined ? {} : { transaction: facts.transaction }),
    ...(facts.gracePeriodExpiresAt === undefined ? {} : { gracePeriodExpiresAt: facts.gracePeriodExpiresAt }),
  };
}

async function upsert(
  ctx: MutationCtx,
  existing: Doc<"entitlements"> | null,
  ownerId: string | undefined,
  facts: TransactionFacts,
  gracePeriodExpiresAt: number | undefined,
): Promise<void> {
  const row = {
    originalTransactionId: facts.originalTransactionId,
    productId: facts.productId,
    environment: facts.environment,
    expiresAt: facts.expiresAt,
    lastSignedAt: Math.max(existing?.lastSignedAt ?? 0, facts.signedAt),
    updatedAt: Date.now(),
    ...(ownerId === undefined ? {} : { ownerId }),
    ...(facts.revokedAt === undefined ? {} : { revokedAt: facts.revokedAt }),
    // A grace period belongs to the period it extends: a renewal past it clears it.
    ...(gracePeriodExpiresAt === undefined || gracePeriodExpiresAt <= facts.expiresAt ? {} : { gracePeriodExpiresAt }),
  };
  if (existing === null) {
    await ctx.db.insert("entitlements", row);
  } else {
    await ctx.db.replace(existing._id, row);
  }
}

async function ownerOfToken(ctx: QueryCtx, token: string): Promise<string | null> {
  const row = await ctx.db
    .query("appAccountTokens")
    .withIndex("by_token", (q) => q.eq("token", token.toLowerCase()))
    .first();
  return row?.ownerId ?? null;
}

async function isLiveAccount(ctx: QueryCtx, ownerId: string): Promise<boolean> {
  const account = await findAccount(ctx, ownerId);
  return account !== null && account.deletionStartedAt === undefined;
}

/** How long a processed notification id is kept to recognise Apple's retries. */
export const NOTIFICATION_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/** Sweeps processed-notification ids older than the retention window, a bounded batch per run. */
export const reclaimNotifications = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - NOTIFICATION_RETENTION_MS;
    const expired = await ctx.db
      .query("appStoreNotifications")
      .withIndex("by_receivedAt", (q) => q.lt("receivedAt", cutoff))
      .take(500);
    for (const row of expired) {
      await ctx.db.delete(row._id);
    }
    return expired.length;
  },
});

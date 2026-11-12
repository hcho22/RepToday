import { ConvexError } from "convex/values";
import type { Auth } from "convex/server";
import type { Doc } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";

/**
 * The one way an account-data function learns whose data it may touch (M3, ADR-0016).
 *
 * Every public account function starts with `requireOwner`, which reads the caller's identity as
 * Convex verified it from the Clerk session token (`convex/auth.config.ts`). Nothing else decides
 * ownership: no function takes an owner, user or account id as an argument, and every read and write
 * is scoped by the `ownerId` returned here. So a caller can never name, read or overwrite a row that
 * belongs to someone else - not by guessing a record id, and not by sending another user's id.
 */

/** The authenticated caller, as the account tables key it. */
export type Owner = {
  /** `identity.tokenIdentifier` (`<issuer>|<subject>`): the `ownerId` on every row. */
  ownerId: string;
  /** `identity.subject`: the Clerk user id, needed only to delete the Clerk user. */
  clerkUserId: string;
};

/**
 * The closed set of refusals an account function raises, as `ConvexError` data so a client can
 * tell an expected refusal from an outage.
 */
export type AccountErrorCode =
  /** No valid Clerk session token reached the function. */
  | "unauthenticated"
  /** Account deletion has started; nothing more is written for this owner. */
  | "account_deleting"
  /** A change was malformed or over a size limit. */
  | "invalid_change"
  /** The deployment has no Clerk secret key, so the Clerk user cannot be deleted. */
  | "deletion_unavailable";

export function accountError(code: AccountErrorCode, message: string): ConvexError<{ code: AccountErrorCode; message: string }> {
  return new ConvexError({ code, message });
}

/** The caller's identity, or an `unauthenticated` refusal. */
export async function requireOwner(ctx: { auth: Auth }): Promise<Owner> {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw accountError("unauthenticated", "Sign in to reach your account data.");
  }
  return { ownerId: identity.tokenIdentifier, clerkUserId: identity.subject };
}

/** The owner's account row, if one exists yet. */
export async function findAccount(ctx: QueryCtx, ownerId: string): Promise<Doc<"users"> | null> {
  return await ctx.db
    .query("users")
    .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
    .unique();
}

/**
 * The owner's account row for a write: created on the first write, and refused once deletion has
 * started, so a device that is still syncing cannot put data back while the account is going away.
 * The marked row stays until Clerk has confirmed the user is deleted and every session token issued
 * before then has expired (`convex/accounts.ts`), so no write can recreate it.
 */
export async function writableAccount(ctx: MutationCtx, owner: Owner): Promise<Doc<"users">> {
  const existing = await findAccount(ctx, owner.ownerId);
  if (existing !== null) {
    if (existing.deletionStartedAt !== undefined) {
      throw accountError("account_deleting", "This account is being deleted.");
    }
    return existing;
  }
  const id = await ctx.db.insert("users", {
    ownerId: owner.ownerId,
    clerkUserId: owner.clerkUserId,
    createdAt: Date.now(),
    changeSeq: 0,
  });
  const created = await ctx.db.get(id);
  if (created === null) {
    throw new Error("account row vanished inside its own transaction");
  }
  return created;
}

import { v } from "convex/values";
import { action, internalMutation, type MutationCtx } from "./_generated/server";
import { internal } from "./_generated/api";
import { accountError, findAccount, requireOwner } from "./ownership";

/**
 * Account deletion (M3, US-AU05, ADR-0016): removes every row the caller owns and the Clerk user.
 *
 * Only the signed-in owner can start it, and only for themselves: the action reads the owner from
 * the verified session token and passes it to internal functions no client can call.
 *
 * The order is what makes it safe to repeat and impossible to half-finish silently:
 *
 * 1. `beginDeletion` marks the account (`users.deletionStartedAt`), which makes every later write for
 *    this owner fail, and schedules `finishDeletion` for `DELETION_GRACE_MS` later. Both commit in
 *    one transaction, so the finishing job exists whenever the mark does.
 * 2. The Clerk user is deleted through Clerk's Backend API with the deployment's `CLERK_SECRET_KEY`.
 *    A 404 means an earlier attempt already deleted it. If Clerk fails, `cancelDeletion` clears the
 *    mark - the scheduled job then finds a different (or no) deletion and does nothing - and the
 *    action throws, so nothing was deleted and the caller can try again.
 * 3. `purgeData` removes the owner's rows straight away, in batches.
 * 4. `finishDeletion` runs after the grace period, once every session token issued before the Clerk
 *    user was deleted has expired (Clerk session tokens live about a minute). It removes anything a
 *    still-valid token wrote in the meantime - none can, because the mark refuses writes - and then
 *    the account row itself, so nothing about the owner is left.
 *
 * Steps 3 and 4 run on the server, so once Clerk has deleted the user the deletion completes even if
 * the phone goes offline or is wiped straight after.
 */

/** How long after the Clerk user is deleted the account row itself is removed. */
export const DELETION_GRACE_MS = 10 * 60 * 1000;

/** Rows removed per table per transaction; larger accounts continue in a scheduled follow-up. */
export const PURGE_BATCH = 200;

/** Clerk's Backend API origin. Overridable only so a test can point it elsewhere. */
const CLERK_API_ORIGIN = "https://api.clerk.com";

/**
 * Convex exposes deployment environment variables on `process.env`; the deploy tsconfig pulls in no
 * `@types/node`, so it is declared here exactly as `http.ts` declares it.
 */
declare const process: { readonly env: Readonly<Record<string, string | undefined>> };

/** Every table that holds rows owned by an account, other than `users` itself. */
const OWNED_TABLES = [
  "profiles",
  "focusAreas",
  "workoutLogs",
  "outsideActivities",
  "sessionPolicies",
  "customWorkouts",
  "coachMemory",
] as const;

/**
 * Delete the caller's account: their Convex data and their Clerk user. Resolves once the Clerk user
 * is gone and the data purge has run; the account row follows after `DELETION_GRACE_MS`.
 */
export const deleteAccount = action({
  args: {},
  handler: async (ctx): Promise<{ deleted: true }> => {
    const owner = await requireOwner(ctx);
    const secret = process.env.CLERK_SECRET_KEY;
    if (secret === undefined || secret.length === 0) {
      // Checked before anything is marked, so a misconfigured deployment changes nothing.
      throw accountError("deletion_unavailable", "Account deletion is not configured on this deployment.");
    }

    const startedAt: number = await ctx.runMutation(internal.accounts.beginDeletion, owner);
    try {
      await deleteClerkUser(owner.clerkUserId, secret);
    } catch (error) {
      await ctx.runMutation(internal.accounts.cancelDeletion, { ownerId: owner.ownerId, startedAt });
      throw accountError("deletion_failed", "We couldn't delete your account. Nothing was deleted.");
    }
    await ctx.runMutation(internal.accounts.purgeData, { ownerId: owner.ownerId, startedAt });
    return { deleted: true };
  },
});

/**
 * Deletes the Clerk user. 200 is success and 404 means it is already gone; anything else, or a
 * network failure, throws.
 */
async function deleteClerkUser(clerkUserId: string, secret: string): Promise<void> {
  const origin = process.env.CLERK_API_ORIGIN ?? CLERK_API_ORIGIN;
  const response = await fetch(`${origin}/v1/users/${encodeURIComponent(clerkUserId)}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${secret}` },
  });
  if (response.ok || response.status === 404) {
    return;
  }
  throw new Error(`Clerk user deletion failed with status ${response.status}`);
}

/**
 * Marks the account as being deleted and schedules the job that finishes it. Keeps the first mark
 * when one is already in place, so a repeated request continues that deletion. Returns the mark.
 */
export const beginDeletion = internalMutation({
  args: { ownerId: v.string(), clerkUserId: v.string() },
  handler: async (ctx, { ownerId, clerkUserId }) => {
    const existing = await findAccount(ctx, ownerId);
    if (existing?.deletionStartedAt !== undefined) {
      return existing.deletionStartedAt;
    }
    const startedAt = Date.now();
    if (existing === null) {
      await ctx.db.insert("users", { ownerId, clerkUserId, createdAt: startedAt, changeSeq: 0, deletionStartedAt: startedAt });
    } else {
      await ctx.db.patch(existing._id, { deletionStartedAt: startedAt });
    }
    await ctx.scheduler.runAfter(DELETION_GRACE_MS, internal.accounts.finishDeletion, { ownerId, startedAt });
    return startedAt;
  },
});

/** Clears a mark Clerk could not act on, so the account carries on as if deletion was never asked. */
export const cancelDeletion = internalMutation({
  args: { ownerId: v.string(), startedAt: v.number() },
  handler: async (ctx, { ownerId, startedAt }) => {
    const account = await findAccount(ctx, ownerId);
    if (account !== null && account.deletionStartedAt === startedAt) {
      await ctx.db.patch(account._id, { deletionStartedAt: undefined });
    }
  },
});

/** Removes the owner's data rows, continuing in follow-up transactions until none are left. */
export const purgeData = internalMutation({
  args: { ownerId: v.string(), startedAt: v.number() },
  handler: async (ctx, { ownerId, startedAt }) => {
    const account = await findAccount(ctx, ownerId);
    if (account === null || account.deletionStartedAt !== startedAt) {
      return;
    }
    if (await purgeBatch(ctx, ownerId)) {
      await ctx.scheduler.runAfter(0, internal.accounts.purgeData, { ownerId, startedAt });
    }
  },
});

/**
 * The deletion's last step: removes any data rows left, then the account row. A job whose mark was
 * cancelled (or replaced by a later deletion) does nothing.
 */
export const finishDeletion = internalMutation({
  args: { ownerId: v.string(), startedAt: v.number() },
  handler: async (ctx, { ownerId, startedAt }) => {
    const account = await findAccount(ctx, ownerId);
    if (account === null || account.deletionStartedAt !== startedAt) {
      return;
    }
    if (await purgeBatch(ctx, ownerId)) {
      await ctx.scheduler.runAfter(0, internal.accounts.finishDeletion, { ownerId, startedAt });
      return;
    }
    await ctx.db.delete(account._id);
  },
});

/** Deletes up to `PURGE_BATCH` of the owner's rows from each owned table. Returns whether any remain. */
async function purgeBatch(ctx: MutationCtx, ownerId: string): Promise<boolean> {
  let remaining = false;
  for (const table of OWNED_TABLES) {
    const rows =
      table === "profiles" || table === "focusAreas" || table === "sessionPolicies"
        ? await ctx.db
            .query(table)
            .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
            .take(PURGE_BATCH + 1)
        : await ctx.db
            .query(table)
            .withIndex("by_ownerId_recordId", (q) => q.eq("ownerId", ownerId))
            .take(PURGE_BATCH + 1);
    for (const row of rows.slice(0, PURGE_BATCH)) {
      await ctx.db.delete(row._id);
    }
    remaining ||= rows.length > PURGE_BATCH;
  }
  return remaining;
}

import { v } from "convex/values";
import { action, internalAction, internalMutation, internalQuery, type MutationCtx } from "./_generated/server";
import { internal } from "./_generated/api";
import { accountError, findAccount, requireOwner } from "./ownership";

/**
 * Account deletion (M3, US-AU05, ADR-0016): removes every row the caller owns and the Clerk user.
 *
 * Only the signed-in owner can start it, and only for themselves: the action reads the owner from
 * the verified session token and passes it to internal functions no client can call.
 *
 * Once the account is marked, the deletion is committed: nothing cancels it, and it finishes on the
 * server even if the phone goes offline or is wiped straight after.
 *
 * 1. `beginDeletion` marks the account (`users.deletionStartedAt`), which makes every later write and
 *    read for this owner fail, and schedules `continueDeletion`. Both commit in one transaction, so
 *    the job that finishes the deletion exists whenever the mark does.
 * 2. The action deletes the Clerk user through Clerk's Backend API with the deployment's
 *    `CLERK_SECRET_KEY`. A 404 means it is already gone; when the request fails, the action asks
 *    Clerk whether the user still exists, because a lost response or a second device's deletion can
 *    mean it is already gone. Every attempt is recorded on the account row (`recordClerkAttempt`).
 * 3. `purgeData` removes the owner's rows straight away, in batches, whatever Clerk answered.
 * 4. `continueDeletion` retries the Clerk deletion on a growing, capped back-off
 *    (`CLERK_RETRY_DELAYS_MS`) until Clerk confirms the user is gone. `DELETION_GRACE_MS` after that
 *    confirmation, once every session token issued before it has expired (Clerk session tokens live
 *    about a minute), `finishDeletion` removes anything left and then the account row itself. Until
 *    then the marked row stays, so a still-linked phone is refused and can never recreate the account.
 */

/** How long after Clerk confirms the user is deleted the account row itself is removed. */
export const DELETION_GRACE_MS = 10 * 60 * 1000;

/** The waits between retries of the Clerk deletion; the last one repeats until Clerk confirms. */
export const CLERK_RETRY_DELAYS_MS = [60 * 1000, 5 * 60 * 1000, 30 * 60 * 1000, 2 * 60 * 60 * 1000, 6 * 60 * 60 * 1000];

/** Rows removed per table per transaction; larger accounts continue in a scheduled follow-up. */
export const PURGE_BATCH = 200;

/** Clerk's Backend API origin. */
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

/** Whether the Clerk user is gone, still exists, or could not be found out. */
const clerkUserState = v.union(v.literal("gone"), v.literal("exists"), v.literal("unknown"));
type ClerkUserState = "gone" | "exists" | "unknown";

/**
 * Delete the caller's account: their Convex data and their Clerk user. Resolves once the deletion is
 * committed and the data purge has run. `clerkUserDeleted` says whether Clerk has confirmed the user
 * is gone; when it has not, the server keeps retrying until it does.
 */
export const deleteAccount = action({
  args: {},
  handler: async (ctx): Promise<{ deleted: true; clerkUserDeleted: boolean }> => {
    const owner = await requireOwner(ctx);
    const secret = clerkSecret();
    if (secret === undefined) {
      // Checked before anything is marked, so a misconfigured deployment changes nothing.
      throw accountError("deletion_unavailable", "Account deletion is not configured on this deployment.");
    }

    await ctx.runMutation(internal.accounts.beginDeletion, owner);
    const outcome = await deleteClerkUser(owner.clerkUserId, secret);
    const clerkUserDeleted: boolean = await ctx.runMutation(internal.accounts.recordClerkAttempt, {
      ownerId: owner.ownerId,
      outcome,
    });
    await ctx.runMutation(internal.accounts.purgeData, { ownerId: owner.ownerId });
    return { deleted: true, clerkUserDeleted };
  },
});

function clerkSecret(): string | undefined {
  const secret = process.env.CLERK_SECRET_KEY;
  return secret === undefined || secret.length === 0 ? undefined : secret;
}

/**
 * Deletes the Clerk user. 200 is success and 404 means it is already gone. When the request fails -
 * a refusal, or a network failure that may have lost Clerk's answer - Clerk is asked whether the user
 * still exists.
 */
async function deleteClerkUser(clerkUserId: string, secret: string): Promise<ClerkUserState> {
  try {
    const response = await fetch(clerkUserURL(clerkUserId), {
      method: "DELETE",
      headers: { Authorization: `Bearer ${secret}` },
    });
    if (response.ok || response.status === 404) {
      return "gone";
    }
  } catch {
    // Clerk may have acted before the connection failed; the lookup below finds out.
  }
  return await lookUpClerkUser(clerkUserId, secret);
}

/** Asks Clerk whether the user exists: 404 means gone, 200 means it exists, anything else is unknown. */
async function lookUpClerkUser(clerkUserId: string, secret: string): Promise<ClerkUserState> {
  try {
    const response = await fetch(clerkUserURL(clerkUserId), {
      method: "GET",
      headers: { Authorization: `Bearer ${secret}` },
    });
    if (response.status === 404) {
      return "gone";
    }
    if (response.ok) {
      return "exists";
    }
  } catch {
    // Unreachable: neither answer is known.
  }
  return "unknown";
}

function clerkUserURL(clerkUserId: string): string {
  return `${CLERK_API_ORIGIN}/v1/users/${encodeURIComponent(clerkUserId)}`;
}

/**
 * Marks the account as being deleted and schedules the job that finishes it. Keeps the first mark
 * when one is already in place, so a repeated request continues that deletion.
 */
export const beginDeletion = internalMutation({
  args: { ownerId: v.string(), clerkUserId: v.string() },
  handler: async (ctx, { ownerId, clerkUserId }) => {
    const existing = await findAccount(ctx, ownerId);
    if (existing?.deletionStartedAt !== undefined) {
      return;
    }
    const startedAt = Date.now();
    if (existing === null) {
      await ctx.db.insert("users", { ownerId, clerkUserId, createdAt: startedAt, changeSeq: 0, deletionStartedAt: startedAt });
    } else {
      await ctx.db.patch(existing._id, { deletionStartedAt: startedAt });
    }
    await ctx.scheduler.runAfter(CLERK_RETRY_DELAYS_MS[0], internal.accounts.continueDeletion, { ownerId });
  },
});

/**
 * Records one attempt to delete the Clerk user, and the moment Clerk first confirmed it is gone.
 * Returns whether Clerk has confirmed it.
 */
export const recordClerkAttempt = internalMutation({
  args: { ownerId: v.string(), outcome: clerkUserState },
  handler: async (ctx, { ownerId, outcome }) => {
    const account = await findAccount(ctx, ownerId);
    if (account === null || account.deletionStartedAt === undefined) {
      return false;
    }
    const now = Date.now();
    const clerkUserDeletedAt = account.clerkUserDeletedAt ?? (outcome === "gone" ? now : undefined);
    await ctx.db.patch(account._id, {
      clerkDeletionAttempts: (account.clerkDeletionAttempts ?? 0) + 1,
      clerkDeletionLastAttemptAt: now,
      clerkDeletionLastOutcome: outcome,
      clerkUserDeletedAt,
    });
    return clerkUserDeletedAt !== undefined;
  },
});

/** Where a committed deletion stands, or `null` when there is none for this owner. */
export const deletionState = internalQuery({
  args: { ownerId: v.string() },
  handler: async (ctx, { ownerId }) => {
    const account = await findAccount(ctx, ownerId);
    if (account === null || account.deletionStartedAt === undefined) {
      return null;
    }
    return {
      clerkUserId: account.clerkUserId,
      clerkUserDeletedAt: account.clerkUserDeletedAt ?? null,
      attempts: account.clerkDeletionAttempts ?? 0,
    };
  },
});

/**
 * The scheduled half of a committed deletion: retries the Clerk deletion until Clerk confirms it,
 * then, once the grace period after that confirmation has passed, finishes the deletion.
 */
export const continueDeletion = internalAction({
  args: { ownerId: v.string() },
  handler: async (ctx, { ownerId }) => {
    const state = await ctx.runQuery(internal.accounts.deletionState, { ownerId });
    if (state === null) {
      return;
    }
    let confirmedAt = state.clerkUserDeletedAt;
    if (confirmedAt === null) {
      const secret = clerkSecret();
      const outcome = secret === undefined ? "unknown" : await deleteClerkUser(state.clerkUserId, secret);
      const confirmed: boolean = await ctx.runMutation(internal.accounts.recordClerkAttempt, { ownerId, outcome });
      if (!confirmed) {
        const attempts = state.attempts + 1;
        const delay = CLERK_RETRY_DELAYS_MS[Math.min(attempts, CLERK_RETRY_DELAYS_MS.length) - 1];
        await ctx.scheduler.runAfter(delay, internal.accounts.continueDeletion, { ownerId });
        return;
      }
      confirmedAt = Date.now();
    }
    const wait = confirmedAt + DELETION_GRACE_MS - Date.now();
    if (wait > 0) {
      await ctx.scheduler.runAfter(wait, internal.accounts.continueDeletion, { ownerId });
      return;
    }
    await ctx.runMutation(internal.accounts.finishDeletion, { ownerId });
  },
});

/** Removes the owner's data rows of a committed deletion, continuing until none are left. */
export const purgeData = internalMutation({
  args: { ownerId: v.string() },
  handler: async (ctx, { ownerId }) => {
    const account = await findAccount(ctx, ownerId);
    if (account === null || account.deletionStartedAt === undefined) {
      return;
    }
    if (await purgeBatch(ctx, ownerId)) {
      await ctx.scheduler.runAfter(0, internal.accounts.purgeData, { ownerId });
    }
  },
});

/**
 * The deletion's last step, once Clerk has confirmed the user is gone and the grace period has
 * passed: removes any data rows left, then the account row.
 */
export const finishDeletion = internalMutation({
  args: { ownerId: v.string() },
  handler: async (ctx, { ownerId }) => {
    const account = await findAccount(ctx, ownerId);
    if (account === null || account.deletionStartedAt === undefined || account.clerkUserDeletedAt === undefined) {
      return;
    }
    if (await purgeBatch(ctx, ownerId)) {
      await ctx.scheduler.runAfter(0, internal.accounts.finishDeletion, { ownerId });
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

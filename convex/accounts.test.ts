import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";
import { api, internal } from "./_generated/api";
import { CLERK_REQUEST_TIMEOUT_MS, CLERK_RETRY_DELAYS_MS, DELETION_GRACE_MS, PURGE_BATCH } from "./accounts";
import type { SyncChange } from "./sync";

/**
 * Behavioural coverage of account deletion (M3, US-AU05): `accounts:deleteAccount` removes the
 * caller's Convex data and their Clerk user, finishes once committed even while Clerk is unreachable, and is safe to repeat.
 *
 * Clerk's Backend API is replaced with a recorded `fetch` stub, so nothing leaves the process.
 */

declare const process: { env: Record<string, string | undefined> };

const modules: Record<string, () => Promise<any>> = Object.fromEntries(
  Object.entries({
    ...import.meta.glob("./**/*.ts"),
    ...import.meta.glob("./**/*.js"),
  }).filter(([path]) => !path.endsWith(".d.ts") && !path.endsWith(".test.ts")),
);

const ALICE = { subject: "user_alice", tokenIdentifier: "https://clerk.test|user_alice", issuer: "https://clerk.test" };
const BOB = { subject: "user_bob", tokenIdentifier: "https://clerk.test|user_bob", issuer: "https://clerk.test" };
const TEST_CLERK_SECRET = "sk_test_stand_in_value";

const OWNED_TABLES = [
  "profiles",
  "focusAreas",
  "workoutLogs",
  "outsideActivities",
  "sessionPolicies",
  "customWorkouts",
  "coachMemory",
] as const;

let clerkRequests: { url: string; method: string; authorization: string | null }[];
let clerkStatus: number;
let clerkLookupStatus: number;
let originalSecret: string | undefined;

beforeEach(() => {
  vi.useFakeTimers();
  originalSecret = process.env.CLERK_SECRET_KEY;
  process.env.CLERK_SECRET_KEY = TEST_CLERK_SECRET;
  clerkRequests = [];
  clerkStatus = 200;
  clerkLookupStatus = 200;
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: string, init?: RequestInit) => {
      const method = init?.method ?? "GET";
      clerkRequests.push({
        url: input,
        method,
        authorization: new Headers(init?.headers).get("Authorization"),
      });
      return new Response(null, { status: method === "DELETE" ? clerkStatus : clerkLookupStatus });
    }),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
  if (originalSecret === undefined) {
    delete process.env.CLERK_SECRET_KEY;
  } else {
    process.env.CLERK_SECRET_KEY = originalSecret;
  }
});

function changes(count = 2): SyncChange[] {
  return [
    { table: "profile", recordId: "local-user-1", clientUpdatedAt: 1, payload: '{"displayName":"Riley"}', focusAreas: ["abs"] },
    { table: "sessionPolicy", recordId: "local-user-1", clientUpdatedAt: 1, payload: "{}" },
    { table: "outsideActivity", recordId: "A1", clientUpdatedAt: 1, deleted: false, payload: "{}", date: 1 },
    ...Array.from(
      { length: count },
      (_, i): SyncChange => ({ table: "workoutLog", recordId: `L${i}`, clientUpdatedAt: 1, deleted: false, payload: "{}", completedAt: 1 }),
    ),
  ];
}

/** Seeds the M4 tables directly: no public function writes them yet. */
async function seedFutureTables(t: ReturnType<typeof convexTest>, ownerId: string) {
  await t.run(async (ctx) => {
    for (const table of ["customWorkouts", "coachMemory"] as const) {
      await ctx.db.insert(table, { ownerId, recordId: "R1", serverSeq: 99, clientUpdatedAt: 1, deleted: false, payload: "{}" });
    }
  });
}

async function ownedRowCount(t: ReturnType<typeof convexTest>, ownerId: string) {
  return await t.run(async (ctx) => {
    let total = 0;
    for (const table of OWNED_TABLES) {
      total += (await ctx.db.query(table).collect()).filter((row) => row.ownerId === ownerId).length;
    }
    return total;
  });
}

async function account(t: ReturnType<typeof convexTest>, ownerId: string) {
  return await t.run(async (ctx) => (await ctx.db.query("users").collect()).find((row) => row.ownerId === ownerId) ?? null);
}

async function expectRefusal(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toSatisfy((error: any) => error?.data?.code === code);
}

describe("deleteAccount", () => {
  test("deletes the caller's Clerk user, then all their data, then the account row", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    await seedFutureTables(t, ALICE.tokenIdentifier);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(8);

    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true, clerkUserDeleted: true });

    expect(clerkRequests).toEqual([
      { url: "https://api.clerk.com/v1/users/user_alice", method: "DELETE", authorization: `Bearer ${TEST_CLERK_SECRET}` },
    ]);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    // The account row stays, marked, through the grace period, so a token issued before the Clerk user
    // was deleted still cannot write anything back.
    expect((await account(t, ALICE.tokenIdentifier))?.deletionStartedAt).toBeDefined();
    await expectRefusal(t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() }), "account_deleting");

    vi.advanceTimersByTime(DELETION_GRACE_MS);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
  });

  test("never touches another user's data", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    await t.withIdentity(BOB).mutation(api.sync.push, { changes: changes() });
    await seedFutureTables(t, BOB.tokenIdentifier);

    await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);

    expect(await ownedRowCount(t, BOB.tokenIdentifier)).toBe(8);
    expect(await account(t, BOB.tokenIdentifier)).not.toBeNull();
    expect(clerkRequests.map((request) => request.url)).toEqual(["https://api.clerk.com/v1/users/user_alice"]);
  });

  test("is safe to repeat: a Clerk user already gone (404) still completes", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {});
    clerkStatus = 404;
    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true, clerkUserDeleted: true });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
  });

  test("Clerk unreachable, then recovering: the deletion is committed and finishes on its own", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    let clerkReachable = false;
    const methods: string[] = [];
    vi.stubGlobal("fetch", vi.fn(async (_input: string, init?: RequestInit) => {
      methods.push(init?.method ?? "GET");
      if (!clerkReachable) {
        throw new TypeError("network down");
      }
      return new Response(null, { status: 200 });
    }));

    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true, clerkUserDeleted: false });

    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    const pending = await account(t, ALICE.tokenIdentifier);
    expect(pending?.deletionStartedAt).toBeDefined();
    expect(pending?.clerkDeletionAttempts).toBe(1);
    expect(pending?.clerkDeletionLastOutcome).toBe("unknown");
    expect(pending?.clerkUserDeletedAt).toBeUndefined();

    clerkReachable = true;
    vi.advanceTimersByTime(CLERK_RETRY_DELAYS_MS[0]);
    await t.finishInProgressScheduledFunctions();
    const confirmed = await account(t, ALICE.tokenIdentifier);
    expect(confirmed?.clerkDeletionAttempts).toBe(2);
    expect(confirmed?.clerkDeletionLastOutcome).toBe("gone");
    expect(confirmed?.clerkUserDeletedAt).toBeDefined();
    expect(methods).toEqual(["DELETE", "GET", "DELETE"]);

    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
  });

  test("Clerk never recovering: the server keeps retrying on a capped back-off and keeps the account closed", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    clerkStatus = 500;

    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true, clerkUserDeleted: false });

    const attemptTimes: number[] = [];
    for (let step = 0; step < CLERK_RETRY_DELAYS_MS.length + 2; step += 1) {
      vi.advanceTimersByTime(CLERK_RETRY_DELAYS_MS[Math.min(step, CLERK_RETRY_DELAYS_MS.length - 1)]);
      await t.finishInProgressScheduledFunctions();
      attemptTimes.push((await account(t, ALICE.tokenIdentifier))?.clerkDeletionLastAttemptAt ?? 0);
    }

    const row = await account(t, ALICE.tokenIdentifier);
    expect(row?.clerkDeletionAttempts).toBe(CLERK_RETRY_DELAYS_MS.length + 3);
    expect(row?.clerkDeletionLastOutcome).toBe("exists");
    expect(row?.clerkUserDeletedAt).toBeUndefined();
    const gaps = attemptTimes.slice(1).map((time, i) => time - attemptTimes[i]);
    const longest = CLERK_RETRY_DELAYS_MS[CLERK_RETRY_DELAYS_MS.length - 1];
    expect(gaps).toEqual([...CLERK_RETRY_DELAYS_MS.slice(1), longest, longest]);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    await expectRefusal(t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() }), "account_deleting");
  });

  test("a linked phone writing during a pending deletion is refused and never rebuilds the account", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    clerkStatus = 503;
    clerkLookupStatus = 503;
    await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {});

    vi.advanceTimersByTime(DELETION_GRACE_MS + CLERK_RETRY_DELAYS_MS[0] + CLERK_RETRY_DELAYS_MS[1]);
    await t.finishInProgressScheduledFunctions();

    await expectRefusal(t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() }), "account_deleting");
    await expectRefusal(t.withIdentity(ALICE).query(api.sync.pull, { since: 0 }), "account_deleting");
    const rows = await t.run(async (ctx) => (await ctx.db.query("users").collect()).filter((row) => row.ownerId === ALICE.tokenIdentifier));
    expect(rows).toHaveLength(1);
    expect(rows[0].deletionStartedAt).toBeDefined();
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
  });

  test("a hanging Clerk is given up on, so the action answers inside the app's request limit", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    vi.stubGlobal("fetch", vi.fn((_input: string, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      }),
    ));

    const answer = t.withIdentity(ALICE).action(api.accounts.deleteAccount, {});
    await vi.advanceTimersByTimeAsync(CLERK_REQUEST_TIMEOUT_MS);
    await vi.advanceTimersByTimeAsync(CLERK_REQUEST_TIMEOUT_MS);

    expect(await answer).toEqual({ deleted: true, clerkUserDeleted: false });
    expect(CLERK_REQUEST_TIMEOUT_MS * 2).toBeLessThan(30_000);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    expect((await account(t, ALICE.tokenIdentifier))?.clerkDeletionLastOutcome).toBe("unknown");
  });

  test("a deletion whose action failed after marking still purges and finishes", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    // The state an action leaves when it throws straight after `beginDeletion`.
    await t.mutation(internal.accounts.beginDeletion, { ownerId: ALICE.tokenIdentifier, clerkUserId: ALICE.subject });
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(6);

    vi.advanceTimersByTime(CLERK_RETRY_DELAYS_MS[0]);
    await t.finishInProgressScheduledFunctions();

    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    expect((await account(t, ALICE.tokenIdentifier))?.clerkUserDeletedAt).toBeDefined();
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });

  test("completes when Clerk deleted the user but the response was lost", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    const methods: string[] = [];
    vi.stubGlobal("fetch", vi.fn(async (_input: string, init?: RequestInit) => {
      methods.push(init?.method ?? "GET");
      if (init?.method === "DELETE") {
        throw new TypeError("connection reset after the request was sent");
      }
      return new Response(null, { status: 404 });
    }));

    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true, clerkUserDeleted: true });

    expect(methods).toEqual(["DELETE", "GET"]);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });

  test("a second device's request while the first is pending continues the same deletion", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    clerkStatus = 500;
    await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {});
    const startedAt = (await account(t, ALICE.tokenIdentifier))?.deletionStartedAt;

    clerkStatus = 200;
    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true, clerkUserDeleted: true });

    expect((await account(t, ALICE.tokenIdentifier))?.deletionStartedAt).toBe(startedAt);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });

  test("changes nothing on a deployment with no Clerk secret key", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    delete process.env.CLERK_SECRET_KEY;
    await expectRefusal(t.withIdentity(ALICE).action(api.accounts.deleteAccount, {}), "deletion_unavailable");
    expect(clerkRequests).toHaveLength(0);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(6);
    expect((await account(t, ALICE.tokenIdentifier))?.deletionStartedAt).toBeUndefined();
  });

  test("a large account is purged across several transactions", async () => {
    const t = convexTest(schema, modules);
    const total = PURGE_BATCH * 2 + 7;
    await t.run(async (ctx) => {
      await ctx.db.insert("users", { ownerId: ALICE.tokenIdentifier, clerkUserId: ALICE.subject, createdAt: 1, changeSeq: total });
      for (let i = 0; i < total; i += 1) {
        await ctx.db.insert("workoutLogs", {
          ownerId: ALICE.tokenIdentifier,
          recordId: `L${i}`,
          serverSeq: i + 1,
          clientUpdatedAt: 1,
          deleted: false,
          payload: "{}",
          completedAt: 1,
        });
      }
    });
    await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });

  test("a signed-in caller with no data yet can still delete their Clerk user", async () => {
    const t = convexTest(schema, modules);
    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true, clerkUserDeleted: true });
    expect(clerkRequests).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });
});

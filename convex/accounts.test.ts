import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import { DELETION_GRACE_MS, PURGE_BATCH } from "./accounts";
import type { SyncChange } from "./sync";

/**
 * Behavioural coverage of account deletion (M3, US-AU05): `accounts:deleteAccount` removes the
 * caller's Convex data and their Clerk user, refuses to half-finish, and is safe to repeat.
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

    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true });

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
    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
  });

  test("deletes nothing when Clerk fails, and the account carries on", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    clerkStatus = 500;

    await expectRefusal(t.withIdentity(ALICE).action(api.accounts.deleteAccount, {}), "deletion_failed");

    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(6);
    expect((await account(t, ALICE.tokenIdentifier))?.deletionStartedAt).toBeUndefined();
    // The finishing job scheduled with the cancelled mark does nothing when it fires.
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).not.toBeNull();
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(6);
    const push = await t.withIdentity(ALICE).mutation(api.sync.push, {
      changes: [{ table: "workoutLog", recordId: "L9", clientUpdatedAt: 2, deleted: false, payload: "{}", completedAt: 2 }],
    });
    expect(push.results[0].outcome).toBe("applied");
  });

  test("deletes nothing when the delete request is lost but Clerk still has the user", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    vi.stubGlobal("fetch", vi.fn(async (_input: string, init?: RequestInit) => {
      if (init?.method === "DELETE") {
        throw new TypeError("network down");
      }
      return new Response(null, { status: 200 });
    }));
    await expectRefusal(t.withIdentity(ALICE).action(api.accounts.deleteAccount, {}), "deletion_failed");
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(6);
    expect((await account(t, ALICE.tokenIdentifier))?.deletionStartedAt).toBeUndefined();
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

    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true });

    expect(methods).toEqual(["DELETE", "GET"]);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });

  test("keeps the deletion going when Clerk cannot be reached at all", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    vi.stubGlobal("fetch", vi.fn(async () => {
      throw new TypeError("network down");
    }));

    await expectRefusal(t.withIdentity(ALICE).action(api.accounts.deleteAccount, {}), "deletion_failed");

    // Clerk may already have deleted the user, so the mark stays: nothing more is written, and the
    // scheduled job completes the deletion.
    expect((await account(t, ALICE.tokenIdentifier))?.deletionStartedAt).toBeDefined();
    await expectRefusal(t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() }), "account_deleting");
    vi.advanceTimersByTime(DELETION_GRACE_MS);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });

  test("a concurrent attempt that cancels the shared mark cannot strand a confirmed deletion", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: changes() });
    vi.stubGlobal("fetch", vi.fn(async () => {
      // Another device's attempt saw Clerk refuse and cleared the mark while this request was in flight.
      await t.run(async (ctx) => {
        const row = (await ctx.db.query("users").collect()).find((user) => user.ownerId === ALICE.tokenIdentifier);
        if (row !== undefined) {
          await ctx.db.patch(row._id, { deletionStartedAt: undefined });
        }
      });
      return new Response(null, { status: 200 });
    }));

    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true });

    expect(await ownedRowCount(t, ALICE.tokenIdentifier)).toBe(0);
    vi.advanceTimersByTime(DELETION_GRACE_MS);
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
    expect(await t.withIdentity(ALICE).action(api.accounts.deleteAccount, {})).toEqual({ deleted: true });
    expect(clerkRequests).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await account(t, ALICE.tokenIdentifier)).toBeNull();
  });
});

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import { MAX_CHANGES_PER_PUSH, MAX_PAYLOAD_BYTES, type SyncChange } from "./sync";

/**
 * Behavioural coverage of the account-data sync boundary (M3, US-AU01/US-AU03): `sync:push` and
 * `sync:pull`, run in process against an in-memory database by `convex-test`.
 *
 * The load-bearing assertions are ownership (a caller only ever reaches rows keyed by their own
 * verified identity) and idempotency (a replayed upload never duplicates a row), so most tests read
 * the tables back directly instead of trusting a function's return value.
 */

const modules: Record<string, () => Promise<any>> = Object.fromEntries(
  Object.entries({
    ...import.meta.glob("./**/*.ts"),
    ...import.meta.glob("./**/*.js"),
  }).filter(([path]) => !path.endsWith(".d.ts") && !path.endsWith(".test.ts")),
);

const ALICE = { subject: "user_alice", tokenIdentifier: "https://clerk.test|user_alice", issuer: "https://clerk.test" };
const BOB = { subject: "user_bob", tokenIdentifier: "https://clerk.test|user_bob", issuer: "https://clerk.test" };

const LOG_ID = "7C9E6679-7425-40DE-944B-E07FC1F90AE7";

function log(recordId: string, clientUpdatedAt: number, payload = `{"id":"${recordId}"}`): SyncChange {
  return { table: "workoutLog", recordId, clientUpdatedAt, deleted: false, payload, completedAt: 1_790_000_000_000 };
}

function profile(clientUpdatedAt: number, payload = '{"displayName":"Riley"}', focusAreas = ["chest"]): SyncChange {
  return { table: "profile", recordId: "local-user-1", clientUpdatedAt, payload, focusAreas };
}

async function rows(t: ReturnType<typeof convexTest>, table: "workoutLogs" | "profiles" | "users" | "focusAreas" | "outsideActivities" | "sessionPolicies") {
  return await t.run(async (ctx) => await ctx.db.query(table).collect());
}

async function expectRefusal(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toSatisfy((error: any) => error?.data?.code === code);
}

describe("ownership: every public account function checks the caller", () => {
  test("an unauthenticated push is refused and writes nothing", async () => {
    const t = convexTest(schema, modules);
    await expectRefusal(t.mutation(api.sync.push, { changes: [log(LOG_ID, 1)] }), "unauthenticated");
    expect(await rows(t, "workoutLogs")).toHaveLength(0);
    expect(await rows(t, "users")).toHaveLength(0);
  });

  test("an unauthenticated pull is refused", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 1)] });
    await expectRefusal(t.query(api.sync.pull, { since: 0 }), "unauthenticated");
  });

  test("an unauthenticated account deletion is refused", async () => {
    const t = convexTest(schema, modules);
    await expectRefusal(t.action(api.accounts.deleteAccount, {}), "unauthenticated");
  });

  test("the deployment's public API is exactly the account and Coach functions", async () => {
    // Each public function needs its own ownership check and a refusal test (here, in
    // `entitlements.test.ts` and in `coach.test.ts`). Every other function - deletion's steps, the
    // Coach's reads and writes, the entitlement updates, the telemetry sink - is internal, and the
    // telemetry routes are HTTP actions that never read an identity.
    const exported = await Promise.all(
      Object.keys(modules)
        .filter((path) => !path.includes("_generated"))
        .map(async (path) => [path, await modules[path]()] as const),
    );
    const publicFunctions = exported.flatMap(([path, module]) =>
      Object.entries(module as Record<string, unknown>)
        .filter(([, value]) => (value as { isPublic?: boolean })?.isPublic === true)
        .map(([name]) => `${path.replace("./", "").replace(".ts", "")}:${name}`),
    );
    expect(publicFunctions.sort()).toEqual([
      "accounts:deleteAccount",
      "coach:history",
      "coach:recordProposalOutcome",
      "coach:send",
      "entitlements:appAccountToken",
      "entitlements:linkTransaction",
      "entitlements:status",
      "sync:pull",
      "sync:push",
    ]);
  });

  test("two users with the same record id never see or overwrite each other's rows", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 10, '{"owner":"alice"}')] });
    // Bob writes the same record id later, with a newer timestamp: it must land on his own row.
    const bobPush = await t.withIdentity(BOB).mutation(api.sync.push, { changes: [log(LOG_ID, 20, '{"owner":"bob"}')] });
    expect(bobPush.results[0].outcome).toBe("applied");

    const stored = await rows(t, "workoutLogs");
    expect(stored).toHaveLength(2);
    expect(stored.find((row) => row.ownerId === ALICE.tokenIdentifier)?.payload).toBe('{"owner":"alice"}');
    expect(stored.find((row) => row.ownerId === BOB.tokenIdentifier)?.payload).toBe('{"owner":"bob"}');

    const alicePull = await t.withIdentity(ALICE).query(api.sync.pull, { since: 0 });
    expect(alicePull.changes).toHaveLength(1);
    expect(alicePull.changes[0]).toMatchObject({ recordId: LOG_ID, payload: '{"owner":"alice"}' });
    const bobPull = await t.withIdentity(BOB).query(api.sync.pull, { since: 0 });
    expect(bobPull.changes.map((change) => (change as any).payload)).toEqual(['{"owner":"bob"}']);
  });

  test("a caller cannot pass an owner: extra arguments are rejected by the validator", async () => {
    const t = convexTest(schema, modules);
    await expect(
      t.withIdentity(BOB).query(api.sync.pull, { since: 0, ownerId: ALICE.tokenIdentifier } as any),
    ).rejects.toThrow();
  });
});

describe("push: idempotent by record id, newest change wins", () => {
  test("a first push creates the account row and the record", async () => {
    const t = convexTest(schema, modules);
    const result = await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 1)] });
    expect(result.results).toEqual([{ table: "workoutLog", recordId: LOG_ID, outcome: "applied" }]);
    expect(result.serverSeq).toBe(1);
    const [account] = await rows(t, "users");
    expect(account).toMatchObject({ ownerId: ALICE.tokenIdentifier, clerkUserId: ALICE.subject, changeSeq: 1 });
  });

  test("replaying the same push writes nothing new", async () => {
    const t = convexTest(schema, modules);
    const changes = [log(LOG_ID, 5), profile(5)];
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes });
    const replay = await t.withIdentity(ALICE).mutation(api.sync.push, { changes });
    expect(replay.results.map((r) => r.outcome)).toEqual(["unchanged", "unchanged"]);
    expect(await rows(t, "workoutLogs")).toHaveLength(1);
    expect(await rows(t, "profiles")).toHaveLength(1);
    expect(await rows(t, "focusAreas")).toHaveLength(1);
    expect((await rows(t, "users"))[0].changeSeq).toBe(replay.serverSeq);
  });

  test("an older change is stale and leaves the newer row alone", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 20, '{"v":"new"}')] });
    const older = await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 10, '{"v":"old"}')] });
    expect(older.results[0].outcome).toBe("stale");
    expect((await rows(t, "workoutLogs"))[0].payload).toBe('{"v":"new"}');
  });

  test("a newer change replaces the row in place", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 10, '{"v":1}')] });
    const newer = await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 11, '{"v":2}')] });
    expect(newer.results[0].outcome).toBe("applied");
    const stored = await rows(t, "workoutLogs");
    expect(stored).toHaveLength(1);
    expect(stored[0]).toMatchObject({ payload: '{"v":2}', serverSeq: 2 });
  });

  test("a deletion leaves a tombstone without a payload", async () => {
    const t = convexTest(schema, modules);
    const activity: SyncChange = { table: "outsideActivity", recordId: "A1", clientUpdatedAt: 1, deleted: false, payload: "{}", date: 100 };
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [activity] });
    await t.withIdentity(ALICE).mutation(api.sync.push, {
      changes: [{ table: "outsideActivity", recordId: "A1", clientUpdatedAt: 2, deleted: true }],
    });
    const [stored] = await rows(t, "outsideActivities");
    expect(stored).toMatchObject({ deleted: true, date: 100 });
    expect(stored.payload).toBeUndefined();
    const pulled = await t.withIdentity(ALICE).query(api.sync.pull, { since: 0 });
    expect(pulled.changes).toEqual([{ table: "outsideActivity", recordId: "A1", serverSeq: 2, clientUpdatedAt: 2, deleted: true, date: 100 }]);
  });

  test("an accepted Custom Workout syncs like any other record, owner-scoped and deletable (M4)", async () => {
    const t = convexTest(schema, modules);
    const workout: SyncChange = { table: "customWorkout", recordId: "W1", clientUpdatedAt: 1, deleted: false, payload: '{"title":"Desk Reset"}' };
    expect((await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [workout] })).results[0].outcome).toBe("applied");
    expect((await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [workout] })).results[0].outcome).toBe("unchanged");
    expect((await t.withIdentity(BOB).query(api.sync.pull, { since: 0 })).changes).toEqual([]);
    expect((await t.withIdentity(ALICE).query(api.sync.pull, { since: 0 })).changes).toEqual([
      { table: "customWorkout", recordId: "W1", serverSeq: 1, clientUpdatedAt: 1, deleted: false, payload: '{"title":"Desk Reset"}' },
    ]);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [{ table: "customWorkout", recordId: "W1", clientUpdatedAt: 2, deleted: true }] });
    const stored = await t.run(async (ctx) => await ctx.db.query("customWorkouts").collect());
    expect(stored).toHaveLength(1);
    expect(stored[0]).toMatchObject({ deleted: true, ownerId: ALICE.tokenIdentifier });
    expect(stored[0].payload).toBeUndefined();
    await expectRefusal(
      t.withIdentity(ALICE).mutation(api.sync.push, { changes: [{ table: "customWorkout", recordId: "W2", clientUpdatedAt: 3, deleted: false }] }),
      "invalid_change",
    );
  });

  test("the profile and its Focus Areas are one change per owner", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [profile(1, '{"n":1}', ["chest", "abs"])] });
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [profile(2, '{"n":1}', ["legs"])] });
    expect(await rows(t, "profiles")).toHaveLength(1);
    expect((await rows(t, "focusAreas"))[0].areas).toEqual(["legs"]);
    const pulled = await t.withIdentity(ALICE).query(api.sync.pull, { since: 0 });
    expect(pulled.changes).toEqual([
      { table: "profile", recordId: "local-user-1", serverSeq: 2, clientUpdatedAt: 2, payload: '{"n":1}', focusAreas: ["legs"] },
    ]);
  });

  test("a session policy is one row per owner", async () => {
    const t = convexTest(schema, modules);
    const policy = (at: number, payload: string): SyncChange => ({ table: "sessionPolicy", recordId: "local-user-1", clientUpdatedAt: at, payload });
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [policy(1, '{"version":1}')] });
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [policy(2, '{"version":2}')] });
    const stored = await rows(t, "sessionPolicies");
    expect(stored).toHaveLength(1);
    expect(stored[0].payload).toBe('{"version":2}');
  });

  test("malformed changes are refused before anything is written", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(ALICE);
    const tooMany = Array.from({ length: MAX_CHANGES_PER_PUSH + 1 }, (_, i) => log(`L${i}`, 1));
    await expectRefusal(alice.mutation(api.sync.push, { changes: tooMany }), "invalid_change");
    await expectRefusal(alice.mutation(api.sync.push, { changes: [log("", 1)] }), "invalid_change");
    await expectRefusal(alice.mutation(api.sync.push, { changes: [log(LOG_ID, -1)] }), "invalid_change");
    await expectRefusal(alice.mutation(api.sync.push, { changes: [log(LOG_ID, 1, "x".repeat(MAX_PAYLOAD_BYTES + 1))] }), "invalid_change");
    await expectRefusal(
      alice.mutation(api.sync.push, { changes: [{ table: "workoutLog", recordId: LOG_ID, clientUpdatedAt: 1, deleted: true, payload: "{}" }] }),
      "invalid_change",
    );
    await expectRefusal(
      alice.mutation(api.sync.push, { changes: [{ table: "workoutLog", recordId: LOG_ID, clientUpdatedAt: 1, deleted: false, payload: "{}" }] }),
      "invalid_change",
    );
    await expectRefusal(
      alice.mutation(api.sync.push, { changes: [log("ok", 1), { table: "workoutLog", recordId: LOG_ID, clientUpdatedAt: 1, deleted: false }] }),
      "invalid_change",
    );
    expect(await rows(t, "workoutLogs")).toHaveLength(0);
    expect(await rows(t, "users")).toHaveLength(0);
  });
});

describe("pull: an ordered cursor over the owner's changes", () => {
  test("pages through every change exactly once, oldest first", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(ALICE);
    await alice.mutation(api.sync.push, { changes: [profile(1)] });
    await alice.mutation(api.sync.push, { changes: Array.from({ length: 6 }, (_, i) => log(`L${i}`, 2)) });
    await alice.mutation(api.sync.push, { changes: [{ table: "sessionPolicy", recordId: "local-user-1", clientUpdatedAt: 3, payload: "{}" }] });

    const seen: string[] = [];
    let since = 0;
    let pages = 0;
    for (;;) {
      const page = await alice.query(api.sync.pull, { since, limit: 3 });
      seen.push(...page.changes.map((change) => `${change.table}:${change.recordId}`));
      expect(page.changes.every((change) => change.serverSeq > since)).toBe(true);
      since = page.cursor;
      pages += 1;
      if (!page.hasMore) break;
    }
    expect(pages).toBe(3);
    expect(seen).toEqual([
      "profile:local-user-1",
      "workoutLog:L0",
      "workoutLog:L1",
      "workoutLog:L2",
      "workoutLog:L3",
      "workoutLog:L4",
      "workoutLog:L5",
      "sessionPolicy:local-user-1",
    ]);
    const after = await alice.query(api.sync.pull, { since });
    expect(after).toEqual({ changes: [], cursor: since, hasMore: false });
  });

  test("a caller with no account yet pulls nothing", async () => {
    const t = convexTest(schema, modules);
    expect(await t.withIdentity(ALICE).query(api.sync.pull, { since: 0 })).toEqual({ changes: [], cursor: 0, hasMore: false });
  });

  test("an account being deleted is neither pulled from nor pushed to", async () => {
    const t = convexTest(schema, modules);
    await t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log(LOG_ID, 1)] });
    await t.run(async (ctx) => {
      const account = (await ctx.db.query("users").collect())[0];
      await ctx.db.patch(account._id, { deletionStartedAt: 1 });
    });
    await expectRefusal(t.withIdentity(ALICE).query(api.sync.pull, { since: 0 }), "account_deleting");
    await expectRefusal(t.withIdentity(ALICE).mutation(api.sync.push, { changes: [log("L2", 2)] }), "account_deleting");
    expect(await rows(t, "workoutLogs")).toHaveLength(1);
  });
});

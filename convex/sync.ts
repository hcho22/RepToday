import { v, type Infer } from "convex/values";
import { mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import { accountError, findAccount, requireOwner, writableAccount } from "./ownership";

/**
 * Local-first sync for the account data (M3, US-AU03, ADR-0016).
 *
 * The phone is the working copy: it records every change in Core Data first and keeps a durable
 * outbox of the records that changed. `push` uploads those records and `pull` hands back whatever
 * changed on the server since the device's cursor, so a second device (or a reinstall) catches up.
 *
 * Both functions are owner-scoped through `requireOwner`; neither takes an owner id.
 *
 * - **Idempotent by record id.** A record lands on the row keyed by `(ownerId, recordId)`, and a
 *   replay of a change the server already holds is reported `unchanged` and writes nothing, so an
 *   upload that is retried after a dropped response cannot duplicate anything.
 * - **Newest change wins.** Each change carries `clientUpdatedAt`, when it was made on the device. A
 *   change older than the row it would replace is reported `stale` and ignored; the device then
 *   pulls the newer row.
 * - **Ordered cursor.** Every write takes the next value of the owner's `users.changeSeq` as its
 *   `serverSeq`, so `pull` pages by a strictly increasing, gap-tolerant number with no ties.
 */

/** The most changes one push may carry; the client batches below it. */
export const MAX_CHANGES_PER_PUSH = 50;
/** The largest encoded record accepted. A real workout log is a few kilobytes. */
export const MAX_PAYLOAD_BYTES = 64 * 1024;
/** The longest record id accepted. The app's ids are UUID strings (36 characters). */
export const MAX_RECORD_ID_LENGTH = 128;
/** The most Focus Areas a profile may carry; the app offers seven. */
export const MAX_FOCUS_AREAS = 16;
/** The default and largest page `pull` returns. */
export const DEFAULT_PULL_LIMIT = 100;
export const MAX_PULL_LIMIT = 200;

const recordFields = {
  recordId: v.string(),
  clientUpdatedAt: v.number(),
};

/**
 * One changed record, as a device uploads it. The profile and the session policy are one per
 * owner and are never deleted by sync (account deletion removes them); logs and Outside Activities
 * can be deleted, so they carry `deleted` and omit their payload when they do.
 */
export const syncChange = v.union(
  v.object({
    table: v.literal("profile"),
    ...recordFields,
    payload: v.string(),
    focusAreas: v.array(v.string()),
  }),
  v.object({
    table: v.literal("sessionPolicy"),
    ...recordFields,
    payload: v.string(),
  }),
  v.object({
    table: v.literal("workoutLog"),
    ...recordFields,
    deleted: v.boolean(),
    payload: v.optional(v.string()),
    completedAt: v.optional(v.number()),
  }),
  v.object({
    table: v.literal("outsideActivity"),
    ...recordFields,
    deleted: v.boolean(),
    payload: v.optional(v.string()),
    date: v.optional(v.number()),
  }),
);
export type SyncChange = Infer<typeof syncChange>;

/** What became of one uploaded change. Every outcome means the device may drop it from its outbox. */
export type ChangeOutcome = "applied" | "unchanged" | "stale";

/**
 * Upload changed records. Returns one outcome per change, in order, and the owner's latest
 * `serverSeq`. The whole batch is one transaction: it lands entirely or not at all.
 */
export const push = mutation({
  args: { changes: v.array(syncChange) },
  handler: async (ctx, { changes }) => {
    const owner = await requireOwner(ctx);
    validateChanges(changes);
    const account = await writableAccount(ctx, owner);

    let seq = account.changeSeq;
    const nextSeq = () => ++seq;
    const results: { table: SyncChange["table"]; recordId: string; outcome: ChangeOutcome }[] = [];
    for (const change of changes) {
      const outcome = await applyChange(ctx, owner.ownerId, change, nextSeq);
      results.push({ table: change.table, recordId: change.recordId, outcome });
    }
    if (seq !== account.changeSeq) {
      await ctx.db.patch(account._id, { changeSeq: seq });
    }
    return { results, serverSeq: seq };
  },
});

/** One record as `pull` returns it: the uploaded shape plus the cursor it was written at. */
export type PulledChange =
  | { table: "profile"; recordId: string; serverSeq: number; clientUpdatedAt: number; payload: string; focusAreas: string[] }
  | { table: "sessionPolicy"; recordId: string; serverSeq: number; clientUpdatedAt: number; payload: string }
  | {
      table: "workoutLog";
      recordId: string;
      serverSeq: number;
      clientUpdatedAt: number;
      deleted: boolean;
      payload?: string;
      completedAt: number;
    }
  | {
      table: "outsideActivity";
      recordId: string;
      serverSeq: number;
      clientUpdatedAt: number;
      deleted: boolean;
      payload?: string;
      date: number;
    };

/**
 * The owner's records written after `since`, oldest first, at most `limit` of them. Pass the
 * returned `cursor` as the next `since`; `hasMore` says another page is waiting. A device that has
 * never pulled passes `0` and receives everything, tombstones included.
 */
export const pull = query({
  args: { since: v.number(), limit: v.optional(v.number()) },
  handler: async (ctx, { since, limit }) => {
    const owner = await requireOwner(ctx);
    if (!Number.isFinite(since) || since < 0) {
      throw accountError("invalid_change", "since must be a non-negative number.");
    }
    const account = await findAccount(ctx, owner.ownerId);
    if (account === null) {
      return { changes: [] as PulledChange[], cursor: since, hasMore: false };
    }
    if (account.deletionStartedAt !== undefined) {
      throw accountError("account_deleting", "This account is being deleted.");
    }

    const pageSize = Math.min(Math.max(Math.floor(limit ?? DEFAULT_PULL_LIMIT), 1), MAX_PULL_LIMIT);
    // Each table contributes at most `pageSize + 1` rows past the cursor, so the merged list is longer
    // than a page exactly when more is waiting somewhere.
    const fetchCount = pageSize + 1;
    const candidates: PulledChange[] = [
      ...(await pulledProfile(ctx, owner.ownerId, since)),
      ...(await rowsAfter(ctx, "sessionPolicies", owner.ownerId, since, fetchCount)).map(
        (row): PulledChange => ({
          table: "sessionPolicy",
          recordId: row.recordId,
          serverSeq: row.serverSeq,
          clientUpdatedAt: row.clientUpdatedAt,
          payload: row.payload ?? "",
        }),
      ),
      ...(await rowsAfter(ctx, "workoutLogs", owner.ownerId, since, fetchCount)).map(
        (row): PulledChange => ({
          table: "workoutLog",
          recordId: row.recordId,
          serverSeq: row.serverSeq,
          clientUpdatedAt: row.clientUpdatedAt,
          deleted: row.deleted,
          ...(row.payload === undefined ? {} : { payload: row.payload }),
          completedAt: row.completedAt,
        }),
      ),
      ...(await rowsAfter(ctx, "outsideActivities", owner.ownerId, since, fetchCount)).map(
        (row): PulledChange => ({
          table: "outsideActivity",
          recordId: row.recordId,
          serverSeq: row.serverSeq,
          clientUpdatedAt: row.clientUpdatedAt,
          deleted: row.deleted,
          ...(row.payload === undefined ? {} : { payload: row.payload }),
          date: row.date,
        }),
      ),
    ];
    candidates.sort((a, b) => a.serverSeq - b.serverSeq);
    const changes = candidates.slice(0, pageSize);
    const cursor = changes.length > 0 ? changes[changes.length - 1].serverSeq : since;
    return { changes, cursor, hasMore: candidates.length > pageSize };
  },
});

// MARK: - Validation

function validateChanges(changes: SyncChange[]): void {
  if (changes.length > MAX_CHANGES_PER_PUSH) {
    throw accountError("invalid_change", `A push carries at most ${MAX_CHANGES_PER_PUSH} changes.`);
  }
  for (const change of changes) {
    const { recordId, clientUpdatedAt } = change;
    if (recordId.length === 0 || recordId.length > MAX_RECORD_ID_LENGTH) {
      throw accountError("invalid_change", "recordId must be 1 to 128 characters.");
    }
    if (!Number.isFinite(clientUpdatedAt) || clientUpdatedAt < 0) {
      throw accountError("invalid_change", "clientUpdatedAt must be a non-negative number.");
    }
    switch (change.table) {
      case "profile":
        requirePayload(change.payload);
        if (change.focusAreas.length > MAX_FOCUS_AREAS || change.focusAreas.some((area) => area.length === 0 || area.length > 32)) {
          throw accountError("invalid_change", "focusAreas holds at most 16 short names.");
        }
        break;
      case "sessionPolicy":
        requirePayload(change.payload);
        break;
      case "workoutLog":
        requireDeletableShape(change.deleted, change.payload, change.completedAt, "completedAt");
        break;
      case "outsideActivity":
        requireDeletableShape(change.deleted, change.payload, change.date, "date");
        break;
    }
  }
}

function requirePayload(payload: string): void {
  if (payload.length === 0 || utf8Length(payload) > MAX_PAYLOAD_BYTES) {
    throw accountError("invalid_change", `payload must be 1 byte to ${MAX_PAYLOAD_BYTES} bytes.`);
  }
}

/** A tombstone carries nothing; a live record carries its payload and its timestamp. */
function requireDeletableShape(deleted: boolean, payload: string | undefined, timestamp: number | undefined, timestampName: string): void {
  if (deleted) {
    if (payload !== undefined) {
      throw accountError("invalid_change", "A deleted record carries no payload.");
    }
    return;
  }
  if (payload === undefined) {
    throw accountError("invalid_change", "A record that is not deleted carries its payload.");
  }
  requirePayload(payload);
  if (timestamp === undefined || !Number.isFinite(timestamp)) {
    throw accountError("invalid_change", `A record that is not deleted carries its ${timestampName}.`);
  }
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

// MARK: - Applying a change

async function applyChange(
  ctx: MutationCtx,
  ownerId: string,
  change: SyncChange,
  nextSeq: () => number,
): Promise<ChangeOutcome> {
  switch (change.table) {
    case "profile":
      return await applyProfile(ctx, ownerId, change, nextSeq);
    case "sessionPolicy": {
      const existing = await ctx.db
        .query("sessionPolicies")
        .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
        .unique();
      const content = { payload: change.payload, deleted: false };
      const outcome = decide(existing, change, content);
      if (outcome === "applied") {
        const row = { ownerId, ...recordRow(change, content), serverSeq: nextSeq() };
        await (existing === null ? ctx.db.insert("sessionPolicies", row) : ctx.db.replace(existing._id, row));
      }
      return outcome;
    }
    case "workoutLog": {
      const existing = await ctx.db
        .query("workoutLogs")
        .withIndex("by_ownerId_recordId", (q) => q.eq("ownerId", ownerId).eq("recordId", change.recordId))
        .unique();
      const content = { payload: change.payload, deleted: change.deleted };
      const outcome = decide(existing, change, content);
      if (outcome === "applied") {
        // A tombstone keeps the record's last known time, so it still sorts where the log was.
        const completedAt = change.completedAt ?? existing?.completedAt ?? change.clientUpdatedAt;
        const row = { ownerId, ...recordRow(change, content), completedAt, serverSeq: nextSeq() };
        await (existing === null ? ctx.db.insert("workoutLogs", row) : ctx.db.replace(existing._id, row));
      }
      return outcome;
    }
    case "outsideActivity": {
      const existing = await ctx.db
        .query("outsideActivities")
        .withIndex("by_ownerId_recordId", (q) => q.eq("ownerId", ownerId).eq("recordId", change.recordId))
        .unique();
      const content = { payload: change.payload, deleted: change.deleted };
      const outcome = decide(existing, change, content);
      if (outcome === "applied") {
        const date = change.date ?? existing?.date ?? change.clientUpdatedAt;
        const row = { ownerId, ...recordRow(change, content), date, serverSeq: nextSeq() };
        await (existing === null ? ctx.db.insert("outsideActivities", row) : ctx.db.replace(existing._id, row));
      }
      return outcome;
    }
  }
}

type RecordContent = { payload: string | undefined; deleted: boolean };
type StoredRecord = { recordId: string; clientUpdatedAt: number; payload?: string; deleted: boolean };

/**
 * The newest-wins rule every record table shares: an older change than the stored row is `stale`, an
 * identical replay is `unchanged`, and anything else is `applied` and takes the next `serverSeq`.
 */
function decide(
  existing: StoredRecord | null,
  change: { recordId: string; clientUpdatedAt: number },
  content: RecordContent,
): ChangeOutcome {
  if (existing === null) {
    return "applied";
  }
  if (existing.clientUpdatedAt > change.clientUpdatedAt) {
    return "stale";
  }
  const identical =
    existing.clientUpdatedAt === change.clientUpdatedAt &&
    existing.recordId === change.recordId &&
    existing.payload === content.payload &&
    existing.deleted === content.deleted;
  return identical ? "unchanged" : "applied";
}

/** The synced-record columns a change writes, leaving `payload` out of a tombstone. */
function recordRow(change: { recordId: string; clientUpdatedAt: number }, content: RecordContent) {
  return {
    recordId: change.recordId,
    clientUpdatedAt: change.clientUpdatedAt,
    deleted: content.deleted,
    ...(content.payload === undefined ? {} : { payload: content.payload }),
  };
}

/** The profile and its Focus Areas land together, at one `serverSeq`. */
async function applyProfile(
  ctx: MutationCtx,
  ownerId: string,
  change: Extract<SyncChange, { table: "profile" }>,
  nextSeq: () => number,
): Promise<ChangeOutcome> {
  const existing = await ctx.db
    .query("profiles")
    .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
    .unique();
  const focus = await ctx.db
    .query("focusAreas")
    .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
    .unique();
  const sameAreas =
    focus !== null &&
    focus.areas.length === change.focusAreas.length &&
    focus.areas.every((area, index) => area === change.focusAreas[index]);

  let seq: number | undefined;
  const takeSeq = () => (seq ??= nextSeq());
  const content = { payload: change.payload, deleted: false };
  const outcome = decide(existing, change, content);
  if (outcome === "stale") {
    return outcome;
  }
  if (outcome === "applied") {
    const row = { ownerId, ...recordRow(change, content), serverSeq: takeSeq() };
    await (existing === null ? ctx.db.insert("profiles", row) : ctx.db.replace(existing._id, row));
  }
  if (focus === null) {
    await ctx.db.insert("focusAreas", { ownerId, areas: change.focusAreas, clientUpdatedAt: change.clientUpdatedAt, serverSeq: takeSeq() });
    return "applied";
  }
  if (!sameAreas && focus.clientUpdatedAt <= change.clientUpdatedAt) {
    await ctx.db.patch(focus._id, { areas: change.focusAreas, clientUpdatedAt: change.clientUpdatedAt, serverSeq: takeSeq() });
    return "applied";
  }
  return outcome;
}

// MARK: - Reading changes

async function rowsAfter(
  ctx: QueryCtx,
  table: "sessionPolicies",
  ownerId: string,
  since: number,
  count: number,
): Promise<Doc<"sessionPolicies">[]>;
async function rowsAfter(
  ctx: QueryCtx,
  table: "workoutLogs",
  ownerId: string,
  since: number,
  count: number,
): Promise<Doc<"workoutLogs">[]>;
async function rowsAfter(
  ctx: QueryCtx,
  table: "outsideActivities",
  ownerId: string,
  since: number,
  count: number,
): Promise<Doc<"outsideActivities">[]>;
/** The owner's rows in `table` written after `since`, oldest first, at most `count`. */
async function rowsAfter(
  ctx: QueryCtx,
  table: "sessionPolicies" | "workoutLogs" | "outsideActivities",
  ownerId: string,
  since: number,
  count: number,
) {
  switch (table) {
    case "sessionPolicies":
      return await ctx.db
        .query("sessionPolicies")
        .withIndex("by_ownerId_serverSeq", (q) => q.eq("ownerId", ownerId).gt("serverSeq", since))
        .order("asc")
        .take(count);
    case "workoutLogs":
      return await ctx.db
        .query("workoutLogs")
        .withIndex("by_ownerId_serverSeq", (q) => q.eq("ownerId", ownerId).gt("serverSeq", since))
        .order("asc")
        .take(count);
    case "outsideActivities":
      return await ctx.db
        .query("outsideActivities")
        .withIndex("by_ownerId_serverSeq", (q) => q.eq("ownerId", ownerId).gt("serverSeq", since))
        .order("asc")
        .take(count);
  }
}

/**
 * The owner's profile with its Focus Areas, when either changed after `since`. It reports the later
 * of the two `serverSeq`s, so a Focus Areas change made on its own still reaches every device.
 */
async function pulledProfile(ctx: QueryCtx, ownerId: string, since: number): Promise<PulledChange[]> {
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
    .unique();
  if (profile === null || profile.payload === undefined) {
    return [];
  }
  const focus = await ctx.db
    .query("focusAreas")
    .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
    .unique();
  const serverSeq = Math.max(profile.serverSeq, focus?.serverSeq ?? 0);
  if (serverSeq <= since) {
    return [];
  }
  return [
    {
      table: "profile",
      recordId: profile.recordId,
      serverSeq,
      clientUpdatedAt: Math.max(profile.clientUpdatedAt, focus?.clientUpdatedAt ?? 0),
      payload: profile.payload,
      focusAreas: focus?.areas ?? [],
    },
  ];
}

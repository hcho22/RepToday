import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/**
 * The account-data columns every synced record table shares (M3, ADR-0016).
 *
 * - `ownerId` is the caller's Clerk identity as Convex verified it (`identity.tokenIdentifier`). It
 *   is only ever read off the authenticated identity inside a function, never taken from arguments,
 *   so a caller can neither read nor write a row it does not own (`convex/ownership.ts`).
 * - `recordId` is the app's own record id (a `WorkoutLog.id`, an `OutsideActivity.id`, the
 *   `User.id`), so a retried upload lands on the same row: sync is idempotent by record id.
 * - `serverSeq` is the owner's strictly increasing change counter (`users.changeSeq`), the cursor a
 *   device pulls changes after.
 * - `clientUpdatedAt` is when the change was made on the device (ms since the epoch); the newer one
 *   wins when two devices write the same record.
 * - `payload` is the app's own JSON encoding of the record, stored verbatim as a string so the
 *   server never rejects a field name Convex would refuse. `deleted` rows are tombstones that tell
 *   other devices a record is gone; they carry no payload.
 */
const syncedRecord = {
  ownerId: v.string(),
  recordId: v.string(),
  serverSeq: v.number(),
  clientUpdatedAt: v.number(),
  payload: v.optional(v.string()),
  deleted: v.boolean(),
};

/**
 * Two backends share this deployment and touch no table of the other's:
 *
 * - the account data (M3, ADR-0016): `users` plus the per-user record tables below, every row
 *   owned by one Clerk identity and reached only through `convex/sync.ts` and `convex/accounts.ts`;
 * - the telemetry evidence backend (`events`, `rateLimits`), described next.
 *
 * The telemetry evidence backend: one immutable table with idempotent inserts.
 *
 * There is deliberately no funnel, cohort, or aggregate structure here. The evidence-table indexes
 * serve only transport idempotency (`eventId`) and raw-row selection (`installId`) for reconciliation
 * and production validation; every metric remains derived offline, so analysis stays revisable.
 *
 * Numeric convention (pinned by US-T03): both timestamps are `v.number()` - Convex float64 - and a
 * plain JSON number already *is* float64, so a client sending one never meets the `int64` vs
 * `float64` mismatch the US-T01 spike documents. The HTTP action requires that wire form rather
 * than coercing whatever it is handed: anything that is not an actual finite JSON number is
 * refused with `400`, so nothing reinterpreted lands in this column.
 * `generation_ms` and every other numeric property ride inside `props` and are stored as-is.
 */
export default defineSchema({
  /**
   * One row per account: the Clerk identity and the owner's change counter. Created on the first
   * authenticated write. `deletionStartedAt` is set once account deletion is committed; every write
   * is refused from then on. The `clerkDeletion*` fields record each attempt to delete the Clerk
   * user, and `clerkUserDeletedAt` when Clerk confirmed it; the deletion job removes this row last,
   * only after that confirmation.
   */
  users: defineTable({
    ownerId: v.string(),
    clerkUserId: v.string(),
    createdAt: v.number(),
    /** The last `serverSeq` handed out to one of this owner's rows. */
    changeSeq: v.number(),
    deletionStartedAt: v.optional(v.number()),
    clerkDeletionAttempts: v.optional(v.number()),
    clerkDeletionLastAttemptAt: v.optional(v.number()),
    clerkDeletionLastOutcome: v.optional(v.union(v.literal("gone"), v.literal("exists"), v.literal("unknown"))),
    clerkUserDeletedAt: v.optional(v.number()),
  }).index("by_ownerId", ["ownerId"]),

  /**
   * The user aggregate (`User`: name, profile, phase, consistency, duration, cold start), one per
   * owner. `recordId` is the device's `User.id`.
   */
  profiles: defineTable(syncedRecord)
    .index("by_ownerId", ["ownerId"])
    .index("by_ownerId_serverSeq", ["ownerId", "serverSeq"]),

  /**
   * The user's Focus Areas (decision 20), one row per owner, written with the profile they belong
   * to. Kept as its own table so a server-side writer can change them without the whole profile.
   */
  focusAreas: defineTable({
    ownerId: v.string(),
    areas: v.array(v.string()),
    serverSeq: v.number(),
    clientUpdatedAt: v.number(),
  }).index("by_ownerId", ["ownerId"]),

  /** Completed sessions (`WorkoutLog`), one row per log. */
  workoutLogs: defineTable({ ...syncedRecord, completedAt: v.number() })
    .index("by_ownerId_recordId", ["ownerId", "recordId"])
    .index("by_ownerId_serverSeq", ["ownerId", "serverSeq"]),

  /** Logged Outside Activities (US-HO04), one row per activity. */
  outsideActivities: defineTable({ ...syncedRecord, date: v.number() })
    .index("by_ownerId_recordId", ["ownerId", "recordId"])
    .index("by_ownerId_serverSeq", ["ownerId", "serverSeq"]),

  /** The in-force `SessionPolicy`, one per owner. `recordId` is the `User.id` it belongs to. */
  sessionPolicies: defineTable(syncedRecord)
    .index("by_ownerId", ["ownerId"])
    .index("by_ownerId_serverSeq", ["ownerId", "serverSeq"]),

  /**
   * Coach-written Custom Workouts (decision 27). Created empty in M3 so the owner's data has one
   * shape from the start; M4 (US-CA04) fills it. Removed with the account.
   */
  customWorkouts: defineTable(syncedRecord)
    .index("by_ownerId_recordId", ["ownerId", "recordId"])
    .index("by_ownerId_serverSeq", ["ownerId", "serverSeq"]),

  /**
   * The Coach agent's conversation memory (US-CA03): one row per message, written only by the Coach
   * functions (`convex/coach.ts`), never by sync. `recordId` is the message id (a user message's id is
   * the client's idempotency key), `payload` the message as JSON (`CoachMessage` in `coach.ts`).
   * Removed with the account.
   */
  coachMemory: defineTable(syncedRecord)
    .index("by_ownerId_recordId", ["ownerId", "recordId"])
    .index("by_ownerId_serverSeq", ["ownerId", "serverSeq"]),

  /**
   * How many Coach turns an owner took on one UTC day, and the deployment-wide total under the
   * reserved `ownerId` `*` (M4, US-CA01). Bounds the paid model calls one account, or everyone, can
   * cause. Rows older than a few days are swept by `crons.ts`.
   */
  coachUsage: defineTable({
    ownerId: v.string(),
    /** `YYYY-MM-DD`, UTC. */
    day: v.string(),
    count: v.number(),
  })
    .index("by_ownerId_day", ["ownerId", "day"])
    .index("by_day", ["day"]),

  /**
   * Premium subscriptions the App Store has told this deployment about (M4, US-CA02, ADR-0017): one
   * row per subscription (its `originalTransactionId`), kept current by App Store Server
   * Notifications and linked to an account by `appAccountToken` or by the account's own verified
   * restore. `ownerId` is absent until a subscription is linked. The Coach reads it on every turn;
   * a client can never write it. Removed with the account.
   */
  entitlements: defineTable({
    ownerId: v.optional(v.string()),
    originalTransactionId: v.string(),
    productId: v.string(),
    environment: v.union(v.literal("Production"), v.literal("Sandbox"), v.literal("Xcode")),
    /** When the current period ends (ms since the epoch). */
    expiresAt: v.number(),
    /** The end of a billing grace period Apple granted, when one is running. */
    gracePeriodExpiresAt: v.optional(v.number()),
    /** Set when Apple refunded or revoked the purchase; the entitlement is then inactive. */
    revokedAt: v.optional(v.number()),
    /** The newest `signedDate` applied, so a late, older update never replaces a newer one. */
    lastSignedAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_ownerId", ["ownerId"])
    .index("by_originalTransactionId", ["originalTransactionId"]),

  /**
   * Each account's App Store `appAccountToken` (M4, US-CA02): a random UUID the app passes to
   * StoreKit with every purchase, which Apple then echoes in that subscription's notifications, so a
   * renewal reaches the right account without the app. Removed with the account.
   */
  appAccountTokens: defineTable({
    ownerId: v.string(),
    token: v.string(),
  })
    .index("by_ownerId", ["ownerId"])
    .index("by_token", ["token"]),

  /**
   * App Store Server Notifications already processed, by Apple's `notificationUUID`, so a retried
   * delivery is applied once (M4, US-CA02). Holds no subscription or account data; swept by `crons.ts`.
   */
  appStoreNotifications: defineTable({
    notificationUUID: v.string(),
    notificationType: v.string(),
    receivedAt: v.number(),
  })
    .index("by_notificationUUID", ["notificationUUID"])
    .index("by_receivedAt", ["receivedAt"]),

  events: defineTable({
    /**
     * Client-generated idempotency key, stable across retries of one accepted event.
     * Optional so the schema remains deployable over pre-reliability production rows and the HTTP
     * boundary can keep accepting already-shipped one-shot clients. The current durable client
     * always supplies it.
     */
    eventId: v.optional(v.string()),
    /**
     * One of the app's 13 pre-registered event names (`EVENT_NAMES` in `events.ts`), or one of the
     * two Waitlist web events (`WEB_EVENT_NAMES` in `webEvents.ts`; see convex/README.md, "Web events").
     */
    name: v.string(),
    /**
     * Random per-install identifier (US-T05), or the one reserved value `web` that every web event
     * row carries (`WEB_EVENT_INSTALL_ID`). Never a user identity.
     */
    installId: v.string(),
    /** Client-side timestamp, milliseconds since the Unix epoch. */
    clientTs: v.number(),
    /**
     * Server-received timestamp, milliseconds since the Unix epoch, stamped by `logEvent` (or by
     * `logWebEvent` for a web event).
     */
    serverTs: v.number(),
    /** The event's non-identifying property bag, stored exactly as it arrived. */
    props: v.any(),
  })
    .index("by_eventId", ["eventId"])
    .index("by_installId", ["installId"]),

  /**
   * US-T14's rate-limit counter store, and nothing else.
   *
   * This is the second - and, per FR-6, last permitted - table the sink may hold: a dedicated
   * helper carrying only ephemeral per-key counters. It is **not** a second evidence surface. It
   * carries no identity (`bucketKey` is a coarse throttle key, not a person), accumulates no
   * history (each row is one time window and is deleted once that window rolls), is read only by
   * the throttle check in `rateLimit.ts`, and is **not** part of the evidence base for K1/K2/K4.
   * It exists solely to answer "has this key exceeded its window", and its contents are transient.
   *
   * The throttle check looks a bucket up by key on every request (`by_bucketKey`), and the
   * `reclaimExpired` cron sweeps expired buckets by window (`by_windowStart`); a full scan of a hot
   * counter table would be the opposite of cheap. "The sink stays dumb" means it performs no
   * analysis, not that operational selectors must scan their entire tables.
   */
  rateLimits: defineTable({
    /**
     * The window-scoped throttle key: `"<scope>:<identity>:<windowStart>"`, where scope is
     * `install` or `ip` for the app's route, or `webip` or `web` for `POST /webEvent`; identity is
     * the per-install id or coarse source IP (`all` in the `web` scope); and `windowStart` is the
     * window this row counts. Baking the window into the key makes each window a distinct row,
     * so a rolled window is a fresh insert rather than a mutated counter and stale windows are
     * cleanly deletable.
     */
    bucketKey: v.string(),
    /** The start of this row's window, ms since the epoch. Used to sweep expired rows. */
    windowStart: v.number(),
    /** How many requests this key has made in this window. */
    count: v.number(),
  })
    .index("by_bucketKey", ["bucketKey"])
    .index("by_windowStart", ["windowStart"]),
});

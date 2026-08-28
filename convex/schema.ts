import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/**
 * The whole telemetry backend: one append-only table.
 *
 * There is deliberately no funnel, cohort, or aggregate structure here and no index beyond
 * Convex's defaults. Every metric in the anonymous funnel event-metric schema is derivable from
 * raw rows by a query written later, so the sink stays dumb and the analysis stays revisable.
 *
 * Numeric convention (pinned by US-T03): both timestamps are `v.number()` - Convex float64 - and a
 * plain JSON number already *is* float64, so a client sending one never meets the `int64` vs
 * `float64` mismatch the US-T01 spike documents. The HTTP action requires that wire form rather
 * than coercing whatever it is handed: anything that is not an actual finite JSON number is
 * refused with `400`, so nothing reinterpreted lands in this column.
 * `generation_ms` and every other numeric property ride inside `props` and are stored as-is.
 */
export default defineSchema({
  events: defineTable({
    /** One of the 13 pre-registered event names; see `EVENT_NAMES` in `events.ts`. */
    name: v.string(),
    /** Random per-install identifier (US-T05). Never a user identity. */
    installId: v.string(),
    /** Client-side timestamp, milliseconds since the Unix epoch. */
    clientTs: v.number(),
    /** Server-received timestamp, milliseconds since the Unix epoch, stamped by `logEvent`. */
    serverTs: v.number(),
    /** The event's non-identifying property bag, stored exactly as it arrived. */
    props: v.any(),
  }),

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
   * Unlike `events`, this table carries indexes: the throttle check looks a bucket up by key on
   * every request (`by_bucketKey`), and the `reclaimExpired` cron sweeps expired buckets by window
   * (`by_windowStart`), and a full scan of a hot counter table would be the opposite of cheap. "The
   * sink stays dumb" is a rule about the *evidence* table, not about a throttle whose whole job is
   * to be fast and forgetful.
   */
  rateLimits: defineTable({
    /**
     * The window-scoped throttle key: `"<scope>:<identity>:<windowStart>"`, where scope is
     * `install` or `ip`, identity is the per-install id or coarse source IP, and `windowStart` is
     * the window this row counts. Baking the window into the key makes each window a distinct row,
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

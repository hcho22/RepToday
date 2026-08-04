import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/**
 * The whole telemetry backend: one append-only table.
 *
 * There is deliberately no funnel, cohort, or aggregate structure here and no index beyond
 * Convex's defaults. Every metric in `gtm/06-channels/event-metric-schema.md` is derivable from
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
});

import { internalMutation } from "./_generated/server";
import { ConvexError, v } from "convex/values";

/**
 * The 13 pre-registered in-app event names.
 *
 * These are a wire contract fixed by US-T02: they are the exact raw values of
 * `AnalyticsEventName` in `ios/RepToday/RepToday/Models/AnalyticsEvent.swift`, which in turn come
 * verbatim from the anonymous funnel event-metric schema. The two web-side events
 * (`landing_page_view`, `waitlist_signup`) are handled outside the app and are deliberately absent.
 *
 * Adding a name here without adding the matching Swift case (or vice versa) breaks the contract.
 */
export const EVENT_NAMES = [
  "app_install",
  "onboarding_started",
  "onboarding_completed",
  "ready_screen_shown",
  "session_started",
  "session_completed",
  "session_abandoned",
  "day7_return",
  "day30_return",
  "week_active",
  "paywall_shown",
  "trial_started",
  "subscribe",
] as const;

/** The compile-time form of the same closed vocabulary. */
export type AnalyticsEventName = (typeof EVENT_NAMES)[number];

/**
 * Property-bag limits.
 *
 * The largest real bag in the pre-registered schema is `session_completed` with four small scalar
 * keys (~120 bytes serialized), so these caps sit roughly two orders of magnitude above anything
 * the app legitimately sends: they exist only to stop a malformed or hostile client from poisoning
 * the table, not to police shape. Per the story's "basic input validation only" criterion, an
 * unknown event name and an oversized bag are the *only* two rejections **this mutation** makes.
 * The boundary checks live in `http.ts`, where untrusted input actually enters: field presence and
 * kind, plus the two size caps US-T04 added once a real client existed to need them.
 *
 * They are raised as `ConvexError` rather than `Error` so the HTTP action can tell a rejection it
 * asked for apart from a runtime or database failure it did not, and answer `400` or `5xx`
 * accordingly. That marker is the whole distinction, so it belongs on the throw.
 */
export const MAX_PROPS_BYTES = 4096;
export const MAX_PROPS_KEYS = 32;

/**
 * Insert one telemetry event idempotently.
 *
 * Existing rows are never mutated. A retry carrying an `eventId` already in the evidence table
 * returns that row's id without a second insert; otherwise this validates, stamps `serverTs`, and
 * inserts exactly one row. The indexed check and insert run in one serializable Convex mutation, so
 * concurrent replays cannot both win. No aggregation, funnel modelling, or cohort math happens here.
 *
 * `internalMutation`, not `mutation`: a public Convex function is callable directly on the
 * deployment's own `.convex.cloud/api/mutation` endpoint, which shares its slug with the
 * `.convex.site` route a shipped client already carries. That second entry point skipped every
 * boundary check in `http.ts`: a direct call was observed inserting a row with an empty
 * `installId`, which is exactly what the action's non-empty-string check keeps out of the column
 * K4 counts unique installs by. Internal makes the HTTP action the single entry point the story
 * says it is.
 */
export const logEvent = internalMutation({
  args: {
    // Optional at the internal boundary only for already-shipped clients that predate durable
    // replay. The current iOS client always supplies it; present ids are idempotent.
    eventId: v.optional(v.string()),
    name: v.union(...EVENT_NAMES.map((name) => v.literal(name))),
    installId: v.string(),
    clientTs: v.number(),
    props: v.any(),
  },
  handler: async (ctx, args) => {
    if (args.eventId !== undefined) {
      const existing = await ctx.db
        .query("events")
        .withIndex("by_eventId", (q) => q.eq("eventId", args.eventId))
        .unique();
      if (existing) return existing._id;
    }

    const props = args.props ?? {};

    // Not a third rule: a bag that is not a bag has no size, so this is the precondition the
    // size check below is measured against rather than a shape check of its own.
    if (typeof props !== "object" || props === null || Array.isArray(props)) {
      throw new ConvexError("props must be an object");
    }

    const keyCount = Object.keys(props).length;
    if (keyCount > MAX_PROPS_KEYS) {
      throw new ConvexError(
        `props has ${keyCount} keys, over the ${MAX_PROPS_KEYS}-key limit`,
      );
    }

    // UTF-8 bytes, not `String.length` - the latter counts UTF-16 code units, so a bag full of
    // non-ASCII would be undercounted by up to a factor of three against a limit called "bytes".
    const serializedBytes = new TextEncoder().encode(JSON.stringify(props)).length;
    if (serializedBytes > MAX_PROPS_BYTES) {
      throw new ConvexError(
        `props is ${serializedBytes} bytes, over the ${MAX_PROPS_BYTES}-byte limit`,
      );
    }

    const event = {
      name: args.name,
      installId: args.installId,
      clientTs: args.clientTs,
      serverTs: Date.now(),
      props,
    };
    return await ctx.db.insert(
      "events",
      args.eventId === undefined ? event : { ...event, eventId: args.eventId },
    );
  },
});

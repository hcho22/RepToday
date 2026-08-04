import { mutation } from "./_generated/server";
import { v } from "convex/values";

/**
 * The 13 pre-registered in-app event names.
 *
 * These are a wire contract fixed by US-T02: they are the exact raw values of
 * `AnalyticsEventName` in `ios/RepToday/RepToday/Models/AnalyticsEvent.swift`, which in turn come
 * verbatim from `gtm/06-channels/event-metric-schema.md`. The two web-side events
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
 * unknown event name and an oversized bag are the *only* two rejections.
 */
export const MAX_PROPS_BYTES = 4096;
export const MAX_PROPS_KEYS = 32;

/**
 * Append one telemetry event.
 *
 * Append-only by construction: it validates, stamps `serverTs`, inserts exactly one row, and
 * returns the id. No aggregation, no dedup, no funnel modelling, no cohort math - analysis is
 * deferred to queries written against the raw rows later.
 */
export const logEvent = mutation({
  args: {
    name: v.union(...EVENT_NAMES.map((name) => v.literal(name))),
    installId: v.string(),
    clientTs: v.number(),
    props: v.any(),
  },
  handler: async (ctx, args) => {
    const props = args.props ?? {};

    // Not a third rule: a bag that is not a bag has no size, so this is the precondition the
    // size check below is measured against rather than a shape check of its own.
    if (typeof props !== "object" || props === null || Array.isArray(props)) {
      throw new Error("props must be an object");
    }

    const keyCount = Object.keys(props).length;
    if (keyCount > MAX_PROPS_KEYS) {
      throw new Error(
        `props has ${keyCount} keys, over the ${MAX_PROPS_KEYS}-key limit`,
      );
    }

    // UTF-8 bytes, not `String.length` - the latter counts UTF-16 code units, so a bag full of
    // non-ASCII would be undercounted by up to a factor of three against a limit called "bytes".
    const serializedBytes = new TextEncoder().encode(JSON.stringify(props)).length;
    if (serializedBytes > MAX_PROPS_BYTES) {
      throw new Error(
        `props is ${serializedBytes} bytes, over the ${MAX_PROPS_BYTES}-byte limit`,
      );
    }

    return await ctx.db.insert("events", {
      name: args.name,
      installId: args.installId,
      clientTs: args.clientTs,
      serverTs: Date.now(),
      props,
    });
  },
});

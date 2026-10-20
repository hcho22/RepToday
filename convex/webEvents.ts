import { internalMutation } from "./_generated/server";
import { v } from "convex/values";

/**
 * The two anonymous web events of the Waitlist (US-WL05), kept apart from the app's 13.
 *
 * `POST /logEvent` and its 13-name union (`events.ts`) are the app's contract and stay exactly as
 * they were: a web name posted there is still rejected. The landing pages instead post to the
 * separate `POST /webEvent` route (`http.ts`), which writes through the mutation below. Its closed
 * union holds only these two names, and the property bag is exactly one key, `referrer_source`.
 *
 * Names and vocabulary come from Mandu's event-metric schema as the approved Waitlist request
 * restates them: `landing_page_view` ("landing page loads") and `waitlist_signup` ("email submitted
 * to the waitlist"), each carrying `referrer_source` = the visit's Source tag or `none`. The word
 * `unknown` is the *sign-up's* Source for a visit with no tag, never an event value, so it is not in
 * the list. The four tags are the Waitlist contract file's `source_tags`
 * (`tools/waitlist/contract.json`), and `none` is its `no_source_event`; `convex/webEvents.test.ts`
 * fails when this list and the contract file differ. Adding a Source is a new Dispatch request plus a
 * reviewed gr0wthlab change.
 *
 * **No identity of any kind.** A web visit has no install, so the row's `installId` column holds the
 * one reserved value below, the same for every web event. Nothing about the visitor, the device, the
 * email address or the sign-up's entry identifier reaches this table, and `tools/reconcile` (which
 * selects rows by install identifier) never asks for it.
 */
export const WEB_EVENT_NAMES = ["landing_page_view", "waitlist_signup"] as const;
export type WebEventName = (typeof WEB_EVENT_NAMES)[number];

export const WEB_REFERRER_SOURCES = ["tiktok", "youtube", "reddit", "network", "none"] as const;
export type WebReferrerSource = (typeof WEB_REFERRER_SOURCES)[number];

/**
 * The reserved `installId` of every web event row. It is not a UUID, so it cannot collide with an
 * install's random identifier, and it is the same for every visitor, so it identifies no one.
 */
export const WEB_EVENT_INSTALL_ID = "web";

/**
 * Insert one web event. Internal for the same reason `logEvent` is: the HTTP action is the only way
 * in, and it is where the origin, size, shape and rate checks live. The row is the same shape the
 * `events` table holds for an app event: `clientTs` is stamped from the server's clock (a page sends
 * no timestamp, so no visitor clock is ever recorded) and `props` is `{ referrer_source }`.
 */
export const logWebEvent = internalMutation({
  args: {
    name: v.union(...WEB_EVENT_NAMES.map((name) => v.literal(name))),
    referrerSource: v.union(...WEB_REFERRER_SOURCES.map((source) => v.literal(source))),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    return await ctx.db.insert("events", {
      name: args.name,
      installId: WEB_EVENT_INSTALL_ID,
      clientTs: now,
      serverTs: now,
      props: { referrer_source: args.referrerSource },
    });
  },
});

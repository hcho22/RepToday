// @ts-check

/**
 * The funnel's event set, ordering, and salient properties - the reconciliation's view of the
 * authoritative schema in `gtm/06-channels/event-metric-schema.md`.
 *
 * The 13 in-app event names and their order are the wire contract. This file mirrors that contract
 * so the pure tabulator has no network or Convex-runtime dependency, and `funnel-schema.test.ts`
 * asserts `FUNNEL_EVENTS.map(e => e.name)` is exactly `EVENT_NAMES` from `convex/events.ts` (itself
 * pinned verbatim to the schema md and to the Swift `AnalyticsEventName`). So this is validated
 * against the source of truth, not a hand-maintained guess: a drift in either list fails the suite.
 *
 * `salientProps` are the properties a reconciliation reads off each event when diffing against the
 * coder's observation log, taken from the schema's Properties column and the emission-site
 * descriptions in the funnel PRD and `CLAUDE.md`. `atMostOncePerInstall` marks the events whose
 * emission is one-shot- or once-guarded so that a second occurrence for one install is a real
 * duplicate defect (as opposed to the session/ready/paywall events, which legitimately recur).
 * `week_active` is once-*per-week*, not per-install, so it is handled separately by the tabulator.
 */

/**
 * @typedef {Object} FunnelEvent
 * @property {string} name           The snake_case wire name.
 * @property {string[]} salientProps Properties surfaced per occurrence for line-by-line diffing.
 * @property {boolean} atMostOncePerInstall True when >1 occurrence for one install is a defect.
 */

/** @type {readonly FunnelEvent[]} */
export const FUNNEL_EVENTS = Object.freeze([
  { name: "app_install", salientProps: ["install_week"], atMostOncePerInstall: true },
  { name: "onboarding_started", salientProps: [], atMostOncePerInstall: true },
  { name: "onboarding_completed", salientProps: ["elapsed_seconds"], atMostOncePerInstall: true },
  { name: "ready_screen_shown", salientProps: ["generation_ms"], atMostOncePerInstall: false },
  { name: "session_started", salientProps: ["requested_minutes"], atMostOncePerInstall: false },
  {
    name: "session_completed",
    salientProps: ["requested_minutes", "completed_minutes", "was_return", "perceived_difficulty"],
    atMostOncePerInstall: false,
  },
  {
    name: "session_abandoned",
    salientProps: ["completed_minutes", "abandon_point"],
    atMostOncePerInstall: false,
  },
  { name: "day7_return", salientProps: [], atMostOncePerInstall: true },
  { name: "day30_return", salientProps: [], atMostOncePerInstall: true },
  { name: "week_active", salientProps: [], atMostOncePerInstall: false },
  { name: "paywall_shown", salientProps: ["entry_point"], atMostOncePerInstall: false },
  { name: "trial_started", salientProps: [], atMostOncePerInstall: true },
  { name: "subscribe", salientProps: ["plan"], atMostOncePerInstall: true },
]);

/** The event names in funnel order. */
export const FUNNEL_EVENT_NAMES = Object.freeze(FUNNEL_EVENTS.map((e) => e.name));

/**
 * Funnel prerequisite edges: `[downstream, upstream]` means an install that emitted `downstream`
 * must also have emitted `upstream`; the reverse absence is a missing-event anomaly. These come
 * straight from the emission-site contracts (e.g. `onboarding_completed` only fires after
 * `onboarding_started`; `week_active` fires *from* a completed session; `subscribe`/`trial_started`
 * only fire from the paywall). `app_install` is deliberately not a prerequisite of anything: it
 * fires only on the first-ever open, so a returning install legitimately has none.
 *
 * @type {readonly [string, string][]}
 */
export const FUNNEL_PREREQUISITES = Object.freeze([
  ["onboarding_completed", "onboarding_started"],
  ["session_completed", "session_started"],
  ["session_abandoned", "session_started"],
  ["week_active", "session_completed"],
  ["trial_started", "paywall_shown"],
  ["subscribe", "paywall_shown"],
]);

/**
 * Ordered milestone pairs `[earlier, later]` whose first-occurrence client timestamps must be
 * monotonic. A `later` event stamped before its `earlier` milestone is an out-of-order anomaly
 * (a clock or window bug the reconciliation cares about). Only genuinely ordered, mostly
 * once-per-install milestones are listed; the recurring session events are not chained here
 * because multiple physical sessions interleave and would produce false positives.
 *
 * @type {readonly [string, string][]}
 */
export const FUNNEL_ORDER_CONSTRAINTS = Object.freeze([
  ["onboarding_started", "onboarding_completed"],
  ["onboarding_completed", "session_started"],
  ["paywall_shown", "trial_started"],
  ["paywall_shown", "subscribe"],
  ["trial_started", "subscribe"],
]);

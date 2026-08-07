import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

/**
 * US-T14's rate-limit maintenance, moved off the request path.
 *
 * `checkAndBump` used to reclaim expired counter rows opportunistically on every request, which made
 * concurrent requests from different installs contend on a shared `by_windowStart` range under
 * Convex's optimistic concurrency and fail closed under load. Reclamation now runs here instead, on
 * a fixed schedule, in bounded batches (`RECLAIM_BATCH`), so the throttle's hot path does only point
 * operations on the caller's own bucket. A large backlog drains over several ticks by design.
 */
const crons = cronJobs();

crons.interval(
  "reclaim expired rate-limit rows",
  { minutes: 1 },
  internal.rateLimit.reclaimExpired,
  {},
);

export default crons;

import { internalQuery } from "./_generated/server";
import { v } from "convex/values";

/**
 * US-T13 reconciliation read path - the *internal* side only.
 *
 * This is the one function the offline reconciliation harness (`tools/reconcile/`) reads through.
 * It is an `internalQuery` on purpose, exactly like `logEvent` is an `internalMutation`: the sink's
 * "one way in, internal-only" posture (see `convex/README.md`) is not weakened for a QA tool.
 * A public query would be callable directly on the deployment's `.convex.cloud/api/query` endpoint
 * by anyone who learns the slug; an internal one is reachable only with a deploy/admin key, which is
 * what `npx convex run reconcile:eventsForInstalls '{"installIds": [...]}' --deployment <name>`
 * carries. It adds **no** public Convex function and **no** HTTP route, and US-T14's future
 * hardening of the *public* `POST /logEvent` surface is untouched by it.
 *
 * It is read-only and adds no field to the `events` row shape: it selects the rows whose `installId`
 * is in the supplied set and returns exactly the five wire columns the pure tabulator consumes.
 * `_id`/`_creationTime` are deliberately dropped - the reconciliation reasons about `clientTs`
 * (what the device stamped) and `serverTs` (what the sink stamped), not Convex's internal doc id.
 *
 * Scale note: the `events` table has no index beyond Convex's defaults (schema.ts keeps the sink
 * dumb), so this does a full table scan and filters in memory. That is intentional and adequate:
 * US-T13 reconciles the ~25-install moderated TestFlight cohort, a one-off offline QA read, not a
 * hot path. If a much larger cohort ever needs this, add a `by_installId` index in `schema.ts` and
 * switch to `withIndex` - a schema change made deliberately, not smuggled in under a QA tool.
 */
export const eventsForInstalls = internalQuery({
  args: {
    installIds: v.array(v.string()),
  },
  handler: async (ctx, { installIds }) => {
    const wanted = new Set(installIds);
    const all = await ctx.db.query("events").collect();
    return all
      .filter((row) => wanted.has(row.installId))
      .map((row) => ({
        name: row.name,
        installId: row.installId,
        clientTs: row.clientTs,
        serverTs: row.serverTs,
        props: row.props,
      }));
  },
});

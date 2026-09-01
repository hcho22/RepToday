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
 * carries. It adds **no** public Convex function and **no** HTTP route, and US-T14's hardening of
 * the *public* `POST /logEvent` surface is untouched by it.
 *
 * It is read-only and adds no field to the `events` row shape: it selects the rows whose `installId`
 * is in the supplied set and returns exactly the five wire columns the pure tabulator consumes.
 * `_id`/`_creationTime` are deliberately dropped - the reconciliation reasons about `clientTs`
 * (what the device stamped) and `serverTs` (what the sink stamped), not Convex's internal doc id.
 *
 * The `events.by_installId` index keeps both the ~25-install US-T13 cohort read and recurring
 * production validation proportional to the requested installs instead of the lifetime table.
 */
export const eventsForInstalls = internalQuery({
  args: {
    installIds: v.array(v.string()),
  },
  handler: async (ctx, { installIds }) => {
    const rows = await Promise.all(
      Array.from(new Set(installIds)).map((installId) =>
        ctx.db
          .query("events")
          .withIndex("by_installId", (q) => q.eq("installId", installId))
          .collect(),
      ),
    );
    return rows.flat().map((row) => ({
      name: row.name,
      installId: row.installId,
      clientTs: row.clientTs,
      serverTs: row.serverTs,
      props: row.props,
    }));
  },
});

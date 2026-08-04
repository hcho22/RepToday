import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { api } from "./_generated/api";
import type { AnalyticsEventName } from "./events";

/**
 * The client's only entry point.
 *
 * US-T01 returned a no-go on `convex-swift` (arm64-only xcframework), so `LiveAnalyticsService`
 * (US-T04) reaches this sink with a plain `URLSession` POST and no Convex SDK. That makes this
 * route load-bearing rather than convenience: see `artifacts/reports/US-T01/spike-note.md`.
 *
 * `Number(...)` on `clientTs` is the pinned numeric convention - it lands the timestamp as float64
 * to match the `v.number()` schema field regardless of how the client formatted it, so the
 * `int64`/`float64` trap never reaches the client. `props` is passed through untouched.
 */
const http = httpRouter();

http.route({
  path: "/logEvent",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      await ctx.runMutation(api.events.logEvent, {
        // A compile-time assertion only: the body is untrusted `any`, and the mutation's
        // `v.union` of the 13 literals is what actually rejects an unknown name at runtime.
        name: String(body.name) as AnalyticsEventName,
        installId: String(body.installId),
        clientTs: Number(body.clientTs),
        props: body.props ?? {},
      });
    } catch (error) {
      // The mutation's two validations (unknown event name, oversized property bag) and a
      // malformed body all land here. Nothing was inserted; answer 400 so the rejection is
      // observable. The client is fire-and-forget and ignores the status either way.
      return new Response(
        JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }
    return new Response(null, { status: 204 });
  }),
});

export default http;

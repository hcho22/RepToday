import { httpRouter } from "convex/server";
import { ConvexError } from "convex/values";
import { httpAction } from "./_generated/server";
import { api } from "./_generated/api";
import { EVENT_NAMES, type AnalyticsEventName } from "./events";

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

const jsonResponse = (status: number, error: string) =>
  new Response(JSON.stringify({ error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const isEventName = (value: unknown): value is AnalyticsEventName =>
  typeof value === "string" && (EVENT_NAMES as readonly string[]).includes(value);

/**
 * `logEvent` raises the rejections this sink asks for as `ConvexError`; anything else that escapes
 * it is a runtime or database failure, which is ours rather than the caller's. The `name` check is
 * a fallback for the class identity not surviving the `runMutation` boundary - it reads a
 * structured field of the error, not its message text.
 */
const rejectionMessage = (error: unknown): string | null => {
  if (error instanceof ConvexError) return String(error.data);
  if (error instanceof Error && error.name === "ConvexError") return error.message;
  return null;
};

http.route({
  path: "/logEvent",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    let body: Record<string, unknown>;
    try {
      const parsed = await request.json();
      if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
        return jsonResponse(400, "body must be a JSON object");
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return jsonResponse(400, "body is not valid JSON");
    }

    // The 13-name vocabulary is still enforced by the mutation's `v.union` - that stays the
    // contract. Checking it here as well makes the type below a fact rather than an assertion and
    // keeps an unknown name a rejection this handler classifies itself.
    if (!isEventName(body.name)) {
      return jsonResponse(400, "name must be one of the 13 pre-registered event names");
    }

    // Not new scope: this is "so a malformed client cannot poison the table" doing its stated job.
    // Coercing these two would have written the literal string "undefined" and `NaN` into exactly
    // the columns the funnel is counted on - `installId` is the cohort key K4 counts unique
    // installs by, `clientTs` is what K1 is timed from - and a junk row is worse than no row.
    // Presence only: no length, format, or shape constraint on what a legitimate client sends.
    if (typeof body.installId !== "string" || body.installId === "") {
      return jsonResponse(400, "installId must be a non-empty string");
    }

    // Still `Number(...)`: the pinned convention lands the timestamp as float64 however the client
    // formatted it, so the `int64`/`float64` trap never reaches Swift. The finite check only
    // rejects what would otherwise have been stored as `NaN` or a coerced-from-nothing zero; a
    // well-formed client sends a plain JSON number and is unaffected.
    const rawClientTs = body.clientTs;
    const clientTs =
      typeof rawClientTs === "number" ||
      (typeof rawClientTs === "string" && rawClientTs.trim() !== "")
        ? Number(rawClientTs)
        : Number.NaN;
    if (!Number.isFinite(clientTs)) {
      return jsonResponse(400, "clientTs must be a finite number of milliseconds since the epoch");
    }

    try {
      await ctx.runMutation(api.events.logEvent, {
        name: body.name,
        installId: body.installId,
        clientTs,
        props: body.props ?? {},
      });
    } catch (error) {
      const rejection = rejectionMessage(error);
      if (rejection !== null) {
        // A rejection the sink asked for (an oversized property bag). Nothing was inserted; answer
        // 400 and carry the message so the rejection is observable to a human.
        return jsonResponse(400, rejection);
      }
      // Anything else is a deployment, runtime, or database failure. US-T04 makes the client
      // strictly fire-and-forget - it swallows every error - so a sink outage reported as the
      // client's fault would be invisible: events would simply stop arriving and nothing would say
      // so. This 4xx/5xx split is the only signal a human watching the PMF test gets. The detail
      // stays in the deployment log rather than the response body.
      console.error("logEvent failed", error);
      return jsonResponse(500, "internal error");
    }
    return new Response(null, { status: 204 });
  }),
});

export default http;

import { httpRouter } from "convex/server";
import { convexToJson, type ConvexError, type Value } from "convex/values";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { EVENT_NAMES, type AnalyticsEventName } from "./events";

/**
 * The client's only entry point.
 *
 * US-T01 returned a no-go on `convex-swift` (arm64-only xcframework), so `LiveAnalyticsService`
 * (US-T04) reaches this sink with a plain `URLSession` POST and no Convex SDK. That makes this
 * route load-bearing rather than convenience: see `artifacts/reports/US-T01/spike-note.md`.
 *
 * `convex/http.test.ts` drives everything below in process with `convex-test`, against no
 * deployment - so the boundary this file is has a gate that re-runs, which is what US-T04 added.
 *
 * The pinned numeric convention is that `clientTs` crosses the wire as a plain JSON number. A JSON
 * number already *is* float64, which is what the `v.number()` schema field stores, so the
 * `int64`/`float64` trap the US-T01 spike documented - a Swift `Int` encoded by the SDK as
 * `{"$integer": …}` and refused by a `v.number()` field - never reaches the client. `props` is
 * passed through untouched.
 */
/**
 * Convex's runtime exposes deployment environment variables on `process.env`, but the deploy
 * tsconfig deliberately pulls in no `@types/node`, so `process` is untyped here. This minimal,
 * type-only declaration satisfies the typecheck for the one variable US-T14 reads
 * (`ANALYTICS_SHARED_SECRET`); it is erased at emit and never ships (the bundler also skips it as a
 * matter of course - `process` is a real global on the deployment).
 */
declare const process: { readonly env: Readonly<Record<string, string | undefined>> };

const http = httpRouter();

/**
 * The two caps the *action* enforces. (`props`'s 32-key / 4096-byte caps live in the mutation -
 * `MAX_PROPS_KEYS` / `MAX_PROPS_BYTES` in `events.ts`.) Both were gaps US-T03 shipped knowingly,
 * on the reasoning that nothing could reach this endpoint until a client existed; US-T04 is that
 * client, so they close here, together, because they are one shape of problem.
 *
 * `MAX_INSTALL_ID_BYTES`: `installId` was an unbounded `v.string()` while `props` was capped, which
 * made it the one client-controlled field with no ceiling - a hostile caller could push a row
 * toward Convex's ~1MB document limit through it, failing at the insert and so reported as *our*
 * `500` rather than the caller's `400`. US-T05's identifier is a UUIDv4, 36 ASCII characters, and
 * 64 bytes leaves room for a differently-shaped anonymous id while never admitting a large row. It
 * is a **length** bound and nothing else: no format check, no UUID-shape check. A later story is
 * free to change the identifier's shape, and this must not be the thing that forbids it.
 *
 * `MAX_REQUEST_BODY_BYTES`: the `props` caps live inside `logEvent`, so they run only *after*
 * `ctx.runMutation` has serialized its arguments - and Convex bounds those arguments (~24 MB,
 * measured against the dev deployment rather than assumed; see `convex/README.md`) far
 * above where the caps sit, so a multi-megabyte bag failed during argument serialization as a plain
 * `Error` and came back `500` rather than the `400` the caps promise, letting a caller manufacture
 * the sink's only outage signal. Measuring the request body before anything is parsed or serialized
 * classifies that as the caller fault it is. 64 KiB is deliberately an order of magnitude above the
 * 4096-byte `props` cap, so across the range a real client could send it does not pre-empt the
 * mutation's own more specific rejection - a 5 KiB bag still comes back with the byte-count message
 * naming the real limit. It is not an absolute ordering: a bag past 64 KiB is answered by this cap
 * rather than the props one, which is still a caller's `400`, just the less specific of the two. And
 * being three orders of magnitude below Convex's argument bound, serialization can no longer be
 * reached by size.
 */
export const MAX_INSTALL_ID_BYTES = 64;
export const MAX_REQUEST_BODY_BYTES = 64 * 1024;

/**
 * US-T14's shared-secret header (its name only; the value is a per-deployment Convex environment
 * variable, `ANALYTICS_SHARED_SECRET`, and never appears in source). The client embeds the matching
 * value from a per-configuration build setting and sends it on every POST.
 *
 * **This is a cost-raiser, not a guarantee, and the honesty of that claim is a criterion.** The
 * secret is embedded in the shipped app binary, so anyone willing to unpack the app can extract it.
 * It stops opportunistic flooding of a freshly-discovered endpoint URL - the case this guard exists
 * for - but it does not stop a determined attacker who reads the secret out of the binary. See
 * `convex/README.md`.
 */
export const ANALYTICS_SECRET_HEADER = "X-RepToday-Analytics-Secret";

/**
 * A length-checked, constant-time string comparison, so the secret check does not leak the secret
 * one byte at a time through response timing. The threat is largely theoretical here - the secret
 * is extractable from the binary anyway, so a timing side channel buys an attacker nothing they
 * could not get more cheaply - but the comparison is cheap and removes the question.
 */
const secretsMatch = (presented: string, expected: string): boolean => {
  if (presented.length !== expected.length) {
    return false;
  }
  let mismatch = 0;
  for (let i = 0; i < presented.length; i++) {
    mismatch |= presented.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return mismatch === 0;
};

/**
 * The coarse source IP the rate-limit backstop keys on, or `null` when the edge handed the action
 * no usable client address. `x-forwarded-for`'s first hop is the conventional client address;
 * `cf-connecting-ip` is Convex's Cloudflare-edge fallback. Both are set by the edge and can be
 * spoofed or flattened by a proxy - which is exactly why the IP is a *backstop* to the per-install
 * key, not the primary one, and why `convex/README.md` states its limits plainly.
 */
const clientIpFrom = (request: Request): string | null => {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  const cloudflare = request.headers.get("cf-connecting-ip")?.trim();
  return cloudflare ? cloudflare : null;
};

const jsonResponse = (status: number, error: string) =>
  new Response(JSON.stringify({ error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const isEventName = (value: unknown): value is AnalyticsEventName =>
  typeof value === "string" && (EVENT_NAMES as readonly string[]).includes(value);

/**
 * `logEvent` raises the rejections this sink asks for as `ConvexError`; anything else that escapes
 * it is a runtime or database failure, which is ours rather than the caller's. The SDK reconstructs
 * a cross-isolate throw as a genuine `ConvexError` when it carries `data`, and as a plain `Error`
 * otherwise, so that one marker is the whole test - and only the error's structured `data` is ever
 * echoed, never a message text.
 *
 * The marker is read the way the SDK itself reads it (`registration_impl.ts` uses
 * `Symbol.for("ConvexError") in thrown`) rather than by `instanceof`. Class identity is not a safe
 * discriminator here: the package ships physically distinct copies of the class under `dist/cjs`
 * and `dist/esm`, and the copy `performAsyncSyscall` constructs from is reached by a relative
 * import rather than the `convex/values` specifier this file uses. If those ever resolve to two
 * copies, `instanceof` fails and every property-bag rejection silently becomes a 500 - the false
 * outage signal this split exists to prevent. `Symbol.for` is registry-global, so it does not care.
 */
const rejectionMessage = (error: unknown): string | null => {
  if (typeof error === "object" && error !== null && Symbol.for("ConvexError") in error) {
    return String((error as ConvexError<Value>).data);
  }
  return null;
};

/**
 * `ctx.runMutation` serializes its arguments with the SDK's own `convexToJson` inside this isolate
 * before anything is sent, and that serializer refuses a field name which starts with `$`, carries
 * a non-ASCII or control character, or runs past 1024 characters. Such a `props` key is therefore
 * already rejected today - it just throws a plain `Error` rather than the mutation's `ConvexError`,
 * so it lands on the wrong side of the split below and is reported as our outage instead of the
 * caller's mistake. Running the same serializer up front corrects that classification without
 * adding a rejection: it is not a rule of ours, so it cannot drift from what Convex enforces, and
 * it inspects field names only - the per-key and per-type checks of `props` the story forbids stay
 * absent.
 */
const isSerializableAsArgs = (args: unknown): boolean => {
  try {
    convexToJson(args as Value);
    return true;
  } catch {
    return false;
  }
};

http.route({
  path: "/logEvent",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    // Shared secret first - a header check, so an unauthenticated flood is rejected before the body
    // is even buffered (US-T14). Both this and the rate-limit check below run *before*
    // `ctx.runMutation`, so a rejected request never inserts a row - the whole point of the guard.
    const expectedSecret = process.env.ANALYTICS_SHARED_SECRET;
    if (!expectedSecret) {
      // Fail closed on *our* misconfiguration. An unguarded sink taking writes is the exact failure
      // this story prevents, so a loud 500 is safer than silently accepting unauthenticated writes.
      // This is deliberately the `5xx` (ours) side of the split, not the `4xx` (caller's) side: no
      // caller can cause it, and it is the one the operator must see. Documented in the README.
      console.error("ANALYTICS_SHARED_SECRET is not configured; refusing all writes to keep the sink guarded");
      return jsonResponse(500, "internal error");
    }
    const presentedSecret = request.headers.get(ANALYTICS_SECRET_HEADER);
    if (presentedSecret === null || !secretsMatch(presentedSecret, expectedSecret)) {
      // A caller fault: missing or wrong credential. `401`, never `5xx`, so it never looks like a
      // sink outage on the `4xx`/`5xx` signal a human watches during the PMF test.
      return jsonResponse(401, "missing or invalid analytics secret");
    }

    // Size first, before the body is even parsed. This is what keeps an oversized payload from
    // reaching `ctx.runMutation` and failing during argument serialization as a plain `Error` -
    // which would answer `500` and so let a caller fake an outage. See `MAX_REQUEST_BODY_BYTES`.
    // Measured on the raw bytes rather than on the decoded string, because the limit is bytes and
    // a JS string's length counts UTF-16 code units - the same distinction the `props` byte cap
    // makes for the same reason.
    const rawBody = await request.arrayBuffer();
    if (rawBody.byteLength > MAX_REQUEST_BODY_BYTES) {
      return jsonResponse(
        400,
        `body is ${rawBody.byteLength} bytes, over the ${MAX_REQUEST_BODY_BYTES}-byte limit`,
      );
    }

    let body: Record<string, unknown>;
    try {
      const parsed = JSON.parse(new TextDecoder().decode(rawBody));
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
    // Presence, kind, and - since US-T04 put a real identifier on the wire - length. Still no
    // format or shape constraint on what a legitimate client sends.
    if (typeof body.installId !== "string" || body.installId === "") {
      return jsonResponse(400, "installId must be a non-empty string");
    }
    const installIdBytes = new TextEncoder().encode(body.installId).length;
    if (installIdBytes > MAX_INSTALL_ID_BYTES) {
      return jsonResponse(
        400,
        `installId is ${installIdBytes} bytes, over the ${MAX_INSTALL_ID_BYTES}-byte limit`,
      );
    }

    // An actual JSON number, which is what the contract says and what a well-formed client sends -
    // and, being float64 already, is exactly why the `int64`/`float64` trap never reaches Swift.
    // Coercing a numeric string instead would let `"1e3"` or `"0x1f"` land silently in the column
    // K1 is timed from, so the kind check is the whole point rather than an obstacle to route past.
    const clientTs = body.clientTs;
    if (typeof clientTs !== "number" || !Number.isFinite(clientTs)) {
      return jsonResponse(400, "clientTs must be a finite number of milliseconds since the epoch");
    }

    // Rate limit (US-T14), keyed on the per-install identifier just validated and, as a backstop,
    // the coarse source IP. This runs *before* the insert, and the whole read-increment-compare is
    // one serializable mutation, so two concurrent floods for the same key cannot both slip under
    // the ceiling. The window is anchored to *server* time (`Date.now()`), never the client-supplied
    // `clientTs`, which a flooder controls and could pin to keep landing in a fresh window. An
    // over-ceiling request is a `429` with no insert - a caller fault, never `5xx`.
    const decision = await ctx.runMutation(internal.rateLimit.checkAndBump, {
      installId: body.installId,
      sourceIp: clientIpFrom(request),
      nowMs: Date.now(),
    });
    if (!decision.allowed) {
      return jsonResponse(429, `rate limit exceeded (${decision.limitedBy})`);
    }

    // `props` is the one optional field, so an absent bag - and a `null` one, which `??` treats the
    // same way - becomes `{}` rather than a rejection. That coercion is deliberate and is not the
    // one refused two checks above: `installId` and `clientTs` are the columns K4 and K1 are counted
    // from, where a coerced value is junk sitting in a counted column looking valid. Nothing is
    // counted from `props` - it has no schema and is stored as it arrived - so an empty bag is a
    // truthful "this event carried no properties", not a fabricated value. A bag that is a non-null
    // non-object still fails in the mutation, since a bag that is not a bag has no size to check.
    const args = {
      name: body.name,
      installId: body.installId,
      clientTs,
      props: body.props ?? {},
    };

    if (!isSerializableAsArgs(args)) {
      return jsonResponse(400, "props contains a field name Convex cannot store");
    }

    try {
      await ctx.runMutation(internal.events.logEvent, args);
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

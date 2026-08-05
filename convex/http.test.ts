import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "./schema";
import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { EVENT_NAMES, MAX_PROPS_BYTES, MAX_PROPS_KEYS, logEvent } from "./events";
import { MAX_INSTALL_ID_BYTES, MAX_REQUEST_BODY_BYTES } from "./http";

/**
 * Behavioural coverage of the sink's single entry point, `POST /logEvent` (US-T04).
 *
 * US-T03 built this boundary over three review rounds and then scoped its own verification to
 * `npm run typecheck` plus a one-time live transcript - honest, but nothing that re-runs: `tsc`
 * cannot catch a regression in a validation rule, and this repo has no CI. Everything those rounds
 * established is asserted here instead, plus the two hardening rules US-T04 adds.
 *
 * `convex-test` runs the real functions in process against an in-memory database, so none of this
 * needs a deployment and none of it touches the network.
 *
 * The load-bearing half of nearly every rejection assertion is the row count: a `400` that inserted
 * anyway would be worse than no check at all, so each one reads the table back rather than trusting
 * the status.
 */

/**
 * The function modules `convex-test` loads. Convex's own docs suggest an extglob for this; it
 * matches nothing under this Vite version, which fails as an empty module map rather than loudly,
 * so the two plain globs are combined and filtered here instead. `_generated` **must** be included
 * (`convex-test` locates the functions root through it), while type declarations and this file are
 * not functions.
 */
const modules: Record<string, () => Promise<any>> = Object.fromEntries(
  Object.entries({
    ...import.meta.glob("./**/*.ts"),
    ...import.meta.glob("./**/*.js"),
  }).filter(([path]) => !path.endsWith(".d.ts") && !path.endsWith(".test.ts")),
);

const VALID_INSTALL_ID = "902676E9-2278-4CFE-871C-EEB9BC508A55";
const VALID_CLIENT_TS = 1_785_715_200_000;

const setup = () => convexTest(schema, modules);

/**
 * The same sink with `logEvent` swapped for one that fails the way a deployment, runtime, or
 * database failure fails: a plain `Error`, not the `ConvexError` the sink's own rejections carry.
 *
 * The action resolves `internal.events.logEvent` through the module map, so overriding that one
 * entry reaches the call `ctx.runMutation` makes without touching `http.ts` or the real mutation.
 * `http.ts`'s static import of `EVENT_NAMES` is resolved by the bundler and is unaffected, so the
 * 13-name check still runs exactly as it does in production.
 */
const failingSink = () =>
  convexTest(schema, {
    ...modules,
    "./events.ts": async () => ({
      ...(await import("./events")),
      logEvent: internalMutation({
        args: { name: v.string(), installId: v.string(), clientTs: v.number(), props: v.any() },
        handler: async () => {
          throw new Error("db unavailable at secret-connection-string");
        },
      }),
    }),
  });

const post = (t: ReturnType<typeof setup>, body: unknown, raw = false) =>
  t.fetch("/logEvent", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: raw ? (body as string) : JSON.stringify(body),
  });

const validBody = (overrides: Record<string, unknown> = {}) => ({
  name: "session_completed",
  installId: VALID_INSTALL_ID,
  clientTs: VALID_CLIENT_TS,
  props: { requested_minutes: 15, completed_minutes: 15, was_return: false },
  ...overrides,
});

const rows = (t: ReturnType<typeof setup>) => t.run(async (ctx) => await ctx.db.query("events").collect());

/** Every rejection must be a `400` that carries a message *and* inserts nothing. */
const expectRejected = async (response: Response, t: ReturnType<typeof setup>) => {
  expect(response.status).toBe(400);
  expect(response.headers.get("Content-Type")).toBe("application/json");
  const payload = await response.json();
  expect(typeof payload.error).toBe("string");
  expect(payload.error.length).toBeGreaterThan(0);
  expect(await rows(t)).toHaveLength(0);
  return payload.error as string;
};

describe("POST /logEvent - the happy path", () => {
  test("a valid event answers 204 with no body and inserts exactly one row", async () => {
    const t = setup();
    const before = Date.now();
    const response = await post(t, validBody());

    expect(response.status).toBe(204);
    expect(await response.text()).toBe("");

    const inserted = await rows(t);
    expect(inserted).toHaveLength(1);
    expect(inserted[0].name).toBe("session_completed");
    expect(inserted[0].installId).toBe(VALID_INSTALL_ID);
    // The client's timestamp is stored as sent; the server stamps its own beside it.
    expect(inserted[0].clientTs).toBe(VALID_CLIENT_TS);
    expect(inserted[0].serverTs).toBeGreaterThanOrEqual(before);
    // `props` is stored exactly as it arrived - no coercion, no reshaping, no dropped keys.
    expect(inserted[0].props).toEqual({
      requested_minutes: 15,
      completed_minutes: 15,
      was_return: false,
    });
  });

  test("props is the one optional field: omitting it stores an empty bag", async () => {
    const t = setup();
    const response = await post(t, {
      name: "week_active",
      installId: VALID_INSTALL_ID,
      clientTs: VALID_CLIENT_TS,
    });

    expect(response.status).toBe(204);
    expect((await rows(t))[0].props).toEqual({});
  });

  test("the sink is append-only: two events are two rows, never a merge or a dedup", async () => {
    const t = setup();
    await post(t, validBody({ name: "session_started" }));
    await post(t, validBody({ name: "session_started" }));
    expect(await rows(t)).toHaveLength(2);
  });
});

describe("POST /logEvent - the 13-name vocabulary is a wire contract", () => {
  test("every pre-registered name is accepted", async () => {
    for (const name of EVENT_NAMES) {
      const t = setup();
      const response = await post(t, validBody({ name }));
      expect(response.status, `${name} was rejected`).toBe(204);
      expect((await rows(t))[0].name).toBe(name);
    }
  });

  test("the vocabulary is exactly 13 names, and the two web-side events are not among them", () => {
    expect(EVENT_NAMES).toHaveLength(13);
    expect(EVENT_NAMES).not.toContain("landing_page_view");
    expect(EVENT_NAMES).not.toContain("waitlist_signup");
  });

  test.each([
    ["an unregistered name", "landing_page_view"],
    ["a near-miss of a real name", "session_complete"],
    ["an empty name", ""],
    ["a non-string name", 7],
    ["a missing name", undefined],
  ])("%s is rejected without inserting", async (_label, name) => {
    const t = setup();
    const body: Record<string, unknown> = validBody();
    if (name === undefined) delete body.name;
    else body.name = name;
    await expectRejected(await post(t, body), t);
  });
});

describe("POST /logEvent - installId is present, a string, and bounded", () => {
  test.each([
    ["missing", undefined],
    ["empty", ""],
    ["a number", 12345],
    ["null", null],
    ["an object", { id: "x" }],
  ])("an installId that is %s is rejected without inserting", async (_label, installId) => {
    const t = setup();
    const body: Record<string, unknown> = validBody();
    if (installId === undefined) delete body.installId;
    else body.installId = installId;
    await expectRejected(await post(t, body), t);
  });

  test("coercion never happens: a missing installId does not become the string \"undefined\"", async () => {
    const t = setup();
    const body: Record<string, unknown> = validBody();
    delete body.installId;
    await post(t, body);
    expect(await rows(t)).toHaveLength(0);
  });

  test(`an installId at exactly ${MAX_INSTALL_ID_BYTES} bytes is accepted`, async () => {
    const t = setup();
    const response = await post(t, validBody({ installId: "a".repeat(MAX_INSTALL_ID_BYTES) }));
    expect(response.status).toBe(204);
    expect((await rows(t))[0].installId).toHaveLength(MAX_INSTALL_ID_BYTES);
  });

  test("US-T05's UUIDv4 fits well inside the bound", () => {
    expect(VALID_INSTALL_ID.length).toBe(36);
    expect(VALID_INSTALL_ID.length).toBeLessThan(MAX_INSTALL_ID_BYTES);
  });

  test("an installId one byte over the bound is rejected without inserting (US-T04)", async () => {
    const t = setup();
    const error = await expectRejected(
      await post(t, validBody({ installId: "a".repeat(MAX_INSTALL_ID_BYTES + 1) })),
      t,
    );
    expect(error).toContain(`${MAX_INSTALL_ID_BYTES}-byte limit`);
  });

  test("a hostile multi-hundred-KB installId is a 400, not the 500 it used to be", async () => {
    const t = setup();
    const response = await post(t, validBody({ installId: "a".repeat(300_000) }));
    // Caught by the request-size cap before the identifier cap even runs - both are caller faults,
    // and the point is that neither reaches the insert and reports as the sink's own failure.
    expect(response.status).toBe(400);
    expect(await rows(t)).toHaveLength(0);
  });

  test("the bound is length only: it makes no claim about format", async () => {
    const t = setup();
    // Not a UUID at all, but short and non-empty - the sink deliberately does not police shape.
    const response = await post(t, validBody({ installId: "not-a-uuid" }));
    expect(response.status).toBe(204);
    expect((await rows(t))[0].installId).toBe("not-a-uuid");
  });

  test("the bound counts UTF-8 bytes, not UTF-16 code units", async () => {
    const t = setup();
    // 33 three-byte characters: 33 UTF-16 code units (under the bound if measured wrong), 99 bytes.
    const multiByte = "あ".repeat(33);
    expect(multiByte.length).toBeLessThan(MAX_INSTALL_ID_BYTES);
    expect(new TextEncoder().encode(multiByte).length).toBeGreaterThan(MAX_INSTALL_ID_BYTES);
    const error = await expectRejected(await post(t, validBody({ installId: multiByte })), t);
    expect(error).toContain(`${MAX_INSTALL_ID_BYTES}-byte limit`);
  });
});

describe("POST /logEvent - clientTs is an actual finite JSON number", () => {
  test.each([
    ["missing", undefined],
    ["a numeric string", "1785715200000"],
    ["an exponent string", "1e3"],
    ["a hex string", "0x1f"],
    ["null", null],
    ["a boolean", true],
  ])("a clientTs that is %s is rejected without inserting", async (_label, clientTs) => {
    const t = setup();
    const body: Record<string, unknown> = validBody();
    if (clientTs === undefined) delete body.clientTs;
    else body.clientTs = clientTs;
    await expectRejected(await post(t, body), t);
  });

  test("a non-finite number is rejected: JSON.parse turns 1e400 into Infinity", async () => {
    const t = setup();
    // Written as raw text because `JSON.stringify(Infinity)` is `null` - the only way this value
    // reaches the action is straight off the wire, which is exactly how a real caller would send it.
    const raw = `{"name":"week_active","installId":"${VALID_INSTALL_ID}","clientTs":1e400,"props":{}}`;
    expect(JSON.parse(raw).clientTs).toBe(Infinity);
    await expectRejected(await post(t, raw, true), t);
  });

  test("the check is presence and kind only - an absurd but finite timestamp lands", async () => {
    const t = setup();
    // Documented on purpose (`convex/README.md`): range and sanity belong to a query written later
    // against the raw rows, where they can be revised without a deploy.
    expect((await post(t, validBody({ clientTs: 0 }))).status).toBe(204);
    expect((await rows(t))[0].clientTs).toBe(0);
  });
});

describe("POST /logEvent - the body itself", () => {
  test.each([
    ["not valid JSON", "{"],
    ["empty", ""],
    ["a JSON array", "[]"],
    ["a JSON string", '"hello"'],
    ["a JSON number", "42"],
    ["null", "null"],
  ])("a body that is %s is rejected without inserting", async (_label, raw) => {
    const t = setup();
    await expectRejected(await post(t, raw, true), t);
  });

  test("a body over the request-size cap is the caller's 400, not the sink's 500 (US-T04)", async () => {
    const t = setup();
    // Under Convex's ~8 MiB argument bound but far over the caps: before this story it failed
    // during argument serialization as a plain Error and answered 500, letting any caller
    // manufacture the sink's only outage signal.
    const oversized = validBody({ props: { blob: "x".repeat(MAX_REQUEST_BODY_BYTES + 1_000) } });
    const error = await expectRejected(await post(t, oversized), t);
    expect(error).toContain(`${MAX_REQUEST_BODY_BYTES}-byte limit`);
  });

  test("the request-size cap does not pre-empt the more specific props cap", async () => {
    const t = setup();
    // Over the 4096-byte props cap, under the 64 KiB request cap: the caller must still be told
    // which limit it actually broke.
    const error = await expectRejected(
      await post(t, validBody({ props: { blob: "x".repeat(MAX_PROPS_BYTES + 100) } })),
      t,
    );
    expect(error).toContain(`${MAX_PROPS_BYTES}-byte limit`);
  });
});

describe("POST /logEvent - the property-bag caps", () => {
  test(`exactly ${MAX_PROPS_KEYS} keys is accepted; one more is rejected`, async () => {
    const atLimit = Object.fromEntries(
      Array.from({ length: MAX_PROPS_KEYS }, (_, index) => [`k${index}`, index]),
    );
    const accepted = setup();
    expect((await post(accepted, validBody({ props: atLimit }))).status).toBe(204);

    const rejected = setup();
    const error = await expectRejected(
      await post(rejected, validBody({ props: { ...atLimit, one_too_many: 1 } })),
      rejected,
    );
    expect(error).toContain(`${MAX_PROPS_KEYS}-key limit`);
  });

  test("the byte cap counts UTF-8, not UTF-16 code units", async () => {
    const t = setup();
    // 2000 three-byte characters: 2000 UTF-16 code units (well under 4096 if measured wrong) but
    // 6000 UTF-8 bytes. Measuring with `String.length` would let this through against a limit
    // whose name says bytes.
    const bag = { note: "あ".repeat(2_000) };
    expect(JSON.stringify(bag).length).toBeLessThan(MAX_PROPS_BYTES);
    expect(new TextEncoder().encode(JSON.stringify(bag)).length).toBeGreaterThan(MAX_PROPS_BYTES);
    const error = await expectRejected(await post(t, validBody({ props: bag })), t);
    expect(error).toContain(`${MAX_PROPS_BYTES}-byte limit`);
  });

  test.each([
    ["an array", [1, 2, 3]],
    ["a string", "not a bag"],
    ["a number", 7],
  ])("a props that is %s is rejected without inserting", async (_label, props) => {
    const t = setup();
    await expectRejected(await post(t, validBody({ props })), t);
  });

  test("there is no per-key or per-type schema on props: an unregistered key lands", async () => {
    const t = setup();
    // Deliberate: property vocabularies are expected to move during the PMF test, and a write-path
    // check would turn every such move into a deploy.
    const response = await post(t, validBody({ props: { some_future_key: "whatever", n: 1.5 } }));
    expect(response.status).toBe(204);
    expect((await rows(t))[0].props).toEqual({ some_future_key: "whatever", n: 1.5 });
  });
});

describe("POST /logEvent - the 4xx/5xx split", () => {
  test("a props field name Convex cannot store is classified as the caller's 400, not a 500", async () => {
    // The `convexToJson` pre-pass. Without it, `ctx.runMutation`'s own serialization throws a plain
    // Error and the caller's mistake is reported as our outage.
    for (const key of ["$leading_dollar", "controlchar", "x".repeat(1_100)]) {
      const t = setup();
      const response = await post(t, validBody({ props: { [key]: 1 } }));
      expect(response.status, `props key ${JSON.stringify(key.slice(0, 20))} was not a 400`).toBe(400);
      expect(await rows(t)).toHaveLength(0);
    }
  });

  test("a failure the sink did not ask for is a 500 that echoes no internal detail", async () => {
    // The other half of the split, and the half that cannot be reached by any input: a deployment,
    // runtime, or database failure throws a plain `Error` rather than the `ConvexError` the sink's
    // own rejections carry. It is produced here by swapping the mutation the action calls for one
    // that throws - see `failingSink` - because the alternative is asserting nothing about the
    // branch that decides whether a human watching the PMF test sees an outage or a client bug.
    //
    // The thrown message is deliberately something that must never be echoed. A `500` body that
    // carried it would leak deployment internals to anyone who can reach the public route.
    const t = failingSink();
    const response = await post(t, validBody());
    const raw = await response.text();

    expect(response.status).toBe(500);
    expect(JSON.parse(raw)).toEqual({ error: "internal error" });
    expect(raw).not.toContain("secret-connection-string");
    expect(await rows(t)).toHaveLength(0);
  });

  test("a 400 carries the rejection's own message so a human can read it", async () => {
    const t = setup();
    const response = await post(t, validBody({ name: "not_an_event" }));
    const payload = await response.json();
    expect(payload.error).toContain("13 pre-registered event names");
  });

  test("every non-204 answer is application/json in one shape", async () => {
    const t = setup();
    for (const body of [validBody({ name: "nope" }), validBody({ installId: "" })]) {
      const response = await post(t, body);
      expect(response.headers.get("Content-Type")).toBe("application/json");
      expect(Object.keys(await response.json())).toEqual(["error"]);
    }
  });
});

describe("the HTTP action is the sink's single entry point", () => {
  test("logEvent is an internalMutation, so it is not on the public API", () => {
    // A public Convex function is callable directly on the deployment's own
    // `.convex.cloud/api/mutation` endpoint, under the same slug the `.convex.site` URL a shipped
    // client carries uses - a second way in that skips every check above. Observed live during
    // US-T03, inserting a row with an empty installId. This is what keeps it closed.
    //
    // Asserted on the registration object's own flags rather than on `api.events.logEvent`, which
    // cannot say anything: the generated `api` is `anyApi`, a proxy that answers *every* property
    // access with a function reference whether the function exists or not. `isInternal` is the flag
    // Convex's own `internalMutationGeneric` sets and the server reads to decide what is publicly
    // callable, so it is the fact rather than a stand-in for it - flipping `internalMutation` back
    // to `mutation` fails here.
    const registration = logEvent as unknown as { isMutation?: boolean; isInternal?: boolean };
    expect(registration.isMutation).toBe(true);
    expect(registration.isInternal).toBe(true);
  });

  test("only POST is routed", async () => {
    const t = setup();
    const response = await t.fetch("/logEvent", { method: "GET" });
    expect(response.status).not.toBe(204);
    expect(await rows(t)).toHaveLength(0);
  });
});

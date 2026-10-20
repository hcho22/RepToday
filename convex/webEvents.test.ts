import { convexTest } from "convex-test";
import { afterAll, beforeEach, describe, expect, test } from "vitest";
import schema from "./schema";
import { internal } from "./_generated/api";
import { EVENT_NAMES } from "./events";
import {
  ANALYTICS_SECRET_HEADER,
  DEFAULT_WEB_EVENT_ORIGINS,
  MAX_WEB_EVENT_BODY_BYTES,
} from "./http";
import {
  MAX_WEB_EVENTS_PER_IP_PER_WINDOW,
  MAX_WEB_EVENTS_PER_WINDOW,
  RATE_LIMIT_WINDOW_MS,
} from "./rateLimit";
import { WEB_EVENT_INSTALL_ID, WEB_EVENT_NAMES, WEB_REFERRER_SOURCES } from "./webEvents";
import contractText from "../tools/waitlist/contract.json?raw";

declare const process: { env: Record<string, string | undefined> };

/**
 * Behavioural coverage of the Waitlist's web-event route, `POST /webEvent` (US-WL05).
 *
 * Runs in process against `convex-test`'s in-memory database: no deployment, no network. As in
 * `http.test.ts`, the half of each rejection assertion that matters is the row count, because a `400`
 * that inserted anyway would be worse than no check. The app's own route is exercised here only to
 * show it is unchanged: `landing_page_view` is still not one of its 13 names.
 */
const modules: Record<string, () => Promise<any>> = Object.fromEntries(
  Object.entries({
    ...import.meta.glob("./**/*.ts"),
    ...import.meta.glob("./**/*.js"),
  }).filter(([path]) => !path.endsWith(".d.ts") && !path.endsWith(".test.ts")),
);

const SITE = "https://reptoday.app";
/** The Waitlist contract file (`tools/waitlist/contract.json`), the one owner of the Source vocabulary. */
const contract = JSON.parse(contractText) as { source_tags: string[]; unknown_source: string; no_source_event: string };
const setup = () => convexTest(schema, modules);

const originalOrigins = process.env.WEB_EVENT_ALLOWED_ORIGINS;
const originalSecret = process.env.ANALYTICS_SHARED_SECRET;
beforeEach(() => {
  delete process.env.WEB_EVENT_ALLOWED_ORIGINS;
  delete process.env.ANALYTICS_SHARED_SECRET;
});
afterAll(() => {
  if (originalOrigins === undefined) delete process.env.WEB_EVENT_ALLOWED_ORIGINS;
  else process.env.WEB_EVENT_ALLOWED_ORIGINS = originalOrigins;
  if (originalSecret === undefined) delete process.env.ANALYTICS_SHARED_SECRET;
  else process.env.ANALYTICS_SHARED_SECRET = originalSecret;
});

/** A page's post: `text/plain`, an `Origin`, and no secret and no custom header. */
const postWeb = (
  t: ReturnType<typeof setup>,
  body: unknown,
  options: { origin?: string | null; raw?: boolean; headers?: Record<string, string> } = {},
) => {
  const { origin = SITE, raw = false, headers = {} } = options;
  return t.fetch("/webEvent", {
    method: "POST",
    headers: {
      "Content-Type": "text/plain;charset=UTF-8",
      ...(origin === null ? {} : { Origin: origin }),
      ...headers,
    },
    body: raw ? (body as string) : JSON.stringify(body),
  });
};

const event = (name = "landing_page_view", source = "none") => ({ name, props: { referrer_source: source } });
const rows = (t: ReturnType<typeof setup>) => t.run(async (ctx) => ctx.db.query("events").collect());
const buckets = (t: ReturnType<typeof setup>) => t.run(async (ctx) => ctx.db.query("rateLimits").collect());

describe("POST /webEvent: accepted bodies", () => {
  test("a landing_page_view with no tag stores one row of exactly the two fields it may carry", async () => {
    const t = setup();
    const response = await postWeb(t, event("landing_page_view", "none"));
    expect(response.status).toBe(204);
    const stored = await rows(t);
    expect(stored).toHaveLength(1);
    expect(stored[0].name).toBe("landing_page_view");
    expect(stored[0].installId).toBe(WEB_EVENT_INSTALL_ID);
    expect(stored[0].props).toEqual({ referrer_source: "none" });
    expect(stored[0]).not.toHaveProperty("eventId");
    expect(stored[0].clientTs).toBe(stored[0].serverTs);
  });

  test("both names accept every tag and none, and nothing else is stored", async () => {
    const t = setup();
    for (const name of WEB_EVENT_NAMES) {
      for (const source of WEB_REFERRER_SOURCES) {
        expect((await postWeb(t, event(name, source))).status).toBe(204);
      }
    }
    const stored = await rows(t);
    expect(stored).toHaveLength(WEB_EVENT_NAMES.length * WEB_REFERRER_SOURCES.length);
    for (const row of stored) {
      expect(Object.keys(row.props)).toEqual(["referrer_source"]);
      expect(row.installId).toBe("web");
    }
    expect(JSON.stringify(stored)).not.toContain("@");
  });

  test("the route accepts exactly the contract file's Source tags and its no-tag value, and not the sign-up's unknown", async () => {
    const wanted = [...contract.source_tags, contract.no_source_event];
    expect([...WEB_REFERRER_SOURCES].sort()).toEqual([...wanted].sort());
    const t = setup();
    for (const name of WEB_EVENT_NAMES) {
      for (const source of wanted) {
        expect((await postWeb(t, event(name, source))).status).toBe(204);
      }
      expect((await postWeb(t, event(name, contract.unknown_source))).status).toBe(400);
    }
    expect(await rows(t)).toHaveLength(WEB_EVENT_NAMES.length * wanted.length);
  });

  test("the site's www origin is accepted too, and no secret is needed", async () => {
    const t = setup();
    expect((await postWeb(t, event(), { origin: "https://www.reptoday.app" })).status).toBe(204);
    expect(DEFAULT_WEB_EVENT_ORIGINS).toEqual(["https://reptoday.app", "https://www.reptoday.app"]);
  });
});

describe("POST /webEvent: rejections insert nothing", () => {
  const rejected = async (body: unknown, options = {}) => {
    const t = setup();
    const response = await postWeb(t, body, options);
    expect(await rows(t)).toHaveLength(0);
    return response.status;
  };

  test("an extra property is refused", async () => {
    expect(await rejected({ name: "landing_page_view", props: { referrer_source: "none", extra: 1 } })).toBe(400);
    expect(await rejected({ name: "waitlist_signup", props: { referrer_source: "tiktok", entry: "abc" } })).toBe(400);
  });

  test("a missing, renamed or non-object property bag is refused", async () => {
    expect(await rejected({ name: "landing_page_view", props: {} })).toBe(400);
    expect(await rejected({ name: "landing_page_view" })).toBe(400);
    expect(await rejected({ name: "landing_page_view", props: { source: "none" } })).toBe(400);
    expect(await rejected({ name: "landing_page_view", props: [] })).toBe(400);
    expect(await rejected({ name: "landing_page_view", props: null })).toBe(400);
  });

  test("a name outside the two is refused, the app's included", async () => {
    for (const name of ["session_started", "app_install", "week_active", "", "LANDING_PAGE_VIEW", "waitlist_signup "]) {
      expect(await rejected({ name, props: { referrer_source: "none" } })).toBe(400);
    }
  });

  test("referrer_source is the visit's tag or none and never unknown, a UTM value or free text", async () => {
    for (const value of ["unknown", "TikTok", "utm", "twitter", "", " none", "tiktok,reddit", 7, null, true, ["none"]]) {
      expect(await rejected({ name: "landing_page_view", props: { referrer_source: value } })).toBe(400);
    }
    const address = "someone" + "@" + "example.test";
    expect(await rejected({ name: "waitlist_signup", props: { referrer_source: address } })).toBe(400);
  });

  test("any other top-level field is refused: no address, entry, identifier, timestamp or event id", async () => {
    const address = "someone" + "@" + "example.test";
    for (const extra of [{ email: address }, { entry: "abc123" }, { installId: "x" }, { clientTs: 1 }, { eventId: "e1" }, { name2: "x" }]) {
      expect(await rejected({ ...event(), ...extra })).toBe(400);
    }
  });

  test("a body that is not an object, not JSON, or over the cap is refused", async () => {
    const t = setup();
    expect((await postWeb(t, "not json", { raw: true })).status).toBe(400);
    expect((await postWeb(t, "[1]", { raw: true })).status).toBe(400);
    expect((await postWeb(t, "null", { raw: true })).status).toBe(400);
    expect((await postWeb(t, "", { raw: true })).status).toBe(400);
    const big = JSON.stringify({ ...event(), pad: "x".repeat(MAX_WEB_EVENT_BODY_BYTES) });
    expect((await postWeb(t, big, { raw: true })).status).toBe(400);
    expect(await rows(t)).toHaveLength(0);
  });

  test("a missing or foreign origin is refused", async () => {
    for (const origin of [null, "http://localhost:8788", "https://reptoday.app.example.test", "http://reptoday.app", "https://evil.example", "null", "https://reptoday.app/"]) {
      expect(await rejected(event(), { origin })).toBe(403);
    }
  });

  test("the app's route is unchanged: a web name posted there is still refused", async () => {
    process.env.ANALYTICS_SHARED_SECRET = "test-secret";
    const t = setup();
    for (const name of WEB_EVENT_NAMES) {
      const response = await t.fetch("/logEvent", {
        method: "POST",
        headers: { "Content-Type": "application/json", [ANALYTICS_SECRET_HEADER]: "test-secret" },
        body: JSON.stringify({ name, installId: "902676E9-2278-4CFE-871C-EEB9BC508A55", clientTs: 1_785_715_200_000, props: { referrer_source: "none" } }),
      });
      expect(response.status).toBe(400);
    }
    expect(await rows(t)).toHaveLength(0);
    expect(EVENT_NAMES).toHaveLength(13);
    for (const name of WEB_EVENT_NAMES) expect(EVENT_NAMES as readonly string[]).not.toContain(name);
  });

  test("a web post never reaches the app's route shape: GET and other methods are not routed", async () => {
    const t = setup();
    const response = await t.fetch("/webEvent", { method: "GET", headers: { Origin: SITE } });
    expect(response.status).toBe(404);
  });
});

describe("POST /webEvent: origins are configurable for a dev deployment", () => {
  test("WEB_EVENT_ALLOWED_ORIGINS replaces the list", async () => {
    process.env.WEB_EVENT_ALLOWED_ORIGINS = "http://localhost:8788, http://127.0.0.1:8788";
    const t = setup();
    expect((await postWeb(t, event(), { origin: "http://localhost:8788" })).status).toBe(204);
    expect((await postWeb(t, event(), { origin: SITE })).status).toBe(403);
    expect(await rows(t)).toHaveLength(1);
  });

  test("an empty setting falls back to the site's origins", async () => {
    process.env.WEB_EVENT_ALLOWED_ORIGINS = " , ";
    const t = setup();
    expect((await postWeb(t, event())).status).toBe(204);
  });
});

describe("POST /webEvent: rate limit", () => {
  test("its own scope: per source IP and for the whole route, never the app's install key", async () => {
    const t = setup();
    expect((await postWeb(t, event(), { headers: { "x-forwarded-for": "203.0.113.9" } })).status).toBe(204);
    const keys = (await buckets(t)).map((row) => row.bucketKey.split(":").slice(0, 2).join(":"));
    expect(keys.sort()).toEqual(["web:all", "webip:203.0.113.9"]);
  });

  test("one source over its ceiling is answered 429 and inserts nothing further", async () => {
    const t = setup();
    for (let i = 0; i < MAX_WEB_EVENTS_PER_IP_PER_WINDOW; i += 1) {
      expect((await postWeb(t, event(), { headers: { "x-forwarded-for": "198.51.100.7" } })).status).toBe(204);
    }
    const over = await postWeb(t, event(), { headers: { "x-forwarded-for": "198.51.100.7" } });
    expect(over.status).toBe(429);
    expect(await rows(t)).toHaveLength(MAX_WEB_EVENTS_PER_IP_PER_WINDOW);
    expect((await postWeb(t, event(), { headers: { "x-forwarded-for": "198.51.100.8" } })).status).toBe(204);
  });

  test("the route-wide ceiling holds across many sources, and a rolled window starts fresh", async () => {
    const t = setup();
    const start = 1_800_000_000_000 - (1_800_000_000_000 % RATE_LIMIT_WINDOW_MS);
    for (let i = 0; i < MAX_WEB_EVENTS_PER_WINDOW; i += 1) {
      const result = await t.mutation(internal.rateLimit.checkAndBumpWeb, { sourceIp: `192.0.2.${i % 250}`, nowMs: start + 1 });
      expect(result.allowed).toBe(true);
    }
    const over = await t.mutation(internal.rateLimit.checkAndBumpWeb, { sourceIp: "192.0.2.250", nowMs: start + 2 });
    expect(over).toEqual({ allowed: false, limitedBy: "web" });
    const next = await t.mutation(internal.rateLimit.checkAndBumpWeb, { sourceIp: "192.0.2.250", nowMs: start + RATE_LIMIT_WINDOW_MS + 1 });
    expect(next).toEqual({ allowed: true, limitedBy: null });
  });

  test("a request over its source's ceiling does not count toward the route-wide budget", async () => {
    const t = setup();
    const start = 1_800_000_000_000 - (1_800_000_000_000 % RATE_LIMIT_WINDOW_MS);
    for (let i = 0; i < MAX_WEB_EVENTS_PER_WINDOW; i += 1) {
      const result = await t.mutation(internal.rateLimit.checkAndBumpWeb, { sourceIp: "198.51.100.66", nowMs: start + 1 });
      expect(result).toEqual(i < MAX_WEB_EVENTS_PER_IP_PER_WINDOW ? { allowed: true, limitedBy: null } : { allowed: false, limitedBy: "webip" });
    }
    const other = await t.mutation(internal.rateLimit.checkAndBumpWeb, { sourceIp: "198.51.100.67", nowMs: start + 2 });
    expect(other).toEqual({ allowed: true, limitedBy: null });
    const whole = (await buckets(t)).find((row) => row.bucketKey === `web:all:${start}`);
    expect(whole?.count).toBe(MAX_WEB_EVENTS_PER_IP_PER_WINDOW + 1);
  });

  test("a request with no usable source IP is limited only by the route-wide key", async () => {
    const t = setup();
    const result = await t.mutation(internal.rateLimit.checkAndBumpWeb, { sourceIp: null, nowMs: 1_800_000_000_000 });
    expect(result.allowed).toBe(true);
    expect((await buckets(t)).map((row) => row.bucketKey.split(":")[0])).toEqual(["web"]);
  });
});

describe("POST /webEvent: a failing store is the sink's fault, not the caller's", () => {
  test("a database failure answers 500 with no detail", async () => {
    const t = convexTest(schema, {
      ...modules,
      "./webEvents.ts": async () => {
        const real = await import("./webEvents");
        const { internalMutation } = await import("./_generated/server");
        return {
          ...real,
          logWebEvent: internalMutation({
            args: {} as never,
            handler: async () => {
              throw new Error("db unavailable at secret-connection-string");
            },
          }),
        };
      },
    });
    const response = await postWeb(t, event());
    expect(response.status).toBe(500);
    expect(await response.text()).not.toContain("secret-connection-string");
  });
});

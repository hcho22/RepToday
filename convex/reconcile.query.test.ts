import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";

const modules: Record<string, () => Promise<any>> = Object.fromEntries(
  Object.entries({
    ...import.meta.glob("./**/*.ts"),
    ...import.meta.glob("./**/*.js"),
  }).filter(([path]) => !path.endsWith(".d.ts") && !path.endsWith(".test.ts")),
);

describe("reconcile:eventsForInstalls", () => {
  test("selects each requested install once without returning unrelated rows", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await ctx.db.insert("events", {
        // Production rows from before durable delivery have no eventId. Schema compatibility and
        // the frozen analytic read must keep those rows queryable unchanged.
        name: "app_install",
        installId: "wanted",
        clientTs: 1,
        serverTs: 2,
        props: { marker: "first" },
      });
      await ctx.db.insert("events", {
        eventId: "event-a-2",
        name: "session_started",
        installId: "unrelated",
        clientTs: 3,
        serverTs: 4,
        props: {},
      });
      await ctx.db.insert("events", {
        eventId: "event-b-1",
        name: "onboarding_started",
        installId: "wanted",
        clientTs: 5,
        serverTs: 6,
        props: { marker: "second" },
      });
    });

    const rows = await t.query(internal.reconcile.eventsForInstalls, {
      installIds: ["wanted", "wanted", "absent"],
    });

    expect(rows).toEqual([
      {
        name: "app_install",
        installId: "wanted",
        clientTs: 1,
        serverTs: 2,
        props: { marker: "first" },
      },
      {
        name: "onboarding_started",
        installId: "wanted",
        clientTs: 5,
        serverTs: 6,
        props: { marker: "second" },
      },
    ]);
  });
});

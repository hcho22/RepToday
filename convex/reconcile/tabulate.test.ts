import { describe, expect, test } from "vitest";
import { EVENT_NAMES } from "../events";
import {
  tabulate,
  toFunnelCsv,
  toFunnelMarkdown,
  toAnomaliesCsv,
  isoFromMs,
  pacificWeekStartKey,
  type EventRow,
} from "../../tools/reconcile/tabulate.js";
import { FUNNEL_EVENT_NAMES } from "../../tools/reconcile/funnel-schema.js";

/**
 * Unit coverage for the US-T13 pure funnel tabulator (`tools/reconcile/tabulate.js`).
 *
 * The tabulator is deliberately network- and Convex-free, so it is exercised entirely against
 * fixture arrays here - the same way the iOS suite exercises `AppEntryTelemetry` without a live app.
 * This file lives under `convex/` on purpose: it is the one place the repo's existing gates reach a
 * `.test.ts` (`vitest`'s `convex/**` include) and typecheck the imported source (`tsc` follows the
 * import and `// @ts-check` in the tabulator surfaces its own type errors). The tabulator source
 * stays under `tools/` so it is never bundled into the deployed telemetry sink.
 */

const BASE = 1_785_715_200_000; // A fixed 2026 instant; the tabulator reads only the ms it is given.
const MIN = 60_000;

/** Build one event row; serverTs defaults to just after clientTs (no clock skew). */
function row(
  name: string,
  installId: string,
  clientTs: number,
  extra: { serverTs?: number; props?: Record<string, unknown> } = {},
): EventRow {
  return {
    name,
    installId,
    clientTs,
    serverTs: extra.serverTs ?? clientTs + 1000,
    props: extra.props ?? {},
  };
}

/** A clean, anomaly-free single-install journey through the funnel in chronological order. */
function cleanJourney(id: string): EventRow[] {
  let t = BASE;
  const next = () => (t += MIN);
  return [
    row("app_install", id, next(), { props: { install_week: "2026-08-02" } }),
    row("onboarding_started", id, next()),
    row("onboarding_completed", id, next(), { props: { elapsed_seconds: 42 } }),
    row("ready_screen_shown", id, next(), { props: { generation_ms: 37 } }),
    row("session_started", id, next(), { props: { requested_minutes: 10 } }),
    row("session_completed", id, next(), {
      props: { requested_minutes: 10, completed_minutes: 10, was_return: false, perceived_difficulty: 3 },
    }),
    row("week_active", id, next()),
    row("paywall_shown", id, next(), { props: { entry_point: "progress_upsell" } }),
    row("subscribe", id, next(), { props: { plan: "com.reptoday.premium.monthly" } }),
  ];
}

describe("funnel schema is the wire contract, not a guess", () => {
  test("FUNNEL_EVENT_NAMES matches convex EVENT_NAMES exactly and in order", () => {
    expect([...FUNNEL_EVENT_NAMES]).toEqual([...EVENT_NAMES]);
  });
});

describe("tabulate - clean full funnel", () => {
  test("one install, all events present, no anomalies", () => {
    const report = tabulate(cleanJourney("install-clean"));
    expect(report.summary.installCount).toBe(1);
    expect(report.summary.anomalyCount).toBe(0);
    const install = report.installs[0];
    expect(install.noEvents).toBe(false);
    expect(install.events.app_install.present).toBe(true);
    expect(install.events.app_install.count).toBe(1);
    expect(install.events.session_completed.props[0]).toMatchObject({ completed_minutes: 10 });
    expect(install.events.ready_screen_shown.props[0]).toMatchObject({ generation_ms: 37 });
    // session_abandoned never happened; it is present in the dense cell map but absent.
    expect(install.events.session_abandoned.present).toBe(false);
  });
});

describe("tabulate - missing emission", () => {
  test("onboarding_completed without onboarding_started flags MISSING_PREREQUISITE", () => {
    const rows = [row("onboarding_completed", "install-miss", BASE, { props: { elapsed_seconds: 9 } })];
    const report = tabulate(rows);
    const types = report.installs[0].anomalies.map((a) => a.type);
    expect(types).toContain("MISSING_PREREQUISITE");
    const flagged = report.installs[0].anomalies.find((a) => a.type === "MISSING_PREREQUISITE");
    expect(flagged?.event).toBe("onboarding_started");
  });
});

describe("tabulate - duplicate emission", () => {
  test("app_install twice for one install flags DUPLICATE", () => {
    const rows = [
      row("app_install", "install-dup", BASE, { props: { install_week: "2026-08-02" } }),
      row("app_install", "install-dup", BASE + MIN, { props: { install_week: "2026-08-02" } }),
    ];
    const report = tabulate(rows);
    const dup = report.installs[0].anomalies.find((a) => a.type === "DUPLICATE");
    expect(dup?.event).toBe("app_install");
    expect(report.installs[0].events.app_install.count).toBe(2);
  });

  test("recurring events (ready_screen_shown) are NOT flagged as duplicates", () => {
    const rows = [
      row("ready_screen_shown", "install-ready", BASE, { props: { generation_ms: 20 } }),
      row("ready_screen_shown", "install-ready", BASE + MIN, { props: { generation_ms: 25 } }),
    ];
    const report = tabulate(rows);
    expect(report.installs[0].anomalies.filter((a) => a.type === "DUPLICATE")).toHaveLength(0);
    expect(report.installs[0].events.ready_screen_shown.count).toBe(2);
  });
});

describe("tabulate - terminal balance (completed xor abandoned)", () => {
  test("started + completed only: no terminal anomaly", () => {
    const rows = [
      row("session_started", "s1", BASE, { props: { requested_minutes: 10 } }),
      row("session_completed", "s1", BASE + MIN, { props: { completed_minutes: 10 } }),
    ];
    const report = tabulate(rows);
    expect(report.installs[0].anomalies.map((a) => a.type)).not.toContain("EXCESS_TERMINAL");
  });

  test("two sessions, one completed one abandoned: legitimate, no anomaly", () => {
    const rows = [
      row("session_started", "s2", BASE, { props: { requested_minutes: 10 } }),
      row("session_completed", "s2", BASE + MIN, { props: { completed_minutes: 10 } }),
      row("session_started", "s2", BASE + 2 * MIN, { props: { requested_minutes: 15 } }),
      row("session_abandoned", "s2", BASE + 3 * MIN, {
        props: { completed_minutes: 4, abandon_point: "mainWork" },
      }),
    ];
    const report = tabulate(rows);
    const terminalTypes = report.installs[0].anomalies
      .map((a) => a.type)
      .filter((t) => t === "EXCESS_TERMINAL" || t === "UNTERMINATED_SESSION");
    expect(terminalTypes).toHaveLength(0);
  });

  test("both terminal events fired for one physical session flags EXCESS_TERMINAL", () => {
    const rows = [
      row("session_started", "s3", BASE, { props: { requested_minutes: 10 } }),
      row("session_completed", "s3", BASE + MIN, { props: { completed_minutes: 10 } }),
      row("session_abandoned", "s3", BASE + 2 * MIN, {
        props: { completed_minutes: 6, abandon_point: "cooldown" },
      }),
    ];
    const report = tabulate(rows);
    const excess = report.installs[0].anomalies.find((a) => a.type === "EXCESS_TERMINAL");
    expect(excess).toBeDefined();
    expect(excess?.detail).toContain("both completed and abandoned");
  });

  test("started with no terminal flags UNTERMINATED_SESSION (documented gap, not a defect)", () => {
    const rows = [row("session_started", "s4", BASE, { props: { requested_minutes: 10 } })];
    const report = tabulate(rows);
    expect(report.installs[0].anomalies.map((a) => a.type)).toContain("UNTERMINATED_SESSION");
  });
});

describe("tabulate - opt-out install with no events", () => {
  test("an expected install with zero rows appears all-absent with no defect flags", () => {
    const report = tabulate([], ["install-optout"]);
    expect(report.summary.installCount).toBe(1);
    const install = report.installs[0];
    expect(install.noEvents).toBe(true);
    expect(install.anomalies).toHaveLength(0);
    for (const name of report.eventOrder) {
      expect(install.events[name].present).toBe(false);
      expect(install.events[name].count).toBe(0);
    }
  });

  test("expected installs union with installs seen only in rows", () => {
    const report = tabulate(cleanJourney("install-seen"), ["install-optout"]);
    expect(report.summary.installCount).toBe(2);
    expect(report.installs.map((i) => i.installId).sort()).toEqual(["install-optout", "install-seen"]);
  });
});

describe("tabulate - out-of-order timestamps", () => {
  test("a later milestone stamped before an earlier one flags OUT_OF_ORDER", () => {
    const rows = [
      row("onboarding_started", "o1", BASE + 5 * MIN),
      row("onboarding_completed", "o1", BASE + MIN, { props: { elapsed_seconds: 3 } }),
    ];
    const report = tabulate(rows);
    const ooo = report.installs[0].anomalies.find((a) => a.type === "OUT_OF_ORDER");
    expect(ooo?.event).toBe("onboarding_completed");
  });

  test("an event before app_install flags OUT_OF_ORDER", () => {
    const rows = [
      row("app_install", "o2", BASE + 5 * MIN, { props: { install_week: "2026-08-02" } }),
      row("session_started", "o2", BASE, { props: { requested_minutes: 5 } }),
    ];
    const report = tabulate(rows);
    const ooo = report.installs[0].anomalies.filter((a) => a.type === "OUT_OF_ORDER");
    expect(ooo.some((a) => a.event === "session_started")).toBe(true);
  });
});

describe("tabulate - week_active is once per week, not per install", () => {
  test("two week_active in the same Pacific week flags DUPLICATE_WEEK_ACTIVE", () => {
    // Both within the same Sunday-start Pacific week.
    const wkStart = Date.UTC(2026, 7, 3, 18, 0, 0); // Mon 2026-08-03, well inside the week
    const rows = [
      row("week_active", "w1", wkStart),
      row("week_active", "w1", wkStart + 2 * 24 * 60 * MIN),
    ];
    const report = tabulate(rows);
    expect(report.installs[0].anomalies.map((a) => a.type)).toContain("DUPLICATE_WEEK_ACTIVE");
  });

  test("two week_active in different weeks are not flagged", () => {
    const rows = [
      row("week_active", "w2", Date.UTC(2026, 7, 4, 18)),
      row("week_active", "w2", Date.UTC(2026, 7, 12, 18)),
    ];
    const report = tabulate(rows);
    expect(report.installs[0].anomalies.map((a) => a.type)).not.toContain("DUPLICATE_WEEK_ACTIVE");
  });
});

describe("tabulate - clock skew", () => {
  test("clientTs well ahead of serverTs flags CLOCK_SKEW", () => {
    const rows = [row("app_install", "c1", BASE + 30 * MIN, { serverTs: BASE, props: { install_week: "x" } })];
    const report = tabulate(rows);
    expect(report.installs[0].anomalies.map((a) => a.type)).toContain("CLOCK_SKEW");
  });
});

describe("unknown event names", () => {
  test("a name outside the 13 is captured, not tabulated into a cell", () => {
    const rows: EventRow[] = [
      { name: "totally_made_up", installId: "u1", clientTs: BASE, serverTs: BASE + 1000, props: {} },
    ];
    const report = tabulate(rows);
    expect(report.installs[0].unknownEvents).toEqual(["totally_made_up"]);
  });
});

describe("formatters", () => {
  const report = tabulate([...cleanJourney("fmt-a"), ...[
    row("app_install", "fmt-b", BASE),
    row("app_install", "fmt-b", BASE + MIN),
  ]]);

  test("CSV has a header and a row per (install, event)", () => {
    const csv = toFunnelCsv(report);
    const lines = csv.trim().split("\n");
    expect(lines[0]).toBe("install_id,event,present,count,first_client_ts,last_client_ts,all_client_ts,props");
    // 2 installs * 13 events + header
    expect(lines).toHaveLength(2 * 13 + 1);
    expect(csv).toContain("fmt-a,app_install,yes,1");
  });

  test("anomalies CSV lists the duplicate", () => {
    const csv = toAnomaliesCsv(report);
    expect(csv).toContain("fmt-b,DUPLICATE,app_install");
  });

  test("markdown names the harness and renders a table per install", () => {
    const md = toFunnelMarkdown(report, "2026-08-07T00:00:00.000Z");
    expect(md).toContain("# US-T13 reconciliation funnel");
    expect(md).toContain("reconciliation **harness**");
    expect(md).toContain("## fmt-a");
    expect(md).toContain("| `app_install` |");
  });
});

describe("helpers", () => {
  test("isoFromMs handles finite and non-finite input", () => {
    expect(isoFromMs(0)).toBe("1970-01-01T00:00:00.000Z");
    expect(isoFromMs(Infinity)).toBe("");
    expect(isoFromMs(NaN)).toBe("");
  });

  test("pacificWeekStartKey returns the Sunday of the local week", () => {
    // Mon 2026-08-03 in Pacific -> week starts Sun 2026-08-02.
    expect(pacificWeekStartKey(Date.UTC(2026, 7, 3, 18))).toBe("2026-08-02");
  });
});

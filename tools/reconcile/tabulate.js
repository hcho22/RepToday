// @ts-check

import {
  FUNNEL_EVENTS,
  FUNNEL_EVENT_NAMES,
  FUNNEL_PREREQUISITES,
  FUNNEL_ORDER_CONSTRAINTS,
} from "./funnel-schema.js";

/**
 * US-T13 pure funnel tabulator.
 *
 * Given the raw `events` rows the pipeline recorded for a set of cohort installs, it produces the
 * per-install funnel table the reconciliation places next to the non-founder coder's observation
 * log for line-by-line diffing. It is a **pure function** - no network, no Convex, no wall clock
 * (every `Date` it constructs is fed an explicit millisecond argument) - mirroring how
 * `AppEntryTelemetry` is a pure, injected decision unit the iOS suite exercises without a live app.
 * The read path that fetches the rows lives entirely in `run.mjs` / `convex/reconcile.ts`; this file
 * never reaches the network, so it is unit-tested against fixture arrays alone.
 *
 * @typedef {Object} EventRow
 * @property {string} name
 * @property {string} installId
 * @property {number} clientTs   Client-stamped ms since epoch.
 * @property {number} serverTs   Sink-stamped ms since epoch.
 * @property {Record<string, unknown> | null | undefined} [props]
 *
 * @typedef {Object} EventCell
 * @property {boolean} present
 * @property {number} count
 * @property {number[]} clientTs        Every occurrence's client ts, ascending.
 * @property {number[]} serverTs        Every occurrence's server ts, order-matched to clientTs.
 * @property {Record<string, unknown>[]} props  Salient props per occurrence, order-matched.
 *
 * @typedef {Object} Anomaly
 * @property {string} type
 * @property {string | null} event
 * @property {string} detail
 *
 * @typedef {Object} InstallFunnel
 * @property {string} installId
 * @property {Record<string, EventCell>} events   Keyed by every one of the 13 funnel names.
 * @property {string[]} unknownEvents             Any names outside the 13 (sink should reject these).
 * @property {Anomaly[]} anomalies
 * @property {boolean} noEvents                   True when the install recorded nothing at all.
 *
 * @typedef {Object} FunnelReport
 * @property {string[]} eventOrder
 * @property {InstallFunnel[]} installs
 * @property {{installCount: number, rowCount: number, anomalyCount: number}} summary
 */

/**
 * ISO-8601 UTC string for a millisecond timestamp, or "" for a non-finite value.
 * @param {number} ms
 */
export function isoFromMs(ms) {
  return typeof ms === "number" && Number.isFinite(ms) ? new Date(ms).toISOString() : "";
}

/**
 * Sunday-start week key (`yyyy-MM-dd`) for a timestamp, bucketed in America/Los_Angeles - the same
 * `AppState.cohortCalendar` split `week_active`'s cadence and `install_week` are pinned to, so the
 * duplicate-week check here buckets the way the server does. Pure: only the passed `ms` is read.
 * @param {number} ms
 */
export function pacificWeekStartKey(ms) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "short",
  }).formatToParts(new Date(ms));
  const get = (/** @type {string} */ t) => parts.find((p) => p.type === t)?.value ?? "";
  const year = Number(get("year"));
  const month = Number(get("month"));
  const day = Number(get("day"));
  const weekdayIndex = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[get("weekday")] ?? 0;
  // Plain-date arithmetic in UTC to reach the Sunday of that local week; only the y-m-d key matters.
  const sunday = new Date(Date.UTC(year, month - 1, day) - weekdayIndex * 86_400_000);
  return sunday.toISOString().slice(0, 10);
}

const FUNNEL_META = new Map(FUNNEL_EVENTS.map((e) => [e.name, e]));

/**
 * Pull just the salient props for an event name from a raw props bag.
 * @param {string} name
 * @param {unknown} props
 */
function salientProps(name, props) {
  const meta = FUNNEL_META.get(name);
  /** @type {Record<string, unknown>} */
  const out = {};
  if (!meta || props == null || typeof props !== "object") return out;
  for (const key of meta.salientProps) {
    if (key in props) out[key] = /** @type {Record<string, unknown>} */ (props)[key];
  }
  return out;
}

/** Build the empty 13-name cell map so every install row is dense (absent events show explicitly). */
function emptyCells() {
  /** @type {Record<string, EventCell>} */
  const cells = {};
  for (const name of FUNNEL_EVENT_NAMES) {
    cells[name] = { present: false, count: 0, clientTs: [], serverTs: [], props: [] };
  }
  return cells;
}

/**
 * Detect the anomalies a reconciliation cares about for one install's already-tabulated cells.
 * @param {Record<string, EventCell>} cells
 * @returns {Anomaly[]}
 */
function detectAnomalies(cells) {
  /** @type {Anomaly[]} */
  const anomalies = [];
  const count = (/** @type {string} */ name) => cells[name].count;
  const firstTs = (/** @type {string} */ name) =>
    cells[name].clientTs.length ? cells[name].clientTs[0] : null;

  // 1. Duplicate emissions of a one-shot/once-guarded event.
  for (const e of FUNNEL_EVENTS) {
    if (e.atMostOncePerInstall && count(e.name) > 1) {
      anomalies.push({
        type: "DUPLICATE",
        event: e.name,
        detail: `${count(e.name)} emissions of a once-per-install event (expected at most 1)`,
      });
    }
  }

  // 1b. week_active is once-per-week, not per-install: flag two in the same Pacific cohort week.
  if (count("week_active") > 1) {
    /** @type {Map<string, number>} */
    const perWeek = new Map();
    for (const ts of cells["week_active"].clientTs) {
      const wk = pacificWeekStartKey(ts);
      perWeek.set(wk, (perWeek.get(wk) ?? 0) + 1);
    }
    for (const [wk, n] of perWeek) {
      if (n > 1) {
        anomalies.push({
          type: "DUPLICATE_WEEK_ACTIVE",
          event: "week_active",
          detail: `${n} week_active in the Pacific week starting ${wk} (expected at most 1/week)`,
        });
      }
    }
  }

  // 2. Missing funnel prerequisite: a downstream event present with its required upstream absent.
  for (const [downstream, upstream] of FUNNEL_PREREQUISITES) {
    if (count(downstream) > 0 && count(upstream) === 0) {
      anomalies.push({
        type: "MISSING_PREREQUISITE",
        event: upstream,
        detail: `${downstream} recorded but its prerequisite ${upstream} is absent`,
      });
    }
  }

  // 3. Terminal balance: the pipeline guarantees exactly one terminal (completed xor abandoned) per
  // physical session, and every physical session opens with a session_started. So
  // completed + abandoned must never exceed started; excess means a session emitted BOTH - the
  // real defect US-T13 is built to catch. A shortfall is the documented force-quit-from-celebration
  // gap (a completed session dismissed before "Done"), surfaced as an informational note, not a
  // defect.
  const started = count("session_started");
  const terminals = count("session_completed") + count("session_abandoned");
  if (terminals > started) {
    anomalies.push({
      type: "EXCESS_TERMINAL",
      event: null,
      detail:
        `${count("session_completed")} completed + ${count("session_abandoned")} abandoned ` +
        `= ${terminals} terminal events for ${started} started session(s): a session emitted ` +
        `both completed and abandoned (the exactly-one-terminal guarantee is violated)`,
    });
  } else if (started > terminals && started > 0) {
    anomalies.push({
      type: "UNTERMINATED_SESSION",
      event: null,
      detail:
        `${started} started vs ${terminals} terminal: ${started - terminals} session(s) with no ` +
        `terminal event (in-progress, or the documented force-quit-from-celebration gap)`,
    });
  }

  // 4. Out-of-order milestones: a later milestone stamped before an earlier one (clock/window bug).
  for (const [earlier, later] of FUNNEL_ORDER_CONSTRAINTS) {
    const a = firstTs(earlier);
    const b = firstTs(later);
    if (a != null && b != null && b < a) {
      anomalies.push({
        type: "OUT_OF_ORDER",
        event: later,
        detail: `${later} (${isoFromMs(b)}) is before ${earlier} (${isoFromMs(a)})`,
      });
    }
  }

  // 4b. app_install must precede everything else (first-ever open); flag any earlier event.
  const installTs = firstTs("app_install");
  if (installTs != null) {
    for (const name of FUNNEL_EVENT_NAMES) {
      if (name === "app_install") continue;
      const t = firstTs(name);
      if (t != null && t < installTs) {
        anomalies.push({
          type: "OUT_OF_ORDER",
          event: name,
          detail: `${name} (${isoFromMs(t)}) is before app_install (${isoFromMs(installTs)})`,
        });
      }
    }
  }

  // 5. Client clock ahead of the sink: clientTs later than the server's receive stamp by more than a
  // tolerance means the device clock was skewed - a window bug that would misbucket cohorts.
  const SKEW_TOLERANCE_MS = 5 * 60_000;
  for (const name of FUNNEL_EVENT_NAMES) {
    const cell = cells[name];
    for (let i = 0; i < cell.clientTs.length; i++) {
      const c = cell.clientTs[i];
      const s = cell.serverTs[i];
      if (Number.isFinite(c) && Number.isFinite(s) && c - s > SKEW_TOLERANCE_MS) {
        anomalies.push({
          type: "CLOCK_SKEW",
          event: name,
          detail: `client ts ${isoFromMs(c)} is ${Math.round((c - s) / 1000)}s ahead of server ts ${isoFromMs(s)}`,
        });
      }
    }
  }

  return anomalies;
}

/**
 * Tabulate raw event rows into the per-install funnel report.
 *
 * @param {EventRow[]} rows            The pipeline's recorded rows for the cohort.
 * @param {string[]} [installIds]      The full expected install-id set. Installs here with no rows
 *                                     appear as all-absent (an opt-out or never-ran install), which
 *                                     the sink cannot distinguish and the report does not guess at.
 * @returns {FunnelReport}
 */
export function tabulate(rows, installIds = []) {
  /** @type {Map<string, {cells: Record<string, EventCell>, unknown: Set<string>, rowCount: number}>} */
  const byInstall = new Map();
  const ensure = (/** @type {string} */ id) => {
    let entry = byInstall.get(id);
    if (!entry) {
      entry = { cells: emptyCells(), unknown: new Set(), rowCount: 0 };
      byInstall.set(id, entry);
    }
    return entry;
  };

  for (const id of installIds) ensure(id);

  // Group rows and sort each event's occurrences by clientTs so first/last are stable and the
  // order checks read a real chronology rather than DB insertion order.
  for (const row of rows) {
    const entry = ensure(row.installId);
    entry.rowCount += 1;
    if (!FUNNEL_META.has(row.name)) {
      entry.unknown.add(row.name);
      continue;
    }
    const cell = entry.cells[row.name];
    cell.present = true;
    cell.count += 1;
    // Insert keeping clientTs / serverTs / props index-aligned and clientTs ascending.
    const insertAt = lowerBound(cell.clientTs, row.clientTs);
    cell.clientTs.splice(insertAt, 0, row.clientTs);
    cell.serverTs.splice(insertAt, 0, row.serverTs);
    cell.props.splice(insertAt, 0, salientProps(row.name, row.props));
  }

  /** @type {InstallFunnel[]} */
  const installs = [];
  let anomalyCount = 0;
  let rowCount = 0;
  for (const [installId, entry] of byInstall) {
    const anomalies = detectAnomalies(entry.cells);
    anomalyCount += anomalies.length;
    rowCount += entry.rowCount;
    installs.push({
      installId,
      events: entry.cells,
      unknownEvents: [...entry.unknown].sort(),
      anomalies,
      noEvents: entry.rowCount === 0,
    });
  }
  installs.sort((a, b) => a.installId.localeCompare(b.installId));

  return {
    eventOrder: [...FUNNEL_EVENT_NAMES],
    installs,
    summary: { installCount: installs.length, rowCount, anomalyCount },
  };
}

/**
 * First index in a sorted ascending array whose value is >= target (stable insertion point).
 * @param {number[]} sorted
 * @param {number} target
 */
function lowerBound(sorted, target) {
  let lo = 0;
  let hi = sorted.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (sorted[mid] < target) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

/**
 * Compact one-line rendering of a salient-props object, e.g. `generation_ms=42`.
 * @param {Record<string, unknown>[]} propsList
 */
function propsSummary(propsList) {
  if (!propsList.length) return "";
  return propsList
    .map((/** @type {Record<string, unknown>} */ p) => {
      const keys = Object.keys(p);
      if (!keys.length) return "{}";
      return keys.map((k) => `${k}=${formatValue(p[k])}`).join(" ");
    })
    .join(" · ");
}

/** @param {unknown} v */
function formatValue(v) {
  if (v == null) return String(v);
  if (typeof v === "string") return v;
  return JSON.stringify(v);
}

/**
 * Escape a CSV field.
 * @param {unknown} value
 */
function csvField(value) {
  const s = String(value ?? "");
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/**
 * Long-format CSV: one row per (install, event), including absent events so a diff against the
 * coder's log has a line for every expected step. Salient props and every occurrence's timestamps
 * are included so a double emission is visible rather than collapsed.
 * @param {FunnelReport} report
 */
export function toFunnelCsv(report) {
  const header = [
    "install_id",
    "event",
    "present",
    "count",
    "first_client_ts",
    "last_client_ts",
    "all_client_ts",
    "props",
  ];
  const lines = [header.join(",")];
  for (const install of report.installs) {
    for (const name of report.eventOrder) {
      const cell = install.events[name];
      const first = cell.clientTs.length ? isoFromMs(cell.clientTs[0]) : "";
      const last = cell.clientTs.length ? isoFromMs(cell.clientTs[cell.clientTs.length - 1]) : "";
      const all = cell.clientTs.map(isoFromMs).join(" ");
      lines.push(
        [
          install.installId,
          name,
          cell.present ? "yes" : "no",
          cell.count,
          first,
          last,
          all,
          propsSummary(cell.props),
        ]
          .map(csvField)
          .join(","),
      );
    }
  }
  return lines.join("\n") + "\n";
}

/**
 * Anomalies-only CSV for quick scanning: install_id, type, event, detail.
 * @param {FunnelReport} report
 */
export function toAnomaliesCsv(report) {
  const lines = ["install_id,type,event,detail"];
  for (const install of report.installs) {
    for (const a of install.anomalies) {
      lines.push([install.installId, a.type, a.event ?? "", a.detail].map(csvField).join(","));
    }
  }
  return lines.join("\n") + "\n";
}

/**
 * Markdown report: a per-install funnel table plus its anomalies, designed to sit next to the
 * coder's observation log. `generatedAtIso` is passed in (never read from the wall clock here) so
 * the tabulator stays pure and its output is deterministic for a given input.
 * @param {FunnelReport} report
 * @param {string} [generatedAtIso]
 */
export function toFunnelMarkdown(report, generatedAtIso = "") {
  const out = [];
  out.push("# US-T13 reconciliation funnel");
  out.push("");
  out.push(
    "Per-install funnel tabulated from the pipeline's recorded `events`. Place this next to the " +
      "non-founder coder's observation log and diff event by event. Anomaly flags mark where the " +
      "pipeline's record is internally suspect; the reconciliation still compares every line " +
      "against what the room actually saw.",
  );
  out.push("");
  out.push(
    `Installs: ${report.summary.installCount} · rows: ${report.summary.rowCount} · ` +
      `anomalies: ${report.summary.anomalyCount}` +
      (generatedAtIso ? ` · generated: ${generatedAtIso}` : ""),
  );
  out.push("");
  out.push(
    "> This is the US-T13 reconciliation **harness** output. It does not by itself complete " +
      "US-T13: the ground-truth report against real observed sessions is still pending the " +
      "moderated cohort, the named non-founder coder, and a frozen rubric.",
  );
  out.push("");

  for (const install of report.installs) {
    out.push(`## ${install.installId}`);
    out.push("");
    if (install.noEvents) {
      out.push(
        "_No events recorded._ Indistinguishable at the sink between an opted-out install, one " +
          "that never ran, and one whose sends were all dropped - the reconciliation resolves " +
          "which from the coder's log, not from here.",
      );
      out.push("");
    }
    out.push("| Event | Present | Count | First (client) | Last (client) | Salient props |");
    out.push("|---|---|---|---|---|---|");
    for (const name of report.eventOrder) {
      const cell = install.events[name];
      const first = cell.clientTs.length ? isoFromMs(cell.clientTs[0]) : "-";
      const last =
        cell.clientTs.length > 1 ? isoFromMs(cell.clientTs[cell.clientTs.length - 1]) : "-";
      const props = (propsSummary(cell.props) || "-").replace(/\|/g, "\\|");
      out.push(
        `| \`${name}\` | ${cell.present ? "yes" : "no"} | ${cell.count} | ${first} | ${last} | ${props} |`,
      );
    }
    out.push("");
    if (install.unknownEvents.length) {
      out.push(`**Unexpected event names** (sink should reject): ${install.unknownEvents.join(", ")}`);
      out.push("");
    }
    if (install.anomalies.length) {
      out.push("**Anomalies:**");
      out.push("");
      for (const a of install.anomalies) {
        out.push(`- \`${a.type}\`${a.event ? ` (\`${a.event}\`)` : ""}: ${a.detail}`);
      }
      out.push("");
    } else if (!install.noEvents) {
      out.push("_No anomalies._");
      out.push("");
    }
  }
  return out.join("\n");
}

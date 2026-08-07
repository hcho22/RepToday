#!/usr/bin/env node
// @ts-check

/**
 * US-T13 reconciliation harness - runner.
 *
 * Given a set of cohort install identifiers and a Convex deployment, this exports the events the
 * pipeline recorded for those installs and writes the per-install funnel table (`funnel.md`,
 * `funnel.csv`, `anomalies.csv`) that sits next to the non-founder coder's observation log for
 * line-by-line diffing. See `tools/reconcile/README.md` for the full workflow and the standing
 * caveat that this is the harness, not the completed US-T13 report.
 *
 * Two cleanly separated halves meet here:
 *   1. Read path - `convex/reconcile.ts`'s `eventsForInstalls` internalQuery, reached through
 *      `npx convex run` with a deploy/admin key (no public function, no HTTP route added). Or skip
 *      it entirely with `--rows <file>` and feed rows you exported yourself.
 *   2. Pure tabulator - `tabulate.js`, imported below. No network, no deployment. Unit-tested.
 *
 * Usage:
 *   node tools/reconcile/run.mjs --installs id1,id2,id3           # read live from your dev deployment
 *   node tools/reconcile/run.mjs --installs-file ids.txt --prod   # ids one-per-line; read from prod
 *   node tools/reconcile/run.mjs --installs-file ids.txt --deployment happy-otter-123
 *   node tools/reconcile/run.mjs --installs-file ids.txt --rows exported.json   # no live read
 *
 * Options:
 *   --installs <csv>        Comma-separated install ids.
 *   --installs-file <path>  File of install ids, one per line (blank lines and # comments ignored).
 *   --rows <path>           Pre-exported JSON array of event rows; skips the live Convex read.
 *   --deployment <name>     Passed through to `npx convex run --deployment`.
 *   --prod                  Passed through to `npx convex run --prod`.
 *   --out <dir>             Output directory (default artifacts/reports/US-T13).
 *   -h, --help              This help.
 *
 * Deployment is never hardcoded: with no --rows, the read is delegated to the Convex CLI, which
 * resolves the target from --deployment / --prod / the ambient CONVEX_DEPLOYMENT (convex/.env.local)
 * or a CONVEX_DEPLOY_KEY in the environment - the same mechanism the sink's own tooling uses.
 */

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";

import { tabulate, toFunnelCsv, toFunnelMarkdown, toAnomaliesCsv } from "./tabulate.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, "..", "..");

/** @param {string[]} argv */
function parseArgs(argv) {
  /** @type {{installs?: string, installsFile?: string, rows?: string, deployment?: string, prod: boolean, out: string, help: boolean}} */
  const args = { prod: false, out: join(REPO_ROOT, "artifacts", "reports", "US-T13"), help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--installs": args.installs = argv[++i]; break;
      case "--installs-file": args.installsFile = argv[++i]; break;
      case "--rows": args.rows = argv[++i]; break;
      case "--deployment": args.deployment = argv[++i]; break;
      case "--prod": args.prod = true; break;
      case "--out": args.out = resolve(argv[++i]); break;
      case "-h":
      case "--help": args.help = true; break;
      default:
        console.error(`Unknown argument: ${a}`);
        args.help = true;
    }
  }
  return args;
}

/** @param {ReturnType<typeof parseArgs>} args @returns {string[]} */
function resolveInstallIds(args) {
  /** @type {string[]} */
  const ids = [];
  if (args.installs) ids.push(...args.installs.split(",").map((s) => s.trim()).filter(Boolean));
  if (args.installsFile) {
    const text = readFileSync(resolve(args.installsFile), "utf8");
    for (const line of text.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith("#")) ids.push(trimmed);
    }
  }
  // De-dupe, preserving order.
  return [...new Set(ids)];
}

/**
 * Read the recorded rows for the given installs from Convex via the internalQuery, unless a
 * pre-exported --rows file was supplied.
 * @param {ReturnType<typeof parseArgs>} args
 * @param {string[]} installIds
 * @returns {import("./tabulate.js").EventRow[]}
 */
function readRows(args, installIds) {
  if (args.rows) {
    const parsed = JSON.parse(readFileSync(resolve(args.rows), "utf8"));
    if (!Array.isArray(parsed)) throw new Error(`--rows file is not a JSON array: ${args.rows}`);
    return parsed;
  }

  const runArgs = ["convex", "run", "reconcile:eventsForInstalls", JSON.stringify({ installIds })];
  if (args.deployment) runArgs.push("--deployment", args.deployment);
  if (args.prod) runArgs.push("--prod");

  console.error(`Reading events via: npx ${runArgs.join(" ")}`);
  const result = spawnSync("npx", runArgs, { cwd: REPO_ROOT, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `\`npx convex run\` exited ${result.status}.\n` +
        `stderr:\n${result.stderr}\nstdout:\n${result.stdout}`,
    );
  }
  return parseConvexRunOutput(result.stdout);
}

/**
 * `npx convex run` prints its function's return value to stdout as JSON; progress goes to stderr.
 * Be tolerant of a leading log line by extracting the outermost JSON array if a bare parse fails.
 * @param {string} stdout
 * @returns {import("./tabulate.js").EventRow[]}
 */
function parseConvexRunOutput(stdout) {
  const trimmed = stdout.trim();
  try {
    const direct = JSON.parse(trimmed);
    if (Array.isArray(direct)) return direct;
  } catch {
    /* fall through to bracket extraction */
  }
  const start = trimmed.indexOf("[");
  const end = trimmed.lastIndexOf("]");
  if (start !== -1 && end > start) {
    const slice = trimmed.slice(start, end + 1);
    const parsed = JSON.parse(slice);
    if (Array.isArray(parsed)) return parsed;
  }
  throw new Error(`Could not parse a JSON array of rows from convex run output:\n${stdout}`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(
      "US-T13 reconciliation harness runner. See the header of this file or " +
        "tools/reconcile/README.md for usage.",
    );
    process.exit(args.help && process.argv.length <= 2 ? 1 : 0);
  }

  const installIds = resolveInstallIds(args);
  if (installIds.length === 0) {
    console.error("No install ids given. Pass --installs <csv> or --installs-file <path>.");
    process.exit(1);
  }

  const rows = readRows(args, installIds);
  const report = tabulate(rows, installIds);
  const generatedAtIso = new Date().toISOString();

  mkdirSync(args.out, { recursive: true });
  writeFileSync(join(args.out, "funnel.md"), toFunnelMarkdown(report, generatedAtIso));
  writeFileSync(join(args.out, "funnel.csv"), toFunnelCsv(report));
  writeFileSync(join(args.out, "anomalies.csv"), toAnomaliesCsv(report));
  writeFileSync(join(args.out, "events.json"), JSON.stringify(rows, null, 2) + "\n");

  console.error(
    `\nWrote reconciliation funnel for ${report.summary.installCount} install(s), ` +
      `${report.summary.rowCount} row(s), ${report.summary.anomalyCount} anomaly flag(s) to:\n` +
      `  ${join(args.out, "funnel.md")}\n` +
      `  ${join(args.out, "funnel.csv")}\n` +
      `  ${join(args.out, "anomalies.csv")}\n` +
      `  ${join(args.out, "events.json")}`,
  );
  if (report.summary.anomalyCount > 0) {
    console.error(
      `\n${report.summary.anomalyCount} anomaly flag(s) - see anomalies.csv. These mark where the ` +
        `pipeline's own record is internally suspect; reconcile them against the coder's log.`,
    );
  }
}

main();

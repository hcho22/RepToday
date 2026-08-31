# US-T13 reconciliation harness

This is the **re-runnable harness** for US-T13 (ground-truth reconciliation of the telemetry pipeline against the moderated TestFlight cohort).
It is **not** the completed US-T13 report, and running it does **not** check off any US-T13 acceptance box.

## What is and is not done

US-T13's deliverable is a reconciliation *report* that diffs, line by line, what the pipeline recorded against what a non-founder coder actually observed in ~25 moderated TestFlight first runs.
That report cannot exist yet, because none of its inputs do:

- no moderated TestFlight cohort has run, so Convex holds production-validation rows but no real cohort events;
- the named non-founder coder is still `[FOUNDER TO FILL]` in the investment thesis;
- the coding rubric is not frozen.

The captain's decision was to pre-build the tooling now, so that the moment the recordings and the coder's log exist, the reconciliation is **run-and-diff** rather than build-from-scratch.
So this directory is the harness only.
**US-T13's PRD acceptance boxes stay unchecked until the moderated cohort, the named coder, and the frozen rubric exist and the report in `artifacts/reports/US-T13/` is written against real observed sessions.**

## The two pieces

1. **Read path** - `convex/reconcile.ts`'s `eventsForInstalls` `internalQuery`.
   It selects the `events` rows for a supplied set of install ids and returns the five wire columns (`name`, `installId`, `clientTs`, `serverTs`, `props`).
   It uses the evidence table's `by_installId` selection index, so the read scales with the requested installs rather than all production history.
   It is **internal-only**, exactly like `logEvent` is an `internalMutation`: no public Convex function and no HTTP route is added, and US-T14's hardening of the public `POST /logEvent` surface is untouched.
   It is reached with a deploy/admin key through `npx convex run`.

2. **Pure tabulator** - `tabulate.js` (+ `funnel-schema.js`).
   A pure function with no network or deployment dependency that turns event rows into the per-install funnel table.
   Unit-tested against fixture arrays in `convex/reconcile/tabulate.test.ts` (run by `npm test`), mirroring how `AppEntryTelemetry` is a pure decision unit the iOS suite exercises without a live app.
   The funnel's event set and order come from `funnel-schema.js`, whose names the test asserts are exactly `EVENT_NAMES` in `convex/events.ts` - itself pinned verbatim to the event-metric schema and the Swift `AnalyticsEventName`.
   So the funnel is driven by the authoritative schema, not a hand-kept guess: a drift in either list fails the suite.

The tabulator source lives under `tools/` (not `convex/`) so it is never bundled into the deployed telemetry sink; its test lives under `convex/reconcile/` so the repo's existing `npm test` / `npm run typecheck` gates reach it with no config change.

## Running it

Install ids come from `--installs` or `--installs-file`; the deployment is never hardcoded.

```bash
# Read live from your dev deployment (uses convex/.env.local's CONVEX_DEPLOYMENT):
node tools/reconcile/run.mjs --installs id1,id2,id3

# Read from a named deployment or prod (delegated to `npx convex run`):
node tools/reconcile/run.mjs --installs-file cohort-ids.txt --deployment happy-otter-123
node tools/reconcile/run.mjs --installs-file cohort-ids.txt --prod

# Offline: feed rows you exported yourself, skipping the live read entirely:
npx convex run reconcile:eventsForInstalls '{"installIds":["id1","id2"]}' --prod > rows.json
node tools/reconcile/run.mjs --installs-file cohort-ids.txt --rows rows.json
```

`--installs-file` is one install id per line; blank lines and `#` comments are ignored.
Deployment selection is delegated to the Convex CLI, which resolves the target from `--deployment` / `--prod` / the ambient `CONVEX_DEPLOYMENT` (in `convex/.env.local`) or a `CONVEX_DEPLOY_KEY` in the environment.

## Output

Written to `--out` (default `artifacts/reports/US-T13/`):

- `funnel.md` - a per-install funnel table (one row per event, absent events shown explicitly) plus each install's anomaly flags. This is the surface to place next to the coder's observation log.
- `funnel.csv` - the same in long format (`install_id, event, present, count, first/last/all client ts, props`), for machine diffing.
- `anomalies.csv` - `install_id, type, event, detail`, for quick scanning.
- `events.json` - the raw rows the read returned.

**No fabricated cohort data is committed.** Real sample rows exist only inside the unit-test fixtures. `artifacts/reports/US-T13/` holds a placeholder until a real cohort is reconciled.

## Anomaly flags

Each surfaces a place where the pipeline's own record is internally suspect; the reconciliation still diffs every line against what the room saw.

| Flag | Meaning |
|---|---|
| `DUPLICATE` | A once-per-install event (`app_install`, onboarding pair, returns, `trial_started`, `subscribe`) recorded more than once. |
| `DUPLICATE_WEEK_ACTIVE` | Two `week_active` in the same Sunday-start Pacific week (`AppState.cohortCalendar`); it is once-per-week, not per-install. |
| `MISSING_PREREQUISITE` | A downstream funnel event present with its required upstream absent (e.g. `onboarding_completed` without `onboarding_started`, `subscribe` without `paywall_shown`). |
| `EXCESS_TERMINAL` | `session_completed` + `session_abandoned` exceed `session_started`: a session emitted **both** terminals, violating the pipeline's exactly-one-terminal-per-physical-session guarantee. This is the core defect US-T13 exists to catch. |
| `UNTERMINATED_SESSION` | More `session_started` than terminals: session(s) with no terminal event - in-progress, or the documented force-quit-from-celebration gap. Informational, not a defect. |
| `OUT_OF_ORDER` | A later milestone's client timestamp precedes an earlier one's (or any event precedes `app_install`) - a clock/window bug. |
| `CLOCK_SKEW` | An event's client timestamp is more than 5 minutes ahead of the sink's server timestamp - a skewed device clock that would misbucket cohorts. |

An install with **no events** is shown all-absent with no defect flag: the sink cannot distinguish an opted-out install from one that never ran or whose sends were all dropped (see the honest-constraints note in the event schema), so the reconciliation resolves which from the coder's log, not from here.

## Known limitation to fold into the real reconciliation

The tabulator has no session id (the wire contract carries none), so the terminal-balance check reasons from `session_started`/`session_completed`/`session_abandoned` **counts** per install rather than per physical session.
It reliably catches an install whose terminals exceed its starts (the both-fired defect) and an install with unterminated starts, but it cannot attribute a specific completed/abandoned pair to a specific physical session when several sessions interleave.
The coder's per-session log is what closes that gap during the real reconciliation.
No pipeline defect was found while building this harness; if one is found during the real run, it becomes a follow-up story - the harness itself ships no app fix.

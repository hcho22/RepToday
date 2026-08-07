# US-T13 - reconciliation output (pending real cohort)

This directory is where the US-T13 reconciliation harness writes its per-install funnel table
(`funnel.md`, `funnel.csv`, `anomalies.csv`, `events.json`) and where the final ground-truth
reconciliation report will live.

**It is intentionally empty of data.** No cohort data is committed here, because none exists yet:

- no moderated TestFlight cohort has run, so Convex holds no real cohort events;
- the non-founder coder is still `[FOUNDER TO FILL]` in `gtm/07-thesis/investment-thesis.md`;
- the coding rubric is not frozen.

The re-runnable harness that will populate this directory is built and tested under
`tools/reconcile/` (see its README) with the internal read path in `convex/reconcile.ts`.
Running the harness against a real deployment writes the files above here.

**US-T13's PRD acceptance boxes remain unchecked** until the moderated cohort has run, the coder is
named, the rubric is frozen, and the reconciliation report - diffing the pipeline's record line by
line against the coder's observation log, with a named cause and a fix-or-accepted-reason for every
disagreement - is written against real observed sessions.

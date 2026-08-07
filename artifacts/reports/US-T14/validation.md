# US-T14 live validation - endpoint abuse guard

Live probe of the shared-secret check and per-caller rate limiting against the **development**
deployment `courteous-dogfish-560`, on 2026-08-07.
The in-process boundary suite (`convex/http.test.ts`, `npm test`) is the gate that re-runs; this
transcript is the one-time live confirmation, in the same spirit as the US-T03 / US-T04 transcripts.

## Setup

- The US-T14 functions deployed to the dev deployment (`npx convex dev --once`).
- The shared secret configured on the deployment: `npx convex env set ANALYTICS_SHARED_SECRET <secret>`.
  The `<secret>` matches the Debug `REPTODAY_ANALYTICS_SECRET` build setting in `ios/RepToday/project.yml`.
- Route: `POST https://courteous-dogfish-560.convex.site/logEvent`.
- Header: `X-RepToday-Analytics-Secret: <secret>`.
- Row counts read back with the internal `reconcile:eventsForInstalls` query
  (`npx convex run reconcile:eventsForInstalls '{"installIds":[...]}'`), which is why every probe used
  a unique, greppable `installId` (`ust14-probe-*`).

## Step 1 - valid event WITH the correct secret

```
POST /logEvent  (X-RepToday-Analytics-Secret: <correct>)  installId=ust14-probe-ok
-> HTTP 204
rows for ust14-probe-ok: 1
```

A secret-bearing request under the ceiling inserts exactly one row. ✓

## Step 2 - missing / wrong secret

```
POST /logEvent  (no secret header)     installId=ust14-probe-nosecret  -> HTTP 401
POST /logEvent  (secret: totally-wrong) installId=ust14-probe-nosecret -> HTTP 401
rows for ust14-probe-nosecret: 0
```

Both a missing and a wrong secret are rejected `401` with no insert. Not `5xx`: a secretless flood
never looks like a sink outage. ✓

## Step 3 - over the rate-limit ceiling from one install

First attempt (sequential curls, ~1 request/second) did **not** trip the limit: 65 requests spanned
more than the 60-second window, so the per-install counter reset between windows and all 65 landed.
That is the rate limiter behaving correctly - 65 requests spread across >1 minute is under
60/minute - not a miss. Re-run with enough requests **inside one window**:

```
90 secret-bearing POSTs, 8-way concurrency (xargs -P 8), same installId=ust14-probe-burst3, ~4s total
code distribution:
   60  204
   28  429
    2  500
rows for ust14-probe-burst3: 60
```

- Exactly **60** (= `MAX_EVENTS_PER_INSTALL_PER_WINDOW`) inserted; every request past the ceiling
  was rejected **`429` with no insert** - the row count is exactly 60, not 90. ✓
- The 2 `500`s are the throttle mutation exhausting Convex's optimistic-concurrency retries under
  8-way concurrent hammering of the *same* counter row (an abnormal load pattern for one install).
  They are **fail-closed**: a throttle-check that cannot be evaluated propagates out of the action
  before `logEvent` is reached, so those 2 also inserted nothing (again, row count is 60). A real
  client never contends with itself this hard; the case here is a deliberate synthetic flood.

## Cleanup

All probe rows were deleted from the `events` evidence table afterwards, exactly as US-T03/US-T04
deleted theirs: a scratch internal mutation (`convex/scratchCleanup.ts`, **never committed**) deleted
every `ust14-probe-*` row (183 rows: 1 + 65 + 57 + 60, across the sequential and concurrent
attempts) and cleared the ephemeral `rateLimits` table, was then removed, and the deployment
redeployed without it. A follow-up `reconcile:eventsForInstalls` read returned **0** probe rows, and
`npx convex run scratchCleanup:purgeProbeRows` now errors (the function is gone).

## What this proves, and its limits

The secret check and the rate limit both run before the insert on the live deployment, and a
rejected request writes no row - the same guarantee the in-process suite asserts. As stated
throughout the code and `convex/README.md`, the secret is extractable from the shipped binary and
the per-install key is client-rotatable, so both raise the *cost* of a flood rather than preventing
one; the live probe confirms the mechanism works, not that it defeats a determined attacker.

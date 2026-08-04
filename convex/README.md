# Rep Today telemetry sink (US-T03)

The whole analytics backend: **one append-only table, one mutation, one HTTP route.**

It exists so the anonymous funnel events defined in `gtm/06-channels/event-metric-schema.md` have
somewhere to land during the 90-day PMF test.
The client that fills it is `LiveAnalyticsService` (US-T04), which reaches this deployment with a
plain `URLSession` POST and **no Convex SDK** - the US-T01 spike returned a no-go on `convex-swift`
because it ships an arm64-only xcframework that would break every Simulator-hosted test suite in
this repo on an Intel host (`artifacts/reports/US-T01/spike-note.md`).
That is why the HTTP action below is load-bearing rather than convenience: it is the client's only
entry point.
It is now the *sink's* only entry point too, which this file previously claimed before it was true:
`logEvent` was a public mutation until review caught it, so the deployment's own
`.convex.cloud/api/mutation` endpoint was a second, undocumented way in that skipped every check the
action performs. It is an `internalMutation` now - see below.

## Non-goal: no analysis in the backend

**The sink is dumb by design.**
There is no funnel modelling, no aggregation, no dedup, no cohort math, and no index beyond
Convex's defaults.
Every kill-criterion metric (K1-K8) is derivable from raw rows by a query written later, so keeping
the backend dumb keeps the analysis revisable - a funnel baked into the write path would be a
threshold decision made before there is any data to make it against.

## Table: `events`

`convex/schema.ts`. One table, five fields, no indexes.

| Field       | Type         | Meaning |
|-------------|--------------|---------|
| `name`      | `v.string()` | One of the 13 pre-registered event names (below). |
| `installId` | `v.string()` | Random per-install identifier (US-T05). Never a user identity - no email, IDFA, or Sign in with Apple id ever reaches here. |
| `clientTs`  | `v.number()` | Client-side timestamp, ms since the Unix epoch. |
| `serverTs`  | `v.number()` | Server-received timestamp, ms since the Unix epoch, stamped by the mutation. |
| `props`     | `v.any()`    | The event's non-identifying property bag, stored exactly as it arrived. |

## Mutation: `events:logEvent` (internal)

`convex/events.ts`. Append-only: it validates, stamps `serverTs = Date.now()`, inserts exactly one
row, and returns the document id. Nothing else.

```
logEvent({ name, installId, clientTs, props }) -> Id<"events">
```

It is declared with `internalMutation`, so it is **not** callable from outside the deployment: the
HTTP action below reaches it as `internal.events.logEvent`, and nothing else calls it at all.
That matters because a public Convex function is exposed on `POST <deployment>.convex.cloud/api/mutation`,
and `.convex.cloud` shares its slug with the `.convex.site` origin a shipped client already carries -
so a public `logEvent` would be a second entry point reachable by anyone who read the URL out of the
binary, and one that bypasses every boundary check in `convex/http.ts`. It was public until review
caught it, and a direct call did write a row with an empty `installId` and a `clientTs` of `0`. The
empty `installId` is precisely what the action refuses - it is the cohort key K4 counts unique
installs by, and a blank one collapses every such row into one phantom install. The `clientTs` of
`0` is *not*: the action checks presence and kind only, so `0` is a finite JSON number and would
land through `POST /logEvent` too, as would any other finite absurdity. That is the pinned scope,
not an oversight - see "Validation - and only this validation" below. Making the mutation internal
is what makes "the HTTP action is the only entry point" a fact rather than a description of intent.

### The 13 event names are a wire contract

`name` is a `v.union` of exactly these string literals, which are the raw values of
`AnalyticsEventName` in `ios/RepToday/RepToday/Models/AnalyticsEvent.swift`:

```
app_install          onboarding_started   onboarding_completed  ready_screen_shown
session_started      session_completed    session_abandoned     day7_return
day30_return         week_active          paywall_shown         trial_started
subscribe
```

The two web-side events from the schema (`landing_page_view`, `waitlist_signup`) are handled
outside the app and are deliberately absent.
Changing a raw value on either side without the other breaks the contract; the case *names* on the
Swift side may be refactored freely, the strings may not.

### Validation - and only this validation

"Basic input validation only" is an acceptance criterion, so `logEvent` rejects exactly two things
and inspects nothing else:

1. **An unknown event name** - the `v.union` above.
2. **An oversized property bag** - more than **32 keys** or more than **4096 UTF-8 bytes**
   serialized. (A `props` that is not an object at all is rejected under the same rule: a bag that
   is not a bag has no size, so that is the precondition the size check is measured against rather
   than a shape check of its own.)

Rationale for those numbers: the largest bag any real event carries is `session_completed` with
four small scalar keys (~120 bytes serialized), so both caps sit roughly two orders of magnitude
above anything the app legitimately sends - they stop a malformed or hostile client from poisoning
the table without ever policing a legitimate payload's shape.
The byte count is UTF-8 (`TextEncoder`), not `String.length`, which counts UTF-16 code units and
would undercount a non-ASCII bag against a limit called "bytes".

There is no schema check on individual property keys or types. Property vocabularies are expected
to move during the PMF test, and a write-path check would turn every such move into a deploy.

The HTTP action adds one thing to that list and only one: the body's fields must be **present and
of the right kind** before they are handed to the mutation - `name` one of the 13, `installId` a
non-empty string, `clientTs` an actual JSON number (a numeric *string* like `"1e3"` is refused, not
coerced).
That is not a third rule so much as the same one applied where untrusted input enters: coercing a
missing or wrong-kind field with `String(...)` / `Number(...)` would write the literal string
`"undefined"`, `NaN`, or a silently reinterpreted `"0x1f"` into the two columns the whole funnel is
counted on (`installId` is the cohort key K4 counts unique installs by; `clientTs` is what K1 is
timed from), and such a row looks valid while being junk - worse than no row at all.
It constrains presence and kind only: no length cap, no format or UUID-shape check, nothing about
what a legitimate value contains.
Read that literally rather than as a promise of plausibility. A `clientTs` of `0`, or of `1e300`,
is a finite JSON number and lands - the check rules out the *missing* and *wrong-kind* cases
(`undefined`, `NaN`, `"1e3"`), not implausible ones. Range and sanity belong to a query written
later against the raw rows, where they can be revised without a deploy, which is the same reason
the sink is dumb everywhere else.

The action also hands the assembled arguments to the Convex SDK's own `convexToJson` before calling
the mutation. That is a **classification**, not a rejection: `ctx.runMutation` runs the same
serializer anyway, so a `props` field name it refuses - one starting with `$`, one carrying a
non-ASCII or control character, or one over 1024 characters - is already refused today; it simply
threw a plain `Error` and so was reported as *our* `500` rather than the caller's `400`. Borrowing
the SDK's function instead of restating its rule means this can never drift from what Convex
actually enforces, and it inspects field names only - the per-key and per-type checks of `props`
above stay absent.

`logEvent` raises its own rejections as `ConvexError` rather than `Error`, which is what lets the
action tell a rejection it asked for apart from a failure it did not - see the status codes below.
That marker is read the way the SDK reads it, by testing the thrown object for `Symbol.for("ConvexError")`
rather than with `instanceof`. The distinction is not pedantry: the `convex` package ships physically
distinct copies of the class under `dist/cjs` and `dist/esm`, and the copy the syscall layer
reconstructs a cross-isolate throw from is reached by a relative import rather than the
`convex/values` specifier `http.ts` uses. Should those ever resolve to two copies, an `instanceof`
test would fail and every property-bag rejection would silently become a `500` - precisely the false
outage the split exists to prevent. `Symbol.for` is registry-global and does not care.

**Known current gap:** `installId` is an unbounded `v.string()` while `props` is capped, so a
hostile client can still write a very large row through that one field. This was reviewed during
US-T03 and consciously accepted for this story: the sink is not yet reachable by any client, and
US-T04 - which is where the identifier actually starts being sent - carries the acceptance
criterion that bounds its length.
That gap also costs a little of the `4xx`/`5xx` precision described above, and this too is accepted
for now: `convexToJson` validates field *names*, not structural limits, so a multi-hundred-KB
`installId` passes the non-empty check, passes the serialization pre-pass, passes the `props` caps
(which measure `props` alone) and only then exceeds Convex's ~1MB document limit at the insert -
landing on the `500` branch as a false outage signal rather than the `400` it deserves.
Bounding `installId` in US-T04 closes that as well as the storage gap.

**The residual is wider than that one case, and is stated here in full rather than as its cheapest
example.** The pre-pass is a *field-name* classifier and nothing more: the SDK's `validateObjectField`
checks a name's length against 1024, a leading `$`, and non-ASCII or control characters, and
`convexToJson` recurses without a depth guard. It therefore says nothing about nesting depth, about
value shapes, or about any other rule Convex only applies at write time. A caller-fault payload that
violates one of those - `props` nested past Convex's 16-level value limit, say, which can be well
under 100 bytes and so is far cheaper to send than a multi-hundred-KB `installId` - passes the name
check, passes both `props` caps, and fails for the first time at `ctx.db.insert`, landing on the same
`500` branch.
**One of the sink's own stated rules is reached by that residual too, which is worth separating out
because it is a matter of ordering rather than of a rule this sink never claimed.** The `props` caps
live inside the mutation, so they are evaluated only once `ctx.runMutation` has serialized its
arguments - and Convex bounds a function's arguments (~8 MiB) far above where those caps sit. A bag
past that bound therefore fails during argument serialization, as a plain `Error`, before the 32-key
and 4096-byte checks can run, and so answers `500` rather than the `400` the caps promise. The caps
answer `400` across the entire range a real client could plausibly send - the widest legitimate bag
is ~120 bytes, and the caps are two orders of magnitude above it - and only a multi-megabyte bag,
past Convex's own argument limit, comes back as a server error instead.
That is accepted for US-T03 rather than fixed, and the reasoning is recorded rather than assumed: it
takes a payload of several megabytes, which no accident produces; nothing can reach this endpoint at
all until US-T04; a pre-mutation size check would be more boundary logic in a story that ships with
no automated test to protect it; and it is the same shape as the oversized-`installId` case above, so
accepting it keeps that treatment consistent. The concern is real all the same - a `500` is meant to
mean the sink is broken, and this lets a caller manufacture one on the only outage signal a human
watching the PMF test has - so it is carried as an unchecked US-T04 acceptance criterion beside the
`installId` bound rather than left implicit.
All three are the same accepted consequence rather than three problems: the story's validation is
deliberately "basic input validation only", so the `400` side is exactly the set of rules this sink
states for itself plus the one it borrows, evaluated where they are - and everything Convex enforces
first or beyond that is discovered at serialization or at the insert and reported as ours. Note it
when reading `500`s during the PMF test; do not read this as a promise that every caller fault is a
`400`.
Relatedly and also accepted: the route below is unauthenticated and unmetered by design - anonymous
telemetry admits no client secret - so the caps are per-row rather than per-caller, and anyone who
reads the `.convex.site` URL out of a shipped binary can add rows indistinguishable from real ones.
(That is the HTTP *route*; the mutation behind it is internal and not separately reachable. Guarding
the route is US-T14.)

## HTTP action: `POST /logEvent` -> `204`

`convex/http.ts`. Routed by `httpRouter` and served from the deployment's **`.convex.site`** origin
(not `.convex.cloud`).

```
POST https://<deployment>.convex.site/logEvent
Content-Type: application/json

{
  "name": "session_completed",
  "installId": "…",
  "clientTs": 1785780300000,
  "props": { "requested_minutes": 15, "completed_minutes": 15, "was_return": false }
}
```

`props` is the one optional field: omit it and the action sends an empty bag, so a valid event with
no properties is a three-field body.
The other three are required, and their absence is one of the `400`s below rather than a default.

- **`204 No Content`** - the row was inserted. No body.
- **`400 Bad Request`** - the caller's fault: a body that is not valid JSON or not a JSON object, a
  missing or wrong-kind `name` / `installId` / `clientTs`, an unknown event name, a `props` field
  name Convex cannot store, or an oversized bag (across the whole range a real client could send;
  see the `500` note for the multi-megabyte exception). No row was inserted. The body carries the
  error message for a human.
- **`500 Internal Server Error`** - *our* fault: a deployment, runtime, or database failure. No row
  was inserted. The body says only `internal error`; the detail stays in the deployment log rather
  than being echoed to the caller. (With the accepted residual noted under "Known current gap": a
  caller fault that only a write-time Convex rule catches - an over-long `installId`, `props` nested
  past the value-depth limit - reaches the insert and is reported here too, as does a `props` bag
  past Convex's ~8 MiB argument bound, which fails during argument serialization before the bag caps
  themselves can run.)

Every non-`204` answer is `application/json` in one shape, `{"error": "…"}`, so US-T04's client can
read a rejection the same way whichever side of the split it came from - it just does not, being
fire-and-forget. `204` carries no body at all.

That split exists for a human, not for the client - US-T04's client is strictly fire-and-forget and
swallows every error, so a sink outage answered as `400` would be invisible: events would simply
stop arriving and nothing would say so. `4xx` versus `5xx` is the only signal anyone watching the
PMF test gets, so a rejection the sink asked for and a failure it did not must not look alike.

### Pinned numeric convention

`clientTs` and `serverTs` are `v.number()` - Convex **float64**.
The client sends `clientTs` as a plain JSON number, which *is* float64, so the Convex
`int64`-vs-`float64` trap the US-T01 spike documents (a `v.number()` field rejecting a Swift `Int`
encoded as `{"$integer": …}` through the SDK) never reaches it.
That is the whole reason the wire form is a bare JSON number rather than anything the action has to
reinterpret - and why the action requires one instead of coercing whatever it is handed.

`generation_ms` is **not** a top-level scalar. It rides inside `props`, which the action passes
through untouched and the schema stores as-is, so it is not reached by that coercion.

## Layout and deployment

Standard Convex layout: the npm project lives at the repo root (`package.json`, `package-lock.json`)
and the functions live here in `convex/`.
Convex bundles every file under the functions directory, so the functions directory cannot also be
the npm project root - `node_modules` would be swept into the bundle.

```bash
npm install
npx convex dev --once     # deploy schema + functions to the dev deployment
npx convex data events    # read rows back from the deployment
npm run typecheck         # tsc --noEmit over convex/
```

`convex/_generated/` **is committed** so `npm run typecheck` and an editor's type hints work in a
fresh clone with no deployment configured.
`.env.local` (which holds `CONVEX_DEPLOYMENT`) is gitignored and must never be committed - it is
per-developer deployment state, not project configuration.

Live validation evidence for this story is in `artifacts/reports/US-T03/validation.md`: the `204`s,
the rows read back with both timestamps populated and `serverTs` stamped server-side, and every
rejection above with the table then read back holding **only** the valid events, so the non-insert
is proven by the table's contents rather than inferred from the errors.
It records four runs, in the order they actually happened - the original one at `7fe0b31`; an interim
verification at `84726ed`, which is where the pre-fix `500`s on unstorable `props` field names were
seen directly and which accounts for the one row in the final listing no other run produced; a re-run
at `42c1310` that gates the post-review boundary checks, the `4xx`/`5xx` split, and the serialization
classification live, and whose `400`s on those same three inputs pair with the interim run's `500`s as
a before/after across the commit that fixed them; and a fourth at `99a11d0` that gates `logEvent`
being internal.
That last one is a before/after pair of the *same* direct `.convex.cloud/api/mutation` call: at
`42c1310` it answered `{"status":"success", …}` and inserted a row with an empty `installId` and a
`clientTs` of `0`; at `99a11d0` it answers
`Could not find public function for 'events:logEvent'` and inserts nothing.
The transport status is `200` in both cases - Convex reports a missing public function in the
response payload rather than as an HTTP status - so the proof is the payload plus the absent row, not
a status code. The junk row that the pre-fix probe inserted was afterwards deleted, and the
transcript records how; the table read back at `99a11d0` holds only valid rows.
What no run covers is two later, classifier-only rounds that landed after that third run and are
gated by `npm run typecheck` alone: the fourth deleted an unreachable branch of the action's error
classifier, and the fifth changed how the remaining branch recognises a `ConvexError` - from
`instanceof` to the SDK's own `Symbol.for("ConvexError")` test - which is a strict superset of what
`instanceof` matched and so leaves every response above unchanged. The transcript says so in place
rather than implying the current commit was re-probed.

**Nothing here has an automated behavioural test, and this repo has no CI.** The gate is
`npm run typecheck` plus the one-time transcript above, so a regression in the 13-name check, the
`installId`/`clientTs` validation, the field-name classification, the `props` caps, the `4xx`/`5xx`
split, or `logEvent` staying internal would not be caught by anything that re-runs. That is recorded
as an unchecked acceptance criterion of US-T04 in
`.claude/agent/tasks/prd-funnel-instrumentation_260803.md` - the story that first sends real traffic
through this boundary and the first to edit `http.ts` after US-T03 - and in `docs/test-coverage.md`.

# Rep Today telemetry sink (US-T03)

The whole analytics backend: **one append-only table, one mutation, one HTTP route.**

It exists so the anonymous funnel events defined in `gtm/06-channels/event-metric-schema.md` have
somewhere to land during the 90-day PMF test.
The client that fills it is `LiveAnalyticsService` (US-T04, landed), which reaches this deployment
with a plain `URLSession` POST and **no Convex SDK** - the US-T01 spike returned a no-go on
`convex-swift` because it ships an arm64-only xcframework that would break every Simulator-hosted
test suite in this repo on an Intel host (`artifacts/reports/US-T01/spike-note.md`).
The wire now has both ends, the wire itself, and - since US-T07 - its **first production callers**:
`RepTodayApp.init()` emits the three app-entry events (`app_install`, `day7_return`, `day30_return`)
through `AppEntryTelemetry.eventsForLaunch(...)`, and US-T08 added the second call site - the
onboarding flow emits `onboarding_started` and `onboarding_completed` through `OnboardingViewModel`.
That is five of the 13 emission sites (US-T09 through US-T12 add the other 8). So `record(_:)` is now
called at app entry and through onboarding - but a **Release build still reaches no sink**: its `REPTODAY_ANALYTICS_ENDPOINT` is empty, so the caller resolves
`NoOpAnalyticsService` and the events go nowhere until a production deployment is chosen (below),
while a Debug build's app-entry events do land here on a genuine first launch. The other caller is
US-T06's `#if DEBUG`, launch-argument-gated XCUITest probe, which normally has its own in-process
interceptor in front of it; pointed at a real deployment deliberately, as the US-T06 validation run
did, it writes ordinary rows here, so probe rows are a thing this table can contain and are deleted
by hand afterwards.
It also has a consent gate in front of it (US-T06, landed): the transport re-reads the user's
`AppState.analyticsEnabled` flag on every emission, so this table only ever
receives rows from installs that have not opted out. That is a **client-side** gate and this sink
knows nothing about it - it has no notion of consent, and no way to tell an install that opted out
from one that never ran. An install is simply absent, and this table cannot say which it was.
Nor is there a production deployment. Which one the app talks to is a per-configuration build
setting (`REPTODAY_ANALYTICS_ENDPOINT` in `ios/RepToday/project.yml`): a Debug build points at the
dev deployment, and a **Release build points nowhere at all** and is inert, because none has been
chosen. Choosing and deploying one is a precondition for shipping any build that emits, recorded on
US-T07's own acceptance criteria.
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
   serialized. (A `props` that is a non-null non-object is rejected under the same rule: a bag that
   is not a bag has no size, so that is the precondition the size check is measured against rather
   than a shape check of its own. A `props` of `null` never reaches it - the action treats it as
   absent, deliberately; see the `POST /logEvent` section below.)

Rationale for those numbers: the largest bag any real event carries is `session_completed` with
four small scalar keys (~120 bytes serialized), so both caps sit roughly two orders of magnitude
above anything the app legitimately sends - they stop a malformed or hostile client from poisoning
the table without ever policing a legitimate payload's shape.
The byte count is UTF-8 (`TextEncoder`), not `String.length`, which counts UTF-16 code units and
would undercount a non-ASCII bag against a limit called "bytes".

There is no schema check on individual property keys or types. Property vocabularies are expected
to move during the PMF test, and a write-path check would turn every such move into a deploy.

The HTTP action adds to that list, and the additions are enumerated rather than summarised. First,
the body's fields must be **present and of the right kind** before they are handed to the mutation -
`name` one of the 13, `installId` a non-empty string, `clientTs` an actual JSON number (a numeric
*string* like `"1e3"` is refused, not coerced).
That is not a third rule so much as the same one applied where untrusted input enters: coercing a
missing or wrong-kind field with `String(...)` / `Number(...)` would write the literal string
`"undefined"`, `NaN`, or a silently reinterpreted `"0x1f"` into the two columns the whole funnel is
counted on (`installId` is the cohort key K4 counts unique installs by; `clientTs` is what K1 is
timed from), and such a row looks valid while being junk - worse than no row at all.
That constrains presence and kind: no format or UUID-shape check, nothing about what a legitimate
value contains.
Read that literally rather than as a promise of plausibility. A `clientTs` of `0`, or of `1e300`,
is a finite JSON number and lands - the check rules out the *missing* and *wrong-kind* cases
(`undefined`, `NaN`, `"1e3"`), not implausible ones. Range and sanity belong to a query written
later against the raw rows, where they can be revised without a deploy, which is the same reason
the sink is dumb everywhere else.

**Two size caps, added by US-T04** (`MAX_INSTALL_ID_BYTES` and `MAX_REQUEST_BODY_BYTES` in
`http.ts`), which is when a real client first started sending anything here:

3. **An `installId` over 64 UTF-8 bytes.** US-T05's identifier is a UUIDv4 - 36 ASCII characters -
   so the bound sits well clear of a legitimate value while leaving room for a differently-shaped
   anonymous id. It is a **length** bound and nothing more: `"not-a-uuid"` is accepted, because
   policing the identifier's *shape* would forbid a future story from changing it.
4. **A request body over 64 KiB**, checked on the raw bytes before the body is even parsed. 64 KiB
   is an order of magnitude above the 4096-byte `props` cap plus that identifier, so across the
   range a real client could send it does not pre-empt the mutation's own, more specific rejection -
   a 5 KiB bag still comes back told which limit it broke. That is not an absolute ordering, and the
   suite asserts the other side of it too: a bag past 64 KiB is answered by *this* cap rather than
   the `props` one, which is still a caller's `400`, just the less specific of the two. And it is
   far below any bound Convex applies to a function's arguments, so serialization can no longer be
   reached by size.

Both are the same `400`-and-no-insert as every other caller fault, and both closed gaps this file
used to carry as accepted; see "What used to be a gap here" below.

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

### What used to be a gap here, and what is left of it

US-T03 shipped two size gaps knowingly, on the reasoning that no client could reach this endpoint
yet. **US-T04 closed both**, and probed each against the real dev deployment before and after
(`artifacts/reports/US-T04/validation.md`). Two of the observations corrected what this file used to
predict, so they are recorded rather than quietly overwritten:

- `installId` was an unbounded `v.string()` while `props` was capped, and this file predicted that a
  multi-hundred-KB identifier would fail at the insert and be misreported as a `500`. It did not: a
  **300 KB `installId` was accepted and inserted a 300 KB row**, because Convex's document limit is
  around 1 MB. The false-outage `500` only began at ~1.5 MB. So the gap was worse than written up -
  not a misclassified status but a real row in the evidence table, through the one field with no
  ceiling. Both cases now answer `400`.
- The `props` caps live inside the mutation, so they run only once `ctx.runMutation` has serialized
  its arguments, and a bag past Convex's argument bound therefore failed during serialization as a
  plain `Error` and answered `500` - letting a caller manufacture the sink's only outage signal.
  That reproduced, but **at ~24 MB, not the ~8 MiB this file used to cite**: 3 MB and 16 MB bags
  both came back as the mutation's own `400`. The concern was real and the number was not.

**The residual that remains is narrower, and is stated here in full rather than as its cheapest
example.** The `convexToJson` pre-pass is a *field-name* classifier and nothing more: the SDK's
`validateObjectField` checks a name's length against 1024, a leading `$`, and non-ASCII or control
characters, and `convexToJson` recurses without a depth guard. It therefore says nothing about
nesting depth, about value shapes, or about any other rule Convex only applies at write time. A
caller-fault payload that violates one of those - `props` nested past Convex's value-depth limit,
say, which can be well under 100 bytes and so passes both size caps easily - passes the name check,
passes both `props` caps, and fails for the first time at `ctx.db.insert`, landing on the `500`
branch. That is left open deliberately: closing it would mean the per-key and per-type validation of
`props` the story forbids, and property vocabularies are expected to move during the PMF test.
It is also the one boundary behaviour the automated suite cannot assert, because `convex-test`'s
in-memory database does not enforce the value-depth limit - the suite reaches the `500` branch by
substituting a mutation that throws instead.
So: the `400` side is exactly the set of rules this sink states for itself, plus the one it borrows,
plus the two size caps, evaluated where they are - and a caller fault that only a *write-time* Convex
rule catches is still discovered at the insert and reported as ours. Note that when reading `500`s
during the PMF test; do not read this as a promise that every caller fault is a `400`.

Relatedly and still accepted: the route below is unauthenticated and unmetered by design - anonymous
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
Sending it as `null` is the same thing - `props: body.props ?? {}` treats a null bag as an absent
one, so it answers `204` and stores `{}`.

That coercion is deliberate, and it is *not* the one `installId` and `clientTs` refuse. Those two
are the columns K4 and K1 are counted from, where a coerced value is junk sitting
in a counted column looking valid - the literal string `"undefined"`, or `NaN`. Nothing is counted
from `props`: it carries no schema and is stored exactly as it arrived, so an empty bag is a truthful
"this event carried no properties" rather than a fabricated value. The asymmetry is the rule doing
its stated job, not an oversight, and the suite asserts it in place.

The other three fields are required, and their absence is one of the `400`s below rather than a
default.

- **`204 No Content`** - the row was inserted. No body.
- **`400 Bad Request`** - the caller's fault: a body that is not valid JSON, not a JSON object, or
  over 64 KiB; a missing or wrong-kind `name` / `installId` / `clientTs`; an unknown event name; an
  `installId` over 64 bytes; a `props` field name Convex cannot store; or an oversized bag. No row
  was inserted. The body carries the error message for a human.
- **`500 Internal Server Error`** - *our* fault: a deployment, runtime, or database failure. No row
  was inserted. The body says only `internal error`; the detail stays in the deployment log rather
  than being echoed to the caller. (With the residual noted under "What used to be a gap here": a
  caller fault that only a *write-time* Convex rule catches - `props` nested past the value-depth
  limit, say - reaches the insert and is reported here too. The two size cases that used to land
  here no longer do.)

Every non-`204` answer is `application/json` in one shape, `{"error": "…"}`, so the client can read
a rejection the same way whichever side of the split it came from - it just does not, being
fire-and-forget. `204` carries no body at all.

That split exists for a human, not for the client - `LiveAnalyticsService` is strictly
fire-and-forget and swallows every error, so a sink outage answered as `400` would be invisible:
events would simply stop arriving and nothing would say so. `4xx` versus `5xx` is the only signal
anyone watching the PMF test gets, so a rejection the sink asked for and a failure it did not must
not look alike.

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
npm run typecheck         # tsc --noEmit over both configs below
npm test                  # vitest + convex-test: the boundary suite, in process, no deployment
```

There are **two** tsconfigs here, and the split is load-bearing rather than tidiness.
`convex/tsconfig.json` is the one the Convex CLI typechecks on every `convex dev` / `convex deploy`,
so it must depend on nothing a production install omits: it excludes `**/*.test.ts` and sets no
`types` array at all, since naming one would also switch off automatic inclusion of every other
`@types` package for the deployed functions.
`convex/tsconfig.test.json` extends it, adds back the test files, and carries the `vite/client` types
`import.meta.glob` needs.
`npm run typecheck` runs **both**, so the suite stays typechecked - an untypechecked test rots
without saying so - while `npx convex deploy` no longer depends on the test toolchain being installed.
The *bundler* was never the problem: it skips any filename with more than one dot, so `http.test.ts`
was already excluded from the deployed functions. It was the CLI's typecheck of this config that the
test file had quietly pulled the test toolchain into.

`convex/_generated/` **is committed** so `npm run typecheck` and an editor's type hints work in a
fresh clone with no deployment configured.
`.env.local` (which holds `CONVEX_DEPLOYMENT`) is gitignored and must never be committed - it is
per-developer deployment state, not project configuration.

Live validation evidence for the sink as US-T03 shipped it is in
`artifacts/reports/US-T03/validation.md`: the `204`s,
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

US-T04's own live evidence is separate, in `artifacts/reports/US-T04/validation.md`: the two new size
rejections probed against the pre-US-T04 action and then against this one, on the same deployment, so
each is a before/after pair rather than a claim about what used to happen; the row a 300 KB
`installId` used to insert, and its deletion; and the transport driven from the real installed app,
whose rows carry the app's own `installId` read out of its preferences plist and a `props` bag of
plain scalars. That transcript also states, at the top and in its own words, that the shipped build
contains **no** emission call site, so what its live legs prove is that the transport and this sink
work end to end - not that the app emits anything yet.

## The boundary suite (US-T04)

`convex/http.test.ts`, run with `npm test`. US-T03 shipped this boundary gated by
`npm run typecheck` plus the one-time transcript above, which left nothing that re-runs: `tsc`
cannot catch a regression in a validation *rule*, and this repo has no CI. That gap is closed for
everything the endpoint can be made to do from outside itself.

`convex-test` executes the real functions in process, in the edge runtime Convex uses, against an
in-memory database and no deployment, so the suite needs no network and no `.env.local`. It drives
`t.fetch("/logEvent", …)` - the same route a client hits - and asserts, for **every** rejection, that
the table is still empty afterwards: a `400` that inserted anyway would be worse than no check at
all, so the proof is the row count rather than the status code.

Covered: the happy path (`204`, one row, both timestamps, `props` stored as-is, an omitted bag
defaulting to `{}`, and two events being two rows); all 13 names accepted and unknown/empty/
non-string/missing names refused; `installId` present, a string, non-empty, and within the 64-byte
bound, counted as UTF-8 rather than UTF-16, with the bound asserted to be length-only; `clientTs` an
actual finite JSON number, including `1e400` arriving as `Infinity` off the wire and a `clientTs` of
`0` deliberately landing; the request-size cap, both that a 5 KiB bag still gets the `props` cap's
more specific message and that a bag past 64 KiB gets this one instead; both `props` caps at their
exact boundaries, with the byte cap counted in UTF-8; a `props` that is a non-null non-object
refused, beside a `props` of `null` deliberately answering `204` with an empty bag;
the `convexToJson` field-name classification answering `400` rather than `500`; the `4xx`/`5xx`
split, including that a `5xx` echoes no internal detail; and `logEvent` still being an
`internalMutation`.

Two notes on how two of those are reached, since neither can be provoked by input:

- The `500` branch is exercised by handing `convexTest` a module map with `logEvent` swapped for a
  mutation that throws a plain `Error` carrying a would-be-secret message. `http.ts` is untouched.
- `logEvent` staying internal is asserted on the registration object's own `isInternal` flag - the
  one Convex's `internalMutationGeneric` sets and the server reads - and **not** on
  `api.events.logEvent`, which can say nothing: the generated `api` is `anyApi`, a proxy that answers
  every property access whether the function exists or not.

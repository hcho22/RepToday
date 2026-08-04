# US-T03 Validation - live Convex sink

**Story:** US-T03 of `.claude/agent/tasks/prd-funnel-instrumentation_260803.md` - one append-only
table, one `logEvent` mutation, one `POST /logEvent` HTTP action.
**Date:** 2026-08-04
**Verdict:** PASS. Every step of the PRD's Validation Test was run against a live deployment, not
simulated and not inferred from a local type-check.

> **Read this first (2026-08-04).** The transcript in the body records a live run against the code as
> it stood at commit `7fe0b31`. Review then hardened `convex/http.ts` over three rounds, and every one
> of those fixes **has since been re-validated live**: the first two at commit `42c1310` - recorded
> under "Post-review re-validation", and where the current response bodies come from - and the third,
> `logEvent` becoming an `internalMutation`, at commit `99a11d0`, recorded under "The direct-mutation
> bypass" with the before/after pair that makes it legible. The body below is kept as the original
> record and is marked in place wherever its recorded output no longer describes current behaviour;
> nothing in it was rewritten to predict output that was never observed.
>
> What the original run still establishes unchanged: the `204` and both persisted rows, the
> server-stamped `serverTs`, the untouched `props` pass-through, the two oversized-bag rejections,
> the non-insert proven by reading the table back, and every shape assertion.
>
> **The scope boundary, stated rather than glossed:** a fourth review round deleted an unreachable
> branch of the action's error classifier in `convex/http.ts`, and that deletion landed *after* the
> `99a11d0` run. So this transcript covers every behaviour through commit `99a11d0` and not the commit
> that carries the deletion; no result is claimed for the latter.

---

## Deployment

| | |
|---|---|
| Convex team / project | `hcho22` / `reptoday-telemetry` |
| Dev deployment | `courteous-dogfish-560` |
| Client URL | `https://courteous-dogfish-560.convex.cloud` |
| HTTP actions URL | `https://courteous-dogfish-560.convex.site` |
| CLI | `convex@1.43.0`, node v20.19.5 |

The US-T01 scratch project (`ust01-spike` / `determined-vulture-542`) was **not** reused: this is a
fresh project, so the sink's own table starts empty and the row counts below are unambiguous.

`npx convex dev --once` deployed the schema, the mutation, and the HTTP action, with the CLI's own
`tsc` typecheck gating the push:

```
▌ [Development] hcho22:reptoday-telemetry:dev/hyung-cho (dev)
▌ └─ https://courteous-dogfish-560.convex.cloud
✔ 06:28:43 Convex functions ready! (2s)
```

The sequence below was run twice - once against the first deploy, then re-run in full against the
final deploy after the byte counter was changed from `String.length` to UTF-8 (see "Why the byte
counter changed"). The transcript is the **final** run; the numbers below are what the deployed code
produces.

---

## Step 2 - a valid event returns `204` and inserts a row with a server-stamped timestamp

Two valid POSTs were sent across the two runs, and both are in the table.

```
POST https://courteous-dogfish-560.convex.site/logEvent
Content-Type: application/json
{"name":"session_completed","installId":"ust03-validation-A1B2","clientTs":1785780300000,
 "props":{"requested_minutes":15,"completed_minutes":15,"was_return":false,
          "perceived_difficulty":"just_right","generation_ms":38}}

HTTP 204          (empty body)
```

```
POST https://courteous-dogfish-560.convex.site/logEvent
{"name":"ready_screen_shown","installId":"ust03-final-R1","clientTs":1785780700000,
 "props":{"generation_ms":38}}

HTTP 204          (empty body)
```

`session_completed` was chosen deliberately: it is the widest real bag in the pre-registered
schema. Both payloads carry `generation_ms` inside `props` to prove the bag is passed through
untouched rather than reached by the action's top-level handling of the scalar fields.

Read back from the deployment with `npx convex data events` - an authenticated query round-trip
against the persisted rows, so a false local success is ruled out:

```
_id                                | _creationTime      | clientTs      | installId               | name                 | props                                                                                                                              | serverTs
"j5711hh2654zq32h59f13em21s8bt6aj" | 1785850123781.344  | 1785780700000 | "ust03-final-R1"        | "ready_screen_shown" | { "generation_ms": 38 }                                                                                                            | 1785850123781
"j5745cj8xgz584taynenzm43ws8bvvae" | 1785849799366.7122 | 1785780300000 | "ust03-validation-A1B2" | "session_completed"  | { "completed_minutes": 15, "generation_ms": 38, "perceived_difficulty": "just_right", "requested_minutes": 15, "was_return": false } | 1785849799366
```

On both rows the two timestamps are populated and **different**: `clientTs` is the value the
request carried, `serverTs` is a wall-clock instant from the deployment (~1785850123781, i.e. the
moment of the POST) - stamped server-side by the mutation, not echoed from the client. `props` came
back intact on both, `generation_ms` still a plain number.

---

## Step 3 - the invalid calls are rejected, and nothing is inserted

Three rejections were exercised over the same HTTP route: the unknown event name the PRD names, and
both halves of the oversized-bag cap this story pins.

### Unknown event name

`landing_page_view` is a real event in `gtm/06-channels/event-metric-schema.md`, but it is web-side
and deliberately outside the app's 13, which makes it the sharpest possible probe of the union.

```
{"name":"landing_page_view","installId":"ust03-final-BAD","clientTs":1785780800000,"props":{}}

HTTP 400
{"error":"ArgumentValidationError: Value does not match validator.\nPath: .name\nValue: \"landing_page_view\"\nValidator: v.union(v.literal(\"app_install\"), v.literal(\"onboarding_started\"), v.literal(\"onboarding_completed\"), v.literal(\"ready_screen_shown\"), v.literal(\"session_started\"), v.literal(\"session_completed\"), v.literal(\"session_abandoned\"), v.literal(\"day7_return\"), v.literal(\"day30_return\"), v.literal(\"week_active\"), v.literal(\"paywall_shown\"), v.literal(\"trial_started\"), v.literal(\"subscribe\"))"}
```

The error enumerates all 13 accepted literals, which is itself confirmation that the deployed union
matches `AnalyticsEventName` exactly - no additions, no omissions.

> **Superseded, response body only.** The post-review action checks the name against `EVENT_NAMES`
> before calling the mutation, so this rejection is now raised at the HTTP boundary and the body no
> longer carries Convex's `ArgumentValidationError` text. The status is still `400` and still
> inserts nothing, and the mutation's `v.union` is unchanged and still the contract - it is simply
> no longer the thing that fires first, so this particular body is not what the current code
> returns. The body it does return was observed in the re-validation run below.

### Oversized bag - serialized bytes

```
props = { "blob": "é" * 2100 }        # 2111 UTF-16 code units, 4211 UTF-8 bytes

HTTP 400
{"error":"Uncaught Error: props is 4211 bytes, over the 4096-byte limit\n    at handler (../convex/events.ts:79:8)"}
```

### Oversized bag - key count

```
props = { k0: 0, …, k39: 39 }         # 40 keys, over the 32 cap

HTTP 400
{"error":"Uncaught Error: props has 40 keys, over the 32-key limit\n    at handler (../convex/events.ts:70:8)"}
```

> **Superseded, response bodies only** (both oversized-bag cases above). `logEvent` now raises these
> two rejections as `ConvexError` rather than `Error`, which is the marker the action uses to answer
> `400` for a caller's fault and `5xx` for its own. The limits, the sentences they are phrased in,
> the `400`, and the non-insert are all unchanged; what is gone is the `Uncaught Error:` prefix and
> the trailing stack frame, which were the shape a raw throw surfaced as. The bodies they return now
> were observed in the re-validation run below.

### No row was inserted - read back, not inferred

The `npx convex data events` listing quoted under step 2 was taken **after** all of these
rejections. It holds exactly two rows, and both are the valid POSTs. None of
`ust03-validation-BAD1`, `ust03-validation-BIG1`, `ust03-validation-KEYS1`, `ust03-final-BAD`,
`ust03-final-BIG`, or `ust03-final-KEYS` is present.

So: six rejected POSTs across the two runs, zero rows. The non-insert is proven by the table's
contents, not inferred from the error responses.

---

## Why the byte counter changed mid-validation

The first deploy measured the bag with `JSON.stringify(props).length`, which counts UTF-16 code
units rather than bytes. The rejection passed its ASCII test (`"x" * 5000` -> "5011 bytes") but the
limit was misnamed: a bag of accented or CJK text would have been undercounted by up to a factor of
three against a cap documented in bytes. The deployed code now measures
`new TextEncoder().encode(...).length`, and the re-run above uses a deliberately non-ASCII payload
to gate it - 2100 `é` characters are only 2111 UTF-16 units (which would have **passed** the old
check) but 4211 UTF-8 bytes, which is correctly rejected.

## Shape assertions

- **No indexes.** `convex/schema.ts` declares `defineTable({...})` with no `.index(...)` call; the
  read-back rows carry only Convex's default `_id` / `_creationTime`.
- **No funnel or cohort structure.** Five fields, one of which is an opaque `v.any()` bag.
- **Append-only.** `logEvent`'s handler contains one `ctx.db.insert` and no query, patch, delete,
  or aggregation.
- **No app code changed.** The diff touches `convex/`, root `package.json` / `package-lock.json`,
  and documentation only; `ios/` is untouched. The iOS build and `RepTodayTests` were nonetheless
  run green on an iPhone 16 Simulator so the "build and tests pass" criterion is observed rather
  than assumed.

## Post-review re-validation (commit `42c1310`, 2026-08-04)

The two review rounds that hardened `convex/http.ts` were re-run in full against the same dev
deployment (`courteous-dogfish-560`, `https://courteous-dogfish-560.convex.site/logEvent`). These are
observed responses, not predictions.

**Accepted:**

```
session_completed, props {requested_minutes, completed_minutes, was_return, perceived_difficulty}
  -> HTTP 204
day7_return, props omitted from the body entirely
  -> HTTP 204        (stored as {})
```

**Rejected - all `400`, and the response bodies are now the action's own sentences rather than the
Convex internals the original run recorded:**

| POST | Body |
|---|---|
| `props {"café":1}` | `{"error":"props contains a field name Convex cannot store"}` |
| `props {"$evil":1}` | same |
| `props` key of 1100 characters | same |
| `clientTs "1e3"` | `{"error":"clientTs must be a finite number of milliseconds since the epoch"}` |
| `clientTs "0x1f"` | same |
| `clientTs " 12 "` | same |
| `clientTs` absent | same |
| `name "landing_page_view"` | `{"error":"name must be one of the 13 pre-registered event names"}` |
| `installId` absent | `{"error":"installId must be a non-empty string"}` |
| `installId ""` | same |
| `props {blob: "é" * 2100}` | `{"error":"props is 4211 bytes, over the 4096-byte limit"}` |
| `props` with 40 keys | `{"error":"props has 40 keys, over the 32-key limit"}` |
| body `not json at all` | `{"error":"body is not valid JSON"}` |
| body `[1,2,3]` | `{"error":"body must be a JSON object"}` |

`npx convex data events` afterwards holds only the valid rows: **14 rejected POSTs, zero rows.** The
non-insert is again proven by the table's contents rather than inferred from the responses.

That claim is about the HTTP route and is scoped to it: none of those 14 rejected POSTs added a row.
It is **not** a claim about the whole table at that moment, because the direct-mutation bypass probe
recorded in the next section was run separately at this same commit and *did* add one row - through
the `.convex.cloud` API endpoint, not through this route. That row's fate is recorded there, and the
complete table listing at the end of this file is the authoritative statement of what the deployment
holds now.

Two review fixes are gated specifically by this run. The three former-`500` cases - the non-ASCII,
`$`-prefixed, and over-long `props` keys - answer `400` now, which is the caller-fault
re-classification working: the input was refused before the change too, but as *our* failure, which
a hostile client could have used to manufacture what looked like a sink outage on the only signal
the PMF test has. And the four `clientTs` cases confirm the string-coercion branch is gone: `"1e3"`,
`"0x1f"`, and `" 12 "` are refused rather than silently reinterpreted into the column K1 is timed
from.

## The direct-mutation bypass - observed open, then observed closed

The same request was sent twice: once at commit `42c1310`, while `logEvent` was still a public
`mutation`, and once at commit `99a11d0`, after it became an `internalMutation`. The request is
byte-for-byte identical, so the pair is what makes the fix's value legible.

**Before the fix (commit `42c1310`).** `logEvent` was public, so it was reachable on the deployment's
own API endpoint, skipping every boundary check above:

```
POST https://courteous-dogfish-560.convex.cloud/api/mutation
{"path":"events:logEvent",
 "args":{"name":"app_install","installId":"","clientTs":0,"props":{}},
 "format":"json"}

HTTP 200
{"status":"success","value":"j579gg022ndcfdb4qq282fdjbn8btryz"}
```

That **inserted a row** with an empty `installId` and a `clientTs` of `0` - precisely the junk-row
shape the `400`s above exist to keep out of the two columns K4 and K1 are counted from. `.convex.cloud`
and `.convex.site` share a deployment slug, so anyone reading the HTTP-action URL out of a shipped
US-T04 binary would have known this endpoint too.

**After the fix (commit `99a11d0`).** The identical request now finds no function to call and writes
nothing:

```
POST https://courteous-dogfish-560.convex.cloud/api/mutation
{"path":"events:logEvent",
 "args":{"name":"app_install","installId":"","clientTs":0,"props":{}},
 "format":"json"}

HTTP 200
{"status":"error",
 "errorMessage":"[Request ID: cea9f35b743a3016] Server Error\nCould not find public function for 'events:logEvent'."}
```

Read the transport status carefully: it is `200` in **both** cases. Convex reports a missing public
function in the response *payload*, not as an HTTP status, so this endpoint does not start answering
`4xx` after the fix and nothing here should be described as it doing so. The proof is the two things
that did change - the `errorMessage` in place of `{"status":"success", …}`, and the absent row.

The HTTP route itself was re-run at the same commit and is unchanged by the switch: a valid
`session_completed` (with `requested_minutes`, `completed_minutes`, `was_return`,
`perceived_difficulty`) and a valid `day7_return` with `props` absent from the body entirely each
answered `204`, while `name "landing_page_view"`, `installId ""`, `clientTs "1e3"`, `props {"café":1}`
and a body of `not json` answered `400` with the same five sentences the table above records,
verbatim.

### What happened to the junk row

The row the pre-fix bypass inserted, `j579gg022ndcfdb4qq282fdjbn8btryz`, **was deleted.** How it was
deleted matters, because this file's whole method is proof-by-table-contents and because the repo
claims to contain exactly one mutation: a scratch delete-by-id mutation was written **outside the
repository** in a temporary working copy, deployed to the dev deployment, run once against that
single document id (it returned `deleted`), and then removed again by redeploying this branch's own
code. It was never committed. The repository still contains exactly one mutation, `logEvent`, and it
is internal.

### The table as it stands (commit `99a11d0`)

`npx convex data events` - the complete table, not an excerpt:

```
j57576n6sdgxr546ekddf19ren8bty2c | clientTs 1785783050000 | installId "r4-NOPROPS"            | day7_return        | serverTs 1785854249727
j57121ny3kr8xqpn3bvrypvsrs8btj32 | clientTs 1785783000000 | installId "r4-OK"                 | session_completed  | serverTs 1785854249456
j5728zwm38mfhrswvd7ka7tess8bt5pp | clientTs 1785782050000 | installId "r3-NOPROPS"            | day7_return        | serverTs 1785853252403
j57f1nb7z5btnq4fgxps2k7j4s8btspf | clientTs 1785782000000 | installId "r3-OK"                 | session_completed  | serverTs 1785853252141
j571dvabbpm6aef09ax1kzkab58bv6y9 | clientTs 1785781100000 | installId "verify-OK"             | session_started    | serverTs 1785852078940
j5711hh2654zq32h59f13em21s8bt6aj | clientTs 1785780700000 | installId "ust03-final-R1"        | ready_screen_shown | serverTs 1785850123781
j5745cj8xgz584taynenzm43ws8bvvae | clientTs 1785780300000 | installId "ust03-validation-A1B2" | session_completed  | serverTs 1785849799366
```

The `props` column is not reproduced above; the two `*-NOPROPS` rows, whose POSTs omitted `props` from
the body entirely, came back holding `{}`, which is the default the action supplies.

Every row has a non-empty `installId`, a non-zero `clientTs`, and a `serverTs` distinct from its
`clientTs`. The empty-`installId` row is absent. So the file's proof method holds end to end: what the
table contains, not what the responses said, is the evidence - and what it contains is only valid
events.

## Limitation

The dashboard at `https://dashboard.convex.dev/d/courteous-dogfish-560` sits behind an interactive
OAuth sign-in and was not opened, for the same reason recorded in the US-T01 spike note. The
`npx convex data events` round-trip is the equivalent authoritative evidence: it is authenticated by
the CLI token and returns the deployment's actually-persisted rows - the same data the dashboard
renders.

# US-T03 Validation - live Convex sink

**Story:** US-T03 of `.claude/agent/tasks/prd-funnel-instrumentation_260803.md` - one append-only
table, one `logEvent` mutation, one `POST /logEvent` HTTP action.
**Date:** 2026-08-04
**Verdict:** PASS. Every step of the PRD's Validation Test was run against a live deployment, not
simulated and not inferred from a local type-check.

> **Partially superseded (post-review, 2026-08-04).** This transcript records a live run against the
> code as it stood at commit `7fe0b31`. Two review findings were fixed in `convex/http.ts` afterwards
> and **the fixes were not re-validated against a live deployment** - they were gated only by
> `npm run typecheck`. Nothing below was re-run, and no output in this file has been edited to
> predict what the new code would return; the individual sections that no longer describe current
> behaviour are marked in place. What still holds unchanged: the `204` and both persisted rows, the
> server-stamped `serverTs`, the untouched `props` pass-through, the two oversized-bag rejections,
> the non-insert proven by reading the table back, and every shape assertion.
>
> What changed:
> 1. The action now requires `installId` to be a non-empty string and `clientTs` to coerce to a
>    finite number, rejecting instead of writing `"undefined"` / `NaN`. **No POST in this transcript
>    omitted either field, so no run below exercised the old behaviour** - this is new surface with
>    no live evidence either way, not a contradicted result.
> 2. Rejections and internal failures no longer share a status. A caller's fault stays `400`; a
>    deployment or database failure now answers `500` with no detail echoed. Every rejection
>    recorded below is a caller's fault, so all of them remain `400`.

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
untouched rather than reached by the top-level `Number(...)` coercion.

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
> returns. Not re-run; no replacement output is claimed here.

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
> the trailing stack frame, which were the shape a raw throw surfaced as. Not re-run; the exact
> current bodies are not claimed here.

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

## Limitation

The dashboard at `https://dashboard.convex.dev/d/courteous-dogfish-560` sits behind an interactive
OAuth sign-in and was not opened, for the same reason recorded in the US-T01 spike note. The
`npx convex data events` round-trip is the equivalent authoritative evidence: it is authenticated by
the CLI token and returns the deployment's actually-persisted rows - the same data the dashboard
renders.

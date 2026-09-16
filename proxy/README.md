# Rep Today LLM Proxy

A thin, stateless, key-holding proxy for Rep Today's Phase 2 LLM slices. It exists so every upstream
model call runs **without shipping an API key in the app**, and so the app never has to trust it: each
client enforces its own short timeout and degrades cleanly on any failure, timeout, or absence of
this proxy.

Two routes live here, both stateless and storing nothing:

- **`POST /variety-language`** (US-N05) - the deferred day-one Variety Language line. Not wired in
  the shipping MVP; the client (`ProxyVarietyLanguageProvider`) falls back to the deterministic
  on-device template on any failure.
- **`POST /coach`** (US-AC01) - the premium AI coach transport. A derived, non-identifying context
  bundle + the user's message + a dedicated abuse-prevention pseudonym in, an OpenAI reply out. The
  chat surface that drives it is US-AC02; US-AC01 ships the transport only.

The descriptions above and below concern the currently deployed legacy Worker entry. The prepared
stronger-authentication gateway is separate and **not deployed**: it adds bounded device security
metadata while retaining no message/training/reply content or purchase proofs. Its iOS flow,
prerequisites, secure Apple intake, TestFlight/Sandbox limit and held migration plan are in
[`docs/coach-runtime-authentication.md`](../docs/coach-runtime-authentication.md). A shipped binary
never receives the production operator gate. Ordinary endpoint settings remain empty until the
migration and genuine-device QA are accepted. The dedicated prepared migration helper
`tools/migrate-coach-runtime.sh` stages under a verified hold and has separate release/hold-only
rollback operations; `tools/test-coach-runtime-migration.sh` tests it without external access. The
official Apple SDK API workerd regression passes after a diagnosed redirect-mode correction; all
requests still terminate in a local fixture. Preparation is not evidence of approved migration
readiness or genuine Apple/model QA.

## What it does

- Holds provider API keys (Wrangler secrets) and proxies **exactly one** model call per request.
  Variety Language uses Anthropic; the premium Coach uses OpenAI.
- **Stores no user data at rest, on either route.** Nothing is persisted: no KV, no D1, no cache, no
  scheduler, and **no request/response body logging**. History is read transiently from the request
  and discarded when the response is sent. The coach's conversation memory, if any, lives on the
  device in the client - never here.
- Carries **no Rep Today identity on the wire**: no account, `installId`, IDFA, Apple ID, email, name,
  or profile. `/variety-language` carries only two pillar values; `/coach` carries the app-audited
  context bundle, the free-text the user typed, and a separately generated random Coach identifier
  used only for OpenAI abuse prevention. That pseudonym is stable across launches and rotates when
  the user deletes their account.
- Bounds every upstream call with `AbortSignal.timeout` and caps the request body at **32 KiB**
  (checked before parsing, so an oversized payload never reaches JSON parsing or a paid model call).

"Stateless" and "stores nothing" above describe the Rep Today Worker. The Coach request sets
`store: false`, so the OpenAI Responses API does not retain response application state, but that flag
does not disable OpenAI's standard abuse-monitoring logs. OpenAI may retain the Coach prompt (message
and training summary) and reply in those logs for up to 30 days. This deployment does not require Zero
Data Retention or Modified Abuse Monitoring; the user disclosure assumes standard retention. The
Coach request still carries no Rep Today identity field. Its `safety_identifier` is a separate,
locally generated pseudonym, never the raw installation identifier or an account value.

## Wire contract: `POST /variety-language` (US-N05)

The client calls this route **only** for the Variety Language slice, and always falls back to the
template on any non-2xx, timeout, or malformed response.

### Request

```
POST /variety-language
Content-Type: application/json
```

```json
{
  "today": "mobility",
  "yesterday": "strength",
  "todayLabel": "mobility",
  "yesterdayLabel": "strength"
}
```

- `today` (required) - the lead pillar of today's assembled session: `strength` | `mobility` | `primal`.
- `yesterday` (optional) - the previous session's lead pillar, **present only when it genuinely
  differs**. Omitted for a first session or a same-pillar day, so the proxy can never invent a
  contrast.
- `todayLabel` / `yesterdayLabel` (optional) - the user-facing words for those pillars, so the
  model phrases with the product's own vocabulary. Default to the pillar value when absent.

### Response

```json
{ "line": "Today leans into mobility - yesterday was all strength." }
```

On any problem the proxy returns a non-2xx with `{ "error": "<code>" }`
(`method_not_allowed`, `unauthorized`, `payload_too_large`, `invalid_json`, `invalid_today`,
`invalid_yesterday`, `not_configured`, `upstream_unreachable`, `upstream_error`, `upstream_bad_json`,
`empty_line`).
The client treats **every** non-2xx and every malformed body identically: discard and fall back to
the template. A failing or absent proxy never blocks the app.

## Wire contract: `POST /coach` (US-AC01)

The coach client (`CoachProxyClient`) POSTs the derived context bundle plus the user's message and
classifies the reply or safety outcome. It throws on any non-2xx, timeout, or malformed body so the
(US-AC02) chat surface degrades to a clear, non-blocking state - the free core loop never depends on it.

### Request

```
POST /coach
Content-Type: application/json
```

```json
{
  "context": {
    "phase": "discipline",
    "requestedMinutes": 15,
    "chainPositions": [
      { "pattern": "push", "currentExercise": "Standard Push-Up", "tier": 3, "chainLength": 7, "hasNextTier": true }
    ],
    "recentPatterns": ["push", "core", "squat"],
    "consistency": { "currentScore": 72, "direction": "rising" }
  },
  "message": "why did I get squats today?",
  "safetyIdentifier": "coach-00000000-0000-4000-8000-000000000001"
}
```

- `context` (required) - the **derived context bundle**: the single, auditable, non-identifying
  summary the app is allowed to send (see `ios/RepToday/RepToday/Services/Coach/CoachContextBundle.swift`,
  which defines this exact shape). It is summarized catalog/aggregate data - phase, per-pattern chain
  positions, recent movement patterns, a coarse consistency signal, a coarse per-pattern
  strength-journey trend (US-AN02: pattern, `climbing`/`flat`/`steady`, weeks at the current tier,
  whether it has advanced - no date, id, or identity field), requested minutes - and contains
  **no raw `WorkoutLog` history and no identity field**. The proxy validates it is present and
  object-shaped but does not otherwise constrain it (the app owns the definition).
- `message` (required) - the user's free-text question. Non-empty and at most **2000 characters**
  (the iOS client caps the same value; the proxy re-checks as defense in depth).
- `safetyIdentifier` (required) - a random, app-generated `coach-<UUIDv4>` pseudonym. It is distinct
  from `installId` and every account value, remains stable across launches, and rotates on account
  deletion. The proxy validates this constrained shape, then sends it to OpenAI as
  `safety_identifier`; it is not included in the model prompt.

### Response

```json
{ "reply": "You got squats because squat was your stalest pattern this week..." }
```

A provider safety refusal is a successful, non-retryable outcome with no provider-authored text:

```json
{ "outcome": "safety_refusal" }
```

The Worker discards OpenAI's raw refusal wording. The iOS client maps this outcome to Rep Today's
stable safety message and does not offer to retry the same request.

The Worker accepts text only from a `completed` response or an `incomplete` response whose reason is
`max_output_tokens`. Content-filtered incomplete output becomes `safety_refusal`; a response error or
`failed`, `cancelled`, `queued`, or `in_progress` status becomes an upstream failure at the proxy
boundary, and any accompanying partial provider text is discarded.

On any problem the proxy returns a non-2xx with `{ "error": "<code>" }`
(`method_not_allowed`, `unauthorized`, `payload_too_large`, `invalid_json`, `invalid_context`,
`invalid_message`, `message_too_long`, `invalid_safety_identifier`, `not_configured`,
`upstream_unreachable`, `upstream_error`, `upstream_bad_json`, `empty_reply`). Every non-2xx and
malformed body is handled identically by the client: surface a non-blocking error; never block the app.

The coach persona (`COACH_SYSTEM_PROMPT`) is the talking coach's voice (US-AC02): it covers the
target intents - "why this workout?" (the engine's stalest-pattern reasoning), "how do I do
<movement>?" (safe bodyweight form cues), "is <movement> safe with <complaint>?" / any mention of
pain or injury (general, non-diagnostic guidance + invite the user to flag that area themselves in
the app's injury settings), "I'm bored" (variety is built in), and "how am I doing?" - narrate a
concrete insight from the strength-journey trend now in the context (name what is climbing and what
has gone flat and for how long) - in the app's identity-framed, never-shaming voice. The load-bearing
invariant it enforces first is that the coach only ever **talks**: it never generates, edits, or
prescribes a workout (the deterministic on-device engine owns every session and all safety). US-AC08
hardened the injury half of that boundary: the persona now states the coach **cannot set, clear, or
read** the injury flag - only the user can, only in that screen - and must never say or imply that it
has flagged an area, removed a movement, or changed anything (it speaks in the future tense about what
the user can do), the model-side half of "the coach's language never implies it has already removed
movements". US-AN02 extended the same posture to the strength-journey narration: the persona may offer
to lean the program toward a stalled pattern but must never claim to have already changed anything
(the app applies the preference). Changing the persona is covered by
`test/worker.test.js` ("sends a persona that forbids generating a workout and names the target
intents and voice", "sends a persona that forbids setting or claiming an injury filter", and "sends a
persona that narrates the strength journey and offers only a bounded preference").

## Tests and typecheck

```bash
cd proxy
npm install
npm run typecheck   # tsc --checkJs over the Worker + tests (no build; the proxy ships plain JS)
npm test            # vitest: drives worker.fetch(request, env) in Node, stubbing the one upstream call
```

The test suite (`test/worker.test.js`) proves the boundary without a network or a deployment: a valid
request makes exactly one route-appropriate upstream call and returns a reply or typed safety outcome;
an oversized / invalid / unauthorized request is rejected **before** that call; provider refusal text
never crosses the Worker boundary; and nothing is logged or persisted.

## Abuse protection

Without a gate, **every** route is an **open relay to a billed model API**: anyone
who discovers the URL can drive unbounded, paid model calls (financial abuse / quota exhaustion).
The shared-secret gate runs **once, before routing**, so it protects `/variety-language` and `/coach`
identically. The Worker is stateless (no KV), so it cannot self-rate-limit. Before deploying you
**MUST**:

1. **Set a client shared secret.** `wrangler secret put CLIENT_SHARED_SECRET`, and have the client
   send it. When the secret is set, the Worker rejects any request whose
   `Authorization: Bearer <secret>` header does not match with `401 { "error": "unauthorized" }`
   **before** it calls an upstream provider, so unauthorized traffic never bills. (The secret is compared in
   constant time.) When the env var is unset the route stays open - convenient for local `wrangler
   dev`, but never acceptable in production. Point the client at it by passing `sharedSecret:` to
   `ProxyVarietyLanguageProvider` / `CoachProxyClient` (see the wiring examples below).
2. **Add a Cloudflare rate-limiting / WAF rule** on the routes, since a leaked secret or a
   distributed caller still needs a request-rate ceiling the stateless Worker cannot enforce itself.

## Model

The premium AI Coach is source-pinned to the exact model identifier `gpt-5.6-luna` and calls the
OpenAI Responses API with `reasoning.effort: "none"`, `store: false`, `safety_identifier`, and the
existing 1024-token output ceiling. `store: false` prevents response application-state storage, not
the standard abuse-monitoring retention documented above. It is intentionally not configurable through
`ANTHROPIC_MODEL`, so Variety Language and Coach model selections cannot drift together.

Variety Language remains on `claude-opus-4-8` by default. Override only that route with the
`ANTHROPIC_MODEL` var in `wrangler.toml` when latency or cost matters more than prose quality.

## Deploy

Prerequisites: a Cloudflare account and [Wrangler](https://developers.cloudflare.com/workers/wrangler/).

### Current production Coach status (2026-09-16)

Firstmate's captain-authorized native launch from clean tested commit `a8b8f75`
completed with exit 0, deploying Worker `reptoday-variety-language-proxy` at
`https://coach.reptoday.app/coach`. The helper verified the approved account/active Free
zone, provider/client-gate binding names, routing, no persistence/body logging, and disabled
development/preview URLs. Its missing/wrong/correct-authorization probes passed the
required **401/401/400** contracts without a model call. The successful release disables
the temporary deployment hold; the exact-path boundary and rate protection remain enabled
and verified. The staging `protected` message does not describe the final hold state.

This proves the guarded deployment and gate path, **not live model or shipped-client QA**.
The native result retains neither actual retry count nor serving-edge convergence duration.
Standard installed Wrangler OAuth refresh recovered the unchanged local auth guard before
this attempt; no new interactive login, credential mode/scope/account/plan change or rotation
was needed. The captain selected **stronger runtime authentication**. Both ordinary iOS Coach build
configurations remain empty until the locally prepared App Attest/StoreKit path is migrated and
verified on a genuine device; the operator gate must never be distributed in a shipped binary.
Provider keys remain solely on the Worker. Only `/coach` is exposed at this production hostname;
the separate Variety Language route is not enabled by this deployment.

### Production Coach credential intake on macOS

`tools/prepare-coach-keychain.sh` opens a local macOS secure-input dialog for the captain's
OpenAI API key and saves it directly through Security.framework to the default macOS Keychain.
It also generates a 256-bit client gate if none exists, preserving any existing credential on
subsequent runs. No values are printed or passed through shell arguments, environment, or secret
files. The helper performs no deployment and makes no paid API calls.

Firstmate launches it locally with:

```bash
./tools/prepare-coach-keychain.sh
```

The captain enters the key only in that dialog. `./tools/prepare-coach-keychain.sh --check`
checks metadata and reports readiness without retrieving either credential. The generic-password
service is `com.reptoday.coach.production`; accounts are `openai-api-key` and
`client-shared-secret`. Intake preserves an existing key rather than silently replacing it;
rotation requires a separate coordinated operation. Do not use a Keychain CLI that puts a value
in command arguments or grants every app access.

Secure intake alone is not deployment evidence. The completed operator-only deployment used the
existing items through the dedicated helper, which confirmed the authenticated account, exact
Worker target `reptoday-variety-language-proxy`, and rate-limit/WAF protection before mutation.
Any separately authorized future operator redeployment must repeat those checks. Provider keys
stay solely on the Worker. A client gate embedded in an iOS binary is extractable and only deters
opportunistic abuse; it does not verify premium entitlement. The captain selected the locally
implemented App Attest/StoreKit path for shipped authentication, so the operator gate must never
enter a distributed build. Its production migration and genuine-device QA remain pending.

### Zone-scoped Cloudflare WAF token intake

The existing product zone and public website hostname are `reptoday.app`; the authoritative
repository pointer is `gtm/03-site/DEPLOY.md` (the `reptoday-site` Pages project). This identifies
the product's zone, but does not choose a Coach route or authorize an invented API subdomain.
The captain-approved Coach origin is `https://coach.reptoday.app/coach`. Only that route and
its necessary method handling may be publicly exposed. Install and verify zone rate limiting
before enabling traffic; disable `workers.dev` and preview URLs. The zone-WAF token stays local
in Keychain and must never be uploaded to the Worker.

The captain-authorized zone-WAF path uses a separate API token with **only `Zone WAF Write`**,
restricted to **the specific `reptoday.app` zone**. It needs no account-wide permissions, DNS edit,
or global API key. This permission also permits ruleset inspection; `Zone WAF Read` need not be
added separately. See Cloudflare's official [zone rate-limit permission documentation](https://developers.cloudflare.com/terraform/additional-configurations/rate-limiting-rules/)
and [ruleset inspection permissions](https://developers.cloudflare.com/ruleset-engine/rulesets-api/view/).
Keep the existing authenticated Wrangler credential for Worker deployment; do not replace it with
the narrower WAF-only token.

After creating that scoped token in their own Cloudflare dashboard, the captain enters it only
in the native secure-input dialog Firstmate launches locally:

```bash
./tools/prepare-coach-keychain.sh --cloudflare-waf
```

This saves the token under the existing Keychain service `com.reptoday.coach.production`, account
`cloudflare-zone-waf-token`. It does not read or rotate the OpenAI key or client gate, contact
Cloudflare, or perform production mutations. The `--check-cloudflare-waf` mode checks only item
metadata; existence is not proof of valid scope or installed abuse protection. Existing tokens
are preserved rather than silently replaced. Never put the token in chat, command arguments,
environment, source, logs, or status. Subsequent API operations must retrieve it through the
approved local Keychain mechanism into process memory and suppress credential-bearing output.

The older `tools/check-coach-keychain-access.py` check captures CLI password output, but timed out
waiting for local access. The approved deployment path now uses a dedicated native reader instead.
Never run `security ... -w` directly in a terminal, record the prompts, or grant all applications
access. A metadata-only readiness check does not prove password retrieval is permitted.

### Dedicated production deployment helper (operator launch completed)

`tools/deploy-coach-production.sh` builds the dedicated `tools/coach-production-deploy.swift`
Security.framework reader in ignored `build/coach-production-deploy/`. It can retrieve only the
three existing items above, and has no Keychain creation, replacement or rotation interface.
The captain may authorize the native prompt for this dedicated executable locally; no broad
permission for `/usr/bin/security` is required. Credential values travel only through an anonymous
pipe to the local `tools/coach-production-deploy.mjs` coordinator, never through argv, environment,
temporary secret files, terminal output, Wrangler diagnostics or status. The WAF token is used
only for the confirmed product zone's Rulesets API; only the provider key and gate can be
provisioned as missing secret bindings on the exact approved Worker. Existing remote bindings
are preserved, so this helper is not a rotation tool.

Before any mutation, the coordinator requires exactly one authenticated account and its active
`reptoday.app` zone on the existing Free plan. A changed or unknown plan stops with `rate-plan`.
Free rate rules support Path/Verified Bot, not Host; see Cloudflare's
[rate-limit plan availability](https://developers.cloudflare.com/waf/rate-limiting-rules/#availability).
**The captain explicitly approved a zone-wide rule for the exact `/coach` path on Free.**
`/coach` is therefore reserved across every hostname in the `reptoday.app` zone, including the
apex and website hostnames. All methods at that exact path share the approved limit of 10
requests per 10 seconds per IP and Cloudflare location, followed by a 10-second block. This
reservation must be considered before another zone hostname adds its own `/coach` endpoint.
The deployment hold and path-boundary custom rules remain scoped to `coach.reptoday.app`,
and the Worker is attached only to that hostname. The helper never buys or changes a plan.
The existing Wrangler OAuth must also have at least 20 minutes remaining; missing, expiring or
overridden authentication stops with `auth`. The helper does not refresh or rewrite the shared
authentication store, and rechecks it before Wrangler starts.

The successful operator-only launch used the helper exactly as follows:

```bash
./tools/deploy-coach-production.sh
```

It ran from clean tested commit `a8b8f75` on `fm/reptoday-ai-coach-proxy-live-qa`, with no
credential arguments, and completed the no-model 401/401/400 probes. This invocation is deployment
history, not authorization to run it again; any further production mutation requires separate
review. The native reader never relays arbitrary coordinator stdout/stderr, API responses or
exceptions.

The reviewed flow first enables a Coach-hostname deployment-hold WAF block, appends a
Coach-hostname exact-path boundary and the zone-wide `/coach` IP/location rate rule described
above, and verifies their configuration. It preserves unrelated rules
and refuses skip rules, unexpected logging, occupied rate-rule capacity or conflicting owned
rules. It stages the current source with supported `wrangler deploy`, `workers_dev = false`,
`preview_urls = false`, no routes, no persistence and observability/Logpush disabled. Wrangler
stdout/stderr are discarded; its debug-log destination is an ignored symlink to `/dev/null`.
Only after confirming closed development URLs and safe settings does it provision missing
server bindings. Custom-domain attachment uses the Cloudflare changeset/records API with both
DNS/origin override flags false, avoiding Wrangler's automatic non-interactive conflict override.

The hold is released only after rechecking bindings, settings, route ownership and WAF rules.
Malformed-JSON probes check missing/wrong/correct authorization without a model call, with
final expectations of 401 JSON `unauthorized`, 401 JSON `unauthorized`, and 400 JSON string error.
The missing-authorization stage now observes serving-edge readiness: only the observed completed
403/non-JSON, non-redirected denial may repeat, at most **four attempts** separated by **five
seconds**, within a **45-second total readiness budget** including requests, body reads and waits.
Each request retains its 15-second deadline and 8192-byte response ceiling; the first-stage
request deadline shortens to the remaining readiness budget when necessary. Timeout, transport,
redirect, absent/oversized/interrupted body, unexpected JSON/status/contract failures stop immediately.
The wrong/correct-authorization stages run once each after readiness succeeds and retain their
15-second deadlines: at most six public requests and 75 seconds for the whole gate-probe sequence,
excluding control-plane checks and hold restoration. These are finite operator ceilings, **not a
Cloudflare propagation guarantee**. No user-agent override or valid provider input is sent.

During a launch, this extends the temporary release window while the verified client gate,
exact-path boundary and rate protection remain configured. Any sustained denial, exhausted readiness budget or later
probe failure re-enables and verifies the hold; earlier failures retain it. Other edge policies
can share the denial class, so retries never identify a producer or establish readiness: only the
existing 401 JSON contract permits moving to the later authorization stages. A `gate` failure
now carries one fixed diagnostic line through the same native boundary, after the blocked summary:

| Field | Allowlisted classes |
| --- | --- |
| Probe | `missing-authorization`, `wrong-authorization`, `correct-authorization` |
| Failure | `request`, `timeout`, `body`, `size`, `json`, `redirect`, `status`, `contract` |
| Status | Standard numeric HTTP status, or `none` when unavailable |
| Redirected | `yes`, `no`, `unknown` |
| JSON/error contract | `not-read`, `body-unavailable`, `oversized`, `non-json`, `unauthorized`, `string-error`, `invalid-error` |

`request` means fetch failed without a response; it can include DNS/TLS/connection failure or
a redirect rejected by fetch. It does not prove which occurred. `timeout` classifies named
timeout/abort failures. `redirect` identifies a received response marked redirected. Body/JSON
classes describe only the bounded read and error-field shape, never their contents. The native
reader accepts at most one diagnostic on a failed deployment with code `gate`, rejects arbitrary
or mixed output entirely, and suppresses partial progress. The blocked prefix and exit 78 remain.
Only the missing-authorization stage permits the bounded readiness attempts above. Final
verification order/contracts, per-request maximum deadline, redirect prohibition and body bound remain.

Inspect only safe error codes/classes when blocked; do not dump API bodies or credential-bearing diagnostics. Do not
disable a hold manually to get past a failure. DNS/certificate propagation can cause a bounded
probe failure and requires a reviewed later retry while protection remains in place.

This helper makes **zero paid model calls**. Its successful deployment message still explicitly
says live model QA is pending. Actual non-empty model replies, real-client QA, iOS production
configuration, stronger-authentication migration and genuine-device QA remain separate gates.
The shipped-client choice is settled: the locally implemented App Attest/StoreKit path replaces
the operator gate after reviewed migration.

Offline tests and native compilation (no Keychain access or network):

```bash
./tools/test-coach-production-deploy.sh
```

### Guarded-launch history and read-only diagnosis

The first reviewed launch stopped before mutation with `auth`; Firstmate refreshed the existing
Wrangler OAuth through the browser. A subsequent launch stopped with `rules` after installing
the three protective rules. GET-only diagnosis proved an omitted `requests_to_origin: false`
default; the helper now accepts only that safety-equivalent omission. The field evidence and
regressions are in
[`rate-normalization.md`](../artifacts/reports/coach-production/rate-normalization.md).

The next Firstmate launch passed rate verification and staged the Worker, then stopped with
`settings` before secret provisioning or domain attachment. GET-only inspection on 2026-09-16
confirmed the owned hold, boundary and rate rule enabled; no unrelated rules or route conflicts;
Worker present; provider/client-gate and unexpected secrets absent; domain absent. Logpush is
disabled, tails empty, and development/preview URLs disabled. Cloudflare omitted `observability`
after Wrangler explicitly submitted `enabled: false`. The corrected helper accepts only that
observed omission or literal `enabled: false`, rejecting null, malformed and enabled values.
Evidence and negative regressions are in
[`settings-normalization.md`](../artifacts/reports/coach-production/settings-normalization.md).
Neither normalization diagnosis changed rules, deployed source, provisioned secrets, attached
the domain or called the Worker/model.

A later approved Firstmate retry provisioned the provider/client-gate bindings and attached
the approved custom domain, then stopped with `gate`. Firstmate's subsequent GET-only inspection
confirmed the hold restored, both other safeguards enabled, settings/rate invariants `ok`,
bindings present and domain approved. A separately authorized credential-free observation
confirmed current DNS readiness and validated TLS, with no HTTP request. The original failing
probe stage/response class was discarded. The next guarded launch at `8601cee` retained a
first-probe 403/non-JSON denial. The captain's expanded existing event identifies the owned
deployment hold blocking a Node `POST /coach` during the available attempt window, though no
exact probe timestamp/Ray correlation was retained. This supports the narrow readiness behavior
above; serving-edge convergence remains a hypothesis, not a proven propagation deadline.
Offline regressions compose transitional denial with the actual Worker, verify finite exhaustion
and hold restoration, and reject unrelated retry classes. They do not demonstrate production success.
The subsequent retry initially stopped with `auth`. Standard installed Wrangler `whoami`
refreshed the existing OAuth session: the unchanged helper guard rejected it before the flow,
accepted it afterward, and GET-only account/zone verification succeeded. Firstmate's next
guarded native launch from `a8b8f75` completed exit 0 with the 401/401/400 gate contracts.
Production is deployed and released as described above. Live model/client QA, iOS production
configuration, stronger-authentication migration and genuine-device QA remain pending. The
App Attest/StoreKit implementation is prepared locally but not deployed. The earlier held-state
observations are historical, not the current production state.

Firstmate can launch the dedicated read-only mode locally:

```bash
./tools/deploy-coach-production.sh --inspect
```

### Native live-QA preparation, separate from shipped-client authentication

The reviewed local launch command, owned by Firstmate after handoff, is:

```bash
./tools/validate-coach-live.sh
```

It requires the clean committed Coach task branch, accepts no arguments, and reuses the
dedicated AppKit/Security.framework reader for **only** the existing client-gate item. It never
retrieves the provider key or zone-WAF token, distributes a gate into an app build, changes
production, or prints credentials/prompts/responses/errors. The actual app `CoachProxyClient`
and `CoachContextBundle` are compiled into the macOS QA executable. This is an equivalent
native transport check, not simulator chat-surface QA or a shipped-build configuration.

It sends four invalid-input boundary probes (missing/wrong bearer -> 401 `unauthorized`,
authorized 32769-byte body -> 413 `payload_too_large`, authorized malformed JSON -> 400
`invalid_json`), then at most **two paid model requests**, one per PRD intent: why squats and
pistol-squat form. The contexts are synthetic non-identifying catalog/aggregate summaries;
the random QA safety pseudonym exists only in memory. There is no retry, and any failure stops
before subsequent calls. A local offline transport and oversized-message rejection exercise
the real client's error paths without network. They do not prove the full view-model/UI behavior.

Only the approved HTTPS endpoint is accepted. An ephemeral URLSession with cache, cookies
and credential storage disabled rejects redirects, caps retained response data at **16384 bytes**,
and uses both request and entire-resource deadlines. Invalid-input probes get at most **10 seconds**
each; model requests retain the app's at most **30-second** deadline. A **100-second monotonic
network budget** shrinks later request deadlines and rejects late completion; compilation,
human Keychain authorization and local processing are outside that budget. Apple's
[resource timeout contract](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforresource)
covers the entire transfer, including streamed bodies. No raw response/body/identifier is retained
in an artifact or forwarded through diagnostics.

After all executable checks pass, the exact fixed output is:

```text
qa: missing-authorization pass
qa: wrong-authorization pass
qa: oversized pass
qa: malformed pass
qa: offline pass
qa: local-limit pass
qa: why-squats non-empty lexical-context-signals-present
qa: pistol-form non-empty lexical-context-signals-present
qa: semantic-context-form-and-no-workout-fabrication unverified
validated: CoachProxyClient live model path returned; shipped client authentication pending
```

Success validates non-empty actual client replies and lexical smoke signals from the supplied
contexts. **It cannot establish full personalization, safe form or absence of fabricated/altered
workouts.** A fabricated-plan counterexample deliberately passes the lexical predicate in the
offline suite, which verifies that the limitation remains in output. Replies stay only in process
memory; semantic review and simulator/on-device premium/chat/offline QA remain separate gates.
A failure returns exit 78 with only an allowlisted stage/failure summary, and no partial success
or arbitrary returned output is printed. This helper makes no on-device workout/policy writes.

Preparation/compilation and local doubles are not live model evidence. No live launch has yet
been recorded. Offline checks intercept every transport request and access no Keychain:

```bash
./tools/test-coach-live-qa.sh
```

This mode retrieves only the existing zone-WAF Keychain item and uses the existing Wrangler
OAuth in memory. Its transport refuses every non-GET request, including the custom-domain
changeset preview. It does not invoke Wrangler, retrieve the model key or gate, refresh auth,
change rules, or call the Worker. It emits only allowlisted states for owned rules, unrelated
rules/capacity, phase/invariant classes, Worker/binding presence and domain/route ownership.
For the owned rate rule it also reports fixed field-match/default classes and the first
comparison divergence. For a present Worker it reports fixed classes for binding policy/names,
observability, Logpush, tails and development/preview URLs, plus the settings invariant.
No field values or expressions are returned.
It never prints ruleset bodies, account/zone/rule identifiers, tokens or arbitrary diagnostics.
If the recompiled dedicated executable needs native Keychain access, the captain authorizes its
local prompt; never grant broad CLI access or supply the token in a shell command.

The original inspector triggered synchronous Security.framework retrieval from a Foundation-only
process on the main thread. Firstmate observed a wait of over four minutes with no usable prompt,
then interrupted it before the coordinator started. Missing foreground AppKit presentation and
an unavailable UI event loop were the presentation hypotheses; the later successful native
inspection resolved the local retrieval uncertainty without changing credentials or ACLs. Apple's
[Keychain retrieval guidance](https://developer.apple.com/documentation/security/secitemcopymatching%28_%3A_%3A%29)
recommends running the blocking API away from the main thread.

The dedicated reader now activates an accessory AppKit application and shows an informational
Keychain-access panel while delegating the unchanged Security query to a background queue.
Its modal event loop stays responsive; the panel has only Cancel and no credential input.
Cancellation or retrieval failure stops before the coordinator. No ACL, LAContext policy,
credential, intake flow or Cloudflare operation changed. The native non-secret counterfactual
rejects the direct main-thread call, then confirms a visible owner window and serviced main-queue
callback through the presentation wrapper. These offline tests establish the local presentation
mechanism. Firstmate subsequently confirmed that the captain's native Allow let the GET-only
inspector finish. The refined agent GET-only inspection also finished through the same dedicated
reader. Neither inspection retrieved the provider key or gate, mutated production or called the model.

The initial agent inspection attempt waited at native retrieval and was stopped before the
local coordinator started. It produced no Cloudflare observations; the successful later
inspections above supersede that uncertainty. The coordinator and native tests/compile establish
the corrected boundary, including both observed server normalizations.
The earlier 25-test fixture assumed an empty phase was either absent or contained
an explicit `rules: []` array, and modeled server rule responses by echoing submitted fields.
Inspection distinguishes sparse arrays, phase/kind mismatches, skip/logging conflicts, owned
semantics and occupied rate capacity before choosing a fix. The fixed `rules` deployment code
and suppression of partial progress on error mask the exact failing guard and stage; neither
is evidence that the Worker or its bindings were created.

### Wrangler flow

```bash
cd proxy
npm install

# Set the API key as a secret (never committed):
wrangler secret put ANTHROPIC_API_KEY
wrangler secret put OPENAI_API_KEY

# Local run:
cp .dev.vars.example .dev.vars   # put your key in .dev.vars
npm run dev

# Deploy:
npm run deploy
```

Then point the client at the deployed route (`https://<worker-subdomain>/variety-language`).

## Client wiring boundaries

`VarietyLanguageResolver.provider` is `nil` in the MVP, so every note is template-sourced.
To enable the LLM upgrade once this proxy is deployed:

```swift
let provider = ProxyVarietyLanguageProvider(
    endpoint: URL(string: "https://<worker-subdomain>/variety-language")!,
    sharedSecret: "<CLIENT_SHARED_SECRET>"  // must match the Worker's abuse gate
)
let resolver = VarietyLanguageResolver(
    provider: provider,
    isOnline: { /* network reachability */ }
)
```

The resolver still attempts the LLM at most once, and only while the user is cold-start-active and
online; on any failure it falls back to the template.
See `ios/RepToday/RepToday/Services/Language/ProxyVarietyLanguageProvider.swift` and
`VarietyLanguageResolver.swift`.

An explicit DEBUG non-production Coach client can use the legacy shared-secret initializer:

```swift
let coach = CoachProxyClient(
    endpoint: URL(string: "https://<worker-subdomain>/coach")!,
    sharedSecret: "<CLIENT_SHARED_SECRET>",  // must match the Worker's abuse gate
    safetyIdentifier: appState.coachSafetyIdentifier
)
let bundle = CoachContextBundle.make(
    phase: user.phase,
    requestedMinutes: requestedMinutes,
    chainPositions: analytics.chainPositions,      // ProgressAnalytics.from(...).chainPositions
    consistencyTrend: ConsistencyTrend.trend(...),
    recentLogs: recentLogs
)
let reply = try await coach.reply(to: userMessage, context: bundle)
```

`CoachProxyClient` is bounded (per-request timeout) and throws on any failure, so the coach never
blocks the free core loop. Production uses `appState.coachSafetyIdentifierProvider` through
`ServiceContainer.live` and accepts only the exact `https://coach.reptoday.app/coach` origin with
`app-attest-storekit-v1` and an empty binary secret; it constructs the App Attest/StoreKit transport,
never this shared-secret example. Both ordinary Debug and Release origins/secrets remain empty until
reviewed migration and genuine-device QA. The deployed operator bearer remains confined to the
separate native QA path. An account deletion updates the already-built client in the same process.
The bundle remains the single audited definition of training context - see
`ios/RepToday/RepToday/Services/Coach/CoachContextBundle.swift` and `CoachProxyClient.swift`.

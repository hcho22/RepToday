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

Secure intake is a prerequisite, not deployment evidence. Before provisioning these credentials
through the dedicated deployment helper, confirm the authenticated account and the explicit Worker target
`reptoday-variety-language-proxy`, and establish the rate-limit/WAF protection described above.
Keep provider keys solely on the Worker. A client gate embedded in an iOS binary is extractable
and only deters opportunistic abuse; it does not verify premium entitlement. Decide that production
security boundary explicitly before injecting the gate through a private build configuration.

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

### Dedicated production deployment helper (awaiting reviewed local launch)

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

After review, the exact local Firstmate launch is:

```bash
./tools/deploy-coach-production.sh
```

Run it in this clean, committed task worktree on `fm/reptoday-ai-coach-proxy-live-qa`. Supply no
credentials as arguments. Production mutation awaits this reviewed local launch.
The native reader never relays arbitrary coordinator stdout/stderr, API responses or exceptions.

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
Three bounded malformed-JSON probes check missing/wrong/correct authorization without a model
call; any probe failure re-enables the hold. Earlier failures retain the hold. Inspect only safe
error codes when blocked; do not dump API bodies or credential-bearing diagnostics. Do not
disable a hold manually to get past a failure. DNS/certificate propagation can cause a bounded
probe failure and requires a reviewed later retry while protection remains in place.

This helper makes **zero paid model calls**. Its successful deployment message still explicitly
says live model QA is pending. Actual non-empty model replies, real-client QA, iOS production
configuration, and the explicit extractable-client-gate security choice remain separate gates.

Offline tests and native compilation (no Keychain access or network):

```bash
./tools/test-coach-production-deploy.sh
```

### Read-only diagnosis after a stopped launch

The first reviewed launch stopped before mutation with `auth`; Firstmate refreshed the existing
Wrangler OAuth through the browser. The next reviewed launch stopped with the fixed code
`rules`. **Treat production state as unknown until inspection succeeds.** A partial launch may
have enabled the deployment hold or added the path boundary. Do not retry deployment, disable
a hold, provision bindings, attach a domain or call a model while diagnosing this failure.

Firstmate can launch the dedicated read-only mode locally:

```bash
./tools/deploy-coach-production.sh --inspect
```

This mode retrieves only the existing zone-WAF Keychain item and uses the existing Wrangler
OAuth in memory. Its transport refuses every non-GET request, including the custom-domain
changeset preview. It does not invoke Wrangler, retrieve the model key or gate, refresh auth,
change rules, or call the Worker. It emits only allowlisted states for owned rules, unrelated
rules/capacity, phase/invariant classes, Worker/binding presence and domain/route ownership.
It never prints ruleset bodies, account/zone/rule identifiers, tokens or arbitrary diagnostics.
If the recompiled dedicated executable needs native Keychain access, the captain authorizes its
local prompt; never grant broad CLI access or supply the token in a shell command.

The original inspector triggered synchronous Security.framework retrieval from a Foundation-only
process on the main thread. Firstmate observed a wait of over four minutes with no usable prompt,
then interrupted it before the coordinator started. Missing foreground AppKit presentation and
an unavailable UI event loop are the presentation hypotheses; ACL/session restrictions remain
an alternative until a real local retry succeeds. Apple's
[Keychain retrieval guidance](https://developer.apple.com/documentation/security/secitemcopymatching%28_%3A_%3A%29)
recommends running the blocking API away from the main thread.

The dedicated reader now activates an accessory AppKit application and shows an informational
Keychain-access panel while delegating the unchanged Security query to a background queue.
Its modal event loop stays responsive; the panel has only Cancel and no credential input.
Cancellation or retrieval failure stops before the coordinator. No ACL, LAContext policy,
credential, intake flow or Cloudflare operation changed. The native non-secret counterfactual
rejects the direct main-thread call, then confirms a visible owner window and serviced main-queue
callback through the presentation wrapper. This proves the local presentation mechanism, not
system-prompt visibility, real Keychain access or any Cloudflare observation. Retry only the
GET-only command above locally, keeping deployment disabled during diagnosis.

The initial agent inspection attempt waited at native retrieval and was stopped before the
local coordinator started. It produced no Cloudflare observations. The 31 offline tests and
native tests establish the inspection boundary, not the live ruleset state or the cause of the
`rules` stop. The earlier 25-test fixture assumed an empty phase was either absent or contained
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

## Wiring the client (deferred - not shipped in the MVP)

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

The coach client is analogous (US-AC01 ships the transport; the chat surface that drives it is
US-AC02):

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
`ServiceContainer.live`, so an account deletion updates the already-built client in the same process.
The bundle remains the single audited definition of training context - see
`ios/RepToday/RepToday/Services/Coach/CoachContextBundle.swift` and `CoachProxyClient.swift`.

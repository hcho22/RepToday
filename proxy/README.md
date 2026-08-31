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
returns the reply. It throws on any non-2xx, timeout, or malformed body so the (US-AC02) chat surface
degrades to a clear, non-blocking state - the free core loop never depends on or waits for it.

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
request makes exactly one route-appropriate upstream call and returns a reply; an oversized / invalid /
unauthorized request is rejected **before** that call; and nothing is logged (the Worker never touches
the console) or persisted (there are no storage bindings).

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

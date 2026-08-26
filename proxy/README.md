# Rep Today LLM Proxy

A thin, stateless, key-holding proxy for Rep Today's Phase 2 LLM slices. It exists so every Claude
call runs **without shipping an API key in the app**, and so the app never has to trust it: each
client enforces its own short timeout and degrades cleanly on any failure, timeout, or absence of
this proxy.

Two routes live here, both stateless and storing nothing:

- **`POST /variety-language`** (US-N05) - the deferred day-one Variety Language line. Not wired in
  the shipping MVP; the client (`ProxyVarietyLanguageProvider`) falls back to the deterministic
  on-device template on any failure.
- **`POST /coach`** (US-AC01) - the premium AI coach transport. A derived, non-identifying context
  bundle + the user's message in, a Claude reply out. The chat surface that drives it is US-AC02;
  US-AC01 ships the transport only.

## What it does

- Holds the Anthropic API key (a Wrangler secret) and proxies **exactly one** Claude call per
  request, on either route.
- **Stores no user data at rest, on either route.** Nothing is persisted: no KV, no D1, no cache, no
  scheduler, and **no request/response body logging**. History is read transiently from the request
  and discarded when the response is sent. The coach's conversation memory, if any, lives on the
  device in the client - never here.
- Carries **no identity on the wire**: no account, no `installId`, no IDFA, no Apple ID, no email, no
  name, no profile. `/variety-language` carries only two pillar values; `/coach` carries only the
  app-audited context bundle (summarized catalog/aggregate signals) plus the free-text the user
  typed.
- Bounds every upstream call with `AbortSignal.timeout` and caps the request body at **32 KiB**
  (checked before parsing, so an oversized payload never reaches JSON parsing or a Claude call).

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
  "message": "why did I get squats today?"
}
```

- `context` (required) - the **derived context bundle**: the single, auditable, non-identifying
  summary the app is allowed to send (see `ios/RepToday/RepToday/Services/Coach/CoachContextBundle.swift`,
  which defines this exact shape). It is summarized catalog/aggregate data - phase, per-pattern chain
  positions, recent movement patterns, a coarse consistency signal, requested minutes - and contains
  **no raw `WorkoutLog` history and no identity field**. The proxy validates it is present and
  object-shaped but does not otherwise constrain it (the app owns the definition).
- `message` (required) - the user's free-text question. Non-empty and at most **2000 characters**
  (the iOS client caps the same value; the proxy re-checks as defense in depth).

### Response

```json
{ "reply": "You got squats because squat was your stalest pattern this week..." }
```

On any problem the proxy returns a non-2xx with `{ "error": "<code>" }`
(`method_not_allowed`, `unauthorized`, `payload_too_large`, `invalid_json`, `invalid_context`,
`invalid_message`, `message_too_long`, `not_configured`, `upstream_unreachable`, `upstream_error`,
`upstream_bad_json`, `empty_reply`). Every non-2xx and malformed body is handled identically by the
client: surface a non-blocking error; never block the app.

The coach persona is intentionally minimal here (transport only). US-AC02 refines the voice and the
target intents; the invariant this route already enforces is that the coach only ever **talks** -
it never generates, edits, or prescribes a workout (the deterministic on-device engine owns every
session and all safety).

## Tests and typecheck

```bash
cd proxy
npm install
npm run typecheck   # tsc --checkJs over the Worker + tests (no build; the proxy ships plain JS)
npm test            # vitest: drives worker.fetch(request, env) in Node, stubbing the one upstream call
```

The test suite (`test/worker.test.js`) proves the boundary without a network or a deployment: a valid
request makes exactly one upstream Anthropic call and returns a reply; an oversized / invalid /
unauthorized request is rejected **before** that call; and nothing is logged (the Worker never touches
the console) or persisted (there are no storage bindings).

## Abuse protection

Without a gate, **every** route is an **open relay to the billed Anthropic Messages API**: anyone
who discovers the URL can drive unbounded, paid Claude calls (financial abuse / quota exhaustion).
The shared-secret gate runs **once, before routing**, so it protects `/variety-language` and `/coach`
identically. The Worker is stateless (no KV), so it cannot self-rate-limit. Before deploying you
**MUST**:

1. **Set a client shared secret.** `wrangler secret put CLIENT_SHARED_SECRET`, and have the client
   send it. When the secret is set, the Worker rejects any request whose
   `Authorization: Bearer <secret>` header does not match with `401 { "error": "unauthorized" }`
   **before** it calls Anthropic, so unauthorized traffic never bills. (The secret is compared in
   constant time.) When the env var is unset the route stays open - convenient for local `wrangler
   dev`, but never acceptable in production. Point the client at it by passing `sharedSecret:` to
   `ProxyVarietyLanguageProvider` / `CoachProxyClient` (see the wiring examples below).
2. **Add a Cloudflare rate-limiting / WAF rule** on the routes, since a leaked secret or a
   distributed caller still needs a request-rate ceiling the stateless Worker cannot enforce itself.

## Model

Defaults to `claude-opus-4-8` (Anthropic's most capable model).
Override with the `ANTHROPIC_MODEL` var in `wrangler.toml` - e.g. a Haiku tier - when latency or cost
matter more than prose quality. The one model var applies to both routes.
Extended thinking is intentionally not requested (fast generation on both routes).

## Deploy

Prerequisites: a Cloudflare account and [Wrangler](https://developers.cloudflare.com/workers/wrangler/).

```bash
cd proxy
npm install

# Set the API key as a secret (never committed):
wrangler secret put ANTHROPIC_API_KEY

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
    sharedSecret: "<CLIENT_SHARED_SECRET>"  // must match the Worker's abuse gate
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
blocks the free core loop. The bundle is the single audited definition of what leaves the device -
see `ios/RepToday/RepToday/Services/Coach/CoachContextBundle.swift` and `CoachProxyClient.swift`.

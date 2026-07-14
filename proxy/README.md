# FitSnack Variety Language Proxy (US-N05)

A thin, stateless, key-holding proxy for the deferred Phase 2 **Variety Language** LLM slice
(US-G03).
It exists so the single day-one Claude call can run **without shipping an API key in the app**, and
so the app never has to trust it: the client (`ProxyVarietyLanguageProvider`) enforces its own short
timeout and falls back to the deterministic on-device template on any failure, timeout, or absence
of this proxy.

This proxy is **not part of the MVP** - no provider is wired in the shipping app.
It is the infrastructure the Variety Language seam was built against, ready to deploy and wire when
the Phase 2 language features land.

## What it does

- Holds the Anthropic API key (a Wrangler secret) and proxies **exactly one** Claude call per
  Variety Language request.
- Turns the engine's genuine day-to-day contrast into one short line
  ("Today leans into mobility - yesterday was strength").
- **Stores no user logs at rest.**
  The request carries only two pillar values (today, and yesterday when it differs) plus their
  labels - never user identity, profile, `why`, or history.
  Nothing is persisted: no KV, no D1, no cache, no scheduler, no request-body logging.

## Wire contract

The client calls this proxy **only** for the Variety Language slice, and always falls back to the
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
(`method_not_allowed`, `invalid_json`, `invalid_today`, `invalid_yesterday`, `not_configured`,
`upstream_unreachable`, `upstream_error`, `upstream_bad_json`, `empty_line`).
The client treats **every** non-2xx and every malformed body identically: discard and fall back to
the template. A failing or absent proxy never blocks the app.

## Model

Defaults to `claude-opus-4-8` (Anthropic's most capable model).
Override with the `ANTHROPIC_MODEL` var in `wrangler.toml` - e.g. a Haiku tier - when latency or
cost on this best-effort, felt-nicety line matter more than prose quality.
Extended thinking is intentionally not requested (fast single-line generation).

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
    endpoint: URL(string: "https://<worker-subdomain>/variety-language")!
)
let resolver = VarietyLanguageResolver(
    provider: provider,
    isOnline: { /* network reachability */ }
)
```

The resolver still attempts the LLM at most once, and only while the user is cold-start-active and
online; on any failure it falls back to the template.
See `ios/FitSnack/FitSnack/Services/Language/ProxyVarietyLanguageProvider.swift` and
`VarietyLanguageResolver.swift`.

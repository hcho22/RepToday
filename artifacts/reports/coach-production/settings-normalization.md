# Coach post-stage settings diagnosis — 2026-09-16

Production remains held and unreachable. Firstmate's guarded launch staged Worker
`reptoday-variety-language-proxy`, then stopped with `settings` before uploading either
provider/client secret or attaching the approved origin `https://coach.reptoday.app/coach`.
No live model reply has returned. This report establishes diagnosis and local validation;
completed deployment, live model/client QA and no-mistakes PR readiness remain separate gates.

## Fixed-class GET evidence

The dedicated native inspector completed twice through the existing Security.framework
boundary. Inspection retrieved only the existing zone-WAF Keychain item and existing Wrangler
OAuth into memory. The transport permits exclusively GET requests. It did not retrieve the
provider key/client gate, invoke Wrangler, change production, attach a hostname or call the
Worker/model. No raw API bodies, identifiers, credentials, prompts or replies were recorded.

| Surface | Observed class |
| --- | --- |
| Account / zone | Single approved account; active approved Free zone |
| Custom / rate invariants | Both `ok`; no unrelated rules; capacity available |
| Owned safeguards | Hold, path boundary and rate rule all enabled |
| Worker | Present |
| Settings bindings | Array valid; policy matches; names unique |
| Observability | Absent, not null or explicitly enabled |
| Logpush / tails | Disabled / empty |
| workers.dev / preview URLs | Both disabled |
| Provider / client-gate / unexpected secrets | All absent |
| Domain / legacy routes | Absent / clear |
| Settings invariant | Before correction: `conflict`; after correction: `ok` |

The only failing settings comparison was the omitted `observability` object. Every other
settings field and both development-URL flags matched the existing guards. The rate default
correction was also confirmed live: `requests-to-origin` remains `absent-default`, with no
rate comparison divergence.

## Trigger, masking condition and disconfirmation

The staging configuration explicitly sets `observability: { enabled: false }`. Cloudflare's
subsequent settings GET omits the object. The old guard required literal
`settings.observability?.enabled === false`, so omission stopped immediately after staging,
before secret provisioning, development-URL verification or domain attachment. The fixed
`settings` error and suppression of partial success output concealed the field until inspection.

The original fixture kept the submitted disabled object, masking this server normalization.
The preserved edits add fixed-class inspection only; they did not change the guard. An offline
counterfactual that deletes only observability after fake staging reproduced `settings` at
that exact post-stage guard before the correction.

Alternative explanations were null/malformed observability, an enabled logger/tail, a persistence
binding or an open development URL. The live fixed classes disconfirm those explanations.
These alternatives remain explicit negative regressions, rather than tolerated normalizations.

Cloudflare's [settings API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/settings/methods/get/)
defines observability as an optional object and its `enabled` field as a boolean. Installed
Wrangler 3.114.17's regular deployment path explicitly sends the configured disabled object;
its documented source comment also treats a disable patch as removing observability.
The [Workers Logs instructions](https://developers.cloudflare.com/workers/observability/logs/workers-logs/)
require enabled observability to write Workers Logs. The safety-equivalent omission conclusion
comes from this explicit-disable deployment path plus the live GET, not a general assumption
about new Worker defaults. Staging continues to submit `enabled: false` explicitly.

## Minimal correction and validation

The guard accepts only absent observability or literal `enabled: false`. It still rejects null,
empty/malformed objects, arrays, primitive substitutes and enabled/non-boolean values. It neither
writes nor normalizes the API response. Binding policy/uniqueness, persistence, Logpush, tails,
development/preview URLs, route ownership, both required secrets and protection remain unchanged.
Inspection retains the raw fixed class `absent` while reporting the corrected invariant `ok`.
The native boundary rejects arbitrary settings field output just as it rejects other raw output.

Validation completed:

- The omission-only regression failed before the correction with `settings`, then passed.
- `./tools/test-coach-production-deploy.sh`: all 40 coordinator tests, native non-secret
  presentation/boundary tests and production Swift compilation with warnings as errors passed.
- Reconstructed omission passes fake protected staging and retry without replacing existing
  secrets or changing logging/development-URL settings. Negative cases retain the hold and
  perform no secret/domain PUT or authorization probe.
- GET-only post-correction inspection reports settings `ok` with the same safely held state.
- `cd proxy && npm test`: 30 Worker tests passed; `npm run typecheck` passed.

No iOS configuration/client behavior changed in this correction. Production model calls,
the two PRD real-client prompts, offline/error real-client QA, private iOS authentication
configuration, iOS validation/build and the shipped gate's security decision remain pending.
No deployment retry or paid call was performed during this diagnosis.

## Next local Firstmate action

Review the committed correction. The exact guarded retry from this clean isolated task branch,
when Firstmate authorizes that next launch, is:

```bash
./tools/deploy-coach-production.sh
```

Supply no credentials as arguments. The helper must re-confirm account, zone, targets and
safeguards; keep the hold through staging/secrets/domain verification; and make only malformed
JSON authorization probes. A successful helper return still means live model QA is pending.

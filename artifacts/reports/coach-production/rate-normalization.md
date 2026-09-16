# Coach production rate-rule diagnosis — 2026-09-16

This report records the earlier rate-rule stop, which left only the three protective rules.
A later Firstmate launch staged the Worker and stopped before secrets/domain on `settings`;
the hold remains enabled and no live model reply has returned. Current state and the later
diagnosis are in [settings-normalization.md](settings-normalization.md). These reports are
diagnostic evidence, not completed production deployment or code/PR readiness evidence.

## GET-only observations

Firstmate's local inspection completed after native Allow. The refined field inspection also
completed through the dedicated reader. Both used the existing zone-WAF item and Wrangler
OAuth, without retrieving the provider key or client gate. The transport allowed only GETs.
No rule, Worker, binding or domain changed, and no Worker/model call occurred during diagnosis.

Only these non-secret deployment targets are recorded: Worker `reptoday-variety-language-proxy`
and approved origin `https://coach.reptoday.app/coach`.

| Surface | Fixed observation |
| --- | --- |
| Authenticated account / zone | Single approved account; active approved Free zone |
| Custom rules | Phase matches; invariant ok; owned hold and boundary enabled |
| Rate rule | Phase matches; owned rule enabled; old invariant `owned-semantics` |
| Unrelated rules / capacity | No unrelated custom or rate rules; capacity available |
| Worker / secret bindings | Worker absent; provider, client-gate and unexpected secret bindings absent |
| Routing | Domain absent; legacy routes clear |

The rate-rule field classes were:

- Ref, action, expression, enabled, characteristics, period, request threshold and mitigation:
  all match the approved configuration.
- Logging and action parameters: absent.
- `requests_to_origin` and counting expression: absent defaults.
- Score fields: absent. Extra rule/rate fields: none.
- First comparison divergence: `requests-to-origin`.

No API response body, identifier, credential, prompt or model response was saved in this report
or the fixtures. The fixtures reconstruct only the known public configuration and omitted field,
using explicitly non-secret identity/credential doubles.

## Trigger, masking condition and symptom

The trigger was Cloudflare returning the optional `requests_to_origin` field as absent after
the helper submitted `false`. The old guard required literal equality, so the first rate-rule
GET after creation failed before Worker staging.

The echo fixture preserved every submitted field and therefore masked this normalization.
The single safe `rules` failure code also concealed the failing comparison and partial stage
until field-class inspection was available. The visible symptom was a stopped launch with
three enabled safeguards, without a Worker, bindings or domain.

The leading explanation was an omitted optional default. Alternative explanations were empty
action parameters or changed core rate semantics. The live observations disconfirm both:
action parameters are absent and every core field matches. A changed core field would instead
require a conflict escalation, not a tolerant comparison. Phase, logging and occupied capacity
were also ruled out. Characteristic ordering was already ignored by the guard.

Cloudflare documents `requests_to_origin` as optional. When origin-only counting is unavailable
on a plan, counting also applies to cached assets by default; explicit `true` restricts counting
to origin requests. The observed omission on the confirmed Free plan therefore retains the
approved all-requests behavior. See the
[Cloudflare parameter reference](https://developers.cloudflare.com/waf/rate-limiting-rules/parameters/).

## Small counterfactual and correction

Two offline regressions failed before the correction:

1. An otherwise matching reconstructed rate entrypoint with only `requests_to_origin` omitted
   produced `owned-semantics` instead of `ok`.
2. A fake Cloudflare creation/GET response that omitted only that field stopped with `rules`
   at the post-create guard, before the fake Worker stage.

The correction accepts `undefined` or literal `false` only when the expected field is `false`.
It does not normalize or write the live object and does not relax any other comparison.
Inspection uses the same accepted-default interpretation when reporting the first divergence.
No tolerance was added for empty action parameters, altered expressions/actions, changed
thresholds, disabled rules, counting expressions or origin-only counting.

Both regressions now pass. The coordinator fake completes staging and verification, and a
protected rerun preserves the rate rule without rewriting it. Separate negative cases reject
explicit `true`, null, numeric/string substitutes, changed core fields, logging and action
parameters. The existing tests still cover protection before staging, binding destinations,
route conflicts, persistence/logging restrictions, release failure and re-closing on probe failure.

Validation: `./tools/test-coach-production-deploy.sh` passed all 34 Node coordinator tests,
native non-secret boundary/presentation tests and Swift compilation with warnings as errors.
These checks use no network or Keychain. Later GET-only inspection confirmed the corrected
production rate invariant `ok`; the subsequent guarded launch also passed rate verification
before stopping on settings, as recorded in the report linked above.

## Next authorized local boundary

Firstmate must review the committed correction and perform the dedicated local launch from
the clean isolated task worktree, without credential arguments:

```bash
./tools/deploy-coach-production.sh
```

The helper must re-confirm account, zone, targets and all safeguards before mutation. The
existing hold must remain enabled through staging, binding verification and domain attachment.
The helper's final authorization probes use malformed JSON and make no model calls.
A successful launch still leaves real model QA, real-client QA, iOS production configuration
and the shipped client-gate security choice pending. No end-to-end success is claimed here.

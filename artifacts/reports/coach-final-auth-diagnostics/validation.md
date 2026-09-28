# Final Coach auth diagnostic candidate: local evidence

2026-09-28. **Code-only preparation; the live Coach defect remains unresolved.**
Implementation under test: `2a93c547382441c4ce63dfae2f6700601e44365c`, based on
`b333997d369fdbda470e66e2de27e502b3158b3e`. The subsequent evidence commit changes this report only.
The selected delivery owner is no-mistakes, without automatic gate approval; its review and
CI outcome must be recorded separately. Scenario linkage below is reviewable evidence, not
machine-enforced Firstmate evidence import. No additional manual review pipeline was added.

## Accepted contract and impact

Prepare a final-request server discriminator and matching bounded capture/restoration support
so a later authorized one-message observation can identify the rejecting authentication guard.
Keep the new flag absent/default-off, emit only fixed event/stage/reason labels on final
unauthorized failures, and preserve independent challenge diagnostics. Preserve all security
predicates, public responses, deadlines, nonce/counter/state, namespace/secrets and dispatch.
Preserve existing native/operational guards. Restore both original active-version traffic and
Worker latest settings; partial, timeout or ambiguous results never count as completion.

Risk is **high**: auth code and tooling affect all Coach callers and shared security state.
This candidate adds diagnostic callbacks beside existing guards, explicit operator flag support,
GET-only exact-target/candidate/baseline verification, a bounded transient filter, two deliberately
invalid coverage probes, tests and guidance. It adds no functional auth fix or automatic recovery
controller. Existing stage/hold/release owners remain responsible for future mutations.
No dependency version, security storage schema, auth policy or app UI/client source was changed.
No active checkout or Xcode scheme was read or modified during implementation.

The captain-authorized outcome is preparation for review. Production, merge, model/device calls,
credential access and live observation remain outside this task. The specific future human
judgment is approval of exact candidate/baseline/target, possible all-caller hold downtime,
native credential attendance, two invalid coverage probes, one send that may call a model,
120-second maximum exposure/capture, and the guarded restoration sequence.

## Environment and executions

Observed 2026-09-28, final focused checks through 18:45:52 UTC:
macOS 26.6.2, Node 20.19.5, Vitest 2.1.9, Wrangler 3.114.17,
workerd 1.20250718.0, Apple server SDK 3.1.0, Swift 6.3.2, Python 3.7.9.
Existing lockfile unchanged. Actual production compatibility date remains 2026-01-01;
local workerd uses 2025-07-18 and cannot prove newer runtime behavior.

`bash tools/test-coach-final-diagnostics.sh` passed in the authorized tmux continuation.
After the final read-only dispatcher guard and process-stream tests were added, their affected
operator/filter suites were rerun and passed. No unrelated suite was rerun for documentation.
The same complete gate is wired into the existing PR CI as the Coach job.

| Check | Observed result | Scope |
|---|---|---|
| Proxy typecheck and full Vitest suite | PASS: 349 tests in 9 files | Includes 118 new final diagnostic cases and existing auth/challenge/Apple tests |
| workerd/SQLite gate | PASS | Real runtime crypto and atomic state; both DO and Worker diagnostic producers; all outbound calls intercepted |
| Operator coordinator suite | PASS: 85 tests | Fixed flags, default-off config, native protocol inputs, target/version/settings/security checks, rejected restoration states |
| Native migration/preflight suite | PASS | Swift doubles and real pipes; compile production entry only; no Security reader or native consent execution |
| Existing preflight supervisor tests | PASS: 9 tests | Cancellation/deadlines/failure index and rejected CLI behavior |
| Capture filter/process suite | PASS: 21 tests | Synthetic metadata/rows, real local child pipes, cancellation, timeout, bounded cleanup and confidentiality |
| Tail adapter `--self-check` | PASS | Installed-source SHA256 and transformed syntax only; no subscription |
| Shell/Node syntax and Git whitespace | PASS | Selected tooling and committed diff |

## Requirement-to-evidence assessment

| Requirement/scenario | Expected and observed local behavior | Status / evidence | Limitations |
|---|---|---|---|
| Final Worker/DO discrimination | Separate envelope, token, pending nonce, assertion, Premium labels without changing denial | PASS: `proxy/test/coach-final-diagnostics.test.js`, `proxy/test/workerd-auth.mjs` | Generated EC keys, synthetic records and trusted Apple doubles; does not identify live failing guard |
| Disabled/absent/invalid gate | No new output and same HTTP/cache/state/counter effects | PASS: six-value flag matrix over 18 scenarios; full state equality for non-consuming denials | Deployment-version environment behavior is not simulated by mutating the injected env |
| Enabled successful path | No auth diagnostic; local accepted auth reaches downstream `400 invalid_context` | PASS: admission control in Node/workerd | No prompt/model invocation or genuine Apple proof; this is not a Coach answer |
| Enable then disable | Next denial silent; in-flight DO read/Premium denial silent when flag is disabled before emission | PASS: in-flight tests plus operator enabled-to-flag-free stage test | Already-running old deployed versions retain their own env; a config write is not a global immediate cutoff |
| Deadline and observer failure | Original 503/401 outcome preserved; late callback/logger exception cannot change it | PASS: callback/logger and delayed Premium tests | Synthetic scheduling; no live clock-skew inference |
| Confidentiality | Only exact three fields and closed label pairs survive; all private sentinels excluded | PASS: auth logger tests, filter negative tests, native complete-transcript validation | Raw real-time metadata exists transiently at the provider/client transport; filter cannot remove provider-internal data |
| Existing challenge/delete behavior | New flag independent; known challenge/enroll/delete and unavailable errors remain silent | PASS: focused tests and existing suites | No changed public errors or new bypass |
| Runtime DO coverage | DO and Worker rows emitted in workerd; malformed coverage enrollment writes no record | PASS: workerd/SQLite and Node canary controls | Does not prove Cloudflare production tail envelopes include matching version/entrypoint metadata |
| No circular readiness wait | Attachment alone not ready; empty-log Worker and DO coverage events can establish readiness before any device send | PASS: parser and real-pipe tests; two invalid probe request shapes exercised locally | Future operator must require probe success AND matching-version coverage; cannot infer device outcome from probes |
| Bounded transient capture | 120s including readiness, 200 events, 20 rows, input framing/total limits; no raw output | PASS: stream limits, real child timeout/failure/cancel tests | No live tail; local exit always reports remote closure unverified |
| Exact candidate/base targets | Wrong owner/source/version/namespace/account or split traffic fails before mutation | PASS: coordinator fixture matrix and read-only dispatcher test | Review must freeze fresh private manifests; identifiers and source markers are assertions requiring operational provenance |
| Original version + latest settings | Original100% version with diagnostic latest settings fails; matching original settings then passes | PASS: historical mismatch reproduced as synthetic API fixtures; separate `resources.script_runtime` checks | Actual bridge/original stage/exact-version selection not executed |
| Recovery containment/failure | Failed stage holds; failed release probe re-holds; unknown/partial results never produce verified success; no retry | PASS: existing owner cases, native partial transcript, inspection timeout/drift tests | Real control-plane effects may be ambiguous and require read-only reconciliation before next action |
| Protections and zero tails | Namespace/class/SQLite/migration, seven secret names, privacy, domains/routes, hold/rate/boundary and zero tails required | PASS: rejection and success matrices | Cannot prove secret values unchanged from names alone; inspections are not atomic locks |
| Genuine device/Apple/model success | Must be observed in a separately authorized operation | UNTESTED | No device operations, credentials, purchases, live calls or production changes authorized |
| Live readiness and restoration | Exact deployed source/coverage plus final baseline and zero tails observed | UNTESTED | No live Cloudflare reads/mutations/tails occurred; synthetic pass is not operational readiness approval |

## Recovery, evidence gaps and handoff

The [operation guide](../../../docs/coach-final-auth-diagnostics.md) contains the exact future
sequence and stop rules. It distinguishes transport attachment, locally proved coverage behavior,
future pre-attempt coverage and post-attempt evidence. It requires a hold, capture closure and
independent zero-tail verification; a default-off candidate stage bridges to the unchanged
original-source owner, original latest settings are staged, and only then the exact original
version is selected. The new GET-only verifier requires both surfaces before original-owner
release, and again afterward. It does not patch settings, waive guards or reset security data.

Containment does not undo a consumed counter/nonce, in-flight work or a completed model call.
Silence is inconclusive. Missing DO rows leave aggregate rejection ambiguous; concurrent caller
rows cannot be attributed without correlation data, which this design intentionally excludes.
No automatic retry follows an unknown external effect. The operation owner retains responsibility
for removing/reviewing the temporary flag after separately authorized observation.

Production mutations, live tails, credential/native-consent reads, device actions and provider
calls performed in this preparation: **zero**. Local temporary test failures were corrected:
callback typing, Python 3.7 mock-call inspection, and workerd output collection. These were harness
issues, not evidence of the Coach cause. No failed live criterion was converted to a local pass.

Implementation completion means committed, locally tested preparation. No-mistakes review,
PR/CI, merge authority, deployment authority, live cause and Coach repair are separate outcomes.

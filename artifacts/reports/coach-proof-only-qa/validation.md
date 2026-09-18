# Coach proof-only QA — intermediate diagnostic source

2026-09-18. Prepared from default-branch revision `248f997` on delivery branch
`fm/reptoday-coach-beta-verification-2026-09-18`. Retained deployment/preparation branches and
their completed pipeline histories were preserved.

**TestFlight Coach is not enabled.** Exact authenticated assertion extension encoding/availability
remains unresolved. The client/server retain Production-only purchase checks and ordinary
Debug/Release endpoints remain empty. No genuine installed beta, Apple proof, current subscription,
new deployment or model result is claimed. Historical guarded release `2952fab` remains separate.

## Delivered source

- Hidden one-attempt server-proof preparation reuses the actual runtime transport, signs exact
  `{}` and intentionally replays identical proof/body after exact `400 invalid_context`.
- The source gateway denies operator-bearer `{}` so that result cannot masquerade as the
  device/Premium gates. No public diagnostic route or weaker authentication was added.
- The probe reserves only a spent marker before operations, stays within 30 seconds, clears
  display/cancels on exit and emits fixed outcome classes. It receives no workout context/writer
  or model prompt. Production purchase, namespace, counter/challenge/body/purchase binding,
  Premium, content-statelessness, provider bounds and ordinary Coach flows are preserved.
- Runbooks, implementation checkpoint and test coverage identify this as diagnostic preparation.
  No permissive field alias/type/byte-order decoder or Sandbox fallback was guessed.

## Executed checks

| Check | Result and limit |
| --- | --- |
| Proxy baseline under Node 20 | 162 tests and typecheck passed before changes |
| Admission regression before correction | Valid operator `{}` returned 400; operator-exclusion test failed as intended |
| Final proxy tests | 178 passed; includes preserved Production eligibility, independently verified Sandbox/Xcode denial, unsupported signed extension candidates, both-gate ordering and operator exclusion |
| Final proxy typecheck | passed |
| `npm run test:runtime` | Installed workerd/native P-256/SQLite admission and exact replay, forged proof and consumed-counter Premium denial; Apple SDK/transport local doubles and actual verifier negatives; zero external requests/provider dispatches |
| `tools/test-coach-runtime-client.sh` | 83 actual-source XCTest cases passed, including 22 runtime transport and 4 probe view-model cases; Apple/HTTP dependencies are doubles |
| XcodeGen + unsigned arm64 CoachDeviceQA build | passed with Xcode 26.5 / iOS 26.5 SDK, iOS 17 floor retained; actual hidden UI compiles |
| Unsigned ordinary Release archive | passed; not an approved installable/uploadable TestFlight binary |
| Actual QA/Release built-plist and scheme inspection | QA public origin/runtime/empty gate/no telemetry/local StoreKit; ordinary Release empty Coach endpoint, empty gate and QA disabled; ArchiveAction selects Release without local StoreKit |
| Built-configuration negative tests | 5 QA + 7 Release/override checks passed; QA tests consumed the new actual built app by replacing the test module's app-path input, not an old build or a fabricated plist |
| `git diff --check` | passed |

The ambient Node 26 run initially failed eight baseline crypto/state tests because fixture CBOR
could not be decoded. Switching only the tool runtime to the project's existing Node 20 made
the unchanged baseline pass. No production cryptographic behavior was loosened for that tooling
difference. A test-only Buffer type annotation corrected final checkJs inference. The unsigned
builds retained existing StoreKit `await`/orientation warnings; no compiler error occurred.
No genuine-device or simulator installation/execution was performed. The native equivalent
client suite and arm64 compilation establish source behavior, not real Apple compatibility.

## Causal evidence and unresolved boundary

The initiating user path is a legitimate TestFlight Sandbox Premium purchase followed by Coach
use. No actual tester transaction rejection was observed. Source demonstrates two independent
masking conditions: ordinary Release never configures Coach, and an enabled QA client rejects
Sandbox locally while the server selects only Production verifier/status/transport/policy.
The expected visible symptom is unavailable Coach, with offline workouts still usable.

The Production workflow introduced by `e7bc24b` deliberately enforced that environment. Its
verified production path passes local workflow/gate tests and historical live denial checks,
not a genuine positive Apple/model exchange. The minimal policy counterfactual changes only
the fixture transaction environment: Production is eligible, Sandbox is denied. Both supplied
and current transaction environments are checked. Enabling an endpoint alone cannot fix that
policy, and a successful operator/body-validation probe cannot establish genuine device/Premium
admission. The pre-fix regression demonstrated that second disconfirming observation directly.

Apple's [server validation guide](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server)
documents TestFlight category 2, UInt32/String attestation properties with `apple_*_01` names and
different assertion property names. Its [public fixture guide](https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide)
does not provide an assertion extension example. The supported exact assertion names/types,
category wire byte order, flags and availability must be established before classification can
safely select Sandbox. Full signature/app/nonce/key binding must precede interpreting those fields,
and classification must reflect the current assertion, not merely an old enrolled beta key.

The next dependency is the bounded Apple-bound schema operation in
[`docs/coach-testflight-schema-probe.md`](../../../docs/coach-testflight-schema-probe.md), with
existing signing/App Attest authority, an approved genuine TestFlight channel/unused version-build,
actual installation and one fresh key/attestation/assertion scope specified. Empirical schema
observations must be interpreted against authoritative protocol evidence; they do not themselves
authorize Sandbox. Then deliver the coupled decoder/client/verifier/status API/allowlist/policy
and actual ordinary archive configuration. A later proof-only run needs matched newly reviewed
held server stage/release plus real verified subscription readiness. This report performs none
of those protected or distribution operations. The broader enablement remains open.

Operation/runbook: [`docs/coach-proof-only-qa.md`](../../../docs/coach-proof-only-qa.md).

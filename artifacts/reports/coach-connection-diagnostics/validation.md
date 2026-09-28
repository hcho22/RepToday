# Normal Release Coach connection diagnostics

Base: `7c97fa71e43bd541d9706b4825b6f6e52911a321`. Local observation date: 2026-09-28.
This is a client-only diagnostic change for the ordinary Coach conversation. It does not establish
or repair the production phone failure. The selected no-mistakes run owns subsequent review,
tests, documentation, lint, push, PR and CI; this report supplies its public-safe
evidence mapping. Scenario linkage is reviewed by that owner, not machine-enforced by Firstmate.

## Evidence and scope

The [runtime runbook](../../../docs/coach-runtime-authentication.md#local-connection-diagnostics)
owns the client diagnostic contract and normal Release reproduction recipe; its build configuration
section owns the ordinary versus synthetic QA route distinction.

`CoachViewModel.send` calls `CoachProxyClient.reply`, which calls the runtime transport. Before
returning a final HTTP response, that transport obtains eligible local purchase proof, enrolls if
needed, gets an assertion challenge and signs the request. Its existing `boundedCoachOperation`
converts internal errors to `CoachAuthenticationError.unavailable`. Thus a challenge 401 and an
underlying URL error previously lost their useful distinction, while a returned final 401 became
`CoachError.badStatus(401)`. The new per-call observation retains only fixed categories before
that erasure; original throws, deadlines, cancellation, recovery and request ordering remain intact.

Prior observations from another source checkout included a challenge 401 and, later, a final 401.
They are distinct boundaries and do not establish this current binary's failure stage. Generic
`nw_connection` endpoint/metadata warnings do not identify the Coach cause. Previously identified
backend response-mapping and capture limitations remain separate work; this change touches neither.
No new real-device, Apple credential, production HTTP, model, deployment or key-reset experiment ran.

## Validation mapping

Client behavior tests execute `CoachProxyClient.configured` or `CoachProxyClient.reply` through
injected, nonsecret dependencies. The review regressions also execute the shared failure trace
directly to force cancellation before or after deadline finalization without scheduler timing. They capture the exact rendered line sent to the OSLog sink.
They do not inspect source strings as a substitute for execution.

| Scenario | Expected / observed evidence |
| --- | --- |
| Challenge 401 vs final 401 | `testDiagnosticsSeparateHandshake401FromFinal401WithoutChangingErrorsOrKey`: one challenge vs HTTP line; unchanged unavailable vs badStatus error; 1 vs 2 HTTP calls, no new key writes. |
| Final fixed codes and privacy | `testDiagnosticsOnlyClassifyStrictBoundedFinalErrorsAndNeverLeakSentinels`: unauthorized, key_unavailable, auth_unavailable, final 401/503, malformed/private/duplicate/oversized input, exact cap boundary and invalid UTF-8; whole output pinned, secret sentinels absent, no final retry. |
| URL failure at handshake and final exchange | `testDiagnosticsURLFailuresSurviveRuntimeErasureWithSafeCodesOnly`: timeout/offline/TLS/DNS and unknown numeric code with secret description/URL/underlying error; stage/category survives and outward error remains unavailable. |
| Local proof / unavailable device | `testDiagnosticsLocalProofAndUnsupportedDeviceFailBeforeHTTP`: purchase/configuration lines, zero HTTP and attester calls, unchanged key. |
| Enrollment / assertion | `testDiagnosticsEnrollmentAndAssertionFailuresHaveDistinctStages`: enrollment HTTP 503 vs native assertion unavailable; original errors/key policy. |
| Private / oversized handshake | `testDiagnosticsMalformedAndOversizedHandshakeNeverLeak`: category other, original failure. |
| Cancellation | `testDiagnosticsCancellationIsSilentAndDoesNotChangeErrorOrLateState`, `testDiagnosticsURLCancellationIsSilentAtHandshakeAndFinalTransport`: no line, no late HTTP/key write, original error. |
| Deadline | `testDiagnosticsDeadlineIsOneFailureAndLateCallbackStaysSilent`: one enrollment timeout line, original timeout, no late HTTP/key write. `testDiagnosticsDeadlineOverridesWorkerCancellationBeforeOrAfterFinalization`: both cancellation types, both orderings, all five runtime stages; exactly one fixed timeout line. `testDiagnosticsCallerCancellationSuppressesWinningDeadline`: cancelled caller stays silent even after worker suppression is cleared. |
| Success / existing recovery | `testDiagnosticsSuccessfulRepliesAndExistingKeyRecoveryStaySilent`: original reply, enrollment and key_unavailable recovery call counts, no output. Existing auth suite covers bounded invalid-key recovery separately. |
| Disabled/invalid/configured route | Three `CoachProxyClientConfiguredTests.testDiagnostics…` methods: exact fixed categories, nil/restricted Release routes, iOS runtime selection with no request; macOS factory remains unavailable. |
| Direct transport / content handling | Remaining diagnostic tests preserve NSError identity, URL cancellation silence, decoding error, empty reply and safety refusal. |

Local commands and final results are recorded below. Genuine phone installation/signing, an eligible
Apple purchase, device App Attest, Xcode's attached-phone console and a successful live model reply
are **not tested**. Simulator and native doubles cannot establish those facts. There is no runtime
feature flag: enable-then-disable testing is inapplicable; recovery is a code revert, not a state reset.

## Historical pre-review results

These results and blob IDs describe the candidate before the R1 correction below; they are not
claims that the simulator build or sink smoke was rerun after that correction.

Xcode 26.5 (17F42), Swift toolchain on macOS, 2026-09-28. All network and Apple calls in tests
use injected fixtures. Build uses the checked-in project, with no scheme/project regeneration.

- `bash tools/test-coach-runtime-client.sh`: **100 tests passed**, zero failures (including 16 new diagnostics tests).
- Optimized tests: **16 diagnostic tests passed**, zero failures:

  ```sh
  xcrun swift test --package-path build/coach-runtime-client --configuration release \
    --cache-path build/coach-runtime-client/cache --scratch-path build/coach-runtime-client/scratch \
    -Xswiftc -module-cache-path -Xswiftc "$PWD/build/coach-runtime-client/module-cache" \
    --filter testDiagnostics
  ```

- Production sink smoke: the following Release test, using the default `.live` sink and rejected
  fixture configurations, passed and emitted **7 visible `[RepTodayCoach]` OSLog error lines**.
  `OS_ACTIVITY_DT_MODE=1` exercises the debugger-style console output on the local Mac; it is not
  a feature flag or a requirement added to the app. Attached-phone visibility remains untested.

  ```sh
  OS_ACTIVITY_DT_MODE=1 xcrun swift test --package-path build/coach-runtime-client \
    --configuration release --cache-path build/coach-runtime-client/cache \
    --scratch-path build/coach-runtime-client/scratch --skip-build \
    --filter testProductionHostnameCannotFallThroughToDevelopmentTransport
  ```

- Normal Release iOS simulator build: **passed**. Processed bundle inspection: **passed** (approved
  runtime endpoint, empty secret, QA off, no local StoreKit resource, Release archive contract).
- `git diff --check`: **passed**. No local service started; compile/test processes exited.

Evidence is bound to these Git blob IDs (repository-relative files), independently of report-only edits:

| File | Tested blob |
| --- | --- |
| `Services/Coach/CoachProxyClient.swift` | `06d91c052ff2ecb3441884c84f048bd9e2a2d1a6` |
| `Services/Coach/CoachRuntimeAuthentication.swift` | `0b6e8847830d20de6efc989f865d52e31c10eac6` |
| `RepTodayTests/CoachProxyClientConfiguredTests.swift` | `432ffbc94b9e00a6b759d1ca80ad0bbba0c8a4b9` |
| `RepTodayTests/CoachRuntimeAuthenticationTests.swift` | `c016ab45b0250f3c50f21e0eb991e62f01c9b620` |

Application files above are under `ios/RepToday/RepToday/`; tests are under `ios/RepToday/`.
One initial optimized build was invalidated by a concurrent local source edit; it was discarded
and the complete optimized diagnostic suite was rerun successfully against those pre-review files.
There was no remaining runtime/resource blocker.

## R1 review correction

The winning deadline now clears worker-cancellation suppression in the shared diagnostic capture.
The caller's `Task.isCancelled` check remains at emission. The trace has internal visibility for
ordered behavioral tests; its locking, deadline wrapper, original errors, authentication, purchase,
key state, recovery and request ordering are unchanged. No output field or accepted label was added.

Focused Release verification on 2026-09-28 used the native package generated by the setup portion
of `tools/test-coach-runtime-client.sh`, then one test invocation:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/build/coach-runtime-client/module-cache" \
xcrun swift test --package-path build/coach-runtime-client --configuration release \
  --cache-path build/coach-runtime-client/cache --scratch-path build/coach-runtime-client/scratch \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/build/coach-runtime-client/module-cache" \
  --filter 'CoachRuntimeAuthenticationTests|CoachProxyClientConfiguredTests'
```

Result: **52 of 53 tests passed**. All **38 runtime authentication tests** and all **18 diagnostic
tests**, including both new regressions, passed. The command exited 1 because the existing
`testActualAppBundleSelectsTheIntendedConfiguration` made three failing assertions: the native
Swift package has no iOS Release app-bundle configuration, endpoint or runtime transport.
This is not a passing app-bundle validation; that check requires the app-hosted test environment.
The focused run did not rerun the simulator build or production-sink smoke. No pre-fix test run
was performed in this review round.

The correction's tested source blobs are:

| File | Tested blob |
| --- | --- |
| `ios/RepToday/RepToday/Services/Coach/CoachProxyClient.swift` | `5b2a7e8c378084ae529673f47406bcc9933dbd2e` |
| `ios/RepToday/RepToday/Services/Coach/CoachRuntimeAuthentication.swift` | `07b5885044473af3cfed4ed6a4ca8c661105be01` |
| `ios/RepToday/RepTodayTests/CoachRuntimeAuthenticationTests.swift` | `9ddce4602829092013d0cd656e400f140dd0ed97` |

`CoachProxyClientConfiguredTests.swift` retains its pre-review blob above. Full test/lint gates
and publication remain owned by the outer executor. No device or production experiment is part
of this correction; the phone connection cause remains unproven.

## Risk, recovery and remaining judgment

Shipped authentication diagnostics are high-risk until privacy and unchanged behavior are reviewed.
Impact is confined to local console output and transient diagnostic memory in the Swift client;
there are no model, auth, purchase, retry, key/counter, server or workout changes. Dependency and
side-effect evidence is the unchanged request counts, original errors and key-state assertions above.
Human review must assess the closed output vocabulary, cancellation races and actual phone evidence
before attributing the incident. A future service repair needs that additional evidence.

No deployment/release is included; diagnostic recovery is documented in the runtime runbook.
The original production incident retains its separate reproduction and release obligations.

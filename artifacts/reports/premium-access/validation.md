# Premium access and post-onboarding Apple sign-in

Date: 2026-09-24. Implementation follow-up to the Premium/signup diagnosis. Source revision and
final build results are recorded below. This report is the public-safe accepted
specification and evidence handoff for the no-mistakes delivery pipeline; it is specification,
not an expansion of captain intent. Scenario linkage is reviewed by that pipeline, not enforced
by a separate evidence-import system.

## Accepted contract and impact

- **Intended behavior:** An onboarded user can open Profile → Account and use the official Sign in
  with Apple control, or see an already-stored sign-in. Restore describes the absence of an active
  Premium subscription. Catalog unavailability stays visible separately, with an accessible Retry
  plans action. Catalog configuration is investigated read-only.
- **Preserved behavior:** Existing profile and `User.id`, workout history, active session, progression
  policy, preferences, onboarding completion and subscription authority remain unchanged through
  sign-in success, cancellation and failure. Free/offline workouts remain available. Apple billing
  does not require app sign-in. Purchase success, cancellation, pending approval and verified restore
  keep their existing grant semantics; no fabricated products, prices or entitlement bypass.
- **Impact/dependencies:** Profile navigation, an Account view/model using the existing Apple auth
  service, paywall model/view and a QA-only raw catalog count. No persistence schema, backend identity,
  CloudKit account, StoreKit verification, billing-grace, product configuration or deployment change.
- **Risk:** Initially high due to possible identity reassignment; bounded to medium after tracing
  identity consumers. The new path can write the existing Keychain credential through `AppleAuthService`
  but has no user/log/policy/active-session write service. It cannot merge or switch app data accounts.
  Native credential presentation/persistence remains an external dependency needing device evidence.
- **Validation scenarios:** Authentication success/cancel/failure, credential storage/read failures,
  already-signed-in state, unchanged history/profile/progression/preferences/onboarding/Premium,
  free workout generation, empty/valid/failed catalogs, successful/empty/failed restores, retry,
  mutual exclusion and existing purchase outcomes. See the scenario table.
- **Recovery:** Revert the task's source/UI commits before release; no data migration is necessary
  because existing ownership keys never change. Reverting code does not erase a credential already
  stored by a user. Existing account deletion retains its existing credential-clear behavior; do not
  delete app data or reinstall as recovery. No live configuration or account changes were performed.
- **Release applicability:** Code and investigation only. No deployment, merge, TestFlight upload,
  App Store submission, pricing/agreement/account operation or production configuration change.

## Identity boundary

`CoreDataUserService.currentUser()` reads the existing single local record; it does not select a
record from the Apple credential. `User.id` is the onboarding-time key, and policy/active-session
stores use it. CloudKit mirrors through the device's iCloud account. Coach authorization uses its
separate App Attest/StoreKit path, and analytics uses its anonymous install ID. None reads the new
credential as a command to move data.

`AccountViewModel` has only `AuthServiceProtocol`. It saves an Apple-issued opaque identifier
through the existing `completeSignIn` seam, reports success only after persistence succeeds, treats
cancellation silently, and leaves a retry after failure. A failed credential read prevents offering
to overwrite unknown status. Already-signed-in state offers no account replacement action. The
official button requests no name/email scopes. It never calls `OnboardingViewModel.finish()` or
saves a `User`, and it makes no cloud-sync or prior-history recovery promise. No account-linking
product/security decision is required for this credential-only addition. A future cross-account
merge or rekey is a separate policy and migration task.

## Causal follow-up and catalog investigation

The existing diagnosis already traced the screenshot symptom: paywall buttons are generated from
usable subscription plans, and the screenshot's QA row reported none. A local fixture can mask
live-catalog failure. Restore then checked qualifying current entitlements; its old “No previous
purchase” copy both overstated that read and replaced the catalog message. Sign-in's separate
navigation gap followed completion of onboarding, after which the welcome-only control disappeared.
The screenshot spinner is not evidence of a hang.

On 2026-09-24, bounded read-only browser inspection again returned App Store Connect at `/login`,
with title “App Store Connect.” No login or settings mutation was attempted. The installed
chrome-devtools-axi CLI omitted the now-required `pageId` for evaluation; its existing `callTool`
interface with explicit page ID completed the read successfully, without modifying shared tooling.

| Evidence | Result and limit |
| --- | --- |
| Requested source product IDs | `com.reptoday.app.premium.monthly`, `com.reptoday.app.premium.yearly` |
| Checked-in local catalog | Same IDs, monthly/yearly recurring subscriptions; local data is not App Store Connect evidence |
| Screenshot build variant | Existing diagnosis identifies `COACH_IPHONE_QA`; that scheme deliberately omits the local StoreKit fixture |
| Locally compiled candidate | Debug and CoachDeviceQA simulator bundles: `com.reptoday.app`, version `1.0.0`, build `1`; these unsigned artifacts do not identify the installed iPhone binary |
| Installed binary identity/channel | Exact version/build, signature, installation channel, storefront and prior purchase environment remain unknown; no device inventory was supplied |
| Live product IDs/type/availability | Unverified: no authenticated catalog dashboard |
| Live prices/localizations/agreements/banking/tax/approval prerequisites | Unverified: no authenticated dashboard; no configuration change authorized |
| Raw product lookup versus app filtering | The original screenshot cannot distinguish these. New QA-only failure detail records “lookup returned N products; 0 usable subscriptions.” N=0 identifies a raw empty result; N>0 identifies filtered products. This is not itself a configuration diagnosis |

Only an integer raw count is added, on the no-usable-subscriptions path. No product payload, receipt,
account identifier, credential or arbitrary error text is retained or transmitted. Valid plan mapping
and ordinary-build facade behavior remain unchanged. QA tests inject both count outcomes through
the existing service/model boundary; they do not claim to manufacture real StoreKit `Product` values.

Counterfactual checks retain independent axes: catalog failure plus a supplied verified Premium
restore still unlocks; a valid catalog plus no current entitlement does not grant Premium; retry
can recover plans without erasing the latest restore result. A usable real subscription reaching
the mapping while the model still produced no plan would disconfirm the original causal boundary;
no such live observation was available. Billing-grace behavior was not changed or claimed reproduced.

## Executed evidence and limits

The source compiles with Xcode 26.5. The focused runner compiles actual production sources in native
macOS SwiftPM packages, once with `COACH_IPHONE_QA` and once without it. Apple ceremony and StoreKit
operations are injected; auth credentials/defaults are in memory. Preservation uses the actual
CoreData services and compiled model in an in-memory store, the actual exercise catalog and engine,
and actual AppState/PremiumSessionAuthority. The harness does not initialize the production app or
call live Apple, Coach or telemetry services. Framework CoreData XPC warnings occurred in this
standalone host; all persistence round-trip assertions passed.

```sh
./tools/test-storekit-paywall-diagnostics.sh
xcodegen generate --spec ios/RepToday/project.yml
# Repeat for scheme RepTodayCoachDeviceQA / configuration CoachDeviceQA:
xcodebuild build-for-testing -project ios/RepToday/RepToday.xcodeproj \
  -scheme RepToday -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/premium-access-ios \
  -clonedSourcePackagesDirPath "$PWD/build/coach-beta-proof-release/SourcePackages" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

**Native result: 45 QA + 38 ordinary = 83 tests passed, zero failures.** Includes 19 paywall,
8 existing Apple auth, 6 new account state tests, 1 six-case preservation test in each configuration,
and 11 QA / 4 ordinary diagnostic tests. UIKit-only checks are excluded from this native count.
The local build uses already-cached Lottie sources; no package update is required. Logs remain in
ignored `build/premium-access-native.log` and `build/premium-access-final-*.log`; this committed
record retains the counts, conditions and limits without private absolute paths.


| Requirement/scenario | Expected and observed result | Status/evidence |
| --- | --- | --- |
| Auth success | Stored synthetic credential, signed-in state and same state after model reconstruction | PASS, `AccountViewModelTests` |
| Auth cancellation/failure | No credential write, cancellation silent, fixed failure copy and retry available | PASS, Apple and domain cancellation plus failed/invalid result cases |
| Persistence failure/unreadable status | Never claim a saved credential after failure; retry status before offering sign-in | PASS, injected read/save errors |
| Already signed in/duplicate callbacks | No replacement write; repeated or empty completion cannot overwrite credential | PASS, `AccountViewModelTests` |
| Data preservation | Success/cancel/failure × free/Premium: exact user/profile/history/policy/active session and defaults retained; onboarding true, one user, no records under new Apple ID, authority unchanged | PASS, `AccountPreservationTests` (six cases per configuration) |
| Free workouts | Actual engine still produces a nonempty session after every preservation case | PASS, same integration test; no auth/billing dependency added |
| Catalog × restore | Available/empty/thrown catalog × sync success/failure × free/Premium keeps exact catalog message and plan list; correct grant/message and call sequence | PASS, 12-case matrix in each configuration |
| Explicit retry | Restores valid plans after empty catalog; clears only catalog message and preserves no-active-subscription outcome | PASS, `PaywallViewModelTests` |
| Mutual exclusion | Suspended load/purchase/restore blocks every duplicate or competing operation; busy state clears afterward | PASS, continuation-controlled test; paywall isolated to main actor |
| Existing purchase/telemetry | Success grants, cancel silent, pending waits, errors remain recoverable; restore does not emit new purchase telemetry; catalog retry does not duplicate paywall-shown | PASS, existing paywall/auth regression suites |
| QA counts/privacy | Raw zero versus filtered positive count distinguished; restore cannot erase count; fixed bounded diagnostics | PASS, injected diagnostic outcomes; genuine lookup untested |
| Account accessibility and retry control | Official sign-in versus signed-in UI, optional billing-independent explanation; catalog and restore text together; actual accessible Retry activation | COMPILE-CHECKED only, `AccountAccessEvidenceTests` and hosted `StoreKitPaywallDiagnosticsTests`; not executed in this worker |
| Real Apple authorization / live purchase / live restore | Device/account-backed success | UNTESTED: no authenticated catalog or authorized genuine-device session |

No simulator was installed into, reset or erased: available devices use shared state outside this
worker's worktree. The existing hosted UI checks were extended and compiled in the full iOS test
bundle; the actual persistence integration was executed natively. Native state assertions do not
establish Profile touch navigation, physical-device VoiceOver/Dynamic Type appearance, Apple sheet
behavior, Keychain entitlement provisioning, CloudKit cross-device sync or live StoreKit availability.
Those gaps remain explicit for the delivery owner and any later device QA.

## Revision and delivery handoff

Validated application/test source: `a3cda7bcbd94b2a8eee7a30418636d991f4c0466`.
The documentation-only handoff commit changes no executable source. The native 83-test result is
bound to this source in both configurations. Final `build-for-testing` results: **TEST BUILD
SUCCEEDED** for ordinary Debug and release-type CoachDeviceQA, both arm64 and x86_64 simulator
architectures, with signing disabled. Both include the new Account hosted test and all existing
unit tests. These are compilation results, not simulator test executions. `git diff --check` and
shell syntax validation of the focused runner passed. No-mistakes v1.79.0 doctor reports a healthy daemon
and runnable pipeline agent, and AXI recognizes the initialized feature branch/repository. The installed run
help was consulted; no shared tool upgrade or restart was performed. Implementation is handed
back committed for the prescribed no-mistakes start. This report supplies accepted criteria and
limits; it must not be substituted for captain intent in `--intent`.

## Gate test follow-up: disposable simulator (2026-09-24)

Run `01M3AK6WGSNCNQM55RRW32YPWN` received explicit permission for one disposable simulator in
the normal device set. Created iPhone 17 Pro / installed iOS 26.5 runtime, UDID
`88E6F927-FA16-4A42-95AD-3F63BB750F98`. All test commands target that exact UDID with
`-sdk iphonesimulator -parallel-testing-enabled NO`, ad-hoc signing (`CODE_SIGN_IDENTITY=-`,
empty team), worktree-local DerivedData/packages, and empty telemetry endpoint/secret overrides.
The initial destination-settings command still failed without the explicit Simulator SDK;
the focused `xcodebuild test` command resolved and launched the normal-set device successfully.

The touch-navigation test then reproduced a separate **test setup failure**: Profile remained
covered by Health Access, so the Account row timed out. The exported runtime accessibility tree
shows `UIA.Health.DoNotAllow.Button`, label `Don’t Allow`; the shared helper expected the older
`UIA.Health.AuthSheet.CancelButton` or ASCII `Don't Allow`. The fix matches both observed spellings
in its existing label fallback. No production code changes are needed. A warm relaunch alone was
insufficient evidence: it passed after the permission state changed, whereas a clean-state attempt
with an early-return-only helper change still failed. That speculative helper change was removed.

Evidence root (outside the worktree, explicitly authorized for this test phase):
`/Users/hcho/.no-mistakes/evidence/01M3AK6WGSNCNQM55RRW32YPWN/premium-recovery/`.
Logs and result bundles preserve the initial failures as well as subsequent results. The
`navigation-clean-attachments/DCAC926A-28D7-4C64-8CC6-67877808E1FB.txt` runtime tree records
the exact changed system control. Screenshots are supplemental evidence; assertions execute
production views and their controls, not source-text matching.

Final focused results: **5 executions passed, zero failures** (four test methods, with the existing
hosted diagnostic method run in both configurations). Earlier diagnostic failures remain in the
evidence root. No full suite, linter, formatter, static analysis, push, PR or CI phase was run.

| Executed check | Result and evidence beneath the root above |
| --- | --- |
| Existing `AccountAccessEvidenceTests` (Debug) | PASS: signed-out official Apple button and signed-in status, optional/billing-independent explanation; `hosted-initial.xcresult`, `premium-access/account-*.png` |
| Existing hosted `StoreKitPaywallDiagnosticsTests.testHostedPaywallDiagnosticRowsFollowTheBuildConfiguration` (Debug) | PASS: activate Restore/Retry, keep catalog and restore errors separate, ordinary build omits QA rows; `hosted-initial.xcresult` |
| New `PaywallViewModelTests.testHostedRetryRecoversPlansAndPreservesNoActiveRestoreResult` (Debug) | PASS: activate real hosted controls with deterministic service fixture; no-active restore remains visible, repeated retry makes one request, Restore disabled while loading, both plan controls return without clearing restore result; `retry-control.xcresult`, `premium-access/paywall-recovered-plans-after-restore.png` |
| Existing hosted diagnostic test (CoachDeviceQA configuration) | PASS: injected catalog/restore failures retain independent bounded QA rows, larger-text render and Retry activation; `qa-hosted.xcresult`, `coach-storekit-diagnostics/qa-*.png` |
| New `AccountAccessUITests.testProfileReachesOptionalAppleSignInAfterOnboarding` (Debug) | PASS on a freshly erased instance of the same test-owned simulator after the selector fix. Trace taps `UIA.Health.DoNotAllow.Button`, then confirmation OK, Profile and Account; official sign-in control is hittable; `account-navigation-final.xcresult` and `navigation-final-attachments/`. Onboarded routing is supplied by the existing test launch argument; this does not repeat onboarding or perform Apple authentication. |

Genuine Apple authorization, Keychain persistence through real authorization, Apple-sheet
cancellation/retry, real StoreKit purchase/restore (including pending/canceled purchases), and the
affected iPhone's live catalog/configuration cause remain **untested** under the scoped permission.
No App Store Connect access or mutation was attempted. The prior 83 native test executions remain
historical evidence; they were not rerun or substituted for device-backed verification here.

Cleanup completed after evidence export: only the recorded test-owned simulator was shut down and
deleted, and the worktree-local temporary build/package directory was removed. `cleanup.json` in
the evidence root confirms both removals. No existing/shared simulator was modified.

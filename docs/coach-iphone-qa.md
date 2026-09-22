# Physical-iPhone Coach synthetic QA preparation

A separate [TestFlight proof-schema probe](coach-testflight-schema-probe.md) is prepared behind this
dedicated QA surface. It requires its own concrete device/signing/Apple-operation approval, makes
no model request and does not grant TestFlight Premium or consume the two-model-request budget.
The same hidden panel now also prepares a separately budgeted
[server proof-only exchange](coach-proof-only-qa.md). It sends signed `{}` plus its exact replay,
with no training content or provider request. Its new operator-exclusion server source is
undeployed. Current client/server source now carries and independently verifies Apple Sandbox
Premium, but the released Worker is still Production-only.

`CoachDeviceQA` is an explicit **preparation** configuration, not evidence of a working service.
Ordinary Debug/Release Coach endpoints remain empty. The runtime-authentication service is deployed.
Compatible production signing/distribution, a capable physical iPhone and an existing production
or Sandbox Premium purchase/trial must be confirmed separately before sending either QA turn. No
arbitrary Production-error fallback, operator bearer, local Premium grant or authentication bypass
is provided. The Sandbox-capable revision has not been deployed or exercised by a genuine
TestFlight build, so TestFlight admission remains unverified.

## Configuration and unsigned build

`ios/RepToday/project.yml` is authoritative. `Info.plist` expands the existing per-configuration
build settings, and `ServiceContainer.live` resolves the actual `CoachProxyClient.configured`.

| Configuration | Public Coach endpoint | Binary Coach secret | Authentication | Synthetic QA |
| --- | --- | --- | --- | --- |
| Debug | empty | empty | `app-attest-storekit-v1` | disabled |
| Release | empty | empty | `app-attest-storekit-v1` | disabled |
| CoachDeviceQA (release type) | `https://coach.reptoday.app/coach` | empty | `app-attest-storekit-v1` | enabled |

The `RepTodayCoachDeviceQA` scheme selects `CoachDeviceQA` for every action and attaches **no local
StoreKit configuration**. This dedicated release-type configuration keeps optimized code and enables
XCTest testability; it defines `COACH_IPHONE_QA`, never `DEBUG`. Testability changes compiler access
for the test bundle, not endpoint authentication or Premium/consent rules. The QA app is named **Rep Today Coach QA**. It retains the registered
`com.reptoday.app` identity and production App Attest entitlement source; it does not create another
app identity. Installing it later may replace an existing app with that identity. QA telemetry is
unconfigured, so this lane emits no analytics. The default `RepToday` scheme remains Debug/Release.

From the repository root, prepare and inspect without signing or credentials:

```sh
(cd ios/RepToday && xcodegen generate)
mkdir -p build/coach-iphone-qa
xcodebuild -project ios/RepToday/RepToday.xcodeproj \
  -scheme RepTodayCoachDeviceQA -configuration CoachDeviceQA \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/coach-iphone-qa/device \
  -clonedSourcePackagesDirPath build/coach-iphone-qa/packages \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
python3 tools/inspect-coach-qa-build.py \
  --app build/coach-iphone-qa/device/Build/Products/CoachDeviceQA-iphoneos/RepToday.app \
  --configuration CoachDeviceQA
```

The inspector parses the **built** plist and generated scheme, checks the endpoint/mode/empty secret,
QA flag and disabled QA telemetry, and rejects a local StoreKit scheme attachment. It prints only
fixed public configuration classes. It does not read Keychain, sign, install, verify entitlement
proofs or call the service. Run `python3 tools/test-coach-qa-build-inspection.py` after the device build to exercise rejection
of endpoint/mode/secret/flag/configuration mismatches and local StoreKit attachments against copies
of the actual generated output contracts. For a separately built ordinary app, pass `--configuration Debug` or
`Release` and its actual `.app` path to verify that Coach is empty/disabled.

An unsigned arm64 `.app` is a compilation artifact, **not an installable iPhone distribution**.
It has no valid code signature/provisioning profile. The checked-in team and entitlement source do
not establish Developer account capability, actual App ID prefix, profile authority or effective
signed entitlement. Do not create profiles, grant account access, archive or upload to fill those
gaps as part of this source-preparation recipe.

## Later signed launch and the two-request run

Only after the separately authorized service/signing/device prerequisites pass:

1. Open `ios/RepToday/RepToday.xcodeproj` in Xcode. Select **RepTodayCoachDeviceQA**, the eligible
   physical iPhone and an **existing** approved signing/distribution path. Confirm the Run
   configuration is `CoachDeviceQA` and StoreKit Configuration is **None**. Inspect the installed
   build's effective identity and **production** App Attest entitlement. A development install is
   not automatically compatible with a genuine production purchase; establish that distribution
   fact separately. No signing/profile creation or upload is included here.
2. Launch the signed app, then open **Profile → Coach Synthetic QA**. There is no launch-time Coach
   request and no free-text chat in this QA route. Actual user workout/history/policy services are
   not dependencies of this runner. It cannot insert fixtures or change a workout.
3. Confirm an existing locally verified Premium purchase/trial. If necessary, restore an existing
   purchase through **Progress → Go deeper with Premium → Restore purchases**; never make a new
   purchase for this recipe. The QA screen does not buy or grant Premium. Local eligibility alone
   is insufficient: each turn still requires real App Attest and fresh production StoreKit proof,
   with independent production status verification on the server.
4. Read/acknowledge the existing Coach data disclosure if not already acknowledged. **Not now**
   exits without sending or recording consent. Acknowledgement uses the existing versioned
   `AppState` contract; it does not alter telemetry consent. Confirm the screen's service and
   signed-device readiness toggle only after operational clearance for this existing budget.
5. The screen first selects **Why squats**. Review its displayed **approved synthetic fixture** and
   fixed prompt, then tap **Send synthetic Why squats once**. The request goes through the actual
   configured client. No real workout data is substituted. The approved fixture source is
   `Services/Coach/CoachSyntheticFixtures.swift`, extracted verbatim from the existing native QA
   fixtures; the native operator runner and iPhone runner now share that one definition.
6. Inspect the returned text **locally on device**. A non-empty reply is a model-return observation,
   not semantic correctness. Check the supplied phase, squat frontier, recent patterns and
   consistency. It must distinguish summary-based reasoning from today's unknown exact session;
   reject invented exercises, prescriptions, session edits or policy changes. Mark **Local semantic
   review passes** only if those checks pass. **Review fails or is uncertain** stops the run.
7. Only a passed first review enables **Pistol-squat form**. Tap its named Send button once; inspect
   its shared synthetic fixture and reply against the earned phase/assisted frontier, safe form
   guidance and no fabricated/altered workout or policy. Mark its local review outcome. This is
   the second and last possible turn.

**Budget:** at most two total model requests across this approved QA exercise, not two per launch,
device, installation or authentication lane. Do not also run the native operator live-QA helper.
Genuine challenge/enrollment POSTs are required authentication protocol steps, not additional model
turns; this runner adds no public status preflight or negative probes. The screen persists only a
content-free stage before each attempt. It allows one why-squats turn
and one pistol-form turn, in that order; no automatic request, resend, retry or reset control exists.
Failure, safety refusal, empty/invalid response, offline/auth/upstream error or ambiguous timeout
ends the run. Leaving with an in-flight or unreviewed attempt ends it too; a crash/relaunch cannot
repeat a reserved turn. A first passed review survives relaunch and leaves only the pistol turn.
Account deletion does not reset the QA ledger. Reinstallation, app-data removal or using a second
device must not be used to replenish the externally coordinated budget.

Every turn is bounded to at most 30 seconds total, including the local eligibility recheck, native
Apple operations and HTTP. The existing runtime transport retains its request/resource deadlines,
10-second bounded handshake steps, 32 KiB request and 16 KiB response caps, redirect rejection and
no retry of the final paid POST. Requests are consent-checked both before admission and after the
asynchronous local Premium recheck. Errors use fixed non-blocking copy, never raw error details.
The on-device deterministic generation/player/completion path remains independently usable offline.

Replies live only in screen memory and clear on review or leaving. There is no clipboard, share,
transcript export or content logging feature. **Do not copy, screenshot, export or log** prompts,
context, replies, credentials or purchase/App Attest proofs. Record only fixed outcomes separately:
configuration/build, signing/device, genuine authentication, model return, local semantic review and
error/core recovery. Offline fixture doubles cannot establish any positive live outcome. The real chat transcript,
workout history and policy are never read, rewritten or seeded by the QA runner.

## Offline validation and boundaries

```sh
(cd proxy && npm test && npm run typecheck && npm run test:runtime)
./tools/test-coach-runtime-client.sh
./tools/test-coach-live-qa.sh
./tools/test-coach-production-deploy.sh
./tools/test-coach-runtime-migration.sh
```

These execute local transport/Apple doubles, not the public service or paid provider. The shared
SwiftPM harness symlinks actual application client/authentication/context/QA-view-model sources and
actual XCTest sources; it does not replace them with a parallel implementation. UIKit surface and
entry/configuration integration tests live in `RepTodayTests` for app-hosted execution. Native
macOS execution does not prove the iOS-only configured-transport branch, UIKit interactions or real
DeviceCheck behavior.

To compile the iOS host/tests without booting/mutating a shared simulator:

```sh
xcodebuild -project ios/RepToday/RepToday.xcodeproj \
  -scheme RepToday -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/coach-iphone-qa/simulator \
  -clonedSourcePackagesDirPath build/coach-iphone-qa/packages \
  REPTODAY_ANALYTICS_ENDPOINT= REPTODAY_ANALYTICS_SECRET= \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build-for-testing
```

To compile the QA app/test host with its actual QA selection too:

```sh
xcodebuild -project ios/RepToday/RepToday.xcodeproj \
  -scheme RepTodayCoachDeviceQA -configuration CoachDeviceQA -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/coach-iphone-qa/simulator \
  -clonedSourcePackagesDirPath build/coach-iphone-qa/packages \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build-for-testing
```

App-hosted execution, when an isolated simulator/device is authorized, uses the same ad hoc flags
for Simulator (fully unsigned entitled hosts fail before XCTest connects). Run the client,
configured-client, context, runtime-authentication, synthetic-QA view-model/surface, ordinary Coach
view-model, gating and disclosure suites. Also execute the QA scheme's configuration/entry tests
under `CoachDeviceQA`; an ordinary Debug test cannot prove selection of that configuration.
Keep Debug test analytics unconfigured as above and never automate the physical QA Send buttons
against the public service. See `artifacts/reports/coach-iphone-qa/validation.md` for this revision's
executed checks and remaining execution gaps.

## Migration revision coordination

This preparation introduces a new source revision. The existing migration wrapper's clean-branch
guard is unchanged and does not accept this QA task branch. The deployment owner must coordinate
the final reviewed source with the guarded deployment checkout **before staging**. Stage pins the
whole committed revision; release must use that exact staged revision. Do not stage older content
and switch HEAD for release, weaken the guard, modify a different task checkout from this lane or
use the legacy helper to migrate/roll back the runtime security binding. This document authorizes
no deployment or service call. `docs/coach-runtime-authentication.md` remains the authentication,
storage and migration authority.


## Ordinary Release archive boundary

The release archive workflow remains `tools/archive-release.sh`, ordinary scheme `RepToday`,
configuration `Release`. That captain-operated workflow performs its existing production telemetry
validation and protected credential injection; do not invoke it during offline Coach preparation.
It rejects additional Coach build-setting/plist overrides and checks the archived app with
`tools/inspect-coach-qa-build.py --configuration Release` before accepting the archive. A Debug
launch's local StoreKit attachment is not part of the ArchiveAction.

For a configuration-only check without credentials, services, signing, installation or upload:

```sh
(cd ios/RepToday && xcodegen generate)
mkdir -p build/coach-testflight
xcodebuild -project ios/RepToday/RepToday.xcodeproj \
  -scheme RepToday -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/coach-testflight/device \
  -clonedSourcePackagesDirPath build/coach-testflight/packages \
  -archivePath build/coach-testflight/RepToday.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= archive
python3 tools/inspect-coach-qa-build.py \
  --app build/coach-testflight/RepToday.xcarchive/Products/Applications/RepToday.app \
  --configuration Release
python3 tools/test-coach-release-build-inspection.py
```

This unsigned archive checks the real ArchiveAction/Release plist contract, not genuine signing or
TestFlight distribution. The current Release endpoint remains empty pending a separately authorized
Sandbox-capable server rollout and genuine-device/TestFlight validation. Never embed an operator
bearer as a workaround.

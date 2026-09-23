# Coach QA paywall diagnostic validation

Date: 2026-09-23. This is a source observability change, not an entitlement fix or a successful
Apple restore. No distribution signing, archive, upload, physical-device installation, account
operation, live StoreKit call, Coach request or model call was performed. The simulator-only
offline host uses certificate-free ad hoc signing.

## Executed behavioral checks

```sh
./tools/test-storekit-paywall-diagnostics.sh
```

Result: **9 QA tests and 3 ordinary tests passed, zero failures.** The script builds the real
`LiveStoreKitFacade.requestFailure`, `StoreKitSubscriptionService` and `PaywallViewModel` sources
as native macOS SwiftPM targets. StoreKit operations are injected doubles and defaults are held
in memory. There are no package dependencies or external requests. The script itself was run
end to end after both configurations had also passed directly during development.

The common matrix exercises 12 combinations in each configuration: available/empty/throwing
catalog × successful/throwing sync × free/Premium entitlement. Assertions pin the unchanged
generic message, grant, plans, settled busy state and exact request sequence. A throwing sync
still invokes the existing history-baseline cleanup and never reads current entitlements;
successful sync reads history then entitlements. Restore never reloads products. A separate
purchase check pins one purchase and its Premium grant.

QA checks additionally cover independent catalog/restore failures; reload preserving restore
evidence; empty products versus a thrown request; successful free restore versus sync failure;
successful Premium restore despite missing products; typed StoreKit/SKError/task cancellation;
typed network/system causes; only one underlying code; unknown domains becoming `other`; no
synthetic private descriptions retained in the value; unprojected errors using fixed text; and
fresh view models starting with fresh diagnostic state. The ordinary projection test pins the
preexisting `.failed(error.localizedDescription)` behavior.

## iOS compilation and UI limits

The Xcode project was regenerated with:

```sh
xcodegen generate --spec ios/RepToday/project.yml
```

The generated project change only registers the new XCTest source. The iOS hosted test uses
the existing `HostedSurface` and `AccessibilityTree` helpers with offline doubles. It checks
both diagnostic labels in QA, their absence in ordinary builds, the existing generic message
and absence of synthetic private text. Native macOS runs exclude this UIKit test.

```sh
xcodebuild build-for-testing \
  -project ios/RepToday/RepToday.xcodeproj \
  -scheme RepTodayCoachDeviceQA -configuration CoachDeviceQA \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/storekit-paywall-validation/ios \
  -clonedSourcePackagesDirPath "$PWD/build/coach-beta-proof-release/SourcePackages" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Result: **TEST BUILD SUCCEEDED**, arm64 and x86_64. This used existing local package checkouts.
The log showed the existing subscription-service redundant-`await` warning and the App Intents
metadata warning; no errors. No signing, archive or install action was requested.

An initial ordinary-build command added `-arch arm64` beside the generic destination. Xcode
rejected that argument combination before compilation (`destination implies architecture`). The
corrected command omits `-arch`, using the same destination form as the successful QA build.

```sh
for configuration in Debug Release; do
  xcodebuild build -project ios/RepToday/RepToday.xcodeproj \
    -scheme RepToday -configuration "$configuration" \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/storekit-paywall-validation/ios \
    -clonedSourcePackagesDirPath "$PWD/build/coach-beta-proof-release/SourcePackages" \
    -disableAutomaticPackageResolution -skipPackageUpdates \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
done
```

Result: **BUILD SUCCEEDED** in both ordinary Debug and Release.

## Isolated simulator UI check

The normal app entry constructs live services at startup, so the focused hosted test uses a
blank scratch SwiftUI app with a distinct local bundle ID. The scratch project includes the
actual native-runner production sources, `PaywallView.swift`, `Theme.swift`, `LegalLinks.swift`,
the existing `HostedSurface.swift` and the checked-in diagnostic tests. The preview-only
`MockSubscriptionService` declaration is copied verbatim from `MockServices.swift`; the tested
paywall instead uses the test's injected facade. No production app entry or service container
is initialized, and no StoreKit configuration is attached.

Initial scratch-project generation failed twice in XcodeGen's `suitableConfig(for:in:)` /
`SchemeGenerator.generateScheme` stack (exit 132 / `EXC_BAD_INSTRUCTION`). The scratch spec had
only debug-type configurations. Adding the missing Release configuration let the one corrected
generation attempt succeed. No tool was installed or updated; production project configuration
was not changed. Scratch generation and build evidence remain under
`build/storekit-paywall-validation/ui/` and are not included in the patch.

The first hosted QA execution failed the generic restore-message assertion: the test invoked
Restore before the view's asynchronous catalog task had settled, allowing the catalog result
to replace that shared message. Both independent diagnostic-row assertions passed. The test now
yields the actor until the expected catalog result arrives (bounded by two seconds) before
invoking Restore. This matches the reported interaction order and changes no production behavior.

The focused simulator command is:

```sh
simulator_id=$(cat build/storekit-paywall-validation/ui/simulator-id.txt)
for configuration in CoachDeviceQA Debug; do
  xcodebuild test \
    -project build/storekit-paywall-validation/ui/OfflinePaywall.xcodeproj \
    -scheme OfflinePaywall -configuration "$configuration" \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath build/storekit-paywall-validation/ui/derived \
    -only-testing:RepTodayTests/StoreKitPaywallDiagnosticsTests/testHostedPaywallDiagnosticRowsFollowTheBuildConfiguration \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
done
```

The dedicated simulator is iPhone 16 / iOS 18.6. The scratch QA build defines
`COACH_IPHONE_QA` for app and tests with testability enabled; the ordinary Debug build omits it.
It tests the actual SwiftUI surface under the conditional flag, while the separate full app
compilation above covers the release-type `CoachDeviceQA` configuration.

Result after synchronizing the test: **1 hosted QA test and 1 hosted ordinary Debug test passed,
zero failures; TEST SUCCEEDED in both configurations.** QA exposes both bounded labels after
Restore; ordinary Debug exposes neither. The generic restore message remains visible and no
synthetic private description appears in the accessibility tree. This is an offline surface
check, not a production app launch or genuine purchase/restore.

Genuine StoreKit errors, the device's underlying failure, successful genuine restore and Coach
eligibility remain unverified. Simulator accessibility results cannot establish physical-device
VoiceOver behavior. A later authorized QA build/device session is needed to obtain the two
bounded row results from the real failure.

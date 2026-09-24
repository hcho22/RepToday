#!/bin/bash
# Execute actual StoreKit/paywall sources with offline doubles in QA and ordinary configurations.
# No Apple service, device, receipt, credential, Coach request or analytics sink is used.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
build_root="$repo_root/build/storekit-paywall-validation"
python3 - "$repo_root" "$build_root" <<'PY'
from pathlib import Path
import sys
root, base = map(Path, sys.argv[1:])
app = root / 'ios/RepToday/RepToday'
sources = []
for directory in ['Models', 'Services/Engine', 'Services/Consistency', 'Services/Auth',
                  'Persistence', 'Services/Programmer', 'Services/Progress']:
    sources.extend((app / directory).glob('*.swift'))
sources.extend(app / path for path in [
    'Services/Protocols/ServiceProtocols.swift', 'Services/Subscription/StoreKitFacade.swift',
    'Services/Subscription/LiveStoreKitFacade.swift',
    'Services/Subscription/StoreKitSubscriptionService.swift', 'ViewModels/PaywallViewModel.swift',
    'ViewModels/AccountViewModel.swift', 'Services/Mock/MockServices.swift',
    'ViewModels/CoachGateViewModel.swift', 'Services/ActiveSession/ActiveSessionStore.swift',
    'Services/Coach/CoachProxyClient.swift', 'Services/Coach/CoachContextBundle.swift',
    'Services/Coach/CoachAnalyticsInsight.swift', 'Services/Coach/CoachRuntimeAuthentication.swift',
    'Services/Coach/CoachRuntimeProofProbe.swift',
    'Utilities/AppState.swift', 'Services/Mock/MockExerciseService.swift'
])
for mode in ['qa', 'ordinary']:
    package = base / mode
    for directory in ['Sources', 'Tests', 'tmp', 'cache', 'module-cache']:
        (package / directory).mkdir(parents=True, exist_ok=True)
    tests = [root / 'ios/RepToday/RepTodayTests' / name for name in [
        'StoreKitPaywallDiagnosticsTests.swift', 'PaywallViewModelTests.swift',
        'AppleAuthServiceTests.swift', 'AccountViewModelTests.swift', 'AccountPreservationTests.swift'
    ]]
    for directory, paths in [('Sources', sources), ('Tests', tests)]:
        for source in paths:
            target = package / directory / source.name
            if target.is_symlink():
                target.unlink()
            elif target.exists():
                raise SystemExit('Refusing to replace an unexpected native-test source entry')
            target.symlink_to(source)
    settings = ', swiftSettings: [.define("COACH_IPHONE_QA")]' if mode == 'qa' else ''
    (package / 'Package.swift').write_text(
        '// swift-tools-version: 5.9\nimport PackageDescription\n'
        'let package = Package(name: "StoreKitPaywallValidation", platforms: [.macOS("14.2")], targets: [\n'
        '.target(name: "RepToday", path: "Sources"' + settings + '),\n'
        '.testTarget(name: "RepTodayTests", dependencies: ["RepToday"], path: "Tests"' + settings + ')])\n'
    )
PY
for mode in qa ordinary; do
    package="$build_root/$mode"
    TMPDIR="$package/tmp" CLANG_MODULE_CACHE_PATH="$package/module-cache" \
        xcrun swift build --build-tests --package-path "$package" --cache-path "$package/cache" \
        --scratch-path "$package/scratch" \
        -Xswiftc -module-cache-path -Xswiftc "$package/module-cache"
    # Production readers use Bundle(for:) / Bundle.main. Install the actual compiled CoreData
    # model and catalog in the standalone XCTest bundle, with no source extraction or substitution.
    test_bundle="$package/scratch/debug/StoreKitPaywallValidationPackageTests.xctest"
    resources="$test_bundle/Contents/Resources"
    mkdir -p "$resources"
    xcrun momc "$repo_root/ios/RepToday/RepToday/Persistence/RepToday.xcdatamodeld" "$resources/RepToday.momd"
    cp "$repo_root/ios/RepToday/RepToday/Resources/Exercises.json" "$resources/Exercises.json"
    TMPDIR="$package/tmp" CLANG_MODULE_CACHE_PATH="$package/module-cache" \
        xcrun swift test --skip-build --package-path "$package" --cache-path "$package/cache" \
        --scratch-path "$package/scratch" \
        -Xswiftc -module-cache-path -Xswiftc "$package/module-cache"
done

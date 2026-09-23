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
for directory in ['Models', 'Services/Engine', 'Services/Consistency']:
    sources.extend((app / directory).glob('*.swift'))
sources.extend(app / path for path in [
    'Services/Protocols/ServiceProtocols.swift', 'Services/Subscription/StoreKitFacade.swift',
    'Services/Subscription/LiveStoreKitFacade.swift',
    'Services/Subscription/StoreKitSubscriptionService.swift', 'ViewModels/PaywallViewModel.swift'
])
for mode in ['qa', 'ordinary']:
    package = base / mode
    for directory in ['Sources', 'Tests', 'tmp', 'cache', 'module-cache']:
        (package / directory).mkdir(parents=True, exist_ok=True)
    test = root / 'ios/RepToday/RepTodayTests/StoreKitPaywallDiagnosticsTests.swift'
    for directory, paths in [('Sources', sources), ('Tests', [test])]:
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
        xcrun swift test --package-path "$package" --cache-path "$package/cache" \
        --scratch-path "$package/scratch" \
        -Xswiftc -module-cache-path -Xswiftc "$package/module-cache"
done

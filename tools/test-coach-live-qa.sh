#!/bin/bash
set -euo pipefail
set +x
umask 077
if [[ $# != 0 ]]; then
    echo 'usage: tools/test-coach-live-qa.sh' >&2
    exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
private_build="$repo_root/build/coach-live-qa"
mkdir -p "$private_build"
export CLANG_MODULE_CACHE_PATH="$private_build/module-cache"
app="$repo_root/ios/RepToday/RepToday"
sources=(tools/coach-production-deploy.swift tools/coach-live-qa.swift
    "$app"/Models/*.swift "$app/Services/Protocols/ServiceProtocols.swift"
    "$app"/Services/Consistency/*.swift "$app"/Services/Engine/*.swift
    "$app/Services/Progress/ProgressAnalytics.swift" "$app/Services/Coach/CoachAnalyticsInsight.swift"
    "$app/Services/Coach/CoachContextBundle.swift" "$app/Services/Coach/CoachProxyClient.swift")
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_LIVE_QA_TESTS \
    -module-cache-path "$private_build/module-cache" "${sources[@]}" tools/coach-live-qa-tests.swift \
    -o "$private_build/coach-live-qa-tests"
"$private_build/coach-live-qa-tests"
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS \
    -module-cache-path "$private_build/module-cache" "${sources[@]}" -o "$private_build/coach-live-qa"

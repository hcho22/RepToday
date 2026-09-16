#!/bin/bash
set -euo pipefail
set +x
umask 077
if [[ $# != 0 ]]; then
    echo 'usage: tools/validate-coach-live.sh (never pass a credential)' >&2
    exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
if [[ "$(git rev-parse --show-toplevel)" != "$repo_root" ]] ||
   [[ "$(git branch --show-current)" != 'fm/reptoday-ai-coach-proxy-live-qa' ]] ||
   [[ -n "$(git status --porcelain)" ]]; then
    echo 'blocked: live QA requires the clean reviewed Coach task branch' >&2
    exit 78
fi
private_build="$repo_root/build/coach-live-qa"
mkdir -p "$private_build"
export CLANG_MODULE_CACHE_PATH="$private_build/module-cache"
app="$repo_root/ios/RepToday/RepToday"
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS \
    -module-cache-path "$private_build/module-cache" \
    "$repo_root/tools/coach-production-deploy.swift" "$repo_root/tools/coach-live-qa.swift" \
    "$app"/Models/*.swift "$app/Services/Protocols/ServiceProtocols.swift" \
    "$app"/Services/Consistency/*.swift "$app"/Services/Engine/*.swift \
    "$app/Services/Progress/ProgressAnalytics.swift" "$app/Services/Coach/CoachAnalyticsInsight.swift" \
    "$app/Services/Coach/CoachContextBundle.swift" "$app/Services/Coach/CoachProxyClient.swift" \
    -o "$private_build/coach-live-qa"
exec "$private_build/coach-live-qa"

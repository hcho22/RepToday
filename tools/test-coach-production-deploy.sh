#!/bin/bash
set -euo pipefail
set +x
umask 077
if [[ $# != 0 ]]; then
    echo 'usage: tools/test-coach-production-deploy.sh' >&2
    exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
private_build="$repo_root/build/coach-production-deploy"
mkdir -p "$private_build"
export CLANG_MODULE_CACHE_PATH="$private_build/module-cache"
node --test tools/coach-production-deploy.test.mjs
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS \
    -module-cache-path "$private_build/module-cache" \
    tools/coach-production-deploy.swift tools/coach-production-deploy-tests.swift \
    -o "$private_build/coach-production-deploy-tests"
"$private_build/coach-production-deploy-tests" "$repo_root" "$(command -v node)"
xcrun swiftc -parse-as-library -warnings-as-errors \
    -module-cache-path "$private_build/module-cache" \
    tools/coach-production-deploy.swift -o "$private_build/coach-production-deploy"

#!/bin/bash
set -euo pipefail
set +x
umask 077

if [[ $# != 0 ]]; then
    echo 'usage: tools/deploy-coach-production.sh (never pass a credential)' >&2
    exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
# This launch must use reviewed, committed code in the isolated task branch.
if [[ "$(git rev-parse --show-toplevel)" != "$repo_root" ]] ||
   [[ "$(git branch --show-current)" != 'fm/reptoday-ai-coach-proxy-live-qa' ]] ||
   [[ -n "$(git status --porcelain)" ]]; then
    echo 'blocked: launch requires the clean reviewed Coach task branch' >&2
    exit 78
fi
node_bin=$(command -v node)
private_build="$repo_root/build/coach-production-deploy"
mkdir -p "$private_build"
export CLANG_MODULE_CACHE_PATH="$private_build/module-cache"
xcrun swiftc -parse-as-library -warnings-as-errors \
    -module-cache-path "$private_build/module-cache" \
    "$repo_root/tools/coach-production-deploy.swift" \
    -o "$private_build/coach-production-deploy"
exec "$private_build/coach-production-deploy" --deploy "$repo_root" "$node_bin"

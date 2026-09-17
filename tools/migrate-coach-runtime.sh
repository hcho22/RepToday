#!/bin/bash
set -euo pipefail
set +x
umask 077
unset NODE_OPTIONS NODE_DEBUG NODE_DEBUG_NATIVE
if [[ $# != 1 || ( $1 != --stage && $1 != --release && $1 != --hold ) ]]; then
    echo 'usage: tools/migrate-coach-runtime.sh --stage|--release|--hold (never pass credentials)' >&2
    exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
if [[ "$(git rev-parse --show-toplevel)" != "$repo_root" ||
      "$(git branch --show-current)" != 'fm/reptoday-ai-coach-proxy-live-qa' ||
      -n "$(git status --porcelain)" ]]; then
    echo 'blocked: runtime migration requires the clean reviewed Coach task branch' >&2
    exit 78
fi
node_bin=$(command -v node)
if [[ "$("$node_bin" -p 'process.versions.node.split(".")[0]')" != 20 ]]; then
    echo 'blocked: use the reviewed installed Node 20 environment' >&2
    exit 78
fi
private_build="$repo_root/build/coach-runtime-migration"
mkdir -p "$private_build"
# Refuse known local runtime incompatibility before any Keychain/UI/control-plane access.
# Emergency hold-only closure must remain available even when code/runtime validation fails.
if [[ $1 != --hold ]]; then
    if ! (cd proxy && "$node_bin" node_modules/vitest/vitest.mjs run >/dev/null 2>&1 &&
          "$node_bin" node_modules/typescript/bin/tsc --noEmit -p tsconfig.json >/dev/null 2>&1 &&
          "$node_bin" test/workerd-auth.mjs >/dev/null 2>&1); then
        echo 'blocked: offline proxy tests, typecheck or Worker runtime validation failed; no Keychain or production action' >&2
        exit 78
    fi
fi
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_RUNTIME_INTAKE_TESTS \
    -module-cache-path "$private_build/module-cache" \
    tools/coach-production-deploy.swift tools/coach-runtime-key-intake.swift tools/coach-runtime-migrate.swift \
    -o "$private_build/coach-runtime-migrate"
exec "$private_build/coach-runtime-migrate" "$1" "$repo_root" "$node_bin"

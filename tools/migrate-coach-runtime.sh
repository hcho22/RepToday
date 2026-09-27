#!/bin/bash
set -euo pipefail
set +x
umask 077
unset NODE_OPTIONS NODE_DEBUG NODE_DEBUG_NATIVE
usage() {
    echo 'usage: tools/migrate-coach-runtime.sh --keychain-preflight | --stage|--release|--hold [--auth-guard-diagnostics for stage/release only] (never pass credentials)'
}
if [[ $# == 1 && $1 == --help ]]; then
    usage
    echo 'Keychain preflight: eight sequential reads, discard each value; no coordinator or network. Native limits: 115s/read, 585s overall. Outer limits: 118s/read, 595s overall, at most 2s cleanup. No retries.'
    exit 0
fi
if [[ $# -lt 1 || $# -gt 2 ||
      ( $1 != --keychain-preflight && $1 != --stage && $1 != --release && $1 != --hold ) ||
      ( $# == 2 && ( $2 != --auth-guard-diagnostics || $1 == --hold || $1 == --keychain-preflight ) ) ]]; then
    usage >&2
    exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
# This branch precedes every production prerequisite, including git/Node/offline runtime
# checks. The supervisor can invoke only the single native preflight argument.
if [[ $1 == --keychain-preflight ]]; then
    private_build="$repo_root/build/coach-runtime-migration"
    mkdir -p "$private_build"
    xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_RUNTIME_INTAKE_TESTS \
        -module-cache-path "$private_build/module-cache" \
        tools/coach-production-deploy.swift tools/coach-runtime-key-intake.swift tools/coach-runtime-migrate.swift \
        tools/coach-keychain-preflight.swift -o "$private_build/coach-runtime-migrate"
    exec python3 tools/coach-keychain-preflight.py "$private_build/coach-runtime-migrate"
fi
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
    tools/coach-keychain-preflight.swift \
    -o "$private_build/coach-runtime-migrate"
exec "$private_build/coach-runtime-migrate" "$1" "$repo_root" "$node_bin" "${@:2}"

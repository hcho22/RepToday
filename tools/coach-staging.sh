#!/bin/bash
# Separate Coach staging Worker on workers.dev: deploy, inspect or tear down. Never touches the
# production script, zone, rules or custom domain. See docs/coach-runtime-authentication.md.
set -euo pipefail
set +x
umask 077
unset NODE_OPTIONS NODE_DEBUG NODE_DEBUG_NATIVE
usage() {
    echo 'usage: tools/coach-staging.sh --deploy|--teardown|--inspect (never pass credentials)'
}
if [[ $# != 1 || ( $1 != --deploy && $1 != --teardown && $1 != --inspect ) ]]; then
    usage >&2; exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
# The staging Worker pins the committed source revision it was deployed from.
if [[ "$(git rev-parse --show-toplevel)" != "$repo_root" || -n "$(git status --porcelain)" ]]; then
    echo 'blocked: staging requires a clean committed checkout' >&2
    exit 78
fi
node_bin=$(command -v node)
if [[ "$("$node_bin" -p 'process.versions.node.split(".")[0]')" != 20 ]]; then
    echo 'blocked: use the reviewed installed Node 20 environment' >&2
    exit 78
fi
# Teardown and inspection read no Keychain item; they need only the existing Wrangler login.
if [[ $1 != --deploy ]]; then
    exec "$node_bin" tools/coach-staging.mjs "$1" </dev/null
fi
if ! (cd proxy && "$node_bin" node_modules/vitest/vitest.mjs run >/dev/null 2>&1 &&
      "$node_bin" node_modules/typescript/bin/tsc --noEmit -p tsconfig.json >/dev/null 2>&1 &&
      "$node_bin" test/workerd-auth.mjs >/dev/null 2>&1); then
    echo 'blocked: offline proxy tests, typecheck or Worker runtime validation failed; no Keychain or Cloudflare action' >&2
    exit 78
fi
private_build="$repo_root/build/coach-staging"
mkdir -p "$private_build"
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_RUNTIME_INTAKE_TESTS -D COACH_STAGING_TOOL \
    -module-cache-path "$private_build/module-cache" \
    tools/coach-production-deploy.swift tools/coach-runtime-key-intake.swift tools/coach-runtime-migrate.swift \
    tools/coach-keychain-preflight.swift tools/coach-staging.swift -o "$private_build/coach-staging"
exec "$private_build/coach-staging" --deploy "$repo_root" "$node_bin"

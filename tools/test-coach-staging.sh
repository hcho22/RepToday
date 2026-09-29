#!/bin/bash
# Offline staging tooling gate: coordinator doubles, native reader scope, closed transcript and the
# credential-only-on-stdin pipe. No Keychain, network, Cloudflare or production action.
set -euo pipefail
set +x
umask 077
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
private_build="$repo_root/build/coach-staging"
mkdir -p "$private_build"
node --test tools/coach-staging.test.mjs
bash -n tools/coach-staging.sh
sources=(tools/coach-production-deploy.swift tools/coach-runtime-key-intake.swift tools/coach-runtime-migrate.swift
    tools/coach-keychain-preflight.swift tools/coach-staging.swift)
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_RUNTIME_INTAKE_TESTS -D COACH_STAGING_TOOL \
    -D COACH_STAGING_TESTS -module-cache-path "$private_build/module-cache" \
    "${sources[@]}" tools/coach-staging-tests.swift -o "$private_build/native-tests"
"$private_build/native-tests" "$repo_root" "$(command -v node)"
# Compile the real staging entry without executing its Keychain/Cloudflare path.
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_RUNTIME_INTAKE_TESTS -D COACH_STAGING_TOOL \
    -module-cache-path "$private_build/module-cache" "${sources[@]}" -o "$private_build/coach-staging-compile-check"
# The real wrapper refuses unknown operations before any credential or network access.
set +e
bash tools/coach-staging.sh --bogus >/dev/null 2>&1; status=$?
set -e
[[ $status == 64 ]]
echo 'passed: staging coordinator, native reader and wrapper refusal; no Keychain, network or Cloudflare access'

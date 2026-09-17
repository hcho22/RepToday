#!/bin/bash
set -euo pipefail
set +x
umask 077
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
private_build="$repo_root/build/coach-runtime-migration"
mkdir -p "$private_build"
node --test tools/coach-runtime-migrate.test.mjs
sources=(tools/coach-production-deploy.swift tools/coach-runtime-key-intake.swift tools/coach-runtime-migrate.swift)
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_RUNTIME_INTAKE_TESTS \
    -D COACH_RUNTIME_MIGRATION_TESTS -module-cache-path "$private_build/module-cache" \
    "${sources[@]}" tools/coach-runtime-migrate-tests.swift -o "$private_build/native-tests"
"$private_build/native-tests" "$repo_root" "$(command -v node)"
# Compile only. Never execute the real Security/AppKit/native provisioning entry in this suite.
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_DEPLOY_TESTS -D COACH_RUNTIME_INTAKE_TESTS \
    -module-cache-path "$private_build/module-cache" "${sources[@]}" -o "$private_build/coach-runtime-migrate"

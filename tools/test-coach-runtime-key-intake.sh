#!/bin/bash
set -euo pipefail
set +x
umask 077
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
private_build="$repo_root/build/coach-runtime-intake"
mkdir -p "$private_build"
sources=("$repo_root/tools/coach-runtime-key-intake.swift")
xcrun swiftc -parse-as-library -warnings-as-errors -D COACH_RUNTIME_INTAKE_TESTS \
    -module-cache-path "$private_build/module-cache" "${sources[@]}" "$repo_root/tools/coach-runtime-key-intake-tests.swift" \
    -o "$private_build/runtime-intake-tests"
"$private_build/runtime-intake-tests"
xcrun swiftc -parse-as-library -warnings-as-errors -module-cache-path "$private_build/module-cache" \
    "${sources[@]}" -o "$private_build/coach-runtime-key-intake"

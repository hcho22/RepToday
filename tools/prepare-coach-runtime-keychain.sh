#!/bin/bash
set -euo pipefail
set +x
umask 077
if [[ $# -gt 1 || ( $# == 1 && $1 != --check ) ]]; then
    echo 'usage: tools/prepare-coach-runtime-keychain.sh [--check]; never pass credentials' >&2
    exit 64
fi
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
private_build="$repo_root/build/coach-runtime-intake"
mkdir -p "$private_build"
xcrun swiftc -parse-as-library -warnings-as-errors -module-cache-path "$private_build/module-cache" \
    "$repo_root/tools/coach-runtime-key-intake.swift" -o "$private_build/coach-runtime-key-intake"
exec "$private_build/coach-runtime-key-intake" "$@"

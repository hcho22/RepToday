#!/bin/bash

# Run locally on the captain's Mac. The native secure-input dialog sends credentials directly
# to Security.framework; no credential passes through shell arguments, environment, or files.
set -euo pipefail
set +x
umask 077

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
    echo 'usage: tools/prepare-coach-keychain.sh [--check] (never pass a credential)' >&2
    exit 64
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
private_build="$repo_root/build/coach-key-intake"
mkdir -p "$private_build"
export CLANG_MODULE_CACHE_PATH="$private_build/module-cache"

xcrun swiftc \
    -warnings-as-errors \
    -module-cache-path "$private_build/module-cache" \
    "$repo_root/tools/coach-key-intake.swift" \
    -o "$private_build/coach-key-intake"

exec "$private_build/coach-key-intake" "$@"

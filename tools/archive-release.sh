#!/bin/bash

# Archive Rep Today with the production telemetry abuse-deterrence token injected from the
# captain-owned macOS login Keychain. The token never appears in source, the generated Xcode
# project, a committed xcconfig, or this command's arguments: xcodebuild receives only the path to
# a mode-600 temporary xcconfig, which is removed on every exit.

set -euo pipefail
set +x

readonly KEYCHAIN_SERVICE="com.reptoday.analytics.production"
readonly KEYCHAIN_ACCOUNT="release-archive"

if [[ $# -lt 1 ]]; then
    echo "usage: tools/archive-release.sh <archive-path> [additional xcodebuild arguments]" >&2
    exit 64
fi

archive_path=$1
shift

repo_root=$(git rev-parse --show-toplevel)
private_dir=$(mktemp -d "${TMPDIR:-/tmp}/reptoday-release.XXXXXX")
private_xcconfig="$private_dir/TelemetrySecrets.xcconfig"

cleanup() {
    rm -f "$private_xcconfig"
    rmdir "$private_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

secret=$(security find-generic-password \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w 2>/dev/null) || {
    echo "error: production telemetry secret is missing from the macOS Keychain" >&2
    echo "see artifacts/reports/production-telemetry/validation.md for provisioning and rotation" >&2
    exit 78
}

if [[ ! "$secret" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo "error: production telemetry secret has an unexpected format; rotate it before archiving" >&2
    exit 78
fi

umask 077
printf 'REPTODAY_ANALYTICS_SECRET = %s\n' "$secret" > "$private_xcconfig"
unset secret

xcodebuild \
    -project "$repo_root/ios/RepToday/RepToday.xcodeproj" \
    -scheme RepToday \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -xcconfig "$private_xcconfig" \
    archive \
    "$@"

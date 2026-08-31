#!/bin/bash

# Archive Rep Today with the production telemetry abuse-deterrence token injected from the
# captain-owned macOS login Keychain. The token never appears in source, the generated Xcode
# project, a committed xcconfig, or this command's arguments: xcodebuild receives only the path to
# a mode-600 temporary xcconfig, which is removed on every exit.

set -euo pipefail
set +x

readonly KEYCHAIN_SERVICE="com.reptoday.analytics.production"
readonly KEYCHAIN_ACCOUNT="release-archive"
readonly EXPECTED_ENDPOINT="https://sensible-spider-810.convex.site"

if [[ $# -lt 1 ]]; then
    echo "usage: tools/archive-release.sh <archive-path> [additional xcodebuild arguments]" >&2
    exit 64
fi

archive_path=$1
shift

for argument in "$@"; do
    case "$argument" in
        -configuration|-configuration=*|-xcconfig|-xcconfig=*|-project|-project=*|-scheme|-scheme=*|-destination|-destination=*|-archivePath|-archivePath=*|-showBuildSettings|-showBuildSettingsForIndex|REPTODAY_ANALYTICS_ENDPOINT=*|REPTODAY_ANALYTICS_ENDPOINT\[*|REPTODAY_ANALYTICS_SECRET=*|REPTODAY_ANALYTICS_SECRET\[*|INFOPLIST_KEY_RepTodayAnalyticsEndpoint=*|INFOPLIST_KEY_RepTodayAnalyticsSecret=*)
            echo "error: additional arguments cannot override the archive or telemetry configuration" >&2
            exit 64
            ;;
    esac
done

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

xcodebuild \
    -project "$repo_root/ios/RepToday/RepToday.xcodeproj" \
    -scheme RepToday \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -xcconfig "$private_xcconfig" \
    archive \
    "$@"

archive_plist="$archive_path/Products/Applications/RepToday.app/Info.plist"
if [[ ! -f "$archive_plist" ]]; then
    unset secret
    echo "error: archive did not produce the expected RepToday.app" >&2
    exit 1
fi

built_endpoint=$(/usr/libexec/PlistBuddy -c 'Print :RepTodayAnalyticsEndpoint' "$archive_plist" 2>/dev/null || true)
built_secret=$(/usr/libexec/PlistBuddy -c 'Print :RepTodayAnalyticsSecret' "$archive_plist" 2>/dev/null || true)
if [[ "$built_endpoint" != "$EXPECTED_ENDPOINT" || "$built_secret" != "$secret" ]]; then
    unset secret built_secret
    echo "error: archived app does not contain the expected production telemetry configuration" >&2
    exit 1
fi
unset secret built_secret

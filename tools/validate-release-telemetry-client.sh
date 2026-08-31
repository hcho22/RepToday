#!/bin/bash

# Build the real Release app with the Keychain-backed production configuration, install it on a
# simulator, and compare a fresh opted-in launch with the same binary launched opted out. The
# production row read is the live positive/negative control; the in-process URLProtocol suite is the
# complementary proof that the negative leg creates no request at all, not merely no stored row.

set -euo pipefail
set +x

readonly DEPLOYMENT='hcho22:reptoday-telemetry:prod'
readonly EXPECTED_ENDPOINT='https://sensible-spider-810.convex.site'
readonly KEYCHAIN_SERVICE='com.reptoday.analytics.production'
readonly KEYCHAIN_ACCOUNT='release-archive'
readonly BUNDLE_ID='com.reptoday.app'

repo_root=$(git rev-parse --show-toplevel)
simulator_id=${1:-$(xcrun simctl list devices available | awk '/iPhone 16 \(/ { gsub(/[()]/, "", $3); print $3; exit }')}

if [[ -z "$simulator_id" ]]; then
    echo 'error: no available iPhone 16 simulator' >&2
    exit 69
fi

secret=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null) || {
    echo 'error: production telemetry token is unavailable in the macOS Keychain' >&2
    exit 78
}

private_dir=$(mktemp -d "${TMPDIR:-/tmp}/reptoday-release-client.XXXXXX")
private_xcconfig="$private_dir/TelemetrySecrets.xcconfig"
derived_data="$private_dir/DerivedData"
trap 'rm -rf "$private_dir"' EXIT HUP INT TERM
umask 077
printf 'REPTODAY_ANALYTICS_SECRET = %s\n' "$secret" > "$private_xcconfig"

xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
xcodebuild \
    -project "$repo_root/ios/RepToday/RepToday.xcodeproj" \
    -scheme RepToday \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived_data" \
    -xcconfig "$private_xcconfig" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= \
    clean build > "$private_dir/xcodebuild.log"

app_path="$derived_data/Build/Products/Release-iphonesimulator/RepToday.app"
plist_path="$app_path/Info.plist"
built_endpoint=$(/usr/libexec/PlistBuddy -c 'Print :RepTodayAnalyticsEndpoint' "$plist_path")
built_secret=$(/usr/libexec/PlistBuddy -c 'Print :RepTodayAnalyticsSecret' "$plist_path")
if [[ "$built_endpoint" != "$EXPECTED_ENDPOINT" || "$built_secret" != "$secret" ]]; then
    unset secret built_secret
    echo 'error: Release artifact endpoint/token do not match the private production configuration' >&2
    exit 1
fi
unset secret built_secret

launch_and_read_id() {
    local consent=$1
    xcrun simctl uninstall "$simulator_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$simulator_id" "$app_path" >/dev/null
    if [[ "$consent" == 'off' ]]; then
        xcrun simctl launch --terminate-running-process "$simulator_id" "$BUNDLE_ID" \
            -AppState.analyticsEnabled NO >/dev/null
    else
        xcrun simctl launch --terminate-running-process "$simulator_id" "$BUNDLE_ID" >/dev/null
    fi
    sleep 8
    local container
    container=$(xcrun simctl get_app_container "$simulator_id" "$BUNDLE_ID" data)
    /usr/libexec/PlistBuddy -c 'Print :AppState.installId' \
        "$container/Library/Preferences/$BUNDLE_ID.plist"
    xcrun simctl terminate "$simulator_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

opted_in_id=$(launch_and_read_id on)
opted_out_id=$(launch_and_read_id off)

npx convex run reconcile:eventsForInstalls \
    "{\"installIds\":[\"$opted_in_id\",\"$opted_out_id\"]}" \
    --deployment "$DEPLOYMENT" > "$private_dir/rows.json"

OPTED_IN_ID="$opted_in_id" \
OPTED_OUT_ID="$opted_out_id" \
ROWS_PATH="$private_dir/rows.json" \
node <<'NODE'
const fs = require("fs");
const rows = JSON.parse(fs.readFileSync(process.env.ROWS_PATH, "utf8"));
const optedIn = rows.filter((row) => row.installId === process.env.OPTED_IN_ID);
const optedOut = rows.filter((row) => row.installId === process.env.OPTED_OUT_ID);
const result = {
  release_endpoint: "https://sensible-spider-810.convex.site",
  release_token_injected: true,
  opted_in_rows: optedIn.length,
  opted_in_app_install_rows: optedIn.filter((row) => row.name === "app_install").length,
  opted_out_rows: optedOut.length,
};
console.log(JSON.stringify(result, null, 2));
if (result.opted_in_rows < 1 || result.opted_in_app_install_rows !== 1 || result.opted_out_rows !== 0) {
  process.exit(1);
}
NODE

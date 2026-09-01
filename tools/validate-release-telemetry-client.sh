#!/bin/bash

# Build the real Release app with the Keychain-backed production configuration, install it on a
# simulator, and compare a reserved opted-in validation launch with the same binary launched opted
# out. The
# production row read is the live positive/negative control; the in-process URLProtocol suite is the
# complementary proof that the negative leg creates no request at all, not merely no stored row.

set -euo pipefail
set +x

readonly DEPLOYMENT='hcho22:reptoday-telemetry:prod'
readonly EXPECTED_ENDPOINT='https://sensible-spider-810.convex.site'
readonly KEYCHAIN_SERVICE='com.reptoday.analytics.production'
readonly KEYCHAIN_ACCOUNT='release-archive'
readonly BUNDLE_ID='com.reptoday.app'
readonly INSTALL_ID_DEADLINE_SECONDS=10
readonly DELIVERY_DEADLINE_SECONDS=15
readonly DELIVERY_POLL_SECONDS=1
readonly VALIDATION_ID_PREFIX='prod-validation-'

repo_root=$(git rev-parse --show-toplevel)
simulator_id=${1:-$(xcrun simctl list devices available | awk '/iPhone 16 \(/ { gsub(/[()]/, "", $3); print $3; exit }')}
convex_bin="$repo_root/node_modules/.bin/convex"
run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
opted_in_id="${VALIDATION_ID_PREFIX}release-${run_stamp}-on"
opted_out_id="${VALIDATION_ID_PREFIX}release-${run_stamp}-off"

if [[ -z "$simulator_id" ]]; then
    echo 'error: no available iPhone 16 simulator' >&2
    exit 69
fi

if [[ ! -x "$convex_bin" ]]; then
    echo 'error: Convex CLI is unavailable; run npm ci first' >&2
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

run_with_timeout() {
    local timeout_seconds=$1
    shift
    /usr/bin/perl -e 'my $timeout = shift @ARGV; alarm $timeout; exec @ARGV or die "exec failed: $!\n";' \
        "$timeout_seconds" "$@"
}

read_install_id() {
    local deadline=$((SECONDS + INSTALL_ID_DEADLINE_SECONDS))
    local container
    local install_id
    local plist_path

    while (( SECONDS < deadline )); do
        container=$(xcrun simctl get_app_container "$simulator_id" "$BUNDLE_ID" data 2>/dev/null || true)
        plist_path="$container/Library/Preferences/$BUNDLE_ID.plist"
        if [[ -n "$container" && -f "$plist_path" ]]; then
            install_id=$(/usr/libexec/PlistBuddy -c 'Print :AppState.installId' "$plist_path" 2>/dev/null || true)
            if [[ -n "$install_id" ]]; then
                printf '%s\n' "$install_id"
                return 0
            fi
        fi
        sleep 0.25
    done

    echo 'error: launched Release app did not persist an install identifier' >&2
    return 1
}

await_delivery_state() {
    local install_id=$1
    local expected=$2
    local event_name=$3
    local deadline=$((SECONDS + DELIVERY_DEADLINE_SECONDS))
    local poll_path="$private_dir/delivery-$expected.json"
    local last_query_succeeded=false
    local remaining

    while (( SECONDS < deadline )); do
        last_query_succeeded=false
        remaining=$((deadline - SECONDS))
        if run_with_timeout "$remaining" "$convex_bin" run reconcile:eventsForInstalls \
            "{\"installIds\":[\"$install_id\"]}" \
            --deployment "$DEPLOYMENT" \
            --typecheck disable \
            --codegen disable > "$poll_path" 2>> "$private_dir/convex-query.log"
        then
            last_query_succeeded=true
            if INSTALL_ID="$install_id" EXPECTED_EVENT="$event_name" ROWS_PATH="$poll_path" node <<'NODE'
const fs = require("fs");
const rows = JSON.parse(fs.readFileSync(process.env.ROWS_PATH, "utf8"));
const found = rows.some(
  (row) => row.installId === process.env.INSTALL_ID && row.name === process.env.EXPECTED_EVENT,
);
process.exit(found ? 0 : 1);
NODE
            then
                [[ "$expected" == present ]]
                return
            fi
        fi
        sleep "$DELIVERY_POLL_SECONDS"
    done

    [[ "$expected" == absent && "$last_query_succeeded" == true ]]
}

seed_validation_identity() {
    local install_id=$1
    local container
    local preferences_path
    container=$(xcrun simctl get_app_container "$simulator_id" "$BUNDLE_ID" data)
    preferences_path="$container/Library/Preferences/$BUNDLE_ID.plist"
    /usr/libexec/PlistBuddy \
        -c "Add :AppState.installId string $install_id" \
        -c 'Add :AppState.firstLaunchUnknown bool true' \
        "$preferences_path" >/dev/null
}

launch_and_validate_id() {
    local consent=$1
    local install_id=$2
    local persisted_install_id
    local delivery_ok=true
    xcrun simctl uninstall "$simulator_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$simulator_id" "$app_path" >/dev/null
    seed_validation_identity "$install_id"
    if [[ "$consent" == 'off' ]]; then
        xcrun simctl launch --terminate-running-process "$simulator_id" "$BUNDLE_ID" \
            -AppState.analyticsEnabled NO >/dev/null
    else
        xcrun simctl launch --terminate-running-process "$simulator_id" "$BUNDLE_ID" >/dev/null
    fi
    persisted_install_id=$(read_install_id)
    if [[ "$persisted_install_id" != "$install_id" ]]; then
        xcrun simctl terminate "$simulator_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
        echo 'error: Release app did not retain the reserved validation install identifier' >&2
        return 1
    fi
    if [[ "$consent" == 'off' ]]; then
        await_delivery_state "$install_id" absent onboarding_started || delivery_ok=false
    else
        await_delivery_state "$install_id" present onboarding_started || delivery_ok=false
    fi
    xcrun simctl terminate "$simulator_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    if [[ "$delivery_ok" != true ]]; then
        echo "error: Release telemetry delivery did not reach the expected $consent state within ${DELIVERY_DEADLINE_SECONDS}s" >&2
        return 1
    fi
    printf '%s\n' "$install_id"
}

launch_and_validate_id on "$opted_in_id" >/dev/null
launch_and_validate_id off "$opted_out_id" >/dev/null

if ! run_with_timeout "$DELIVERY_DEADLINE_SECONDS" "$convex_bin" run reconcile:eventsForInstalls \
    "{\"installIds\":[\"$opted_in_id\",\"$opted_out_id\"]}" \
    --deployment "$DEPLOYMENT" \
    --typecheck disable \
    --codegen disable > "$private_dir/rows.json" 2>> "$private_dir/convex-query.log"
then
    echo "error: final production telemetry query did not complete within ${DELIVERY_DEADLINE_SECONDS}s" >&2
    exit 1
fi

OPTED_IN_ID="$opted_in_id" \
OPTED_OUT_ID="$opted_out_id" \
VALIDATION_ID_PREFIX="$VALIDATION_ID_PREFIX" \
ROWS_PATH="$private_dir/rows.json" \
node <<'NODE'
const fs = require("fs");
const rows = JSON.parse(fs.readFileSync(process.env.ROWS_PATH, "utf8"));
const optedIn = rows.filter((row) => row.installId === process.env.OPTED_IN_ID);
const optedOut = rows.filter((row) => row.installId === process.env.OPTED_OUT_ID);
const result = {
  release_endpoint: "https://sensible-spider-810.convex.site",
  release_token_injected: true,
  validation_identity_prefix: process.env.VALIDATION_ID_PREFIX,
  opted_in_install_id: process.env.OPTED_IN_ID,
  opted_out_install_id: process.env.OPTED_OUT_ID,
  opted_in_rows: optedIn.length,
  opted_in_onboarding_started_rows: optedIn.filter((row) => row.name === "onboarding_started").length,
  opted_out_rows: optedOut.length,
};
console.log(JSON.stringify(result, null, 2));
if (result.opted_in_rows < 1 || result.opted_in_onboarding_started_rows !== 1 || result.opted_out_rows !== 0) {
  process.exit(1);
}
NODE

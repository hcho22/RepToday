#!/bin/bash

# One-shot, secret-safe production boundary validation. Reads the same Keychain item as the Release
# archive path, never prints the value, and reports only statuses and row counts. The rate-limit leg
# deliberately uses a props key Convex refuses after the limiter, so the first 60 attempts consume
# budget without polluting the evidence table and the 61st can prove 429/no insert.

set -euo pipefail
set +x

readonly DEPLOYMENT='hcho22:reptoday-telemetry:prod'
readonly ENDPOINT='https://sensible-spider-810.convex.site/logEvent'
readonly KEYCHAIN_SERVICE='com.reptoday.analytics.production'
readonly KEYCHAIN_ACCOUNT='release-archive'
readonly CURL_CONNECT_TIMEOUT_SECONDS=3
readonly CURL_MAX_TIME_SECONDS=5
readonly MAX_RATE_WINDOW_ATTEMPTS=3

run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
smoke_id="prod-smoke-$run_stamp"
missing_id="prod-missing-$run_stamp"
wrong_id="prod-wrong-$run_stamp"
rate_id=''
client_ts=$(($(date +%s) * 1000))
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/reptoday-production-validation.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
umask 077

secret=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null) || {
    echo 'error: production telemetry token is unavailable in the macOS Keychain' >&2
    exit 78
}
secret_header_config="$temp_dir/curl-secret.conf"
printf 'header = "X-RepToday-Analytics-Secret: %s"\n' "$secret" > "$secret_header_config"
unset secret

smoke_body=$(printf '{"name":"app_install","installId":"%s","clientTs":%s,"props":{"install_week":"production-validation","validation_marker":"%s"}}' "$smoke_id" "$client_ts" "$run_stamp")
missing_body=$(printf '{"name":"session_started","installId":"%s","clientTs":%s,"props":{}}' "$missing_id" "$client_ts")
wrong_body=$(printf '{"name":"session_started","installId":"%s","clientTs":%s,"props":{}}' "$wrong_id" "$client_ts")
post() {
    local response_file=$1
    local body=$2
    shift 2
    curl -sS \
        --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" \
        --max-time "$CURL_MAX_TIME_SECONDS" \
        -o "$response_file" \
        -w '%{http_code}' \
        -X POST "$ENDPOINT" \
        -H 'Content-Type: application/json' \
        "$@" \
        --data "$body" || true
}

wait_for_fresh_rate_window() {
    local second
    second=$((10#$(date -u '+%S')))
    if (( second > 2 )); then
        sleep $((61 - second))
    fi
}

rate_window() {
    echo "$(($(date +%s) / 60))"
}

run_rate_attempt() {
    local started_window
    local status
    started_window=$(rate_window)
    rate_400=0
    rate_429=0
    rate_other=0

    for _ in $(seq 1 61); do
        if [[ "$(rate_window)" != "$started_window" ]]; then
            return 1
        fi
        status=$(post "$temp_dir/rate" "$rate_body" --config "$secret_header_config")
        case "$status" in
            400) rate_400=$((rate_400 + 1)) ;;
            429) rate_429=$((rate_429 + 1)) ;;
            *) rate_other=$((rate_other + 1)) ;;
        esac
        if [[ "$(rate_window)" != "$started_window" ]]; then
            return 1
        fi
    done
}

smoke_status=$(post "$temp_dir/smoke" "$smoke_body" --config "$secret_header_config")
missing_status=$(post "$temp_dir/missing" "$missing_body")
wrong_status=$(post "$temp_dir/wrong" "$wrong_body" -H 'X-RepToday-Analytics-Secret: wrong-production-validation-token')

rate_attempt_complete=false
for rate_attempt in $(seq 1 "$MAX_RATE_WINDOW_ATTEMPTS"); do
    wait_for_fresh_rate_window
    rate_id="prod-rate-$run_stamp-$rate_attempt"
    # `$invalid` below is the intentional literal invalid Convex field name.
    # shellcheck disable=SC2016
    rate_body=$(printf '{"name":"session_started","installId":"%s","clientTs":%s,"props":{"$invalid":"rate-validation"}}' "$rate_id" "$client_ts")
    if run_rate_attempt; then
        rate_attempt_complete=true
        break
    fi
done

if [[ "$rate_attempt_complete" != true ]]; then
    echo "error: rate-limit validation crossed $MAX_RATE_WINDOW_ATTEMPTS consecutive server-minute windows" >&2
    exit 1
fi
unset smoke_body missing_body wrong_body rate_body

npx convex run reconcile:eventsForInstalls \
    "{\"installIds\":[\"$smoke_id\",\"$missing_id\",\"$wrong_id\",\"$rate_id\"]}" \
    --deployment "$DEPLOYMENT" > "$temp_dir/rows.json"

SMOKE_STATUS="$smoke_status" \
MISSING_STATUS="$missing_status" \
WRONG_STATUS="$wrong_status" \
RATE_400="$rate_400" \
RATE_429="$rate_429" \
RATE_OTHER="$rate_other" \
SMOKE_ID="$smoke_id" \
MISSING_ID="$missing_id" \
WRONG_ID="$wrong_id" \
RATE_ID="$rate_id" \
ROWS_PATH="$temp_dir/rows.json" \
node <<'NODE'
const fs = require("fs");
const rows = JSON.parse(fs.readFileSync(process.env.ROWS_PATH, "utf8"));
const by = (id) => rows.filter((row) => row.installId === id);
const result = {
  smoke_install_id: process.env.SMOKE_ID,
  smoke_status: process.env.SMOKE_STATUS,
  missing_status: process.env.MISSING_STATUS,
  wrong_status: process.env.WRONG_STATUS,
  rate_first_sixty_status_400: Number(process.env.RATE_400),
  rate_rejected_status_429: Number(process.env.RATE_429),
  rate_other_statuses: Number(process.env.RATE_OTHER),
  smoke_rows: by(process.env.SMOKE_ID).length,
  missing_rows: by(process.env.MISSING_ID).length,
  wrong_rows: by(process.env.WRONG_ID).length,
  rate_rows: by(process.env.RATE_ID).length,
  smoke_marker_ok: by(process.env.SMOKE_ID)[0]?.props?.validation_marker !== undefined,
};
console.log(JSON.stringify(result, null, 2));
const valid =
  result.smoke_status === "204" &&
  result.missing_status === "401" &&
  result.wrong_status === "401" &&
  result.rate_first_sixty_status_400 === 60 &&
  result.rate_rejected_status_429 === 1 &&
  result.rate_other_statuses === 0 &&
  result.smoke_rows === 1 &&
  result.missing_rows === 0 &&
  result.wrong_rows === 0 &&
  result.rate_rows === 0 &&
  result.smoke_marker_ok;
if (!valid) process.exit(1);
NODE

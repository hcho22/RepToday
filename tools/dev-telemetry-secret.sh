#!/bin/bash

# Owns the development usage-data shared secret: the value a Debug build sends to the dev sink in
# the X-RepToday-Analytics-Secret header. It lives in two places only, this Mac's login Keychain and
# the dev Convex deployment's ANALYTICS_SHARED_SECRET variable, and reaches a Debug build through
# the same route Release uses (tools/telemetry-keychain.sh): Keychain -> private xcconfig.
#
#   install   Keychain -> ios/RepToday/Config/DebugTelemetry.local.xcconfig (untracked, mode 600).
#             Run once per checkout; Debug builds made afterwards send usage data to the dev sink.
#   remove    Delete that file; later Debug builds send no usage data.
#   verify    Status codes only: the Keychain value is accepted (204); a missing value, a wrong
#             value and every --refused-value-file value are refused (401).
#   adopt     Copy the dev deployment's current value into this Mac's Keychain, then verify. For a
#             second Mac. Changes no deployment.
#   rotate    Generate a new value, store it in the Keychain, set it on the dev deployment, then
#             verify. Every other Mac and every already-built Debug app is refused from then on.
#
# Nothing here prints a value, passes one as a command argument, or can target production: every
# deployment command names the deployment read from the Debug REPTODAY_ANALYTICS_ENDPOINT build
# setting, prints it first, and stops if it is the Release one.

set -euo pipefail
set +x

readonly DEPLOYMENT_VARIABLE='ANALYTICS_SHARED_SECRET'
readonly SECRET_HEADER='X-RepToday-Analytics-Secret'
readonly CURL_CONNECT_TIMEOUT_SECONDS=5
readonly CURL_MAX_TIME_SECONDS=15
readonly CONVEX_TIMEOUT_SECONDS=60
readonly ACCEPTANCE_DEADLINE_SECONDS=60
readonly VALIDATION_ID_PREFIX='dev-validation-'

repo_root=$(git rev-parse --show-toplevel)
# shellcheck source=tools/telemetry-keychain.sh
source "$repo_root/tools/telemetry-keychain.sh"

readonly project="$repo_root/ios/RepToday/RepToday.xcodeproj"
readonly local_xcconfig="$repo_root/ios/RepToday/Config/DebugTelemetry.local.xcconfig"
readonly convex_bin="$repo_root/node_modules/.bin/convex"

usage() {
    echo 'usage: tools/dev-telemetry-secret.sh <install|remove|verify|adopt|rotate> [--refused-value-file <path>]...' >&2
    exit 64
}

fail() {
    local status=$1
    shift
    echo "error: $*" >&2
    exit "$status"
}

run_with_timeout() {
    local timeout_seconds=$1
    shift
    /usr/bin/perl -e 'my $timeout = shift @ARGV; alarm $timeout; exec @ARGV or die "exec failed: $!\n";' \
        "$timeout_seconds" "$@"
}

endpoint_for() {
    xcodebuild -project "$project" -target RepToday -configuration "$1" -showBuildSettings 2>/dev/null \
        | awk -F' = ' '$1 ~ /^ *REPTODAY_ANALYTICS_ENDPOINT$/ { print $2; exit }'
}

deployment_name_of() {
    [[ "$1" =~ ^https://([a-z]+-[a-z]+-[0-9]+)\.convex\.site$ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

# Sets dev_deployment and dev_endpoint, printing the target, or stops. Called before every command
# that reads or changes a deployment.
dev_deployment=''
dev_endpoint=''
resolve_dev_deployment() {
    local debug_origin release_origin release_deployment
    debug_origin=$(endpoint_for Debug)
    release_origin=$(endpoint_for Release)
    dev_deployment=$(deployment_name_of "$debug_origin") \
        || fail 78 'the Debug REPTODAY_ANALYTICS_ENDPOINT build setting does not name a Convex deployment'
    release_deployment=$(deployment_name_of "$release_origin") \
        || fail 78 'the Release REPTODAY_ANALYTICS_ENDPOINT build setting does not name a Convex deployment, so the target cannot be told apart from production'
    echo "target deployment: $dev_deployment (dev: the Debug REPTODAY_ANALYTICS_ENDPOINT)"
    if [[ "$dev_deployment" == "$release_deployment" || "$dev_deployment" == "$TELEMETRY_PRODUCTION_DEPLOYMENT" ]]; then
        fail 78 "refusing: $dev_deployment is the production deployment"
    fi
    dev_endpoint="$debug_origin/logEvent"
}

require_convex() {
    [[ -x "$convex_bin" ]] || fail 69 'Convex CLI is unavailable; run npm ci first'
    run_with_timeout "$CONVEX_TIMEOUT_SECONDS" "$convex_bin" env list --names-only \
        --deployment "$dev_deployment" < /dev/null > /dev/null 2>&1 \
        || fail 69 "the Convex CLI cannot reach $dev_deployment; log in with npx convex login and retry"
}

# The Keychain write goes through security's command reader on stdin, so the value is never a
# process argument. Read back afterwards, because that reader reports no failure of its own.
store_in_keychain() {
    local secret=$1
    local service account stored
    service=$(telemetry_keychain_service development)
    account=$(telemetry_keychain_account development)
    printf 'add-generic-password -U -s %s -a %s -w %s\n' "$service" "$account" "$secret" \
        | security -i > /dev/null 2>&1 || true
    stored=$(telemetry_keychain_secret development) || stored=''
    if [[ "$stored" != "$secret" ]]; then
        unset stored
        fail 78 'the macOS Keychain did not store the dev usage-data secret; unlock the login Keychain and retry'
    fi
    unset stored
}

temp_dir=''
make_temp_dir() {
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/reptoday-dev-telemetry.XXXXXX")
    chmod 700 "$temp_dir"
    trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
}

# Prints the HTTP status of one POST. The secret travels in a private curl config file.
post_status() {
    local label=$1
    local secret=$2
    local stamp=$3
    local header_config="$temp_dir/curl-$label.conf"
    local body
    body=$(printf '{"eventId":"dev-validation-%s-%s","name":"app_install","installId":"%s%s-%s","clientTs":%s,"props":{"install_week":"dev-validation"}}' \
        "$label" "$stamp" "$VALIDATION_ID_PREFIX" "$label" "$stamp" "$(($(date +%s) * 1000))")
    if [[ -n "$secret" ]]; then
        (umask 077; printf 'header = "%s: %s"\n' "$SECRET_HEADER" "$secret" > "$header_config")
    else
        : > "$header_config"
    fi
    curl -sS \
        --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" \
        --max-time "$CURL_MAX_TIME_SECONDS" \
        -o /dev/null \
        -w '%{http_code}' \
        -X POST "$dev_endpoint" \
        -H 'Content-Type: application/json' \
        --config "$header_config" \
        --data "$body" 2>/dev/null || true
    rm -f "$header_config"
}

# verify_boundary <accepted secret> <refused value file>...
verify_boundary() {
    local accepted=$1
    shift
    local stamp deadline status refused refused_file index=0 ok=true
    stamp=$(date -u '+%Y%m%dT%H%M%SZ')

    # A changed deployment variable can take a moment to reach the HTTP action.
    deadline=$((SECONDS + ACCEPTANCE_DEADLINE_SECONDS))
    status=$(post_status accepted "$accepted" "$stamp")
    while [[ "$status" != 204 ]] && (( SECONDS < deadline )); do
        sleep 2
        status=$(post_status accepted "$accepted" "$stamp")
    done
    echo "keychain value: HTTP $status (expected 204)"
    [[ "$status" == 204 ]] || ok=false

    status=$(post_status missing '' "$stamp")
    echo "no value: HTTP $status (expected 401)"
    [[ "$status" == 401 ]] || ok=false

    refused=$(od -An -vtx1 -N32 /dev/urandom | tr -d ' \n')
    status=$(post_status wrong "$refused" "$stamp")
    echo "random wrong value: HTTP $status (expected 401)"
    [[ "$status" == 401 ]] || ok=false

    for refused_file in "$@"; do
        index=$((index + 1))
        refused=$(tr -d '\r\n' < "$refused_file")
        if [[ ! "$refused" =~ ^[[:alnum:]_.-]+$ ]]; then
            unset refused
            fail 65 "refused value file $index does not hold a single plain token"
        fi
        if [[ "$refused" == "$accepted" ]]; then
            unset refused
            fail 65 "refused value file $index holds the current Keychain value"
        fi
        status=$(post_status "refused$index" "$refused" "$stamp")
        echo "refused value $index: HTTP $status (expected 401)"
        [[ "$status" == 401 ]] || ok=false
    done
    unset refused

    echo "checked at $(date -u '+%Y-%m-%dT%H:%M:%SZ') against $dev_deployment"
    [[ "$ok" == true ]]
}

command_install() {
    local secret
    secret=$(telemetry_keychain_secret development) \
        || fail 78 'the dev usage-data secret is not in the macOS Keychain; run tools/dev-telemetry-secret.sh adopt (or rotate) first. Debug builds still work without it and send no usage data'
    telemetry_secret_is_well_formed "$secret" \
        || { unset secret; fail 78 'the dev usage-data secret has an unexpected format; rotate it'; }
    # Never let the value land where git would publish it.
    git -C "$repo_root" check-ignore -q "$local_xcconfig" \
        || { unset secret; fail 70 'the private xcconfig path is not ignored by git; nothing was written'; }
    write_telemetry_secret_xcconfig "$secret" "$local_xcconfig"
    unset secret
    echo "wrote ${local_xcconfig#"$repo_root"/} (untracked, mode 600); Debug builds now send usage data to the dev sink"
}

command_remove() {
    rm -f "$local_xcconfig"
    echo "removed ${local_xcconfig#"$repo_root"/}; Debug builds now send no usage data"
}

command_verify() {
    local secret
    resolve_dev_deployment
    secret=$(telemetry_keychain_secret development) \
        || fail 78 'the dev usage-data secret is not in the macOS Keychain'
    make_temp_dir
    verify_boundary "$secret" "$@" || { unset secret; fail 1 'the dev sink did not answer as expected'; }
    unset secret
}

command_adopt() {
    local secret
    resolve_dev_deployment
    require_convex
    secret=$(run_with_timeout "$CONVEX_TIMEOUT_SECONDS" "$convex_bin" env get "$DEPLOYMENT_VARIABLE" \
        --deployment "$dev_deployment" < /dev/null 2>/dev/null) \
        || fail 69 "could not read $DEPLOYMENT_VARIABLE from $dev_deployment"
    telemetry_secret_is_well_formed "$secret" \
        || { unset secret; fail 78 "$dev_deployment holds a value of an unexpected format; rotate it"; }
    store_in_keychain "$secret"
    echo 'stored the dev deployment value in the macOS Keychain'
    make_temp_dir
    verify_boundary "$secret" "$@" || { unset secret; fail 1 'the dev sink did not answer as expected'; }
    unset secret
}

command_rotate() {
    local previous secret output
    resolve_dev_deployment
    require_convex
    previous=$(telemetry_keychain_secret development) || previous=''
    secret=$(od -An -vtx1 -N32 /dev/urandom | tr -d ' \n')
    telemetry_secret_is_well_formed "$secret" \
        || { unset secret previous; fail 70 'the system random source did not yield 32 bytes'; }

    make_temp_dir
    if [[ -n "$previous" ]]; then
        (umask 077; printf '%s' "$previous" > "$temp_dir/previous")
        set -- "$@" "$temp_dir/previous"
    fi

    store_in_keychain "$secret"
    echo "setting $DEPLOYMENT_VARIABLE on $dev_deployment"
    if ! output=$(printf '%s' "$secret" | run_with_timeout "$CONVEX_TIMEOUT_SECONDS" "$convex_bin" env set \
        "$DEPLOYMENT_VARIABLE" --deployment "$dev_deployment" 2>&1); then
        output=${output//"$secret"/<redacted>}
        if [[ -n "$previous" ]]; then
            store_in_keychain "$previous"
            echo 'the Keychain was put back to the previous value' >&2
        else
            security delete-generic-password \
                -s "$(telemetry_keychain_service development)" \
                -a "$(telemetry_keychain_account development)" > /dev/null 2>&1 || true
            echo 'the Keychain item was removed again' >&2
        fi
        unset secret previous
        printf '%s\n' "$output" >&2
        fail 69 "could not set $DEPLOYMENT_VARIABLE on $dev_deployment; nothing was rotated"
    fi
    unset output previous
    echo "rotated at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    verify_boundary "$secret" "$@" || { unset secret; fail 1 'the dev sink did not answer as expected after the rotation'; }
    unset secret
    echo 'next: run tools/dev-telemetry-secret.sh install in each checkout that builds Debug'
}

[[ $# -ge 1 ]] || usage
command=$1
shift

refused_files=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --refused-value-file)
            [[ $# -ge 2 && -r "$2" ]] || usage
            refused_files+=("$2")
            shift 2
            ;;
        *) usage ;;
    esac
done

case "$command" in
    install) [[ ${#refused_files[@]} -eq 0 ]] || usage; command_install ;;
    remove) [[ ${#refused_files[@]} -eq 0 ]] || usage; command_remove ;;
    verify) command_verify ${refused_files[@]+"${refused_files[@]}"} ;;
    adopt) command_adopt ${refused_files[@]+"${refused_files[@]}"} ;;
    rotate) command_rotate ${refused_files[@]+"${refused_files[@]}"} ;;
    *) usage ;;
esac

#!/bin/bash

# Offline test of the dev usage-data secret's tooling: tools/dev-telemetry-secret.sh (install,
# verify, rotate) over tools/telemetry-keychain.sh. It runs the real scripts inside a throwaway git
# repository with stand-ins for security, xcodebuild, curl and the Convex CLI first on PATH, so it
# touches no Keychain, no deployment and no network, and every value in it is plainly fake.

set -euo pipefail

real_root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/reptoday-telemetry-wiring-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

readonly sandbox="$work/repo"
readonly stubs="$work/bin"
export FAKE_STATE="$work/state"

readonly FAKE_PRODUCTION_SECRET='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
readonly FAKE_DEV_SECRET='fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
readonly FAKE_PUBLISHED_SECRET='00000000000000000000000000000000'
readonly DEV_DEPLOYMENT='courteous-dogfish-560'
readonly PRODUCTION_DEPLOYMENT='sensible-spider-810'
readonly DEV_ITEM='com.reptoday.analytics.development__debug-build'
readonly PRODUCTION_ITEM='com.reptoday.analytics.production__release-archive'

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
expect() {
    local description=$1
    shift
    if "$@"; then pass "$description"; else fail "$description"; fi
}

# --- stand-ins -------------------------------------------------------------------------------

mkdir -p "$stubs" "$sandbox/tools" "$sandbox/ios/RepToday/Config" "$sandbox/node_modules/.bin"

cat > "$stubs/security" <<'STUB'
#!/bin/bash
printf 'security %s\n' "$*" >> "$FAKE_STATE/argv.log"
store="$FAKE_STATE/keychain"
[[ -e "$FAKE_STATE/keychain-locked" ]] && exit 36
item_of() {
    local service='' account=''
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) service=$2; shift 2 ;;
            -a) account=$2; shift 2 ;;
            -w) if [[ $# -ge 2 ]]; then password=$2; shift 2; else shift; fi ;;
            *) shift ;;
        esac
    done
    printf '%s/%s__%s\n' "$store" "$service" "$account"
}
if [[ "${1:-}" == -i ]]; then
    while read -r subcommand rest; do
        [[ "$subcommand" == add-generic-password ]] || exit 2
        password=''
        # shellcheck disable=SC2086
        set -- $rest
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -s) service=$2; shift 2 ;;
                -a) account=$2; shift 2 ;;
                -w) password=$2; shift 2 ;;
                *) shift ;;
            esac
        done
        printf '%s' "$password" > "$store/${service}__${account}"
    done
    exit 0
fi
subcommand=${1:-}
shift || true
case "$subcommand" in
    find-generic-password) item=$(item_of "$@"); [[ -f "$item" ]] || exit 44; cat "$item"; echo ;;
    delete-generic-password) item=$(item_of "$@"); [[ -f "$item" ]] || exit 44; rm -f "$item" ;;
    *) exit 2 ;;
esac
STUB

cat > "$stubs/xcodebuild" <<'STUB'
#!/bin/bash
printf 'xcodebuild %s\n' "$*" >> "$FAKE_STATE/argv.log"
configuration='' action=''
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
    case "${arguments[index]}" in
        -configuration) configuration=${arguments[index + 1]} ;;
        -showBuildSettings) action=${arguments[index]} ;;
    esac
done
[[ "$action" == -showBuildSettings ]] || exit 64
if [[ "$configuration" == Debug ]]; then origin=$FAKE_DEBUG_ENDPOINT; else origin=$FAKE_RELEASE_ENDPOINT; fi
printf '    REPTODAY_ANALYTICS_ENDPOINT = %s\n' "$origin"
STUB

# A value the Convex stand-in was told to delay (convex-set-lags) reaches the sink only after the
# sink has answered one more request with the value it held before.
cat > "$stubs/curl" <<'STUB'
#!/bin/bash
printf 'curl %s\n' "$*" >> "$FAKE_STATE/argv.log"
config='' url=''
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
    case "${arguments[index]}" in
        --config) config=${arguments[index + 1]} ;;
        https://*) url=${arguments[index]} ;;
    esac
done
deployment=${url#https://}
deployment=${deployment%%.*}
variable="$FAKE_STATE/deployment/$deployment/ANALYTICS_SHARED_SECRET"
presented=$(sed -n 's/^header = "X-RepToday-Analytics-Secret: \(.*\)"$/\1/p' "$config")
expected=$(cat "$variable" 2>/dev/null || true)
if [[ -n "$presented" && "$presented" == "$expected" ]]; then printf '204'; else printf '401'; fi
if [[ -f "$variable.pending" ]]; then mv "$variable.pending" "$variable"; fi
STUB

cat > "$sandbox/node_modules/.bin/convex" <<'STUB'
#!/bin/bash
printf 'convex %s\n' "$*" >> "$FAKE_STATE/argv.log"
[[ -e "$FAKE_STATE/convex-logged-out" ]] && { echo 'You are not logged in.' >&2; exit 1; }
deployment='' positional=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deployment) deployment=$2; shift 2 ;;
        --*) shift ;;
        *) positional+=("$1"); shift ;;
    esac
done
[[ -n "$deployment" ]] || exit 1
variable="$FAKE_STATE/deployment/$deployment/${positional[2]:-}"
case "${positional[1]:-}" in
    list) echo ANALYTICS_SHARED_SECRET ;;
    set)
        [[ -e "$FAKE_STATE/convex-set-fails" ]] && { echo "could not set $(cat) on $deployment" >&2; exit 1; }
        printf '%s\n' "$deployment" >> "$FAKE_STATE/deployment-writes.log"
        if [[ -e "$FAKE_STATE/convex-set-lags" ]]; then cat > "$variable.pending"; else cat > "$variable"; fi
        ;;
    *) exit 1 ;;
esac
STUB

chmod +x "$stubs"/* "$sandbox/node_modules/.bin/convex"
export PATH="$stubs:$PATH"

# --- the repository under test ---------------------------------------------------------------

cp "$real_root/.gitignore" "$sandbox/.gitignore"
cp "$real_root/tools/telemetry-keychain.sh" "$real_root/tools/dev-telemetry-secret.sh" "$sandbox/tools/"
chmod +x "$sandbox"/tools/*.sh
git -C "$sandbox" init -q

readonly local_xcconfig="$sandbox/ios/RepToday/Config/DebugTelemetry.local.xcconfig"

reset_state() {
    rm -rf "$FAKE_STATE" "$local_xcconfig"
    mkdir -p "$FAKE_STATE/keychain" "$FAKE_STATE/deployment/$DEV_DEPLOYMENT" \
        "$FAKE_STATE/deployment/$PRODUCTION_DEPLOYMENT"
    : > "$FAKE_STATE/argv.log"
    : > "$FAKE_STATE/deployment-writes.log"
    printf '%s' "$FAKE_PUBLISHED_SECRET" > "$FAKE_STATE/deployment/$DEV_DEPLOYMENT/ANALYTICS_SHARED_SECRET"
    printf '%s' "$FAKE_PRODUCTION_SECRET" > "$FAKE_STATE/deployment/$PRODUCTION_DEPLOYMENT/ANALYTICS_SHARED_SECRET"
    export FAKE_DEBUG_ENDPOINT="https://$DEV_DEPLOYMENT.convex.site"
    export FAKE_RELEASE_ENDPOINT="https://$PRODUCTION_DEPLOYMENT.convex.site"
}

# run <arguments>: runs the dev secret script, setting status and output (stdout and stderr together).
status=0
output=''
run() {
    set +e
    output=$(cd "$sandbox" && bash tools/dev-telemetry-secret.sh "$@" 2>&1)
    status=$?
    set -e
}

keychain() { cat "$FAKE_STATE/keychain/$1" 2>/dev/null || true; }
deployed() { cat "$FAKE_STATE/deployment/$1/ANALYTICS_SHARED_SECRET"; }
# No fake value, and no value a run generated, may reach an output or a command's arguments.
leaks() {
    local value
    for value in "$FAKE_PRODUCTION_SECRET" "$FAKE_DEV_SECRET" "$FAKE_PUBLISHED_SECRET" "$@"; do
        [[ -n "$value" ]] || continue
        if grep -qF -- "$value" "$FAKE_STATE/argv.log" || [[ "$output" == *"$value"* ]]; then return 0; fi
    done
    return 1
}
no_leak() { ! leaks "$@"; }

# --- install ---------------------------------------------------------------------------------

reset_state
run install
expect 'install: a missing development item stops with 78' test "$status" -eq 78
expect 'install: and writes no file' test ! -e "$local_xcconfig"

printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
printf '%s' "$FAKE_PRODUCTION_SECRET" > "$FAKE_STATE/keychain/$PRODUCTION_ITEM"
run install
expect 'install: succeeds with the development item' test "$status" -eq 0
expect 'install: writes the development secret' \
    test "$(cat "$local_xcconfig")" = "REPTODAY_ANALYTICS_SECRET = $FAKE_DEV_SECRET"
expect 'install: the file is mode 600' test "$(stat -f '%Lp' "$local_xcconfig")" = 600
expect 'install: git ignores the file' test -z "$(git -C "$sandbox" status --porcelain -- ios)"
expect 'install: never reads the production item' \
    bash -c "! grep -q 'analytics.production' '$FAKE_STATE/argv.log'"
expect 'install: prints no value and passes none as an argument' no_leak

reset_state
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
mv "$sandbox/.gitignore" "$work/gitignore.aside"
run install
expect 'install: refuses with 70 when git would not ignore the file' test "$status" -eq 70
expect 'install: and writes nothing there' test ! -e "$local_xcconfig"
mv "$work/gitignore.aside" "$sandbox/.gitignore"

# --- rotate ----------------------------------------------------------------------------------

reset_state
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
printf '%s' "$FAKE_PUBLISHED_SECRET" > "$work/published"
run rotate --refused-value-file "$work/published"
rotated=$(keychain "$DEV_ITEM")
expect 'rotate: succeeds' test "$status" -eq 0
expect 'rotate: names the dev deployment before anything else' \
    test "$(printf '%s\n' "$output" | head -1)" = "target deployment: $DEV_DEPLOYMENT (dev: the Debug REPTODAY_ANALYTICS_ENDPOINT)"
expect 'rotate: the Keychain holds a new 32-byte value' \
    bash -c "[[ '$rotated' =~ ^[0-9a-f]{64}\$ && '$rotated' != '$FAKE_DEV_SECRET' ]]"
expect 'rotate: the dev deployment holds the same value' test "$(deployed "$DEV_DEPLOYMENT")" = "$rotated"
expect 'rotate: wrote the dev deployment only' test "$(sort -u "$FAKE_STATE/deployment-writes.log")" = "$DEV_DEPLOYMENT"
expect 'rotate: left the production deployment and item alone' \
    bash -c "[[ '$(deployed "$PRODUCTION_DEPLOYMENT")' == '$FAKE_PRODUCTION_SECRET' ]] && ! grep -q 'analytics.production' '$FAKE_STATE/argv.log'"
expect 'rotate: reports the new value accepted' grep -q '^keychain value: HTTP 204' <<< "$output"
expect 'rotate: reports the published and previous values refused' \
    test "$(grep -c '^refused value [12]: HTTP 401' <<< "$output")" -eq 2
expect 'rotate: prints no value and passes none as an argument' no_leak "$rotated"

reset_state
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
touch "$FAKE_STATE/convex-set-lags"
run rotate
expect 'rotate: waits for a sink that has not taken the new value yet' test "$status" -eq 0
expect 'rotate: and reports the new value accepted once it has' grep -q '^keychain value: HTTP 204' <<< "$output"

reset_state
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
export FAKE_DEBUG_ENDPOINT="https://$PRODUCTION_DEPLOYMENT.convex.site"
run rotate
expect 'rotate: stops with 78 when Debug points at the Release deployment' test "$status" -eq 78
expect 'rotate: and changes neither the Keychain nor a deployment' \
    bash -c "[[ '$(keychain "$DEV_ITEM")' == '$FAKE_DEV_SECRET' && ! -s '$FAKE_STATE/deployment-writes.log' ]]"
export FAKE_RELEASE_ENDPOINT='https://another-release-1.convex.site'
run rotate
expect 'rotate: stops with 78 on the known production deployment whatever Release says' test "$status" -eq 78
expect 'rotate: and still changes nothing' \
    bash -c "[[ '$(keychain "$DEV_ITEM")' == '$FAKE_DEV_SECRET' && ! -s '$FAKE_STATE/deployment-writes.log' ]]"

reset_state
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
touch "$FAKE_STATE/convex-logged-out"
run rotate
expect 'rotate: stops with 69 when the Convex CLI is logged out' test "$status" -eq 69
expect 'rotate: and leaves the Keychain alone' test "$(keychain "$DEV_ITEM")" = "$FAKE_DEV_SECRET"

reset_state
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
touch "$FAKE_STATE/convex-set-fails"
run rotate
expect 'rotate: a failed deployment write stops with 69' test "$status" -eq 69
expect 'rotate: and puts the previous Keychain value back' test "$(keychain "$DEV_ITEM")" = "$FAKE_DEV_SECRET"
expect 'rotate: with the value the CLI echoed redacted' \
    bash -c "[[ \"\$1\" == *'<redacted>'* ]]" _ "$output"
expect 'rotate: so the failure prints no value either' \
    bash -c "! grep -qE '[0-9a-f]{64}' <<< \"\$1\"" _ "$output"

reset_state
touch "$FAKE_STATE/convex-set-fails"
run rotate
expect 'rotate: a first rotation that fails leaves no Keychain item' test -z "$(keychain "$DEV_ITEM")"

# --- verify ----------------------------------------------------------------------------------

reset_state
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
printf '%s' "$FAKE_DEV_SECRET" > "$FAKE_STATE/deployment/$DEV_DEPLOYMENT/ANALYTICS_SHARED_SECRET"
run verify
expect 'verify: passes when the Keychain matches the deployment' test "$status" -eq 0
expect 'verify: changes no deployment' test ! -s "$FAKE_STATE/deployment-writes.log"
expect 'verify: prints no value and passes none as an argument' no_leak

reset_state
printf '%s' "$FAKE_PRODUCTION_SECRET" > "$FAKE_STATE/keychain/$DEV_ITEM"
run verify
expect 'verify: fails when the Keychain value is refused' test "$status" -eq 1
expect 'verify: and says so by status code' grep -q '^keychain value: HTTP 401' <<< "$output"
expect 'verify: after asking the sink once per value, with no wait' \
    test "$(grep -c '^curl ' "$FAKE_STATE/argv.log")" -eq 3

echo
if (( failures > 0 )); then
    echo "$failures check(s) failed"
    exit 1
fi
echo 'all checks passed'

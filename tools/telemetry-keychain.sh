#!/bin/bash

# Where the development usage-data shared secret lives on this Mac and how it reaches a Debug build:
# a generic password in the macOS login Keychain is read into a shell variable and written to a
# private, mode-600 xcconfig that sets REPTODAY_ANALYTICS_SECRET. The value never appears in source,
# the generated Xcode project, a tracked xcconfig, a command's arguments or its output. Release takes
# the same route with its own item in tools/archive-release.sh; nothing here names or reads that one.
#
# Source this file; it defines names and functions and runs nothing. tools/dev-telemetry-secret.sh
# is its caller.

readonly DEV_TELEMETRY_KEYCHAIN_SERVICE='com.reptoday.analytics.development'
readonly DEV_TELEMETRY_KEYCHAIN_ACCOUNT='debug-build'
readonly TELEMETRY_SECRET_BUILD_SETTING='REPTODAY_ANALYTICS_SECRET'

# Prints the secret for capture into a variable: secret=$(dev_telemetry_keychain_secret). Fails,
# printing nothing, when the item is missing or the Keychain refuses.
dev_telemetry_keychain_secret() {
    security find-generic-password \
        -s "$DEV_TELEMETRY_KEYCHAIN_SERVICE" -a "$DEV_TELEMETRY_KEYCHAIN_ACCOUNT" -w 2>/dev/null
}

# 256 bits from the system's random source, as 64 hex digits: the only shape the item holds.
telemetry_secret_is_well_formed() {
    [[ "$1" =~ ^[[:xdigit:]]{64}$ ]]
}

# Writes the private xcconfig. The caller owns the path and its removal.
write_telemetry_secret_xcconfig() {
    local secret=$1
    local path=$2
    (
        umask 077
        printf '%s = %s\n' "$TELEMETRY_SECRET_BUILD_SETTING" "$secret" > "$path"
    )
    chmod 600 "$path"
}

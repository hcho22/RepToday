#!/bin/bash

# The one route a usage-data shared secret takes into a build, for every configuration: an item in
# the macOS login Keychain is read into a shell variable and written to a private, mode-600 xcconfig
# that sets REPTODAY_ANALYTICS_SECRET. The value never appears in source, the generated Xcode
# project, a tracked xcconfig, a command's arguments or its output.
#
# Source this file; it defines names and functions and runs nothing. Its callers:
#   tools/archive-release.sh, tools/validate-release-telemetry-client.sh and
#   tools/validate-production-telemetry.sh   read the production item
#   tools/dev-telemetry-secret.sh                                 owns the development item
#
# The two Keychain items, both generic passwords in the login Keychain:
#   environment   service                               account           deployment
#   production    com.reptoday.analytics.production     release-archive   sensible-spider-810
#   development   com.reptoday.analytics.development    debug-build       courteous-dogfish-560
# shellcheck disable=SC2034  # the *_DEPLOYMENT names are read by the scripts that source this file.

readonly TELEMETRY_KEYCHAIN_SERVICE_PRODUCTION='com.reptoday.analytics.production'
readonly TELEMETRY_KEYCHAIN_ACCOUNT_PRODUCTION='release-archive'
readonly TELEMETRY_KEYCHAIN_SERVICE_DEVELOPMENT='com.reptoday.analytics.development'
readonly TELEMETRY_KEYCHAIN_ACCOUNT_DEVELOPMENT='debug-build'
readonly TELEMETRY_PRODUCTION_DEPLOYMENT='sensible-spider-810'
readonly TELEMETRY_SECRET_BUILD_SETTING='REPTODAY_ANALYTICS_SECRET'

# Prints the Keychain service of an environment, or fails for a name that is not one of the two.
telemetry_keychain_service() {
    case "$1" in
        production) printf '%s\n' "$TELEMETRY_KEYCHAIN_SERVICE_PRODUCTION" ;;
        development) printf '%s\n' "$TELEMETRY_KEYCHAIN_SERVICE_DEVELOPMENT" ;;
        *) return 64 ;;
    esac
}

telemetry_keychain_account() {
    case "$1" in
        production) printf '%s\n' "$TELEMETRY_KEYCHAIN_ACCOUNT_PRODUCTION" ;;
        development) printf '%s\n' "$TELEMETRY_KEYCHAIN_ACCOUNT_DEVELOPMENT" ;;
        *) return 64 ;;
    esac
}

# Prints an environment's secret for capture into a variable: secret=$(telemetry_keychain_secret
# production). Fails, printing nothing, when the item is missing or the Keychain refuses.
telemetry_keychain_secret() {
    local service account
    service=$(telemetry_keychain_service "$1") || return 64
    account=$(telemetry_keychain_account "$1") || return 64
    security find-generic-password -s "$service" -a "$account" -w 2>/dev/null
}

# 256 bits from the system's random source, as 64 hex digits: the only shape either item holds.
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

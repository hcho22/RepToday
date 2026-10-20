#!/bin/bash

# The read-only audit the founder points at the gr0wthlab, Mandu and RepToday checkouts at go-live (US-WL08):
#
#     tools/waitlist/audit-checkouts.sh <directory>...
#
# It prints file names, line numbers, rule names and counts only, never a value, and writes nothing. Each rule's
# file scope is stated in tools/check-no-waitlist-credentials.py (its docstring is the one place), which this
# script runs in its --audit mode. Exit status: 0 no findings, 1 findings or a directory that could not be read.

set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ $# -eq 0 ]]; then
    echo "usage: tools/waitlist/audit-checkouts.sh <directory>..." >&2
    exit 2
fi
exec python3 "$here/../check-no-waitlist-credentials.py" --audit "$@"

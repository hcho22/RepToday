#!/usr/bin/env python3
"""Captain-operated Keychain read check. Credential bytes never reach terminal output."""

import subprocess
import sys

SERVICE = "com.reptoday.coach.production"
ACCOUNTS = ("openai-api-key", "client-shared-secret", "cloudflare-zone-waf-token")


def main():
    if len(sys.argv) != 1:
        print("usage: tools/check-coach-keychain-access.py (never pass a credential)")
        return 64
    for account in ACCOUNTS:
        try:
            result = subprocess.run(
                ["/usr/bin/security", "find-generic-password", "-s", SERVICE, "-a", account, "-w"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            print("not-ready: local Keychain read timed out; no credential value printed")
            return 78
        except OSError:
            print("not-ready: local Keychain reader unavailable; no credential value printed")
            return 78
        if result.returncode != 0 or not result.stdout.strip():
            print("not-ready: local Keychain read unavailable; no credential value printed")
            return 78
        # Never relay security's stdout/stderr: stdout contains the saved credential.
        del result
    print("ready: all three production Coach credentials are locally readable; values suppressed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

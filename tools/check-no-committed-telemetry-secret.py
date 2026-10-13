#!/usr/bin/env python3
"""Fail when a build setting commits a usage-data shared secret.

This repository is public. REPTODAY_ANALYTICS_SECRET reaches a build only from the macOS Keychain
through a private xcconfig, so no file git would publish may give it a value: not the XcodeGen
spec, the generated project, a tracked xcconfig, a scheme or a workflow, and not Info.plist, whose
key must stay the build-setting reference.

It reads the working tree, tracked and untracked-but-not-ignored, so it also covers a project that
was just regenerated. An ignored file (the private xcconfig itself) is not read. A finding names
the file and line and never repeats the value.

usage: tools/check-no-committed-telemetry-secret.py [repository root]
"""

import plistlib
import re
import subprocess
import sys
from pathlib import Path

SETTING = 'REPTODAY_ANALYTICS_SECRET'
PLIST_KEY = 'RepTodayAnalyticsSecret'
PLIST_REFERENCE = f'$({SETTING})'
BUILD_SETTING_SUFFIXES = ('.pbxproj', '.xcconfig', '.xcscheme', '.yml', '.yaml')

# The setting, an optional [sdk=...] condition and closing quote of a quoted key, then `:` or `=`
# and whatever value follows.
ASSIGNMENT = re.compile(
    re.escape(SETTING)
    + r'(?:\[[^\]]*\])?["\']?\s*[:=]\s*(?:"(?P<double>[^"]*)"|\'(?P<single>[^\']*)\'|(?P<bare>\S*))'
)
PLACEHOLDER = re.compile(r'<[^<>]*>')
REFERENCE = re.compile(r'\$[({].*[)}]')


def is_empty_value(match):
    quoted = match.group('double')
    if quoted is None:
        quoted = match.group('single')
    value = quoted if quoted is not None else match.group('bare').rstrip(';\\,').strip('"\'')
    return value == '' or bool(PLACEHOLDER.fullmatch(value) or REFERENCE.fullmatch(value))


def published_files(root):
    listed = subprocess.run(
        ['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
        check=True, stdout=subprocess.PIPE,
    ).stdout
    return [root / name for name in listed.decode().split('\0') if name]


def findings_in(root):
    findings = []
    for path in published_files(root):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if path.name.endswith(BUILD_SETTING_SUFFIXES):
            text = path.read_text(encoding='utf-8', errors='replace')
            for number, line in enumerate(text.splitlines(), start=1):
                if any(not is_empty_value(match) for match in ASSIGNMENT.finditer(line)):
                    findings.append(f'{relative}:{number}: {SETTING} is given a value (withheld)')
        elif path.suffix == '.plist':
            try:
                value = plistlib.loads(path.read_bytes()).get(PLIST_KEY)
            except Exception:
                continue
            if value is not None and value not in ('', PLIST_REFERENCE):
                findings.append(f'{relative}: {PLIST_KEY} is not {PLIST_REFERENCE} (value withheld)')
    return findings


def main(arguments):
    root = Path(arguments[1]) if len(arguments) > 1 else Path(__file__).resolve().parent.parent
    findings = findings_in(root.resolve())
    for finding in findings:
        print(f'error: {finding}')
    if findings:
        print('error: a usage-data secret must never be committed; if a real value was, remove it and '
              'rotate it (tools/dev-telemetry-secret.sh rotate)', file=sys.stderr)
        return 1
    print(f'no committed {SETTING} value')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

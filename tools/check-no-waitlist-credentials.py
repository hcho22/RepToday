#!/usr/bin/env python3
"""Fail when an email-service credential, a subscriber export or an unlisted email address is committed (US-WL08).

Treat this repository as public (its visibility has changed before). The Waitlist's addresses stay on the
founder's side (ADR-0009): the only places a credential may live are the macOS Keychain and the hosting or email
provider's own secret store, and no export that holds addresses may sit in the RepToday, gr0wthlab or Mandu
checkouts.

Two modes, one set of rules:

  tools/check-no-waitlist-credentials.py [repository root]
      The CI guard. Reads the working tree, tracked and untracked-but-not-ignored (the files git would publish).

  tools/check-no-waitlist-credentials.py --audit DIRECTORY...
      The read-only audit (tools/waitlist/audit-checkouts.sh runs it) the founder points at the gr0wthlab, Mandu
      and RepToday checkouts at go-live. It reads what the sandbox reads, the directory itself, not git's file
      list. In every directory the credential rules scan every file, git-ignored or not, skipping only `.git`,
      so a key kept in an ignored file such as a root `.env` is found; the export rule scans the same files
      except installed dependency folders (`node_modules/`, a Python virtual environment, `site-packages/`),
      whose third-party package metadata carries maintainers' addresses. On the RepToday checkout this script
      lives in, the audit also applies the address rule, with the guard's allowlist, to the guard's own file
      list. On any other directory it applies no address rule: single address strings are not what the request
      forbids there, and the gr0wthlab checkout's own tests and examples hold them. An export there is still
      caught, with no row count, so even a one-row export is reported.

Rules, each named in a finding:

  credential-assignment  a literal value given to a name used for an email-service credential (the Kit and
                         ConvertKit key and secret names, a few other mail services', and Kit's own API-key
                         header, `X-Kit-Api-Key`). A reference (`$(...)`, `${...}`, `<placeholder>`), an empty
                         value or a call is not a literal.
  credential-header      in the Waitlist's own paths (`gtm/03-site/`, `tools/waitlist/`, this guard and its test,
                         and the Waitlist's evidence reports): any bearer or API-key header with a literal value.
  export-file            a CSV, TSV, JSON or JSONL file with a column or field named for an email address that
                         holds even one email-shaped address not on the allowlist, however few rows it has. Every
                         such file is read whatever its encoding (UTF-8, else UTF-16 by its byte-order mark, else
                         a single-byte decoding such as Latin-1), so a Windows-1252 export is not skipped, and a
                         CSV or TSV the reader cannot parse (a NUL byte, say) is read line by line instead.
  address                an email-shaped string not on the allowlist. Only text files are read for this rule
                         (files that decode as UTF-8 and hold no NUL byte): committed images such as the Trainer
                         pose art hold address-shaped byte runs by chance.

"Email-shaped" means a whole address: a local part of letters, digits and `._%+-`, an `@`, and a dotted domain
whose last label is two or more letters. It is narrower than gr0wthlab's any-`@` rule on purpose: that rule, which
tools/waitlist/check-view.py keeps for the view, would flag every scoped package path in `package-lock.json`.

The allowlist is the policy's published contact address, addresses at the reserved example domains, and two
URL-userinfo test inputs that are address-shaped by accident, each allowed only in its own file. A finding names
the file and line and never repeats a value.

Exit status: 0 clean, 1 findings, 2 usage.
"""
import csv
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CONTACT_ADDRESS = 'reptoday.app' + chr(64) + 'gmail.com'
EXAMPLE_DOMAINS = ('example.com', 'example.org', 'example.net')
# Each allowed only in its own file: URL userinfo (`user:password@host`, `user@host`) that reads as an address.
FILE_PINNED = {
    'proxy/test/apple-fetch.test.js': {
        'password' + chr(64) + 'api.storekit.apple.com',
        'password' + chr(64) + 'api.storekit-sandbox.apple.com',
    },
    'ios/RepToday/RepTodayTests/CoachProxyClientConfiguredTests.swift': {
        'user' + chr(64) + 'coach.reptoday.app',
    },
}

WAITLIST_PATHS = (
    'gtm/03-site/',
    'tools/waitlist/',
    'tools/check-no-waitlist-credentials.py',
    'tools/test-check-no-waitlist-credentials.py',
    'artifacts/reports/US-WL',
)

ADDRESS = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}')

# Names used for an email-service credential. Matched case-insensitively with an optional separator between the
# words, so KIT_API_KEY, kit-api-key, kitApiKey and the header X-Kit-Api-Key are all one name.
CREDENTIAL_WORDS = [
    ('kit', 'api', 'key'), ('kit', 'api', 'secret'), ('kit', 'secret'), ('kit', 'v4', 'api', 'key'),
    ('convertkit', 'api', 'key'), ('convertkit', 'api', 'secret'), ('convertkit', 'secret'),
    ('ck', 'api', 'key'), ('ck', 'api', 'secret'),
    ('mailchimp', 'api', 'key'), ('sendgrid', 'api', 'key'), ('mailgun', 'api', 'key'),
    ('postmark', 'api', 'token'), ('postmark', 'server', 'token'), ('resend', 'api', 'key'),
    ('buttondown', 'api', 'key'), ('beehiiv', 'api', 'key'), ('mailerlite', 'api', 'key'),
    ('brevo', 'api', 'key'), ('sendinblue', 'api', 'key'),
]
SEPARATOR = r'[_\-. ]?'
# The same names with every separator removed: a file whose lower-cased, separator-stripped bytes hold none of them
# cannot hold a credential assignment, and that test runs at memory speed, so the rules below read only the rest.
FLAT_NAMES = [''.join(words).encode('ascii') for words in CREDENTIAL_WORDS]
NAME = r'(?<![A-Za-z0-9])(?:' + '|'.join(SEPARATOR.join(words) for words in CREDENTIAL_WORDS) + r')(?![A-Za-z0-9])'
# The name, an optional closing quote or bracket, `:` or `=`, then whatever value follows.
ASSIGNMENT = re.compile(NAME + r'''["'\]]*\s*(?::=|[:=])\s*(?P<value>.*)''', re.IGNORECASE)
HEADER_ASSIGNMENT = re.compile(
    r'''(?<![A-Za-z0-9])(?:x-[a-z0-9-]*(?:api-?key|api-?secret|api-?token|auth-?token)|authorization)["']?\s*[:=]\s*(?P<value>.*)''',
    re.IGNORECASE)
# `Bearer <value>` where it is written as a header value (after a quote or a colon), not in a sentence.
BEARER = re.compile(r'''(?:["'`]|:\s)\s*bearer\s+(?P<value>\S+)''', re.IGNORECASE)
# A cheap whole-file test, so the line-by-line rules run only on files that could hold a header.
HEADER_ANYWHERE = re.compile(r'authorization|bearer|x-[a-z0-9-]*(?:api|auth)', re.IGNORECASE)

BARE_LITERAL = re.compile(r'[A-Za-z0-9_\-./+=~]{4,}')
QUOTED = re.compile(r'''^(?P<quote>["'`])(?P<body>.*?)(?P=quote)''')
PLACEHOLDER = re.compile(r'<[^<>]*>|\$[({]?[A-Za-z_(].*|%[({]?[A-Za-z_].*|\{\{.*\}\}|\{[A-Za-z_][^}]*\}')

EXPORT_SUFFIXES = ('.csv', '.tsv', '.json', '.jsonl')
EXPORT_SKIP_DIRECTORIES = ('node_modules', 'site-packages')
MAX_BYTES = 50 * 1000 * 1000
csv.field_size_limit(MAX_BYTES)  # no field of a file this reads is longer than the file


def is_placeholder(text):
    return text == '' or bool(PLACEHOLDER.fullmatch(text))


def literal_value(raw):
    """Whether what follows an assignment is a literal value rather than a reference, a placeholder, an empty
    value or a call."""
    raw = raw.strip()
    quoted = QUOTED.match(raw)
    if quoted:
        body = quoted.group('body')
        return not is_placeholder(body.strip())
    if not raw or raw[0] in '$<{%([':
        return False
    token = re.split(r'[\s,;)}\]]', raw, maxsplit=1)[0].rstrip('"\'`')
    if not BARE_LITERAL.fullmatch(token) or is_placeholder(token):
        return False
    rest = raw[len(token):].lstrip()
    return not rest.startswith('(')


SCHEME = re.compile(r'(?:bearer|basic|token)\s+(?P<rest>\S+)', re.IGNORECASE)


def header_value_is_literal(raw):
    """Whether a header's value is a literal. For an Authorization header the scheme (`Bearer`, `Basic`, `Token`) is
    set aside and what follows it is judged; a header holding only a scheme word, or a reference after it, is not."""
    raw = raw.strip()
    quoted = QUOTED.match(raw)
    body = quoted.group('body').strip() if quoted else raw
    scheme = SCHEME.match(body)
    if scheme:
        return literal_value(scheme.group('rest').rstrip('"\'`,;)}]'))
    if re.fullmatch(r'(?:bearer|basic|token)', body, re.IGNORECASE):
        return False
    return literal_value(raw)


def is_waitlist_path(relative):
    return relative.startswith(WAITLIST_PATHS)


def allowed_address(address, relative):
    lowered = address.lower()
    if lowered == CONTACT_ADDRESS:
        return True
    domain = lowered.rsplit('@', 1)[1]
    if any(domain == known or domain.endswith('.' + known) for known in EXAMPLE_DOMAINS):
        return True
    return address in FILE_PINNED.get(relative, ())


def unlisted_addresses(text, relative):
    return [match for match in ADDRESS.finditer(text) if not allowed_address(match.group(0), relative)]


# Reading files.


def decode_for_export(data):
    """UTF-8, else UTF-16 by its byte-order mark, else a single-byte decoding. Never fails and never skips."""
    if data.startswith(b'\xef\xbb\xbf'):
        return data[3:].decode('utf-8', errors='replace')
    if data.startswith((b'\xff\xfe', b'\xfe\xff')):
        return data.decode('utf-16', errors='replace')
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return data.decode('latin-1')


def decode_text_only(data):
    """The text of a file the address rule may read: it decodes as UTF-8 and holds no NUL byte; otherwise None."""
    if b'\0' in data:
        return None
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return None


def line_of(text, offset):
    return text.count('\n', 0, offset) + 1


# The rules.


def may_hold_credential(data, relative):
    flat = data.lower().translate(None, b'_-. ')
    if any(name in flat for name in FLAT_NAMES):
        return True
    return is_waitlist_path(relative) and HEADER_ANYWHERE.search(data.decode('latin-1')) is not None


def credential_findings(text, relative):
    """(line, rule) for each literal credential in `text`."""
    waitlist = is_waitlist_path(relative)
    found = []
    for number, line in enumerate(text.splitlines(), start=1):
        for match in ASSIGNMENT.finditer(line):
            if literal_value(match.group('value')):
                found.append((number, 'credential-assignment'))
        if waitlist:
            for match in HEADER_ASSIGNMENT.finditer(line):
                if header_value_is_literal(match.group('value')):
                    found.append((number, 'credential-header'))
            for match in BEARER.finditer(line):
                if literal_value(match.group('value').rstrip('"\'`,;)}]')):
                    found.append((number, 'credential-header'))
    return found


def email_named(name):
    """Whether a column or field name is named for an email address."""
    flat = re.sub(r'[^a-z0-9]', '', str(name).lower())
    return 'email' in flat or flat == 'mail' or flat.endswith('mailaddress') or flat.endswith('mailaddr')


def walk_json(value, relative, line, found):
    if isinstance(value, dict):
        for key, inner in value.items():
            if email_named(key) and isinstance(inner, str) and unlisted_addresses(inner, relative):
                found.append((line, 'export-file'))
            walk_json(inner, relative, line, found)
    elif isinstance(value, list):
        for inner in value:
            walk_json(inner, relative, line, found)


JSON_PAIR = re.compile(r'"([^"\\]*)"\s*:\s*"([^"\\]*)"')


def export_findings(data, relative):
    """(line, rule) for a CSV, TSV, JSON or JSONL file that holds a subscriber export: a column or field named for an
    email address with at least one address not on the allowlist."""
    text = decode_for_export(data)
    found = []
    suffix = os.path.splitext(relative)[1].lower()
    if suffix in ('.csv', '.tsv'):
        delimiter = '\t' if suffix == '.tsv' else ','
        try:
            rows = list(csv.reader(io.StringIO(text), delimiter=delimiter))
            damaged = False
        except csv.Error:
            # Not readable as a table (a NUL byte on Python 3.9 and 3.10, say): split each line by hand and, under a
            # header that names an email column, count an unlisted address anywhere on a line, so damage hides nothing.
            rows = [line.split(delimiter) for line in text.splitlines()]
            damaged = True
        header = None
        for number, row in enumerate(rows, start=1):
            if header is None:
                if any(cell.strip() for cell in row):
                    header = [index for index, cell in enumerate(row) if email_named(cell)]
                continue
            cells = [delimiter.join(row)] if damaged and header else [row[index] for index in header if index < len(row)]
            if any(unlisted_addresses(cell, relative) for cell in cells):
                found.append((number, 'export-file'))
        return found
    try:
        walk_json(json.loads(text.lstrip('\ufeff')), relative, 1, found)
        return found
    except (ValueError, RecursionError):
        pass
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            walk_json(json.loads(line), relative, number, found)
        except (ValueError, RecursionError):
            # Not JSON at all (or damaged): fall back to the pairs it spells out, so damage hides nothing.
            for key, value in JSON_PAIR.findall(line):
                if email_named(key) and unlisted_addresses(value, relative):
                    found.append((number, 'export-file'))
    return found


def address_findings(text, relative):
    return [(line_of(text, match.start()), 'address') for match in unlisted_addresses(text, relative)]


# File lists.


def published_files(root):
    """The files git would publish from `root`: tracked, and untracked but not ignored."""
    listed = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                            check=True, stdout=subprocess.PIPE).stdout
    return [name for name in listed.decode('utf-8', errors='replace').split('\0') if name]


def walked_files(root, skip_dependency_folders):
    """Every regular file under `root`, git-ignored or not, skipping `.git` (a directory, or the file a linked
    worktree has). With `skip_dependency_folders`, installed dependency folders are skipped too."""
    for directory, names, files in os.walk(str(root), followlinks=False):
        pruned = []
        for name in names:
            path = os.path.join(directory, name)
            if name == '.git' or os.path.islink(path):
                continue
            if skip_dependency_folders and (name in EXPORT_SKIP_DIRECTORIES or os.path.exists(os.path.join(path, 'pyvenv.cfg'))):
                continue
            pruned.append(name)
        names[:] = pruned
        for name in files:
            path = os.path.join(directory, name)
            if name != '.git' and not os.path.islink(path):
                yield os.path.relpath(path, str(root))


# The two modes.


class Tally(object):
    def __init__(self):
        self.findings = []
        self.scanned = 0
        self.skipped_large = 0

    def add(self, relative, found):
        for line, rule in found:
            self.findings.append('{}:{}: rule {}'.format(relative, line, rule))


def read_bytes(path, tally):
    try:
        if os.path.getsize(path) > MAX_BYTES:
            tally.skipped_large += 1
            return None
        with open(path, 'rb') as handle:
            return handle.read()
    except OSError:
        return None


def scan_file(root, relative, tally, credentials, exports, addresses):
    path = os.path.join(str(root), relative)
    if not os.path.isfile(path) or os.path.islink(path):
        return
    data = read_bytes(path, tally)
    if data is None:
        return
    tally.scanned += 1
    if credentials and may_hold_credential(data, relative):
        tally.add(relative, credential_findings(data.decode('utf-8', errors='replace') if b'\0' not in data
                                                else data.decode('latin-1'), relative))
    if exports and relative.lower().endswith(EXPORT_SUFFIXES):
        tally.add(relative, export_findings(data, relative))
    if addresses:
        text = decode_text_only(data)
        if text is not None:
            tally.add(relative, address_findings(text, relative))


def check_tree(root):
    tally = Tally()
    for relative in published_files(root):
        scan_file(root, relative, tally, True, True, True)
    return tally


def audit_directory(directory):
    root = Path(directory).resolve()
    tally = Tally()
    this_checkout = root == ROOT
    export_scope = set(walked_files(root, True))
    for relative in walked_files(root, False):
        scan_file(root, relative, tally, True, relative in export_scope, False)
    if this_checkout:
        for relative in published_files(root):
            path = os.path.join(str(root), relative)
            data = read_bytes(path, tally) if os.path.isfile(path) and not os.path.islink(path) else None
            text = decode_text_only(data) if data is not None else None
            if text is not None:
                tally.add(relative, address_findings(text, relative))
    return tally


def report(tally, label):
    for finding in sorted(set(tally.findings)):
        print('error: {}'.format(finding))
    note = ', {} files over {} MB not read'.format(tally.skipped_large, MAX_BYTES // 1000000) if tally.skipped_large else ''
    print('{}: {} files read, {} findings{}'.format(label, tally.scanned, len(set(tally.findings)), note))


def main(arguments):
    if len(arguments) > 1 and arguments[1] == '--audit':
        directories = arguments[2:]
        if not directories:
            print('usage: check-no-waitlist-credentials.py --audit DIRECTORY...', file=sys.stderr)
            return 2
        failed = False
        for directory in directories:
            if not os.path.isdir(directory):
                print('audit: not a directory (skipped): {}'.format(os.path.basename(os.path.normpath(directory))), file=sys.stderr)
                failed = True
                continue
            tally = audit_directory(directory)
            report(tally, 'audit {}'.format(os.path.basename(os.path.normpath(os.path.abspath(directory)))))
            failed = failed or bool(tally.findings)
        return 1 if failed else 0
    root = Path(arguments[1]) if len(arguments) > 1 else ROOT
    tally = check_tree(root.resolve())
    report(tally, 'waitlist boundary')
    if tally.findings:
        print('error: no email-service credential, subscriber export or unlisted address may be committed; if a real '
              'one was, remove it and rotate the credential (docs: tools/waitlist/README.md, "The address boundary")',
              file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

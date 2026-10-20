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
                         holds, directly or anywhere beneath it, even one email-shaped address not on the allowlist,
                         however few rows it has. Every such file is read whatever its encoding (UTF-8, else UTF-16
                         by its byte-order mark, else a single-byte decoding such as Latin-1), so a Windows-1252
                         export is not skipped. In a table, every row is read against each email column any row
                         above it named, so a title line above the header hides nothing, even one that mentions
                         email; a JSON array of rows, or JSON Lines with one row per line, is read as a table too. A damaged file (a CSV or TSV the reader cannot parse or that
                         leaves a line break inside a cell, as an unclosed quote does; a line of JSON that does not
                         parse) is read line by line: once the file names an email column or field, any unlisted
                         address on such a line counts, so damage hides nothing.
  unreadable-export      a CSV, TSV, JSON or JSONL file in the export rule's scope that cannot be read (no
                         permission, an I/O error): it could hold an export, so it fails the run.
  unreadable-directory   in the audit, a directory that cannot be listed: whatever it holds would go unread, so it
                         fails the run.
  address                an email-shaped string not on the allowlist. Only text files are read for this rule
                         (files that decode as UTF-8 and hold no NUL byte): committed images such as the Trainer
                         pose art hold address-shaped byte runs by chance.

"Email-shaped" means a whole address: a local part of letters, digits and `._%+-`, an `@`, and a dotted domain
whose last label is two or more letters. It is narrower than gr0wthlab's any-`@` rule on purpose: that rule, which
tools/waitlist/check-view.py keeps for the view, would flag every scoped package path in `package-lock.json`.

The allowlist is the policy's published contact address, addresses at the reserved example domains, and two
URL-userinfo test inputs that are address-shaped by accident, each allowed only in its own file. A finding names
the file and line and never repeats a value.

A file over 50 MB is read by the export rule alone, and only if it is a CSV, TSV, JSON or JSONL file in that rule's
scope: decoded as any other export is, a line at a time, under the damaged-file reading above, so every row is seen
without holding the file. The other rules skip it, and the run reports how many files no rule read.

Exit status: 0 clean, 1 findings, 2 usage.
"""
import codecs
import csv
import io
import json
import os
import re
import stat
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
CHUNK_BYTES = 1000 * 1000
csv.field_size_limit(MAX_BYTES)  # no field of a file read whole is longer than the file


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


def export_encoding(path):
    """The codec `decode_for_export` would decode the file with, found without holding the file."""
    with open(path, 'rb') as handle:
        head = handle.read(3)
        if head.startswith(b'\xef\xbb\xbf'):
            return 'utf-8-sig'
        if head.startswith((b'\xff\xfe', b'\xfe\xff')):
            return 'utf-16'
        handle.seek(0)
        decoder = codecs.getincrementaldecoder('utf-8')()
        try:
            for chunk in iter(lambda: handle.read(CHUNK_BYTES), b''):
                decoder.decode(chunk)
            decoder.decode(b'', final=True)
        except UnicodeDecodeError:
            return 'latin-1'
    return 'utf-8'


def export_lines(path, encoding):
    """The file's lines in that codec, one at a time."""
    with open(path, encoding=encoding, errors='replace') as handle:
        for line in handle:
            yield line.rstrip('\r\n')


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


def strings_beneath(value):
    """Every string in a parsed JSON value, however deep, object keys included."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        value = list(value) + list(value.values())
    if isinstance(value, list):
        return [text for inner in value for text in strings_beneath(inner)]
    return []


def table_step(header, row, damaged, delimiter, relative):
    """One row of a table, against `header`, the email columns rows above it named. Returns those columns with this
    row's own added, and whether the row holds an unlisted address in one of them or, in a damaged table once any
    row has named one, anywhere on its line."""
    if damaged:
        cells = [delimiter.join(row)] if header else []
    else:
        cells = [row[index] for index in header if index < len(row)]
    return header | {index for index, cell in enumerate(row) if email_named(cell)}, any(
        unlisted_addresses(cell, relative) for cell in cells)


def table_findings(rows, damaged, delimiter, relative):
    """(line, rule) for each row holding an unlisted address in a column a row above it named for email."""
    found = []
    header = set()
    for number, row in enumerate(rows, start=1):
        header, hit = table_step(header, row, damaged, delimiter, relative)
        if hit:
            found.append((number, 'export-file'))
    return found


def json_row(items):
    """A JSON array as a table row: each cell as text."""
    return [item if isinstance(item, str) else json.dumps(item, ensure_ascii=False) for item in items]


def walk_json(value, relative, line, found):
    if isinstance(value, dict):
        for key, inner in value.items():
            if email_named(key) and any(unlisted_addresses(text, relative) for text in strings_beneath(inner)):
                found.append((line, 'export-file'))
            walk_json(inner, relative, line, found)
    elif isinstance(value, list):
        header = set()
        for inner in value:
            if isinstance(inner, list):
                header, hit = table_step(header, json_row(inner), False, ',', relative)
                if hit:
                    found.append((line, 'export-file'))
            walk_json(inner, relative, line, found)


JSON_KEY = re.compile(r'"([^"\\]*)"\s*:')


def json_line_findings(lines, names_email, relative):
    """(line, rule) for JSON read a line at a time: an object or array line (a trailing comma, as in one element of a
    larger document, set aside) is walked, array lines are also rows of one table, and any other line (damaged, or a
    fragment of a larger document) counts an unlisted address anywhere on it once the file names an email field, so
    damage hides nothing."""
    found = []
    header = set()
    for number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            value = json.loads(line.rstrip().rstrip(','))
            parsed = isinstance(value, (dict, list))
            if parsed:
                walk_json(value, relative, number, found)
            if isinstance(value, list):
                header, hit = table_step(header, json_row(value), False, ',', relative)
                if hit:
                    found.append((number, 'export-file'))
        except (ValueError, RecursionError):
            parsed = False
        if not parsed and names_email and unlisted_addresses(line, relative):
            found.append((number, 'export-file'))
    return found


def export_findings(data, relative):
    """(line, rule) for a CSV, TSV, JSON or JSONL file that holds a subscriber export: a column or field named for an
    email address with at least one address not on the allowlist."""
    text = decode_for_export(data)
    suffix = os.path.splitext(relative)[1].lower()
    if suffix in ('.csv', '.tsv'):
        delimiter = '\t' if suffix == '.tsv' else ','
        try:
            rows = list(csv.reader(io.StringIO(text), delimiter=delimiter))
        except csv.Error:
            rows = None
        damaged = rows is None or any('\n' in cell or '\r' in cell for row in rows for cell in row)
        if damaged:
            # Not readable as a table (a NUL byte on Python 3.9 and 3.10), or a cell holding a line break (an unclosed
            # quote folds the rest of the file into one): split each line by hand.
            rows = [line.split(delimiter) for line in text.splitlines()]
        return table_findings(rows, damaged, delimiter, relative)
    found = []
    try:
        walk_json(json.loads(text.lstrip('\ufeff')), relative, 1, found)
        return found
    except (ValueError, RecursionError):
        pass
    return found + json_line_findings(text.splitlines(), any(email_named(key) for key in JSON_KEY.findall(text)), relative)


def large_export_findings(path, relative):
    """The export rule over a file too large to read whole: decoded as `export_findings` decodes, read a line at a
    time under the damaged-file reading, so every row is seen and the file is never held."""
    encoding = export_encoding(path)
    suffix = os.path.splitext(relative)[1].lower()
    if suffix in ('.csv', '.tsv'):
        delimiter = '\t' if suffix == '.tsv' else ','
        return table_findings((line.split(delimiter) for line in export_lines(path, encoding)), True, delimiter, relative)
    names_email = any(email_named(key) for line in export_lines(path, encoding) for key in JSON_KEY.findall(line))
    return json_line_findings(export_lines(path, encoding), names_email, relative)


def address_findings(text, relative):
    return [(line_of(text, match.start()), 'address') for match in unlisted_addresses(text, relative)]


# File lists.


def published_files(root):
    """The files git would publish from `root`: tracked, and untracked but not ignored."""
    listed = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                            check=True, stdout=subprocess.PIPE).stdout
    return [name for name in listed.decode('utf-8', errors='replace').split('\0') if name]


def walked_files(root, skip_dependency_folders, unlisted=None):
    """Every regular file under `root`, git-ignored or not, skipping `.git` (a directory, or the file a linked
    worktree has). With `skip_dependency_folders`, installed dependency folders are skipped too. A directory that
    cannot be listed is appended to `unlisted`, when given, by its path relative to `root`."""
    def record(error):
        if unlisted is not None:
            unlisted.append(os.path.relpath(error.filename or str(root), str(root)))
    for directory, names, files in os.walk(str(root), onerror=record, followlinks=False):
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


def read_small(path):
    """The bytes of a file of at most MAX_BYTES, or None for a larger one. An unreadable file raises OSError."""
    if os.path.getsize(path) > MAX_BYTES:
        return None
    with open(path, 'rb') as handle:
        return handle.read()


def scan_file(root, relative, tally, credentials, exports, addresses):
    path = os.path.join(str(root), relative)
    export = exports and relative.lower().endswith(EXPORT_SUFFIXES)
    try:
        if not stat.S_ISREG(os.lstat(path).st_mode):
            return
        data = read_small(path)
        if export:
            tally.add(relative, export_findings(data, relative) if data is not None else large_export_findings(path, relative))
    except FileNotFoundError:
        return
    except OSError:
        if export:
            tally.add(relative, [(1, 'unreadable-export')])
        return
    if data is None and not export:
        tally.skipped_large += 1
        return
    tally.scanned += 1
    if data is None:
        return
    if credentials and may_hold_credential(data, relative):
        tally.add(relative, credential_findings(data.decode('utf-8', errors='replace') if b'\0' not in data
                                                else data.decode('latin-1'), relative))
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
    unlisted = []
    for relative in walked_files(root, False, unlisted):
        scan_file(root, relative, tally, True, relative in export_scope, False)
    for relative in unlisted:
        tally.add(relative, [(1, 'unreadable-directory')])
    if this_checkout:
        for relative in published_files(root):
            path = os.path.join(str(root), relative)
            try:
                data = read_small(path) if os.path.isfile(path) and not os.path.islink(path) else None
            except OSError:
                data = None
            text = decode_text_only(data) if data is not None else None
            if text is not None:
                tally.add(relative, address_findings(text, relative))
    return tally


def report(tally, label):
    for finding in sorted(set(tally.findings)):
        print('error: {}'.format(finding))
    note = ', {} files over {} MB read by no rule'.format(tally.skipped_large, MAX_BYTES // 1000000) if tally.skipped_large else ''
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

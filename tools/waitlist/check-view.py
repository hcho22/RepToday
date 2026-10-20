#!/usr/bin/env python3
"""Check a Waitlist anonymous view against the rules gr0wthlab's reader enforces (US-WL01).

    python3 tools/waitlist/check-view.py <view.json>

The view is the one address-free file RepToday keeps on the founder's Mac for gr0wthlab's launcher
(`.claude/agent/tasks/prd-waitlist_261019.md`, "The gr0wthlab reader contract"). This checker mirrors
the reader, `waitlist.read` in gr0wthlab's `src/gr0wthlab/waitlist.py`, rule for rule and in the same
order, so a view it accepts is a view the reader reads. Where the PRD's prose and the reader disagree
the reader wins. The values it checks against (Source tags, Fit answers, the view version, the entry
pattern, the byte limit) come from `contract.json`, the Waitlist's one contract file.

Exit status and verdict, matching the reader's three outcomes:

    0  accepted  the reader would read it
    1  failed    the file departs from the format (the reader reports a failed read and goes on)
    2  refused   something looks like an email address (the reader discards the read and reports a breach)

The address check runs first, over the whole text and then over every key and value, so a view that
is both malformed and address-bearing is refused rather than failed. A finding names its rule and
its position (`entry 2, source`) and never repeats a value the file holds. Python 3 standard library
only, so it runs anywhere the producer does.
"""
import base64
import json
import re
import sys
from collections import namedtuple
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import unquote

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / 'contract.json'

ACCEPTED, FAILED, REFUSED = 'accepted', 'failed', 'refused'
EXIT_STATUS = {ACCEPTED: 0, FAILED: 1, REFUSED: 2}
EXIT_USAGE = 64
EXIT_INTERNAL = 70

# A value looks like an email address when anything but a space or a delimiter stands on both sides
# of an @ (gr0wthlab's `ADDRESS`).
ADDRESS = re.compile(r"[^\s@\"'<>()\[\]{},;:\\]@[^\s@\"'<>()\[\]{},;:\\]")
# An identifier decoded from base64 or hex counts only when it holds a whole address, so a random
# identifier never does (gr0wthlab's `ENCODED_ADDRESS`).
ENCODED_ADDRESS = re.compile(r"[A-Za-z0-9._%+-]@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")

OUTSIDE_VALUES = "the file's text, outside any value the format names"
MAX_SHOWN = 20

# A finding is one way the file departs from the reader's rules. `rule` is a stable name tests and
# operators can cite, `where` a position in the format's own words, and `text` the sentence shown.
Finding = namedtuple('Finding', 'rule where text')

Result = namedtuple('Result', 'verdict findings entries')


class Rules(object):
    """The reader's configurable rules, taken from the contract file."""

    def __init__(self, contract):
        view = contract['view']
        self.version = view['version']
        self.top_keys = tuple(view['top_keys'])
        self.entry_keys = tuple(view['entry_keys'])
        self.entry_pattern = re.compile(view['entry_pattern'])
        self.max_bytes = view['max_bytes']
        self.fit_answers = tuple(answer['tag'] for answer in contract['fit_answers'])
        self.sources = tuple(contract['source_tags']) + (contract['unknown_source'],)


def load_rules(path=CONTRACT_PATH):
    return Rules(json.loads(Path(path).read_text(encoding='utf-8')))


# The address check (gr0wthlab's `looks_like_address` ... `address_places`).


def looks_like_address(text):
    return ADDRESS.search(text) is not None


def decoded(identifier):
    """The printable text an entry identifier holds when it is read as base64, in either alphabet, or as hex."""
    candidates = []
    plain = identifier.rstrip('=').replace('-', '+').replace('_', '/')
    try:
        candidates.append(base64.b64decode(plain + '=' * (-len(plain) % 4), validate=True))
    except ValueError:
        pass
    try:
        candidates.append(bytes.fromhex(identifier))
    except ValueError:
        pass
    for data in candidates:
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            continue
        if text.isprintable():
            yield text


def encodes_address(identifier):
    """Whether an entry identifier is an address in percent-encoding (judged by the loose rule), base64 or hex
    (judged by the whole-address rule)."""
    return looks_like_address(unquote(identifier)) or any(ENCODED_ADDRESS.search(text) for text in decoded(identifier))


def address_places(value, rules):
    """Where in the parsed view a key or value looks like an address, named by position and by the format's own
    field names, never by anything the view holds."""
    places = []

    def field_name(key, known):
        return '`{}`'.format(key) if key in known else 'a field outside the format'

    def check(item, where, identifier=False):
        if isinstance(item, str):
            if looks_like_address(item) or (identifier and encodes_address(item)):
                places.append(where)
        elif isinstance(item, dict):
            for key, inner in item.items():
                if looks_like_address(str(key)):
                    places.append(where + ', a field name')
                check(inner, where)
        elif isinstance(item, list):
            for inner in item:
                check(inner, where)

    if not isinstance(value, dict):
        check(value, 'the file')
        return places
    for key, inner in value.items():
        if looks_like_address(str(key)):
            places.append('the top of the file, a field name')
        if key == 'entries' and isinstance(inner, list):
            for number, entry in enumerate(inner, 1):
                if not isinstance(entry, dict):
                    check(entry, 'entry {}'.format(number))
                    continue
                for entry_key, entry_value in entry.items():
                    where = 'entry {}, {}'.format(number, field_name(entry_key, rules.entry_keys))
                    if looks_like_address(str(entry_key)):
                        places.append('entry {}, a field name'.format(number))
                    check(entry_value, where, entry_key == 'entry')
        else:
            check(inner, 'the top of the file, ' + field_name(key, rules.top_keys))
    return places


# The view's format (gr0wthlab's `check_view`).


def parse_datetime(text):
    """An ISO 8601 date and time that states its UTC offset (gr0wthlab's `exchange.parse_datetime`)."""
    try:
        moment = datetime.fromisoformat(text.strip().replace('Z', '+00:00'))
    except ValueError:
        return None
    return moment if moment.tzinfo is not None else None


def valid_date(text):
    try:
        return date.fromisoformat(text).isoformat() == text
    except ValueError:
        return False


def check_format(data, rules):
    """Every way a parsed file departs from the view's format, as findings; empty when it follows it."""
    if not isinstance(data, dict):
        return [Finding('not-object', 'the file', 'the file is not a JSON object')]
    findings = []

    def add(rule, where, text):
        findings.append(Finding(rule, where, text))

    if sorted(data) != sorted(rules.top_keys):
        add('top-keys', 'the top of the file',
            'the file must hold exactly {} at its top'.format(', '.join(rules.top_keys)))
    version = data.get('view')
    if isinstance(version, int) and not isinstance(version, bool) and version > rules.version:
        # The reader's own message carries the number; this one does not, so no value is repeated.
        return [Finding('view-newer', '`view`',
                        'view format is newer than gr0wthlab reads (up to {})'.format(rules.version))]
    if version != rules.version or isinstance(version, bool):
        add('view-version', '`view`', 'view must be {}'.format(rules.version))
    generated = data.get('generated_at')
    generated_at = parse_datetime(generated) if isinstance(generated, str) else None
    if generated_at is None:
        add('generated-at', '`generated_at`', 'generated_at must be an ISO 8601 time with its UTC offset')
    raw = data.get('entries')
    if not isinstance(raw, list):
        add('entries-type', '`entries`', 'entries must be a list')
        return findings
    seen = set()
    for number, item in enumerate(raw, 1):
        where = 'entry {}'.format(number)
        if not isinstance(item, dict):
            add('entry-object', where, '{} is not a JSON object'.format(where))
            continue
        if sorted(item) != sorted(rules.entry_keys):
            add('entry-keys', where, '{} must hold exactly {}'.format(where, ', '.join(rules.entry_keys)))
            continue
        identifier, source, fit, opted_in, day = (item[key] for key in rules.entry_keys)
        before = len(findings)
        if not isinstance(identifier, str) or not rules.entry_pattern.fullmatch(identifier):
            add('entry-id', where + ', `entry`',
                '{}: entry must be 1 to 64 letters, digits, - or _'.format(where))
        elif identifier in seen:
            add('entry-repeat', where + ', `entry`',
                "{}: entry repeats an earlier entry's identifier".format(where))
        if source not in rules.sources:
            add('entry-source', where + ', `source`',
                '{}: source is not one of {}'.format(where, ', '.join(rules.sources)))
        if fit is not None and fit not in rules.fit_answers:
            add('entry-fit', where + ', `fit`',
                '{}: fit is not one of {}, or null'.format(where, ', '.join(rules.fit_answers)))
        if not isinstance(opted_in, bool):
            add('entry-beta', where + ', `beta_opt_in`', '{}: beta_opt_in must be true or false'.format(where))
        if not isinstance(day, str) or not valid_date(day):
            add('entry-date', where + ', `signed_up_on`',
                '{}: signed_up_on must be a YYYY-MM-DD date'.format(where))
        elif generated_at and date.fromisoformat(day) > generated_at.astimezone(timezone.utc).date():
            add('entry-date-future', where + ', `signed_up_on`',
                '{}: signed_up_on is after the day the view was generated'.format(where))
        if len(findings) == before:
            seen.add(identifier)
    return findings


# One read (gr0wthlab's `read`).


def evaluate(data, rules):
    """The verdict on a file's bytes. Like the reader, it looks at no more than the first `max_bytes + 1`
    bytes: the address check runs on them and on every parsed key and value before anything else, then the
    file-level checks, then the format."""
    data = data[:rules.max_bytes + 1]
    text = data.decode('utf-8', errors='replace')
    whole_file = looks_like_address(text)
    parsed = None
    places = []
    problem = None
    if len(data) > rules.max_bytes:
        problem = Finding('too-large', 'the file', 'is larger than {} MB'.format(rules.max_bytes // 1000000))
    else:
        try:
            parsed = json.loads(data.decode('utf-8'))
            places = address_places(parsed, rules)
        except UnicodeDecodeError:
            problem = Finding('not-utf8', 'the file', 'is not UTF-8 text')
        except RecursionError:
            problem = Finding('too-deep', 'the file', 'is nested too deeply to be the view')
        except ValueError as error:
            problem = Finding('not-json', 'the file',
                              'is not valid JSON (line {})'.format(getattr(error, 'lineno', '?')))
    if whole_file or places:
        return Result(REFUSED, [Finding('address-like', where, 'something looks like an email address')
                                for where in (places or [OUTSIDE_VALUES])], 0)
    if problem:
        return Result(FAILED, [problem], 0)
    findings = check_format(parsed, rules)
    if findings:
        return Result(FAILED, findings, 0)
    return Result(ACCEPTED, [], len(parsed['entries']))


def read_view(path, rules):
    """The first `max_bytes + 1` bytes of the file, or a failed result when it cannot be read."""
    try:
        with open(str(path), 'rb') as handle:
            return handle.read(rules.max_bytes + 1), None
    except FileNotFoundError:
        return None, Finding('unreadable', 'the file', 'is configured but does not exist')
    except IsADirectoryError:
        return None, Finding('unreadable', 'the file', "is a folder, not the view's file")
    except OSError as error:
        return None, Finding('unreadable', 'the file', 'could not be read: {}'.format(error.strerror or 'error'))


def evaluate_file(path, rules):
    data, problem = read_view(path, rules)
    if problem:
        return Result(FAILED, [problem], 0)
    return evaluate(data, rules)


def render(result):
    """The report lines for a result. They name rules and positions only."""
    if result.verdict == ACCEPTED:
        return ['check-view: accepted (entries: {})'.format(result.entries)]
    lines = ['check-view: {}'.format(result.verdict)]
    for finding in result.findings[:MAX_SHOWN]:
        lines.append('  rule {} ({}): {}'.format(finding.rule, finding.where, finding.text))
    if len(result.findings) > MAX_SHOWN:
        lines.append('  and {} more'.format(len(result.findings) - MAX_SHOWN))
    return lines


def main(argv):
    if len(argv) != 1:
        print('usage: check-view.py <view.json>', file=sys.stderr)
        return EXIT_USAGE
    try:
        result = evaluate_file(argv[0], load_rules())
    except Exception as error:  # Never let a traceback carry a value out of the file.
        print('check-view: internal error ({})'.format(type(error).__name__), file=sys.stderr)
        return EXIT_INTERNAL
    stream = sys.stdout if result.verdict == ACCEPTED else sys.stderr
    print('\n'.join(render(result)), file=stream)
    return EXIT_STATUS[result.verdict]


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

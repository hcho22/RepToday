#!/usr/bin/env python3
"""Tests for the Waitlist contract file and view checker (US-WL01).

    python3 tools/waitlist/test-check-view.py

Needs only Python 3 and this repository, no network, no secret and no Xcode. It covers:

  * the contract file's approved strings against the PRD's Appendix A, byte for byte;
  * every committed fixture under tools/waitlist/fixtures/, with the verdict and the rule it must name;
  * the address cases and the over-limit files, which are built here at run time (every address is
    assembled from parts) and written to a temporary directory outside the repository, never committed;
  * that no file under tools/waitlist/ holds an address-shaped string;
  * that no report ever repeats a value the checked file holds.

Optional read-only cross-check: set GR0WTHLAB_CHECKOUT to a gr0wthlab checkout and the same files, plus
a seeded mutation sweep, are also run through that checkout's reader (`src/gr0wthlab/waitlist.py`),
whose verdict must agree with the checker's. Nothing is ever written in that checkout: bytecode
writing is switched off before it is imported. Without the variable that class is skipped.
"""
import base64
import copy
import importlib.util
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import unittest
from collections import namedtuple
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

sys.dont_write_bytecode = True  # Importing the checker (or a gr0wthlab checkout) must leave no cache behind.

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CHECKER = HERE / 'check-view.py'
CONTRACT = HERE / 'contract.json'
FIXTURES = HERE / 'fixtures'
PRD = ROOT / '.claude/agent/tasks/prd-waitlist_261019.md'
GR0WTHLAB_ENV = 'GR0WTHLAB_CHECKOUT'


def load_checker():
    spec = importlib.util.spec_from_file_location('waitlist_check_view', str(CHECKER))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check_view = load_checker()
RULES = check_view.load_rules()
ACCEPTED, FAILED, REFUSED = check_view.ACCEPTED, check_view.FAILED, check_view.REFUSED
MAX_BYTES = RULES.max_bytes

# Addresses are assembled from parts so that no address-shaped string is ever written in this file.
AT = chr(64)
WHOLE_ADDRESS = re.compile('[A-Za-z0-9._%+-]+' + re.escape(AT) + '[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}')
CANARY = 'ZZCANARYZZ'
OUTSIDE_VALUES = "the file's text, outside any value the format names"


def address(local='tester.one', domain='example.invalid'):
    return local + AT + domain


def read_contract():
    return json.loads(CONTRACT.read_text(encoding='utf-8'))


def scratch_directory():
    directory = tempfile.TemporaryDirectory()
    resolved = Path(directory.name).resolve()
    if ROOT in resolved.parents or resolved == ROOT:
        directory.cleanup()
        raise RuntimeError('the temporary directory is inside the repository; set TMPDIR to a path outside it')
    return directory


# The contract file against the PRD's Appendix A.


def appendix_a():
    text = PRD.read_text(encoding='utf-8')
    section = text[text.index('## Appendix A'):text.index('## Appendix B')]
    return '\n'.join(re.sub(r'^> ?', '', line) for line in section.splitlines())


def ticked(values):
    return ['`{}`'.format(value) for value in values]


def appendix_mismatches(contract, appendix):
    """The approved strings of the contract file that Appendix A does not carry verbatim."""
    missing = []

    def need(name, needle):
        if needle not in appendix:
            missing.append(name)

    for name, value in sorted(contract['copy'].items()):
        need('copy.' + name, '"{}"'.format(value))
    for answer in contract['fit_answers']:
        need('fit_answers.' + answer['tag'], '"{}" (`{}`)'.format(answer['label'], answer['tag']))
    tags = [answer['tag'] for answer in contract['fit_answers']]
    need('fit_answers.list', '`fit`: {}, or {}'.format(', '.join(ticked(tags[:-1])), ticked(tags[-1:])[0]))
    sources = contract['source_tags']
    for tag in sources:
        need('source_tags.' + tag, '`reptoday.app/{}`'.format(tag))
    need('source_tags.list', '`source`: {}, or `{}`'.format(', '.join(ticked(sources)), contract['unknown_source']))
    need('no_source_event', "the visit's tag, or `{}`".format(contract['no_source_event']))
    return missing


class ContractTests(unittest.TestCase):
    def test_every_approved_string_is_byte_identical_to_appendix_a(self):
        self.assertEqual(appendix_mismatches(read_contract(), appendix_a()), [])

    def test_a_drifted_string_is_caught(self):
        appendix = appendix_a()
        for path in (['copy', 'heading'], ['copy', 'sentence'], ['copy', 'fit_legend'], ['copy', 'beta_label'],
                     ['copy', 'promise'], ['fit_answers', 0, 'label'], ['fit_answers', 1, 'tag'],
                     ['source_tags', 2], ['unknown_source'], ['no_source_event']):
            contract = read_contract()
            holder = contract
            for step in path[:-1]:
                holder = holder[step]
            holder[path[-1]] = holder[path[-1]] + 'x'
            self.assertNotEqual(appendix_mismatches(contract, appendix), [], 'drift in {} went unnoticed'.format(path))

    def test_the_contract_file_carries_the_reader_rules_that_are_not_in_the_appendix(self):
        contract = read_contract()
        self.assertEqual(contract['view'], {
            'version': 1,
            'top_keys': ['view', 'generated_at', 'entries'],
            'entry_keys': ['entry', 'source', 'fit', 'beta_opt_in', 'signed_up_on'],
            'entry_pattern': '[A-Za-z0-9_-]{1,64}',
            'max_bytes': 10000000,
        })
        self.assertEqual(len(contract['source_tags']), 4)
        self.assertEqual(len(set(contract['source_tags'])), 4)
        self.assertNotIn(contract['unknown_source'], contract['source_tags'])
        self.assertNotIn(contract['no_source_event'], contract['source_tags'])
        self.assertEqual(sorted(contract['posted_fields']), ['beta_opt_in', 'email', 'fit', 'source'])
        names = list(contract['posted_fields'].values())
        self.assertTrue(all(isinstance(name, str) and name for name in names))
        self.assertEqual(len(set(names)), 4)

    def test_the_checker_takes_its_rules_from_the_contract_file(self):
        contract = read_contract()
        self.assertEqual(RULES.sources, tuple(contract['source_tags']) + (contract['unknown_source'],))
        self.assertEqual(RULES.fit_answers, tuple(answer['tag'] for answer in contract['fit_answers']))
        self.assertEqual(RULES.max_bytes, contract['view']['max_bytes'])
        self.assertEqual(RULES.version, contract['view']['version'])


# The committed fixtures.

Case = namedtuple('Case', 'name data verdict expect')

EXPECTED = {
    'valid.json': (ACCEPTED, 3),
    'valid-empty.json': (ACCEPTED, 0),
    'valid-all-values.json': (ACCEPTED, 3),
    'valid-z-offset.json': (ACCEPTED, 3),
    'valid-utc-day.json': (ACCEPTED, 1),
    'top-keys-missing.json': (FAILED, ['top-keys', 'generated-at']),
    'top-keys-extra.json': (FAILED, ['top-keys']),
    'view-2.json': (FAILED, ['view-newer']),
    'view-true.json': (FAILED, ['view-version']),
    'view-0.json': (FAILED, ['view-version']),
    'view-string.json': (FAILED, ['view-version']),
    'generated-no-offset.json': (FAILED, ['generated-at']),
    'generated-not-a-time.json': (FAILED, ['generated-at']),
    'generated-number.json': (FAILED, ['generated-at']),
    'date-malformed.json': (FAILED, ['entry-date']),
    'date-impossible.json': (FAILED, ['entry-date']),
    'date-not-a-string.json': (FAILED, ['entry-date']),
    'date-after-generated.json': (FAILED, ['entry-date-future']),
    'entry-duplicate.json': (FAILED, ['entry-repeat']),
    'entry-length-0.json': (FAILED, ['entry-id']),
    'entry-length-65.json': (FAILED, ['entry-id']),
    'entry-bad-char.json': (FAILED, ['entry-id']),
    'entry-bad-char-space.json': (FAILED, ['entry-id']),
    'entry-bad-char-non-ascii.json': (FAILED, ['entry-id']),
    'entry-not-a-string.json': (FAILED, ['entry-id']),
    'source-unlisted.json': (FAILED, ['entry-source']),
    'source-case.json': (FAILED, ['entry-source']),
    'source-null.json': (FAILED, ['entry-source']),
    'fit-unlisted.json': (FAILED, ['entry-fit']),
    'fit-string-null.json': (FAILED, ['entry-fit']),
    'beta-string.json': (FAILED, ['entry-beta']),
    'beta-number.json': (FAILED, ['entry-beta']),
    'entry-extra-key.json': (FAILED, ['entry-keys']),
    'entry-missing-key.json': (FAILED, ['entry-keys']),
    'entry-not-an-object.json': (FAILED, ['entry-object']),
    'entries-not-a-list.json': (FAILED, ['entries-type']),
    'top-level-array.json': (FAILED, ['not-object']),
    'several-problems.json': (FAILED, ['entry-source', 'entry-fit', 'entry-beta', 'entry-date']),
    'invalid-json.json': (FAILED, ['not-json']),
    'empty.json': (FAILED, ['not-json']),
    'not-json-bom.json': (FAILED, ['not-json']),
    'not-utf8.json': (FAILED, ['not-utf8']),
}


def committed_cases():
    return [Case(name, (FIXTURES / name).read_bytes(), verdict, expect)
            for name, (verdict, expect) in sorted(EXPECTED.items())]


def assert_case(test, case, result):
    test.assertEqual(result.verdict, case.verdict, case.name)
    if case.verdict == ACCEPTED:
        test.assertEqual(result.entries, case.expect, case.name)
        test.assertEqual(result.findings, [], case.name)
    elif case.verdict == REFUSED:
        test.assertEqual([finding.where for finding in result.findings], case.expect, case.name)
        test.assertEqual({finding.rule for finding in result.findings}, {'address-like'}, case.name)
    else:
        test.assertEqual([finding.rule for finding in result.findings], case.expect, case.name)


class CommittedFixtureTests(unittest.TestCase):
    def test_every_committed_fixture_is_listed_and_every_listed_fixture_exists(self):
        self.assertEqual(sorted(path.name for path in FIXTURES.iterdir()), sorted(EXPECTED))

    def test_every_committed_fixture_gets_its_verdict_and_names_its_rule(self):
        for case in committed_cases():
            assert_case(self, case, check_view.evaluate(case.data, RULES))

    def test_the_required_failing_fixtures_exist_one_per_rule(self):
        rules = {rule for verdict, expect in EXPECTED.values() if verdict == FAILED for rule in expect}
        self.assertEqual(rules, {
            'top-keys', 'view-newer', 'view-version', 'generated-at', 'entry-date', 'entry-date-future',
            'entry-repeat', 'entry-id', 'entry-source', 'entry-fit', 'entry-beta', 'entry-keys', 'entry-object',
            'entries-type', 'not-object', 'not-json', 'not-utf8',
        })

    def test_a_valid_view_has_three_entries_with_a_null_fit_and_an_unknown_source(self):
        view = json.loads((FIXTURES / 'valid.json').read_text(encoding='utf-8'))
        self.assertEqual(len(view['entries']), 3)
        self.assertEqual(sum(1 for entry in view['entries'] if entry['fit'] is None), 1)
        self.assertEqual(sum(1 for entry in view['entries'] if entry['source'] == 'unknown'), 1)

    def test_a_valid_view_lists_entries_in_the_producers_stable_order(self):
        view = json.loads((FIXTURES / 'valid.json').read_text(encoding='utf-8'))
        order = [(entry['signed_up_on'], entry['entry']) for entry in view['entries']]
        self.assertEqual(order, sorted(order))


# The cases built at run time.


def base_view():
    return {
        'view': 1,
        'generated_at': '2026-10-11T22:00:00+00:00',
        'entries': [
            {'entry': 'k3P9xQ2m', 'source': 'tiktok', 'fit': 'lost-the-routine', 'beta_opt_in': True,
             'signed_up_on': '2026-10-05'},
            {'entry': 'Zr4-tW8_nB1c', 'source': 'unknown', 'fit': 'exercises-regularly', 'beta_opt_in': False,
             'signed_up_on': '2026-10-08'},
            {'entry': 'a7Vx0LqE92mD', 'source': 'reddit', 'fit': None, 'beta_opt_in': False,
             'signed_up_on': '2026-10-11'},
        ],
    }


def dump(view):
    return json.dumps(view).encode('utf-8')


def with_entry_value(key, value, index=1):
    view = base_view()
    view['entries'][index][key] = value
    return dump(view)


def alphabet_safe_base64_address():
    """An address whose base64 form is a legal entry identifier on its own (letters and digits only)."""
    for number in range(1000):
        text = 'user{}'.format(number) + AT + 'example.invalid'
        if len(text) % 3:
            continue
        encoded = base64.b64encode(text.encode('ascii')).decode('ascii')
        if re.fullmatch('[A-Za-z0-9]+', encoded):
            return encoded
    raise RuntimeError('no letters-and-digits base64 address found')


def padded_to(data, size):
    return data + b' ' * (size - len(data))


def generated_cases():
    addr = address()
    raw = addr.encode('ascii')
    refused = []

    def refuse(name, data, *places):
        refused.append(Case(name, data, REFUSED, list(places)))

    refuse('address-in-source', with_entry_value('source', addr), 'entry 2, `source`')
    refuse('address-in-fit', with_entry_value('fit', addr), 'entry 2, `fit`')
    view = base_view()
    view['generated_at'] = addr
    refuse('address-in-generated-at', dump(view), 'the top of the file, `generated_at`')
    refuse('address-in-an-entry-key-name', with_entry_value(addr, 'x'), 'entry 2, a field name')
    view = base_view()
    view[addr] = 'x'
    refuse('address-in-a-top-level-key-name', dump(view), 'the top of the file, a field name')
    view = base_view()
    view['note'] = addr
    refuse('address-in-an-extra-top-level-value', dump(view), 'the top of the file, a field outside the format')
    refuse('address-as-the-entry', with_entry_value('entry', addr), 'entry 2, `entry`')
    refuse('entry-percent-encoded', with_entry_value('entry', quote(addr, safe='')), 'entry 2, `entry`')
    refuse('entry-base64', with_entry_value('entry', base64.b64encode(raw).decode('ascii')), 'entry 2, `entry`')
    refuse('entry-base64-url-safe',
           with_entry_value('entry', base64.urlsafe_b64encode(raw).decode('ascii')), 'entry 2, `entry`')
    refuse('entry-base64-letters-and-digits-only',
           with_entry_value('entry', alphabet_safe_base64_address()), 'entry 2, `entry`')
    refuse('entry-hex', with_entry_value('entry', raw.hex()), 'entry 2, `entry`')
    # Percent-decoding puts an at sign between two ordinary characters, but no whole address forms: the
    # reader refuses it rather than failing it.
    refuse('entry-percent-decoding-gives-a-loose-address',
           with_entry_value('entry', 'ab%40cd'), 'entry 2, `entry`')
    view = base_view()
    view['entries'] = [addr]
    refuse('address-as-an-entry-that-is-not-an-object', dump(view), 'entry 1')
    escaped = json.dumps(dict(base_view(), note='abXXcd')).replace('XX', '\\u0040').encode('ascii')
    refuse('address-hidden-behind-a-json-escape', escaped, 'the top of the file, a field outside the format')
    refuse('address-in-text-that-is-not-json', b'this is not json ' + raw, OUTSIDE_VALUES)
    refuse('address-in-text-that-is-not-utf8', b'\xff' + raw, OUTSIDE_VALUES)
    refuse('replacement-character-beside-an-at-sign', b'\xff' + AT.encode('ascii') + b'x',
           OUTSIDE_VALUES)
    # Past the limit nothing is parsed, so the reader's address check can name only the file's text.
    over_with_address = base_view()
    over_with_address['entries'][0]['source'] = addr
    refuse('address-in-an-over-limit-file', padded_to(dump(over_with_address), MAX_BYTES + 1),
           OUTSIDE_VALUES)

    failed = [
        Case('over-limit-by-one-byte', padded_to(dump(base_view()), MAX_BYTES + 1), FAILED, ['too-large']),
        Case('address-beyond-the-bytes-the-reader-looks-at',
             padded_to(dump(base_view()), MAX_BYTES + 1) + b' ' + raw, FAILED, ['too-large']),
        Case('nested-too-deeply', b'[' * 200000, FAILED, ['too-deep']),
    ]
    accepted = [
        Case('exactly-at-the-limit', padded_to(dump(base_view()), MAX_BYTES), ACCEPTED, 3),
        Case('entry-base64-of-something-that-is-not-an-address',
             dump(dict(base_view(), entries=[dict(base_view()['entries'][0],
                       entry=base64.b64encode(b'a' + AT.encode('ascii') + b'b').decode('ascii'))])), ACCEPTED, 1),
        Case('entry-hex-of-plain-text', with_entry_value('entry', b'hello'.hex(), 0), ACCEPTED, 3),
        Case('entry-hex-looking-but-not-text', with_entry_value('entry', 'deadbeefcafe', 0), ACCEPTED, 3),
        # What the reader's own parser lets through, which the PRD's prose does not say: a JSON float 1.0
        # for the version, and the last of two equal keys.
        Case('view-written-as-the-float-1.0', dump(dict(base_view(), view=1.0)), ACCEPTED, 3),
        Case('a-repeated-top-level-key-keeps-the-last',
             dump(base_view()).replace(b'{"view": 1,', b'{"view": 2, "view": 1,'), ACCEPTED, 3),
        Case('generated-at-with-surrounding-spaces',
             dump(dict(base_view(), generated_at=' 2026-10-11T22:00:00+00:00 ')), ACCEPTED, 3),
    ]
    return refused + failed + accepted


class GeneratedCaseTests(unittest.TestCase):
    def test_every_generated_case_gets_its_verdict_and_names_its_place_or_rule(self):
        with scratch_directory() as directory:
            for case in generated_cases():
                path = Path(directory) / (case.name + '.json')
                path.write_bytes(case.data)
                assert_case(self, case, check_view.evaluate_file(path, RULES))

    def test_the_generated_cases_cover_what_the_acceptance_criteria_name(self):
        names = {case.name for case in generated_cases()}
        for name in ('address-in-source', 'address-in-fit', 'address-in-generated-at', 'address-in-an-entry-key-name',
                     'address-in-a-top-level-key-name', 'entry-percent-encoded', 'entry-base64', 'entry-hex',
                     'entry-percent-decoding-gives-a-loose-address', 'over-limit-by-one-byte'):
            self.assertIn(name, names)

    def test_a_refused_view_is_refused_even_when_it_is_also_malformed(self):
        view = base_view()
        view['view'] = 2
        view['entries'][0]['source'] = address()
        self.assertEqual(check_view.evaluate(dump(view), RULES).verdict, REFUSED)


class RepositoryHygieneTests(unittest.TestCase):
    def test_no_file_under_tools_waitlist_holds_an_address_shaped_string(self):
        scanned = 0
        for path in sorted(HERE.rglob('*')):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            text = path.read_bytes().decode('utf-8', errors='replace')
            scanned += 1
            self.assertIsNone(check_view.ADDRESS.search(text), 'loose address pattern in {}'.format(path.name))
            self.assertIsNone(WHOLE_ADDRESS.search(text), 'address in {}'.format(path.name))
        self.assertGreater(scanned, 40)

    def test_no_committed_fixture_is_an_address_or_over_the_limit(self):
        for path in FIXTURES.iterdir():
            self.assertLess(path.stat().st_size, 100000, path.name)
            self.assertNotIn(AT.encode('ascii'), path.read_bytes(), path.name)


# The command line, and what a report may say.


def run_cli(*arguments):
    return subprocess.run([sys.executable, '-B', str(CHECKER)] + [str(argument) for argument in arguments],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, check=False)


class CommandLineTests(unittest.TestCase):
    def test_a_valid_view_exits_zero(self):
        result = run_cli(FIXTURES / 'valid.json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'check-view: accepted (entries: 3)')

    def test_a_malformed_view_exits_one_and_names_the_rule_and_the_position(self):
        result = run_cli(FIXTURES / 'source-unlisted.json')
        self.assertEqual(result.returncode, 1)
        self.assertIn('rule entry-source (entry 1, `source`)', result.stderr)
        self.assertNotIn('instagram', result.stderr)

    def test_an_address_bearing_view_exits_two_and_repeats_nothing_of_the_address(self):
        with scratch_directory() as directory:
            path = Path(directory) / 'address-in-source.json'
            path.write_bytes(with_entry_value('source', address()))
            result = run_cli(path)
        self.assertEqual(result.returncode, 2)
        self.assertIn('rule address-like (entry 2, `source`)', result.stderr)
        for part in ('tester', 'example', 'invalid', AT):
            self.assertNotIn(part, result.stdout + result.stderr)

    def test_a_missing_file_fails_and_a_wrong_call_is_a_usage_error(self):
        with scratch_directory() as directory:
            missing = run_cli(Path(directory) / 'missing.json')
            folder = run_cli(directory)
        self.assertEqual(missing.returncode, 1)
        self.assertIn('rule unreadable', missing.stderr)
        self.assertEqual(folder.returncode, 1)
        self.assertIn('rule unreadable', folder.stderr)
        self.assertEqual(run_cli().returncode, 64)
        self.assertEqual(run_cli('a', 'b').returncode, 64)


class NoValueIsEchoedTests(unittest.TestCase):
    def render(self, data):
        return '\n'.join(check_view.render(check_view.evaluate(data, RULES)))

    def test_no_report_repeats_a_value_the_file_holds(self):
        addr = address()
        cases = []
        for key in ('source', 'fit', 'beta_opt_in', 'signed_up_on', 'entry'):
            cases.append(with_entry_value(key, CANARY + ' ' + key))
        view = base_view()
        view['generated_at'] = CANARY
        cases.append(dump(view))
        view = base_view()
        view['view'] = CANARY
        cases.append(dump(view))
        view = base_view()
        view[CANARY] = CANARY
        cases.append(dump(view))
        cases.append(with_entry_value(CANARY, CANARY))
        cases.append(CANARY.encode('ascii') + b'{')
        cases.append(with_entry_value('source', addr))
        cases.append(with_entry_value('entry', quote(addr, safe='')))
        cases.append(with_entry_value('entry', base64.b64encode(addr.encode('ascii')).decode('ascii')))
        cases.append(with_entry_value('entry', addr.encode('ascii').hex()))
        for data in cases:
            report = self.render(data)
            for marker in (CANARY, 'tester', 'example.invalid', AT):
                self.assertNotIn(marker, report)

    def test_a_large_version_number_is_not_repeated(self):
        view = base_view()
        view['view'] = 987654321
        self.assertNotIn('987654321', self.render(dump(view)))

    def test_every_committed_fixture_report_leaves_out_the_fixtures_own_values(self):
        # Words the format itself uses may appear in a report; any other string a fixture holds may not.
        vocabulary = set(RULES.sources) | set(RULES.fit_answers) | set(RULES.top_keys) | set(RULES.entry_keys)
        vocabulary |= {'null', 'true', 'false'}
        for name in EXPECTED:
            data = (FIXTURES / name).read_bytes()
            try:
                parsed = json.loads(data.decode('utf-8'))
            except ValueError:
                continue
            report = self.render(data)
            for value in strings_in(parsed):
                if value not in vocabulary and len(value) >= 6:
                    self.assertNotIn(value, report, name)


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, inner in value.items():
            yield key
            for text in strings_in(inner):
                yield text
    elif isinstance(value, list):
        for inner in value:
            for text in strings_in(inner):
                yield text


# Seeded mutations of a valid view: used here to show the checker never crashes or echoes, and below to
# compare it with the real reader.

POOL = [
    None, True, False, 0, 1, 1.0, 2, -1, 10 ** 30, float('nan'), float('inf'), '', ' ', 'x', 'unknown', 'tiktok',
    'TikTok', 'lost-the-routine', 'never-had-a-routine', '2026-10-12', '2026-10-11', '2026-13-40', '20261011',
    '2026-10-11T22:00:00', '2026-10-11T22:00:00Z', ' 2026-10-11T22:00:00+00:00 ', '2026-10-12T03:00:00+05:00',
    'k3P9xQ2m', 'a' * 64, 'a' * 65, [], {}, ['x'], {'a': 1}, 'Z', CANARY, 'ab%40cd', 'a%2540b',
    address(), quote(address(), safe=''), base64.b64encode(address().encode('ascii')).decode('ascii'),
    address().encode('ascii').hex(), base64.b64encode(b'a' + AT.encode('ascii') + b'b').decode('ascii'),
]
EXTRA_KEYS = ['name', 'note', 'x', CANARY, 'view', 'entries', 'fit']


def mutated_views(seed, count):
    rng = random.Random(seed)
    for _ in range(count):
        view = base_view()
        for _ in range(rng.randint(1, 3)):
            slots = [(view, key) for key in list(view)]
            if isinstance(view.get('entries'), list):
                for entry in view['entries']:
                    if isinstance(entry, dict):
                        slots.extend((entry, key) for key in list(entry))
            container, key = rng.choice(slots)
            kind = rng.choice(['set', 'set', 'set', 'delete', 'add', 'duplicate', 'entries'])
            if kind == 'set':
                container[key] = rng.choice(POOL)
            elif kind == 'delete':
                container.pop(key, None)
            elif kind == 'add':
                container[rng.choice(EXTRA_KEYS)] = rng.choice(POOL)
            elif kind == 'duplicate' and isinstance(view.get('entries'), list) and view['entries']:
                view['entries'].append(copy.deepcopy(rng.choice(view['entries'])))
            elif kind == 'entries':
                view['entries'] = rng.choice(POOL)
        yield dump(view)


def mutated_bytes(seed, count):
    rng = random.Random(seed)
    for _ in range(count):
        data = bytearray(dump(base_view()))
        for _ in range(rng.randint(1, 3)):
            kind = rng.choice(['truncate', 'flip', 'insert', 'address'])
            position = rng.randrange(len(data) + 1)
            if kind == 'truncate':
                del data[position:]
            elif kind == 'flip' and data:
                data[min(position, len(data) - 1)] = rng.randrange(256)
            elif kind == 'insert':
                data[position:position] = bytes([rng.randrange(256)])
            else:
                data[position:position] = (b'a' + AT.encode('ascii') + b'b.cd')
        yield bytes(data)


class MutationSweepTests(unittest.TestCase):
    def test_the_checker_never_crashes_and_never_echoes_on_seeded_mutations(self):
        seen = set()
        for data in list(mutated_views(20261019, 400)) + list(mutated_bytes(20261020, 200)):
            result = check_view.evaluate(data, RULES)
            seen.add(result.verdict)
            report = '\n'.join(check_view.render(result))
            for marker in (CANARY, 'tester', 'example.invalid', AT):
                self.assertNotIn(marker, report)
        self.assertEqual(seen, {ACCEPTED, FAILED, REFUSED}, 'the sweep should reach all three verdicts')


# The optional, read-only cross-check against gr0wthlab's reader.


@unittest.skipUnless(os.environ.get(GR0WTHLAB_ENV),
                     'set {} to a gr0wthlab checkout to compare with the real reader'.format(GR0WTHLAB_ENV))
class CrossCheckAgainstTheReaderTests(unittest.TestCase):
    FILE_LEVEL = {'unreadable', 'too-large', 'not-utf8', 'too-deep', 'not-json'}

    @classmethod
    def setUpClass(cls):
        sys.dont_write_bytecode = True
        checkout = Path(os.environ[GR0WTHLAB_ENV]).resolve()
        source = str(checkout / 'src')
        sys.path.insert(0, source)
        try:
            from gr0wthlab import waitlist, settings
        finally:
            sys.path.remove(source)
        cls.reader = waitlist
        cls.settings = settings
        products = json.loads((checkout / 'config/products.json').read_text(encoding='utf-8'))
        configured = [product['waitlist'] for product in products['products'] if product.get('waitlist')]
        assert len(configured) == 1, 'expected exactly one Product with a Waitlist'
        cls.configured = configured[0]
        cls.started = datetime(2026, 10, 12, 12, 0, tzinfo=timezone.utc)

    def rules_for(self, path):
        configured = self.configured
        return self.settings.Waitlist(
            product='RepToday', view=Path(path), source_tags=tuple(configured['source_tags']),
            fit_answers=tuple(configured['fit_answers']), good_fit=tuple(configured['good_fit']),
            bar=int(configured['beta_cohort_bar']))

    def listed(self, items):
        shown = '; '.join(items[:5])
        return shown + ('; and {} more'.format(len(items) - 5) if len(items) > 5 else '')

    def assert_agrees(self, path, label):
        mine = check_view.evaluate_file(path, RULES)
        reading = self.reader.read(self.rules_for(path), self.started)
        verdicts = {self.reader.READ: ACCEPTED, self.reader.FAILED: FAILED, self.reader.REFUSED: REFUSED}
        self.assertEqual(verdicts[reading.status], mine.verdict, label)
        if mine.verdict == ACCEPTED:
            self.assertEqual(len(reading.entries), mine.entries, label)
        elif mine.verdict == REFUSED:
            self.assertEqual(list(reading.places), [finding.where for finding in mine.findings], label)
        else:
            detail = re.sub(r'view format -?\d+ is newer', 'view format is newer', reading.detail)
            if len(mine.findings) == 1 and mine.findings[0].rule in self.FILE_LEVEL:
                expected = '`{}` {}.'.format(Path(path), mine.findings[0].text)
            else:
                expected = "`{}` does not follow the view's format: {}.".format(
                    Path(path), self.listed([finding.text for finding in mine.findings]))
            self.assertEqual(detail, expected, label)

    def test_the_contract_file_lists_the_sources_and_answers_the_reader_is_configured_with(self):
        contract = read_contract()
        self.assertEqual(contract['source_tags'], self.configured['source_tags'])
        self.assertEqual([answer['tag'] for answer in contract['fit_answers']], self.configured['fit_answers'])
        self.assertEqual(contract['view']['version'], self.reader.VIEW_FORMAT)
        self.assertEqual(contract['view']['max_bytes'], self.reader.MAX_VIEW_BYTES)
        self.assertEqual(contract['view']['top_keys'], list(self.reader.TOP_KEYS))
        self.assertEqual(contract['view']['entry_keys'], list(self.reader.ENTRY_KEYS))
        self.assertEqual(contract['view']['entry_pattern'], self.reader.ENTRY_PATTERN.pattern)
        self.assertEqual(contract['unknown_source'], self.settings.UNKNOWN)

    def test_the_checker_and_the_reader_agree_on_every_committed_fixture(self):
        for case in committed_cases():
            self.assert_agrees(FIXTURES / case.name, case.name)

    def test_the_checker_and_the_reader_agree_on_every_generated_case(self):
        with scratch_directory() as directory:
            for case in generated_cases():
                path = Path(directory) / (case.name + '.json')
                path.write_bytes(case.data)
                self.assert_agrees(path, case.name)

    def test_the_checker_and_the_reader_agree_on_a_missing_file_and_a_folder(self):
        with scratch_directory() as directory:
            self.assert_agrees(Path(directory) / 'missing.json', 'missing file')
            self.assert_agrees(directory, 'folder')

    def test_the_checker_and_the_reader_agree_on_seeded_mutations(self):
        verdicts = set()
        with scratch_directory() as directory:
            path = Path(directory) / 'mutation.json'
            for number, data in enumerate(list(mutated_views(20261019, 400)) + list(mutated_bytes(20261020, 200))):
                path.write_bytes(data)
                self.assert_agrees(path, 'mutation {}'.format(number))
                verdicts.add(check_view.evaluate(data, RULES).verdict)
        self.assertEqual(verdicts, {ACCEPTED, FAILED, REFUSED})


if __name__ == '__main__':
    unittest.main()

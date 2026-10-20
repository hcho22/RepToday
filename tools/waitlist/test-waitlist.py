#!/usr/bin/env python3
"""Tests for the Waitlist's Mac-side tooling (US-WL06 storage and identifiers, US-WL07 view producer, US-WL09
send-time lookup, US-WL10 removal and retention).

    python3 tools/waitlist/test-waitlist.py

Python 3 standard library only, no network beyond loopback, no Keychain, no credential and no real address:

  * the store logic runs against a synthetic store (a JSON file in a temporary directory) and against the real
    Kit client over HTTP to `fake_kit.py`, a local fake of the part of Kit's API the tooling uses;
  * every address is assembled from parts at run time and written only to a temporary directory outside the
    repository; no file in the repository holds one;
  * the command is run as a subprocess (the way the scheduled job runs it) for the cases that need a real
    process: a crash between a write and its rename, two runs started at once, a hung run, a pseudo-terminal
    for `show` and for the address prompt of `remove`;
  * every command's output is checked to hold no address, answer or key.
"""
import json
import os
import plistlib
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import date, timedelta
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

import fake_kit  # noqa: E402
import wl_common  # noqa: E402
import wl_core  # noqa: E402
import wl_store  # noqa: E402
from wl_store import KitStore, RestrictedStore, StoreError, SyntheticStore  # noqa: E402

WAITLIST = HERE / 'waitlist.py'
CHECK_VIEW = HERE / 'check-view.py'
AT = chr(64)  # addresses are assembled from parts, so none is ever written in this file
KEY = 'test-' + 'key-' + 'value'  # the fake's key, never a real one


def address(label):
    return 'wl-{}{}example.com'.format(label, AT)


def contains_address(text):
    return wl_core.check_view.ENCODED_ADDRESS.search(text) is not None or AT in text


class KeepsKey(dict):
    """A fake Kit record that ignores every write to one key, as a record Kit would not change that way."""

    def __init__(self, record, key):
        dict.__init__(self, record)
        self.kept = key

    def __setitem__(self, key, value):
        if key != self.kept:
            dict.__setitem__(self, key, value)


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='waitlist-test-'))
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        self.state = self.tmp / 'state'
        self.store_path = self.tmp / 'store.json'
        self.records = []
        self.next_id = 100

    # A synthetic store.

    def add(self, state='active', created='2026-10-05T12:00:00Z', fit=None, beta=None, source=None, entry=None,
            email=None, label=None):
        self.next_id += 1
        label = label or 's{}'.format(self.next_id)
        self.records.append({'id': str(self.next_id), 'email': email or address(label), 'state': state,
                             'created_at': created, 'fields': {'fit': fit, 'beta_opt_in': beta, 'source': source, 'entry': entry}})
        self.save_store()
        return str(self.next_id)

    def save_store(self):
        self.store_path.write_text(json.dumps({'subscribers': self.records}), encoding='utf-8')

    def reload_store(self):
        self.records = json.loads(self.store_path.read_text(encoding='utf-8'))['subscribers']
        return {record['id']: record for record in self.records}

    def synthetic(self):
        return SyntheticStore(self.store_path)

    # The command, as a subprocess.

    def cli(self, *arguments, env=None, expect=None, check_output=True):
        environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        environment.pop(wl_common.FAULT_ENV, None)
        environment.update(env or {})
        done = subprocess.run([sys.executable, str(WAITLIST)] + list(arguments) + [
            '--state-dir', str(self.state), '--synthetic', str(self.store_path)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=environment, cwd=str(self.tmp), timeout=120)
        output = done.stdout.decode('utf-8', 'replace')
        if check_output:
            self.assertFalse(contains_address(output), 'a command printed an address-shaped string')
            self.assertNotIn(KEY, output)
        if expect is not None:
            self.assertEqual(done.returncode, expect, output)
        return done.returncode, output

    def view(self):
        return json.loads((self.state / wl_common.VIEW_NAME).read_text(encoding='utf-8'))

    def launch_record(self, sent_days_ago):
        """The launch-email record `record-launch-email` would have written on the day the email went out."""
        sent_on = (wl_common.today_local() - timedelta(days=sent_days_ago)).isoformat()
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        (self.state / wl_common.LAUNCH_NAME).write_text(json.dumps({'launch_email': 1, 'sent_on': sent_on, 'recorded_on': sent_on}))

    def ledger(self):
        return json.loads((self.state / wl_common.LEDGER_NAME).read_text(encoding='utf-8'))['subscribers']

    def check_view_file(self):
        done = subprocess.run([sys.executable, str(CHECK_VIEW), str(self.state / wl_common.VIEW_NAME)],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(done.returncode, 0, done.stdout.decode())


class SevenSignups(Case):
    """US-WL07's Validation Test store: seven sign-ups out of date order, two on one day."""

    def setUp(self):
        super(SevenSignups, self).setUp()
        self.ticked = self.add(created='2026-10-05T12:00:00Z', fit='lost-the-routine', beta='true', source='tiktok')
        self.null_fit = self.add(created='2026-10-01T23:59:59Z')
        self.same_a = self.add(created='2026-10-03T08:00:00Z', fit='exercises-regularly', beta='false', source='reddit')
        self.out_of_set = self.add(created='2026-10-03T09:00:00Z', fit='whatever', beta='yes', source='Facebook')
        self.no_entry = self.add(created='2026-10-04T10:00:00Z', fit='never-had-a-routine', beta='true', source='network')
        self.unconfirmed = self.add(state='inactive', created='2026-10-04T11:00:00Z', fit='lost-the-routine', beta='true', source='youtube')
        self.cancelled = self.add(state='cancelled', created='2026-10-02T11:00:00Z', fit='lost-the-routine', source='tiktok')
        # The ledger already holds an identifier for every sign-up but `no_entry` (and the unconfirmed one, the
        # cancelled one): the two same-day sign-ups get identifiers that sort opposite to their ids.
        self.known = {self.ticked: 'TickedEntry000001', self.null_fit: 'NullFitEntry00001', self.same_a: 'zzSameDayEntry001',
                      self.out_of_set: 'aaSameDayEntry002'}
        self.state.mkdir(parents=True, mode=0o700)
        payload = {'ledger': 1, 'subscribers': {key: {'entry': value, 'source': 'unknown'} for key, value in self.known.items()}}
        payload['subscribers'][self.ticked]['source'] = 'tiktok'
        payload['subscribers'][self.same_a]['source'] = 'reddit'
        (self.state / wl_common.LEDGER_NAME).write_text(json.dumps(payload), encoding='utf-8')

    def test_view_projects_exactly_five_fields_in_stable_order(self):
        self.cli('produce', expect=0)
        self.check_view_file()
        view = self.view()
        self.assertEqual(sorted(view), ['entries', 'generated_at', 'view'])
        self.assertEqual(view['view'], 1)
        entries = view['entries']
        for entry in entries:
            self.assertEqual(sorted(entry), ['beta_opt_in', 'entry', 'fit', 'signed_up_on', 'source'])
        self.assertEqual([item['signed_up_on'] for item in entries], sorted(item['signed_up_on'] for item in entries))
        by_entry = {item['entry']: item for item in entries}
        # five confirmed sign-ups: the unconfirmed and the unsubscribed one are absent
        self.assertEqual(len(entries), 5)
        ledger = self.ledger()
        self.assertNotIn(ledger[self.unconfirmed]['entry'], by_entry)
        self.assertNotIn(self.cancelled, ledger)  # an unsubscribed sign-up never gets an identifier
        # a null Fit and an unknown Source; a ticked box; the out-of-set values become null/unknown/false
        self.assertEqual(by_entry['NullFitEntry00001'], {'entry': 'NullFitEntry00001', 'source': 'unknown', 'fit': None,
                                                         'beta_opt_in': False, 'signed_up_on': '2026-10-01'})
        self.assertEqual(by_entry['TickedEntry000001']['beta_opt_in'], True)
        self.assertEqual(by_entry['TickedEntry000001']['source'], 'tiktok')
        self.assertEqual(by_entry['aaSameDayEntry002'], {'entry': 'aaSameDayEntry002', 'source': 'unknown', 'fit': None,
                                                         'beta_opt_in': False, 'signed_up_on': '2026-10-03'})
        # the two same-day sign-ups are written in entry order, not store order
        same_day = [item['entry'] for item in entries if item['signed_up_on'] == '2026-10-03']
        self.assertEqual(same_day, ['aaSameDayEntry002', 'zzSameDayEntry001'])
        # the sign-up with no identifier was given one, in the ledger and in the store, never reassigned later
        assigned = ledger[self.no_entry]['entry']
        self.assertRegex(assigned, wl_core.ENTRY_PATTERN.pattern)
        self.assertEqual(self.reload_store()[self.no_entry]['fields']['entry'], assigned)
        self.assertEqual(by_entry[assigned]['source'], 'network')
        self.assertEqual(by_entry[assigned]['fit'], 'never-had-a-routine')

    def test_unconfirmed_signup_appears_once_confirmed_with_its_submission_date(self):
        self.cli('produce', expect=0)
        self.assertNotIn(self.unconfirmed, [self.ledger_id(item['entry']) for item in self.view()['entries']])
        entry_before = self.ledger()[self.unconfirmed]['entry']
        self.reload_store()
        for record in self.records:
            if record['id'] == self.unconfirmed:
                record['state'] = 'active'
        self.save_store()
        self.cli('produce', expect=0)
        listed = {item['entry']: item for item in self.view()['entries']}
        self.assertIn(entry_before, listed)
        self.assertEqual(listed[entry_before]['signed_up_on'], '2026-10-04')
        self.assertEqual(len(listed), 6)

    def ledger_id(self, entry):
        for key, record in self.ledger().items():
            if record['entry'] == entry:
                return key
        return None

    def test_removal_drops_exactly_one_entry_and_keeps_every_other_identifier(self):
        self.cli('produce', expect=0)
        before = {item['entry']: item for item in self.view()['entries']}
        gone = 'TickedEntry000001'
        self.cli('remove', '--entry', gone, expect=0)
        after = {item['entry']: item for item in self.view()['entries']}
        self.assertEqual(set(before) - set(after), {gone})
        for entry in after:
            self.assertEqual(after[entry], before[entry])
        record = self.reload_store()[self.ticked]
        self.assertEqual(record['state'], 'cancelled')
        self.assertNotIn(AT, record['email'])
        self.assertTrue(all(value is None for value in record['fields'].values()))
        self.assertNotIn(self.ticked, self.ledger())
        self.check_view_file()

    def test_planted_entry_in_kit_is_reset_to_the_ledgers_value(self):
        # a public post can set Kit's entry field (D1): plant an address-shaped value and another sign-up's identifier
        planted = 'planted' + AT + 'example.com'
        for record in self.records:
            if record['id'] == self.null_fit:
                record['fields']['entry'] = planted
            if record['id'] == self.same_a:
                record['fields']['entry'] = 'TickedEntry000001'
        self.save_store()
        self.cli('produce', expect=0)
        text = (self.state / wl_common.VIEW_NAME).read_text(encoding='utf-8')
        self.assertNotIn(AT, text)
        store = self.reload_store()
        self.assertEqual(store[self.null_fit]['fields']['entry'], 'NullFitEntry00001')
        self.assertEqual(store[self.same_a]['fields']['entry'], 'zzSameDayEntry001')
        self.check_view_file()

    def test_two_runs_started_at_once_give_the_new_signup_one_identifier(self):
        environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        command = [sys.executable, str(WAITLIST), 'produce', '--state-dir', str(self.state), '--synthetic', str(self.store_path)]
        processes = [subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=environment) for _ in range(3)]
        outputs = [process.communicate(timeout=120)[0] for process in processes]
        self.assertEqual([process.returncode for process in processes], [0, 0, 0], outputs)
        ledger = self.ledger()
        entry = ledger[self.no_entry]['entry']
        self.assertEqual(self.reload_store()[self.no_entry]['fields']['entry'], entry)
        self.assertEqual(sum(1 for item in self.view()['entries'] if item['entry'] == entry), 1)
        self.assertEqual(len(set(record['entry'] for record in ledger.values())), len(ledger))

    def test_files_are_owner_only(self):
        self.cli('produce', expect=0)
        self.assertEqual(os.stat(str(self.state)).st_mode & 0o777, 0o700)
        for name in (wl_common.VIEW_NAME, wl_common.LEDGER_NAME):
            self.assertEqual(os.stat(str(self.state / name)).st_mode & 0o777, 0o600, name)
        self.assertEqual(list(self.state.glob('.waitlist-*.tmp')), [])

    def test_a_removed_signup_is_gone_from_the_next_view_after_a_hung_run(self):
        """US-WL07 step 8 / US-WL10 step 5: a hung run ends within its bound without writing, the removal it was
        holding up then runs, and the first view generated after the removal omits the removed sign-up."""
        self.cli('produce', expect=0)
        bytes_before = (self.state / wl_common.VIEW_NAME).read_bytes()
        removed_entry = 'NullFitEntry00001'
        environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', **{wl_common.RUN_LIMIT_ENV: '3', wl_common.FAULT_ENV: 'after-read:hang'})
        base = ['--state-dir', str(self.state), '--synthetic', str(self.store_path)]
        hung = subprocess.Popen([sys.executable, str(WAITLIST), 'produce'] + base, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=environment)
        deadline = time.monotonic() + 20
        while not self.lock_is_held() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(self.lock_is_held(), 'the hung run never took the lock')
        clean = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        removal = subprocess.Popen([sys.executable, str(WAITLIST), 'remove', '--entry', removed_entry] + base,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=clean)
        started = time.monotonic()
        hung_output = hung.communicate(timeout=30)[0].decode()
        self.assertEqual(hung.returncode, 3, hung_output)
        self.assertLess(time.monotonic() - started, 15)  # bounded by the limit, not by the hang
        self.assertEqual((self.state / wl_common.VIEW_NAME).read_bytes(), bytes_before)  # the hung run wrote nothing
        removal_output = removal.communicate(timeout=60)[0].decode()
        self.assertEqual(removal.returncode, 0, removal_output)
        self.assertNotIn(removed_entry, [item['entry'] for item in self.view()['entries']])
        # and the next scheduled run keeps it out
        self.cli('produce', expect=0)
        self.assertNotIn(removed_entry, [item['entry'] for item in self.view()['entries']])

    def lock_is_held(self):
        import fcntl
        path = self.state / wl_common.LOCK_NAME
        if not path.exists():
            return False
        descriptor = os.open(str(path), os.O_RDWR)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            return False
        except OSError:
            return True
        finally:
            os.close(descriptor)


class ProducerSafety(Case):
    def test_interrupted_write_leaves_the_complete_old_file_and_blocks_no_later_run(self):
        self.add(created='2026-10-05T12:00:00Z', fit='lost-the-routine', beta='true', source='tiktok')
        self.cli('produce', expect=0)
        old = (self.state / wl_common.VIEW_NAME).read_bytes()
        self.add(created='2026-10-06T12:00:00Z', fit='exercises-regularly', beta='false', source='reddit')
        code, _ = self.cli('produce', env={wl_common.FAULT_ENV: 'after-temp-write'})
        self.assertEqual(code, 137)
        self.assertEqual((self.state / wl_common.VIEW_NAME).read_bytes(), old)  # never a partial file
        self.assertTrue(list(self.state.glob('.waitlist-*.tmp')), 'the crash should have left a temporary file')
        self.cli('produce', expect=0)  # a leftover blocks nothing, and the run cleans it up
        self.assertEqual(len(self.view()['entries']), 2)
        self.assertEqual(list(self.state.glob('.waitlist-*.tmp')), [])
        self.check_view_file()

    def test_a_failing_check_leaves_the_previous_file_untouched_and_prints_no_value(self):
        self.add(created='2026-10-05T12:00:00Z', fit='lost-the-routine', beta='true', source='tiktok')
        self.cli('produce', expect=0)
        old = (self.state / wl_common.VIEW_NAME).read_bytes()
        # a record created after the view is generated (a clock far ahead) fails the checker's date rule
        self.add(created='2099-01-01T00:00:00Z', fit='lost-the-routine', beta='true', source='tiktok')
        code, output = self.cli('produce')
        self.assertEqual(code, 2, output)
        self.assertIn('entry-date-future', output)
        self.assertIn('previous file is untouched', output)
        self.assertEqual((self.state / wl_common.VIEW_NAME).read_bytes(), old)

    def test_an_address_in_the_candidate_is_refused_and_never_replaces_the_file(self):
        self.add(created='2026-10-05T12:00:00Z', fit='lost-the-routine', beta='true', source='tiktok')
        self.cli('produce', expect=0)
        path = self.state / wl_common.VIEW_NAME
        old = path.read_bytes()
        planted = address('planted')

        def poison(candidate):
            return candidate.replace(b'"source": "tiktok"', ('"source": "{}"'.format(planted)).encode())

        with self.assertRaises(wl_core.CheckRefused) as raised:
            wl_core.produce_view(self.synthetic(), self.state, mutate_candidate=poison)
        self.assertEqual(raised.exception.verdict, 'refused')
        self.assertNotIn(planted, str(raised.exception))
        self.assertNotIn(AT, str(raised.exception))
        self.assertEqual(path.read_bytes(), old)

    def test_a_view_over_the_byte_limit_fails_instead_of_truncating(self):
        self.add(created='2026-10-05T12:00:00Z')
        wl_core.produce_view(self.synthetic(), self.state)
        old = (self.state / wl_common.VIEW_NAME).read_bytes()
        limit = wl_core.RULES.max_bytes
        with self.assertRaises(wl_common.WaitlistError) as raised:
            wl_core.produce_view(self.synthetic(), self.state, mutate_candidate=lambda data: data + b' ' * (limit + 1))
        self.assertIn('exceed', str(raised.exception))
        self.assertEqual((self.state / wl_common.VIEW_NAME).read_bytes(), old)

    def test_write_backs_past_the_soft_deadline_are_left_for_the_next_run_and_the_view_is_still_written(self):
        first = self.add(fit='lost-the-routine', beta='true', source='tiktok')
        second = self.add(created='2026-10-06T12:00:00Z')
        # a 120 second limit leaves no time before the reserve, so not one write-back to Kit is started
        code, output = self.cli('produce', env={wl_common.RUN_LIMIT_ENV: '120'}, expect=0)
        self.assertIn('2 entry write-backs to Kit were left for the next run', output)
        self.assertEqual(len(self.view()['entries']), 2)
        self.check_view_file()
        store = self.reload_store()
        self.assertEqual([store[key]['fields']['entry'] for key in (first, second)], [None, None])
        self.cli('produce', expect=0)
        store, ledger = self.reload_store(), self.ledger()
        for key in (first, second):
            self.assertEqual(store[key]['fields']['entry'], ledger[key]['entry'])

    def test_an_output_into_an_existing_folder_keeps_that_folders_mode(self):
        self.add()
        shared = self.tmp / 'shared'
        shared.mkdir()
        os.chmod(str(shared), 0o755)
        self.cli('produce', '--output', str(shared / 'view.json'), expect=0)
        self.assertEqual(os.stat(str(shared)).st_mode & 0o777, 0o755)
        self.assertEqual(os.stat(str(shared / 'view.json')).st_mode & 0o777, 0o600)
        fresh = self.tmp / 'fresh' / 'deeper'
        self.cli('produce', '--output', str(fresh / 'view.json'), expect=0)
        self.assertEqual(os.stat(str(fresh)).st_mode & 0o777, 0o700)  # a folder the run created is owner-only

    def test_an_empty_store_writes_an_empty_entries_list(self):
        self.save_store()
        self.cli('produce', expect=0)
        self.assertEqual(self.view()['entries'], [])
        self.check_view_file()

    def test_refuses_a_path_inside_a_work_tree_or_a_symlink_into_one(self):
        self.add()
        inside = ROOT / 'tools' / 'waitlist' / 'must-not-be-written'
        self.assertFalse(inside.exists())
        code, output = self.cli('produce', '--output', str(inside / 'view.json'))
        self.assertEqual(code, 1, output)
        self.assertFalse(inside.exists())
        link = self.tmp / 'link'
        os.symlink(str(ROOT / 'tools'), str(link))
        code, output = self.cli('produce', '--output', str(link / 'view.json'))
        self.assertEqual(code, 1, output)
        self.assertFalse((ROOT / 'tools' / 'view.json').exists())
        # a symlink to a file in the checkout, in an otherwise fine directory
        target = ROOT / 'tools' / 'waitlist' / 'must-not-be-written.json'
        os.symlink(str(target), str(self.tmp / 'file-link.json'))
        code, output = self.cli('produce', '--output', str(self.tmp / 'file-link.json'))
        self.assertEqual(code, 1, output)
        self.assertFalse(target.exists())
        # the state directory itself, inside the checkout
        done = subprocess.run([sys.executable, str(WAITLIST), 'produce', '--state-dir', str(inside), '--synthetic', str(self.store_path)],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertFalse(inside.exists())
        # a plain directory whose ancestor holds a `.git` file, as a linked worktree does
        worktree = self.tmp / 'worktree'
        (worktree / 'deep').mkdir(parents=True)
        (worktree / '.git').write_text('gitdir: elsewhere\n')
        code, output = self.cli('produce', '--output', str(worktree / 'deep' / 'view.json'))
        self.assertEqual(code, 1, output)
        self.assertFalse((worktree / 'deep' / 'view.json').exists())

    def test_a_damaged_ledger_stops_the_run_and_the_view_stays(self):
        self.add()
        self.cli('produce', expect=0)
        old = (self.state / wl_common.VIEW_NAME).read_bytes()
        (self.state / wl_common.LEDGER_NAME).write_text('{not json')
        code, output = self.cli('produce')
        self.assertEqual(code, 1)
        self.assertIn('ledger is damaged', output)
        self.assertEqual((self.state / wl_common.VIEW_NAME).read_bytes(), old)

    def test_a_ledger_entry_that_is_not_an_identifier_is_refused(self):
        sub = self.add()
        self.state.mkdir(mode=0o700)
        (self.state / wl_common.LEDGER_NAME).write_text(json.dumps({'ledger': 1, 'subscribers': {
            sub: {'entry': 'x' + AT + 'example.com', 'source': 'unknown'}}}))
        code, output = self.cli('produce')
        self.assertEqual(code, 1)
        self.assertFalse(contains_address(output))

    def test_a_corrupt_creation_time_fails_the_run_rather_than_dropping_the_signup(self):
        self.add(created='not a time')
        code, output = self.cli('produce')
        self.assertEqual(code, 1, output)
        self.assertFalse((self.state / wl_common.VIEW_NAME).exists())

    def test_first_seen_source_is_kept_when_a_resubmission_overwrites_it(self):
        sub = self.add(fit='lost-the-routine', beta='false', source='tiktok')
        self.cli('produce', expect=0)
        for record in self.records:
            if record['id'] == sub:
                record['fields'].update({'source': 'unknown', 'fit': 'exercises-regularly', 'beta_opt_in': 'true'})
        self.save_store()
        self.cli('produce', expect=0)
        (entry,) = self.view()['entries']
        self.assertEqual((entry['source'], entry['fit'], entry['beta_opt_in']), ('tiktok', 'exercises-regularly', True))


class Identifiers(Case):
    def test_five_thousand_identifiers_match_are_unique_and_pass_the_address_check(self):
        seen = set()
        for _ in range(5000):
            entry = wl_common.new_entry(seen)
            self.assertRegex(entry, r'^[A-Za-z0-9_-]{1,64}$')
            self.assertEqual(len(entry), 16)
            self.assertFalse(wl_core.check_view.looks_like_address(entry))
            self.assertFalse(wl_core.check_view.encodes_address(entry))
            seen.add(entry)
        self.assertEqual(len(seen), 5000)

    def test_an_identifier_is_not_a_function_of_the_address(self):
        first = [wl_common.new_entry() for _ in range(2)]
        self.assertNotEqual(*first)
        # two stores holding the same address assign unrelated identifiers
        ids = []
        for _ in range(2):
            directory = Path(tempfile.mkdtemp(prefix='waitlist-test-'))
            self.addCleanup(shutil.rmtree, str(directory), True)
            path = directory / 'store.json'
            path.write_text(json.dumps({'subscribers': [{'id': '1', 'email': address('same'), 'state': 'active',
                                                         'created_at': '2026-10-05T12:00:00Z', 'fields': {}}]}))
            wl_core.produce_view(SyntheticStore(path), directory / 'state')
            ids.append(json.loads((directory / 'state' / wl_common.LEDGER_NAME).read_text())['subscribers']['1']['entry'])
        self.assertNotEqual(*ids)

    def test_the_same_address_re_added_after_a_removal_gets_a_different_identifier(self):
        email = address('again')
        first = self.add(email=email, fit='lost-the-routine', beta='true', source='tiktok')
        self.cli('produce', expect=0)
        old_entry = self.ledger()[first]['entry']
        self.cli('remove', '--entry', old_entry, expect=0)
        self.reload_store()
        # Kit gives a re-added address a brand-new subscriber (a new id) once the old one is a shell
        second = self.add(email=email, fit='lost-the-routine', beta='true', source='reddit')
        self.cli('produce', expect=0)
        new_entry = self.ledger()[second]['entry']
        self.assertNotEqual(old_entry, new_entry)
        self.assertEqual([item['entry'] for item in self.view()['entries']], [new_entry])
        self.assertEqual(self.view()['entries'][0]['source'], 'reddit')

    def test_a_repeat_signup_never_creates_a_second_entry(self):
        sub = self.add(fit='lost-the-routine', beta='true', source='tiktok')
        self.cli('produce', expect=0)
        entry = self.ledger()[sub]['entry']
        for record in self.records:  # Kit overwrites the answers of the same subscriber on a resubmission
            record['fields'].update({'fit': 'exercises-regularly', 'beta_opt_in': 'false'})
        self.save_store()
        self.cli('produce', expect=0)
        (only,) = self.view()['entries']
        self.assertEqual(only['entry'], entry)
        self.assertEqual((only['fit'], only['beta_opt_in']), ('exercises-regularly', False))


class Removal(Case):
    def sweep_world(self):
        self.keep = self.add(fit='lost-the-routine', beta='true', source='tiktok')
        self.gone = self.add(fit='lost-the-routine', beta='false', source='reddit')
        self.pending = self.add(state='inactive', fit='lost-the-routine')
        self.cli('produce', expect=0)

    def test_unsubscribed_sweep_is_a_dry_run_by_default_then_deletes_when_live(self):
        self.sweep_world()
        for record in self.records:
            if record['id'] == self.gone:
                record['state'] = 'cancelled'
        self.save_store()
        code, output = self.cli('sweep-unsubscribed', expect=0)
        self.assertIn('dry run, nothing deleted', output)
        self.assertIn('due 1', output)
        self.assertIn(AT, self.reload_store()[self.gone]['email'])  # nothing deleted
        code, output = self.cli('sweep-unsubscribed', '--live', expect=0)
        self.assertIn('erased 1', output)
        store = self.reload_store()
        self.assertNotIn(AT, store[self.gone]['email'])
        self.assertTrue(all(value is None for value in store[self.gone]['fields'].values()))
        self.assertIn(AT, store[self.keep]['email'])  # nobody else touched
        self.assertIn(AT, store[self.pending]['email'])
        entries = [item['entry'] for item in self.view()['entries']]
        self.assertEqual(len(entries), 1)  # the view was regenerated after the deletion
        self.cli('sweep-unsubscribed', '--live', expect=0)  # idempotent: a shell is not erased again
        self.assertIn('due 0', self.cli('sweep-unsubscribed', '--live')[1])

    def test_retention_deletes_nothing_without_a_recorded_date_and_exits_zero(self):
        self.sweep_world()
        code, output = self.cli('sweep-retention', '--live', '--as-of', '2099-01-01', expect=0)
        self.assertIn('no launch-email date is recorded', output)
        for record in self.reload_store().values():
            self.assertIn(AT, record['email'])

    def test_no_date_recorded_still_deletes_an_unsubscribed_signup_and_refreshes_the_view(self):
        """The captain's carried finding: with no launch-email date the daily job deletes nothing by retention but
        still erases an unsubscribed sign-up and writes a fresh view."""
        self.sweep_world()
        for record in self.records:
            if record['id'] == self.gone:
                record['state'] = 'cancelled'
        self.save_store()
        before = self.view()['generated_at']
        time.sleep(1.1)
        code, output = self.cli('daily', '--live', expect=0)
        self.assertIn('daily: all 3 steps ok', output)
        self.assertIn('no launch-email date is recorded', output)
        store = self.reload_store()
        self.assertNotIn(AT, store[self.gone]['email'])
        self.assertIn(AT, store[self.keep]['email'])
        self.assertGreater(self.view()['generated_at'], before)
        self.assertEqual(len(self.view()['entries']), 1)

    def record(self, text, today=None, replace=False):
        return wl_core.record_launch_email(self.state, text, today or date(2026, 11, 10), replace=replace)

    def test_record_launch_email_prints_the_deletion_date_and_refuses_bad_dates(self):
        today = date(2026, 11, 10)
        with self.assertRaises(wl_common.WaitlistError) as future:
            self.record('2026-11-11', today)
        self.assertIn('future', str(future.exception))
        with self.assertRaises(wl_common.WaitlistError) as month_old:
            self.record('2026-10-10', today)  # a month ago: retention would delete everyone tomorrow
        self.assertIn('more than 7 days ago', str(month_old.exception))
        self.assertIn('2026-11-09', str(month_old.exception))
        for bad in ('2026-02-30', '10/10/2026', '2026-1-1', '', 'tomorrow', '2026-11-10T00:00'):
            with self.assertRaises(wl_common.WaitlistError):
                self.record(bad, today)
        self.assertFalse((self.state / wl_common.LAUNCH_NAME).exists(), 'a refused date records nothing')
        sent_on, deletes_on = self.record('2026-11-04', today)  # six days ago is inside the window
        self.assertEqual((sent_on, deletes_on), (date(2026, 11, 4), date(2026, 12, 4)))
        self.record('2026-11-10', today, replace=True)
        self.assertEqual(wl_core.read_launch_record(self.state), date(2026, 11, 10))
        self.assertEqual(os.stat(str(self.state / wl_common.LAUNCH_NAME)).st_mode & 0o777, 0o600)
        self.record('2026-11-03', today, replace=True)  # exactly seven days is the edge of the window
        with self.assertRaises(wl_common.WaitlistError):
            self.record('2026-11-02', today, replace=True)

    def test_a_launch_email_is_recorded_once(self):
        self.record('2026-11-10')
        with self.assertRaises(wl_common.WaitlistError) as again:
            self.record('2026-11-09')
        self.assertIn('already recorded', str(again.exception))
        self.assertEqual(wl_core.read_launch_record(self.state), date(2026, 11, 10))

    def test_record_launch_email_from_the_command_line(self):
        today = wl_common.today_local()
        code, output = self.cli('record-launch-email', '--sent-on', (today + timedelta(days=2)).isoformat())
        self.assertEqual(code, 1)
        self.assertIn('future', output)
        code, output = self.cli('record-launch-email', '--sent-on', (today - timedelta(days=30)).isoformat())
        self.assertEqual(code, 1)
        self.assertIn('refused', output)
        self.assertFalse((self.state / wl_common.LAUNCH_NAME).exists())
        code, output = self.cli('record-launch-email', '--sent-on', (today - timedelta(days=2)).isoformat(), expect=0)
        self.assertIn((today - timedelta(days=2) + timedelta(days=30)).isoformat(), output)

    def test_retention_deletes_nothing_at_29_days_and_everything_at_30(self):
        self.sweep_world()
        self.record('2026-11-10')  # sent 2026-11-10: due on 2026-12-10
        for as_of, expected in (('2026-12-09', 0), ('2026-12-10', 3)):
            code, output = self.cli('sweep-retention', '--live', '--as-of', as_of, expect=0)
            erased = sum(1 for record in self.reload_store().values() if AT not in record['email'])
            self.assertEqual(erased, expected, (as_of, output))
        self.assertEqual(self.view()['entries'], [])  # the view was regenerated after the deletion
        self.check_view_file()

    def test_retention_dry_run_counts_and_deletes_nothing_even_when_due(self):
        self.sweep_world()
        self.record('2026-11-10')
        code, output = self.cli('sweep-retention', '--as-of', '2027-01-01', expect=0)
        self.assertIn('dry run, nothing deleted', output)
        self.assertIn('due 3', output)
        for record in self.reload_store().values():
            self.assertIn(AT, record['email'])

    def test_as_of_cannot_move_a_live_sweep_against_the_real_store(self):
        # without --synthetic the clock override is refused for a live sweep (checked before any store is opened)
        done = subprocess.run([sys.executable, str(WAITLIST), 'sweep-retention', '--live', '--as-of', '2099-01-01',
                               '--state-dir', str(self.state)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(done.returncode, 1)
        self.assertIn('--as-of', done.stdout.decode())

    def test_a_damaged_or_hand_edited_launch_record_deletes_nothing(self):
        self.sweep_world()
        self.state.mkdir(exist_ok=True, mode=0o700)
        path = self.state / wl_common.LAUNCH_NAME
        cases = {
            'garbage': '{nope',
            'a month-old date': json.dumps({'launch_email': 1, 'sent_on': '2026-10-01', 'recorded_on': '2026-11-10'}),
            'sent after recorded': json.dumps({'launch_email': 1, 'sent_on': '2026-11-11', 'recorded_on': '2026-11-10'}),
            'wrong version': json.dumps({'launch_email': 2, 'sent_on': '2026-11-10', 'recorded_on': '2026-11-10'}),
        }
        for name, text in cases.items():
            path.write_text(text)
            code, output = self.cli('sweep-retention', '--live', '--as-of', '2099-01-01')
            self.assertEqual(code, 1, name)
            self.assertIn('nothing was deleted', output)
            for record in self.reload_store().values():
                self.assertIn(AT, record['email'], name)

    def test_a_stale_listing_of_an_erased_signup_never_brings_it_back(self):
        """Kit's listing trails a write by up to a couple of minutes: a read made just after an erasure can still show
        the old record. The ledger's tombstone keeps it out of the view, off the identifier assignment and out of
        the sweeps."""
        self.sweep_world()
        entry = self.ledger()[self.keep]['entry']
        stale = [dict(record, fields=dict(record['fields'])) for record in self.records if record['id'] == self.keep][0]
        self.cli('remove', '--entry', entry, expect=0)
        self.reload_store()
        for record in self.records:  # the lagging listing: the erased record is still there, active, with its address
            if record['id'] == self.keep:
                record.clear()
                record.update(stale)
        self.save_store()
        code, output = self.cli('produce', expect=0)
        self.assertIn('assigned 0', output)
        self.assertNotIn(entry, [item['entry'] for item in self.view()['entries']])
        self.assertEqual(len(self.view()['entries']), 1)  # only the other confirmed sign-up
        self.assertNotIn(self.keep, self.ledger())
        self.assertIn(self.keep, json.loads((self.state / wl_common.LEDGER_NAME).read_text())['erased'])
        stale_fields = self.reload_store()[self.keep]['fields']
        self.assertEqual(stale_fields['entry'], stale['fields']['entry'])  # nothing was written to the stale record
        code, output = self.cli('sweep-retention', '--live', '--as-of', '2099-01-01', expect=0)
        self.assertIn('no launch-email date', output)

    def test_remove_by_entry_is_exact_and_names_an_unknown_one(self):
        self.sweep_world()
        entry = self.ledger()[self.keep]['entry']
        code, output = self.cli('remove', '--entry', entry[:-1] + ('A' if entry[-1] != 'A' else 'B'))
        self.assertEqual(code, 1)
        self.assertIn('no sign-up has entry identifier', output)
        code, output = self.cli('remove', '--entry', entry, '--dry-run', expect=0)
        self.assertIn(AT, self.reload_store()[self.keep]['email'])
        self.cli('remove', '--entry', entry, expect=0)
        store = self.reload_store()
        self.assertNotIn(AT, store[self.keep]['email'])
        self.assertIn(AT, store[self.gone]['email'])
        self.assertIn(AT, store[self.pending]['email'])

    def test_remove_by_address_is_typed_at_a_prompt_never_an_argument(self):
        self.sweep_world()
        near = self.add(email=address(self.records[0]['id'] + 'x'), fit='lost-the-routine')  # an address that merely contains another
        target = self.records[0]['email']
        # a pipe is not a prompt
        done = subprocess.run([sys.executable, str(WAITLIST), 'remove', '--state-dir', str(self.state), '--synthetic', str(self.store_path)],
                              input=(target + '\n').encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(done.returncode, 1)
        self.assertIn(AT, self.reload_store()[self.keep]['email'])
        # a typed address on a terminal
        output, code = run_in_pty(['remove', '--state-dir', str(self.state), '--synthetic', str(self.store_path)], typed=target)
        self.assertEqual(code, 0, output)
        self.assertNotIn(target, output)  # not shown while typed, never printed
        store = self.reload_store()
        self.assertNotIn(AT, store[self.keep]['email'])
        self.assertIn(AT, store[near]['email'])  # the match is exact, so a different person's record is untouched
        self.assertIn(AT, store[self.gone]['email'])
        # an address that is on no record erases nothing
        output, code = run_in_pty(['remove', '--state-dir', str(self.state), '--synthetic', str(self.store_path)], typed=address('nobody'))
        self.assertEqual(code, 1, output)
        self.assertIn('no sign-up has that address', output)

    def test_an_erased_signup_keeps_no_first_name_or_other_field(self):
        sub = self.add(fit='lost-the-routine', beta='true', source='tiktok')
        leftover = self.add(state='cancelled', email='removed-0')  # no address, but a name a scrub missed
        for record in self.records:
            if record['id'] in (sub, leftover):
                record['first_name'] = 'Named'
                record['fields']['last_name'] = 'Other'
        self.save_store()
        self.cli('produce', expect=0)
        self.cli('remove', '--entry', self.ledger()[sub]['entry'], expect=0)
        code, output = self.cli('sweep-unsubscribed', '--live', expect=0)
        self.assertIn('erased 1', output)
        store = self.reload_store()
        for key in (sub, leftover):
            self.assertIsNone(store[key]['first_name'])
            self.assertIn('last_name', store[key]['fields'])
            self.assertTrue(all(value is None for value in store[key]['fields'].values()))

    def test_a_dry_run_changes_nothing_and_the_hash_of_the_store_stays(self):
        self.sweep_world()
        for record in self.records:
            if record['id'] == self.gone:
                record['state'] = 'cancelled'
        self.save_store()
        before = self.store_path.read_bytes()
        self.cli('sweep-unsubscribed', expect=0)
        self.cli('sweep-retention', expect=0)
        self.assertEqual(self.store_path.read_bytes(), before)


class DailyJob(Case):
    def test_a_step_that_fails_does_not_stop_the_next_and_is_reported(self):
        keep = self.add(fit='lost-the-routine', beta='true', source='tiktok')
        self.state.mkdir(mode=0o700)
        (self.state / wl_common.LAUNCH_NAME).write_text('{damaged')
        code, output = self.cli('daily', '--live')
        self.assertEqual(code, 1, output)
        self.assertIn('daily: step sweep-unsubscribed ok', output)
        self.assertIn('daily: step sweep-retention FAILED (exit 1)', output)
        self.assertIn('daily: step produce ok', output)
        self.assertIn('1 of 3 steps failed: sweep-retention', output)
        self.assertEqual(len(self.view()['entries']), 1)  # the producer still ran
        self.assertIn(AT, self.reload_store()[keep]['email'])

    def test_a_hung_first_step_is_cut_off_and_the_rest_still_run(self):
        self.add(fit='lost-the-routine', beta='true', source='tiktok')
        code, output = self.cli('daily', '--live', env={wl_common.RUN_LIMIT_ENV: '2', wl_common.FAULT_ENV: 'sweep-unsubscribed:hang'})
        self.assertEqual(code, 1, output)
        self.assertIn('daily: step sweep-unsubscribed FAILED (exit 3)', output)
        self.assertIn('daily: step sweep-retention ok', output)
        self.assertIn('daily: step produce ok', output)
        self.assertEqual(len(self.view()['entries']), 1)

    def test_every_step_ok_exits_zero(self):
        self.add()
        code, output = self.cli('daily', '--live', expect=0)
        self.assertIn('daily: all 3 steps ok', output)

    def test_without_live_the_sweeps_are_dry_runs(self):
        sub = self.add(state='cancelled', fit='lost-the-routine')
        code, output = self.cli('daily', expect=0)
        self.assertIn('dry-run sweeps', output)
        self.assertIn(AT, self.reload_store()[sub]['email'])

    def test_the_retention_step_repeats_passes_until_a_store_larger_than_one_pass_is_erased(self):
        """A 121 second limit leaves each pass one second before the reserve to start erasures in, and each erasure
        pauses 0.3 seconds, so one pass erases at most four of the ten sign-ups. Every Kit state is due."""
        states = ('active', 'inactive', 'bounced', 'complained')
        for number in range(10):
            self.add(state=states[number % len(states)], fit='lost-the-routine', beta='true', source='tiktok')
        self.launch_record(sent_days_ago=31)
        code, output = self.cli('daily', '--live', env={wl_common.RUN_LIMIT_ENV: '121', wl_common.FAULT_ENV: 'erase:pause'})
        self.assertEqual(code, 0, output)
        self.assertIn('sweep-retention: incomplete', output)
        self.assertIn('starting pass 2', output)
        self.assertIn('daily: step sweep-retention ok', output)
        for record in self.reload_store().values():
            self.assertNotIn(AT, record['email'])
            self.assertTrue(all(value is None for value in record['fields'].values()))
        self.assertEqual(self.view()['entries'], [])

    def test_a_view_that_cannot_be_written_after_a_pass_does_not_stop_the_next_pass(self):
        """The last sign-up is dated in the future, so every view made while it is still listed fails the checker; the
        passes that erase the others still count their erasures and the next pass runs."""
        for _ in range(7):
            self.add(fit='lost-the-routine')
        self.add(created='2099-01-01T00:00:00Z', fit='lost-the-routine')
        self.launch_record(sent_days_ago=31)
        code, output = self.cli('daily', '--live', env={wl_common.RUN_LIMIT_ENV: '121', wl_common.FAULT_ENV: 'erase:pause'})
        self.assertEqual(code, 0, output)
        self.assertIn('entry-date-future', output)
        self.assertIn('starting pass 2', output)
        self.assertIn('daily: step sweep-retention ok', output)
        for record in self.reload_store().values():
            self.assertNotIn(AT, record['email'])
        self.assertEqual(self.view()['entries'], [])

    def test_a_retention_pass_that_erases_nothing_fails_the_step_and_is_not_repeated(self):
        for _ in range(3):
            self.add(fit='lost-the-routine')
        self.launch_record(sent_days_ago=31)
        # a 120 second limit leaves no time before the reserve, so the pass starts no erasure
        code, output = self.cli('daily', '--live', env={wl_common.RUN_LIMIT_ENV: '120'})
        self.assertEqual(code, 1, output)
        self.assertIn('daily: step sweep-retention FAILED (exit 1)', output)
        self.assertNotIn('starting pass 2', output)
        self.assertIn('daily: step produce ok', output)
        for record in self.reload_store().values():
            self.assertIn(AT, record['email'])

    def test_the_launchd_definition_runs_the_live_daily_job_and_holds_no_secret(self):
        path = HERE / 'launchd' / 'app.reptoday.waitlist-daily.plist'
        definition = plistlib.loads(path.read_bytes())
        arguments = definition['ProgramArguments']
        self.assertEqual(arguments[0], '/usr/bin/python3')
        self.assertTrue(arguments[1].endswith('tools/waitlist/waitlist.py'))
        self.assertEqual(arguments[2:], ['daily', '--live'])
        self.assertIn('StartCalendarInterval', definition)
        self.assertNotIn('EnvironmentVariables', definition)


class KitClient(unittest.TestCase):
    """The real Kit client over HTTP to the local fake."""

    def setUp(self):
        self.fake = fake_kit.FakeKit(KEY).start()
        self.addCleanup(self.fake.stop)
        self.store = KitStore(KEY, base_url=self.fake.url, timeout=5)
        self.tmp = Path(tempfile.mkdtemp(prefix='waitlist-test-'))
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        self.state = self.tmp / 'state'

    def test_listing_follows_every_page_and_never_returns_an_address(self):
        original = wl_store.PAGE_SIZE
        wl_store.PAGE_SIZE = 2
        self.addCleanup(setattr, wl_store, 'PAGE_SIZE', original)
        ids = [self.fake.add(address('p{}'.format(number)), source='tiktok') for number in range(5)]
        self.fake.add(address('gone'), state='cancelled')
        listed = self.store.list_subscribers()
        self.assertEqual(sorted(item.id for item in listed), sorted(str(item) for item in ids + [ids[-1] + 1]))
        for item in listed:
            self.assertNotIn(AT, repr(item))
            self.assertNotIn('email', item._fields)
        self.assertEqual({item.state for item in listed}, {'active', 'cancelled'})
        self.assertTrue(all(request[2] for request in self.fake.requests), 'every request carried the key')

    def test_the_view_is_produced_through_the_kit_client_and_planted_entries_are_reset(self):
        good = self.fake.add(address('good'), created_at='2026-10-05T12:00:00Z', fit='lost-the-routine', beta_opt_in='true', source='tiktok')
        planted = self.fake.add(address('planted'), created_at='2026-10-06T12:00:00Z', entry='planted' + AT + 'example.com')
        unconfirmed = self.fake.add(address('wait'), state='inactive', created_at='2026-10-06T12:00:00Z')
        counts = wl_core.produce_view(self.store, self.state)
        self.assertEqual((counts['entries'], counts['assigned'], counts['unconfirmed']), (2, 3, 1))
        ledger = json.loads((self.state / wl_common.LEDGER_NAME).read_text())['subscribers']
        for subscriber_id in (good, planted, unconfirmed):
            self.assertEqual(self.fake.get(subscriber_id)['fields']['entry'], ledger[str(subscriber_id)]['entry'])
        text = (self.state / wl_common.VIEW_NAME).read_text()
        self.assertNotIn(AT, text)
        # a second run assigns nothing and rewrites nothing in Kit
        writes = [request for request in self.fake.requests if request[0] == 'PUT']
        again = wl_core.produce_view(self.store, self.state)
        self.assertEqual((again['assigned'], again['reset']), (0, 0))
        self.assertEqual([request for request in self.fake.requests if request[0] == 'PUT'], writes)

    def test_erase_unsubscribes_overwrites_the_address_and_blanks_every_field(self):
        subscriber = self.fake.add(address('erase'), fit='lost-the-routine', beta_opt_in='true', source='tiktok', entry='SomeEntry')
        bystander = self.fake.add(address('stay'), fit='lost-the-routine')
        self.store.erase(subscriber)
        record = self.fake.get(subscriber)
        self.assertEqual(record['state'], 'cancelled')
        self.assertEqual(record['email_address'], 'removed-{}'.format(subscriber))
        self.assertTrue(all(value is None for value in record['fields'].values()))
        self.assertIn(AT, self.fake.get(bystander)['email_address'])
        self.assertTrue([item for item in self.store.list_subscribers() if item.id == str(subscriber)][0].scrubbed)

    def test_erase_blanks_the_first_name_and_every_other_custom_field(self):
        subscriber = self.fake.add(address('named'), fit='lost-the-routine', source='tiktok')
        record = self.fake.get(subscriber)
        record['first_name'] = 'Named'
        record['fields']['last_name'] = 'Other'  # a custom field this tooling does not name
        self.store.erase(subscriber)
        record = self.fake.get(subscriber)
        self.assertIsNone(record['first_name'])
        self.assertEqual(set(record['fields']), set(fake_kit.FIELD_NAMES) | {'last_name'})
        self.assertTrue(all(value is None for value in record['fields'].values()))

    def test_erase_that_does_not_scrub_is_reported(self):
        for kept, value in (('email_address', None), ('first_name', 'Named')):
            subscriber = self.fake.add(address('stubborn-' + kept), fit='lost-the-routine')
            record = self.fake.subscribers[subscriber]
            if value is not None:
                record[kept] = value
            self.fake.subscribers[subscriber] = KeepsKey(record, kept)  # Kit keeps it however it is written
            with self.assertRaises(StoreError) as raised:
                self.store.erase(subscriber)
            self.assertIn('not erased', str(raised.exception), kept)

    def test_erase_accepts_a_bounced_or_complained_record_that_keeps_its_state(self):
        for state in (wl_store.BOUNCED, wl_store.COMPLAINED):
            subscriber = self.fake.add(address(state), state=state, fit='lost-the-routine')
            self.fake.subscribers[subscriber] = KeepsKey(self.fake.subscribers[subscriber], 'state')
            self.store.erase(subscriber)
            record = self.fake.get(subscriber)
            self.assertEqual(record['state'], state)
            self.assertNotIn(AT, record['email_address'])
        mailed = self.fake.add(address('still-mailed'), fit='lost-the-routine')
        self.fake.subscribers[mailed] = KeepsKey(self.fake.subscribers[mailed], 'state')
        with self.assertRaises(StoreError):
            self.store.erase(mailed)  # a record Kit still mails is never called erased

    def test_find_by_address_is_exact_and_ignores_case(self):
        target = self.fake.add('Mixed-Case' + AT + 'example.com')
        self.fake.add('mixed-case-2' + AT + 'example.com')
        self.assertEqual(self.store.find_id_by_email('mixed-case' + AT + 'EXAMPLE.com'), str(target))
        self.assertIsNone(self.store.find_id_by_email('mixed' + AT + 'example.com'))

    def test_errors_never_carry_the_address_the_url_the_body_or_the_key(self):
        self.fake.mode = 'error'
        for call in (lambda: self.store.find_id_by_email(address('secret')), self.store.list_subscribers,
                     lambda: self.store.set_entry('1', 'x')):
            with self.assertRaises(StoreError) as raised:
                call()
            text = str(raised.exception)
            self.assertIn('HTTP 500', text)
            for banned in (AT, KEY, 'secret', '/v4', 'http://'):
                self.assertNotIn(banned, text)
        wrong = KitStore('another-' + 'key', base_url=self.fake.url, timeout=5)
        self.fake.mode = 'normal'
        with self.assertRaises(StoreError) as raised:
            wrong.list_subscribers()
        self.assertIn('HTTP 401', str(raised.exception))

    def test_an_answer_cut_short_is_a_store_error(self):
        subscriber = self.fake.add(address('cut'), fit='lost-the-routine')
        self.fake.mode = 'truncated'
        for call in (self.store.list_subscribers, lambda: self.store.erase(subscriber)):
            with self.assertRaises(StoreError) as raised:
                call()
            self.assertIn('no answer', str(raised.exception))

    def test_a_call_that_never_answers_ends_by_its_timeout(self):
        self.fake.mode = 'hang'
        quick = KitStore(KEY, base_url=self.fake.url, timeout=0.5)
        started = time.monotonic()
        with self.assertRaises(StoreError) as raised:
            quick.list_subscribers()
        self.assertLess(time.monotonic() - started, 5)
        self.assertIn('no answer', str(raised.exception))

    def test_a_busy_answer_is_retried_a_bounded_number_of_times(self):
        original = wl_store.RETRY_PAUSES
        wl_store.RETRY_PAUSES = (0.01, 0.01)
        self.addCleanup(setattr, wl_store, 'RETRY_PAUSES', original)
        self.fake.mode, self.fake.busy_count = 'busy', 2
        self.assertEqual(self.store.list_subscribers(), [])
        self.fake.busy_count = 5
        with self.assertRaises(StoreError) as raised:
            self.store.list_subscribers()
        self.assertIn('HTTP 503', str(raised.exception))

    def test_a_rate_limit_answer_is_waited_out_as_kit_asks_a_bounded_number_of_times(self):
        original = wl_store.MAX_RETRY_WAIT_SECONDS
        wl_store.MAX_RETRY_WAIT_SECONDS = 0.05
        self.addCleanup(setattr, wl_store, 'MAX_RETRY_WAIT_SECONDS', original)
        self.fake.mode, self.fake.busy_status, self.fake.busy_retry_after = 'busy', 429, 120  # asked to wait 2 minutes: capped
        self.fake.busy_count = 5
        started = time.monotonic()
        self.assertEqual(self.store.list_subscribers(), [])
        self.assertLess(time.monotonic() - started, 5)
        self.fake.busy_count = 6
        with self.assertRaises(StoreError) as raised:
            self.store.list_subscribers()
        self.assertIn('HTTP 429', str(raised.exception))

    def test_the_key_can_only_go_to_kit_or_to_loopback(self):
        for url in ('https://example.com', 'http://api.kit.com', 'https://api.kit.com.evil.test', 'http://10.0.0.1:80'):
            with self.assertRaises(StoreError):
                KitStore(KEY, base_url=url)
        KitStore(KEY, base_url='https://api.kit.com')
        KitStore(KEY, base_url='http://127.0.0.1:9')

    def test_a_missing_keychain_item_is_an_error_that_names_the_item_not_a_key(self):
        with self.assertRaises(StoreError) as raised:
            wl_store.read_api_key('com.reptoday.waitlist.no-such-item-for-the-test')
        self.assertIn('no Kit API key in the Keychain', str(raised.exception))
        self.assertIn('com.reptoday.waitlist.no-such-item-for-the-test', str(raised.exception))

    def test_a_sweep_through_the_kit_client_deletes_only_what_it_may(self):
        gone = self.fake.add(address('gone'), state='cancelled', fit='lost-the-routine')
        stay = self.fake.add(address('stay'), state='active', fit='lost-the-routine')
        outsider = self.fake.add(address('outsider'), state='cancelled', fit='lost-the-routine')
        restricted = RestrictedStore(self.store, [gone, stay])
        counts = wl_core.sweep_unsubscribed(restricted, self.state, live=True)
        self.assertEqual((counts['due'], counts['erased']), (1, 1))
        self.assertNotIn(AT, self.fake.get(gone)['email_address'])
        self.assertIn(AT, self.fake.get(stay)['email_address'])
        self.assertIn(AT, self.fake.get(outsider)['email_address'])  # outside the named set: never read, never written
        with self.assertRaises(StoreError):
            restricted.erase(outsider)

    def test_retention_through_the_kit_client_with_an_injected_clock(self):
        wl_core.record_launch_email(self.state, '2026-11-10', date(2026, 11, 10))
        states = ('active', 'inactive', 'cancelled', 'bounced', 'complained')
        ids = [self.fake.add(address('r{}'.format(n)), state=state) for n, state in enumerate(states)]
        early = wl_core.sweep_retention(self.store, self.state, date(2026, 12, 9), live=True)
        self.assertEqual((early['due'], early['erased'], early['not_due']), (0, 0, True))
        for subscriber_id in ids:
            self.assertIn(AT, self.fake.get(subscriber_id)['email_address'])
        due = wl_core.sweep_retention(self.store, self.state, date(2026, 12, 10), live=True)
        self.assertEqual((due['due'], due['erased']), (5, 5))
        for subscriber_id in ids:
            self.assertNotIn(AT, self.fake.get(subscriber_id)['email_address'])
        later = wl_core.sweep_retention(self.store, self.state, date(2026, 12, 11), live=True)
        self.assertEqual(later['due'], 0)  # shells are not erased again

    def test_tagging_marks_exactly_the_named_signups_and_a_batch_of_twenty_five_is_one_call(self):
        ids = [self.fake.add(address('t{}'.format(n)), created_at='2026-10-05T12:00:00Z', fit='lost-the-routine') for n in range(25)]
        wl_core.produce_view(self.store, self.state)
        ledger = json.loads((self.state / wl_common.LEDGER_NAME).read_text())['subscribers']
        entries = [ledger[str(item)]['entry'] for item in ids]
        self.assertEqual(wl_core.tag_entries(self.store, self.state, 'beta-test', entries), 25)
        self.assertEqual(self.store.tag_members('beta-test'), sorted(str(item) for item in ids))
        self.assertEqual(wl_core.tag_entries(self.store, self.state, 'second', entries[:2] + entries[:2]), 2)
        self.assertEqual(self.store.tag_members('second'), sorted(str(item) for item in ids[:2]))

    def test_the_kit_client_reads_an_address_only_for_the_two_calls_that_mean_to(self):
        subscriber = self.fake.add(address('reader'), fit='lost-the-routine')
        self.assertEqual(self.store.email_of(subscriber), address('reader'))
        for item in self.store.list_subscribers():
            self.assertFalse(any(isinstance(value, str) and AT in value for value in item))


class SendTimeLookup(Case):
    def world(self):
        self.a = self.add(fit='lost-the-routine', beta='true', source='tiktok')
        self.b = self.add(fit='exercises-regularly', beta='true', source='reddit')
        self.c = self.add(fit='lost-the-routine', beta='false')
        self.waiting = self.add(state='inactive')
        self.cli('produce', expect=0)
        return {key: self.ledger()[key]['entry'] for key in (self.a, self.b, self.c, self.waiting)}

    def test_tag_marks_the_named_signups_and_nobody_else(self):
        entries = self.world()
        self.cli('tag', 'beta-test', entries[self.a], entries[self.b], expect=0)
        tagged = sorted(record['id'] for record in self.reload_store().values() if 'beta-test' in (record.get('tags') or []))
        self.assertEqual(tagged, sorted([self.a, self.b]))

    def test_an_unknown_malformed_or_unconfirmed_identifier_is_an_error_naming_it_and_tags_nothing(self):
        entries = self.world()
        code, output = self.cli('tag', 'beta-test', entries[self.a], 'NoSuchEntry00000', 'bad id!', entries[self.waiting])
        self.assertEqual(code, 1)
        self.assertIn("'NoSuchEntry00000' is not a known entry identifier", output)
        self.assertIn("'bad id!' is not an entry identifier", output)
        self.assertIn('is not a confirmed sign-up', output)
        self.assertFalse([record for record in self.reload_store().values() if record.get('tags')], 'all or nothing')

    def test_an_address_given_as_an_identifier_is_never_echoed(self):
        self.world()
        code, output = self.cli('tag', 'beta-test', address('pasted'))
        self.assertEqual(code, 1)
        self.assertIn('argument 1 is not an entry identifier', output)

    def test_a_label_outside_the_allowed_characters_is_refused(self):
        entries = self.world()
        code, output = self.cli('tag', 'bad/label', entries[self.a])
        self.assertEqual(code, 1)

    def test_show_prints_once_to_a_terminal_and_refuses_a_pipe_or_a_redirect(self):
        entries = self.world()
        wanted = [record['email'] for record in self.records if record['id'] == self.a][0]
        base = ['--state-dir', str(self.state), '--synthetic', str(self.store_path)]
        output, code = run_in_pty(['show', entries[self.a]] + base)
        self.assertEqual(code, 0, output)
        self.assertEqual(output.count(wanted), 1)
        redirected = self.tmp / 'out.txt'
        with open(str(redirected), 'wb') as handle:
            done = subprocess.run([sys.executable, str(WAITLIST), 'show', entries[self.a]] + base, stdout=handle, stderr=subprocess.PIPE)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(redirected.read_bytes(), b'')
        self.assertNotIn(wanted.encode(), done.stderr)
        piped = subprocess.run([sys.executable, str(WAITLIST), 'show', entries[self.a]] + base, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(piped.returncode, 1)
        self.assertNotIn(AT.encode(), piped.stdout + piped.stderr)
        self.assertIn(b'interactive terminal', piped.stdout + piped.stderr)

    def test_show_on_a_terminal_names_an_unknown_identifier(self):
        self.world()
        base = ['--state-dir', str(self.state), '--synthetic', str(self.store_path)]
        output, code = run_in_pty(['show', 'NoSuchEntry00000'] + base)
        self.assertEqual(code, 1)
        self.assertIn('NoSuchEntry00000', output)

    def test_no_address_reaches_the_state_directory_or_any_log(self):
        self.world()
        self.cli('tag', 'beta-test', self.ledger()[self.a]['entry'], expect=0)
        for path in self.state.rglob('*'):
            if path.is_file():
                data = path.read_bytes()
                for record in self.records:
                    self.assertNotIn(record['email'].encode(), data, path.name)
                self.assertNotIn(AT.encode(), data, path.name)


def run_in_pty(arguments, typed=None, timeout=60):
    """Run the command with a pseudo-terminal as its stdin, stdout and stderr, typing `typed` at a prompt. Returns
    (what the terminal showed, the exit status)."""
    pid, descriptor = pty.fork()
    if pid == 0:
        environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        os.execve(sys.executable, [sys.executable, str(WAITLIST)] + list(arguments), environment)
    shown = b''
    sent = typed is None
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([descriptor], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(descriptor, 4096)
            except OSError:
                break
            if not chunk:
                break
            shown += chunk
        if not sent and b'Address to remove' in shown:
            os.write(descriptor, (typed + '\n').encode())
            sent = True
    _, status = os.waitpid(pid, 0)
    return shown.decode('utf-8', 'replace'), os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1


class DateLogic(unittest.TestCase):
    def test_deletion_date_and_retention_boundary(self):
        sent = date(2026, 11, 10)
        self.assertEqual(wl_common.deletion_date(sent), date(2026, 12, 10))
        self.assertFalse(wl_common.retention_due(sent, date(2026, 12, 9)))
        self.assertTrue(wl_common.retention_due(sent, date(2026, 12, 10)))
        self.assertTrue(wl_common.retention_due(sent, date(2027, 6, 1)))

    def test_signed_up_on_is_the_utc_date(self):
        self.assertEqual(wl_common.utc_day_of('2026-10-05T23:30:00-07:00'), date(2026, 10, 6))
        self.assertEqual(wl_common.utc_day_of('2026-10-05T00:00:00Z'), date(2026, 10, 5))
        self.assertIsNone(wl_common.utc_day_of('2026-10-05T00:00:00'))
        self.assertIsNone(wl_common.utc_day_of('later'))

    def test_the_launch_window_edges(self):
        today = date(2026, 11, 10)
        self.assertEqual(wl_common.validate_launch_date('2026-11-10', today), today)
        self.assertEqual(wl_common.validate_launch_date('2026-11-03', today), date(2026, 11, 3))
        for refused in ('2026-11-11', '2026-11-02', '2026-10-10', '2026-13-01'):
            with self.assertRaises(wl_common.WaitlistError):
                wl_common.validate_launch_date(refused, today)


if __name__ == '__main__':
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Tests for the Waitlist address-boundary guard and the checkout audit (US-WL08).

    python3 tools/test-check-no-waitlist-credentials.py

Python 3 standard library plus `git`, no network and no secret. Every sabotage (a credential, an export, an
address, a binary file) is written into a scratch directory, never into the repository, and every address and
credential-shaped value is assembled from parts so this file holds none. A real-tree test requires the guard to
pass on the repository itself, which holds `Bearer` test fixtures and the two URL-userinfo inputs.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
GUARD = ROOT / 'tools' / 'check-no-waitlist-credentials.py'
AUDIT = ROOT / 'tools' / 'waitlist' / 'audit-checkouts.sh'

AT = chr(64)
KIT_KEY_NAME = 'KIT' + '_API' + '_KEY'
KIT_SECRET_NAME = 'CONVERTKIT' + '_API' + '_SECRET'
KIT_HEADER = 'X-Kit' + '-Api-' + 'Key'
VALUE = '0123' + '4567' + '89abcdef'  # looks like a key, is not one
PASSWORD_DOMAIN = 'password' + AT + 'api.storekit.apple.com'


def address(label):
    return 'subscriber-{}{}mail-provider.net'.format(label, AT)


def load_guard():
    spec = importlib.util.spec_from_file_location('check_no_waitlist_credentials', str(GUARD))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


guard = load_guard()


class Scratch(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='waitlist-guard-')).resolve()
        self.addCleanup(shutil.rmtree, str(self.root), True)
        git(self.root, 'init', '-q')
        (self.root / '.gitignore').write_text('.env\nignored/\n')

    def write(self, relative, content, binary=False):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding='utf-8')
        return path

    def run_guard(self, *extra):
        done = subprocess.run([sys.executable, str(GUARD)] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              cwd=str(self.root))
        return done.returncode, (done.stdout + done.stderr).decode('utf-8', 'replace')

    def check(self):
        return self.run_guard(str(self.root))

    def findings(self, *extra):
        code, output = self.run_guard(*extra) if extra else self.check()
        return code, [line for line in output.splitlines() if line.startswith('error: ') and ': rule ' in line], output


def git(directory, *arguments):
    subprocess.run(['git', '-C', str(directory)] + list(arguments), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def rules_of(findings):
    return sorted(set(line.split(': rule ')[1] for line in findings))


class CleanAndSabotage(Scratch):
    def test_the_real_tree_passes(self):
        done = subprocess.run([sys.executable, str(GUARD)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=str(ROOT))
        self.assertEqual(done.returncode, 0, done.stdout.decode())
        self.assertIn('0 findings', done.stdout.decode())

    def test_a_clean_scratch_tree_passes_and_each_sabotage_fails_with_its_own_rule(self):
        self.write('README.md', 'nothing here\n')
        code, found, output = self.findings()
        self.assertEqual(code, 0, output)
        sabotage = {
            'credential-assignment': ('settings.sh', '{}={}\n'.format(KIT_KEY_NAME, VALUE)),
            'export-file': ('subscribers.csv', 'name,email\nA,{}\n'.format(address('one'))),
            'address': ('notes.txt', 'ask {} about it\n'.format(address('two'))),
        }
        for rule, (name, content) in sabotage.items():
            path = self.write(name, content)
            code, found, output = self.findings()
            self.assertEqual(code, 1, (rule, output))
            self.assertIn(rule, rules_of(found), (rule, output))
            self.assertTrue(any(line.startswith('error: {}:'.format(name)) for line in found))
            self.assertNotIn(VALUE, output)
            self.assertNotIn(AT, output.replace(AT + 'ignored', ''), 'a finding repeated an address')
            path.unlink()
            code, found, output = self.findings()
            self.assertEqual(code, 0, (rule, 'removing it passes', output))

    def test_a_finding_names_file_and_line_and_never_repeats_a_value(self):
        self.write('a/b.sh', 'echo hi\n\n{}: "{}"\n'.format(KIT_SECRET_NAME, VALUE))
        code, found, output = self.findings()
        self.assertEqual(code, 1)
        self.assertEqual(found, ['error: a/b.sh:3: rule credential-assignment'])
        self.assertNotIn(VALUE, output)


class CredentialRule(Scratch):
    def flagged(self, text, relative='tools/x.txt'):
        self.write(relative, text)
        code, found, output = self.findings()
        (self.root / relative).unlink()
        return code == 1 and bool(found)

    def test_literal_values_are_flagged_in_assignment_shapes(self):
        for text in ('{}={}'.format(KIT_KEY_NAME, VALUE), 'export {}="{}"'.format(KIT_KEY_NAME, VALUE),
                     '"{}": "{}"'.format(KIT_SECRET_NAME, VALUE), "{} = '{}'".format(KIT_KEY_NAME.lower(), VALUE),
                     '{}: {}'.format(KIT_KEY_NAME, VALUE), 'kit' + 'ApiKey = "{}"'.format(VALUE),
                     "headers = {{'{}': '{}'}}".format(KIT_HEADER, VALUE), '{}: {}'.format(KIT_HEADER, VALUE),
                     'MAILCHIMP' + '_API_KEY=' + VALUE, 'SENDGRID' + '_API_KEY: "' + VALUE + '"'):
            self.assertTrue(self.flagged(text), text.replace(VALUE, '<value>'))

    def test_references_placeholders_empty_values_and_calls_are_not_literals(self):
        for text in ('{}=$(security find-generic-password -w)'.format(KIT_KEY_NAME), '{}=${{{}}}'.format(KIT_KEY_NAME, 'OTHER'),
                     '{}=<paste your key here>'.format(KIT_KEY_NAME), '{}='.format(KIT_KEY_NAME), '{}=""'.format(KIT_KEY_NAME),
                     '{} = read_key()'.format(KIT_KEY_NAME.lower()), 'the {} header carries the key'.format(KIT_HEADER),
                     '{}: $KEY'.format(KIT_HEADER), "{} = ''".format(KIT_KEY_NAME), '{}: {{{{ secrets.NAME }}}}'.format(KIT_KEY_NAME)):
            self.assertFalse(self.flagged(text), text)

    def test_a_name_that_merely_contains_the_words_is_not_a_credential_name(self):
        self.assertFalse(self.flagged('toolkit_api_keyring = "{}"'.format(VALUE)))

    def test_a_bearer_or_api_key_header_with_a_literal_is_flagged_only_in_the_waitlists_own_paths(self):
        line = "const headers = {{ Authorization: 'Bearer {}' }};".format(VALUE)
        self.assertTrue(self.flagged(line, 'tools/waitlist/probe.js'))
        self.assertTrue(self.flagged(line, 'gtm/03-site/page.js'))
        self.assertFalse(self.flagged(line, 'proxy/test/fixture.js'), 'existing Bearer fixtures lie outside the Waitlist paths')
        self.assertFalse(self.flagged("const headers = {{ Authorization: `Bearer ${{token}}` }};", 'tools/waitlist/probe.js'))
        self.assertFalse(self.flagged("Authorization: Bearer <token>", 'tools/waitlist/README.md'))
        self.assertTrue(self.flagged('curl -H "X-Some-Api-Key: {}" https://host'.format(VALUE), 'tools/waitlist/run.sh'))

    def test_a_credential_in_a_binary_file_is_still_found_by_the_credential_rules(self):
        self.write('blob.bin', b'\0\0' + '{}={}\n'.format(KIT_KEY_NAME, VALUE).encode())
        code, found, output = self.findings()
        self.assertEqual(rules_of(found), ['credential-assignment'])


class ExportRule(Scratch):
    def export_rules(self, name, data):
        self.write(name, data)
        code, found, output = self.findings()
        (self.root / name).unlink()
        self.assertNotIn(VALUE, output)
        return code, rules_of(found), found

    def test_one_row_csv_tsv_json_and_jsonl_exports_are_found(self):
        row = address('one')
        cases = {
            'x.csv': 'Name,Email Address\nA,{}\n'.format(row),
            'x.tsv': 'name\temail\nA\t{}\n'.format(row),
            'x.json': json.dumps([{'name': 'A', 'email': row}]),
            'x.jsonl': json.dumps({'name': 'A', 'email_address': row}) + '\n',
            'nested.json': json.dumps({'data': {'subscribers': [{'primaryEmail': row}]}}),
            'bom.csv': '﻿email\n{}\n'.format(row),
        }
        for name, content in cases.items():
            code, rules, found = self.export_rules(name, content.encode('utf-8'))
            self.assertEqual(code, 1, name)
            self.assertIn('export-file', rules, name)

    def test_a_windows_1252_export_with_an_accented_name_is_found_by_the_export_rule_alone(self):
        """The captain's carried finding: a file that is not UTF-8 is read by the export rule, whatever its encoding,
        while the address rule (text only) skips it, so only the export rule can fail it."""
        content = 'name,email\nJos\xe9,{}\n'.format(address('accent')).encode('cp1252')
        self.assertRaises(UnicodeDecodeError, content.decode, 'utf-8')
        code, rules, found = self.export_rules('export.csv', content)
        self.assertEqual(code, 1)
        self.assertEqual(rules, ['export-file'])
        self.assertEqual(len(found), 1)

    def test_a_utf16_export_is_found(self):
        for encoding in ('utf-16', 'utf-16-le', 'utf-16-be'):
            text = 'name,email\r\nA,{}\r\n'.format(address('wide'))
            data = text.encode(encoding)
            if encoding != 'utf-16':
                data = ('﻿' + text).encode(encoding)  # a byte-order mark, as a spreadsheet writes it
            code, rules, found = self.export_rules('wide.csv', data)
            self.assertEqual((code, rules), (1, ['export-file']), encoding)  # NUL bytes hide it from the address rule
        code, rules, found = self.export_rules('wide.json', ('﻿' + json.dumps([{'email': address('wide')}])).encode('utf-16'))
        self.assertEqual((code, rules), (1, ['export-file']))

    def test_a_latin1_json_export_and_a_damaged_json_export_are_found(self):
        content = ('{"name": "Ren\xe9e", "email": "%s"}' % address('latin')).encode('latin-1')
        code, rules, found = self.export_rules('latin.json', content)
        self.assertEqual((code, rules), (1, ['export-file']))
        damaged = ('[{"email": "%s"}, {"email": ' % address('damaged')).encode('utf-8')  # truncated
        code, rules, found = self.export_rules('damaged.json', damaged)
        self.assertIn('export-file', rules)

    def test_a_csv_the_reader_cannot_parse_is_still_found_and_never_crashes_the_guard(self):
        row = address('damaged')
        cases = {
            'nul.csv': 'name,email\nA\0B,{}\n'.format(row),  # Python 3.9 and 3.10 refuse a NUL
            'nul.tsv': 'name\temail\nA\0B\t{}\n'.format(row),
            'long.csv': 'email,note\n{},"{}"\n'.format(row, 'x ' * 100000),  # a field past the reader's default limit
            'unbalanced.csv': 'email,note\n{},"{}\n'.format(row, 'x ' * 100000),
        }
        for name, content in cases.items():
            code, rules, found = self.export_rules(name, content.encode('utf-8'))
            self.assertEqual(code, 1, name)
            self.assertIn('export-file', rules, name)
        clean = 'name,note\nA\0B,{}\n'.format('x ' * 100000)
        code, rules, found = self.export_rules('clean.csv', clean.encode('utf-8'))
        self.assertEqual((code, rules), (0, []))

    def test_an_unclosed_quote_before_the_email_column_hides_nothing(self):
        """The reader folds the rest of the file into the quoted cell and raises nothing; saved in Windows-1252 so the
        address rule skips it and only the export rule can fail it."""
        for name, delimiter in (('quote.csv', ','), ('quote.tsv', '\t')):
            content = delimiter.join(['name', 'email']) + '\n' + delimiter.join(['"Jos\xe9', address('one')]) + '\n' + \
                delimiter.join(['B', address('two')]) + '\n'
            code, rules, found = self.export_rules(name, content.encode('cp1252'))
            self.assertEqual((code, rules), (1, ['export-file']), name)

    def test_an_address_anywhere_beneath_an_email_field_is_found_parsed_or_damaged(self):
        cases = {
            'list.json': {'subscribers': [{'name': 'Jos\xe9', 'emails': [address('listed')]}]},
            'people.json': {'names': [{'displayName': 'Ren\xe9e'}], 'emailAddresses': [{'value': address('people')}]},
            'keyed.json': {'name': 'Jos\xe9', 'emails': {address('keyed'): True}},
        }
        for name, value in cases.items():
            code, rules, found = self.export_rules(name, json.dumps(value, ensure_ascii=False).encode('cp1252'))
            self.assertEqual((code, rules), (1, ['export-file']), name)
        damaged = '[{"name": "Jos\xe9", "emails": [\n  "%s"\n]}, {"emails": [' % address('damaged')  # truncated
        code, rules, found = self.export_rules('damaged.json', damaged.encode('cp1252'))
        self.assertEqual((code, rules), (1, ['export-file']))

    def test_an_export_over_the_size_cap_is_read_a_line_at_a_time(self):
        """Made here and never committed: filler rows past the 50 MB cap, then one row in Windows-1252 with an accented
        name and an unlisted address, so only the export rule, reading every row, can fail it."""
        rows = {
            'large.csv': (b'name,email\n', ('x y ' * 250 + ',\n').encode('ascii'), 'Jos\xe9,{}\n'),
            'large.jsonl': (b'', ('{"note": "' + 'x y ' * 250 + '"}\n').encode('ascii'), '{{"name": "Jos\xe9", "email": "{}"}}\n'),
        }
        for name, (head, filler, last) in rows.items():
            path = self.root / name
            with open(str(path), 'wb') as handle:
                handle.write(head)
                for _ in range(guard.MAX_BYTES // len(filler) + guard.CHUNK_BYTES // len(filler) + 1):
                    handle.write(filler)
                handle.write(last.format(address('large')).encode('cp1252'))
            self.assertGreater(path.stat().st_size, guard.MAX_BYTES + guard.CHUNK_BYTES)
            code, found, output = self.findings()
            path.unlink()
            self.assertEqual(code, 1, output)
            self.assertEqual(rules_of(found), ['export-file'], name)
            self.assertTrue(found[0].startswith('error: {}:'.format(name)), found)
            self.assertNotIn('read by no rule', output)

    @unittest.skipIf(os.geteuid() == 0, 'root reads a file whatever its mode')
    def test_an_export_that_cannot_be_read_fails_naming_it(self):
        other = self.write('locked.txt', 'notes\n')
        locked = self.write('locked.csv', 'name,email\n')
        for path in (other, locked):
            os.chmod(str(path), 0)
            self.addCleanup(os.chmod, str(path), 0o600)
        code, found, output = self.findings()
        self.assertEqual(code, 1, output)
        self.assertEqual(found, ['error: locked.csv:1: rule unreadable-export'])

    def test_a_file_with_an_email_column_but_no_unlisted_address_is_not_an_export(self):
        allowed = 'reptoday.app' + AT + 'gmail.com'
        example = 'person' + AT + 'example.com'
        for name, content in (('a.csv', 'email\n{}\n{}\n'.format(allowed, example)), ('b.csv', 'email,name\n,\n'),
                              ('c.json', json.dumps({'email': ''})), ('d.json', json.dumps({'note': address('x')[:8]})),
                              ('e.csv', 'name,note\nA,{}\n'.format(address('elsewhere')))):
            code, rules, found = self.export_rules(name, content.encode('utf-8'))
            if name == 'e.csv':
                self.assertIn('address', rules)  # an address in a column not named for email is still a stray address
                self.assertNotIn('export-file', rules)
            else:
                self.assertEqual((code, rules), (0, []), name)

    def test_the_export_rule_needs_no_row_count(self):
        code, rules, found = self.export_rules('single.csv', 'email\n{}\n'.format(address('only')).encode())
        self.assertEqual(code, 1)
        self.assertIn('export-file', rules)

    def test_a_binary_file_carrying_the_same_bytes_is_skipped_but_the_same_text_fails(self):
        payload = address('binary')
        self.write('image.png', b'\x89PNG\r\n\0\0' + payload.encode() + b'\0\xff')
        code, found, output = self.findings()
        self.assertEqual(code, 0, output)  # a NUL byte makes it binary: skipped by the address rule
        self.write('stray.txt', 'see ' + payload + '\n')
        code, found, output = self.findings()
        self.assertEqual(code, 1)
        self.assertEqual(rules_of(found), ['address'])
        self.assertTrue(any('stray.txt:1' in line for line in found))


class AddressRule(Scratch):
    def test_whole_addresses_only(self):
        self.write('notes.md', 'scoped @types/node and @babel/core and a@b and user@host without a dot\n')
        code, found, output = self.findings()
        self.assertEqual(code, 0, output)

    def test_the_allowlist_is_the_contact_address_and_example_domains(self):
        self.write('ok.md', 'write to {}, {}, {}, {}\n'.format(
            'reptoday.app' + AT + 'gmail.com', 'a' + AT + 'example.com', 'b' + AT + 'sub.example.org', 'c' + AT + 'example.net'))
        code, found, output = self.findings()
        self.assertEqual(code, 0, output)
        self.write('other.md', 'also {}\n'.format('reptoday.app' + AT + 'example-lookalike.com'))
        code, found, output = self.findings()
        self.assertEqual(code, 1)

    def test_the_two_userinfo_entries_apply_only_in_their_own_files(self):
        self.write('proxy/test/apple-fetch.test.js', "new URL('https://user:{}')\n".format(PASSWORD_DOMAIN))
        code, found, output = self.findings()
        self.assertEqual(code, 0, output)
        self.write('proxy/test/other.test.js', "new URL('https://user:{}')\n".format(PASSWORD_DOMAIN))
        code, found, output = self.findings()
        self.assertEqual(code, 1)
        self.assertEqual(found, ['error: proxy/test/other.test.js:1: rule address'])
        self.write('tools/waitlist/x.js', "new URL('https://user:{}')\n".format(PASSWORD_DOMAIN))
        code, found, output = self.findings()
        self.assertIn('error: tools/waitlist/x.js:1: rule address', found)  # no Waitlist path gains an exemption


class Audit(Scratch):
    def audit(self, *directories):
        done = subprocess.run(['bash', str(AUDIT)] + [str(item) for item in directories], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return done.returncode, (done.stdout + done.stderr).decode('utf-8', 'replace')

    def snapshot(self, directory):
        entries = {}
        for path in sorted(Path(directory).rglob('*')):
            if path.is_file():
                stat = path.stat()
                entries[str(path.relative_to(directory))] = (stat.st_size, stat.st_mtime_ns, path.read_bytes())
        return entries

    def seed(self):
        self.write('creds.sh', '{}={}\n'.format(KIT_KEY_NAME, VALUE))
        self.write('export.csv', 'email\n{}\n'.format(address('one')))
        self.write('notes.txt', 'a stray {} here\n'.format(address('stray')))

    def test_it_reports_a_credential_and_an_export_but_not_a_lone_address_outside_the_repotoday_checkout(self):
        self.seed()
        before = self.snapshot(self.root)
        code, output = self.audit(self.root)
        self.assertEqual(code, 1, output)
        self.assertIn('creds.sh:1: rule credential-assignment', output)
        self.assertIn('export.csv:2: rule export-file', output)
        self.assertNotIn('notes.txt', output)
        self.assertNotIn(VALUE, output)
        self.assertNotIn(AT, output)
        self.assertEqual(self.snapshot(self.root), before, 'the audit is read-only')

    def test_a_credential_kept_in_a_git_ignored_file_is_found_by_name_without_its_value(self):
        self.write('.env', '{}={}\n'.format(KIT_KEY_NAME, VALUE))
        self.write('ignored/more.env', '{}: {}\n'.format(KIT_SECRET_NAME, VALUE))
        code, found, output = self.findings()  # the CI guard reads only what git would publish
        self.assertEqual(code, 0, output)
        code, output = self.audit(self.root)
        self.assertEqual(code, 1)
        self.assertIn('.env:1: rule credential-assignment', output)
        self.assertIn('ignored/more.env:1: rule credential-assignment', output)
        self.assertNotIn(VALUE, output)

    def as_checkout(self):
        """Make the scratch directory a RepToday checkout in the audit's eyes: the script lives in its `tools/`."""
        (self.root / 'tools').mkdir(exist_ok=True)
        shutil.copy(str(GUARD), str(self.root / 'tools' / GUARD.name))
        return self.root / 'tools' / GUARD.name

    def audit_as_checkout(self):
        script = self.as_checkout()
        done = subprocess.run([sys.executable, str(script), '--audit', str(self.root)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return done.returncode, (done.stdout + done.stderr).decode('utf-8', 'replace')

    def test_on_the_checkout_it_lives_in_it_also_applies_the_address_rule_with_the_allowlist(self):
        self.write('notes.txt', 'a stray {} here, and the contact {}\n'.format(address('stray'), 'reptoday.app' + AT + 'gmail.com'))
        self.write('.gitignore', '.env\nignored/\nignored.txt\n')
        self.write('ignored.txt', 'an ignored stray {}\n'.format(address('ignored')))
        code, output = self.audit_as_checkout()
        self.assertEqual(code, 1, output)
        self.assertIn('notes.txt:1: rule address', output)
        self.assertNotIn('ignored.txt', output)  # the address rule reads the guard's own file list, not ignored files
        self.assertNotIn(AT, output)
        code, output = self.audit(self.root)  # the same directory seen from another checkout's copy: no address rule
        self.assertEqual(code, 0, output)

    def test_an_ignored_credential_in_the_checkout_is_found_by_the_audit_and_removed_again(self):
        marker = self.write('.env', '{}={}\n'.format(KIT_KEY_NAME, VALUE))
        self.as_checkout()
        code, found, output = self.findings(str(self.root))
        self.assertEqual(code, 0, 'the CI guard does not read ignored files')
        code, output = self.audit_as_checkout()
        self.assertEqual(code, 1)
        self.assertIn('.env:1: rule credential-assignment', output)
        self.assertNotIn(VALUE, output)
        marker.unlink()
        code, output = self.audit_as_checkout()
        self.assertEqual(code, 0, output)

    def test_dependency_folders_are_skipped_for_exports_but_not_for_credentials(self):
        self.write('node_modules/pkg/people.json', json.dumps({'email': address('maintainer')}))
        self.write('.venv/pyvenv.cfg', 'home = /usr\n')
        self.write('.venv/lib/export.csv', 'email\n{}\n'.format(address('venv')))
        self.write('.git/config', '[core]\n')
        code, output = self.audit(self.root)
        self.assertEqual(code, 0, output)
        self.write('node_modules/pkg/leak.sh', '{}={}\n'.format(KIT_KEY_NAME, VALUE))
        code, output = self.audit(self.root)
        self.assertEqual(code, 1)
        self.assertIn('node_modules/pkg/leak.sh:1: rule credential-assignment', output)

    def test_a_one_row_export_in_another_checkout_is_reported(self):
        other = Path(tempfile.mkdtemp(prefix='waitlist-guard-other-')).resolve()
        self.addCleanup(shutil.rmtree, str(other), True)
        (other / 'data').mkdir()
        (other / 'data' / 'list.csv').write_bytes('first,email\nJos\xe9,{}\n'.format(address('far')).encode('cp1252'))
        code, output = self.audit(other)
        self.assertEqual(code, 1)
        self.assertIn('data/list.csv:2: rule export-file', output)

    def test_a_damaged_csv_in_one_directory_does_not_stop_the_audit_of_the_rest(self):
        self.write('first.csv', 'name,email\nA\0B,{}\n'.format(address('first')))
        self.write('later.csv', 'email,note\n{},"{}"\n'.format(address('later'), 'x ' * 100000))
        other = Path(tempfile.mkdtemp(prefix='waitlist-guard-other-')).resolve()
        self.addCleanup(shutil.rmtree, str(other), True)
        (other / 'creds.sh').write_text('{}={}\n'.format(KIT_KEY_NAME, VALUE))
        code, output = self.audit(self.root, other)
        self.assertEqual(code, 1, output)
        self.assertNotIn('Traceback', output)
        self.assertIn('first.csv:2: rule export-file', output)
        self.assertIn('later.csv:2: rule export-file', output)
        self.assertIn('creds.sh:1: rule credential-assignment', output)

    def test_a_missing_directory_is_an_error_not_a_pass(self):
        code, output = self.audit(self.root / 'nope')
        self.assertNotEqual(code, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)

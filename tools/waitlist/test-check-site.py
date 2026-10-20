#!/usr/bin/env python3
"""Tests for the Waitlist static site check (US-WL03).

Each case copies the real site into a temporary directory, breaks one thing, and requires the
check to fail with the finding that names that thing and nothing else. Addresses are assembled
from parts at run time, so no address-shaped string is committed; a finding must never repeat one.

  python3 tools/waitlist/test-check-site.py
"""

import contextlib
import importlib.util
import io
import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SITE = HERE.parent.parent / 'gtm' / '03-site'
CONTRACT = HERE / 'contract.json'

spec = importlib.util.spec_from_file_location('check_site', HERE / 'check-site.py')
check_site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_site)


def rules(findings):
    return sorted(set(finding.split()[0] for finding in findings))


class SiteCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='check-site-'))
        self.site = self.tmp / 'site'
        shutil.copytree(SITE, self.site)
        self.contract = json.loads(CONTRACT.read_text(encoding='utf-8'))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def findings(self):
        return check_site.check(self.site, self.contract)

    def edit(self, name, function):
        path = self.site / name
        path.write_text(function(path.read_text(encoding='utf-8')), encoding='utf-8')

    def test_the_real_site_passes(self):
        self.assertEqual(self.findings(), [])

    def test_the_command_line_agrees(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check_site.main([]), 0)
            self.edit('index.html', lambda t: t.replace('Join the waitlist', 'Join the wait list', 1))
            self.assertEqual(check_site.main(['--site', str(self.site)]), 1)

    def test_a_mailbox_join_line_in_every_placement_fails_only_the_mailto_rule(self):
        link = '<noscript><p class="waitlist-fallback">Email <a href="mailto:{}">us</a> to join.</p></noscript>'.format(
            'reptoday.app' + '@' + 'gmail.com')
        for name in check_site.PAGES:
            self.edit(name, lambda t: t.replace(
                '<noscript><p class="waitlist-fallback">The sign-up form needs JavaScript.</p></noscript>', link))
        found = self.findings()
        self.assertEqual(rules(found), ['mailto-join'])
        self.assertEqual(len(found), 4)
        for finding in found:
            self.assertRegex(finding, r'index(-b)?\.html:\d+')

    def test_one_placement_that_differs_is_named(self):
        text = (self.site / 'index.html').read_text(encoding='utf-8')
        closing = text.index('id="waitlist-foot-head"')
        edited = text[:closing] + text[closing:].replace('<label for="wl-email-foot">Email</label>', '<label for="wl-email-foot">Your email</label>', 1)
        (self.site / 'index.html').write_text(edited, encoding='utf-8')
        found = self.findings()
        self.assertIn('placement-drift', rules(found))
        self.assertTrue(any('closing placement of index.html' in finding for finding in found))
        self.assertFalse(any('hero placement of index.html differs' in finding for finding in found))

    def test_an_altered_or_missing_approved_string_fails(self):
        self.edit('index-b.html', lambda t: t.replace("Add your email and we'll tell you the day it ships.", 'Add your email.'))
        self.assertIn('approved-string', rules(self.findings()))

    def test_the_promise_phrase_must_be_on_each_page(self):
        self.edit('index.html', lambda t: t.replace(self.contract['copy']['promise'], 'a launch email'))
        found = self.findings()
        self.assertEqual(rules(found), ['approved-string'])
        self.assertTrue(any(finding.split()[1] == 'index.html' for finding in found))

    def test_the_old_promise_wording_fails_in_any_case(self):
        self.edit('index.html', lambda t: t.replace('no spam,', 'no spam, One Message,', 1))
        found = self.findings()
        self.assertIn('one-message', rules(found))
        self.assertTrue(any(re.search(r'index\.html:\d+', finding) for finding in found))

    def test_a_fourth_field_or_a_second_hidden_input_fails(self):
        self.edit('index.html', lambda t: t.replace('<input type="hidden"', '<input type="text" name="heard"><input type="hidden"', 1))
        self.assertIn('form-fields', rules(self.findings()))

    def test_a_field_with_the_wrong_posted_name_fails(self):
        self.edit('index.html', lambda t: t.replace('name="fields[beta_opt_in]"', 'name="beta"', 1))
        self.assertIn('form-fields', rules(self.findings()))

    def test_a_download_follow_or_share_ask_fails(self):
        self.edit('index-b.html', lambda t: t.replace('<p class="lead">Rep Today is pre-launch.', '<p class="lead">Follow us. Rep Today is pre-launch.', 1))
        self.assertEqual(rules(self.findings()), ['ask-guard'])

    def test_a_stray_address_fails_without_repeating_it(self):
        address = 'someone' + '@' + 'example.test'
        (self.site / 'notes.md').write_text('line one\ncontact {}\n'.format(address), encoding='utf-8')
        found = self.findings()
        self.assertEqual(rules(found), ['stray-address'])
        self.assertIn('notes.md:2', found[0])
        self.assertNotIn(address, '\n'.join(found))
        self.assertNotIn('someone', '\n'.join(found))

    def test_the_published_contact_address_alone_is_allowed(self):
        (self.site / 'notes.md').write_text('mail ' + check_site.CONTACT + '\n', encoding='utf-8')
        self.assertEqual(self.findings(), [])

    def test_a_binary_file_with_address_shaped_bytes_is_skipped(self):
        address = 'someone' + '@' + 'example.test'
        (self.site / 'blob.bin').write_bytes(b'\x00\x01' + address.encode() + b'\x00')
        self.assertEqual(self.findings(), [])

    def test_the_script_must_post_the_contract_field_names(self):
        self.edit('waitlist.js', lambda t: t.replace("'fields[fit]'", "'fit'"))
        self.assertEqual(rules(self.findings()), ['script'])

    def test_a_page_without_the_script_fails(self):
        self.edit('index.html', lambda t: t.replace('<script src="/waitlist.js"></script>', ''))
        self.assertEqual(rules(self.findings()), ['script'])

    def test_a_third_placement_on_a_page_fails_the_count(self):
        text = (self.site / 'index.html').read_text(encoding='utf-8')
        closing = check_site.placements(text)[1]
        self.assertEqual(closing[0], 'closing')
        self.edit('index.html', lambda t: t.replace('</main>', closing[2] + '\n</main>', 1))
        self.assertIn('placement-count', rules(self.findings()))


if __name__ == '__main__':
    unittest.main()

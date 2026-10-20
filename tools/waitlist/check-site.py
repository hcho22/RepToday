#!/usr/bin/env python3
"""Static checks for the Waitlist on the landing pages (US-WL03).

The two landing pages (`index.html`, `index-b.html`) each carry the sign-up form twice, and
there is no build step, so this check is what keeps the four copies one form and keeps the
approved wording from drifting. Python 3 standard library only; no network.

  python3 tools/waitlist/check-site.py [--site gtm/03-site] [--contract tools/waitlist/contract.json]

It exits 0 when every rule holds and 1 otherwise, printing one finding per line as
`rule  file:line  what` with the rule's name first. A finding never repeats a value the
files hold (an address-shaped string in particular), only where it is.

Rules:
  placement-count   each landing page has exactly two sign-up placements (hero, closing)
  placement-drift   the four placements are one form, differing only in element ids
  approved-string   every approved string of the contract file is present in each placement,
                    and the promise phrase is on each page
  form-fields       a placement has exactly three fields (email, the Fit radios, the beta
                    box) plus the one hidden Source input, named as the contract says
  one-message       the words "one message" appear on neither page
  mailto-join       no `mailto:` link inside a placement (no second way to join)
  ask-guard         neither page asks the visitor to download, follow or share
  script            both pages load /waitlist.js once and it posts the contract's field names
  source-tags       waitlist.js lists exactly the contract's source_tags, in order
  source-links      _redirects rewrites each of the four Source links, and its trailing-slash
                    form, to the landing page ("/" - a rewrite to /index.html is answered
                    with a 308 that drops the tag from the URL)
  no-404-page       the site has no top-level 404.html: with one, Pages stops serving the
                    landing page for other letter cases (/TikTok), and the links break
  stray-address     no text file under the site holds an email-shaped string other than the
                    policy's published contact address
"""

import argparse
import html
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
PAGES = ('index.html', 'index-b.html')
CONTACT = 'reptoday.app' + '@' + 'gmail.com'  # the policy's published contact address, the only allowed one
ADDRESS = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
OPEN = re.compile(r'<div class="waitlist" role="group" aria-labelledby="(waitlist-(hero|foot)-head)">')
TAG = re.compile(r'<(/?)div\b')
ASK_WORDS = re.compile(r'\b(download|follow|share|retweet|repost)\b', re.IGNORECASE)


def line_of(text, index):
    return text.count('\n', 0, index) + 1


def placements(text):
    """The sign-up blocks of one page: (kind, start line, block text), found by div depth."""
    found = []
    for opening in OPEN.finditer(text):
        depth = 0
        end = None
        for tag in TAG.finditer(text, opening.start()):
            depth += -1 if tag.group(1) else 1
            if depth == 0:
                end = text.index('>', tag.start()) + 1
                break
        if end is None:
            continue
        found.append(('hero' if opening.group(2) == 'hero' else 'closing', line_of(text, opening.start()), text[opening.start():end]))
    return found


def normalized(block):
    """A placement with element ids made equal and indentation removed."""
    block = re.sub(r'-(hero|foot)\b', '-X', block)
    return [line.strip() for line in block.split('\n') if line.strip()]


def visible_text(page):
    page = re.sub(r'(?is)<(script|style)\b.*?</\1>', ' ', page)
    page = re.sub(r'(?s)<!--.*?-->', ' ', page)
    return html.unescape(re.sub(r'(?s)<[^>]*>', ' ', page))


def is_text(raw):
    if b'\x00' in raw:
        return False
    try:
        raw.decode('utf-8')
    except UnicodeDecodeError:
        return False
    return True


def check(site, contract):
    findings = []

    def find(rule, where, what):
        findings.append('{:<16} {}  {}'.format(rule, where, what))

    copy = contract['copy']
    pages = {}
    for name in PAGES:
        path = site / name
        if not path.is_file():
            find('placement-count', name, 'the page is missing')
            continue
        pages[name] = path.read_text(encoding='utf-8')

    found = {}
    for name, text in pages.items():
        blocks = placements(text)
        found[name] = blocks
        kinds = sorted(kind for kind, _, _ in blocks)
        if kinds != ['closing', 'hero']:
            find('placement-count', name, 'expected one hero and one closing placement, found {}'.format(len(blocks)))

    # The reference is the form most placements share, so one odd placement is the one named.
    seen = [(name, kind, line, normalized(block)) for name in PAGES for kind, line, block in found.get(name, [])]
    shared = {}
    for _, _, _, lines in seen:
        shared[tuple(lines)] = shared.get(tuple(lines), 0) + 1
    if seen:
        majority = max(seen, key=lambda item: shared[tuple(item[3])])
        for name, kind, line, lines in seen:
            if lines != majority[3]:
                differing = next((i for i, (a, b) in enumerate(zip(lines, majority[3])) if a != b), min(len(lines), len(majority[3])))
                find('placement-drift', '{}:{}'.format(name, line), 'the {} placement of {} differs from the {} placement of {} (first difference at its line {})'.format(
                    kind, name, majority[1], majority[0], differing + 1))

    for name, blocks in found.items():
        for kind, line, block in blocks:
            where = '{}:{}'.format(name, line)
            plain = html.unescape(block)
            wanted = [('copy.heading', copy['heading']), ('copy.sentence', copy['sentence']),
                      ('copy.fit_legend', copy['fit_legend']), ('copy.beta_label', copy['beta_label'])]
            for answer in contract['fit_answers']:
                wanted.append(('fit_answers.' + answer['tag'] + '.label', answer['label']))
                if 'value="{}"'.format(answer['tag']) not in block:
                    find('approved-string', where, 'the {} placement lacks the Fit tag {}'.format(kind, answer['tag']))
            for key, string in wanted:
                if string not in plain:
                    find('approved-string', where, 'the {} placement lacks {}'.format(kind, key))
            fields = contract['posted_fields']
            inputs = re.findall(r'<input\b[^>]*>', block)
            others = [tag for tag in inputs if not re.search(r'type="(email|radio|checkbox|hidden)"', tag)]
            if re.search(r'<(select|textarea)\b', block) or others:
                find('form-fields', where, 'the {} placement has a control beyond the three fields'.format(kind))
            counts = {t: sum(1 for tag in inputs if 'type="{}"'.format(t) in tag) for t in ('email', 'radio', 'checkbox', 'hidden')}
            if counts != {'email': 1, 'radio': len(contract['fit_answers']), 'checkbox': 1, 'hidden': 1}:
                find('form-fields', where, 'the {} placement does not hold exactly the email field, the Fit radios, the beta box and one hidden Source input'.format(kind))
            for key, tag_type in (('email', 'email'), ('fit', 'radio'), ('beta_opt_in', 'checkbox'), ('source', 'hidden')):
                for tag in inputs:
                    if 'type="{}"'.format(tag_type) in tag and 'name="{}"'.format(fields[key]) not in tag:
                        find('form-fields', where, 'the {} placement has a {} input not named {}'.format(kind, tag_type, 'posted_fields.' + key))
            if 'mailto:' in block.lower():
                find('mailto-join', where, 'a mailto: link inside the {} placement is a second way to join'.format(kind))
            if re.search(r'name="(?!{})[^"]*"[^>]*type="hidden"|type="hidden"[^>]*name="(?!{})[^"]*"'.format(re.escape(fields['source']), re.escape(fields['source'])), block):
                find('form-fields', where, 'the {} placement has a hidden input other than the Source'.format(kind))

    for name, text in pages.items():
        plain = html.unescape(text)
        if contract['copy']['promise'] not in plain:
            find('approved-string', name, 'the page lacks copy.promise')
        for match in re.finditer(r'one message', text, re.IGNORECASE):
            find('one-message', '{}:{}'.format(name, line_of(text, match.start())), 'the old promise wording is still on the page')
        for match in ASK_WORDS.finditer(visible_text(text)):
            find('ask-guard', name, 'the page asks the visitor for more than the sign-up (a download, follow or share word)')
            break
        tags = re.findall(r'<script\b[^>]*\bsrc="/waitlist\.js"', text)
        if len(tags) != 1:
            find('script', name, 'the page must load /waitlist.js exactly once')

    script_path = site / 'waitlist.js'
    if script_path.is_file():
        script = script_path.read_text(encoding='utf-8')
        for key, posted in contract['posted_fields'].items():
            if "'{}'".format(posted) not in script:
                find('script', 'waitlist.js', 'does not post posted_fields.' + key)
        listed = re.search(r'var SOURCE_TAGS = \[([^\]]*)\];', script)
        tags = re.findall(r"'([^']*)'", listed.group(1)) if listed else None
        if tags != contract['source_tags']:
            find('source-tags', 'waitlist.js', 'SOURCE_TAGS is not the contract file\'s source_tags')
    else:
        find('script', 'waitlist.js', 'the script is missing')

    redirects = site / '_redirects'
    rules = set()
    if redirects.is_file():
        for line in redirects.read_text(encoding='utf-8').split('\n'):
            parts = line.split('#')[0].split()
            if len(parts) == 3:
                rules.add(tuple(parts))
    for tag in contract['source_tags']:
        for suffix in ('', '/'):
            if ('/' + tag + suffix, '/', '200') not in rules:
                find('source-links', '_redirects', 'no rewrite of the {} link{} to the landing page'.format(tag, ' with a trailing slash' if suffix else ''))
    if (site / '404.html').exists():
        find('no-404-page', '404.html', 'a top-level 404 page turns the Source links in other letter cases into 404s')

    for path in sorted(p for p in site.rglob('*') if p.is_file()):
        raw = path.read_bytes()
        if not is_text(raw):
            continue
        text = raw.decode('utf-8')
        for match in ADDRESS.finditer(text):
            if match.group(0) != CONTACT:
                find('stray-address', '{}:{}'.format(path.relative_to(site), line_of(text, match.start())), 'an email-shaped string that is not the published contact address')
    return findings


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--site', default=str(REPO / 'gtm' / '03-site'))
    parser.add_argument('--contract', default=str(HERE / 'contract.json'))
    args = parser.parse_args(argv)
    try:
        contract = json.loads(Path(args.contract).read_text(encoding='utf-8'))
        findings = check(Path(args.site), contract)
    except (OSError, ValueError, KeyError):
        print('check-site: could not read the site or the contract file')
        return 64
    if findings:
        print('check-site: FAILED ({} finding{})'.format(len(findings), '' if len(findings) == 1 else 's'))
        for finding in findings:
            print('  ' + finding)
        return 1
    print('check-site: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())

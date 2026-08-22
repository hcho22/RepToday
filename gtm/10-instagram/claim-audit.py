#!/usr/bin/env python3
"""Claim-hygiene and experiment-integrity audit for gtm/10-instagram/.

Run it from anywhere:  python3 gtm/10-instagram/claim-audit.py

Two jobs.

1. Claim hygiene. Scan every authored file in this folder for the strings and
   characters that are hard blockers for a Rep Today asset: em dashes, the
   one-word name, the retired listing suffix, any speed figure (the real-device
   p95 substantiation in ../08-redteam/pre-publication-checklist.md is still
   outstanding), and any movement count (the figure in the GTM package is stale
   and the correct framing is an open captain decision).

2. Experiment integrity. gtm/05-social-pmf/ is a pre-registered experiment with
   frozen hooks. Restating a hook verbatim on a carousel pre-exposes one leg of
   an A/B pair and biases the day-N versus day-N+7 comparison the pair exists to
   resolve. Rather than hard-coding the hook list (which would silently drift if
   the frozen files were ever re-read), this pulls every quoted sentence out of
   angles.md and ab-pairs.md and asserts that none of them appears in our copy.
   That is a deliberate superset of the A/B leg hooks: it also covers the angle
   bank's hooks and the mined review quotes, so the check is stricter than the
   rule requires.

   This script only reads gtm/05-social-pmf/. It never writes there.

   The rule it guards is verbatim reuse, which is the whole rule: the pairs run
   on TikTok and YouTube Shorts and Instagram is not a test platform, so what a
   carousel must not do is put a frozen leg's sentence in front of a reader.
   README.md records why the scope stops there.
"""

import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
PMF = os.path.normpath(os.path.join(HERE, "..", "05-social-pmf"))

# Characters that must not appear in any Rep Today copy.
# Written as escapes on purpose: spelling them literally would put an em dash in
# this file, and this file is one of the files the character check scans.
BANNED_CHARS = {
    "\u2014": "an em dash",
    "\u2013": "an en dash",
}

# (regex, why it is a blocker, flags)
# The two name patterns are deliberately case-SENSITIVE. Matching them
# case-insensitively would flag the correct "Rep Today" as a violation of
# itself, which is exactly the false positive this comment exists to prevent.
BANNED_PATTERNS = [
    (r"RepToday", "the name is 'Rep Today', two words (brand-guidelines.md section 2)", 0),
    (r"REP Today", "the name is 'Rep Today', two words (brand-guidelines.md section 2)", 0),
    (r"Rest Tomorrow", "the retired listing suffix is dead everywhere (section 2)", re.I),
    (r"\b\d+\s*(?:ms|milliseconds?|seconds?)\b",
     "no speed figure may publish until the real-device p95 record exists", re.I),
    (r"under 100", "no speed figure may publish until the real-device p95 record exists", re.I),
    (r"\b\d+\s*(?:movements?|exercises?)\b",
     "the movement count in the GTM package is stale; say 'bodyweight', count nothing", re.I),
    (r"\bday \d+ of\b", "no 'day N of' framing (the product refuses that mechanic)", re.I),
]

TEXT_EXTS = {".html", ".md", ".css", ".sh", ".py"}

# Two scopes, because they answer two different questions.
#
# Publishable copy is the slide HTML and the captions: everything that reaches a
# reader on Instagram. That is what the banned strings and the frozen-hook rule
# are about, and it gets the full check.
#
# Everything else here is documentation and tooling (README.md, this file,
# fit-check.py, render.sh, carousel.css). Those have to quote the banned strings
# in order to forbid them, so string-matching them would flag the very lines
# that record the rule. They still get the character check, because the no-em-dash
# rule genuinely does cover the README too.
def is_publishable_copy(path):
    name = os.path.basename(path)
    parent = os.path.basename(os.path.dirname(path))
    if not parent.startswith("carousel-"):
        return False
    return name == "caption.md" or (name.startswith("slide-") and name.endswith(".html"))


def normalize(text):
    """Lowercase, strip accents, collapse whitespace, and unify quote glyphs."""
    text = unicodedata.normalize("NFKD", text)
    text = (text.replace("‘", "'").replace("’", "'")
                .replace("“", '"').replace("”", '"'))
    return re.sub(r"\s+", " ", text).strip().lower()


def blank_tags(text):
    """Replace every HTML tag with spaces, preserving length and line breaks.

    A reader sees a headline, not its markup, so the string and frozen-hook
    checks have to see it the same way: "71<br>movements" and a leg hook broken
    across two lines are violations that matching the raw file misses entirely,
    and headlines here carry explicit <br> exactly where a break would land.
    Blanking rather than deleting keeps every byte offset intact, so the line
    numbers reported below still point at the real line.
    """
    return re.sub(r"<[^>]*>", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)


def authored_files():
    """Every authored text file in this folder, and nothing a tool left behind.

    The walk prunes build detritus rather than descending it, for two reasons.

    The count printed at the end is quoted in README.md as this audit's current
    result, so it has to be a property of what is committed rather than of
    whatever happens to be sitting in the tree. widow-check.py and render.sh both
    write scratch copies here, and a run killed before its cleanup leaves them
    behind - which is why .gitignore carries both patterns.

    The second reason is the one that matters more. A leftover `.widow-check-*.html`
    is a copy of a slide, but its name does not start with `slide-`, so
    `is_publishable_copy` reads it as documentation and gives it the character
    check without the banned-string or frozen-hook checks. That is slide copy
    getting a weaker check than a slide, silently, on a green run. Skipping the
    file entirely is correct: the original it was copied from is audited in full.
    """
    out = []
    for root, dirs, names in os.walk(HERE):
        # Prune in place so os.walk does not descend them at all. Dot-directories
        # covers `.render-scratch-*` and anything else a tool hides here.
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in sorted(names):
            if name.startswith("."):
                continue
            if os.path.splitext(name)[1] not in TEXT_EXTS:
                continue
            out.append(os.path.join(root, name))
    return sorted(out)


def _quoted(text):
    return re.findall(r'"([^"]{25,})"', text)


def frozen_hooks():
    """Every quoted sentence in the pre-registered PMF files, 25 chars or longer.

    Parsed line by line and, inside a line, cell by cell across markdown table
    pipes. Scanning whole files at once looked simpler and was wrong: a single
    unpaired quote anywhere in angles.md shifts every later quote pairing, which
    silently swallowed two real A/B leg hooks and produced one nonsense entry
    spanning a table boundary. Confining the scan to one cell keeps a stray
    quote from cascading past it.
    """
    hooks = set()
    leg_hooks = set()
    problems = []

    for name in ("angles.md", "ab-pairs.md"):
        path = os.path.join(PMF, name)
        if not os.path.exists(path):
            problems.append("could not read %s, so the frozen-hook check cannot "
                            "run at all" % os.path.relpath(path, HERE))
            continue
        for line in open(path, encoding="utf-8"):
            for cell in line.split("|"):
                for quoted in _quoted(cell):
                    hooks.add(normalize(quoted))
            # ab-pairs.md's leg hooks are the strings the no-verbatim-restatement
            # rule is actually about, so track them separately to self-check below.
            if re.match(r"\s*-\s*Leg [AB] hook:", line):
                for quoted in _quoted(line):
                    leg_hooks.add(normalize(quoted))

    # Self-check. ab-pairs.md pre-registers 6 pairs, so 12 leg hooks. AB-3's two
    # legs describe their hook in prose around a quoted review, so they may
    # contribute more than one string each; fewer than 12 means the parser has
    # regressed and the experiment-integrity half of this audit is not actually
    # running.
    #
    # These are failures, not warnings, and that distinction is the whole point:
    # a guard that cannot run must not report PASS. If the PMF files move or a
    # reformat turns their straight quotes typographic, `hooks` comes back empty,
    # the hook loop matches nothing, and every printed line below would otherwise
    # read as a clean run of a check that never happened.
    if len(leg_hooks) < 12:
        problems.append("parsed only %d A/B leg hook(s) from ab-pairs.md, expected "
                        "at least 12, so the no-restatement check is incomplete"
                        % len(leg_hooks))

    return hooks, problems


def main():
    files = authored_files()
    copy_files = [p for p in files if is_publishable_copy(p)]
    hooks, problems = frozen_hooks()

    # The same rule the frozen-hook self-checks enforce, applied to this audit's
    # own scope: a check with nothing to check must not print PASS. `files` is
    # empty if the folder is moved, and `copy_files` is empty if the carousel
    # directories are ever renamed off the `carousel-` prefix `is_publishable_copy`
    # keys on - and this is the publication blocker, so a green run over zero
    # slides is the one result it may never give.
    if not files:
        problems.append("found no authored files in gtm/10-instagram/ at all")
    elif not copy_files:
        problems.append("found no publishable copy (no carousel-*/slide-*.html or "
                        "carousel-*/caption.md), so the banned-string and "
                        "frozen-hook checks scanned nothing")

    failures = ["%s (this audit cannot pass while it cannot check)" % p
                for p in problems]

    for path in files:
        raw = open(path, encoding="utf-8").read()
        rel = os.path.relpath(path, HERE)

        # Character check: everything, documentation included, on the raw bytes.
        # Every occurrence, not just the first: reporting one hit per character
        # per file makes an editor fix it, re-run, and discover the next, once
        # for as many as exist, and understates the count printed at the end.
        for char, label in BANNED_CHARS.items():
            for m in re.finditer(re.escape(char), raw):
                line = raw[:m.start()].count("\n") + 1
                failures.append("%s:%d contains %s" % (rel, line, label))

        # String and frozen-hook checks: publishable copy only, and against the
        # text a reader sees rather than the markup that produces it.
        if not is_publishable_copy(path):
            continue

        visible = blank_tags(raw)
        seen = set()
        for pattern, why, flags in BANNED_PATTERNS:
            # Both scans, because they catch different things: the visible text
            # catches a match split across a tag, and the raw file still covers
            # attribute values (a title or an aria-label is authored copy too).
            for source in (visible, raw):
                for m in re.finditer(pattern, source, flags):
                    line = source[:m.start()].count("\n") + 1
                    hit = "%s:%d %r - %s" % (rel, line, m.group(0).strip(), why)
                    if hit not in seen:
                        seen.add(hit)
                        failures.append(hit)

        # Same two scans, and for the same reason: blanking the tags is what
        # catches a hook broken across a <br>, and the raw file is what keeps a
        # hook parked in a <title>, an alt, or an aria-label from slipping past.
        for source in (visible, raw):
            flat = normalize(source)
            for hook in hooks:
                if hook in flat:
                    hit = "%s restates a frozen PMF hook verbatim: %r" % (rel, hook)
                    if hit not in seen:
                        seen.add(hit)
                        failures.append(hit)

    print("Audited %d authored file(s) in gtm/10-instagram/, of which %d are "
          "publishable copy (slides and captions)." % (len(files), len(copy_files)))
    print("Checked against %d quoted sentence(s) frozen in gtm/05-social-pmf/." % len(hooks))
    print()
    if failures:
        for f in failures:
            print("FAIL  %s" % f)
        print("\n%d finding(s)." % len(failures))
        return 1
    print("PASS  0 em dashes, 0 en dashes, 0 'RepToday', 0 'Rest Tomorrow',")
    print("      0 speed figures, 0 movement counts, 0 'day N of' framings,")
    print("      0 verbatim reuses of a pre-registered PMF hook.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

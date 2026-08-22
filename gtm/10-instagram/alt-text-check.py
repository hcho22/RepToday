#!/usr/bin/env python3
"""Alt-text sync check: every word on a slide is in that slide's alt text.

Each caption.md quotes its slides verbatim in an "## Alt text" block, one
paragraph per slide, and that block is what a screen-reader user gets instead of
the PNG. Nothing structural keeps the two in step: the copy lives in the slide
HTML, the restatement lives in a different file, and a copy edit that touches one
and not the other produces a slide whose picture and description disagree. That
is the same class of drift a review round already caught in README.md, where a
summary still carried an absolute the slides had been corrected off.

claim-verification.md used to assert this property from a throwaway script that
was run once and not committed. This is that assertion, made standing: it is the
one of this folder's guards that checks a *correspondence* rather than a format.

What it checks: every copy-bearing element on every slide appears verbatim inside
its own slide's alt-text paragraph. Not the reverse - alt text also describes
layout, colour and the Ready Mark, which have no on-slide string.

Comparison is verbatim up to two normalizations, both of which are about the
transport rather than the words:

  * Whitespace collapses, and a tag becomes a space. A headline carries explicit
    <br> breaks that alt text writes as one flowing sentence.
  * Quote glyphs are unified. Alt text nests slide copy inside a double-quoted
    string, so a slide that quotes something itself has to switch to single
    quotes there (carousel 1 slide 6, `What "no deciding" means here, exactly.`).

Nothing else is relaxed: a changed, dropped, or reordered word fails.

Usage:  python3 gtm/10-instagram/alt-text-check.py [carousel-dir ...]
"""

import glob
import os
import re
import sys
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))

# Every class in carousel.css that carries authored copy, plus the stacked
# statements, which are <li> and carry no class of their own. Layout classes
# (.slide, .zone, .rail, .steps, .step, .cond, .wordmark) hold no text directly
# and are reached through their children, and .lede is an inline emphasis span
# inside an <li> rather than an element of its own.
COPY_CLASSES = {
    "display", "h1", "h2", "h3", "body", "overline",
    "step-label", "step-name", "txt", "swipe", "name", "status", "legal",
}

# Void and SVG-shape elements never close, so they must not be treated as
# nesting; <br> is the one that carries meaning here, as a word boundary.
VOID = {"br", "img", "hr", "input", "meta", "link", "source",
        "path", "circle", "rect", "polygon", "polyline", "line", "ellipse", "use"}


class SlideCopy(HTMLParser):
    """Collect the text of every copy-bearing element, outermost first."""

    def __init__(self):
        super().__init__()
        self.depth = 0
        self.buf = []
        self.texts = []

    def handle_starttag(self, tag, attrs):
        if tag in VOID:
            if self.depth:
                self.buf.append(" ")
            return
        if self.depth:
            self.depth += 1
            return
        classes = set((dict(attrs).get("class") or "").split())
        if (classes & COPY_CLASSES) or tag == "li":
            self.depth = 1
            self.buf = []

    def handle_endtag(self, tag):
        if tag in VOID or not self.depth:
            return
        self.depth -= 1
        if self.depth == 0:
            text = collapse("".join(self.buf))
            if text:
                self.texts.append(text)

    def handle_data(self, data):
        if self.depth:
            self.buf.append(data)


def collapse(text):
    return re.sub(r"\s+", " ", text).strip()


def comparable(text):
    """Collapse whitespace and flatten every quote glyph to one sentinel."""
    return re.sub(r"[\"'‘’“”]", " ", collapse(text))


def alt_paragraphs(caption_path):
    """{slide number: alt text} from a caption's '## Alt text' block."""
    text = open(caption_path, encoding="utf-8").read()
    parts = text.split("## Alt text", 1)
    if len(parts) < 2:
        return None
    return {int(n): collapse(body)
            for n, body in re.findall(r"\*\*Slide (\d+)\.\*\*(.*)", parts[1])}


def check_carousel(name):
    """Return (elements checked, failures) for one carousel directory."""
    directory = os.path.join(HERE, name)
    failures = []

    if not os.path.isdir(directory):
        return 0, ["no such carousel directory: %s" % name]

    caption = os.path.join(directory, "caption.md")
    if not os.path.isfile(caption):
        return 0, ["%s has no caption.md, so its slides have no alt text" % name]

    alts = alt_paragraphs(caption)
    if alts is None:
        return 0, ["%s/caption.md has no '## Alt text' block" % name]

    slides = sorted(glob.glob(os.path.join(directory, "slide-*.html")))
    if not slides:
        return 0, ["%s holds no slide-*.html, so nothing was compared" % name]

    checked = 0
    described = set()
    for slide in slides:
        rel = os.path.relpath(slide, HERE)
        number = int(re.search(r"slide-(\d+)", os.path.basename(slide)).group(1))
        if number not in alts:
            failures.append("%s has no alt text: caption.md describes no slide %d"
                            % (rel, number))
            continue
        described.add(number)

        parser = SlideCopy()
        parser.feed(open(slide, encoding="utf-8").read())
        if not parser.texts:
            failures.append("%s yielded no copy at all, so its alt text was "
                            "compared against nothing" % rel)
            continue

        alt = comparable(alts[number])
        for text in parser.texts:
            checked += 1
            if comparable(text) not in alt:
                failures.append("%s reads %r, which its alt text does not quote"
                                % (rel, text))

    for number in sorted(set(alts) - described):
        failures.append("%s/caption.md describes a slide %d that does not exist"
                        % (name, number))

    return checked, failures


def main(argv):
    names = argv or sorted(os.path.basename(d.rstrip("/"))
                           for d in glob.glob(os.path.join(HERE, "carousel-*/")))

    checked, failures = 0, []
    for name in names:
        count, problems = check_carousel(name)
        checked += count
        failures.extend(problems)

    # The same floor the other three guards carry: a check with nothing to check
    # must never print PASS. An empty argument list, a renamed folder, or a set
    # of slides that yielded no copy all land here rather than in a green run.
    if not names:
        failures.append("found no carousel directories at all, so nothing was checked")
    elif checked == 0:
        failures.append("compared no slide copy at all, so nothing was checked")

    print("Compared %d slide element(s) against the alt text in %d caption(s)."
          % (checked, len(names)))
    print()
    if failures:
        for failure in failures:
            print("FAIL  %s" % failure)
        print("\n%d finding(s)." % len(failures))
        return 1
    print("PASS  every slide's copy appears verbatim in its own alt text.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

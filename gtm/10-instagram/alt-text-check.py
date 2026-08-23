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

Which elements those are is read out of carousel.css rather than kept as a list
here: a rule that sets a font size, by either `font-size` or the `font`
shorthand, is a text style, so its subject can hold copy. A hand-kept list would
exclude the next text style someone adds, and an unchecked class must not read
as a passing one - so a slide class the stylesheet does not style at all fails
the run rather than being skipped.

That derivation is not trusted either, because every allow-list fails the same
way: by omission. So the guard also asserts its own coverage - every run of
non-whitespace text on the slide canvas has to sit inside an element the
derivation collected, and text that does not fails the run. An unclassed
`<p>Some copy</p>`, a class the stylesheet styles by a route this parser does
not model, or a text style added in a form the regex misses are then all one
failure with one message, rather than three holes each needing its own patch.
Only document metadata is outside the canvas and exempt.

Comparison is verbatim up to two normalizations, both of which are about the
transport rather than the words:

  * Whitespace collapses, and a tag becomes a space. A headline may carry an
    explicit <br>, and alt text writes that headline as one flowing sentence.
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

STYLESHEET = os.path.join(HERE, "carousel.css")

# Void and SVG-shape elements never close, so they must not be treated as
# nesting; <br> is the one that carries meaning here, as a word boundary.
VOID = {"br", "img", "hr", "input", "meta", "link", "source",
        "path", "circle", "rect", "polygon", "polyline", "line", "ellipse", "use"}

# Text here is document metadata rather than anything the canvas renders, so it
# is exempt from the coverage assertion. Nothing else is: an element on the
# slide holding text no text style claims is a finding.
OFF_CANVAS = {"head", "title", "style", "script"}

# Classes a slide may carry that carousel.css does not name, because they are
# not styling hooks: none today. Anything else unknown to the stylesheet is a
# failure rather than a silent skip, since an unchecked class must not read as
# a passing one.
UNSTYLED_OK = set()


def stylesheet_classes(path):
    """(copy-bearing selectors, every class carousel.css styles) from the CSS.

    The copy set is bound to the stylesheet rather than kept by hand: a rule
    that sets a font size is a text style, so its subject is an element that
    can hold authored copy. That is what keeps a newly added text style from
    being excluded from this guard by an allow-list nobody remembered to
    extend - the same defect the widow-check selector was corrected for.

    Both spellings of "sets a font size" count. `font-size` is the one every
    rule in carousel.css uses today, and the `font` shorthand sets a size too,
    so matching only the longhand would reintroduce exactly the omission this
    derivation exists to remove. The other font longhands (-family, -weight,
    and the rest) set no size and do not qualify.

    Returns (classes, tags, known). `tags` carries the one text style whose
    subject is an element rather than a class (`.stack > li`).
    """
    css = re.sub(r"/\*.*?\*/", "", open(path, encoding="utf-8").read(), flags=re.S)

    classes, tags, known = set(), set(), set()
    for selectors, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
        text_style = re.search(r"(^|[\s;])font(-size)?\s*:", body)
        for selector in selectors.split(","):
            compounds = [c for c in re.split(r"[\s>+~]+", selector.strip()) if c]
            if not compounds:
                continue
            for compound in compounds:
                known.update(re.findall(r"\.([A-Za-z0-9_-]+)", compound))
            if not text_style:
                continue
            # A rule styles its rightmost compound; that is the element the
            # copy actually sits in.
            subject = re.findall(r"\.([A-Za-z0-9_-]+)", compounds[-1])
            if subject:
                classes.update(subject)
            else:
                tags.add(compounds[-1].lower())
    return classes, tags, known


try:
    COPY_CLASSES, COPY_TAGS, KNOWN_CLASSES = stylesheet_classes(STYLESHEET)
    STYLESHEET_ERROR = None
except OSError as error:
    COPY_CLASSES, COPY_TAGS, KNOWN_CLASSES = set(), set(), set()
    STYLESHEET_ERROR = str(error)


class SlideCopy(HTMLParser):
    """Collect the text of every copy-bearing element, outermost first.

    `uncovered` is the coverage assertion: canvas text that landed in no
    collected element at all. Collection is by class or tag, so text in an
    element carrying neither - the bare `<p>` an allow-list can never name -
    would otherwise be dropped silently and leave the run green.
    """

    def __init__(self):
        super().__init__()
        self.depth = 0
        self.off_canvas = 0
        self.buf = []
        self.texts = []
        self.uncovered = []
        self.unknown = set()

    def handle_starttag(self, tag, attrs):
        if tag in OFF_CANVAS:
            self.off_canvas += 1
            return
        if self.off_canvas:
            return
        classes = set((dict(attrs).get("class") or "").split())
        self.unknown |= classes - KNOWN_CLASSES - UNSTYLED_OK
        if tag in VOID:
            if self.depth:
                self.buf.append(" ")
            return
        if self.depth:
            self.depth += 1
            return
        if (classes & COPY_CLASSES) or tag in COPY_TAGS:
            self.depth = 1
            self.buf = []

    def handle_endtag(self, tag):
        if tag in OFF_CANVAS:
            self.off_canvas = max(0, self.off_canvas - 1)
            return
        if self.off_canvas or tag in VOID or not self.depth:
            return
        self.depth -= 1
        if self.depth == 0:
            text = collapse("".join(self.buf))
            if text:
                self.texts.append(text)

    def handle_data(self, data):
        if self.off_canvas:
            return
        if self.depth:
            self.buf.append(data)
        elif data.strip():
            self.uncovered.append(collapse(data))


def collapse(text):
    return re.sub(r"\s+", " ", text).strip()


def comparable(text):
    """Collapse whitespace and flatten every quote glyph to one sentinel."""
    return re.sub(r"[\"'‘’“”]", " ", collapse(text))


def alt_paragraphs(caption_path):
    """({slide number: alt text}, problems) from a caption's '## Alt text' block.

    A paragraph runs to the next blank line, not to the end of the physical
    line: this repo writes long markdown one sentence per line, so an alt
    paragraph split that way must still be read whole rather than compared
    against its first sentence alone.
    """
    text = open(caption_path, encoding="utf-8").read()
    parts = text.split("## Alt text", 1)
    if len(parts) < 2:
        return None, []

    alts, problems = {}, []
    for number, body in re.findall(r"\*\*Slide (\d+)\.\*\*(.*?)(?=\n[ \t]*\n|\Z)",
                                   parts[1], re.S):
        number = int(number)
        if number in alts:
            problems.append("%s describes slide %d more than once, so only one "
                            "of those paragraphs would be checked"
                            % (os.path.relpath(caption_path, HERE), number))
            continue
        alts[number] = collapse(body)
    return alts, problems


def check_carousel(name):
    """Return (elements checked, failures) for one carousel directory."""
    directory = os.path.join(HERE, name)
    failures = []

    if not os.path.isdir(directory):
        return 0, ["no such carousel directory: %s" % name]

    caption = os.path.join(directory, "caption.md")
    if not os.path.isfile(caption):
        return 0, ["%s has no caption.md, so its slides have no alt text" % name]

    alts, problems = alt_paragraphs(caption)
    if alts is None:
        return 0, ["%s/caption.md has no '## Alt text' block" % name]
    failures.extend(problems)

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
        for unknown in sorted(parser.unknown):
            failures.append("%s carries class %r, which carousel.css does not "
                            "style, so this guard cannot tell whether it holds "
                            "copy" % (rel, unknown))
        for stray in parser.uncovered:
            failures.append("%s renders %r outside every element carousel.css "
                            "gives a text style, so it was compared against "
                            "nothing" % (rel, stray))
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

    # The copy set is derived, so a stylesheet that will not parse leaves it
    # empty and every slide trivially clean. That is a failure, not a pass, in
    # the same spirit as claim-audit.py's integrity self-checks.
    if STYLESHEET_ERROR:
        failures.append("could not read carousel.css (%s), so no copy class was "
                        "derived" % STYLESHEET_ERROR)
    elif not COPY_CLASSES:
        failures.append("carousel.css yielded no text styles, so every slide "
                        "would compare as empty")
    else:
        for name in names:
            count, problems = check_carousel(name)
            checked += count
            failures.extend(problems)

    # A check with nothing to check must never print PASS. An empty argument
    # list, a renamed folder, or a set of slides that yielded no copy all land
    # here rather than in a green run.
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

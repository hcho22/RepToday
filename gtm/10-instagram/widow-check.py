#!/usr/bin/env python3
"""Headline widow check for the rendered carousel slides.

A single short word stranded on its own line is a defect at these type sizes
("A missed day moves the / number. It cannot empty / it."). Headlines here carry
explicit <br> breaks rather than relying on the browser, because the canvas is a
fixed size and explicit breaks are predictable. Explicit breaks are also easy to
invalidate: any copy edit can re-widow a line silently. This is the guard.

It measures real line boxes rather than guessing. Each slide is copied beside
its original (so the relative stylesheet link still resolves), a measuring
script is injected, and headless Chrome runs it and dumps the DOM. The script
walks every word of every large-type element with a Range, groups words by the
top of their client rect, and reports the resulting lines.

Anything set at 40px or larger is checked: headlines, the stacked statements,
and the hotel-room-test conditions. Body copy at 34px is ordinary prose and is
left alone.

Usage:  python3 gtm/10-instagram/widow-check.py [carousel-dir ...]
"""

import base64
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# A line that is one word this short or shorter, and is not the only line, is a
# widow. "it" and "plan" are defects; a lone "workout." reads as deliberate.
MAX_WIDOW_WORD = 6

SELECTOR = ".display, .h1, .h2, .h3, .stack > li, .cond .txt"

MEASURE_JS = """
<script>
(function () {
  function lines(el) {
    var words = [], walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT), n;
    while ((n = walker.nextNode())) {
      var t = n.nodeValue, i = 0;
      while (i < t.length) {
        while (i < t.length && /\\s/.test(t[i])) i++;
        if (i >= t.length) break;
        var j = i;
        while (j < t.length && !/\\s/.test(t[j])) j++;
        var r = document.createRange();
        r.setStart(n, i); r.setEnd(n, j);
        var box = r.getBoundingClientRect();
        words.push({ w: t.slice(i, j), top: Math.round(box.top) });
        i = j;
      }
    }
    // Group by rect top within a tolerance rather than by exact equality. A
    // bold <span> sitting inside a regular-weight line reports a slightly
    // different top for its own inline box, which exact matching read as a
    // second line and reported as a widow that is not on screen. Every line
    // height here is 56px or more, so 16px cannot merge two real lines.
    var out = [];
    words.forEach(function (x) {
      var last = out[out.length - 1];
      if (last && Math.abs(last.top - x.top) <= 16) last.ws.push(x.w);
      else out.push({ top: x.top, ws: [x.w] });
    });
    return out.map(function (l) { return l.ws.join(" "); });
  }

  var result = [];
  document.querySelectorAll(%s).forEach(function (el) {
    result.push({ cls: el.className || el.tagName.toLowerCase(), lines: lines(el) });
  });
  var d = document.createElement("div");
  d.id = "__widow_result";
  d.textContent = btoa(unescape(encodeURIComponent(JSON.stringify(result))));
  document.body.appendChild(d);
})();
</script>
"""


def find_chrome():
    env = os.environ.get("CHROME")
    if env and os.path.isfile(env):
        return env
    for c in ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
              "/Applications/Chromium.app/Contents/MacOS/Chromium",
              shutil.which("google-chrome"), shutil.which("chromium")]:
        if c and os.path.isfile(c):
            return c
    raise SystemExit("Could not find Chrome or Chromium. Set CHROME=/path/to/chrome.")


def measure(chrome, slide_path):
    # The measuring copy has to live beside the original so the relative
    # stylesheet link still resolves, which puts it inside a tracked directory.
    # Its name is therefore unique per run rather than fixed: a fixed name is
    # clobbered by a concurrent run and, if the process is killed outright, is
    # left behind in the tree as a stray render artifact someone can commit.
    html = open(slide_path, encoding="utf-8").read()
    js = MEASURE_JS % json.dumps(SELECTOR)
    fd, tmp = tempfile.mkstemp(prefix=".widow-check-", suffix=".html",
                               dir=os.path.dirname(slide_path))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(html.replace("</body>", js + "\n</body>"))
    try:
        out = subprocess.run(
            [chrome, "--headless", "--disable-gpu", "--hide-scrollbars",
             "--force-device-scale-factor=1", "--window-size=1080,1350",
             "--virtual-time-budget=2000", "--dump-dom", "file://" + os.path.abspath(tmp)],
            capture_output=True, text=True, timeout=90).stdout
    finally:
        os.remove(tmp)

    m = re.search(r'<div id="__widow_result">([A-Za-z0-9+/=]*)</div>', out)
    if not m:
        raise RuntimeError("measuring script did not run for %s" % slide_path)
    return json.loads(base64.b64decode(m.group(1)).decode("utf-8"))


def widows(entry):
    """Lines in this element that are a lone short word."""
    found = []
    if len(entry["lines"]) < 2:
        return found
    for line in entry["lines"]:
        words = line.split()
        if len(words) == 1 and len(re.sub(r"[^\w]", "", words[0])) <= MAX_WIDOW_WORD:
            found.append(line)
    return found


def main(argv):
    chrome = find_chrome()
    dirs = argv or sorted(os.path.basename(d.rstrip("/"))
                          for d in glob.glob(os.path.join(HERE, "carousel-*/")))
    slides, failures = 0, []
    for name in dirs:
        for slide in sorted(glob.glob(os.path.join(HERE, name, "slide-*.html"))):
            slides += 1
            for entry in measure(chrome, slide):
                for w in widows(entry):
                    failures.append("%s  <%s> strands %r on its own line\n      lines: %s"
                                    % (os.path.relpath(slide, HERE), entry["cls"], w,
                                       " / ".join(entry["lines"])))

    print("Measured line boxes on %d slide(s)." % slides)
    print()
    if failures:
        for f in failures:
            print("FAIL  %s" % f)
        print("\n%d widow(s)." % len(failures))
        return 1
    print("PASS  no headline or large-type line is a lone word of %d characters "
          "or fewer." % MAX_WIDOW_WORD)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

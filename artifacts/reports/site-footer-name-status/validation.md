# Site footer name status

The footer of `index.html`, `index-b.html` and `privacy.html` now reads the wording approved on 2026-10-19:
"Pre-launch. A USPTO search was completed and the App Store name was reserved on 2026-08-07. This does not state that a trademark was registered or legally cleared."
It never claims a registered or cleared trademark.

Each page was served locally (`python3 -m http.server` on 127.0.0.1) and measured with `chrome-devtools-axi` at 390x844 (mobile, 3x) and 1440x900, before and after.
The local hosts are outside `waitlist.js`'s event hosts, no request left 127.0.0.1, and the Waitlist form was never submitted.

| Page | Width | Before: lines / last line | After: lines / last line | Horizontal scroll |
| --- | --- | --- | --- | --- |
| index, index-b | 390 | 4 / "reserved." | 5 / "legally cleared." | none (scrollWidth 390) |
| privacy | 390 | 4 / "reserved." | 5 / "legally cleared." | none |
| index, index-b | 1440 | 3 / full line | 3 / full line | none (scrollWidth 1440) |
| privacy | 1440 | 2 / full line | 2 / full line | none |

At 390 px the new sentence first ended on the lone word "cleared.", so the last two words are joined with `&nbsp;`, the pattern the landing pages already use against orphans.
The rendered text is unchanged.
Screenshots: `before-<page>-<width>.png` and `after-<page>-<width>.png` in this folder.

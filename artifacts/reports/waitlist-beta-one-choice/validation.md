# Waitlist beta choice: one per page (2026-10-21)

The captain's decision of 2026-10-21 ("optin - 1"): ticking either sign-up box counts whichever Join is pressed.
`gtm/03-site/waitlist.js` keeps both boxes on each page but sets every box to match whenever one is ticked or unticked, and a successful sign-up leaves every box unticked.
The pages' HTML, the field name `fields[beta_opt_in]`, its `true`/`false` values and everything Kit, Convex and the view receive are unchanged.
Nothing changes on reptoday.app until the next captain-approved publish.

## Automated

| Check | Result |
| --- | --- |
| `node tools/waitlist/test-source.cjs` | 29 passed, including two new tests: the cross-form tick, untick and no-tick cases, and the reset after a sign-up and on a back/forward restore. Both new tests fail against the previous `waitlist.js`. |
| `python3 tools/waitlist/check-site.py` | ok |
| `python3 tools/waitlist/test-check-site.py` | OK |
| `python3 tools/waitlist/test-check-view.py` | OK (5 skipped: no gr0wthlab checkout set) |
| `python3 tools/waitlist/test-waitlist.py` | OK |
| `python3 tools/check-no-waitlist-credentials.py` and its test | 0 findings, OK |

## Browser

`npx wrangler@3 pages dev gtm/03-site --port 8788` with `tools/waitlist/stub-receiver.py` on 8799, driven by `chrome-devtools-axi`.
A page served from localhost posts its sign-up to the stub, never to Kit, and its events went to the stub through the `waitlist.testEndpoints` override, never to Convex.
Each case loaded the page fresh, clicked the boxes' labels, filled the named form and pressed its Join; the stub's recorded body is shown without the address.

| Page | Boxes clicked | Join | Boxes before Join | Posted `beta_opt_in` | Boxes after success |
| --- | --- | --- | --- | --- | --- |
| `/`, `/index-b`, `/tiktok` | top | bottom | both ticked | `true` | both unticked |
| `/`, `/index-b`, `/tiktok` | bottom | top | both ticked | `true` | both unticked |
| `/`, `/index-b`, `/tiktok` | top, then top again | bottom | both unticked | `false` | both unticked |
| `/`, `/index-b`, `/tiktok` | top, then bottom | top | both unticked | `false` | both unticked |
| `/`, `/index-b`, `/tiktok` | none | bottom | both unticked | `false` | both unticked |
| `/`, `/index-b`, `/tiktok` | none | top | both unticked | `false` | both unticked |

Every case posted the same four fields in the same order as before (email, `fields[fit]` `exercises-regularly`, `fields[beta_opt_in]`, `fields[source]` `unknown` on `/` and `/index-b`, `tiktok` on `/tiktok`), showed the success wording, and sent one `landing_page_view` per page load and one `waitlist_signup` per accepted sign-up, each carrying only `referrer_source` (`none`, or `tiktok` on `/tiktok`).
One more case on `/index-b` used the tool's own pointer clicks instead of DOM clicks: the bottom box ticked, the top form's Join posted `true`, and both boxes were unticked afterwards.

Screenshots (one box clicked, both boxes shown ticked, no horizontal scroll: `scrollWidth` equal to the viewport width):

- `/` at 1440 px and 390 px, top box clicked: `a-1440-hero-ticked-{hero,closing}.png`, `a-390-hero-ticked-{hero,closing}.png`.
- `/index-b` at 1440 px and 390 px, bottom box clicked: `b-1440-closing-ticked-{hero,closing}.png`, `b-390-closing-ticked-{hero,closing}.png`.

## Found, not changed

The other fields are still per form: each placement has its own Email field and its own Fit answer, so an answer typed or picked in one form is not sent by the other form's Join.
Unlike the beta box, a missing email or Fit answer blocks that Join with a visible message, so nothing is silently lost.

## Known deviation after publish

reptoday.app's Cloudflare zone gives `/waitlist.js` a 4-hour browser cache (`gtm/03-site/DEPLOY.md`), so a returning browser may keep the old, per-form behavior for up to 4 hours after the publish.

# US-WL02 validation: the sign-up form

Date: 2026-10-20.
Spec: `.claude/agent/tasks/prd-waitlist_261019.md`, US-WL02.
Site change only, nothing deployed: no Kit setting, DNS, hosting or Convex deployment was touched.
No email address appears in this record; the browser checks used addresses created for the test, and the stub receiver prints counts only.

## What landed

- `gtm/03-site/waitlist.js`: the one script behind every placement.
  It posts the email, the Fit answer, the beta choice and the visit's Source to Kit's public sign-up endpoint as a form-encoded body (`email_address`, `fields[fit]`, `fields[beta_opt_in]`, `fields[source]`), reads Kit's JSON answer, and shows the in-progress, success, validation-error and submission-error states.
  The destination is set in one place (`CONFIG.signupUrl`, the live Kit form's public endpoint).
  A page served from `localhost`, `127.0.0.1` or `[::1]` never posts there: it posts to `tools/waitlist/stub-receiver.py` on `127.0.0.1:8799`, which is how no test run can reach the production list.
- The four placements (hero and closing band on `index.html` and `index-b.html`) now carry one `<form>` definition, identical except for element ids, in place of Kit's embed script.
  The `<noscript>` mailbox join is gone; a visitor without script sees "The sign-up form needs JavaScript." (Appendix B).
- Kit's reCAPTCHA check (spike decision D4): a `quarantined` answer shows Kit's guard page in an iframe inside the card.
  The script accepts it only from Kit's origin and `/forms/guards/` path, listens for Kit's `ckjs:guard:*` messages from that origin and that form's own frame only, and shows the success wording when Kit reports it confirmed.
- `tools/waitlist/stub-receiver.py`: the local stand-in (success, quarantined, validation errors, failure and slow modes) with a stand-in guard page.
- `tools/waitlist/contract.json`: the three provisional custom-field names are settled by the spike (`fields[fit]`, `fields[beta_opt_in]`, `fields[source]`; Kit's keys are `fit`, `beta_opt_in`, `source`), and the producer-owned `entry` field is recorded separately because the form never posts it.
- Styles: an `--error` token (`#A32A2A`) and the form styles, using the existing Paper tokens.
- `_headers`: the script revalidates like the HTML.
- The hero's "Rep Today is pre-launch and not yet on the App Store." now sits above the card, so the card itself carries exactly the approved sentence (Appendix B, OQ9).

## Validation Test (local site `wrangler pages dev gtm/03-site --port 8788`, stub receiver on 8799)

True 390 px came from `chrome-devtools-axi emulate --viewport "390x844x3,mobile,touch"` and then `open` (`innerWidth` 390, `scrollWidth` 390, card 342 px wide); desktop from `emulate --viewport "1440x900x1"` (`innerWidth` 1440, no horizontal scroll, hero card 538 px).

1. The hero form reads: heading "Join the waitlist", sentence "Add your email and we'll tell you the day it ships.", label "Email", legend "Which sounds most like you?", three radios labelled exactly as approved, the checkbox "Invite me to the beta before launch", and the button.
   `hero-390.png`, `index-hero-1440.png`.
2. `input[type=radio]:checked` and `input[type=checkbox]:checked`: 0 and 0 on first load.
3. After a reload, and after `/privacy` then back: 0 and 0 both times (the form also clears its choices on load and on `pageshow`).
4. Submitting with everything empty showed the email message and the Fit message and focused the email field; a malformed address showed the email message with the typed value kept; a valid address with no Fit answer showed only the Fit message, focused the first radio, and kept the email.
   Messages are tied to their controls (`aria-describedby`), and the status line is a polite live region.
   `hero-390-errors.png`, `index-b-hero-1440-errors.png`.
5. A valid address, "I work out regularly", the box left unticked: the stub received `email_address`, `fields[fit]=exercises-regularly`, `fields[beta_opt_in]=false`, `fields[source]=unknown` and nothing else; the card showed "Check your email to confirm your address." and the fields collapsed, with the card still 342 px wide.
   `hero-390-success.png`.
6. The stub in `fail` mode: the card showed "That did not go through. Try again in a moment.", the entered email, the chosen answer and the ticked box were all still there, the button was enabled again; a retry in `slow` mode showed the disabled "Joining..." button with `aria-busy` true and a 342 px card, then success.
   The stub in `quarantined` mode: the guard iframe appeared in the card; activating the stand-in's button reported `ckjs:guard:confirmed` and the card showed the success wording with the iframe removed.
   This step is evidenced by this transcript only; no screenshot of it is kept.
7. The closing band and `/index-b` behaved the same (`index-closing-1440.png`, `index-b-closing-1440.png`), including on the Night band where the card stays Paper.

Other checks: tab order email, three radios, checkbox, button, all native with `tabindex` 0, so the form completes by keyboard alone; control heights 44 px (choices) and 48 px (email, button).
Contrast ratios computed from the tokens: ink on Paper 15.05, slate on Paper 6.24, error on Paper 6.73, white on moss 6.31, white on slate (disabled button) 6.66, the slate input border 6.24 against Paper, the moss focus ring 5.90.

## Against the live Kit endpoint

Not run, by design: no test in this story posts to Kit.
The spike (`artifacts/reports/US-WL06/spike.md`) exercised Kit's real endpoint against the test account only, from a throwaway page, and showed a form-encoded browser post is readable and stores the custom fields.
The live form's own custom fields (`fit`, `beta_opt_in`, `source`, `entry`) must exist on the production Kit account before go-live; that is a slice 4 step for the captain.

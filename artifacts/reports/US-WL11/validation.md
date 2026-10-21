# US-WL11 validation: the privacy policy's Waitlist section

Run on 2026-10-20 (UTC) against the local site (`npx wrangler pages dev gtm/03-site --port 8788`), in headless Chrome through `chrome-devtools-axi`.
Nothing was published: the live `reptoday.app/privacy` is unchanged until the captain-approved production deploy (US-WL12), which also sets "Last updated" to the publication date.
No address appears below other than the policy's published contact address.

## The wording

The captain approved the draft as written plus one item under "What is collected" ("privacy - approve with b", 2026-10-20).
It is Appendix C adjusted to his answers: a spam complaint is treated as a removal request, and "deleted" stays because the founder deletes each scrubbed record in Kit's web app (US-WL10).
Structure follows OQ10 (a): section 10 is "This website", the new section 11 is "The waitlist" (`id="waitlist"`, linked from the table of contents), and the old sections 11-14 are now 12-15.
Every sentence of the approved text was found word for word in the rendered page text (27 sentences checked by script).

## Validation Test

| Step | Result |
| --- | --- |
| 1. 390 px (`emulate --viewport "390x844x3,mobile,touch"`, viewport 390, page width 390): follow the contents link for the Waitlist section, read it against the five points | The link sets `#waitlist` and brings the section to the top of the viewport. The five points appear in order: what is collected, why, how long it is kept, how to be removed, who sees your address. Screenshots: `privacy-waitlist-390.png`, `privacy-removal-390.png`, `privacy-website-390.png`. |
| 2. The page contains "30 days", "7 days" and the contact address, and no longer contains the old Kit sentence of section 10 | `true`, `true`, `true`; the sentence "collected and stored by our email provider (Kit)" is absent. |
| 3. Follow every "section N" reference | The page refers to sections 3, 6, 7, 9 and 11; each resolves to the heading it names (3 Private iCloud sync, 6 AI Coach, 7 Anonymous usage measurement, 9 Deleting your data, 11 The waitlist). No reference points at a renumbered section. |
| 4. 1440 px (`emulate --viewport "1440x900x1"`) | Viewport 1440, page width 1440, `#waitlist` at the top; `privacy-waitlist-1440.png`. |

No horizontal scroll at either width.

## Every sentence, traced to what makes it true

| Sentence | Mechanism |
| --- | --- |
| Section 10: one anonymous count per landing-page load and per sign-up, naming only the link, no address and no identifier | US-WL05 (`POST /webEvent`, `landing_page_view` and `waitlist_signup` with `referrer_source` only) |
| Section 10: the link's name kept in the tab's session storage, no cookie of the site's own | US-WL04 (`gtm/03-site/waitlist.js`, the tag alone in `sessionStorage`) |
| Section 10: the hosting provider's page-view analytics | V3 (Cloudflare injects its Web Analytics beacon at the edge) |
| What is collected: address, Fit answer, beta choice, link, sign-up date | US-WL02 (the three fields and the hidden Source), US-WL06 (Kit's `created_at` as the sign-up date) |
| What is collected: Kit's approximate location for a confirmed sign-up, deleted with the sign-up | US-WL06 finding (Kit's geolocation block); US-WL10 (the founder's delete in Kit's web app) |
| Why: to confirm your address | OQ5 double opt-in (Kit's confirmation email, US-WL06 spike unknown 4) |
| Why: to count without your address | US-WL07 (the anonymous view holds no address) |
| Kept until 30 days after the launch email | US-WL10 (`record-launch-email`, the retention sweep's erasure at the launch-email date plus 25 and the founder's delete in Kit by plus 30, checked by `kit-deletes`) |
| The unsubscribe link in any waitlist email | US-WL06 spike unknown 5 (the confirmation email carries a working one); every waitlist email is sent from Kit (US-WL09 runbook) |
| A message to the contact address | US-WL10 (`remove`, the mailbox cadence in the runbook) |
| Marking a waitlist email as spam is a removal request | US-WL10 (the daily sweep erases a `complained` sign-up) |
| Deleted within 7 days | US-WL10 (the daily scrub, then the founder's delete in Kit by 7 days after the request - Kit's unsubscribe time, else the last run that saw the sign-up subscribed - checked by `kit-deletes`) |
| Only the founder and Kit see the address; never sold or shared | OQ1 Option A (the form posts straight to Kit), US-WL08 (no credential or export in any checkout), US-WL09 (`tag` and `show` on the founder's Mac) |
| Kit's reCAPTCHA check | D4 (the form hosts Kit's guard iframe) |

## Legal flags

The draft banner and header comment are unchanged.
Section 11 carries its own "Flagged for legal review" note, and section 13's flag now says that section 11 states a retention period and a removal process for the waitlist and that neither has been reviewed by counsel.

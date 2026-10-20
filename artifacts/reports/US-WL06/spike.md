# US-WL06 spike: does Kit carry the Waitlist (OQ1 Option A)?

Run on 2026-10-20 (UTC) against a separate free Kit **test** account and its test form (form id 10070589).
The production Kit account, its list and its live form were never contacted.
The API key was read from the macOS Keychain at run time (service `com.reptoday.waitlist.kit-spike`, account `api-key`) and is not in this note, a file or a log.
Test sign-ups used four plus-aliases of the founder's own mailbox, called mailbox 1 to 4 below.
No address appears in this note.
Times are UTC unless marked.

## Verdict in one paragraph

Option A works for what the PRD needs, with four findings the captain decided on (section "Decisions the captain made") and the facts under "Other facts" that the build must handle.
A first-party form can post the Fit answer, beta choice and Source to Kit as stored custom fields, and a browser can read the result.
Kit double opt-in sends a confirmation email whose unsubscribe link works, but only once the account's sending address is verified.
Kit's API has no way to delete a subscriber, so "deleted within 7 days" cannot be met by an API call alone.
A public post can set the field that would hold the entry identifier.

## Unknowns the PRD lists, answered

| # | Unknown | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Does a first-party sign-up carry Fit, beta choice and Source as stored fields? | **Yes.** A `POST` to `https://app.kit.com/forms/<form id>/subscriptions` with `email_address` and `fields[fit]`, `fields[beta_opt_in]`, `fields[source]` stores them on the subscriber. The custom-field keys Kit derived from the labels I created are exactly `fit`, `beta_opt_in`, `source` and `entry`. Values are stored as strings (`"true"`, `"false"`). A field the post omits stays `null`, so the form must always post `beta_opt_in` as `true` or `false`. | Subscriber record read back through the API after each post. |
| 2 | Can a browser read the result? | **Yes.** The endpoint answers `OPTIONS` with `access-control-allow-origin: *` and allows the `content-type` header. A `fetch` from a page on another origin, with `Accept: application/json` and a `FormData` body, gets a readable JSON body. `status` is `success` (plus `consent` and `redirect_url`), or `quarantined` (plus `url`), or an error list. | Chrome at `http://127.0.0.1`, read through `chrome-devtools-axi`. |
| 3 | Is a post ever challenged? | **Yes, sometimes.** `quarantined` carries a `url` for an interactive reCAPTCHA ("One more step ... I'm not a robot") that Kit's own script shows in an iframe and that reports back with `postMessage` (`ckjs:guard:confirmed`, origin `https://app.kit.com`). Quarantine followed the second and later posts from one address in a few minutes (scripted and from headless Chrome). The first post and the one fresh post a day later both returned `success`. A quarantined post is not stored until the check is passed. I did not try to pass or bypass it. The first-party form must host that iframe, or such visitors silently lose their sign-up. | Responses and a screenshot. |
| 4 | Does Kit send a confirmation message? | **Yes, once the sending address is verified.** The first post (04:01Z) was never emailed: the account's only sending address read `pending` and `is_verified: false` before it and reads `confirmed`, `is_verified: true` now (the likely cause, not provable from the API). A fresh post at 13:15:59Z (06:15:59 Pacific) was emailed at 06:16 Pacific from the account's sending address, subject "Important: confirm your subscription". Kit's own default text, not Rep Today's. | The captain's report; subscriber still `inactive` until confirmed. |
| 5 | Does that message carry a working unsubscribe link? | **Yes.** It is at the bottom. It opens a page that asks "Are you sure you want to unsubscribe ...?"; confirming shows "You have been successfully unsubscribed" and Kit set the subscriber to `cancelled` with `canceled_at` 13:28:18Z. | The captain's report; the API. |
| 6 | Can the store permanently delete a subscriber and its fields? | **No, not through the API.** `DELETE /v4/subscribers/{id}` and every plausible variant answer `404`. Kit's published API index lists unsubscribe ("the subscriber record, history, and tags are retained") and no subscriber delete. What does work: unsubscribe, then `PUT /v4/subscribers/{id}` replacing the email with a non-address placeholder and nulling every custom field. The record is then an empty shell (id, creation time, state `cancelled`) with no address and no answers. A later API create for the old address made a brand-new subscriber (new id, new `created_at`). Whether the Kit dashboard has a true erase is not known to me; the captain would have to look. | API calls on a test subscriber. |
| 7 | Does a resubmission of a listed address overwrite the stored fields? | **Yes.** A second post for the same address changed Fit, beta choice and Source (Source `tiktok` to `unknown`) within seconds, while `created_at` stayed the same. A field the second post omits (`entry`) kept its value. So the OQ11 window is real: a visit by plain `reptoday.app` can replace the first Source before the producer's next run. | Subscriber record before and after. |
| 8 | Is there a creation time a resubmission does not change, and is it the submission time, unchanged by confirmation? | **Yes.** `created_at` equals the post time (04:01:01Z for a post at 04:01:01Z; 13:15:59Z for a post at 13:15:59Z) and a resubmission did not move it. The form membership time `added_at` is one second later. The captain confirmed the fresh sign-up (a click on the confirm link) and then unsubscribed it at 13:28:18Z, about 12 minutes after the post, and its `created_at` still reads 13:15:59Z. So confirmation does not change it, and `signed_up_on` can be the UTC date of `created_at`. | API, and the captain's answer that he confirmed before unsubscribing. |
| 9 | Can a public post set or overwrite the identifier field? | **It can set it.** A post carrying `fields[entry]=<any text>` on a new sign-up stored that text as the subscriber's `entry`. Overwriting an existing value was not shown, because the attempt was quarantined (I did not repeat it). The field name is public in any page that posts to it, so a hostile post can plant a value, including a copy of another sign-up's identifier or one derived from an address. | Subscriber record. |

## Other facts the build has to handle

- **Confirmation state.** An unconfirmed sign-up is state `inactive`. An unsubscribed one is `cancelled`. They are different, so the producer can tell them apart. The list endpoint returns only `active` by default and takes `status=all`.
- **The list endpoint lags.** A listing trailed a fresh write by seconds to a couple of minutes, while `GET /v4/subscribers/{id}` was current. The producer should tolerate a list that is a few minutes old, and the daily cadence already does.
- **Custom field values.** The list and the single record both return `fields` with the four keys.
- **Account timezone.** The API stamps `created_at` in UTC (`Z`) although the account timezone is Eastern, so `signed_up_on` can be the UTC date of `created_at` directly.
- **What the form never sends.** The first-party form must not post `entry` (the producer owns it).

## Decisions the captain made on these findings (2026-10-20)

The captain accepted every recommendation, in his words "Kit decisions - recommendations".

1. **D1, planted identifiers: a local ledger.** The producer keeps a local, owner-only ledger on the Mac beside the view (Kit subscriber id to entry identifier) and trusts only the ledger. It resets Kit's `entry` field to the ledger's value and replaces any value it did not assign. Losing the ledger would mean new identifiers, which is accepted. Built in slice 3 (US-WL06 storage glue and US-WL07).
2. **D2, no API delete: scrub.** The removal and retention sweeps unsubscribe, overwrite the email with a non-address placeholder and blank every custom field within a day of the request or the retention date, and the privacy wording keeps "deleted". Built in slice 3 (US-WL10); the wording is slice 4's (US-WL11).
3. **D3, resubmission overwrites Source: accepted.** A same-day resubmission can replace the first Source before the producer's next daily run.
4. **D4, quarantine: the form hosts Kit's guard.** The form shows Kit's reCAPTCHA iframe when Kit answers `quarantined`, accepting `postMessage` only from `https://app.kit.com`. The privacy section (slice 4) names reCAPTCHA via Kit.

## Cleanup

The four test subscribers remain in the test account only: mailbox 1 unconfirmed, mailbox 4 cancelled, and two scrubbed shells.
The throwaway page and server used for the browser checks lived in the session scratchpad and are not committed.
The four custom fields stay in the test account.

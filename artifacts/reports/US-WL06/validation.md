# US-WL06 validation: sign-up storage and entry identifiers (slice 3)

Run on 2026-10-20 (UTC).
The spike half of this story is `spike.md` beside this file.
This record covers the rest: storage glue, entry identifiers and the ledger.
Everything ran against the Kit **test** account (never the production account, its form 9786563, its list or its subscribers) or against synthetic stores in temporary directories.
The API key was read from the Keychain at run time (service `com.reptoday.waitlist.kit-spike`, account `api-key`) and appears in no file or output.
No address appears below: counts, states and Kit subscriber ids only.

## What was run

| Check | Command | Result |
| --- | --- | --- |
| Offline suite (synthetic store, the real Kit client over HTTP to `tools/waitlist/fake_kit.py`, the command as a subprocess) | `python3 tools/waitlist/test-waitlist.py` | 65 tests pass on Python 3.7 and 3.9 (CI runs 3.9 and 3.12); review rounds later the same day added cases, and `docs/test-coverage.md` lists the current ones |
| Kit test account | a scratch driver (not committed) that created 7 subscribers through Kit's API, then ran `tools/waitlist/waitlist.py` as a subprocess with `WAITLIST_KIT_KEYCHAIN_SERVICE=com.reptoday.waitlist.kit-spike` and `--restrict-to-ids <the ids it created>` | every assertion below held |

`--restrict-to-ids` makes a command see only the named Kit subscriber ids, so the four subscribers left in the test account by the spike and anything else there were never read or written.
Subscribers were created through Kit's API, not through the form: the form-to-Kit path was proven in the spike and in US-WL02, a form post would email the founder's mailbox for each test, and Kit's quarantine challenge follows repeated posts from one address.

## The Validation Test, step by step

1. **Three sign-ups, one repeated.**
   The two plain sign-ups (a `tiktok` one with Fit `lost-the-routine` and the box ticked, and one with another Fit and Source) were created on Kit.
   The repeat is Kit's own behavior (spike, unknown 7: a second post for the same address overwrites the answers of the same subscriber and keeps `created_at`), so no second record exists; `ProducerSafety.test_first_seen_source_is_kept_when_a_resubmission_overwrites_it` and `Identifiers.test_a_repeat_signup_never_creates_a_second_entry` show the producer keeping one entry, the latest Fit and beta choice, and the Source first seen.
2. **Identifier assignment, then inspect.**
   The first `produce` on the 7 test subscribers: `assigned 7, entry resets 1, unconfirmed left out 1`, view accepted by `check-view.py` with 6 entries.
   Every stored sign-up carries its ledger identifier in Kit's `entry` field (read back by id).
   One of them had a hostile `entry` planted through the API (an address-shaped value); the producer reset Kit's field to the ledger's value and the view never held it.
   A second `produce` kept every identifier (the ledger was byte-for-byte the same).
3. **Remove the first sign-up, re-add the same address.**
   Removal is `remove --entry`, shown on Kit (below) and, for the re-add, on the synthetic store (`Identifiers.test_the_same_address_re_added_after_a_removal_gets_a_different_identifier`): Kit gives a re-added address a brand-new subscriber (spike, unknown 6), the producer mints it a different identifier, and the new Source is the new link's.
4. **Identifier unit tests.** 5,000 generated identifiers all match `[A-Za-z0-9_-]{1,64}`, are unique, are 16 characters (about 95 bits), and pass `check-view.py`'s address check and its percent, base64 and hex decodings; two stores holding the same address assign unrelated identifiers (`Identifiers.*`).
5. **A Fit and Source outside the allowed sets.**
   This is the Option A normalization, shown on the view: the Kit test sign-up whose stored Fit was `bogus`, Source `Facebook` and beta `yes` was written as Fit `null`, Source `unknown`, beta `false`.

## Acceptance criteria, with where each is shown

| Criterion | Evidence |
| --- | --- |
| Spike | `spike.md` (slice 2). |
| A stored sign-up holds exactly the listed fields | **Open.** See the finding below. |
| Entry identifier: secure random, pattern, unique, stored, never derived, never changes | `wl_common.new_entry` (`secrets`), `Identifiers.*`, the ledger (D1) and the second `produce` above. |
| Collision negligible | 16 characters from 62 is about 95 bits, above the 80-bit floor. |
| Assignment step, no overlap, bounded | `waitlist.py assign` and `produce`; one `flock` lock for every command, a 600 second limit, a 20 second timeout on every call; `SevenSignups.test_two_runs_started_at_once_give_the_new_signup_one_identifier` and the hung-run test (US-WL07's record). |
| Out-of-set values never reach the view as sent | The Kit run above, `SevenSignups.test_view_projects_exactly_five_fields_in_stable_order`. |
| `signed_up_on` is the UTC date and does not change | It is the UTC date of Kit's `created_at` (`DateLogic.test_signed_up_on_is_the_utc_date`); a resubmission does not move it (spike). |
| Second submission follows OQ11 | Above, step 1. D3 (a resubmission before the next daily run can replace the first Source) is unchanged. |
| Existing sign-ups (OQ6) | A subscriber with no stored answers (a sign-up made through the old form) projects as Source `unknown`, Fit `null`, beta `false` with its original creation date: the synthetic case in `SevenSignups`, and the real Kit case recorded in the "Additional Kit checks" section below. |
| Confirmation (OQ5) | An `inactive` Kit sign-up is left out (`unconfirmed left out 1`); `SevenSignups.test_unconfirmed_signup_appears_once_confirmed_with_its_submission_date` shows it appearing once active with its submission date. The confirming click cannot be made through the API, so that transition is shown on the synthetic store only (the spike observed it once on Kit). |
| No log or output holds an address | Every command's output is asserted free of any `@` in the suite and in the Kit driver; `SendTimeLookup.test_no_address_reaches_the_state_directory_or_any_log`. |
| Stored field names in one place | `tools/waitlist/contract.json`; `wl_store.FIELD_KEYS` reads them. |
| Unit tests | `Identifiers.*`. |

## Additional Kit checks (a second test-account run)

- **OQ6, a sign-up made through the old form.** A subscriber created with no stored answers (the shape of a sign-up made before this build) read back with all four custom fields empty and projected as Source `unknown`, Fit `null`, beta `false`, with its `signed_up_on` equal to the UTC date of its creation time.
- **A batch of 25.** 26 subscribers (the legacy one and 25 more) were listed after 59 seconds; one `produce` gave all 26 identifiers and a view of 26 entries; one `tag wl-validate-batch <25 entries>` call tagged exactly the 25 named (Kit's tag listing showed exactly those 25, and no other, after 183 seconds).
- **Rate limit.** A burst of single-record reads during cleanup was answered `429`; the client now waits as `Retry-After` asks (at most 30 seconds a time, five tries) and `KitClient.test_a_rate_limit_answer_is_waited_out_as_kit_asks_a_bounded_number_of_times` covers it.

## Cleanup of the test account

Every subscriber this work created (35 across both runs and the earlier probes) was erased: read back, none holds an address or an answer.
Three empty tags (`wl-probe-tag`, `wl-validate-tag`, `wl-validate-batch`) remain in the test account.
The four subscribers the spike left there were never touched.

## Finding for the captain: Kit's geolocation

For a sign-up that has **confirmed**, Kit also stores a geolocation (city, state, country, latitude, longitude).
On the test account the founder's confirmed form sign-up carries all five; subscribers created through the API carry none.
Kit's `PUT /v4/subscribers/{id}` accepts a body that sets the block and answers 200 without changing it, so the D2 scrub (unsubscribe, placeholder address, blank every custom field) cannot clear it and the "empty shell" Kit keeps is not entirely empty.
This is not a field the PRD chose to store, it breaks the first acceptance criterion as written, and it weakens D2's "nothing identifying remains".
It does not change what the producer writes (the view never holds it).
The captain decides whether to accept it, look for an erase in the Kit dashboard, or have the privacy section (slice 4) say so.
I have not tried the dashboard.

## Not done here, and why

- Nothing was run against the production Kit account or form.
- The confirmation click, which only a mailbox can make.
- Browser sign-ups through the form (they would mail the founder and trigger Kit's quarantine); the form is US-WL02's, validated against the stub receiver.

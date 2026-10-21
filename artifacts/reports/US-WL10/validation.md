# US-WL10 validation: removal and retention (slice 3)

Run on 2026-10-20 (UTC) against the Kit **test** account (only subscribers the run created, named with `--restrict-to-ids`; production untouched) and synthetic stores in temporary directories.
Erasure on Kit cannot be undone (D2), which is why no subscriber that the run did not create was read or written.
No address appears below.
Nothing was written under the founder's Application Support folder and no `launchd` job was installed.

## What was run

- `python3 tools/waitlist/test-waitlist.py`: `Removal.*`, `DailyJob.*` and the Kit-client sweep cases (`KitClient.test_a_sweep_through_the_kit_client_deletes_only_what_it_may`, `test_retention_through_the_kit_client_with_an_injected_clock`, `test_erase_unsubscribes_overwrites_the_address_and_blanks_every_field`).
- A scratch driver on the Kit test account running the real command (`/usr/bin/python3 tools/waitlist/waitlist.py ...`) against subscribers it created.

## The Validation Test, on the Kit test account

| Step | Result |
| --- | --- |
| View before any removal | The view listed all the confirmed test sign-ups (6, with the unconfirmed one left out) and `check-view.py` accepted it. |
| 1. Unsubscribe through the link, run the daily sweep | The unsubscribe is Kit's own call (`POST .../unsubscribe`, what the link does). `sweep-unsubscribed` (dry run, the default): `due 1, erased 0` and the record still holds its address. With `--live`: `erased 1`; read back by id the record is state `cancelled`, address gone (a placeholder that is not an address), every custom field blank; the next view (5 entries) omits it and every other test sign-up is untouched. |
| 2. Mailbox request, `remove` | `remove --entry <entry>`: `erased one sign-up`; the record reads back as an empty shell; the view regenerated in the same run (4 entries). Re-running `produce` straight after (Kit's list may still lag) kept both removed sign-ups out. |
| 3. Launch-email date; retention at +29 then +30 days | Recorded with `--sent-on` a few days back; the output names the deletion date 30 days after it. Dry-run retention at +29: `not due until <date>`. At +30 (dry run): `due 4`, nothing deleted. Live through the production code path with an injected clock (a live `--as-of` against Kit is refused by the command, by design): +29 `due 0, erased 0`; +30 `due 4, erased 4`; all four read back as shells. |
| 4. Regenerate the view after each deletion and run the checker | Every view `check-view.py` accepted; the last has `"entries": []`. |
| 5. A hung run, then the sweep, then the next scheduled run | Shown on the synthetic store (`SevenSignups.test_a_removed_signup_is_gone_from_the_next_view_after_a_hung_run`): a producer run hung after its read is cut off at its limit and writes nothing; a removal started behind it waits for the lock, erases, regenerates; the next `produce` keeps it out. The sweeps take the same lock, so a hung run delays them by at most its limit, never indefinitely. |

## The captain's carried finding (the live retention sweep needs a validated date)

| Check | Result |
| --- | --- |
| `record-launch-email --sent-on <tomorrow>` | Exit 1, `the launch email cannot have been sent in the future`; nothing recorded. |
| `record-launch-email --sent-on <30 days ago>` | Exit 1, `that date is more than 7 days ago; recording it would delete every sign-up on <today> ... so it is refused`; nothing recorded. Also refused (unit tests): a malformed date (`2026-02-30`, `10/10/2026`, `2026-1-1`, an empty string, a time of day), and a second record without `--replace`. The window's edges: 7 days back is accepted, 8 is refused. |
| `record-launch-email --sent-on <2 days ago>` | Exit 0, `recorded <date>; the retention sweep will delete every remaining sign-up on or after <date + 30 days>`. |
| No date recorded: `sweep-retention --live` | Exit 0, `no launch-email date is recorded, so nothing is due and nothing was deleted`; the four other test sign-ups were untouched. |
| No date recorded, an unsubscribed sign-up, `daily --live` | `daily: all 3 steps ok`: the unsubscribed sweep erased the sign-up (address gone, fields blank), the retention step deleted nothing and said so, and the producer wrote a fresh view (`generated_at` later than before). |
| A damaged, hand-edited or too-old launch record | The sweep deletes nothing and exits 1 (`Removal.test_a_damaged_or_hand_edited_launch_record_deletes_nothing`: garbage, a date a month before it was recorded, a sent date after the recorded date, a wrong version). |
| Each step of the daily job runs whatever an earlier one did, and failures are reported | `DailyJob.test_a_step_that_fails_does_not_stop_the_next_and_is_reported` (a damaged launch record fails `sweep-retention`, `sweep-unsubscribed` and `produce` still run, the job exits 1 and names `sweep-retention`) and `test_a_hung_first_step_is_cut_off_and_the_rest_still_run` (a hung `sweep-unsubscribed` exits 3 at its limit and the other two steps run). |

## Acceptance criteria

Shown above: `remove` by entry or by an address typed at a pseudo-terminal prompt (never an argument, refused on a pipe, exact match so a record whose address merely contains another is untouched); the daily sweep; the launch-email record and the retention rule; both sweeps dry by default with an injected `asOf`; a view regeneration after every deletion; counts-only output; the runbook (`tools/waitlist/README.md`: who watches the mailbox and how often, what to do for an address that is not on the list); a deletion never touches another record (exact match; `--restrict-to-ids` refuses writes outside the named set).

## Open

- **Every waitlist email carries an unsubscribe link.** The confirmation message does (spike, unknown 5); the launch and beta broadcasts need a test send, shown in the go-live rehearsal.
- **A removal request is erased within 7 days.** The mechanisms are built and proven; the headroom depends on the installed daily job and the mailbox cadence, shown in the rehearsal.
- **Both sweeps run live in the installed schedule.** `launchd/app.reptoday.waitlist-daily.plist` runs `daily --live`, but nothing was installed or loaded; recording that the installed schedule ran is slice 4's.
- **Geolocation.** Kit keeps a derived geolocation block for a confirmed sign-up that its API cannot clear (US-WL06's record), so the erased shell is not entirely empty until the captain decides.

## The founder's delete in Kit (amendment, 2026-10-20 to 2026-10-21)

Kit's API cannot delete a subscriber, so removal and retention end with the founder deleting the scrubbed record in Kit's web app, and `waitlist.py kit-deletes` checks afterwards (README, "Delete in Kit").
Checked read-only on the Kit **test** account (account 2956640, test form 10070589), ids and counts only:

| Check | Result |
| --- | --- |
| Before the delete | 40 subscribers listed (1 active, 1 inactive, 38 cancelled), 35 read as scrubbed shells (once the listing's empty-string blanks were read as blank). A single-record read of an id the account does not hold answers `404`. |
| The captain's first try | Shell 4348812537 still answered (`200`, still listed) at 11 reads over 5 minutes and again about 3 hours later. Kit's subscriber list hides unsubscribed subscribers by default, so the shell was not where he looked. |
| The captain's delete of shell 4348812537 in Kit's web app | At 02:57 UTC on 2026-10-21 the id answers `404` and is gone from the listing (38 listed: 37 cancelled, 1 inactive, 34 shells). |
| `check_kit_deletes` against the real account, with a scratch ledger listing 4348812537 as awaiting its delete | Before the delete: the shell stayed waiting (delete by 2026-10-25) and an id the account does not hold was confirmed. After: `confirmed 1, waiting []`, and the ledger's awaiting list is empty while its tombstone stays. |

So Kit's web-app delete removes a subscriber completely, and the tooling's check sees it.
The captain reached the shell through its own page (`https://app.kit.com/subscribers/<id>`), so the runbook makes that the route and the commands print each id's page; the list's status filter set to Cancelled or All is the fallback, since the default list hides unsubscribed subscribers.

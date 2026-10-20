# US-WL07 validation: the anonymous view producer (slice 3)

Run on 2026-10-20 (UTC), against synthetic stores in temporary directories outside every checkout and against the Kit **test** account (production untouched; the Keychain item is the spike's, read at run time and never printed).
No address appears below.
Nothing was written under the founder's Application Support folder, and no `launchd` job was installed, loaded or enabled.

## What was run

- `python3 tools/waitlist/test-waitlist.py` (65 tests, Python 3.7 and 3.9): the producer cases are `SevenSignups`, `ProducerSafety` and `Identifiers`.
- `tools/waitlist/waitlist.py produce` against 7 Kit test subscribers (see US-WL06's record), then `tools/waitlist/check-view.py` on the output.
- The optional cross-check against gr0wthlab's real reader (`GR0WTHLAB_CHECKOUT`): **not run** (no gr0wthlab checkout in this worktree); the producer's output is accepted by `check-view.py`, which US-WL01 proved agrees with the reader on every fixture.

## The Validation Test

The synthetic store holds seven sign-ups listed out of date order, two on one day: a `null` Fit with an `unknown` Source, a ticked box, a recent date, one whose stored Fit, Source and beta are outside the allowed sets, one with no identifier, one unconfirmed (`inactive`), and one unsubscribed.

| Step | Result |
| --- | --- |
| 1. Produce, check, cross-check | The view has exactly `view`, `generated_at`, `entries`; five entries (the unconfirmed and the unsubscribed one are absent); each has exactly the five keys; the out-of-set sign-up is `fit` `null`, `source` `unknown`, `beta_opt_in` `false`; the sign-up with no identifier got one, in the ledger and in the store; entries are ascending by `signed_up_on` and the two same-day entries are in entry order (the test gives them identifiers that sort opposite to their ids); `check-view.py` accepts it. Cross-check not run. |
| 2. Remove one, rerun | `remove --entry` drops exactly that entry and keeps every other entry byte-for-byte (the newly assigned one included); the removed record is a shell (state `cancelled`, no address, every field blank). |
| 3. Make the checker fail | **Amended for D1:** under the ledger a planted `entry` (an address-shaped value, another sign-up's identifier) never reaches the view, and Kit's field is reset to the ledger's (`test_planted_entry_in_kit_is_reset_to_the_ledgers_value`, and on Kit). To make the checker itself fail: a sign-up created after the view's own time is refused by the checker's date rule (exit 2, message names `entry-date-future` and says the previous file is untouched), and an address inside the candidate is refused with the verdict `refused` and no value in the message; both leave the previous file's bytes identical. An over-limit candidate (the limit plus one byte) fails the run and leaves the file. |
| 4. Output inside the checkout, or a symlink into it | Both refused with exit 1 and nothing created; also refused: a symlink to a file in the checkout placed in an otherwise fine directory, a state directory inside the checkout, and a directory whose ancestor holds a `.git` file (as a linked worktree has). |
| 5. Interrupt between the temporary write and the rename | A crash injected there (exit 137, available only against a synthetic store) leaves the complete old file and a temporary file; the next run succeeds, removes the leftover and writes the complete new file. No partial file is ever visible. |
| 6. Confirm the unconfirmed one, rerun | It appears with `signed_up_on` still its submission date, under the identifier it was given while unconfirmed. (Synthetic store; the confirming click cannot be made through Kit's API.) |
| 7. Two runs at once | Three concurrent `produce` runs all exit 0; the new sign-up has one identifier, the same in the ledger, in the store and in the view, and the ledger holds no repeated identifier. |
| 8. A hung run, a removal, the next scheduled run | A producer run hung after its read (injected) is cut off at its limit (3 seconds in the test; 600 by default), exits 3 and writes nothing (the file's bytes are unchanged). A `remove` started while it held the lock waited, then ran: the first view generated after it omits the removed sign-up, and the next scheduled `produce` keeps it out. |

Also shown: the files are mode 600 in a mode 700 directory; an empty store writes `"entries": []`; a damaged ledger, a ledger entry that is an address and a corrupt creation time each fail the run and leave the view; the first-seen Source survives a resubmission; a stale Kit listing of an erased sign-up never brings it back (the ledger's tombstone).

## On the Kit test account

Seven subscribers created through the API (active, active, inactive, active with a planted `entry` and out-of-set answers, and three more used for the removal and sweep checks); listing caught up in 25 seconds (Kit's list trails a write; a single-record read does not).
`produce`: `entries 6, assigned 7, entry resets 1, unconfirmed left out 1`; `check-view.py` accepted; `signed_up_on` ascending; `generated_at` with a `+00:00` offset.
A second `produce` rewrote the view with the same ledger and printed `entry resets 1` again because Kit's list still showed the planted value (the lag); the reset is idempotent.
`unconfirmed left out` counted a sign-up Kit still listed as unconfirmed after the run had erased it (the same lag); the count now skips erased ids.

## Criteria that stay open

- **Cadence.** `tools/waitlist/launchd/app.reptoday.waitlist-daily.plist` is the daily definition and `waitlist.py daily --live` is what it runs (the test checks the file parses, runs `/usr/bin/python3 ... daily --live`, holds no environment and no secret), but nothing was installed: the scheduled run and the "does a run the Mac slept through run on wake" evidence are slice 4's.
- The reader cross-check against a gr0wthlab checkout.

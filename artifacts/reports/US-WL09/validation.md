# US-WL09 validation: send-time lookup on the founder's side (slice 3)

Run on 2026-10-20 (UTC) against the Kit **test** account and a synthetic store.
The Keychain item is the spike's (read at run time, never printed); production was not contacted.
No address appears below: the checks assert it and report booleans and counts.

## What was run

- `python3 tools/waitlist/test-waitlist.py`: `SendTimeLookup.*` (synthetic store, with a pseudo-terminal for `show`) and `KitClient.test_tagging_marks_exactly_the_named_signups_and_a_batch_of_twenty_five_is_one_call` (the real Kit client over HTTP to the local fake).
- A scratch driver on the Kit test account, restricted to the subscribers it created with `--restrict-to-ids`.

## The Validation Test

| Step | Result |
| --- | --- |
| 1. `tag beta-test <entry> <entry>` for two of three sign-ups; open Kit's list for the label | On Kit: `tag: tagged 2 confirmed sign-ups with the label 'wl-validate-tag'`. Kit's tag-member listing then showed exactly those two ids after 199 seconds (the listing trails a write), and no other. On the synthetic store only the two named sign-ups carry the label. |
| 2. `show <entry>` in a terminal, then `> out.txt` and `\| cat` | On a pseudo-terminal: exit 0 and the address printed once. Redirected to a file: exit 1 and the file is 0 bytes. Piped: exit 1 and no address in either stream; the refusal comes before Kit is contacted. |
| 3. `tag` with an identifier that does not exist | Exit 1: `'NoSuchEntry00000' is not a known entry identifier` on Kit and in the suite. A malformed identifier (`'bad id!'`) and an unconfirmed sign-up's are named too, in one error, and nothing is tagged (all or nothing). An address pasted as an identifier is named by position (`argument 1`), never repeated. |
| 4. Search the tool's logs and the working tree for the test addresses | Every command's output is asserted free of any `@`; the state directory (view, ledger, lock, launch record) is searched for each test address and for any `@` and holds none (`test_no_address_reaches_the_state_directory_or_any_log`). The working tree holds only the code. |

## Acceptance criteria

- `tag` and `show`: shown above.
- A batch at least as large as the Beta Cohort invitation batch (20) in one call: 25 sign-ups tagged by one `tag` invocation against the fake (`KitClient`), and by one invocation on the Kit test account (see "Additional Kit checks" in US-WL06's record).
- The credential comes from the Keychain (`wl_store.read_api_key`); the tool and its tests hold no credential or address, and the boundary guard (US-WL08) passes on them.
- The runbook states the send-time path: `tools/waitlist/README.md`, "Send-time path".

## Open

"The Waitlist send path always includes the unsubscribe link": every waitlist email is sent from Kit (the runbook says so), but showing a test broadcast that carries the link needs a send, which this slice does not make; the go-live rehearsal (slice 4) shows it.

# US-WL08 validation: the address boundary guard and the checkout audit (slice 3)

Run on 2026-10-20 (UTC) in a disposable worktree of the RepToday repository.
Every sabotage ran in a scratch directory (or, for the git-ignored credential, a file created in the checkout for one run and deleted), with every credential-shaped value and address assembled from parts, so none appears here or in the tests.
Findings print a file, a line and a rule name, never a value.

## What was run

| Check | Command | Result |
| --- | --- | --- |
| The guard's tests | `python3 tools/test-check-no-waitlist-credentials.py` | 25 tests pass (CI runs them on Python 3.9 and 3.12) |
| The guard on the real tree | `python3 tools/check-no-waitlist-credentials.py` | `waitlist boundary: 1367 files read, 0 findings`, exit 0, including the existing `Bearer` test fixtures (`CoachProxyClientTests.swift`, `ProxyVarietyLanguageProviderTests.swift`, `CoachRuntimeAuthenticationTests.swift`, `coach-auth-worker.test.js`, `coach-staging-labels.test.js`) and the two URL-userinfo inputs, which need no entry beyond the two the PRD names |
| The audit on the RepToday checkout | `tools/waitlist/audit-checkouts.sh .` | `audit RepToday: 75290 files read, 0 findings, 23 files over 50 MB not read`, exit 0 (the checkout holds a 10 GB git-ignored `build/` folder, so the audit read it too; the 23 unread files are over the 50 MB cap, and the audit says so) |
| The audit on a seeded scratch directory | `tools/waitlist/audit-checkouts.sh <scratch>` | `people.csv:2: rule export-file` and `settings.sh:1: rule credential-assignment`, exit 1; the seeded stray address in `notes.txt` is not reported (no address rule outside the RepToday checkout); the directory is byte-identical afterwards |
| A new git-ignored credential file in the checkout | a root `.env` holding a literal credential assignment, then the guard, then the audit, then the file deleted | the guard does not read it (git would not publish it); the audit reports `.env:1: rule credential-assignment`, by name and without the value; the file was deleted afterwards: the guard printed `waitlist boundary: 1368 files read, 0 findings`, and the audit printed `error: .env:1: rule credential-assignment` and `audit RepToday: 75292 files read, 1 findings, 23 files over 50 MB not read`, exit 1 |

## The Validation Test

1. **Clean tree.** Passes (above).
2. **Sabotage, one at a time** (`CleanAndSabotage.test_a_clean_scratch_tree_passes_and_each_sabotage_fails_with_its_own_rule` and the rule classes): a literal credential assignment fails `credential-assignment`; a CSV export with one address-shaped row fails `export-file`; a stray address fails `address`; each message is `file:line: rule <name>` with no value, and each passes again once removed.
   A binary file (a NUL byte) carrying the same address-shaped bytes is skipped, while the same bytes in a text file fail `address` (`ExportRule.test_a_binary_file_carrying_the_same_bytes_is_skipped_but_the_same_text_fails`).
   **Carried finding:** an export saved in Windows-1252 with one accented name fails naming the export rule alone (`ExportRule.test_a_windows_1252_export_with_an_accented_name_is_found_by_the_export_rule_alone`): the address rule reads only files that decode as UTF-8 with no NUL byte, so only the export rule can fail it.
   UTF-16 exports (with a byte-order mark, little and big endian), a Latin-1 JSON export and a damaged JSON export are found the same way; one-row CSV, TSV, JSON, JSONL and nested JSON exports are found; a file with an email column and only allowlisted addresses (the contact address, an example-domain address) is not an export.
3. **Audit** on the real checkout and on the seeded scratch directory (above): zero findings on the checkout; on the scratch directory the credential and the export but not the stray address, names and line numbers only.
4. **A git-ignored credential file** (above, and `Audit.test_an_ignored_credential_in_the_checkout_is_found_by_the_audit_and_removed_again` on a scratch checkout).

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| The guard's rules, in CI | `tools/check-no-waitlist-credentials.py`, run by the `waitlist` job on every pull request |
| "Email-shaped", text files only for the address rule | `AddressRule.test_whole_addresses_only`; the binary and Windows-1252 cases above |
| Allowlist, with the two file-pinned entries | `AddressRule.test_the_allowlist_is_the_contact_address_and_example_domains`, `test_the_two_userinfo_entries_apply_only_in_their_own_files` (the pinned string fails in any other file, a Waitlist path included) |
| A finding names file and line, never the value | the sabotage tests assert it |
| Non-vacuity | step 2 above |
| `audit-checkouts.sh` | read-only (a snapshot test and the seeded run), file scope stated in the guard's docstring |
| Keychain item names documented, values never | `tools/waitlist/README.md`, "State and credentials" |
| The producer's refusal to write in a work tree is covered by a test cited here | `ProducerSafety.test_refuses_a_path_inside_a_work_tree_or_a_symlink_into_one` in `tools/waitlist/test-waitlist.py` |
| The RepToday side is the only side enforced | stated in the README; the audit's credential and export rules are what check gr0wthlab's Guardrail G6 on the other two checkouts |

## Not done here

The audit was not run against the gr0wthlab or Mandu checkouts (it is run at go-live, slice 4, with the founder pointing it at them).

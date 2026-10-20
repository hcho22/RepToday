# US-WL01 validation: the Waitlist contract file and view checker

Date: 2026-10-19.
Spec: `.claude/agent/tasks/prd-waitlist_261019.md`, US-WL01.
Tooling only: no site, backend, event, privacy-policy or app change.
No email address appears in this record or in any committed file under `tools/waitlist/`; every address the tests use is assembled from parts at run time and written outside the repository.

## What landed

- `tools/waitlist/contract.json`: the approved strings, the three Fit answers with labels and tags, the four Source tags, `unknown`, `none`, the four posted field names, the view version `1`, the top-level and entry key lists, the entry pattern `[A-Za-z0-9_-]{1,64}` and the 10,000,000-byte limit.
- `tools/waitlist/check-view.py`: mirrors gr0wthlab's `waitlist.read` rule for rule and in the same order (address check on the file's text, then on every key and value, then the file-level checks, then the format).
  Exit 0 accepted, 1 failed, 2 refused (an address-shaped value), 64 usage.
  Each finding names a rule and a position (`entry 2, source`) and never a value.
- `tools/waitlist/fixtures/`: 42 committed files (5 valid, 37 failing, one per rule at least), none holding an `@`.
- `tools/waitlist/test-check-view.py`: 27 tests, 5 of them the optional cross-check.
- CI job `waitlist` in `.github/workflows/ci.yml` (Ubuntu, Python 3.9 and 3.12, no Xcode, no secret, no network).
- The wording fold-in: `README.md`, `convex/README.md`, `.github/workflows/ci.yml`, `ios/RepToday/project.yml` and `tools/check-no-committed-telemetry-secret.py` now carry the premise `AGENTS.md` states, "treat this repository as public (its visibility has changed before)".
  Only that wording changed; `python3 tools/test-check-no-committed-telemetry-secret.py` (7 tests) and `python3 tools/check-no-committed-telemetry-secret.py` pass unchanged.

## Validation Test

1. `python3 tools/waitlist/test-check-view.py` on Python 3.7.9, 3.11 and 3.12: `Ran 27 tests ... OK (skipped=5)` (the five skipped are the cross-check, which needs the environment variable).
2. `python3 tools/waitlist/check-view.py tools/waitlist/fixtures/valid.json` printed `check-view: accepted (entries: 3)` and exited 0.
   An address-in-`source` view written by the test's generator to a temporary directory outside the repository printed `check-view: refused` and one finding, rule `address-like` at position `entry 2, source`, exited 2, and repeated no part of the address.
3. Changing the heading in `contract.json` to "Join the wait list" and rerunning step 1 failed `test_every_approved_string_is_byte_identical_to_appendix_a` with `['copy.heading'] != []` (and nothing else); restoring the file made it pass again.
4. Cross-check, read-only, against the local gr0wthlab checkout (HEAD `48b6996`): `GR0WTHLAB_CHECKOUT=<checkout> python3.12 tools/waitlist/test-check-view.py` and the same on 3.11: `Ran 27 tests ... OK`, no skips.
   The checker and the real `waitlist.read` agreed on:
   - all 42 committed fixtures (verdict, entry count, the refused places, and the failed read's whole detail sentence);
   - all 29 generated cases (19 refused, 3 failed, 7 accepted), including the percent-decoding case that is refused rather than failed, base64 in both alphabets, a letters-and-digits-only base64 address, hex, the 10,000,000-byte limit exactly and by one byte, an address beyond the bytes the reader keeps, a repeated key, a float version and a `generated_at` with spaces;
   - a missing file and a folder;
   - 600 seeded mutations (400 structural, 200 byte-level) that reach all three verdicts.
   `git status` in the gr0wthlab checkout was clean before and after (bytecode writing is switched off before the import).

## Non-vacuity

With the cross-check on, each deliberate break of the checker failed the suite: reading only `max_bytes` bytes (2 failures), rejecting a float `1.0` version (1), not stripping `generated_at` (2), using the local day instead of the UTC day (2), judging percent-decoding by the whole-address rule (3), skipping the hex decoding (3).
Skipping the hex decoding also failed one test with no cross-check (the generated hex case), so the default CI run catches it too.
The checker was restored from a saved copy after each break.

## Checks that are not tests

- Lint: `ruff check --select E,F,W,B --line-length 120 tools/waitlist/` and `pyflakes tools/waitlist/*.py` report nothing (gr0wthlab's ruff settings; the repository has no Python lint configuration of its own).
- Address grep: `grep -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'` over every modified and new file matches only the privacy policy's published contact address, already quoted in the PRD, and nothing under `tools/waitlist/`.
  The test `test_no_file_under_tools_waitlist_holds_an_address_shaped_string` enforces the same rule, with the reader's looser rule as well, on every file there including the test itself.
- The PRD's US-WL01 acceptance boxes are ticked, V20 records the five reworded files, and "The gr0wthlab reader contract" gains the reader details its prose omitted.

## Where the reader and the PRD's prose differ

The reader wins; none of these changes a requirement.
They are listed in the PRD under "The gr0wthlab reader contract", and each is a committed fixture or a generated case.

## Not covered

- The CI job's own run is evidenced by the pull request's checks, not here.
  The job runs on Python 3.9 and 3.12; 3.9 was not available locally (3.7 and 3.11 and 3.12 were).
- `fromisoformat` accepts different spellings on different Python versions, so the checker is exact against the reader only on the same interpreter; the producer (US-WL07) writes the one spelling every version accepts.

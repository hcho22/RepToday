# PRD Skill Memory

This is the PRD skill's living memory.
It accumulates **new tools** and **habits/conventions** discovered while writing PRDs in this project, so each PRD is better than the last.

**How this file is used (see `PRD_SKILL.md`):**

- **Read first:** At the start of every PRD job, read this file and apply everything below.
- **Write last:** After finishing a PRD, append anything new you learned - a tool that helped, a convention the user enforced, a mistake to avoid next time.

**Rules for maintaining this file:**

- One entry = one durable lesson. Keep each entry to 1-3 lines.
- Only record things that generalize to **future** PRDs. Skip facts specific to a single feature.
- Before adding, scan for an existing entry that covers it - update that entry instead of duplicating.
- Delete entries that turn out to be wrong or obsolete.
- Put each full sentence on its own line.

---

## Tools

_New tools, skills, or commands that made PRD work better. Format: `- **tool-name** - what it does / when to reach for it`._

- **/grill-me** - Stress-tests a plan before the PRD is written. Run it first; build the PRD from the resulting discussion.
- **/grill-with-docs** - Same pre-PRD stress-test but also cross-references the codebase and resolves terminology; its resolved decisions (and any plan file it wrote) feed straight into the PRD.
- **chrome-devtools-axi** - Reads the live site and verifies website (`gtm/03-site`) stories in a real browser; `resize 390 844` is clamped to about 500 px by headless Chrome, so use `emulate --viewport "390x844x3,mobile,touch"` and re-open the page for a true phone width.

## Habits & Conventions

_Recurring preferences the user has confirmed, and conventions specific to how PRDs are written in this repo._

- Every user story needs a **Validation Test** (setup, steps, expected result, failure indicator) - no exceptions.
- UI stories must include a visual-verification step. **This is an iOS app**, so use "Verify in iOS Simulator" (build/run via `xcodebuild` or Xcode, inspect the screen) instead of the skill's default "Verify in browser using dev-browser skill."
  Website stories (`gtm/03-site`) are the exception: verify them in a browser with `chrome-devtools-axi` at 390 px and a desktop width.
- Acceptance criteria must be verifiable, never vague ("Button shows confirmation dialog" not "Works correctly").
- **PRD doubles as a progress tracker.** As each task/user story from a generated PRD is completed, mark its acceptance-criteria checkboxes `[ ]` → `[x]` in the PRD file (`.claude/agent/tasks/prd-*.md`), so done vs. remaining is visible at a glance.
- **Post-implementation archive PRDs** - a PRD authored outside the repo (e.g. from a design grill) and shipped before it was committed gets archived into `.claude/agent/tasks/prd-*_<YYMMDD>.md` after the fact; keep the source text faithful and add a `**Status:** Complete - shipped` header line citing the stories/PRs, rather than re-checking the acceptance boxes here.
- **For rename/refactor/infra PRDs** (no new feature behavior), Validation Tests lean on **grep guards** ("`grep -rn OLD` returns nothing"), the full `xcodebuild` test suite, and a Simulator boot check - not feature interactions. Order stories by dependency and call out irreversible-after-publish fields (bundle id, CloudKit container, StoreKit ids) explicitly.
- **Filename and prefix:** save as `.claude/agent/tasks/prd-<slug>_<YYMMDD>.md` (the date the PRD is written), and pick a `US-XX##` story prefix only after grepping existing PRDs and docs for collisions (`US-T##` is telemetry, so a new prefix starting with T needs a second letter that no story uses).
- **Interview-to-PRD traceability:** when a PRD is built from a recorded design interview or an approved request, include a table mapping each numbered decision or request clause to the stories and FRs that carry it, and route anything it did not settle to Open Questions (options, a marked recommendation, the stories it gates) instead of deciding it in an acceptance criterion.
  Write an ADR only for what the interview or request already fixes; choices still left to the captain get no ADR until they are settled.
- **Re-verify inherited facts:** re-check every code fact a grill record states against current `main` before relying on it, and list the results in a "Verified facts" section that marks additions and discrepancies rather than silently correcting the record.
- **Match another repo's contract by reading its validator:** when the output is read by another repo (a file format, an event), read that reader's code and tests read-only, cite the file, and map each rule it enforces to a requirement; the request's prose can omit rules the reader checks (exact key sets, date ordering, size limits).
- **Probe the live system before specifying routes or hosting behavior:** a default such as a single-page fallback can make a missing route look present (every path returned 200), so record status codes in Verified facts.
- **Mark unverifiable vendor behavior "confirm" and give it a spike story:** never state what an email service, API or host does as fact when the repo cannot show it.
- **Approved wording and personal data:** carry request wording verbatim in an appendix and diff it against the source, list new strings as proposals for approval, and put no real address in a PRD (describe fixtures as assembled at test time).
- **External inputs (art, data, assets) outside the repo:** re-run any coverage or inventory check read-only at PRD time and put reproducible numbers (counts, bytes, gaps) in the PRD, without copying private paths into it.
- Engine / session-shape PRDs are often **engine-only**: the continuous-circuit player (US-CC02 onward) renders stations and round counts data-drivenly, so a new session shape usually needs no player/UI story.
  Verify the player already handles it before scoping any UI work.

## Mistakes to Avoid

_Things that went wrong in a past PRD, so they don't happen again._

_(none yet)_

---

_Last updated: 2026-10-19_

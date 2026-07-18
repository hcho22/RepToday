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

## Habits & Conventions

_Recurring preferences the user has confirmed, and conventions specific to how PRDs are written in this repo._

- Every user story needs a **Validation Test** (setup, steps, expected result, failure indicator) - no exceptions.
- UI stories must include a visual-verification step. **This is an iOS app**, so use "Verify in iOS Simulator" (build/run via `xcodebuild` or Xcode, inspect the screen) instead of the skill's default "Verify in browser using dev-browser skill."
- Acceptance criteria must be verifiable, never vague ("Button shows confirmation dialog" not "Works correctly").
- **PRD doubles as a progress tracker.** As each task/user story from a generated PRD is completed, mark its acceptance-criteria checkboxes `[ ]` → `[x]` in the PRD file (`.claude/agent/tasks/prd-*.md`), so done vs. remaining is visible at a glance.
- **For rename/refactor/infra PRDs** (no new feature behavior), Validation Tests lean on **grep guards** ("`grep -rn OLD` returns nothing"), the full `xcodebuild` test suite, and a Simulator boot check - not feature interactions. Order stories by dependency and call out irreversible-after-publish fields (bundle id, CloudKit container, StoreKit ids) explicitly.

## Mistakes to Avoid

_Things that went wrong in a past PRD, so they don't happen again._

_(none yet)_

---

_Last updated: 2026-06-25_

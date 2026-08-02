# Completeness Critic - v2 package audit (2026-08-01)

Persona: completeness critic with authority to send phases back.
Scope: every deliverable in gtm-master-prompt-v2.md sections 9-11 plus each phase gate in section 7, checked against the actual tree under gtm/.

Verdict up front: Phases 1-4 have their gate evidence on disk and it is real, not theater.
The tournament scorecard shows margins (naming-decision.md), the fresh-agent gate shipped a round-1 FAIL and a round-2 PASS with both artifacts, four site screenshots exist for both hero variants, the video gate has ffprobe plus viewed frames plus a close-card frame, the PMF kit has 16 pre-registered angles and 6 hook-only A/B pairs, the channel plan commits to a dual ranking and a spend verdict, and the event schema and thesis kill criteria exist.
What fails is the packaging layer: recap.html, README.md, self-grade.md, sources.md, and the execution record are all still the v1 artifacts, and they now assert things the v2 tree makes false.
Phase 6 cannot close, and Phase 5's v2 evidence is not yet on disk.

## Objections

### 1. MUST-FIX - recap.html (entire file; lines 65-118 worst)

recap.html is the v1 front door verbatim: it presents the killed listing name "Rep Today, Rest Tomorrow" as the standing verdict (line 65, directly contradicting D-106 and 02-brand/naming-decision.md), links dead directories 05-thesis/, 06-redteam/, 07-extras/ (lines 61, 82, 91, 106-112), links screenshot filenames that no longer exist (screenshot-mobile-390x844.png vs the actual screenshot-a/b-* files, line 103), and links the v1 tournament/ and v1 gate-test-report.md instead of tournament-v2/ and gate-test-report-v2.md.
It also omits every net-new v2 required deliverable: the PMF kit, the 06-channels channel plan, the event schema, the marketing-agent build spec, and the second hero variant.
Its naming card even describes the v1 tournament outcome, not the v2 pitch-2 anti-discipline win.
Smallest honest fix: rebuild the deliverables table against the v2 tree (05-social-pmf, 06-channels, 07-thesis, 08-redteam, 09-extras), replace the naming card with the D-106 verdict (plain "Rep Today", suffix killed, v2 scorecard with pitch-2 margins), fix the four screenshot links to the -a-/-b- names, repoint gate links to the -v2 artifacts, refresh the build date and orchestration paragraph, and re-run a programmatic link check.

### 2. MUST-FIX - README.md (Map table, lines 21-32)

The map lists 05-thesis/, 06-redteam/, 07-extras/ and has no rows for 05-social-pmf/ or 06-channels/, so the three-command front door routes a stranger into directories that do not exist.
Smallest honest fix: rewrite the map to the v2 layout (05-social-pmf, 06-channels, 07-thesis, 08-redteam, 09-extras) and add one-line descriptions for the PMF kit and channel plan.

### 3. MUST-FIX - sources.md (whole file; "Total: 139" at the last line)

The v2 prompt requires every cited URL with a fetch timestamp, and self-grade item 2 claims completeness, but sources.md contains only the 14 v1 research sections.
The five v2 research files (meta-ad-library-sweep.md, pain-point-frequency.md, platform-signal-evidence.md, creative-carries-targeting-sources.md, ios-attribution-and-paid-vs-organic.md) carry roughly 141 https citations between them and none appear in sources.md; the file even says "Later phases append their own sections below" and none were appended.
Smallest honest fix: append the five v2 sections with their fetch timestamps and update the total count.

### 4. MUST-FIX - self-grade.md (whole file, dated 2026-07-15)

The shipped self-grade is the v1 grade: it checks boxes that are currently false in this tree ("recap.html links everything; every link resolves", "sources.md complete") and grades none of the v2-only checklist items in section 11 (transcript-never-cited, anti-discipline pitch genuinely argued, PMF kit angle count and pre-registration, channel-plan commitment with citations).
A stale self-grade asserting green is worse than no self-grade; it is exactly "a placeholder pretending to be finished work".
Smallest honest fix: regrade against the v2 section 11 checklist after objections 1-3 and 5-8 are fixed, and keep the v1 grade only if clearly labeled as the v1 run's record.

### 5. MUST-FIX - dead relative links after the D-102 git mv (three files)

04-video/gate-report.md line 41 links ../06-redteam/pre-publication-checklist.md (now ../08-redteam/).
self-grade.md lines 36 and 46 link 06-redteam/dossier.md and 06-redteam/pre-publication-checklist.md.
08-redteam/skeptic-thesis.md line 3 links ../05-thesis/investment-thesis.md and ../05-thesis/channel-plan.md.
Every one 404s from its own directory today.
Smallest honest fix: repoint all to 08-redteam/ and 07-thesis/ respectively (or, for the frozen v1 red-team files, fix the paths in place while keeping the 2026-07-15 dating).

### 6. MUST-FIX - 06-channels/channel-plan.md line 110

The committed channel plan's own change-log says "Note: `05-social-pmf/` is empty at this writing; the kit is a committed v2 deliverable ... and A1 depends on it landing."
The kit now exists with 16 angles and 6 A/B pairs, so the plan's rank-1 channel cites its load-bearing instrument as missing when it is not; a cold reader must not have to reconcile that.
Smallest honest fix: replace the sentence with a pointer to the shipped kit (16 angles, 6 pairs, 14-day cadence) so A1's dependency reads as satisfied.

### 7. MUST-FIX - 01-research/product-facts-brief.md line 7

The package's own ground-truth brief still says the App Store listing name is "planned: 'Rep Today, Rest Tomorrow'", which D-106 and naming-decision.md killed.
Downstream agents are instructed to treat this brief as canon, so the canon currently contradicts the locked naming decision.
Smallest honest fix: one line, "listing name: 'Rep Today' (the v1 'Rest Tomorrow' suffix was killed in v2, see 02-brand/naming-decision.md)".

### 8. MUST-FIX - master-prompt-execution-record.md (whole file)

The record maps only gtm-master-prompt.md (v1), cites 05-thesis/06-redteam/07-extras paths throughout, and claims "§7 Output structure: matches the specified tree", which is false for the v2 tree it now sits in.
recap.html links it as the end-to-end audit evidence, so it must either cover the v2 run or clearly stop claiming to be the record of the current package.
Smallest honest fix: retitle it as the v1 run record with a banner pointing to the v2 successor, fix its stale paths, and append (or add as a sibling section) the v2 run's section-to-artifact map including the new gates (tournament-v2, gate-test-report-v2, PMF kit, dual-ranked channel plan, event schema, marketing-agent dry run).

### 9. MUST-FIX - 08-redteam/ (Phase 5 v2 gate evidence absent)

Everything in 08-redteam except this file is the 2026-07-15 v1 red team: the dossier's header, the five persona files, and _findings.json all attack the v1 package (they cite the dead listing name as current, the 94-char keyword field, and 07-extras paths).
The v2 Phase 5 gate ("at least one thing changed materially") has no v2 evidence artifact on disk yet, so Phase 5 cannot be marked closed and Phase 6 cannot start.
This run is visibly in progress (this file is part of it), so the objection is a gate hold, not an accusation of skipping.
Smallest honest fix: finish the v2 red-team pass, disposition its findings, and add a clearly dated v2 section to dossier.md recording what changed; label the v1 persona files as frozen v1 attacks.

### 10. SURVIVING-OBJECTION - dual-generation tree with no authority manifest

The package deliberately keeps v1 and v2 artifacts side by side (tournament/ beside tournament-v2/, gate-test-asset.png beside -v2.png, channel-plan-v1.md beside channel-plan.md, the superseded social-launch-kit.md, the v1 red team beside the v2 one).
D-101/D-102 justify this for diffability, but nothing except the not-yet-rebuilt recap says which file is authoritative for each deliverable, and a consumer who lands on aso-landscape.md line 83 or the v1 tournament will absorb a killed decision.
Fixing recap (objection 1) mitigates this, but the weakness is structural and should be carried visibly: any doc that survives from v1 without a superseded-by banner is a live trap.

### 11. NOTE - 01-research/aso-landscape.md lines 13 and 83

The v1 ASO file still recommends the title "Rep Today, Rest Tomorrow" with no superseded pointer.
It is dated research and naming-decision.md overrides it, but a one-line banner ("title recommendation superseded by D-106") would cost nothing and close the trap named in objection 10.

### 12. NOTE - 09-extras/social-launch-kit.md line 12

The superseded banner is done well, but the frozen body still links ../05-thesis/channel-plan.md, a dead path.
Harmless inside a do-not-use file; fix it if touching the file anyway.

### 13. NOTE - what was checked and found sound (no objection manufactured)

Tournament scorecard with visible margins: present, including the 0.10 near-tie honestly disclosed.
Fresh-agent gate: round-1 FAIL shipped with root cause and guideline edits, round-2 PASS, both artifacts on disk.
Site: both hero variants, four screenshots at both required sizes, pain states named in mined verbatim quotes with a no-users disclaimer.
Video: ffprobe, five viewed frames plus a 48s close-card frame, strip, D-106 end-card fix verified in-frame.
PMF kit: 16 angles spanning all seven required territories plus contrarian, 6 isolated-hook A/B pairs, day-7 midpoint gate, honest zero-follower measurement rules, 208 lines of week-1 drafts.
Channels: dual $0/$500 ranking with a committed "mostly do not spend it yet" verdict and a cited paid-vs-organic answer.
Event schema: one page, no warehouse, funnel matches section 5.2.
Extras: exactly three chosen plus the invented review-response playbook, with the retired v1 kit labeled and the dropped options reasoned in D-104.
No "Rest Tomorrow" or v1 hero wording survives in any v2-authoritative asset (site, video, screenshots src, teaser, PMF kit).

## Counts

MUST-FIX: 9.
SURVIVING-OBJECTION: 1.
NOTE: 4.

## Phase disposition

Phases 1-4: gates evidenced, pass.
Phase 5: held open pending the v2 dossier (objection 9).
Phase 6: sent back; recap.html, README.md, sources.md, self-grade.md, and the execution record are the v1 files and fail section 11 items 2, 16, and 17 as the tree stands.

# Execution Record: gtm-master-prompt.md

`gtm-master-prompt.md` is a markdown orchestration prompt, not an executable script.
Running it means executing its instructions.
This record maps every section of the file to the execution evidence, so the run is auditable end to end.
Run window: 2026-07-14 21:15 PT through 2026-07-15, in this repository, all output under `gtm/`.

| Master prompt section | Requirement | Executed as | Artifact |
|---|---|---|---|
| §0 Context | Read the PRD in full before anything else | PRD read in full (982 lines, both pages) before any GTM work; the rebrand PRD read as well, which corrected §0's stale naming state | `01-research/product-facts-brief.md` (distilled canon) |
| §0 Naming state | Evaluate Cairn/Stack/FitSnack/new names against positioning, collisions, domains | Collision scan executed via live App Store/DNS/web fetches; Rep Today treated as incumbent per the founder's completed rebrand (logged D-002) | `01-research/name-collisions.md`, `decisions-log.md` D-002 |
| §1 Mission | Complete, locally-runnable GTM package a stranger can act on; a falsifiable case, not a proof | All 9 required deliverables + 3 extras + 1 invented deliverable produced; thesis carries evidence-against and kill criteria as first-class sections | `recap.html` (front door), `05-thesis/investment-thesis.md` |
| §2.1 No spending | Nothing purchased or signed up for | Only local tools (Chrome, ffmpeg, macOS `say`) and free web fetches used; VO is TTS because hiring a voice would violate this rule | `self-grade.md` item 1 |
| §2.2 Publish nothing | Everything local | No deploys, posts, accounts, or registrations; social kit is labeled drafts-only | `self-grade.md` item 1, `07-extras/social-launch-kit.md` header |
| §2.3 Truth policy | Fetched-URL-backed claims only; [ASSUMPTION] labels; zero fabricated social proof | 139 fetched URLs with timestamps; assumptions labeled throughout; zero testimonials/user counts/ratings anywhere including mocks | `sources.md`, `self-grade.md` items 2-4 |
| §2.4 No clearance claims | State clearance is unverified, founder's next action | Present in every asset; strengthened by the red team ("pending" ruled misleading, replaced with "has not been trademark-searched or registered") | `02-brand/naming-decision.md`, dossier |
| §2.5 No health claims | None anywhere | Voice rules enforced; two edge cases ("same-day relief", "real mobility") caught by the red team and removed | `06-redteam/dossier.md` |
| §2.6 Never ask a question | Decide, mark [DECIDED BY AGENT], log alternative | 10 logged decisions D-001..D-010 | `decisions-log.md` |
| §2.7 Stay in project dir | All output under /gtm/ | No app source or PRD modified; everything under `gtm/` | repo state |
| §3 Founder voice rules | Every founder-voiced line passes | Voice rules embedded in the brand guidelines §7 and enforced across site, video script, social kit, playbook; red team swept violations | `02-brand/brand-guidelines.md` §7 |
| §4 Fan out researchers | Per-competitor agents (8 named + 3+ found), review mining, economics, ASO, creators | 14-agent parallel research workflow (8 named teardowns, a scout that added Seven/Bend/Wakeout/pliability, review mining, economics, ASO, creators, collisions); Sweat teardown redone inline after an agent hang | `01-research/` (14 files) |
| §4 Tournament | >=4 blind pitchers, >=3 judges with published differing rubrics, published scorecard with losers | 4 blind pitchers (distinct angles) + 3 judges (differentiation/conversion/defensibility), unanimous winner, visible margins, losers' reasons published | `02-brand/tournament/`, `02-brand/naming-decision.md` |
| §4 Adversarial verification | Skeptic refutes each load-bearing thesis claim, gets the last word | Skeptic agent ran claim-by-claim (REFUTED/WEAKENED/STANDS); its surviving objections ship verbatim | `06-redteam/skeptic-thesis.md` |
| §4 Red team | 4 personas: investor, competitor growth head, cynical user, App Store reviewer/FTC lawyer | All four ran; 55 must-fixes dispositioned; 30 surviving objections published | `06-redteam/` (5 attack files, dossier) |
| §4 Completeness critic | Phases checked against exit criteria | Each phase gated by the orchestrator against the master prompt's own gates before being marked done (see gate rows below) | gate reports |
| §5 Phase 1 gate | Fresh agent produces on-brand asset from guidelines alone | Ran; asset passed; 8 surfaced gaps fixed into the guidelines | `02-brand/gate-test-report.md` |
| §5 Phase 2 gate | Screenshots at 390x844 and 1440x900, saved and inspected | Captured, inspected, re-captured and re-inspected after red-team fixes | `03-site/screenshot-*.png` |
| §5 Phase 3 gate | ffprobe + frames at 0/25/50/75/100% viewed + strip saved + script passes voice rules | Executed twice (initial render rejected for transition text-overlap; rebuilt; rebuilt again post-red-team and re-gated) | `04-video/gate-report.md`, `frame-strip.png`, `ffprobe-report.txt` |
| §5 Phase 4 gate | At least one material change from the red team | Kill criteria rewritten, economics recomputed, false legal line replaced across six assets, video rebuilt, hero changed | `06-redteam/dossier.md` |
| §5 Phase 5 | recap.html as single front door | Built; explains the business in <5 min; name recommendation + unverified clearance; thesis and strongest surviving objection side by side; every deliverable linked; links verified programmatically | `recap.html` |
| §6 Required deliverables 1-9 | All nine | All present | `recap.html` deliverables table |
| §6 Choose 2-3 extras | By "feels most real to a stranger"; drop the rest and say so | App Store screenshot set, investor teaser, social kit chosen; deck/walkthrough/email sequence dropped with reasons | `decisions-log.md` D-007 |
| §6 Invented deliverable | The "they actually thought about this" artifact | App Store review-response playbook: 13 predicted review themes with evidence-cited, pre-written founder responses | `07-extras/review-response-playbook.md` |
| §7 Output structure | Exact directory layout incl. decisions-log.md and sources.md | Matches the specified tree | `README.md` map |
| §8 Self-grade | Report honestly, including unfixed failures | Written, with five limitations kept and reasoned | `self-grade.md` |

Orchestration topology actually used (logged per §4's "log the topology you chose"):
one 14-agent research fan-out workflow; one 7-agent tournament workflow (4 pitchers -> barrier -> 3 judges); one synchronous fresh-agent gate test; three parallel builders (site, video, thesis) then four parallel extras builders; one 5-agent red-team workflow; two parallel fix agents plus orchestrator-executed video rebuild; all gates executed by the orchestrator, not self-certified by the producing agents.
Two account session-limit outages occurred mid-run; both were absorbed by resume/rebuild without quality shortcuts (details in `self-grade.md`).

---

# Execution Record: gtm-master-prompt-v2.md (v2 update run)

Run window: 2026-08-01 through 2026-08-02 PT, all output under `gtm/`.
The v1 table above is frozen history; its `05-thesis/`, `06-redteam/`, `07-extras/` paths refer to the v1 layout, renamed in v2 to `07-thesis/`, `08-redteam/`, `09-extras/` (D-102).
The v2 run was an update run (D-101): v1 research and assets carried forward where still valid; everything a v2 delta invalidated was rebuilt.

| v2 prompt section | Requirement | Executed as | Artifact |
|---|---|---|---|
| §0 Context | Read the PRD in full first | PRD v6 read in full (1,093 lines) before any v2 work | conversation record; `01-research/product-facts-brief.md` (canon, updated for D-106) |
| §0 Naming state | Stress-test RepToday, confirm or beat; incumbency is not a score | All 4 blind pitchers + all 3 judges issued independent name verdicts; RepToday confirmed 7-0; listing suffix killed | `02-brand/naming-decision.md`, `02-brand/tournament-v2/` |
| §4 Discipline brief | Discipline as proposed spine; at least one pitch must argue against it; judges decide on merit | The anti-discipline pitch won rank 1 on all three rubrics; discipline shipped as internal spine only, reported honestly | `02-brand/positioning.md` (verdict stated first), scorecard in `naming-decision.md` |
| §5 Channel doctrine | Verify iOS attribution with live sources; commit to paid-vs-organic; creative-carries-targeting from primary sources; no warehouse | 5-researcher refresh (63+ fresh fetches); committed zero-paid verdict; one-page event schema instead of any warehouse | `01-research/ios-attribution-and-paid-vs-organic.md`, `creative-carries-targeting-sources.md`, `06-channels/channel-plan.md`, `06-channels/event-metric-schema.md` |
| §5.3 Transcript | Nothing from the transcript citable | Transcript not on disk (D-103); every method claim re-verified from primary sources; zero transcript citations anywhere | `decisions-log.md` D-103, `sources.md` v2 section |
| §6 Orchestration | Parallel researchers, blind tournament >=4 with judges >=3, skeptics, red team, completeness critic | 5 workflows + 4 standalone agents, ~34 subagent runs: research (5 parallel), tournament (4 blind pitches -> 3 judges), production (5 lanes incl. 3-step brand-gate pipeline), red team (5 personas incl. completeness critic), fixes (5 lanes -> dossier) | topology note in `recap.html`; workflow journals in the session record |
| §7 Phase 1 gate | Fresh agent + guidelines alone produces an on-brand asset | Round 1 FAILED honestly (canvas clipping); 4 guideline gaps closed; round 2 blind retest PASSED, orchestrator-verified | `02-brand/gate-test-asset-v2.{html,png}`, `gate-test-report-v2.md` (both rounds) |
| §7 Phase 2 gate | Two hero variants; screenshot-verified 390x844 + 1440x900 | Both variants shipped and captured at both widths, viewed, one fold defect fixed and re-shot; pain states named in copy | `03-site/index.html`, `index-b.html`, 4 `screenshot-*.png` |
| §7 Phase 3 gate | ffprobe + frames at 0/25/50/75/100% actually viewed + strip | Video rebuilt (killed suffix removed from end card, Hero A wording); all gates re-run, frames viewed | `04-video/gate-report.md`, `ffprobe-report.txt`, `frame-strip.png` |
| §8 PMF kit | >=15 distinct angles, A/B hook-only pairs, platform assignment, 14-day cadence, results guide, drafts, no fabricated engagement | 16 angles / 6 pairs / TikTok + Shorts + Reddit-listening / day-7 gate / honest zero-follower noise limits; signals restricted to zero-follower-measurable after red team | `05-social-pmf/` (7 files) |
| §7 Phase 5 gate | Red team must change something material | 58 findings, 26 MUST-FIX applied (K0 ladder unified, site data-FAQ corrected, day-2 draft de-invented, screenshot copy aligned to build, teaser re-denominated); 16 surviving objections ship visibly | `08-redteam/dossier.md`, persona files `*-v2.md` |
| §7 Phase 6 | recap.html front door; every link resolves | Rebuilt for v2; 126 relative targets verified on disk; thesis beside strongest surviving objection; responsive (390px verified via real-viewport browser: docScrollWidth 375, no overflow) | `recap.html`, `README.md`, `sources.md` |

## Run interruptions (disclosed)

The run was interrupted twice by session limits/auth expiry (once mid-tournament, once mid-fix-phase) and recovered via workflow resume with cached agents; one workflow script bug (a literal placeholder instead of interpolated fix summaries) was caught before the dossier wrote and corrected.
One capture artifact was diagnosed at the end: macOS headless Chrome lays pages out at a ~500px minimum window even when asked for 390, cropping the capture; the recap's true-390 layout was therefore re-verified in a real 390px browser viewport (no overflow) rather than trusting the cropped capture.
None of these left defects in deliverables; they are disclosed here because an auditable record beats a tidy one.

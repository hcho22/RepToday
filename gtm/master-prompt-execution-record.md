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

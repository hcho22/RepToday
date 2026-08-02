# Rep Today - Go-To-Market Package (v2)

Everything is local and static. Nothing here is published, deployed, or purchased.

## Run it (3 commands)

```bash
cd /Users/hcho/firstmate/projects/reptoday/gtm
python3 -m http.server 8080          # serves the whole package
open http://localhost:8080/recap.html # the front door (landing page: /03-site/index.html)
```

Play the launch video:

```bash
open 04-video/launch-video.mp4
```

## Map

| Path | What it is |
|------|------------|
| `recap.html` | Single front door - start here |
| `01-research/` | Sourced research: competitor teardowns, review mining, economics, ASO, creators, name collisions, plus 5 new v2 files (attribution, Meta ad sweep, pain-point frequency, platform signals, creative-carries-targeting) |
| `02-brand/` | Positioning, naming decision, brand guidelines, v1 tournament, `tournament-v2/` (4 blind pitches + 3 judges), brand-gate round 2 (`gate-test-*-v2.*`) |
| `03-site/` | Landing page in two hero variants (`index.html`, `index-b.html`) + 4 screenshots (a/b x desktop/mobile) |
| `04-video/` | Launch video, VO script, build scripts, ffprobe report, frames, gate report |
| `05-social-pmf/` | Week-one PMF kit: 16 angles, 6 A/B pairs, 14-day cadence, read-the-results guide, week-1 drafts |
| `06-channels/` | v2 channel plan, event/metric schema, retained v1 plan (`channel-plan-v1.md`) |
| `07-thesis/` | Investment thesis with kill criteria K0-K9 |
| `08-redteam/` | v2 personas + dossier + pre-publication checklist, v1 persona history |
| `09-extras/` | Investor teaser, App Store screenshot comps, social launch kit, review-response playbook (invented deliverable), `marketing-agent/` build spec + creative loop |
| `decisions-log.md` | Every [DECIDED BY AGENT] call (v2: D-101..D-106) |
| `sources.md` | Every URL cited, with fetch timestamp (v1 + v2 runs) |
| `self-grade.md` | Self-grade record |
| `gtm-master-prompt.md` / `gtm-master-prompt-v2.md` | The two master prompts |

## Honesty notes

- The app is pre-launch: zero users, zero downloads, zero revenue. Nothing in this package claims otherwise.
- Formal trademark and App Store name clearance are UNVERIFIED for Rep Today - the founder's next action.
- v2 refresh ran 2026-08-01/02; v1 artifacts are retained side by side as labeled history, and the red-team dossier (`08-redteam/dossier.md`) is the current gate record.

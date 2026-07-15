# Self-Grade Against the Master Prompt (§8)

Graded 2026-07-15, after the red team pass. Honest, including what was not fixed and why.

- [x] **No spend. No publication. Nothing live.**
  Everything is local files. No accounts created, no domains bought, no posts made, no deploys. The only "services" used were already-local tools (Chrome, ffmpeg, macOS `say`) and free web fetches.

- [x] **Every factual claim has a fetched URL; sources.md complete; zero dead links.**
  139 URLs in [sources.md](sources.md), each with a fetch timestamp from the run. Research files carry claims with inline sources; downstream docs reuse only researched claims with their URLs. Every relative link in recap.html, README.md, and the dossier was programmatically verified to resolve. *Caveat stated honestly: URLs were verified live during the run; link rot after the run date is possible, and two retention benchmarks are anchored on aggregator blogs because primary fetches failed - that provenance is now disclosed inside the thesis itself (a red-team fix).*

- [x] **Zero fabricated stats, users, quotes, testimonials, or social proof anywhere - including mockups and ad creative.**
  The landing page, video, screenshots, teaser, and social kit contain no user counts, no star ratings, no testimonials, no press logos. UI mocks show a single plausible user state and are labeled pre-release mocks. Evidence quotes are real, fetched, and captioned as being about *other* products or from *other* communities, never about Rep Today. The review-response playbook's "reviews" are explicitly labeled predicted/hypothetical.

- [x] **Every guess is labeled [ASSUMPTION] with reasoning.**
  Install ranges, persona details, effort estimates, K8 thresholds, cohort floors, platform-share direction - all labeled, with reasoning shown, in the thesis, channel plan, positioning, and teaser.

- [x] **No health/medical claims. No XP/levels/badges/streak language. No bro-fitness register.**
  The red team's lawyer caught two edge cases ("same-day relief", "real mobility") and both were removed. Streak/badge words appear only to name the mechanics the product rejects.

- [x] **Name recommendation carries the explicit unverified-clearance caveat.**
  Strengthened by the red team: "clearance pending" was ruled misleading (nothing is pending) and replaced everywhere with "has not been trademark-searched or registered, and the App Store name has not been reserved - the founder's next action." The naming decision, recap, README, site footer, teaser, and brand guidelines all carry it.

- [x] **Nothing contradicts the PRD.**
  Offline on-device generation, ready-on-open, zero-equipment, forgiving non-streak score, mobility co-primary, AI-tunes-policy-never-generates - all stated exactly per the PRD across every asset. One near-miss was caught in reverse: the site claimed the in-session swap, the fact-check confirmed the PRD implements it (US-C08/US-K03), and the internal facts brief was corrected.

- [x] **Site verified at both widths; screenshots in package.**
  [390x844](03-site/screenshot-mobile-390x844.png) and [1440x900](03-site/screenshot-desktop-1440x900.png), captured, inspected by the orchestrator, re-captured and re-inspected after the red-team fixes.

- [x] **Video: ffprobe output + frame strip in package; script passes voice rules.**
  [ffprobe-report.txt](04-video/ffprobe-report.txt), [frame-strip.png](04-video/frame-strip.png), frames viewed at all five gate points plus a close-card frame; audio verified non-silent; rebuilt twice (once for a transition defect I caught, once for red-team fixes) and re-gated both times. Details in [gate-report.md](04-video/gate-report.md).

- [x] **Brand guidelines passed the fresh-agent test.**
  A fresh agent restricted to the guidelines file alone produced an on-brand asset ([report](02-brand/gate-test-report.md)); the 8 gaps it surfaced were fixed into the guidelines the same day.

- [x] **Red team ran; something changed because of it; objections visible in final docs.**
  55 must-fix objections, all dispositioned; material changes include rewritten kill criteria, recomputed base-case economics, a false legal line replaced across six assets, a rebuilt video, and a changed hero. 30 surviving objections ship verbatim in the [dossier](06-redteam/dossier.md), and the single strongest sits beside the thesis summary on the recap page.

- [x] **recap.html links everything; every link resolves.**
  Programmatically checked after the final edit.

- [x] **Nothing is a placeholder pretending to be finished work.**
  The placeholders that exist are labeled as exactly that, deliberately: six [FOUNDER TO FILL] slots (name, background, commitment, contact, two reviewer roles) where inventing facts would have violated the truth policy.

## Failures and limitations kept, with reasons

1. **The video voiceover is macOS text-to-speech (Samantha).** The red team's user persona is right that TTS narration reads poorly in-feed. No human voice was available to this run and hiring one would violate the no-spend guardrail. The video is labeled animatic-grade; the human re-record is the first item on the [pre-publication checklist](06-redteam/pre-publication-checklist.md), and the build is one-command reproducible for exactly that swap.
2. **"Under 100 milliseconds" is not yet device-benchmarked.** It is the PRD's tested engine requirement, but no on-device benchmark record exists. The claim stays (it is the product's own spec, honestly framed), and the benchmark record is a blocking pre-publication item; if the slowest supported iPhone misses it, the number changes everywhere.
3. **Reddit self-promotion rules could not be read** (blocked during research). The channel plan and social kit refuse to treat those drafts as postable until the founder reads the rules manually.
4. **The landing page has no call to action.** Deliberate: there is no waitlist, handle, or listing to point to, and fabricating one would be worse. Blocking checklist item before the site ever goes live.
5. **Two session-limit outages during the run** forced a rebuilt research pass (13 of 14 files survived from the first run; the Sweat teardown was redone inline) and a delayed red team. No quality shortcut was taken as a result - the delays are visible in the decisions log timeline, not in the deliverables.

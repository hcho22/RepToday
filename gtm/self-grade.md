# Self-Grade Against the v2 Master Prompt (§11)

Graded 2026-08-02, after the v2 red team pass and packaging.
Supersedes the v1 self-grade of 2026-07-15 (frozen in git history).
Honest, including what was not fixed and why.

- [x] **No spend. No publication. Nothing live. No ad account touched.**
  Everything is local files; the only tools were already-local (Chrome, ffmpeg, macOS say, Python stdlib) plus read-only web fetches.
  The marketing-agent extra's publish adapter refuses by design (`NotImplementedError`) and its scoreboard shows honest nulls.

- [x] **Every factual claim has a fetched URL; sources.md complete; zero dead links.**
  210 catalogued entries (139 v1 + 71 v2, cross-run dedupe caveat stated in the file).
  The full v1 catalog was re-link-checked this run: 133 unique URLs, all live or correctly cited as 404-evidence (three 403/406s were curl bot-blocks, verified live by proper fetches).
  v2 URLs carry their 2026-08-01 fetch timestamps as recorded by the researchers.

- [x] **Zero fabricated stats, users, quotes, testimonials, engagement, or social proof - including mockups and social drafts.**
  The red team caught and killed the closest calls: the day-2 draft's "months of research" and "hundreds of reviews" (replaced with the real mined-source count, 24), an unsourced on-screen review date, and a false data-practices line on the site.
  App Store screenshot 04's line was aligned to the exact shipped build copy and documented as verified product UI.

- [x] **Nothing from the provided transcript is cited as fact anywhere.**
  The transcript was not even on disk (D-103); every method claim it inspired was independently re-verified from primary sources (Meta/TikTok/Google/Apple docs) and only those are cited.

- [x] **Every guess labeled [ASSUMPTION] with reasoning.**
  Carried v1 discipline forward; new v2 instances (200-impression floor, K9 direction-not-level, platform time-to-signal ordering, 90-day signal ranges) are labeled at the point of use.

- [x] **No health claims. No XP/levels/badges/streak language. No bro-fitness register.**
  Swept programmatically at close: the only em dash in live docs is inside a verbatim fetched competitor quote, and every "grind"/"beast mode"/"no excuses" hit names the banned register as banned.
  The lawyer persona read every claim including social drafts; mobility copy states mechanics, never relief-from-symptoms.

- [x] **Naming verdict carries the clearance caveat.**
  "Trademark + App Store clearance UNVERIFIED - founder's next action" appears in the naming decision, recap banner, README, site footers, teaser, brand guidelines, and (new this run) the screenshots README.

- [x] **Nothing contradicts the PRD.**
  On-device offline <100ms generation (spec, benchmark pending - stated as such everywhere including the teaser after a red-team fix), ready-on-open, zero-equipment, forgiving non-streak score, mobility co-primary, AI-tunes-policy-never-generates.
  The site FAQ's movement names were verified against the shipped `Exercises.json` after the lawyer flagged invented tier claims.

- [x] **The anti-discipline pitch was genuinely argued and scored, not strawmanned.**
  It won: rank 1 on all three rubrics, and discipline shipped as internal spine only.
  The scorecard with visible margins (including the 0.10 near-tie on differentiation) is published; the losing discipline-inversion pitch survives as an essay-layer sentence and one pre-registered PMF test angle.

- [x] **Site verified at both widths; screenshots in package; pain state named explicitly.**
  Both hero variants captured at 390x844 and 1440x900, viewed; one fold defect (variant A's Start button cut) found and fixed during the gate.
  The pain vocabulary ("no quiz, no picking, no catalog scroll", paywall rage, streak-shame) is in the hero and a dedicated sourced-quotes section.

- [x] **Video: ffprobe output + frame strip in package; script passes voice rules.**
  Rebuilt this run (killed listing suffix on the end card, Hero A wording); 52.4s, 1920x1080, AAC audio verified; frames at 0/25/50/75/100% plus the end card actually viewed and described in the gate report.

- [x] **Brand guidelines passed the fresh-agent test; the test artifact ships.**
  Round 1 failed honestly (canvas clipping) and closed four guideline gaps; a second blind agent then passed, orchestrator-verified.
  Both rounds and both artifacts ship in `02-brand/`.

- [x] **PMF kit: >=15 distinct angles, isolated-variable A/B pairs, pre-registered signals, honest sample-size limits.**
  16 angles across all required lanes, 6 hook-only pairs, and - after the investor persona's attack - every signal restricted to what is actually measurable at zero followers, with waitlist-dependent signals explicitly gated on the waitlist existing.

- [x] **Channel plan commits and answers paid-vs-organic with citations.**
  Committed verdict: zero paid spend pre-launch; organic short-form + first-party waitlist is the first-signal engine (install ads are structurally unavailable with no listing; SKAN/AAK aggregation and learning-phase economics starve small budgets of signal).
  Both rankings ship with per-channel kill criteria; the $500 answer is "mostly hold it".

- [x] **Red team ran; something changed materially; surviving objections visible.**
  58 findings, 26 MUST-FIX applied; the largest change was structural: one pre-registered K0 escalation ladder (day-14 / week-8 / week-16) now stated identically in the thesis, channel plan, and results guide, replacing three divergent verdicts.
  16 surviving objections ship in the dossier; the strongest (competitor's copyable-at-the-visible-layer attack) sits beside the thesis summary in the recap.

- [x] **recap.html links everything; every link resolves.**
  126 relative targets programmatically verified on disk.
  Responsiveness at 390px was verified in a real browser viewport (no horizontal overflow) after diagnosing a headless-capture artifact; details in the execution record.

- [x] **Nothing is a placeholder pretending to be finished work.**
  Deliberate, labeled exceptions: six [FOUNDER TO FILL] slots in the teaser (inventing them would violate the truth policy), and the marketing-agent's vision-QA layer, described in the build spec and explicitly marked not yet built.

## Failures and limitations kept, with reasons

1. **The video voiceover is still macOS TTS (Samantha), animatic-grade.** No human voice is available without spending; the human re-record remains the first pre-publication checklist item and the build is one-command reproducible for the swap.
2. **"Under 100 milliseconds" remains device-unbenchmarked.** It is the PRD's tested engine spec, framed as such everywhere (teaser included, after a red-team fix); the real-device benchmark is a blocking pre-publication gate.
3. **The waitlist does not exist yet.** The site deliberately has no CTA; K0's waitlist-dependent signals are gated on "pre-publication action #1"; nothing fabricates a capture destination.
4. **Reddit and YouTube comment mining stayed partially blocked**, so the pain corpus over-weights App Store reviews and Hacker News; stated in the research file's method notes, and the streak-grief evidence is honestly flagged as partly Duolingo-sourced.
5. **Word of mouth, the thesis's load-bearing growth mechanism, is unmeasurable pre-launch.** Now stated as such (K9 measures it post-launch, direction-not-level); it ships as a surviving objection rather than dressed as analysis.
6. **Two session interruptions (limit reset, auth expiry) hit mid-run** and were recovered via workflow resume; disclosed in the execution record; no deliverable shortcuts resulted.

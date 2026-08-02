# Decisions Log

Every autonomous decision made during the GTM runs, per the master prompt's §2.6.
Format: decision, alternative rejected, and why.
Entries D-001 through D-010 are the v1 run (2026-07-15, `gtm-master-prompt.md`).
Entries D-101 onward are the v2 update run (2026-08-01, `gtm-master-prompt-v2.md`).

## D-101 - v2 is an update run: v1 assets carry forward unless a v2 delta invalidates them [DECIDED BY AGENT]

The v2 prompt was issued as "update gtm ... using that latest prompt" against a repo already carrying the completed, red-teamed v1 package.
Decision: treat v2 as an update, not a from-scratch rebuild.
v1 research files (competitor teardowns, review mining, economics, ASO, creators, name collisions; all URLs fetched 2026-07-15) carry forward as-is; new research runs only where v2 introduces a requirement v1 never covered (iOS-attribution state for the paid-vs-organic verdict, Meta Ad Library sweep, frequency-ranked pain mining for angle seeds, platform-selection evidence, creative-carries-targeting primary sources).
Deliverables rebuilt outright: positioning tournament (v2's discipline-spine brief changes the question), channel plan (creative-carries-targeting doctrine plus $0/$500 dual ranking), landing page heroes (two variants now required), plus the net-new PMF kit, event schema, and marketing-agent build spec.
**Rejected alternative:** re-running all research from scratch - it would spend most of the run re-fetching facts that have not changed in 17 days and starve the net-new v2 deliverables.

## D-102 - Directory restructure to the v2 layout via `git mv` [DECIDED BY AGENT]

`05-thesis` → `07-thesis`, `06-redteam` → `08-redteam`, `07-extras` → `09-extras`; new `05-social-pmf/` and `06-channels/`.
The v1 channel plan moved to `06-channels/channel-plan-v1.md` and is kept as the superseded predecessor for diffability.
**Rejected alternative:** keeping the v1 layout and bolting new folders on the end - recap.html must match the v2 prompt's published output structure.

## D-103 - The Cody Schneider transcript is not on disk; §5.1/5.2 of the v2 prompt stand in as the method summary [DECIDED BY AGENT]

The v2 prompt says a marketing-agent transcript was "given", but no transcript file exists anywhere in the repo or the founder's projects directory (searched 2026-08-01).
Since §5.3 already forbids citing the transcript as fact, the loss is method-only, and §5.1/5.2 of the prompt itself enumerate the method points that transfer.
Decision: proceed from §5.1/5.2, re-verify independently any claim that matters (the creative-carries-targeting mechanism, the iOS attribution state) with primary sources, and cite only those.
**Rejected alternative:** halting to ask for the transcript - guardrail §2.6 forbids halting, and no deliverable may cite the transcript anyway.

## D-104 - v2 chosen extras: marketing-agent build spec, App Store screenshot set (carried), investor teaser (carried); invented deliverable stays the review-response playbook [DECIDED BY AGENT]

Chosen by the prompt's rule (which makes the company feel most real to a stranger), max three:
1. The marketing-agent build spec is new in v2 and is the prompt's own headline addition - the system that operates the creative loop the day budget exists, built and dry-run verified but never run against an account.
2. The App Store product-page screenshot set carries from v1 (D-007's reasoning stands: the most reality-conferring asset an unshipped iOS app can have); its copy gets re-checked against the v2 positioning verdict.
3. The one-page investor teaser carries from v1 and gets updated to the v2 thesis and positioning.
The v1 social-launch-kit is retired as an extra because the §8 social PMF test kit supersedes it as a required deliverable; its still-valid drafts are folded into the PMF kit rather than shipped twice.
The invented deliverable remains the App Store review-response playbook (used weekly post-launch; still nobody would ask for it pre-launch).
**Rejected alternatives:** pitch deck (thesis + teaser already cover the investor story), product walkthrough video (a second video would be rushed), onboarding email sequence (the product has no accounts or email capture; the artifact would be fiction).

## D-105 - v2 positioning: pitch-2 (anti-discipline, "already ready") wins; discipline becomes internal spine only [DECIDED BY AGENT]

The v2 tournament ran the discipline brief honestly: pitch-2 argued discipline is the wrong surface word and took rank 1 on all three rubrics (scorecard in `02-brand/naming-decision.md`).
All three judges converged independently on "internal spine, never the surface lead word".
Hero A is pitch-2's hero; Hero B is pitch-3's forgiveness hero with its headline rebuilt (word-level collision with a live Jillian Michaels ad) and two lines killed by the defensibility judge (an unenforceable experience guarantee and a false data-practices claim).
Grafts: pitch-1's inversion survives at essay length plus one PMF test angle; pitch-4 survives as one mechanics-only contrarian PMF angle.
**Rejected alternative:** protecting the discipline surface lead because the v2 brief proposed it - the brief itself ordered the honest outcome to ship.

## D-106 - Listing name becomes plain "Rep Today"; the "Rest Tomorrow" suffix is killed [DECIDED BY AGENT]

All four pitchers and all three judges independently flagged the suffix as grind-register under hostile paraphrase and counter to the forgiveness pillar.
The subtitle keeps the mechanic wedge ("Opens to a ready workout", D-005/D-009 carried).
**Rejected alternatives:** "Rep Today: Showing Up Counts" (emotional-contract register, scored below mechanic register) and a keyword suffix (D-005's reasoning stands).
Consequence: every v2 asset that carried the old listing name (site footer, video end card, App Store screenshot set, teaser) must be checked and updated this run.

## D-107 - K0 measures only zero-follower-measurable signals, on one pre-registered escalation ladder [DECIDED BY AGENT]

The red-team investor and competitor personas independently showed K0's kill line depended on waitlist link-taps the package's own measurement-honesty section declares unmeasurable pre-launch, and that the week-8 no-signal observation had three divergent verdicts across the thesis, channel plan, and results guide.
Resolution applied everywhere identically: K0 reads only bank-relative saves per 1k impressions, watch-through, and comment sentiment (200-impression floor, with a named "K0 under-sampled" state); waitlist-dependent signals activate only once the waitlist exists (pre-publication action #1); the single ladder is day-14 midpoint (kill losers, rebuild the matrix once) -> week 8 no angle clears its floor (bet (c) revised, one listening-informed rebuild) -> week 16 still nothing (K0 trips, bet (c) failed, walk-away observation).
A new K9 makes word of mouth measurable post-launch (unattributed-install share plus organic search impressions, direction not level); pre-launch WOM is declared an unmeasured assumption and ships as a surviving objection.
**Rejected alternative:** keeping the richer signal set (profile visits, shares) and the softer week-8 wording - a kill criterion with unmeasurable inputs or a menu of escalation ladders is not pre-registered, which was the whole point.

## D-001 - Output location is `/Users/hcho/Developer/RepToday/gtm/` [DECIDED BY AGENT]

The session's configured working directory (`/Users/hcho/Developer/FitSnack`) no longer exists; the repo was renamed to `RepToday` on 2026-07-14.
The master prompt lives at `RepToday/gtm/gtm-master-prompt.md` and mandates "all output under /gtm/", so the package is built there.
**Rejected alternative:** recreating a `FitSnack` directory - it would resurrect a path the founder deliberately deleted.

## D-002 - "Rep Today" enters the naming tournament as the incumbent [DECIDED BY AGENT]

The master prompt's naming state (live candidates Cairn and Stack, current name FitSnack) predates a completed rebrand:
`prd-rebrand-fitsnack-to-rep-today_071426.md` (dated 2026-07-14, all acceptance criteria checked) renamed the app, repo, bundle id (`com.reptoday.app`), CloudKit container, and StoreKit ids to Rep Today, with the App Store listing name planned as "Rep Today, Rest Tomorrow".
The app is still pre-submission, so the name is technically still changeable - but the founder's revealed decision is Rep Today.
**Decision:** run the tournament honestly with Rep Today as the incumbent candidate alongside Cairn, Stack, and any new proposals; pitchers are told the incumbent exists and what switching costs (redoing a completed identifier migration before submission, which is free in money but not in effort).
**Rejected alternative:** ignoring the rebrand and treating FitSnack as current - that would market a name the founder has already abandoned and produce a package contradicting the repo it ships in.

## D-003 - Free local tooling only: Chrome headless for capture, ffmpeg for video, macOS `say` for voiceover [DECIDED BY AGENT]

Guardrail §2.1 forbids new spending. The machine already has ffmpeg/ffprobe, Google Chrome, and the built-in `say` TTS (Playwright was present but not resolvable as a module; Chrome's own `--headless --screenshot` works and was verified).
**Rejected alternative:** any hosted TTS/video service (would require new signups or spend).

## D-004 - Positioning: pitch-1 "Friction is the enemy" ships, with two grafts [DECIDED BY AGENT]

The tournament was unanimous (scorecard in `02-brand/naming-decision.md`): the friction angle won all three rubrics.
Grafted from runners-up per the judges' notes: pitch-2's forgiveness line as messaging pillar 4, pitch-4's "A floor, a wall, and five minutes" as the secondary line.
**Rejected alternatives:** identity-led (headline unprovable at first run, ambiguous to cold strangers), anti-fitness-app-led (contested ground, weakest claims hygiene), audience-led (best listing subtitle but a "5-Min" name that narrows a 5-60 minute product).

## D-005 - App Store subtitle: "Opens to a ready workout" over the ASO researcher's "No Equipment Micro Workouts" [DECIDED BY AGENT]

Both are 30-char-legal. The wedge subtitle is a claim no researched competitor can copy truthfully and matches the hero promise the first app-open immediately proves; the keyword subtitle optimizes an [ASSUMPTION]-grade volume guess with no tooling behind it.
The keyword set (bodyweight, micro, no equipment, mobility) moves to the 100-char keyword field per the ASO file's own recommendation.
**Rejected alternative:** the keyword-first subtitle; revisit with real ASO tooling post-launch.

## D-007 - Extras: App Store screenshot set, investor teaser, first-week social drafts; invented deliverable: App Store review-response playbook [DECIDED BY AGENT]

Chosen by the master prompt's rule: which makes this company feel most real to a stranger.
An App Store product-page screenshot set is the single most reality-conferring asset an unshipped iOS app can have, and doubles as the ad creative for the expected #1 channel (App Store search).
A one-page investor teaser makes the thesis consumable by a cold investor.
First-week social post drafts make the launch plan concrete.
The invented deliverable is a review-response playbook: pre-written, honest founder responses to the most likely negative App Store reviews, derived from the actual complaint themes mined in research - preparation nobody asks for pre-launch.
**Dropped:** pitch deck (the thesis + teaser cover the investor story without padding), product walkthrough video (a second video would be rushed, violating "three polished beats six rushed"), onboarding email sequence (the product deliberately has no accounts or email capture, so the artifact would be fiction).
**Rejected invented-deliverable alternative:** a pre-written shutdown memo honoring the kill criteria - striking but performative; the playbook is used weekly post-launch.

## D-008 - Video scene transitions changed from crossfade to dip-through-black at the gate [DECIDED BY AGENT]

The first render crossfaded text-centered scenes into each other, producing 0.8s of overlapping text (visible in the original 50% gate frame).
Scene-to-scene transitions became `xfade=fadeblack`; intra-scene keyframe reveals keep plain fades; the video was re-rendered and re-gated.
**Rejected alternative:** shipping the crossfade version and calling the overlap "expected mid-transition blend" - it read as text soup in stills and in motion.

## D-009 - Post-red-team: the wedge subtitle stays; the keyword field was amended instead [DECIDED BY AGENT]

The competitor red team re-demanded the keyword subtitle ("No Equipment Micro Workouts") over D-005's wedge subtitle ("Opens to a ready workout").
The demand was rejected a second time for D-005's reasons, but its substance was honored: the App Store keyword field was amended to carry `micro` and `equipment` (dropping `travel` and `men`), so the keyword coverage exists without spending the subtitle on an unmeasured-volume term.
The amended 99/100-char field ships in `05-thesis/channel-plan.md`.
**Rejected alternative:** reversing D-005 - it would optimize copy against a search volume nobody has measured, at the cost of the one subtitle claim no competitor can copy truthfully.

## D-010 - Red team dispositions: 55 must-fixes applied or deferred, none silently dropped [DECIDED BY AGENT]

The five-persona red team produced 55 must-fix objections; all were dispositioned (fixed / resolved-by-fact-check / deferred-with-reason) and the 30 surviving objections ship verbatim in `06-redteam/dossier.md`.
Notable calls: the video's end-card legal line was replaced with a simulated-screens disclosure (satisfying the lawyer) rather than the trademark caveat (which the user persona correctly called doubt-planting in a consumer video - the trademark caveat lives in every written asset); the VO stays TTS under the no-spend guardrail, labeled animatic-grade, with a human re-record as the first pre-publication checklist item; the landing page deliberately keeps zero calls to action rather than fabricating a follow destination that does not exist.
**Rejected alternative:** treating any red-team demand as optional without recording why.

## D-006 - Names "9pm Priya" and all persona details are marketing constructs [DECIDED BY AGENT]

The product has zero users; no interview data exists.
Persona details are labeled [ASSUMPTION] wherever they appear and are inferred from the PRD's own target ("a tired parent at 9pm") plus cited third-party demand evidence.
**Rejected alternative:** presenting the persona as researched fact (truth-policy violation).

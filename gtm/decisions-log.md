# Decisions Log

Every autonomous decision made during the GTM run, per the master prompt's §2.6.
Format: decision, alternative rejected, and why.

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

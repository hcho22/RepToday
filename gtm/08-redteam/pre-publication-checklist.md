# Pre-Publication Checklist

Everything the red team correctly identified as unverifiable or unfinishable from this environment.
Nothing in the package may be published before its blocking items clear.
Items marked (blocking: X) block only that asset.

## Legal / naming

- [ ] **USPTO trademark search for "Rep Today"** (ideally with counsel), and App Store Connect name reservation for "Rep Today, Rest Tomorrow". (blocking: everything public)
- [ ] Decide on the reptoday.com domain ($3,895 buy-now at HugeDomains as fetched 2026-07-15) or commit to reptoday.app; register before any asset carrying a URL ships.
- [ ] **Author the privacy policy** and host it; link it from the site footer and FAQ, and align App Store privacy nutrition labels with the on-device / optional-iCloud / HealthKit-opt-in story. The app already links to it from a single constant (`LegalLinks.privacyPolicy`) that still points at an `example.com` placeholder, so hosting the document and setting that one value are the same task. **As of US-T06 this item's reach and severity both grew, though not its status:** the link is no longer only on the paywall behind a premium entry point - it is on the *first* onboarding screen every new user sees and in Settings, sitting directly beside the anonymous-usage-data consent disclosure, which makes it the document that justifies the collection rather than a footnote on a purchase screen. A dead link there is materially worse than a dead link on a paywall. Still blocking for submission, as it always was. (blocking: site, submission)
- [ ] Account deletion path: because optional Sign in with Apple exists, App Store Guideline 5.1.1(v) account-deletion requirements attach - verify the build satisfies them before submission.

## Substantiation

- [ ] **Device benchmark record for the "under 100 milliseconds" claim**: measure cold and warm session generation on real hardware including the slowest supported iPhone (iPhone XS on iOS 17), record device list, percentiles (p95), method, and date; check the record into `01-research/` as the substantiation file. If the slowest device misses 100ms, change the number in every asset. (blocking: site, video, screenshots, social, investor teaser)
- [ ] Confirm final App Store Connect pricing, then regenerate App Store screenshot 05 (it states planned prices) and the site pricing section.

## Assets

- [ ] **Re-record the video voiceover with a human voice** (the founder's own is fine). The current VO is macOS `say` Samantha - acceptable as an animatic, but the red team's cynical-user persona is right that TTS narration reads as AI-slop in-feed. The build is reproducible: replace the `say` lines in `04-video/build/build.sh` with recorded aiff files and re-run. (blocking: video publication)
- [ ] **Capture the real App Store submission screenshots from the built app** on-device and diff them screen by screen against the marketing comps in `07-extras/app-store-screenshots/` (App Store Guideline 2.3.3: screenshots must show the app in use). The comps are design references, not submission assets.
- [ ] Verify every behavioral claim in the site/video/screenshots against the actual approved binary before launch day (the package was written against the PRD and test suite, pre-submission).
- [ ] **Give the landing page exactly one low-pressure action** (follow link, notify email, or App Store pre-order) once a real handle or store listing exists; today the page is a deliberate dead end and the cynical-user red team is right that an interested reader has no way back. (blocking: site publication)
- [ ] Consider replacing or augmenting App Store screenshot 4 with the return-after-a-gap screen (celebrated, easy comeback session) - it is implemented behavior and the strongest emotional differentiator; capture it from the build when the real submission set is made.

## Channels

- [ ] **Manually read the self-promotion rules** of r/bodyweightfitness and r/fitness30plus (unfetchable during research) before posting anything; adjust or drop the Reddit drafts accordingly.
- [ ] Verify X/Instagram handle availability for @reptoday (login walls blocked checks).

## Measurement (from the fixed kill criteria)

- [ ] Instrument the funnel before TestFlight: onboarding -> first session, D7/D30 cohorts, weekly active exercisers, trial starts, paid conversions.
- [ ] Pre-register the K8 wedge-comprehension rubric (written coding criteria, 25+ observed first runs, non-founder coding) before the first cohort, per the skeptic's fix.

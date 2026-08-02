# Red Team: App Store Reviewer + FTC-Minded Lawyer

Persona: an App Store reviewer and an FTC-minded lawyer reading every public-facing claim line by line.
Scope: `03-site/index.html`, `04-video/script.md`, `07-extras/app-store-screenshots/` (README and src), `07-extras/social-launch-kit.md`, `07-extras/investor-teaser.html`, `02-brand/brand-guidelines.md`.
Ground truth: `01-research/product-facts-brief.md` and the sourced research files in `01-research/`.
Findings are ranked by severity.
MUST-FIX items demand a concrete change.
SURVIVING OBJECTIONS are weaknesses no rewrite can remove; they ship in the package as-is.

---

## MUST-FIX

### 1. "Trademark and App Store name clearance pending" is a false statement of legal process (HIGH)

Targets: `03-site/index.html` footer ("Pre-launch. Trademark and App Store name clearance pending."), `04-video/script.md` Scene 8 ("the clearance line 'Trademark and App Store name clearance pending.'"), `07-extras/investor-teaser.html` footer (same line), `02-brand/brand-guidelines.md` section 2 (which mandates this exact line), `07-extras/social-launch-kit.md` checklist ("trademark clearance is pending and is never claimed").
"Pending" is a term of art.
"Patent pending" and "trademark pending" mean an application has been filed and is awaiting examination.
Ground truth (`01-research/name-collisions.md`): "No USPTO (or any trademark registry) search was performed in this run", and `product-facts-brief.md`: "no App Store Connect record."
Nothing has been filed, searched, or reserved.
Nothing is pending.
Telling an investor a clearance process is "pending" when it has not begun is exactly the kind of misrepresentation that poisons a diligence file, and the social kit's own checklist contradicts itself: writing "pending" IS claiming a pending process.
Demand: replace the line everywhere, including the canonical form in brand-guidelines.md section 2, with exact wording that admits no process exists.
Proposed wording: "Pre-launch. 'Rep Today' has not been trademark-searched or registered, and the App Store name has not been reserved."
If that is too long for the video end card, use: "Name not yet trademark-searched or registered."

### 2. The screenshot set is positioned as App Store submission assets while being hand-built HTML mocks (HIGH)

Target: `07-extras/app-store-screenshots/README.md`.
The README opens: "Five screenshots for the 6.7-inch iPhone App Store slot, 1290x2796 PNG each" and asserts "Everything shown in the UI mocks is implemented product behavior."
These PNGs are rendered from hand-written HTML/CSS in `src/`, not captured from the app.
App Store Review Guideline 2.3.3 requires screenshots to show the app in use, and 2.3 generally treats metadata that misrepresents the app as grounds for rejection.
A CSS approximation asserted to match "implemented product behavior" is an unverified fidelity claim: nobody has diffed these mocks against the running app, and details like the variety line, block layouts, and the "you showed up. That's the whole game." string may not exist pixel-for-pixel in the build.
Demand: add a prominent warning block at the top of the README stating that this set is a pre-release design comp for marketing review only, that the actual App Store Connect submission set must be captured from the built app on device or simulator, and that each mock must be diffed against the real Ready Screen, session player, progress view, and plan screen before any upload.
Also delete or soften "Everything shown in the UI mocks is implemented product behavior" unless someone has verified it screen by screen against the build.

### 3. "AI Programmer" on the landing page without the MVP-heuristics disclosure is AI-washing (HIGH)

Target: `03-site/index.html`, mechanism section, card 2: "Between sessions, an AI Programmer adjusts your Session Policy" and the section intro "including what the AI does and does not do".
Also `07-extras/social-launch-kit.md` X post 4: "The AI never generates a workout. It tunes a policy - progression rate, pillar weighting, variety - asynchronously."
Ground truth (`product-facts-brief.md`): "At MVP the Programmer is deterministic on-device heuristics (option C) with exactly one optional LLM call."
The FTC's 2024 Operation AI Comply actions targeted precisely this: describing deterministic software as "AI" to consumers.
The HN draft and the investor teaser both disclose the heuristics honestly; the landing page and X post 4, the two widest-reach consumer assets, do not.
A page that brags "here is exactly how that works, including what the AI does and does not do" and then omits that the "AI" is currently a rule-based heuristic is not telling the consumer exactly how it works.
Demand: add one sentence to the site's card 2 and to X post 4's thread opener or its mandatory first reply: "At launch the Programmer is deterministic on-device logic; there is exactly one optional AI-generated line of text in the app, with an offline fallback."
Alternatively, drop the word "AI" from consumer copy entirely until the LLM-backed Programmer ships.

### 4. "Built for same-day relief" is an implied therapeutic claim (HIGH)

Target: `03-site/index.html`, library section, Mobility card: "Mobility work is programmed for how a desk day actually feels, built for same-day relief."
Relief is a symptom word.
"Same-day relief" of how a desk day feels is an implied claim that the app reduces pain or physical discomfort within a day, which requires competent and reliable scientific evidence under FTC health-claim substantiation standards.
The package's own rules ban this: `product-facts-brief.md` says "No health/medical claims permitted: no calorie/weight-loss/pain-cure/body-composition promises", and brand-guidelines.md section 7 rule 7 repeats it.
"Same-day relief" appears in the internal brief as a design intent, but printing it on a public page converts it into an outcome promise the founder cannot substantiate with zero users.
Demand: rewrite the card without the word "relief" or any same-day outcome, e.g. "Mobility work is programmed for how a desk day actually feels, and it earns full space in the session."

### 5. FAQ claims a mid-session movement swap that the product-facts brief does not contain (HIGH)

Target: `03-site/index.html`, FAQ "Can I build my own workout?": "You can change the duration in one tap and swap a movement mid-session."
`product-facts-brief.md` describes the duration chip, the engine, the pillars, and the score.
It nowhere mentions a mid-session movement swap.
Under this package's own rules, claims beyond the brief are errors, and if the shipped app lacks the feature this becomes misrepresented functionality in public marketing, the exact thing Guideline 2.3 punishes when it migrates into metadata.
Demand: verify against the build that mid-session swap exists in the MVP; if yes, add it to the product-facts brief with a source; if no, cut the clause.

### 6. "Nothing you can do in the app waits on a network" is factually false (MEDIUM)

Target: `03-site/index.html`, FAQ "Does it need internet?": "Nothing you can do in the app waits on a network."
The app sells subscriptions via StoreKit 2 and syncs via CloudKit (`product-facts-brief.md`).
Purchasing Premium waits on a network.
Restoring purchases waits on a network.
iCloud sync waits on a network.
An absolute negative that is falsifiable by the app's own paywall is a credibility gift to any skeptical HN commenter and a literal-falsity problem for a deceptive-practices analysis.
Demand: scope the claim to what is true: "Nothing between opening the app and starting a workout waits on a network."

### 7. The site captions a CSS mock as "product UI" and the video shows a fake screen with no simulation disclosure (MEDIUM)

Targets: `03-site/index.html`, phone caption: "Ready Screen (product UI, pre-release)"; `04-video/script.md` Scene 3: "faithful Ready Screen phone mock".
The site's phone is hand-written HTML in the page itself, not product UI, so the caption is literally false as written.
The video shows the same style of mock for 10 seconds as product proof with no disclosure anywhere in its 52.4 seconds that the screen is simulated.
"Screen images simulated" is the standard ad disclosure for exactly this situation, and its absence invites a claim that the ad depicts a product state that does not exist.
Demand: change the site caption to "Ready Screen (pre-release mock of the product UI)" and add "Screen images simulated; app is pre-release." to the video's Scene 8 end card alongside the corrected name-clearance line.

### 8. "Under 100 milliseconds" has no substantiation artifact anywhere in the package (MEDIUM)

Targets: `03-site/index.html` meta description and subhead ("built on your phone in under 100 milliseconds"), `04-video/script.md` VO line 3, `07-extras/app-store-screenshots/src/02-duration-chips.html` footnote ("Rebuilt on your phone in under 100 ms"), `07-extras/social-launch-kit.md` bios and posts ("in under 100ms"), `07-extras/investor-teaser.html` ("generated in under 100 milliseconds").
The number originates in the PRD as a requirement and is restated in `product-facts-brief.md` as fact, but no asset in the package cites a measurement: no device, no percentile, no benchmark run.
An objective, specific performance claim requires substantiation at the time it is made, and the burden is on the advertiser.
Under 100ms on an iPhone 16 Simulator says nothing about an iPhone XS, the oldest hardware iOS 17 supports.
Demand: before any of these assets go public, produce a benchmark record (device list including the slowest supported iPhone, cold and warm generation times, p95 or worse, method, date) and check it into `01-research/` as the substantiation file; if the slowest supported device misses 100ms, the number changes everywhere.

### 9. Screenshot 5 shows a priced free trial with no auto-renewal disclosure and no "planned" qualifier (MEDIUM)

Target: `07-extras/app-store-screenshots/src/05-free-forever.html`: "$7.99 a month or $59.99 a year · 14-day free trial".
Two problems.
First, a "free trial" offer adjacent to a price with no disclosure that the trial converts to an auto-renewing subscription is the fact pattern of the FTC's negative-option enforcement; the material term (it auto-renews unless cancelled) must accompany the offer, and Apple's own subscription-metadata expectations point the same way.
Second, the site correctly labels these prices "planned and may change before launch", but the screenshot states them as live terms; if pricing shifts before submission this asset is stale and misleading on its face.
Demand: add "Auto-renews until cancelled" (or Apple-standard equivalent) beside the trial line in the mock, and add a note in the screenshots README that screenshot 5 must be regenerated against final App Store Connect pricing before submission.

### 10. "Free means the workouts. All of them. Forever." collides with a paywalled Strength Phase (MEDIUM)

Targets: `03-site/index.html` pricing headline plus Premium list item "The Strength Phase, earned through sustained consistency and cleared movement tiers"; same pairing in `07-extras/app-store-screenshots/src/05-free-forever.html`.
The Strength Phase changes what the user's sessions are (`product-facts-brief.md`: a two-phase journey where the Strength Phase is the earned second phase).
If the second phase of the training itself sits behind Premium, then a category of workouts, the Strength Phase kind, is gated, and "all of them" carries an undisclosed qualification.
A reasonable consumer reads "all of the workouts, forever" as covering the app's training content, not "all workouts except the earned progression tier's programming."
Demand: define the boundary in the copy itself, e.g. a plan-note line: "The Strength Phase changes how sessions are programmed; every session remains free to generate and start."
If that sentence cannot be written truthfully, the headline must lose "All of them."

### 11. "Is my data sold? No." is a public privacy commitment with no privacy policy behind it (LOW)

Target: `03-site/index.html`, FAQ "Is my data sold?": "No. Your history lives on your device ... There is nothing to sell."
A public "we never sell data" pledge is enforceable against the company as a deceptive practice if practices ever diverge, and Apple requires a privacy policy URL and accurate privacy nutrition labels at submission.
No privacy policy exists anywhere in this package.
Demand: write the privacy policy before the site goes live, link it from this FAQ answer and the footer, and make the nutrition labels match the "on-device, optional private iCloud, HealthKit only if you choose" story told here.

### 12. "No questions" is falsified by the app's own permission prompts (LOW)

Targets: `03-site/index.html` subhead and `02-brand/brand-guidelines.md` section 8 approved subhead: "No questions, no account, no internet needed."; `04-video/script.md` VO line 3: "No questions. No account. No internet needed."
The app writes to HealthKit "if you choose" (site FAQ), which means an iOS permission dialog, a question, and Sign in with Apple is offered, another question, even if both are optional and off the start path.
The claim is defensible as "no onboarding interview", but as written it is an absolute a pedantic reviewer can falsify on first run.
Demand: keep the line but add the scoping once per asset where space allows ("no quiz, no sign-up, nothing between open and Start"), and record in brand-guidelines.md section 8 that "no questions" means the open-to-start path, so future copy inherits the defense.

### 13. "Real mobility" and "the kind of moving you did when you were seven" flirt with restored-capability claims (LOW)

Target: `04-video/script.md` VO line 5: "Bodyweight strength, real mobility, and the kind of moving you did when you were seven."
"Real mobility" implies competitors' mobility is fake, an unsubstantiated comparative.
"The kind of moving you did when you were seven" implies the app returns an adult to childhood movement capability, an outcome no pre-launch app can substantiate.
Both are mild, and the second is clearly poetic, but this is the only health-adjacent line in a video that cannot be footnoted.
Demand: drop the word "real" ("bodyweight strength, mobility, and the kind of moving you did when you were seven"); the childhood line may stay as obvious figurative language once "real" stops sharpening the comparative frame around it.

---

## SURVIVING OBJECTIONS

These stand after every fix above and should be published with the package.

1. "Forever" is a promise no pre-revenue solo founder can guarantee: the free tier's perpetuity depends on the app existing, and if Rep Today shuts down, is sold, or pivots, every asset that said "Free means the workouts. All of them. Forever." becomes the record of a broken promise; softening it would gut the brand's central pledge, so the founder is choosing to carry this liability knowingly.
2. The entire public package markets, in the present tense, an app that has never been submitted to the App Store: every behavioral claim ("it opens to", "it never asks", "it rebuilds in under 100ms") is a claim about software zero consumers have run, and any drift between these assets and the binary Apple actually approves converts polished copy into documented misrepresentation retroactively.
3. The name is legally naked: no USPTO search has been performed, REP Fitness owns heavy "REP" mindshare in fitness commerce, reptoday.com belongs to a domain investor at $3,895 and could be bought tomorrow by anyone, including a competitor, and the "Rep" prefix is crowded with live fitness apps; the collision scan is a search-results sample, not clearance, and the package launches a brand on that sample.
4. "No account" as a marketing pillar does not remove account obligations: because Sign in with Apple exists, App Store Guideline 5.1.1(v)'s account-deletion requirement attaches to the app regardless of what the copy says, and the marketing's "nothing to sign up for" framing will make any future account-related friction, including the deletion flow Apple requires, read as a contradiction.
5. Even with a benchmark file behind it, "under 100 milliseconds" is an unverifiable-by-consumers precision claim that invites free challenges: a competitor's NAD referral or an FTC complaint costs the challenger nothing, and the defense burden (device matrices, percentiles, updated measurements every release) is carried forever by a one-person company for a number no tired parent at 9pm can perceive.

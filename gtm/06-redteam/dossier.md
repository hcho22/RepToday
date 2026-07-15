# Red Team Dossier

Five attackers ran against the finished package on 2026-07-15: an adversarial skeptic with the last word on every thesis claim, plus the four personas the master prompt demands.
They produced 55 must-fix objections and 30 surviving objections.
Every must-fix was dispositioned: fixed, resolved by fact-check, or deferred to the [pre-publication checklist](pre-publication-checklist.md) with the reason stated.
None were silently dropped.

The full attacks:

- [skeptic-thesis.md](skeptic-thesis.md) - the skeptic's claim-by-claim refutation pass
- [redteam-investor.md](redteam-investor.md) - the seed investor
- [redteam-competitor.md](redteam-competitor.md) - the competitor growth head
- [redteam-user.md](redteam-user.md) - the cynical target user
- [redteam-lawyer.md](redteam-lawyer.md) - the App Store reviewer / FTC lawyer
- [_findings.json](_findings.json) - every objection and demand, machine-readable

## What changed because of the red team (the gate requires this, and it is long)

**Thesis and economics (skeptic + investor):**
- K2/K3 retention kill thresholds were raised - the originals would have let an at-median product survive a thesis whose premise requires beating the median; an explicit "at-median at day 90 = the bet failed" rule was added.
- Every kill criterion gained minimum cohort sizes, pooled-cohort rules, and fixed week-8/week-12 evaluation dates; the skeptic was right that at forecast volumes the original review would have read noise as a verdict.
- K5's gameable three-way conjunction became a rolling 4-week average against a floor raised from 50 to 90 installs/week (the base case's own run rate).
- K8 (wedge comprehension, a walk-away criterion) was pre-registered: frozen rubric, 25+ observed first runs, numeric thresholds, non-founder coding.
- The "empty quadrant" heading was demoted to "no researched competitor combines..." with the uncomfortable sentence added that the corner may be empty because ungated free tiers monetize worse.
- "Adjacent scale proves the demand shape" became "suggests", with vendor self-reported labels and the confound named: both scale witnesses run on the exact mechanics Rep Today bans.
- The base case's launch-spike assumption (1,500 installs) contradicted the channel plan's own forecast (a few hundred); the thesis now uses ~600, and every downstream number was recomputed (base year-1 gross ~$4,500 -> ~$3,700).
- The revenue model's LTV-timing overstatement was added to its stated ignore list; the 2.1% conversion input was relabeled an at-benchmark scenario; the 14-day-trial benchmark sentence now admits the cited band excludes 14 days.
- Bet (c) no longer rests on the unmeasured "micro workout" ASO whitespace.
- The investor teaser gained a founder block, a raise trigger, an iOS-only argument, and a commitment/runway section (with honest [FOUNDER TO FILL] placeholders rather than invented facts).

**Legal and claims (lawyer):**
- "Trademark and App Store name clearance pending" was ruled FALSE - nothing is pending - and replaced everywhere with the canonical "has not been trademark-searched or registered" wording; the video end card now carries "Screen images simulated. App is pre-release." instead.
- The site's AI card was rewritten to disclose that the tuner at launch is deterministic on-device logic, with exactly one optional AI-generated line (offline fallback); the same disclosure now rides X post 4's mandatory first reply and the creator outreach email.
- "Same-day relief" (an implied therapeutic claim) was removed from the mobility copy.
- The screenshots README now states loudly that the set is a pre-release design comp, not submission assets (App Store Guideline 2.3.3), and screenshot 5 gained auto-renewal disclosure and a planned-pricing qualifier (regenerated and re-inspected).
- "Nothing you can do in the app waits on a network" was scoped to the open-to-start path; "no questions" got a scoping note in the brand guidelines.
- The video VO dropped a comparative ("real mobility" -> "mobility") and was re-rendered and re-gated.
- The in-session swap claim survived because it is true: the lawyer flagged it as beyond the product-facts brief, and the fact-check showed the brief was incomplete (PRD US-C08/US-K03) - the brief was fixed, not the site.

**Consumer credibility (user + competitor):**
- The free-tier promise moved into the hero viewport (it appeared five scroll-lengths down; "what's the catch" was answered too late).
- The hero mock's variety line was replaced with one the engine actually guarantees, and its block list now matches its labeled duration.
- The AI card lost its PRD vocabulary; the launch FAQ lost its vaporware pun; the self-referential honesty tics ("this page is the whole pitch", "I'll say plainly") were cut across the site and social kit.
- A new FAQ confronts the 42-movements question honestly.
- The Down Dog contrast in the positioning was corrected to what the research supports (configure-first and login-mandatory, not "interviews you").
- The channel plan's launch week gained brand-term monitoring, and the trademark search was upgraded to search-then-file as a blocking pre-launch item.

**Demands not applied, with reasons:**
- Re-recording the VO with a human voice: impossible under the no-spend guardrail (no human voice available to this run); it is the first item on the pre-publication checklist, and the current VO is labeled animatic-grade.
- Shipping the keyword subtitle instead of the wedge subtitle: rejected again, but the keyword field was amended to carry `micro` and `equipment`, and the trade-off is recorded in the decisions log.
- A landing-page email-capture/follow action: fabricating a destination that does not exist would be worse than a dead end; blocking checklist item instead.
- Replacing screenshot 4 with the return-after-a-gap screen: the emotional point is right, but that screen should be captured from the real build for the submission set; deferred with the checklist.

## The surviving objections

These are the objections no rewrite can fix.
They ship here, verbatim, because a reader deciding whether to believe this package deserves the strongest case against it.


### The adversarial skeptic (thesis claims)

> Nothing in this product is defensible. Every leg of the wedge, a ready session on open, a forgiving non-streak score, and an ungated free tier, is a UX or pricing choice with no data moat, no network effect, and no switching cost behind it; Seven or Bend could copy the entire stack in one release cycle the moment it shows signs of working. The quadrant is empty of competitors, but it is also empty of barriers, and a fully successful 90-day experiment proves a feature set, not a company.

> The demand evidence is anecdote-grade and the category has never validated the core bet. The load-bearing demand quote is one Hacker News commenter, the in-category friction quote is a single review from 2019, and the two scale witnesses (Seven's self-claimed 30M users, Bend's 15M) built that scale on the streak-and-achievement mechanics Rep Today bans. No gamification-free micro-workout app at scale exists anywhere in the research, so the anti-streak bet is validated by no one, including the apps cited as proof of demand.

> Every zero-budget channel reaches someone other than the customer. The ICP is a tired parent at 9pm; the channels are Hacker News (engineers, by the channel plan's own admission), an ASO term with unmeasured and probably negligible volume, fitness subreddits whose rules could not even be read during research, and creators with no incentive to promote a competitor. The plan contains no reliable path from any channel to the stated audience.

> At the install volumes this plan itself forecasts, the 90-day verdict will be statistical noise. Weekly cohorts of 35-100 users cannot distinguish the kill thresholds from the expected bands, where the margins are one to three users per cohort; the 'cheap, instrumented, self-terminating experiment' framing oversells what 90 days of underpowered data can decide.

> The most likely outcome is the one the package is not calibrated to detect: unremarkable survival. Median-ish retention, a few dozen payers, no kill criterion fired, no compounding, in a category where the top 10% of apps take 92.6% of revenue and median new-app revenue fell 22% year over year. The kill criteria catch catastrophe and the verdict celebrates success, but nothing forces a decision in the wide gray middle where solo apps actually go to linger.


### The skeptical seed investor

> No answer to the copy scenario exists: the teaser concedes 'not a moat... the quadrant is empty today', and if Seven (30M claimed users) or Down Dog defaults to a ready session, or Apple sherlocks the Ready Screen, the package can name no surviving asset - no network effect, no data moat, no brand, no distribution lock, and no speed advantage for one solo founder.

> The distribution story has no base rate: every install figure is an [ASSUMPTION], the only always-on channel rests on a keyword whose volume is admittedly unmeasured and likely near zero, and the plan's own per-channel realistic expectations sum closer to the pessimistic 2,000 installs than the base 6,000 - against a market the package itself documents as 92.6% concentrated with median new-app revenue falling 22%.

> The only spike channel acquires the wrong customer by the plan's own definition: Show HN traffic is 'skewed toward engineers rather than the 9pm-parent ICP', the plan pre-classifies half-rate-retention spikes as audience mismatch, and no listed channel plausibly reaches tired 9pm parents at volume.

> By its own numbers, total success in year 1 is still not a business: optimistic gross under $30K, base case 'roughly $375 a month', no year-2 model, and no argument anywhere that the prize for passing every kill criterion is large - the package proves the experiment is cheap and falsifiable, and its own phrase 'fundable as an experiment rather than dismissible as a hobby' concedes that today it is a well-instrumented hobby.

> The evidence base is mined App Store reviews and forum comments the thesis itself calls 'directional, not measured', with the streak-pain quotes mostly out-of-category and the demand anchor a single HN commenter; demand evidence is not demand proof, and the thesis admits 'the difference is the whole company'.

> Every mitigation still routes through one person's discipline: one founder is simultaneously developer, support desk, analyst, community member, video editor, and judge of his own kill criteria inside an 8-12 hour weekly GTM cap - this risk is structural and no rewrite removes it.


### The competitor's head of growth

> The hero claim is imitable in one sprint (cached pre-generation, quick-start setting, widget); only the free-forever/no-account business model is structurally safe, and a moat that narrow must carry the whole company.

> The paywall wedge does not bite the beloved incumbents: Rep Today's own research found Down Dog's US review set 'contained no pricing complaints; users treat the subscription as fair,' so the free pitch converts scam-paywall victims, a smaller pool than the positioning implies.

> ASO whitespace is a countdown, not a moat: 'micro workout' is empty because it is worthless, and the moment it shows volume any incumbent with five-digit ratings takes it with one subtitle edit against Rep Today's zero ratings.

> 42 movements will read as small next to Down Dog HIIT's marketed 1000+ exercises; repeat-fatigue one-star reviews are a predictable wave within weeks of daily use.

> 'Free means the workouts. All of them. Forever.' is an unverifiable promise from a zero-revenue solo developer, and 'free-forever apps flip the paywall or die' is a counter-message incumbents get for free.

> The channel plan's own numbers (single-digit daily ASO installs, one few-hundred-install HN spike of non-ICP engineers, tens per Reddit post) produce week-12 kill-criteria cohorts too small to be more than noise.

> Premium's day-one value is thin and mockable: $7.99/mo buys deeper analytics plus a Strength Phase gated by both payment and merit ('earned ... never self-selected') - 'they charge you for a feature they might not let you use.'

> The launch page has zero social proof: both evidence quotes are about other products and the captions admit 'we don't have any yet,' so the page argues from theory against incumbents holding hundreds of thousands of five-star ratings.

> The App Store name 'Rep Today, Rest Tomorrow' hands competitors a one-line joke - a consistency app whose title schedules tomorrow off - and no GTM copy can rewrite a locked name.


### The cynical target user

> The package never answers why I open the app on day 12: no streaks means nothing to lose, but with no reminder, hook, or social layer it also means nothing calls me back - the Product Hunt comment admits retention is 'a bet, not a proven result,' and I am the person the bet is about.

> Speed-to-start is not why I deleted four fitness apps; I quit in week three when life won, not at the login screen, and the package treats the first 100 milliseconds as the whole war.

> Everything here is a promise from an app with zero users, no date, and no way to try it; the evidence quotes are strangers on Hacker News describing an app they wished existed - market research standing where social proof should eventually go.

> The brand bans photography, so I never see a human move: 42 movement names stay abstract until install, and a novice with a bad back cannot judge fitness suitability from geometric shapes.

> 'Rep Today, Rest Tomorrow' (the planned App Store name, shown in the video end card) parses as 'never rest today' - a daily-obligation vibe that quietly contradicts the forgiveness pitch, and the listing name of record means the tension stays.

> My real 9pm failure mode is the kid-cries interruption at minute four, and nothing in any asset says whether a broken-off session counts as showing up; the facts brief covers a 5-minute session but not an abandoned one, so no copy can honestly promise anything here yet.


### The App Store reviewer / FTC-minded lawyer

> "Forever" is a promise no pre-revenue solo founder can guarantee: if Rep Today shuts down, is sold, or pivots, every asset that said "Free means the workouts. All of them. Forever." becomes the record of a broken promise; softening it would gut the brand's central pledge, so the founder carries this liability knowingly.

> The entire public package markets, in the present tense, an app that has never been submitted to the App Store: every behavioral claim is about software zero consumers have run, and any drift between these assets and the binary Apple approves converts polished copy into documented misrepresentation retroactively.

> The name is legally naked: no USPTO search has been performed, REP Fitness owns heavy "REP" mindshare, reptoday.com belongs to a domain investor at $3,895 and could be bought tomorrow by anyone including a competitor, and the collision scan is a search-results sample, not clearance.

> "No account" as a marketing pillar does not remove account obligations: because Sign in with Apple exists, Guideline 5.1.1(v)'s account-deletion requirement attaches regardless of the copy, and "nothing to sign up for" framing will make any account-related friction read as a contradiction.

> Even with a benchmark file behind it, "under 100 milliseconds" is an unverifiable-by-consumers precision claim that invites free challenges (NAD referral, FTC complaint), and the defense burden - device matrices, percentiles, re-measurement every release - is carried forever by a one-person company for a number no tired parent at 9pm can perceive.


## Verdict on the gate

The master prompt's gate: at least one thing in the package must have changed materially because of the red team, or the red team performed rather than ran.
The kill criteria were rewritten, the base-case economics were recomputed downward, a legal line that appeared in six assets was ruled false and replaced, the video was rebuilt, and the hero of the landing page changed.
The red team ran.

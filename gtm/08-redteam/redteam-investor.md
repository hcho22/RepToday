# Red Team - The Skeptical Seed Investor

Persona: a seed investor doing 30 minutes of diligence on the Rep Today GTM package.
Documents read: investment-thesis.md, investor-teaser.html, naming-decision.md, channel-plan.md, product-facts-brief.md, decisions-log.md, aso-landscape.md.
Posture: I am not here to be balanced.
The package is unusually candid about zero traction, and candor is not the same thing as an answer.
Findings are split into MUST-FIX defects (the package cannot ship with these) and SURVIVING OBJECTIONS (no rewrite fixes these; they ship visibly).

## MUST-FIX defects, ranked by severity

### MF-1 (high) - The investor teaser has no founder, no entity, and no contact

07-extras/investor-teaser.html calls itself a "watch-this-space teaser" and ends with "If the wedge survives its own kill criteria, the next document will contain data instead of claims."
There is no founder name, no one-line background, no legal entity, and no email anywhere in the document.
I cannot diligence a person who is not named, and I cannot watch a space I have no address for.
An anonymous teaser reads as a writing exercise, not an investment document.
Demand: add the founder's name, a one-line background, commitment status (full-time or nights-and-weekends), and a contact address to the teaser header or footer.

### MF-2 (high) - The "micro workout" whitespace bet has zero presence in the shipped metadata

The thesis's distribution bet (c) and the teaser both lean on "micro workout" as "near-empty whitespace."
But the title is "Rep Today, Rest Tomorrow" (no micro, no workout), decisions-log D-005 chose the subtitle "Opens to a ready workout" over the ASO researcher's "No Equipment Micro Workouts," and the 94-char keyword field quoted in channel-plan.md (`bodyweight,quick,daily,home,mobility,stretching,minute,hiit,exercise,routine,busy,travel,men,5`) contains neither "micro" nor "equipment."
D-005 asserts "The keyword set (bodyweight, micro, no equipment, mobility) moves to the 100-char keyword field," which the quoted field flatly does not do.
Worse, channel-plan.md calls the subtitle "the open decision" while decisions-log.md marks D-005 "[DECIDED BY AGENT]."
The package's number-one organic keyword appears nowhere in the metadata the package tells the founder to ship.
Demand: revise the keyword field to include the micro and equipment terms, and make channel-plan.md agree with decisions-log.md about whether the subtitle decision is open or decided.

### MF-3 (high) - "Money could then accelerate" contradicts the package's own math

investment-thesis.md section 7 says "there is something real here that money could then accelerate."
channel-plan.md says "paid acquisition is underwater before the first dollar is spent" ($50-$190 per payer against $35.64 year-1 LTV).
Every channel in the plan is explicitly founder-time-bound, and the thesis's own economics say installs cannot be bought at a profit.
So what, concretely, would a check accelerate: not ads, not distribution, and one founder cannot be parallelized by capital.
Demand: either name what capital would buy (Android build, a hire, creator budget, whatever the real answer is) or delete the accelerate clause and say plainly that this business, as modeled, cannot absorb money.

### MF-4 (high) - Solo-founder execution risk and runway are never addressed anywhere

The thesis's bet (c) rests on "one solo founder with zero ad budget," and the model "deliberately ignores... development opportunity cost."
channel-plan.md caps GTM at "8-12 founder-hours/week, capped so development and bug response stay primary."
No document says whether the founder is full-time, how many months this is sustainable at zero income, or what happens to support, fixes, and the weekly metrics ritual if the founder gets a job, a flu, or a second child.
A plan whose every channel, every kill-criterion measurement, and every fix iteration routes through one unnamed person's spare hours has a single point of failure the package pretends not to see.
Demand: add an explicit founder-commitment and sustainability statement (hours per week total, months of runway, what breaks first) to the thesis and a one-line version to the teaser.

### MF-5 (medium) - "No round is being raised" is a dodge until the raise trigger is stated

investor-teaser.html, "The ask": "No round is being raised in this document, and no check is being solicited."
Fine, but the document is titled "Investor teaser" and promises a "next document."
Pre-marketing a future raise while soliciting nothing lets the founder collect attention without ever being accountable for a use-of-funds story.
Candor would state the conditions: which kill-criteria outcomes open a round, at roughly what stage, to fund what.
Demand: add one sentence stating what would trigger a raise and what it would fund, or retitle the document as a build log and stop calling it an investor teaser.

### MF-6 (medium) - The naming "tournament" is AI agents grading AI agents, presented as validation

naming-decision.md: "A blind tournament: four independent pitch agents... Three judges with different published rubrics scored all four... The win was unanimous."
Every pitcher and every judge is a language-model agent spawned by the same package.
Unanimity among three scripted rubrics is not market evidence, and a cold reader is invited to mistake it for testing.
Zero humans have seen the name, the hero line, or the "Rest Tomorrow" pun the defensibility judge itself flagged as misreadable.
Demand: label the tournament explicitly as synthetic internal deliberation with zero human validation, in the document's first section, not the appendix.

### MF-7 (medium) - The kill criteria are self-graded, and the escape hatches are unbounded

investment-thesis.md section 5 is the package's centerpiece, and it is enforced by nobody.
The thresholds fire only "after two fix iterations" (K1) or "after at least one ASO metadata iteration and one launch post" (K5), and nothing bounds how long an iteration takes or who counts them.
The base rate of solo founders honoring their own written walk-away criteria is approximately zero, and the package knows enough about base rates to know that.
Demand: add an accountability mechanism - pre-commit to publishing the 90-day review publicly on a named date, or name a specific external person who receives the numbers and holds the walk-away call.

### MF-8 (medium) - iOS-only is asserted, never argued

The teaser descriptor says "for iOS," product-facts-brief.md says "No Android... at MVP," and channel-plan.md even rehearses answering "why not Android" on HN launch day.
No document in the package actually answers it.
The ICP is "a tired parent at 9pm," and most of the world's tired parents hold Android phones; iOS 17+ narrows the wedge further, and that narrowing appears nowhere in the market section.
Demand: one honest paragraph in the thesis stating why iOS-only (native stack, solo capacity, monetization skew), what fraction of the ICP it concedes, and under what condition Android happens.

### MF-9 (low) - Three different download-to-paid medians circulate without reconciliation

investment-thesis.md section 4 uses 2.1% (freemium day-35 median) as the base case, its own trial-funnel cross-check yields 2.6%, and channel-plan.md's paid-UA arithmetic uses "the 2.9% median download-to-paid at day 35" from a different RevenueCat page.
All three may be defensible individually, but a diligent reader meets three numbers for nearly the same metric across two documents and starts doubting every other figure.
Demand: one footnote reconciling the three (blended vs freemium vs funnel-implied) and a statement of which one the model stands on.

### MF-10 (low) - The bundle root advertises a domain someone else owns, and the fixable gap is left open

product-facts-brief.md: bundle root `com.reptoday.app` is locked while reptoday.com sits at HugeDomains for $3,895, and the package's advice is "Do not buy reptoday.com."
Fine, but the same research says reptoday.app returned NXDOMAIN, and the package treats that availability as a finding instead of an action.
Every week the .app stays unregistered is a week a squatter can close the brand's only cheap domain while the identifiers are already unchangeable.
Demand: register reptoday.app now (roughly $20) and record it in the decisions log; the do-not-buy advice should apply to the .com only.

## SURVIVING OBJECTIONS - publish these with the package

### SO-1 - There is no answer to the copy scenario, because there isn't one

The teaser says it itself: "This is a researched observation as of that date, not a moat. Parts of the stack can be copied; the claim is only that the quadrant is empty today."
Seven claims 30 million users and already owns the workout shape; making its home screen open to a ready session is a design change, not a technology.
Down Dog already generates sessions; defaulting the configuration is one release.
Apple can sherlock the Ready Screen into Fitness+ at a keynote.
The forgiveness ground is already contested by other builders, per the thesis's own HN evidence ("No streak anxiety. No guilt.").
Asked what survives 24 months of competent imitation, the package has no asset to point to: no network effect, no data moat, no brand, no distribution lock.
The honest answer is "nothing except execution speed and taste," and one solo founder has no speed advantage over Seven's team.

### SO-2 - The distribution story has no base rate, and its own numbers lean pessimistic

Every install figure in the package is an [ASSUMPTION]; the thesis concedes "No citable public benchmark for a solo pre-launch iOS app's organic installs was found."
The only always-on channel rests on a keyword whose volume is admitted to be unmeasured and "likely low... precisely because no successful app has trained users to search it."
Sum the plan's own realistic expectations - "single-digit to low-double-digit installs per day" from ASO, "a few hundred installs per successful post," "tens of installs per accepted post" on Reddit, "near-zero installs" from short-form - and you land nearer the pessimistic 2,000 than the base 6,000.
The package honestly cites the hostile market structure (92.6% of revenue to the top decile, median new-app revenue down 22%) and then asks you to believe an unmeasured keyword and one lucky launch post outrun it.

### SO-3 - The only spike channel acquires the wrong customer, by the plan's own definition

channel-plan.md admits the Show HN audience is "skewed toward engineers rather than the 9pm-parent ICP," and its own leading indicator says "a spike that retains at half the organic rate is audience mismatch, not success."
The thesis's K8 likewise treats acquiring the customizer segment as a channel failure.
So the plan's highest-volume moment is one it has pre-classified as probable mismatch, and no channel in the list plausibly reaches tired 9pm parents at volume: they are not on HN, not in r/bodyweightfitness, and not searching "micro workout."
The wedge was validated with quotes from engineers and the product is aimed at parents, and that seam runs through the whole package.

### SO-4 - By its own numbers, total success in year 1 is still not a business

The thesis says it plainly: optimistic year-1 gross is under $30K, the base case is "roughly $375 a month," and "this is not a year-1 income story under any honest input set."
There is no year-2 model, no sketch of what the business looks like if every kill criterion passes, and no order-of-magnitude path from 20,000 installs to anything an investor can price.
The package's sharpest self-description is "fundable as an experiment rather than dismissible as a hobby," which concedes that on the evidence presented it is a well-built hobby with excellent instrumentation.
The honest verdict is that the package proves the experiment is cheap and falsifiable; it never argues, anywhere, that the prize for passing is large.
Underwriting 90 days of data is only rational if someone can say what the data would be worth, and nobody in these documents does.

### SO-5 - The evidence base is mined reviews and forum comments, and the package admits it

The thesis's own caveats: App Store review pages "skew positive... the complaint themes above are directional, not measured," and the streak-pain quotes are "about Duolingo and habit apps, not fitness apps."
The demand-side anchor is a single HN commenter with ADHD asking for a decision-free app.
Zero humans have used the product; zero humans have even seen the positioning.
Demand evidence is not demand proof, and the thesis says so itself: "the difference is the whole company."

### SO-6 - Every mitigation in this package still routes through one person's discipline

Even after MF-4 and MF-7 are fixed on paper, the structural fact stands: one founder is simultaneously the developer, the support desk, the analyst, the community member in four subreddits, the video editor, and the judge of his own kill criteria, inside a self-imposed 8-12 hour weekly GTM cap.
The plan is honest about the hours; it cannot be honest about what it feels like in week nine when K2 is borderline and the fix backlog is full, because no document can be.
This risk is not a defect in the writing.
It is the deal.

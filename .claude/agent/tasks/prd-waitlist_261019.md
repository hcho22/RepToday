# PRD: Rep Today Waitlist (2026-10-19)

- Status: **Drafted 2026-10-19; implementation authorized 2026-10-19, built in four reviewed slices.**
  The captain approved the gr0wthlab Dispatch request for RepToday's Waitlist (item 20261016-reptoday-waitlist) on 2026-10-19 and asked for this PRD first.
  The request fixes the sign-up, the Source links, the web events, the privacy policy content, the anonymous view's format and the address boundary.
  This PRD carries all of it verbatim (Appendix A) and adds or drops no field, Source, event property or file field.
  The request leaves five choices to RepToday: storage (including whether Kit stays), hosting, how a link's Source reaches its sign-up, how and how often the view is produced, and whether sign-ups confirm their email.
  Each is Open Question 1-5 below, with the realistic options, a marked recommendation and the stories it gates.
  Open Questions 6-14 are further design choices this PRD found while grounding the request in current `main`.
  A story that depends on a question does not build that choice until the captain settles it; each story names the questions it waits for.
- Story prefix: `US-WL##` (Waitlist).
  A grep of every PRD, doc, source file and report found no existing `US-W` story id.
  `US-ME##` belongs to gr0wthlab's own PRD and is not used here.
- Related decisions: [ADR-0009](../../../docs/adr/0009-waitlist-anonymous-view-and-address-boundary.md) records the one architectural boundary the request fixes (addresses stay on the founder's side; the Marketing Engineer reads only the anonymous view).
  No ADR is written for any choice left to the captain in the Open Questions; ADR-0009 is amended once they are settled.
  Domain terms: `CONTEXT.md` -> "Waitlist" (Waitlist, Source, Fit, anonymous view, entry identifier).
- Amends, when US-WL05 lands: the funnel PRD's non-goal "No web-side events" (`.claude/agent/tasks/prd-funnel-instrumentation_260803.md`), which scoped web events out of that build only, and the matching "handled outside the app" notes in `convex/events.ts`, `convex/README.md` and `ios/RepToday/RepToday/Models/AnalyticsEvent.swift`.
- Read-only dependency: gr0wthlab's Waitlist view reader (`src/gr0wthlab/waitlist.py` in the gr0wthlab repository).
  This PRD's file contract was written against that code, not against prose; see "The gr0wthlab reader contract".
- Follow-up outside this PRD: one reviewed gr0wthlab change records the view's path and the go-live date (see Dependencies).

## Introduction / Overview

Rep Today is pre-launch, and gr0wthlab's PRD treats the Waitlist as the last open launch-readiness item before any public post.
Today the landing site collects an email address through a Kit embed shown four times (hero and closing band, on each of two served page variants).
It records nothing about where a person came from or how well they fit, it promises "one message", its privacy section says only that Kit stores the address, and nothing lets the Marketing Engineer count sign-ups without being able to read addresses.

This feature turns that form into the Waitlist the request describes.
A visitor arrives by one of four short links (`reptoday.app/tiktok`, `/youtube`, `/reddit`, `/network`) or by any other way.
They see one low-pressure call to action and three fields: email, one Fit question, and an unticked box asking for a beta invitation.
Their Source comes from the link, not from a question.
The site emits two anonymous web events, the privacy policy says plainly what is kept, why, for how long and how to be removed, and RepToday writes one anonymous view file on the founder's Mac that gr0wthlab reads read-only each week.
Addresses never leave the founder's side: no credential and no address export is ever placed in the gr0wthlab, Mandu or RepToday checkouts.

It is a **website and operator-tooling change**.
No iOS code, engine behavior, app telemetry event, Coach behavior or paywall changes.

## Goals

- One sign-up form, identical in every placement on both served pages, with exactly the three approved fields and the approved wording.
- A visit's Source is captured from the link (`tiktok`, `youtube`, `reddit`, `network`, else `unknown`), kept while the visitor looks around the site, and stored with the sign-up.
- `landing_page_view` and `waitlist_signup` are emitted with `referrer_source` (the visit's tag, or `none`) and nothing identifying.
- `reptoday.app/privacy` has a Waitlist section that states the five approved points in the policy's plain voice, published no later than the form.
- One anonymous view file, in exactly the approved shape, that gr0wthlab's reader accepts, that never holds an address or anything derived from one, and that sits outside every checkout and git work tree.
- Addresses are resolved only on the founder's side at send time; no email-service credential and no address export exists in any of the three checkouts.
- Removal deletes the sign-up and its answers within 7 days; retention ends 30 days after the launch email goes out.
- Every design choice the request leaves to RepToday is put to the captain with options and a recommendation before it is built.

## Request traceability

Each clause of the approved request, mapped to the stories and functional requirements that carry it.
The request itself is Appendix A, verbatim.
"OQ" is an Open Question below; "Dep." is the Dependencies section.

| # | Request clause | Stories | FRs |
| --- | --- | --- | --- |
| 1 | Built in RepToday through its normal reviewed path; the Marketing Engineer never changes RepToday | every story lands as a reviewed change; US-WL08 guards the checkouts | FR-38, FR-49 |
| 2 | Every quoted wording is for the captain's approval, and an approval note can change any of it | Appendix A (verbatim), Appendix B (new strings), OQ9 | FR-1, FR-5, FR-6, FR-7 |
| 3 | Exactly one low-pressure call to action, keeping the page's words "Join the waitlist" and "Add your email and we'll tell you the day it ships." | US-WL02, US-WL03 | FR-1 |
| 4 | The page asks for nothing else, no download, follow, or share | US-WL03 | FR-1 |
| 5 | Where the form appears more than once, it is the same form | US-WL02, US-WL03 | FR-2 |
| 6 | Three fields and no others | US-WL02 | FR-3 |
| 7 | Field 1: Email, required | US-WL02 | FR-4 |
| 8 | Field 2: the Fit question "Which sounds most like you?", no answer pre-selected, three answers with tags, an answer required to sign up | US-WL02, US-WL01 | FR-5 |
| 9 | Field 3: a box, unticked until ticked, "Invite me to the beta before launch" | US-WL02 | FR-6 |
| 10 | The promise becomes "one launch email, plus a beta invitation only if you ask for one" | US-WL03 | FR-7 |
| 11 | No "how did you hear about us" field | US-WL02 | FR-8 |
| 12 | One link per Source: `reptoday.app/tiktok`, `/youtube`, `/reddit`, `/network`; each opens the sign-up page; the word after the slash is the lowercase tag | US-WL04 | FR-10 |
| 13 | Each link is short enough to say aloud, type, or put in a profile | US-WL04 | FR-12 |
| 14 | A sign-up keeps the Source of the link its visitor arrived by, even after they look around the site | US-WL04 | FR-13 (OQ3) |
| 15 | Reached any other way, such as plain `reptoday.app`, is Source `unknown`; the links work in any letter case | US-WL04 | FR-11, FR-14 (OQ12) |
| 16 | A new Source later is a new Dispatch request plus a reviewed gr0wthlab change | US-WL01, US-WL04 | FR-15 |
| 17 | Emit `landing_page_view` when the landing page loads, with `referrer_source`, as the event schema defines it | US-WL05 | FR-16, FR-18, FR-21 |
| 18 | Emit `waitlist_signup` when an email is submitted, with `referrer_source` | US-WL05 | FR-17, FR-18, FR-21 (OQ8) |
| 19 | `referrer_source` is the visit's tag, or `none` | US-WL05 | FR-18 |
| 20 | Neither event carries the email address or the entry identifier | US-WL05 | FR-19 |
| 21 | `/privacy` gains a Waitlist section, in place of the waitlist sentences in section 10 | US-WL11 | FR-45 (OQ10) |
| 22 | Privacy: what is collected (address; routine answer; beta invitation request; which link, if any; sign-up date) | US-WL11, US-WL06 | FR-22, FR-45 |
| 23 | Privacy: why (launch email; beta invitation only if asked; counting without the address) | US-WL11 | FR-45 |
| 24 | Privacy: kept until 30 days after the launch email, or until removal, whichever is first | US-WL10, US-WL11 | FR-43, FR-44, FR-45 |
| 25 | Privacy: removal by the unsubscribe link or a message to reptoday.app@gmail.com; deleted within 7 days | US-WL10, US-WL11 | FR-40, FR-41, FR-42, FR-45 |
| 26 | Privacy: who sees the address (only the founder at send time, and the storing service); never sold or shared | US-WL11, US-WL08 | FR-39, FR-45 (OQ1) |
| 27 | RepToday keeps one file on the founder's Mac that gr0wthlab's launcher reads read-only at each weekly run, with no network | US-WL07 | FR-34, FR-35 (OQ4) |
| 28 | The file sits outside the gr0wthlab, Mandu and RepToday checkouts; a reviewed gr0wthlab change records its path | US-WL07, US-WL08 | FR-33, Dep. 1 |
| 29 | UTF-8 JSON in exactly the shape shown | US-WL01, US-WL07 | FR-27, FR-28 |
| 30 | `entry`: random, 1 to 64 letters, digits, `-` or `_`; unique; stable while the sign-up exists; never derived from the address | US-WL06 | FR-23 |
| 31 | `source`: `tiktok`, `youtube`, `reddit`, `network`, or `unknown` | US-WL07 | FR-28 |
| 32 | `fit`: the three tags, or `null` only for a sign-up that holds no answer | US-WL07 | FR-28 |
| 33 | `beta_opt_in`: `true` or `false` | US-WL07 | FR-28 |
| 34 | `signed_up_on`: the sign-up's date in UTC, `YYYY-MM-DD` | US-WL06, US-WL07 | FR-24, FR-28 |
| 35 | `generated_at`: when the file was written, with its UTC offset | US-WL07 | FR-29 |
| 36 | Nothing else: no address, name or other field | US-WL01, US-WL07 | FR-30 |
| 37 | A removed sign-up leaves the file | US-WL10, US-WL07 | FR-31 |
| 38 | An address-like value makes gr0wthlab discard the read and report a breach | US-WL01, US-WL08 | FR-30 (the plan is that it never triggers) |
| 39 | Addresses are resolved only on the founder's side, at send time | US-WL09 | FR-36 |
| 40 | No email-service credential and no address export is placed in the gr0wthlab, Mandu or RepToday checkouts | US-WL08 | FR-37, FR-38 |
| 41 | Left to RepToday: storage, including whether Kit stays | US-WL06 | OQ1 |
| 42 | Left to RepToday: hosting | US-WL04 | OQ2 |
| 43 | Left to RepToday: how a link's Source reaches its sign-up | US-WL04 | OQ3 |
| 44 | Left to RepToday: how and how often the view is produced | US-WL07 | OQ4 |
| 45 | Left to RepToday: whether sign-ups confirm their email | US-WL06, US-WL07 | OQ5 |
| 46 | Left to RepToday: every other implementation choice | all | OQ6-OQ14 |
| 47 | Once the build lands, gr0wthlab needs one reviewed change (the file's path and the go-live date); until then every post stays "can't publish yet" | US-WL12 | Dep. 1 |

## Verified facts on current main (2026-10-19)

What was checked, so the build can repeat it:

- RepToday: `AGENTS.md`, `CONTEXT.md` (its structure, the Trainer and Two-Writer entries, and a search for any existing Waitlist, Source or Fit term), the `docs/adr/` listing and ADR-0008 in full, the Trainer pose art PRD (#188) for shape, `.claude/skills/prd/PRD_SKILL.md` and its `MEMORY.md`, `gtm/03-site/` (`index.html`, `index-b.html`, `privacy.html`, `_headers`, `DEPLOY.md`), `convex/` (`schema.ts`, `http.ts`, `events.ts`, `rateLimit.ts`, `README.md`), the relevant lines of the funnel PRD, `.github/workflows/ci.yml` job names, `tools/` precedents (`check-no-committed-telemetry-secret.py`, `telemetry-keychain.sh`), and a repository-wide grep for the three event names and for `waitlist`.
- The live site, read-only in a browser with `chrome-devtools-axi` on 2026-10-19: `https://reptoday.app` DOM (forms, scripts, storage), response headers, and a `fetch` status probe of eleven paths.
  No form was submitted.
- gr0wthlab, read-only: `src/gr0wthlab/waitlist.py`, `src/gr0wthlab/settings.py` (`waitlist`), `src/tests/test_waitlist.py`, `src/dispatches/reptoday-waitlist.md`, `config/products.json`, `config/run.json`, and the Waitlist stories of `docs/prd/prd-marketing-engineer-v1_261008.md`.
- Mandu, read-only: `projects/RepToday/gtm/06-channels/event-metric-schema.md`.
- GitHub: repository visibility.

Each row is marked **holds**, **DIFFERS** (the request's assumption does not match the code) or **new** (a fact the request did not mention).

| # | Fact | Where | Status |
| --- | --- | --- | --- |
| V1 | Each served page has two sign-up placements: the hero block (`id="waitlist-hero-head"`, around lines 762-767) and the closing band (`id="waitlist-foot-head"`, around lines 1059-1064); `index-b.html` is one line later. Four placements in total, each a Kit embed `<script async data-uid=... src="https://rep-today.kit.com/.../index.js">`. | `gtm/03-site/index.html`, `index-b.html` | holds ("where the form appears more than once") |
| V2 | On the live page each placement renders one `<form method=post>` whose action is Kit's hosted subscriptions endpoint, with one required text input `email_address` (label "Email Address") and a submit button "Subscribe", plus a "Built with Kit" link. The page also loads Kit's script from `f.convertkit.com` and sets a `ckid` key in `localStorage`. | live probe | holds ("the account behind today's Kit form"); extras are **new** |
| V3 | The live page also loads a Cloudflare Web Analytics beacon (`static.cloudflareinsights.com`). It is not in the repository's HTML, so Cloudflare injects it at the edge. The privacy policy does not mention it. | live probe; `grep cloudflareinsights gtm/03-site` is empty | **new** (matters for OQ10) |
| V4 | "Join the waitlist" is the exact heading in both placements. "Add your email and we'll tell you the day it ships." is the exact sub-line in the closing band. | `index.html:1060-1061` | holds |
| V5 | The hero sub-line is longer: "Rep Today is pre-launch and not yet on the App Store. Add your email and we'll tell you the day it ships." | `index.html:764` | **DIFFERS** (the request keeps "the page's words"; see OQ9) |
| V6 | "one message" appears once per page, in the closing band's lead: "...no date to announce yet, no spam, one message." It is not in the hero. | `index.html:1057`, `index-b.html:1058` | holds |
| V7 | Neither page asks for a download, follow or share. A search for download, follow, share and the social-network names in `index.html` finds nothing. The "Source" links are evidence citations to Hacker News and App Store reviews, not asks. | `index.html` | holds |
| V8 | Every placement has a `<noscript>` fallback: "The signup form needs JavaScript. Email ... to join the waitlist", a `mailto:` link to a `hello@` mailbox on the site's own domain. That is a second way to join, with no Fit answer, no Source and no beta choice, and it is a different mailbox from the policy's published contact address. | `index.html:766,1063`; `index-b.html:767,1064` | **DIFFERS** (the request says "exactly one" call to action and "three fields and no others"; see OQ9) |
| V9 | The FAQ describes the waitlist's data: "the pre-launch waitlist holds the email you add to it, so we can tell you when the app ships - nothing more" (in "Is my data sold?"), and "The waitlist is open now - add your email and we'll tell you the day it ships" (in "When does it launch?"). | `index.html:1037,1045`; `index-b.html:1038,1046` | **DIFFERS** once the form also keeps an answer, a beta choice and a Source: "nothing more" becomes false (OQ9) |
| V10 | Privacy section 10, "This website and the waitlist" (`id="website"`), has three paragraphs: the scope sentence, "If you join the pre-launch **waitlist**, the email address you enter is collected and stored by our email provider (Kit) so we can email you when the app launches. We use it for that purpose. This is distinct from the app, which never asks for your email.", and a muted note: "This website is static. Any additional processing performed by the hosting or email provider is governed by that provider's own privacy terms." | `privacy.html:359-364` | holds; the waitlist sentences are the second paragraph, and arguably the third (OQ10) |
| V11 | The policy's published contact address is the one the request quotes, `reptoday.app@gmail.com`. "Last updated" reads September 1, 2026. The table of contents links `#website`. The only "section N" cross-references in the page are to sections 3, 6, 7 and 9. | `privacy.html:236,260,389`; grep | holds |
| V12 | The policy is an engineering draft: a visible "Draft - not legal advice" banner and a header comment require a legal pass before go-live, and section 12 flags that the policy "does not describe a formal rights-request process ... or a data-retention schedule". Section 8 says "We use no third-party analytics or tracking SDKs - the anonymous measurement above goes only to Rep Today's own endpoint". | `privacy.html:11-27,~376,341` | **new** (the Waitlist section adds the first retention schedule and removal process; the legal flag stays) |
| V13 | Sign-ups are stored by Kit today. The repository holds no sign-up data, no export, no Kit credential and no code that reads Kit (`kit.com` appears only in the pages, `_headers` and `DEPLOY.md`). Whether the live Kit form sends a confirmation email, and how many sign-ups exist, cannot be seen from the repository or the page. | repo grep | holds; two **new** unknowns (OQ5, OQ6) |
| V14 | Hosting is Cloudflare Pages, project `reptoday-site`, pure static, no build step, `gtm/03-site` as both root and output. `DEPLOY.md` documents two deploy routes (Wrangler CLI, or Git integration) and does not say which is live. There is no `_redirects`, no `functions/` directory and no 404 page. `_headers` sets `nosniff`, a referrer policy, `X-Frame-Options: DENY` and a permissions policy, and sets no Content-Security-Policy so the Kit embed keeps working. `DEPLOY.md` assigns attaching the custom domain to the captain as a manual step. | `gtm/03-site/DEPLOY.md`, `_headers`; `ls` | holds |
| V15 | Today `/tiktok`, `/TikTok`, `/youtube`, `/reddit` and `/network` all return `200 text/html` with the landing page, consistent with Cloudflare Pages' documented single-page-app fallback, which serves `index.html` for any path that matches no file when the project has no 404 page. So does `/robots.txt` and `/sitemap.xml`. `/index-b` is `200`; `/privacy.html` and `/index-b.html` answer with a redirect (Pages' extensionless-URL behavior). The Source links therefore "work" today but record nothing, and an arbitrary path is indistinguishable from plain `reptoday.app`. | live `fetch` probe, 2026-10-19 | **new** (shapes OQ2, OQ3; the `robots.txt` behavior is noted as a Non-Goal) |
| V16 | RepToday's repository does **not** define `landing_page_view`, `waitlist_signup` or `referrer_source`. It records them as web-side events "handled outside the app and deliberately absent": `convex/events.ts:9-11`, `convex/README.md` ("The 13 event names are a wire contract"), `Models/AnalyticsEvent.swift:31`, the funnel PRD's non-goal (line 561), `AnalyticsServiceTests` and `convex/http.test.ts:309-314`, which asserts the sink **rejects** both names. | repo grep | holds (with the consequence that today's sink refuses them) |
| V17 | The definition is in Mandu's event-metric schema: `landing_page_view` (Web, "Landing page loads", property `referrer_source` "(utm or none)", feeds "Pre-launch top of funnel; K5 channel signal"); `waitlist_signup` (Web, "Email submitted to waitlist", `referrer_source`, feeds "Pre-launch conversion"); and the conversion `waitlist_signup` divided by `landing_page_view`, split by `referrer_source`. The schema also says events carry a random per-install ID only. | Mandu `projects/RepToday/gtm/06-channels/event-metric-schema.md` | **DIFFERS** in one word: the schema says "utm or none" for `landing_page_view`, the request says the visit's tag or `none`. This PRD follows the request and reads no UTM parameters (OQ12). A web visit has no install, so "random per-install ID" cannot apply (OQ7). |
| V18 | The Convex sink's `events` row requires `installId`, and its `name` is a plain string; the closed union of the 13 app events is on the internal `logEvent` mutation's arguments; `POST /logEvent` requires a shared-secret header, enforces 60 events per install and 600 per IP per minute and a 64 KiB body, and handles no CORS or preflight anywhere in `convex/http.ts`. The deployment's schema is limited to the `events` table and the ephemeral `rateLimits` table ("the second - and, per FR-6, last permitted - table"). Its contract is "no identity in any event". | `convex/schema.ts`, `events.ts`, `http.ts`, `rateLimit.ts`; funnel PRD FR-6 | **new** (rules out Convex as the address store; constrains OQ7) |
| V19 | Both page variants are live: `index.html` at `/` and `index-b.html` at `/index-b`. The A/B split by Worker is explicitly out of scope in `DEPLOY.md`. | `DEPLOY.md`; live probe | holds ("the form appears more than once" applies across both) |
| V20 | `AGENTS.md` said "This repository is public". GitHub reports `RepToday` as **private** (checked 2026-10-19). | `AGENTS.md:21`; `gh repo view` | **DIFFERS**; `AGENTS.md` now reads "Treat this repository as public (its visibility has changed before)", keeping its no-committed-secret rule unchanged. The same "is public" premise stood, unedited, in `README.md`, `convex/README.md`, `.github/workflows/ci.yml`, `ios/RepToday/project.yml` and `tools/check-no-committed-telemetry-secret.py`; US-WL01's change reworded those five to the same premise, changing only that wording (the rule and its checks are untouched). Every credential rule in this PRD holds either way, and the site's own content is public regardless. |
| V21 | Headless Chrome through `chrome-devtools-axi resize 390 844` reports a 500 px viewport, because it enforces a minimum window width (the pages' own CSS comments say the same). `chrome-devtools-axi emulate --viewport "390x844x3,mobile,touch"` followed by re-opening the page gives a true 390 px viewport. On the live page the waitlist card is 342 px wide at 390 px, with no horizontal scroll. | live probe | **new** (how this PRD's web Validation Tests reach 390 px) |

## The gr0wthlab reader contract

The view is read by `waitlist.read` in gr0wthlab's `src/gr0wthlab/waitlist.py`, with its rules configured in `config/products.json` (`waitlist`) and `config/run.json` (`waitlist`).
The request's prose and the reader agree.
These are the reader's exact rules, which US-WL01's checker mirrors and which the requirements below cite.

| Reader rule | Consequence for this PRD |
| --- | --- |
| The file must be UTF-8 and at most 10,000,000 bytes; larger or non-UTF-8 files are a failed read. | FR-32 |
| The top level holds **exactly** `view`, `generated_at`, `entries` (a different key set is a failed read). | FR-27 |
| `view` must be the integer `1` (a boolean is rejected; a larger number is "never guessed at"). | FR-27 |
| `generated_at` must be a string that Python's `fromisoformat` accepts after replacing `Z` with `+00:00`, **and** carry a UTC offset. | FR-29 |
| `entries` must be a list of objects, each holding **exactly** `entry`, `source`, `fit`, `beta_opt_in`, `signed_up_on`. | FR-28 |
| `entry` must fully match `[A-Za-z0-9_-]{1,64}` and be unique in the file. | FR-23 |
| `source` must be one of the configured tags (`tiktok`, `youtube`, `reddit`, `network`) or `unknown`. | FR-14, FR-28 |
| `fit` must be `null` or one of the configured answers (`lost-the-routine`, `exercises-regularly`, `never-had-a-routine`). A `null` is counted as unknown Fit, never as not a fit. | FR-5, FR-28 |
| `beta_opt_in` must be a real JSON boolean. | FR-28 |
| `signed_up_on` must be a string that round-trips `date.fromisoformat(text).isoformat() == text` (so exactly `YYYY-MM-DD`) and must **not** be later than the UTC date of `generated_at`. | FR-24, FR-29 |
| **Address check, run first over the file's whole text and again over every key and value:** any `@` with a character other than whitespace, another `@` or one of `"'<>()[]{},;:\` on **both** sides counts as an address. A hit **refuses** the whole read: nothing is kept, no Waitlist Evidence is recorded that week, and a Guardrail breach is reported. An `entry` is additionally decoded: its percent-decoding is judged by that same loose rule, while its base64 (both alphabets) and hex decodings, read as printable UTF-8, count only when they hold a whole address (a local-part character, an `@` and a dotted domain ending in two or more letters); a hit in either is a breach. | FR-30 |
| Any other departure from the format is a **failed** read (named in the run report without repeating any value), not a breach; the run goes on without the view. | FR-27, FR-28 |
| The reader opens and reads the whole file once, with no lock; a view of any age is read and its age reported. | FR-32, FR-34 |
| Beta Cohort invitations take opted-in sign-ups in order: good Fit first, then the earliest `signed_up_on`, and the view's own order settles a tie (`invitation_order`); each batch takes at most `batch_size` (20 in `config/run.json`) from the front. So the order the producer writes entries in decides who is invited among same-day sign-ups. | FR-28, US-WL07 |
| The configured path must not overlap, in either direction, any place the sandboxed agent can read: the gr0wthlab repository and git directories, every registered location (including the Mandu and RepToday checkouts) and the system read paths. The launcher refuses to start otherwise. | FR-33 |
| The path is `null` in `config/products.json` until a reviewed change sets it; `GR0WTHLAB_WAITLIST_VIEW` overrides it. `waitlist.live_since` in `config/run.json` is `null` until a reviewed change sets it "once US-ME05's Validation Test has passed on reptoday.app". | Dep. 1 |
| The reader's own test draws 5,000 random identifiers of 8 to 64 characters from the allowed alphabet and requires none to look like, or decode to, an address. | US-WL06 |

Reader details the prose above omits, found by reading `waitlist.py` and checked by US-WL01's cross-check against it (the reader wins; none changes a requirement):

- `view` is compared with `1` after the boolean test, so a JSON float `1.0` is read as version 1; a larger integer is rejected on its own, with no other problem listed.
  The checker follows the reader, and the producer (US-WL07) writes the integer.
- `generated_at` is stripped of surrounding whitespace and every `Z` is replaced by `+00:00` before `fromisoformat` runs, so which spellings parse depends on the interpreter (Python 3.11 and later accept more than 3.9 does).
  The producer writes the one form of the request's example, which every version accepts.
- The reader keeps only the first 10,000,001 bytes of a file: the address check runs on those bytes, so an address after them is never seen and the file is a failed read for its size, while an address inside them makes an oversized file a refused read.
  The same order holds for a file that is not UTF-8 or not JSON: the address check on its text runs first, so such a file with an address-shaped sequence is refused, not failed.
- The text is decoded with replacement characters for the address check, so an invalid byte beside an `@` counts as a character on that side.
- JSON is parsed by Python's own `json.loads`, so a repeated key keeps its last value (the reader accepts such a file) and `NaN` and `Infinity` parse, though they can only land where the format rejects them.
  The producer writes neither.
- When the file cannot be opened (missing, a folder, unreadable) the reader reports a failed read.

Every one of these is a fixture or a generated case in `tools/waitlist/`, and the checker agrees with the reader on all of them.

## User Stories

Stories are ordered by dependency.
Every web story's visual check runs in a browser with `chrome-devtools-axi`, at a true 390 px phone width and at a 1440 px desktop width:

```
chrome-devtools-axi emulate --viewport "390x844x3,mobile,touch"
chrome-devtools-axi open http://localhost:8788/
chrome-devtools-axi emulate --viewport "1440x900x1"
chrome-devtools-axi open http://localhost:8788/
```

`chrome-devtools-axi resize 390 844` is not enough: headless Chrome clamps it to about 500 px (V21).
The local site is served with `npx wrangler pages dev gtm/03-site --port 8788`, which needs no Cloudflare login and is meant to apply `_headers` and `_redirects`; whether it also reproduces the Pages fallback is itself checked in US-WL04, and anything the emulation does not reproduce is re-checked on the captain-approved preview deploy in US-WL12.
No test posts to the production list, and no email goes to any address other than one created for the test or owned by the founder; sign-up destinations are configurable and tests use a local stub receiver or a separate test destination.
The US-WL12 rehearsal is the one captain-approved step that uses the production destination and the production event sink, with the founder's own addresses; its evidence records the rehearsal's time window so the conversion computation can exclude those rows.
Each story writes evidence (screenshots at both widths, command transcripts, no addresses) under `artifacts/reports/US-WL##/validation.md`, adds a row to `docs/test-coverage.md` and an entry to `docs/implementation-log.md`.
Pure date logic takes an injected `asOf` clock and never reads the wall clock, per the project convention.
The first task of US-WL06 (the spike that proves the OQ1 destination) runs before US-WL02 is built against a real destination; the rest of US-WL06 follows US-WL02.

| Story | Waits for |
| --- | --- |
| US-WL01 contract and view checker | nothing |
| US-WL02 sign-up form | OQ1 and US-WL06's spike (the destination), OQ5, OQ9 |
| US-WL03 page copy and consistency | US-WL01, US-WL02, OQ9 |
| US-WL04 Source links and persistence | US-WL01, US-WL02, OQ2, OQ3, OQ12 |
| US-WL05 web events | OQ7, OQ8, US-WL02, US-WL04 |
| US-WL06 sign-up storage and entry identifiers | OQ1, OQ5, OQ6, OQ11; after its spike, US-WL02 and US-WL04 |
| US-WL07 anonymous view producer | US-WL01, US-WL06, OQ4, OQ5 |
| US-WL08 address boundary guard | US-WL01, US-WL03 (which removes the `hello@` mailbox links the guard would flag), US-WL07, OQ1 |
| US-WL09 send-time lookup | US-WL06, US-WL08, OQ1 |
| US-WL10 removal and retention | US-WL06, US-WL07, OQ13 |
| US-WL11 privacy policy Waitlist section | OQ1, OQ5, OQ10, US-WL10 |
| US-WL12 go-live rehearsal and evidence | all of the above, plus the captain's deploy approval |

### US-WL01: One contract - the approved strings, the tags and a view checker

**Description:** As a builder, I want the approved strings, the Source tags, the Fit answers and the view's rules in one place, with a checker that mirrors gr0wthlab's reader, so that every later story builds against the same contract and an address-bearing or malformed view can never be written.

**Acceptance Criteria:**

- [x] A data file under `tools/waitlist/` (for example `contract.json`) holds, as data: the heading "Join the waitlist"; the sentence "Add your email and we'll tell you the day it ships."; the Fit legend "Which sounds most like you?"; the three Fit answers with their labels and tags; the beta label "Invite me to the beta before launch"; the phrase "one launch email, plus a beta invitation only if you ask for one"; the four Source tags; the words `unknown` and `none`; the names of the form's posted fields (email, Fit answer, beta choice, Source); the view format version `1`; the entry pattern `[A-Za-z0-9_-]{1,64}`; and the 10,000,000-byte limit.
- [x] Every approved string in that file (the wording, the Fit and Source tags, `unknown` and `none`) is byte-identical to its text in Appendix A (checked by a test that reads both).
  The posted field names, the entry pattern and the byte limit are not in Appendix A (the email name is Kit's `email_address` under OQ1 Option A and the others are provisional until US-WL06's spike; the pattern and the limit are the reader's), so the test does not compare them with it.
- [x] `tools/waitlist/check-view.py` (Python 3 standard library only, like `tools/check-trainer-art.py`) takes a file path and exits 0 only for a view that satisfies every rule in "The gr0wthlab reader contract"; on failure it names the rule and the entry's position and never prints the offending value.
- [x] It runs the address check first, over the file's whole text and then every key and value, with the reader's loose pattern; it judges `entry`'s percent-decoding by that same loose pattern, and its base64 (both alphabets) and hex decodings by the reader's whole-address pattern, as the reader contract states.
- [x] Fixtures under `tools/waitlist/fixtures/`: a valid view with three entries (one with `fit` `null`, one with source `unknown`), a valid view with empty `entries`, and one failing fixture per rule (missing and extra top-level keys; `view` 2 and `view` true; `generated_at` without an offset; `signed_up_on` malformed and later than `generated_at`'s UTC date; a duplicate entry; an entry of length 0 and of 65; a character outside the alphabet; a `source` and a `fit` outside the lists; `beta_opt_in` as a string; an extra entry key; a file that is not UTF-8).
- [x] The address cases and the over-limit file are generated, never committed: the test builds each at run time, assembling every address from parts, and writes it to a temporary path outside the repository (an address-shaped value in `source`, in `fit`, in `generated_at` and in a key name; an `entry` that is an address in percent-encoded, base64 and hex form; an `entry` whose percent-decoding puts an `@` between two ordinary characters without forming a whole address, which the reader refuses rather than fails; a file over the 10,000,000-byte limit), and a test fails if any file under `tools/waitlist/fixtures/` contains an address-shaped string.
- [x] `tools/waitlist/test-check-view.py` runs every committed and generated fixture and asserts accept or reject and the named rule.
- [x] Optional local cross-check: when an environment variable names a gr0wthlab checkout, the test also imports that checkout's `src/gr0wthlab/waitlist.py` read-only and requires its verdict (read, failed or refused) to agree with this checker on every fixture; it is skipped otherwise, never required in CI, and writes nothing in gr0wthlab.
- [x] The test is wired into a CI job that needs no Xcode (US-WL12 may add the job if none exists).
- [x] Lint passes.

**Validation Test:**

- **Setup:** The branch with US-WL01; Python 3; optionally a gr0wthlab checkout for the cross-check.
- **Steps:**
  1. Run `python3 tools/waitlist/test-check-view.py`.
  2. Run `python3 tools/waitlist/check-view.py tools/waitlist/fixtures/valid.json`, then run it on an address-in-`source` view that the test's generator writes to a temporary path outside the repository.
  3. Edit one string in the contract file (for example the heading) and rerun step 1.
  4. If a gr0wthlab checkout is available, set the environment variable and rerun step 1 read-only.
- **Expected Result:** Step 1 passes; step 2 exits 0 for the valid view and non-zero for the generated address view with a message that names the rule and position but not the value; step 3 fails the byte-identity test; step 4 shows the checker and the real reader agreeing on every fixture.
- **Failure Indicator:** A malformed view is accepted, a message repeats an address-shaped value, an address is committed in a fixture, or the checker and the reader disagree on any fixture.

### US-WL02: The sign-up form

**Description:** As a visitor, I want one short form that asks for my email, one question about me, and whether I want a beta invitation, so that joining the waitlist takes a few seconds and asks for nothing else.

**Acceptance Criteria:**

- [x] One form definition appears in all four placements (hero and closing band, on `index.html` and `index-b.html`), identical except for element ids (FR-2; US-WL03 enforces it).
- [x] The heading is "Join the waitlist" and the sentence is "Add your email and we'll tell you the day it ships."
- [x] Field 1: an Email input (`type="email"`, `autocomplete="email"`, required) with a visible label; no placeholder stands in for the label.
- [x] Field 2: a `fieldset` with the legend "Which sounds most like you?" and three radio buttons labelled exactly "I used to work out and lost the routine" (`lost-the-routine`), "I work out regularly" (`exercises-regularly`) and "I've never had a routine" (`never-had-a-routine`); required; **none checked** on first load, after a reload and after back-navigation (form restoration must not pre-select).
- [x] Field 3: a checkbox labelled exactly "Invite me to the beta before launch", **unchecked** on first load, after a reload and after back-navigation.
- [x] No other input, visible or hidden, carries anything the visitor entered; the only additional value sent is the visit's Source tag (FR-14), which the visitor is never asked for.
  There is no "how did you hear about us" field.
- [x] Empty or malformed email, or no Fit answer, blocks submission with a visible message tied to its control (`aria-describedby` or an associated error element), moves focus to the first invalid control, and keeps everything already entered; wording per Appendix B (OQ9).
- [x] While sending, the submit control is disabled and shows the in-progress wording; on acceptance the form shows the success wording; on failure it shows the error wording, keeps the entered values and allows a retry; none of these states widens the card.
- [x] The submission goes to the destination settled in OQ1, configurable in one place; tests post to a local stub receiver, and no test run posts to the production destination (the US-WL12 rehearsal is the one exception, stated above).
- [x] Control heights are at least 44 px; text and controls meet 4.5:1 contrast on the Paper tokens (hero) and on the light card inside the Night band (closing); focus is visible; the whole form completes by keyboard alone; status messages are announced (`aria-live="polite"`).
- [x] The form lives inside the existing `.waitlist` card and fits it at 390 px and 1440 px with no horizontal scroll.
- [x] Verify in browser with `chrome-devtools-axi` at 390 px and 1440 px (screenshots under `artifacts/reports/US-WL02/`).

**Validation Test:**

- **Setup:** `npx wrangler pages dev gtm/03-site --port 8788` and the local stub receiver, with the form pointed at the stub.
- **Steps:**
  1. At 390 px, in a fresh page (`chrome-devtools-axi newpage`) that has opened no Source link, open `http://localhost:8788/`, take a snapshot, and read the hero form: heading, sentence, label, legend, three radios, checkbox.
  2. Evaluate `document.querySelectorAll('input[type=radio]:checked').length` and `document.querySelectorAll('input[type=checkbox]:checked').length`.
  3. Reload, then navigate to `/privacy` and back; repeat step 2.
  4. Click submit with everything empty, then with a malformed email, then with a valid email and no Fit answer.
  5. Fill a valid email, choose "I work out regularly", leave the box unticked, submit; read the stub's received body.
  6. Repeat steps 1, 2 and 5 at 1440 px on `/index-b` and in the closing band of each page.
- **Expected Result:** Exactly three controls plus the legend and labels appear; step 2 returns 0 and 0 on first load, after reload and after back-navigation; step 4 shows three distinct messages and focus on the first invalid control with nothing cleared; step 5's received body holds the email, `exercises-regularly`, beta `false` and Source `unknown`, and the page shows the success wording; no horizontal scroll at either width; all four placements behave the same.
- **Failure Indicator:** A radio or the box is pre-checked after restoration, a fourth field exists, submission succeeds without an email or Fit answer, entered values vanish on error, the card overflows at 390 px, or any run posts to a destination other than the stub.

### US-WL03: Page copy and consistency across both pages

**Description:** As the captain, I want the landing pages to promise exactly what the Waitlist does and to ask only for the sign-up, so that nothing on either page contradicts the form or the policy.

**Acceptance Criteria:**

- [ ] The string "one message" appears nowhere on either page.
- [ ] The closing band's lead now contains the phrase "one launch email, plus a beta invitation only if you ask for one" verbatim.
- [ ] The hero's lead-in sentence "Rep Today is pre-launch and not yet on the App Store." and the `<noscript>` mailbox fallbacks are handled as OQ9 settles; after this story no placement offers a second way to join the waitlist.
- [ ] The FAQ sentence "the pre-launch waitlist holds the email you add to it ... nothing more" is replaced as OQ9 settles, so it no longer understates what the form keeps; the "When does it launch?" answer stays consistent with the call to action.
- [ ] Neither page asks the visitor for a download, a follow or a share; the form is the only action that asks anything of the visitor (a word-list grep guard).
- [ ] `tools/waitlist/check-site.py` (CI) fails when: the four placements differ beyond element ids; any approved string from the contract file is missing or altered; "one message" is present; a `mailto:` join path is present; an email-shaped string (a whole address, as US-WL08 defines it) other than the policy's published contact address appears in a text file in `gtm/03-site/` (text as US-WL08 defines it).
- [ ] Outside the waitlist blocks and the sentences above, `index.html` and `index-b.html` differ only as they do today (a before/after diff is attached to the evidence), so the running A/B comparison is not disturbed.
- [ ] Verify in browser with `chrome-devtools-axi` at 390 px and 1440 px on `/` and `/index-b`.

**Validation Test:**

- **Setup:** The branch with US-WL02 and US-WL03; the local site.
- **Steps:**
  1. Run `python3 tools/waitlist/check-site.py`.
  2. Evaluate on each page `document.body.innerText.includes('one message')` and `...includes('one launch email, plus a beta invitation only if you ask for one')`.
  3. Add the same `<noscript>` mailbox line, a `mailto:` link to the policy's published contact address, to all four placements and rerun step 1.
     The line is identical in every placement and names only the allowed address, so neither the drift rule nor the stray-address rule can fire; a browser with scripting on parses `<noscript>` content as text, so a DOM query cannot see that link, and the static check in step 1 is the test for a mailbox join path.
  4. Make one placement differ (change a label in the closing band only) and rerun step 1.
  5. Read the FAQ answers at 390 px and 1440 px.
- **Expected Result:** Step 1 passes; step 2 is `false` then `true`; step 3 fails the check with a message that names the `mailto:` join-path rule, the file and the line, and no other rule; step 4 fails the check and names the placement; the FAQ matches the form and the policy.
- **Failure Indicator:** "one message" survives, a mailbox join path survives, the FAQ still says "nothing more", one placement drifts without the check failing, or the A/B variants gain unrelated differences.

### US-WL04: Source links and Source persistence

**Description:** As the founder, I want each of four short links to record where a visitor came from, and to keep it while they look around the site, so that every sign-up carries its Source without asking anyone.

**Acceptance Criteria:**

- [ ] `reptoday.app/tiktok`, `/youtube`, `/reddit` and `/network` each open the landing page with the sign-up form; the lowercase word after the slash is that visit's Source tag.
- [ ] The links work in any letter case (`/TikTok`, `/YOUTUBE`, `/rEdDiT`, `/Network` all resolve to the lowercase tag).
- [ ] Each link is only the bare tag: no query string, token or redirect chain is needed to use it, so it can be said aloud, typed or put in a profile.
- [ ] Once a visit has arrived by one of the four links, the tag is kept for the rest of that visit while the visitor moves between the landing page, the FAQ anchors and `/privacy`, per the persistence rule settled in OQ3, and is what the form sends and what the events carry.
- [ ] Every other arrival (plain `reptoday.app`, `/index-b` with no tag, an unrecognized path, any search or social referrer, a `utm_*` parameter) yields Source `unknown` for the sign-up and `none` for the events; nothing outside the four tags is ever recorded as a tag.
- [ ] The four tags live in one list shared by the page script, the contract file (US-WL01) and the view producer; a unit test fails if the list and the view checker's allowed sources disagree.
- [ ] Adding a Source is documented as a new Dispatch request plus a reviewed gr0wthlab change, and no code path accepts a fifth tag.
- [ ] The routing the chosen hosting needs (OQ2) is explicit, not an accident of the fallback: a test fails if a top-level 404 page is added in a way that turns the four links into 404s.
- [ ] No cookie is set and no identifier is stored beyond the tag (and, if OQ3 recommends it, a per-tab `sessionStorage` entry holding only the tag).
- [ ] Verify in browser with `chrome-devtools-axi` at 390 px and 1440 px.

**Validation Test:**

- **Setup:** The local site and the stub receiver; the hidden Source field's name is taken from the contract file.
- **Steps:**
  1. Open `/tiktok`, `/TikTok`, `/YOUTUBE`, `/reddit` and `/network`, each in a fresh page (`chrome-devtools-axi newpage`); after each, evaluate the hidden Source field's value.
  2. In a fresh page open `/tiktok`, follow the footer "Privacy Policy" link, then return to `/` in the same tab, and evaluate the field; then submit a sign-up and read the stub.
  3. In a fresh page, before any Source link is opened in it, open `/`, evaluate the field, and submit a sign-up; then open `/index-b`, `/tiktk` and `/?utm_source=tiktok` in turn in the same page, evaluating the field after each.
  4. In the same page open `/reddit?x=1` and evaluate the field.
  5. After the captain-approved preview deploy (US-WL12), repeat step 1 against the preview URL.
- **Expected Result:** Step 1 yields `tiktok`, `tiktok`, `youtube`, `reddit`, `network`; step 2 still yields `tiktok` after browsing and the stub body carries `tiktok`; step 3 yields `unknown` for `/`, `/index-b`, `/tiktk` and the UTM URL, and its stub body carries `unknown`; step 4 yields `reddit`; step 5 matches the local result for every casing.
- **Failure Indicator:** A casing misses, the tag is lost after visiting `/privacy`, a `utm_source` or an arbitrary path becomes a tag, a cookie appears, or the fallback behavior differs on the real Pages deployment.

### US-WL05: Web events

**Description:** As the captain, I want the landing page view and the sign-up counted by Source, so that I can see which links turn visitors into sign-ups without learning who anyone is.

**Acceptance Criteria:**

- [ ] `landing_page_view` is emitted once on every load of either landing-page document (`index.html` or `index-b.html`), whatever path served it (`/`, `/index-b`, the four Source links, or any other path the fallback answers with the landing page), never on `/privacy`, with exactly one property, `referrer_source`.
- [ ] `waitlist_signup` is emitted when an email is submitted (the moment settled in OQ8) with exactly one property, `referrer_source`.
- [ ] `referrer_source` is the visit's tag (`tiktok`, `youtube`, `reddit`, `network`) or `none`; it is never the Source's other spelling `unknown`, never a UTM value and never free text.
- [ ] Neither event carries the email address, the entry identifier, any identifier of the visitor or device, or any cookie.
- [ ] Emission is fire-and-forget: a failed, slow or blocked request never delays the page, the form or the success state, and nothing retries into a loop.
- [ ] No event is sent from `localhost`, a preview URL or a test run to the production sink (the US-WL12 rehearsal is the one exception, stated above).
- [ ] The sink side follows OQ7 and, whatever it is, rejects any name other than the two web names and any property bag other than exactly `{referrer_source: <tag or none>}`, without disturbing the app's `POST /logEvent` contract (its 13 names, its secret header, its tests).
- [ ] The app's shared-secret header value is never placed in a web page.
- [ ] If the sink is Convex: the new route has its own rate-limit scope sized for web traffic (the per-install key cannot apply), the origin is checked, `convex/README.md` documents the route and the reserved row convention, `convex/http.test.ts`-style tests cover accepted and rejected bodies, `npm run typecheck` and `npm test` pass, and the stale "handled outside the app" notes (V16) are rewritten.
- [ ] `AGENTS.md` and the funnel PRD's non-goal are amended only as far as the new route requires, in the existing amendment style.
- [ ] Deploying the sink to the production Convex deployment is a separate, captain-approved, credentialed step.

**Validation Test:**

- **Setup:** The dev Convex deployment (`courteous-dogfish-560`) or the in-process `convex-test` harness, never production; the local site pointed at it.
- **Steps:**
  1. In a fresh page (`chrome-devtools-axi newpage`), before any Source link is opened in it, open `/`; then `/youtube`, then `/` again in the same page; read the stored rows.
  2. Submit a sign-up from `/youtube`; read the stored rows.
  3. Post a web event with an extra property, one with a name outside the two, and one with a `referrer_source` of `unknown`; post `landing_page_view` to the app's `/logEvent`.
  4. Open `/privacy`.
  5. Point the page's event endpoint (configurable for tests) at an unreachable local address, submit a sign-up, and read `chrome-devtools-axi console`.
  6. With the endpoint restored, open `/tiktk` in a fresh page; read the stored rows.
- **Expected Result:** Step 1 stores three `landing_page_view` rows, with `{"referrer_source":"none"}`, then `{"referrer_source":"youtube"}`, then `{"referrer_source":"youtube"}` (the kept tag); step 2 adds `waitlist_signup` with `{"referrer_source":"youtube"}`; every row holds exactly the two names and one property; step 3's three web posts are rejected and the `/logEvent` post is still rejected as before; step 4 adds nothing; step 5 still reaches the sign-up stub and shows the success wording, with no uncaught error in the console; step 6 adds one `landing_page_view` with `{"referrer_source":"none"}`.
- **Failure Indicator:** Any row holds an address, an entry identifier, an extra property or `unknown`; `/privacy` emits a view; a landing page served at an unrecognized path emits none; a failing sink blocks the form; the app contract or its tests change.

### US-WL06: Sign-up storage and entry identifiers

**Description:** As the founder, I want each sign-up stored with its answers and a random entry identifier, so that I can email people, invite the ones who asked, and count them without addresses.

**Acceptance Criteria:**

- [ ] A first task proves the OQ1 design before anything else is built: a spike note under `artifacts/reports/US-WL06/` records, against a test destination and never the production list, whether the chosen path accepts a first-party sign-up with the Fit answer, beta choice and Source as stored fields, whether a browser can read its success or failure, whether it sends a confirmation message (the unknowns in V13) and whether that message carries a working unsubscribe link (OQ5), whether the store can permanently delete a sign-up and its fields rather than only mark it unsubscribed (OQ1; US-WL10 and the policy's "deleted within 7 days" depend on it), whether a resubmission of a listed address overwrites its stored fields (OQ11), whether the service exposes a creation time a resubmission does not change and that is the submission time, unchanged by confirmation (OQ5) (under OQ1 Option A the only source of `signed_up_on`; under every option the only source of the original dates OQ6 keeps, since those sign-ups exist only in Kit), and whether a public post can set or overwrite the field that holds the entry identifier.
  If it cannot carry the fields or report its result, the design falls back as OQ1 states and the captain approves the amended policy sentence before US-WL11; if it cannot permanently delete, the captain decides how the 7-day deletion is kept before US-WL11 publishes the wording; if a public post can set or overwrite the identifier field, the captain decides how the producer keeps identifiers its own before US-WL07 is built; if it exposes no creation time a resubmission leaves alone, the captain decides how `signed_up_on` and OQ6's original dates are kept before US-WL06 and US-WL07 are built; if that time is not the submission time under double opt-in, the captain decides which date `signed_up_on` carries before US-WL07 is built; if its confirmation message carries no working unsubscribe link, the captain decides how removal by that link is kept before US-WL11 publishes the wording.
- [ ] A stored sign-up holds exactly: the address, the Fit answer (or none), the beta choice, the Source, the sign-up date, the entry identifier, and only the status fields the sending service itself requires (for example subscribed or unsubscribed, confirmed or not).
- [ ] The entry identifier is generated from a cryptographically secure random source, matches `[A-Za-z0-9_-]{1,64}` (recommended: 16 characters from the 62-letter-and-digit alphabet), is unique among current sign-ups, is stored with the sign-up so the view can be rebuilt from scratch with identical identifiers, never changes while the sign-up exists, and is never a function of the address (no hash, no encoding, no counter that reveals order).
- [ ] A collision with the identifier of a removed sign-up is negligible by construction (identifiers carry at least 80 bits of entropy).
- [ ] Under OQ1 Option A, where no Rep Today code runs at sign-up, an assignment step gives every stored sign-up that lacks an entry identifier a fresh one under the rule above, writes it back to the store, and never reassigns an existing one; its runs never overlap a view-producer run or another assignment and end within the same bound, with a timeout on every network call (US-WL07).
- [ ] A value that arrives outside the allowed sets never reaches the view as sent: a Fit value outside the three tags counts as no answer, and a Source outside the five counts as `unknown`.
  Under OQ1 Option A the browser posts straight to the sending service and no Rep Today code runs at storage time, so the service keeps what was posted and the producer normalizes it when it projects the view (FR-28, US-WL07); under A2 or B, Rep Today's own code stores the value as none or `unknown`.
- [ ] `signed_up_on` is the UTC date the sign-up was submitted, and does not change on a later resubmission.
- [ ] A second submission with an address already on the list follows OQ11 and never creates a second entry.
- [ ] Existing sign-ups made before this build are handled as OQ6 settles.
- [ ] Confirmation behaves as OQ5 settles.
- [ ] No log, error report or console output written by the storage code contains an address.
- [ ] The names of any stored fields in the sending service are recorded in one place (renaming them later would lose data).
- [ ] Unit tests: 5,000 generated identifiers all match the pattern, are unique, and pass US-WL01's address check; two sign-ups of the same address with a removal between them receive different identifiers.

**Validation Test:**

- **Setup:** A test destination (a separate test list or tag in the chosen service, or the local stub), the captain's approval of OQ1, OQ5, OQ6 and OQ11.
- **Steps:**
  1. Submit three test sign-ups with addresses created for the test, each in a fresh page (`chrome-devtools-axi newpage`): one through `/tiktok` with Fit `lost-the-routine` and the box ticked, one through plain `/` with a different Fit answer, one repeating the first address with the box unticked.
  2. Under OQ1 Option A, run the identifier assignment; then inspect the stored records.
  3. Remove the first sign-up, then submit the same address again through `/reddit` in a fresh page; under Option A, run the identifier assignment again.
  4. Run the identifier unit tests.
  5. Under OQ1 Option A2 or B only, post one sign-up straight to the destination with a Fit and a Source outside the allowed sets, and inspect its stored record (under Option A this check is US-WL07's).
- **Expected Result:** Step 2 shows two entries (not three) with the Source, Fit, beta choice, date and identifier recorded, and the repeat handled as OQ11 settles; step 3 gives the re-added sign-up a different identifier; step 4 passes; step 5's record holds no answer and Source `unknown`.
- **Failure Indicator:** A second entry appears for a repeated address, an identifier correlates with the address, under A2 or B an out-of-set value reaches the stored record verbatim, or an address appears in any log.

### US-WL07: The anonymous view producer

**Description:** As the Marketing Engineer's launcher, I want one address-free file, in exactly the format I read, kept fresh on the founder's Mac, so that the weekly run can count sign-ups by Source and Fit without ever reading an address.

**Acceptance Criteria:**

- [ ] A command under `tools/waitlist/` reads the store (OQ1) and writes the view: top-level keys exactly `view` (`1`), `generated_at` and `entries`; each entry exactly `entry`, `source`, `fit`, `beta_opt_in`, `signed_up_on`, with the values and types in the reader contract.
- [ ] It projects only those five fields; the address, any name and any other stored field never enter its in-memory view structure.
- [ ] `fit` is `null` only for a sign-up that holds no answer, which includes a stored Fit outside the three tags (US-WL06); `source` is `unknown` for a sign-up with no valid tag; `beta_opt_in` is a boolean; `signed_up_on` is the UTC date.
- [ ] Under OQ1 Option A, the producer runs US-WL06's identifier assignment before projecting, so it never projects a missing identifier and never mints one only in memory.
- [ ] Under double opt-in (OQ5), an unconfirmed sign-up is never projected, and it appears once confirmed, with `signed_up_on` still its submission date.
- [ ] `generated_at` is stamped after the store is read and carries a UTC offset, so no `signed_up_on` is later than its UTC date.
- [ ] Entries are written in a stable order, whatever order the store returns them in: ascending by `signed_up_on`, then by entry identifier, so the reader's invitation tie-break (the view's own order) is the same on every run.
- [ ] Before writing, it runs US-WL01's checker over the candidate bytes and refuses to replace the existing file if the check fails, leaving the previous view untouched and exiting non-zero with a message that never repeats a value.
- [ ] Runs of the view producer and of the identifier assignment never overlap, so one sign-up never gets two identifiers; every run ends within a stated bound, with a timeout on every network call, and a run past its limit exits without replacing the file; every removal is followed, no later than the next scheduled run, by a view generated from a store read made after the removal; no run can stall another indefinitely or stop the deletion sweep, so a removed sign-up is still deleted within 7 days; and an interrupted run leaves nothing that blocks later runs.
  The build designs and tests the mechanism for the storage option chosen.
- [ ] The write is atomic (a temporary file in the same directory, then a rename), the file mode is owner-only, and a file that would exceed the 10,000,000-byte limit fails the run rather than truncating.
- [ ] A removed or retention-expired sign-up is absent from the next generation that reads the store after its removal; an empty store writes `"entries": []`.
- [ ] The default output path is outside the gr0wthlab, Mandu and RepToday checkouts and outside every git work tree, settled in OQ4; the command resolves symbolic links and refuses to write when the directory the file would be written in, or any ancestor of it, contains a `.git` entry (a directory, or a file as in a linked worktree).
- [ ] It runs on the cadence settled in OQ4 and can be run on demand; a missed run is visible to the reader as the view's age (`generated_at`), which the launcher already reports.
- [ ] The evidence records whether a scheduled run that the Mac slept through runs when it wakes (OQ4's "confirm").
- [ ] It needs no network at read time for gr0wthlab: the reader opens a local file; the producer's own network use (to read the store and, under OQ1 Option A, to write back new identifiers) is the producer's alone.
- [ ] Credentials the producer needs are read from the macOS Keychain at run time (item names recorded, values never), never from a file, argument or environment value that git or a shell history could keep.
- [ ] It logs counts only, never a value.
- [ ] A synthetic store mode (fixture input) exists for tests, so no test touches the real store.

**Validation Test:**

- **Setup:** A synthetic store holding seven sign-ups (a `null` Fit, an `unknown` Source, a ticked box, a recent date, one whose stored Fit and Source are outside the allowed sets, one with no entry identifier under OQ1 Option A, and one not yet confirmed under double opt-in), listed out of date order and with two on the same day, the default output directory (or a temporary one outside any repository for the test), and optionally the gr0wthlab checkout for the cross-check.
- **Steps:**
  1. Run the producer against the synthetic store; run `check-view.py` on the output; if available, run the reader cross-check.
  2. Remove one synthetic sign-up and rerun; compare entries.
  3. Make the checker fail on purpose (inject a stored entry identifier that is an address, assembled from parts at test time as in US-WL01, into the synthetic store; an out-of-set `source` would only be normalized) and rerun; confirm the previous file is unchanged.
  4. Point the output at a path inside the RepToday checkout, then at a symlink that resolves into it.
  5. Interrupt a run between the temporary write and the rename, then start a new run.
  6. Under double opt-in, confirm the unconfirmed sign-up and rerun.
  7. Under OQ1 Option A, add a synthetic sign-up with no identifier and start two runs at once.
  8. Start a run; while it is running, remove a synthetic sign-up and start the run a removal triggers (as US-WL10's removal does); let every run finish; then run the producer as the next scheduled run would.
- **Expected Result:** Step 1 produces a view the checker and the reader accept, with one entry per sign-up except the unconfirmed one under double opt-in, the out-of-set sign-up written as `fit` `null` and `source` `unknown`, the sign-up without an identifier given one that is written back to the store, and the entries in ascending `signed_up_on` (the two same-day entries in entry-identifier order); step 2 drops exactly the removed entry and keeps every other identifier, the newly assigned one included; step 3 exits non-zero, leaves the earlier bytes untouched and prints no value; step 4 refuses both with a clear message; step 5 leaves either the complete old file or the complete new file, never a partial one, and the new run completes; step 6 lists the newly confirmed sign-up with `signed_up_on` still its submission date; step 7 gives that sign-up exactly one identifier, the same in the store and in every view written; step 8's first view generated from a store read after the removal, no later than that run, omits the removed sign-up.
- **Failure Indicator:** The file holds a field beyond the five, the entries follow the store's order rather than `signed_up_on` then entry identifier, an unconfirmed sign-up is listed under double opt-in, an identifier is reassigned or minted only in memory, step 2's rerun still lists the removed sign-up, step 8's first view generated from a store read after the removal, no later than its final run, holds the removed sign-up, an interrupted run blocks a later one, an address-shaped string is written, a failing check still replaces the file, a path inside a work tree is accepted, or a partial file is ever visible.

### US-WL08: The address boundary guard

**Description:** As the captain, I want mechanical checks that no email-service credential and no address export can land in the gr0wthlab, Mandu or RepToday checkouts, so that the boundary holds even when someone forgets it.

**Acceptance Criteria:**

- [ ] `tools/check-no-waitlist-credentials.py` (CI, in the style of `tools/check-no-committed-telemetry-secret.py`) fails when a tracked or untracked-but-not-ignored file in the RepToday checkout contains: an assignment of a literal value to a name used for an email-service credential, or to a header named for one (the names, including the email service's own API-key header, listed in the tool); any bearer or API-key header with a literal value in the Waitlist's own paths (`gtm/03-site/`, `tools/waitlist/` and any other path a Waitlist story adds); a subscriber-export file (any CSV, TSV, JSON or JSONL file with a column or field named for an email address that holds even one email-shaped address not on the allowlist, however few rows it has); or an email-shaped string not on the allowlist.
- [ ] "Email-shaped" means a whole address: a local part of letters, digits and `._%+-`, an `@`, and a dotted domain whose last label is two or more letters.
  The address rules read only text files (files that decode as UTF-8 and contain no NUL byte); committed images such as the Trainer pose art hold address-shaped byte runs by chance.
  It is narrower than the reader's any-`@` rule on purpose: that rule, which US-WL01's view checker keeps for the view, would flag every scoped package path in `package-lock.json` and `proxy/package-lock.json`.
- [ ] The allowlist is the policy's published contact address, addresses at the reserved `example` domains used by existing tests, and two existing URL-userinfo test inputs, each allowed only in its own file: the `user:password@` inputs before the App Store Server API hosts in `proxy/test/apple-fetch.test.js`, and the `user@` input before the Coach host in `ios/RepToday/RepTodayTests/CoachProxyClientConfiguredTests.swift`.
  The two file-pinned entries apply to no other file, so no Waitlist path gains an exemption.
  The existing `Bearer` test fixtures (`CoachProxyClientTests.swift`, `ProxyVarietyLanguageProviderTests.swift` and `CoachRuntimeAuthenticationTests.swift` in `ios/RepToday/RepTodayTests/`; `coach-auth-worker.test.js` and `coach-staging-labels.test.js` in `proxy/test/`) name no email-service credential and lie outside the Waitlist paths, so they pass without an entry.
- [ ] A finding names the file and line and never repeats the value.
- [ ] Non-vacuity is shown the way the repository does it: adding a credential-shaped assignment, then an export file, then an address, each makes the check fail with a message naming its own rule; removing them makes it pass.
- [ ] `tools/waitlist/audit-checkouts.sh <directory>...` is a read-only audit the founder can point at the gr0wthlab, Mandu and RepToday checkouts; it prints file names and counts only and is run at go-live (US-WL12).
  It reads what the sandbox reads, the directory itself, not git's file list, so each rule states its file scope.
  In every directory, the guard's credential rules scan every file, git-ignored or not, skipping only `.git`, so a key kept in an ignored file (such as a root `.env`) is found.
  In every directory, the guard's export rule scans the same files except installed dependency folders (`node_modules/` and a Python virtual environment), whose third-party package metadata carries maintainers' addresses.
  On the RepToday checkout it lives in, it also applies the guard's address rule, with the guard's allowlist, to the text files in the guard's own file list (tracked, or untracked and not ignored).
  On any other directory it applies no address rule, because single address strings are not what the request forbids there and the gr0wthlab checkout's own tests and examples hold them; an export there is still caught by the export rule, which needs no row count, so even a one-row export is reported.
- [ ] The only places a credential may live are the macOS Keychain and the hosting or email provider's own secret store; the Keychain item names (service and account, in the style of `tools/telemetry-keychain.sh`) are documented, values never.
- [ ] The view producer's refusal to write inside a work tree (US-WL07) is covered by a test cited here.
- [ ] The RepToday side is the only side this PRD can enforce; the matching rule for the other two checkouts is stated as gr0wthlab's Guardrail G6 and verified read-only by the audit's credential and export rules, with no change made to either.

**Validation Test:**

- **Setup:** The branch, with US-WL03 merged; a scratch copy of the working tree for the sabotage steps.
- **Steps:**
  1. Run the check on the clean tree.
  2. In the scratch copy add, one at a time: a literal credential assignment, a CSV export file with a single address-shaped row (assembled from parts), a stray address, and a binary file (holding a NUL byte) carrying the same address-shaped bytes.
  3. Run the audit against the RepToday checkout, and against a scratch directory seeded with step 2's credential, export and stray address.
  4. Create a new git-ignored file holding a literal credential assignment in the RepToday checkout (for example a root `.env`, which `.gitignore` ignores, when none exists yet), run the audit against the checkout again, then delete that new file.
- **Expected Result:** Step 1 passes, including over the existing proxy and iOS test fixtures named above; each step 2 sabotage except the binary file fails the check with a file-and-line message that holds no value, the binary file is skipped while the same bytes as a stray address in a text file fail, and the export case's message names the export rule (its address would also trip the address rule, so failing alone proves nothing); step 3's audit reports zero findings on the real checkout and, on the scratch directory, the credential and the export but not the stray address, naming files and counts only; step 4's audit reports the credential in the ignored file, by name and without its value.
- **Failure Indicator:** A planted credential, export or address passes the check, a message echoes a value, the audit misses a credential (in an ignored file or not) or an export, flags a lone address outside the RepToday checkout, or writes anything.

### US-WL09: Send-time lookup on the founder's side

**Description:** As the founder, I want to turn an entry identifier into a reachable sign-up only when I am sending, so that gr0wthlab can pick people by identifier and I can email them without any address ever being written down.

**Acceptance Criteria:**

- [ ] A tool under `tools/waitlist/` supports two modes on the founder's Mac: `tag <label> <entry>...`, which marks the named sign-ups inside the email service so a broadcast to that label needs no address to leave the service, and `show <entry>`, which prints one address to the terminal.
- [ ] `show` prints only when standard output is an interactive terminal, refuses a pipe or a redirect, never writes an address to disk and never logs one.
- [ ] An unknown or malformed identifier is an error naming the identifier, not an empty result.
- [ ] A batch of entry identifiers at least as large as gr0wthlab's configured Beta Cohort invitation batch (20 at this date) is handled in one call.
- [ ] The tool reads its credential from the Keychain (US-WL08), and the tool and its tests live in the RepToday checkout without any credential or address.
- [ ] The runbook (`docs/` or `tools/waitlist/README.md`) states the send-time path: gr0wthlab's Review Queue item names entry identifiers; the founder runs `tag`; the founder sends from the email service to that label.
- [ ] The Waitlist send path always includes the unsubscribe link (US-WL10).

**Validation Test:**

- **Setup:** Three test sign-ups in the test destination (US-WL06).
- **Steps:**
  1. Run `tag beta-test <entry> <entry>` for two of them; open the email service's test list for that label.
  2. Run `show <entry>` in a terminal, then again as `show <entry> > out.txt` and `show <entry> | cat`.
  3. Run `tag` with an identifier that does not exist.
  4. Search the tool's logs and the working tree for the test addresses.
- **Expected Result:** Step 1 shows exactly the two sign-ups under the label; step 2 prints once to the terminal and refuses both redirected forms; step 3 errors by name; step 4 finds nothing.
- **Failure Indicator:** An address reaches a file, a log or a pipe, a missing identifier silently succeeds, or the tool needs a credential stored in a file.

### US-WL10: Removal and retention

**Description:** As a person on the waitlist, I want to be removed when I ask and not be kept past launch, so that my address does not linger.

**Acceptance Criteria:**

- [ ] Every waitlist email (launch and beta, and the confirmation message if OQ5 settles on double opt-in) carries an unsubscribe link; a test message through the email service shows it (a configuration check, not a code change, if the service adds it).
- [ ] A removal request by unsubscribe link or by a message to reptoday.app@gmail.com results in the sign-up and its answers being **deleted** (not merely marked unsubscribed) within 7 days of the request.
- [ ] A `remove` command removes one sign-up by entry identifier or by an address typed at a prompt (never an argument), and a daily sweep deletes every sign-up the email service reports as unsubscribed.
- [ ] The founder records the launch-email date once, in a small state file outside every checkout (`record-launch-email --sent-on YYYY-MM-DD`, OQ13); the retention sweep deletes every remaining sign-up on or after that date plus 30 days.
- [ ] Both sweeps default to a dry run that prints counts, take an injected `asOf` clock in their date logic, and log counts only.
- [ ] Both sweeps run live in the daily scheduled job, before the producer run OQ4 chains after them, so a sign-up past the launch-email date plus 30 days is deleted on the first daily run on or after that day; the evidence records that the installed schedule invokes both sweeps without the dry-run default.
- [ ] Deleting a sign-up is followed by a view regeneration, so a removed sign-up leaves the file on the next generation that reads the store after its removal, and by the next scheduled run at the latest.
- [ ] The runbook states who watches the contact mailbox and how often (recommended: at least every 5 days while the waitlist is open) so the 7-day promise is operationally real, and what the founder does for a request that names an address not on the list.
- [ ] A deletion never touches a different person's record (the match is exact on the address or the entry identifier).

**Validation Test:**

- **Setup:** The test destination with four test sign-ups, each confirmed if OQ5 settles on double opt-in, and a view generated from it before any removal; an injected clock; the producer from US-WL07.
- **Steps:**
  1. Unsubscribe one test sign-up through the service's test unsubscribe link; run the daily sweep with `asOf` one day later.
  2. Request removal of a second by simulating a mailbox request; run `remove` for it.
  3. Record a launch-email date; run the retention sweep with `asOf` at launch plus 29 days, then plus 30 days.
  4. After each deletion regenerate the view and run the checker.
  5. Add a fifth test sign-up (confirmed under double opt-in) and unsubscribe it; make a view-producer run hang; then run the daily sweep; then run the producer as the next scheduled run would.
- **Expected Result:** The view generated before any removal lists all four; step 1's sign-up is deleted from the store and absent from the next view; step 2's likewise; step 3 deletes nothing at +29 and every remaining sign-up at +30; step 4's views never contain a removed entry, and the last view has `"entries": []`; step 5's sweep deletes the sign-up and exits, the hung run ends within its bound without writing, and the first view generated from a store read after the removal, no later than that run, omits the deleted sign-up.
- **Failure Indicator:** The view before any removal does not list all four, a hung run stalls the sweep, outlives its bound or writes a view, or step 5's first view generated from a store read after the removal, no later than its final run, holds the deleted sign-up, a removed sign-up stays in the store or the view, a sweep deletes before +30 or fails to delete at +30, a dry run deletes, or the wrong person's record is touched.

### US-WL11: The privacy policy's Waitlist section

**Description:** As a visitor deciding whether to join, I want the privacy policy to say plainly what the waitlist keeps, why, for how long, and how to be removed, so that I can decide with the facts.

**Acceptance Criteria:**

- [ ] `reptoday.app/privacy` has a Waitlist section, in place of the waitlist sentences of section 10, saying in the policy's plain voice:
  what is collected (the email address; the answer to the routine question; whether you asked for a beta invitation; which Rep Today link brought you, if any; and the sign-up date);
  why (to email you when Rep Today launches; to invite you to the beta, only if you asked; and to count, without your address, which links and which routines bring people);
  how long it is kept (until 30 days after the launch email goes out, or until you ask to be removed, whichever comes first);
  how to be removed (the unsubscribe link in any waitlist email, or a message to reptoday.app@gmail.com; your sign-up and answers are then deleted within 7 days);
  and who sees your address (only the founder, when sending a waitlist email, and the service that stores it for Rep Today; it is never sold or shared).
- [ ] The wording is the approved draft in Appendix C, edited by the captain, and makes no promise beyond the five points and what OQ5 and OQ10 add.
- [ ] Structure, numbering, the table of contents, the anchor and the "This website is static" note follow OQ10; no cross-reference to a renumbered section is left stale.
- [ ] "Last updated" carries the publication date.
- [ ] Every sentence in the section is traced to the mechanism that makes it true (a table in the evidence: "the unsubscribe link in any waitlist email" -> US-WL10 and the US-WL06 spike's confirmation-message result; "within 7 days" -> US-WL10; "30 days after the launch email" -> US-WL10; "only the founder ... and the service that stores it" -> OQ1's design; "without your address" -> US-WL07).
- [ ] The existing draft banner, header comment and legal-review flags stay; the section is flagged for the same legal pass, and section 12's flag about the missing retention schedule is updated to say what now exists and what is still unreviewed.
- [ ] The section is published no later than the form (US-WL12 orders the deploy).
- [ ] Verify in browser with `chrome-devtools-axi` at 390 px and 1440 px.

**Validation Test:**

- **Setup:** The local site.
- **Steps:**
  1. Open `/privacy` at 390 px; follow the table-of-contents link for the Waitlist section; read it against the five points.
  2. Evaluate that the page contains "30 days", "7 days" and the contact address, and no longer contains the Kit sentence from section 10.
  3. Follow every "section N" reference on the page.
  4. Repeat at 1440 px.
- **Expected Result:** The five points appear in order and in plain language; the anchor and contents entry work; no reference points to the wrong section; the page has no horizontal scroll at 390 px.
- **Failure Indicator:** A point is missing or softened, a commitment appears that the design does not keep, a stale cross-reference survives, or the old Kit sentence remains.

### US-WL12: Go-live rehearsal and evidence

**Description:** As the captain, I want the whole path rehearsed end to end, on the real site, with my own test sign-ups, before anything public points at it, so that the first real sign-up behaves exactly as promised.

**Acceptance Criteria:**

- [ ] The full flow passes on the local site and stub (all earlier stories' Validation Tests rerun).
- [ ] With the captain's approval, the site is deployed to a Cloudflare Pages preview first and the Source-link casings, the fallback behavior and the events are rechecked there; production publication is a separate, captain-approved, credentialed step (as `AGENTS.md` already requires), with the privacy page deployed with or before the form.
- [ ] The rehearsal reproduces gr0wthlab's own acceptance test for the Waitlist: the founder signs up once through the TikTok link and once with no tag, in a fresh browser tab that has opened no Source link (with addresses the founder owns), confirms both addresses if OQ5 settles on double opt-in, the view is produced and read with the reader's own checks (and `check-view.py`), and the privacy page is opened.
- [ ] Both rehearsal sign-ups appear with Sources `tiktok` and `unknown`, the Fit answers and beta choices as entered, and no address anywhere in the file; both page views and both sign-ups are counted in the sink; the privacy page has the Waitlist section.
- [ ] The rehearsal then removes both sign-ups, one by the unsubscribe link and one by a message to the contact mailbox, and both leave the store and the next view.
- [ ] `tools/waitlist/audit-checkouts.sh` is run read-only against the gr0wthlab, Mandu and RepToday checkouts and reports nothing: no email-service credential and no export that holds addresses in any of them, git-ignored files included, and no address outside the guard's allowlist in the RepToday checkout (US-WL08, with each rule's file scope as stated there).
- [ ] The evidence (`artifacts/reports/US-WL12/validation.md`) contains screenshots at 390 px and 1440 px, the commands and results above, the view's path and format version, the rehearsal's start and end times (so its event rows can be excluded from the conversion), and **no address**.
- [ ] A short hand-off note states the file's path and the go-live date for the gr0wthlab follow-up (Dependencies, item 1); this story makes no change in gr0wthlab or Mandu.
- [ ] `AGENTS.md` (a pointer entry only), `CONTEXT.md`, `gtm/03-site/DEPLOY.md`, `convex/README.md` (if US-WL05 used Convex), `docs/implementation-log.md` and `docs/test-coverage.md` are updated, and this PRD's status header and checkboxes are brought current.

**Validation Test:**

- **Setup:** Every earlier story merged; the captain's approval for the preview and production deploys; two addresses the founder owns.
- **Steps:**
  1. Follow the acceptance criteria in order, recording evidence at each step.
  2. Run the reader cross-check and `audit-checkouts.sh`.
  3. Compare the hand-off note with gr0wthlab's configuration fields it must fill.
- **Expected Result:** Each criterion passes with evidence, the reader's verdict is "read" with the two rehearsal entries among the view's entries (beside any existing sign-ups, such as those OQ6 keeps), and then the same view without them, the audit is clean, and the hand-off note names the path and date.
- **Failure Indicator:** The reader refuses or fails the view, a Source is lost, a removed sign-up lingers, the audit finds a credential or an export that holds addresses (in an ignored file or not), or an address outside the guard's allowlist in the RepToday checkout, or any rehearsal step used the production list outside the agreed addresses.

## Functional Requirements

**Sign-up form**

- FR-1: Every sign-up placement must show exactly one call to action, the heading "Join the waitlist" and the sentence "Add your email and we'll tell you the day it ships."; neither page may ask the visitor for a download, a follow or a share.
- FR-2: Where the form appears more than once, on a page or across `index.html` and `index-b.html`, it must be the same form, differing only in element ids.
- FR-3: The form must have three fields and no others; beyond them it may carry only the visit's Source tag, which the visitor is never asked for.
- FR-4: The Email field must be required.
- FR-5: The Fit question "Which sounds most like you?" must offer exactly "I used to work out and lost the routine" (`lost-the-routine`), "I work out regularly" (`exercises-regularly`) and "I've never had a routine" (`never-had-a-routine`), with no answer pre-selected on load, reload or back-navigation, and an answer required to sign up.
- FR-6: The box "Invite me to the beta before launch" must be unticked until the person ticks it, on load, reload and back-navigation.
- FR-7: Wherever the pages promise "one message", they must instead say "one launch email, plus a beta invitation only if you ask for one", and "one message" must appear nowhere.
- FR-8: The form must not ask how the person heard about Rep Today.
- FR-9: The form must show distinct, accessible in-progress, success, validation-error and submission-error states without losing entered values (wording per Appendix B).

**Source**

- FR-10: `reptoday.app/tiktok`, `/youtube`, `/reddit` and `/network` must each open the sign-up page; the lowercase word after the slash is that visit's Source tag.
- FR-11: The links must work in any letter case.
- FR-12: Each link must be the bare tag, short enough to say aloud, type or put in a profile.
- FR-13: A visit that arrived by one of the links must keep that Source while the visitor looks around the site, per OQ3, and the sign-up must carry it.
- FR-14: Every other arrival must be Source `unknown` for the sign-up and `none` for the events; only the four tags are ever recorded as a tag.
- FR-15: The four tags must live in one list; a new Source requires a new Dispatch request and a reviewed gr0wthlab change.

**Web events**

- FR-16: `landing_page_view` must be emitted on every load of either landing-page document, whatever path served it, and never on `/privacy`, with the property `referrer_source` and no other.
- FR-17: `waitlist_signup` must be emitted when an email is submitted (OQ8), with the property `referrer_source` and no other.
- FR-18: `referrer_source` must be the visit's tag or `none`.
- FR-19: Neither event may carry the email address, the entry identifier, or any other identifier of the visitor or device.
- FR-20: Emission must never block, delay or fail the page or the sign-up, and must not run from `localhost`, a preview or a test against the production sink, apart from the captain-approved US-WL12 rehearsal.
- FR-21: The sink must accept only these two names with exactly that property bag and must leave the app's `POST /logEvent` contract unchanged.

**Records and entries**

- FR-22: A stored sign-up must hold the address, the Fit answer or none, the beta choice, the Source, the sign-up date and the entry identifier, plus only the status the sending service requires.
- FR-23: The entry identifier must be random (cryptographically secure), 1 to 64 letters, digits, `-` or `_`, unique, stable while the sign-up exists, stored with the sign-up, and never derived from the address (not a hash, not an encoding).
- FR-24: `signed_up_on` must be the sign-up's date in UTC and must not change on resubmission.
- FR-25: A repeated submission of an address already on the list must not create a second entry (OQ11).
- FR-26: Confirmation of the address must follow OQ5, and only sign-ups the design counts must appear in the view.

**The anonymous view**

- FR-27: The view must be UTF-8 JSON whose top level is exactly `view` (the integer `1`), `generated_at` and `entries`.
- FR-28: Each entry must be exactly `entry`, `source` (`tiktok`, `youtube`, `reddit`, `network` or `unknown`), `fit` (one of the three tags, or `null` only for a sign-up that holds no answer), `beta_opt_in` (`true` or `false`) and `signed_up_on` (`YYYY-MM-DD`); a stored value outside these sets is written as `unknown` or `null`, never as stored; entries are written in ascending order of `signed_up_on`, then entry identifier, because the reader's invitation order falls back to the view's own order.
- FR-29: `generated_at` must be the time the file was written, with its UTC offset, and no `signed_up_on` may be later than its UTC date.
- FR-30: The view must hold nothing else: no address, name or other field, and no string, key or identifier anywhere in it that looks like an address or decodes to one.
- FR-31: A removed or retention-expired sign-up must be absent from the next generation that reads the store after its removal.
- FR-32: The file must be written atomically, owner-only, within 10,000,000 bytes, and must never replace a good file with one that fails the checker.
- FR-33: The file must lie outside the gr0wthlab, Mandu and RepToday checkouts and outside every git work tree, and the producer must refuse any other path.
- FR-34: The view must be produced on the cadence and at the location settled in OQ4; the reader reads it read-only at each weekly run with no network.
- FR-35: The path and field names must be recorded in one document for the gr0wthlab follow-up.

**Address boundary**

- FR-36: An entry identifier must be turned into an address only on the founder's side, at send time, in RepToday's storage or the email service.
- FR-37: No email-service credential may be placed in the gr0wthlab, Mandu or RepToday checkouts; credentials live in the Keychain or the provider's secret store.
- FR-38: No export that holds addresses may be placed in those checkouts, and RepToday's CI must fail if a credential, an export or an unlisted address is committed.
- FR-39: Only the founder (when sending) and the storing service may see an address, and the privacy policy must name that service truthfully (OQ1).

**Removal and retention**

- FR-40: Every waitlist email, including the confirmation message if OQ5 settles on double opt-in, must carry an unsubscribe link.
- FR-41: A message to reptoday.app@gmail.com must be an accepted way to ask for removal.
- FR-42: A removal must delete the sign-up and its answers within 7 days of the request.
- FR-43: A sign-up must be deleted when it has been kept until 30 days after the launch email went out, or earlier on removal, whichever comes first.
- FR-44: The launch-email date must be recorded once by the founder, outside every checkout, and the retention sweep must read it.

**Privacy policy**

- FR-45: `/privacy` must have a Waitlist section, in place of the waitlist sentences of section 10, that states the five approved points, published no later than the form, with "Last updated" revised.
- FR-46: The policy must describe the page's anonymous counts as OQ10 settles.

**Quality**

- FR-47: Every web surface must work at 390 px and 1440 px with no horizontal scroll, 44 px minimum controls, 4.5:1 contrast, visible focus, labelled controls and keyboard-only completion.
- FR-48: CI must run the site checks (US-WL03), the view checker tests (US-WL01) and the boundary guard (US-WL08) without Xcode or secrets.
- FR-49: Deployment of the site, the sink and any scheduled job to the founder's Mac is a separate, captain-approved step; the repository holds no credential for any of them.

## Non-Goals (Out of Scope)

- No new Source tag, Fit answer, form field, event property or view field beyond the request, and no UTM handling (OQ12).
- No change to the iOS app, the deterministic engine, the 13 app telemetry events, the Coach, the paywall or `POST /logEvent`'s contract.
- No A/B bucketing change; the two page variants stay as they are apart from the waitlist blocks and the sentences US-WL03 names.
- No Content-Security-Policy authoring, even though dropping the Kit embed (if OQ1 does) removes the reason it was omitted; flagged as a follow-up in `DEPLOY.md`.
- No `robots.txt`, sitemap or 404 behavior change; V15 notes that both currently return the landing page.
- No analytics dashboard, count or chart inside RepToday; the Marketing Engineer's counts are gr0wthlab's.
- No automatic sending: the founder sends the launch email and the beta invitations.
- No export of addresses to any other system, and no sync of addresses beyond the one storing service.
- No account, login, referral link, share prompt or reward for the waitlist.
- No closing of the waitlist or App Store link at launch; that is a later change when the app ships.
- No change in gr0wthlab or Mandu; the follow-up is a dependency (below).
- No change to Kit, DNS, Cloudflare or any hosted service by this PRD; every such step is the captain's and is named in Dependencies.

## Design Considerations

- **Look.** Reuse the page's Paper tokens (`--paper`, `--ink`, `--slate`, `--moss`) and the existing `.waitlist` card (342 px wide at 390 px, as measured on the live page); the closing band keeps the light card on the Night background, as today.
  An error state needs a color with 4.5:1 contrast on Paper; add it as a token rather than hardcoding it.
- **Tone.** Site copy follows the project voice: identity-framed, plain, never loss-framed ("don't miss out" is out).
  The approved strings are fixed; the new strings in Appendix B are proposals for the captain.
- **Low pressure.** One call to action, one question, one optional box; the box is unticked and the form never blocks on it.
- **Accessibility.** Native `fieldset`/`legend` and labels, programmatic error association, a polite live region for status, 44 px controls, visible focus.
  Radios and checkbox must not be restored to a checked state by the browser after a reload.
- **No second path.** The `<noscript>` mailbox join and any "email us to join" copy are removed; a visitor without script gets either a native form post (if OQ1 allows) or a plain statement that the form needs script.
- **Source is invisible.** The visitor sees no Source label and is never asked; the tag travels in a hidden field and in the events.
- **Evidence.** Screenshots at 390 px and 1440 px for the hero and closing placements, success and error states, the Source links and the privacy section, all with synthetic data.

## Technical Considerations

- **Static site, no build.** `DEPLOY.md` says the site is pure static HTML with inline CSS and no build step; four copies of the form markup are kept identical by a check (US-WL03) rather than a build step, unless OQ2 introduces a Function.
- **Tooling.** New operator tooling lives in `tools/waitlist/` as Python 3 standard-library scripts with `unittest` tests (precedent: `tools/check-trainer-art.py`, `tools/test-check-trainer-art.py`), adds no package, and is public-safe: it holds no credential and no address.
- **CI.** The existing `sink` job (Ubuntu) already runs Node tests for `convex/`; a small additional job (or steps) runs the Python site, view and guard checks without Xcode.
  No test needs a secret or the network.
- **Local run.** `npx wrangler pages dev gtm/03-site --port 8788` serves the site with `_headers`, `_redirects` and the Pages fallback.
  Behavior that emulation does not reproduce is verified on the preview deploy in US-WL12.
- **Browser requests.** A simple cross-origin `POST` (a `text/plain` body, no custom header) needs no preflight; the PRD does not require CORS handling for the events, and forbids reusing the app's secret header on a public page.
  Whether the sign-up submission can be read by the page depends on the destination (the US-WL06 spike).
- **Producer scheduling.** A per-user `launchd` agent on the founder's Mac is the recommended runner (OQ4); the plist template lives in the repository, installation is the captain's, and credentials come from the Keychain at run time.
- **Time.** All dates in the view are UTC; the founder's weekly sitting is on the Mac's local clock, so a sign-up late on a Sunday evening local time can carry Monday's UTC date, which the reader already counts as the following week.
- **Conventions.** Pure date logic takes an injected `asOf`; new story rows go in `docs/test-coverage.md`; new facts go in `docs/implementation-log.md`.

## Hard to change after go-live

These become expensive once the Waitlist is live or the first link is posted, so they are settled and reviewed before US-WL12.

| Item | Why it is hard to change | Who must change it |
| --- | --- | --- |
| The four Source links and tags | The links are in profiles, bios and video descriptions; the tags are in gr0wthlab's `source_tags` and in stored sign-ups | A new Dispatch request, this site, a reviewed gr0wthlab change |
| The Fit answer tags | Stored with every sign-up; in gr0wthlab's `fit_answers` and `good_fit` | Same as above |
| The view's field names, types and version | The reader accepts exactly the five entry keys and `view` 1 | A new `view` version plus a reviewed gr0wthlab change |
| The view's file path | gr0wthlab's `config/products.json` records it | A reviewed gr0wthlab change |
| Entry identifiers | gr0wthlab's Waitlist Evidence keeps them week over week, and the send-time lookup depends on them | Never regenerate; the store keeps them |
| The privacy wording, once published | People join on the strength of it; 7 days and 30 days are public commitments | The captain, with the legal pass |
| The event names and `referrer_source` vocabulary | The conversion metric is pre-registered, and the schema says it must not be edited to move a threshold after data starts arriving | The captain, in Mandu's schema |
| The web-event route URL (if Convex) | It is embedded in every page | A site deploy |
| Stored field keys in the sending service (if Kit stays) | Renaming loses data | A migration |

## Success Metrics

- Zero address-shaped strings in every generated view: the producer refuses to write one, and the first live view is read by gr0wthlab's reader as a normal read, not a failed or refused one.
- All five arrivals (the four links and plain `reptoday.app`) give the form the right hidden Source value in US-WL04's Validation Test, with the four links rechecked on the preview: 5 of 5; and the rehearsal's two stored sign-ups carry `tiktok` and `unknown`: 2 of 2.
- The rehearsal's removal leaves the store and the next view in one sweep, and the commitment of 7 days has measured headroom (the daily sweep plus a stated mailbox cadence).
- `landing_page_view` and `waitlist_signup` rows exist for the rehearsal, inside its recorded time window, with only `referrer_source`, so the pre-registered conversion (`waitlist_signup` divided by `landing_page_view`, split by `referrer_source`) can be computed.
- The privacy policy's Waitlist section is live before the form, and every sentence in it is traced to a mechanism.
- The audit of the three checkouts finds zero credentials and zero address lists.
- If Kit's embed script is dropped (OQ1 option A), the landing pages load one fewer third-party script and set no `ckid` storage key.

## Dependencies

1. **gr0wthlab follow-up (after this build, not a story here).**
   gr0wthlab needs one reviewed change that records the view's path in `config/products.json` (`waitlist.view.local_path`) and the go-live date in `config/run.json` (`waitlist.live_since`, to be set "once US-ME05's Validation Test has passed on reptoday.app").
   Until it lands, every post stays "can't publish yet".
   US-WL12 produces the hand-off note; the change itself is gr0wthlab's.
2. **Captain actions** (none is done by this PRD or by a crewmate): settle Open Questions 1-14; read the live Kit account's confirmation setting and sign-up count (V13); create any credential in the Keychain; approve the preview and production deploys of the site and, if used, the Convex sink; install the daily scheduled job on the Mac (both US-WL10 sweeps, then the producer); run the legal pass the privacy page already requires; commit to the mailbox cadence in US-WL10.
3. **Mandu** owns the event-metric schema; if the captain wants its "utm or none" wording aligned with the request's "tag or `none`", that edit is outside RepToday.

## Open Questions

**Settled 2026-10-19.**
The captain's words: "Waitlist - go with your recommendations".
Every marked recommendation below is accepted:

- OQ1: Option A (Kit stays, a first-party form posts to Kit, a producer on the founder's Mac assigns entry identifiers).
- OQ2: (a) stay on Cloudflare Pages, static.
- OQ3: (a) per-tab last-touch among the four links; a plain path keeps an existing tag; a trailing slash counts as the same link.
- OQ4: (ii) a daily `launchd` run that also runs after each sweep, plus on demand, writing `~/Library/Application Support/RepToday/waitlist/waitlist-view.json`, owner-only.
- OQ5: double opt-in; only confirmed sign-ups in the view.
- OQ6: (a) keep existing Kit sign-ups as Source `unknown`, Fit `null`, beta `false`.
- OQ7: (a) a new, separate `POST` route for web events.
- OQ8: `waitlist_signup` fires once per accepted submission.
- OQ9: Appendix B's wording.
- OQ10: (a) a new privacy section "The waitlist".
- OQ11: no second entry; the latest Fit and beta choice win.
- OQ12: `utm_*` parameters do not set the Source.
- OQ13: `record-launch-email --sent-on`.
- OQ14: (a) date-only order.
- US-WL06 spike findings (2026-10-20, `artifacts/reports/US-WL06/spike.md`), each recommendation accepted:
  D1 the view producer keeps a local owner-only ledger (Kit subscriber id to entry identifier) and trusts only it, because a public post can set Kit's `entry` field;
  D2 Kit's API cannot delete a subscriber, so the sweeps unsubscribe, overwrite the email with a placeholder and blank every field within a day, and the privacy wording keeps "deleted";
  D3 a same-day resubmission overwriting the first Source is accepted;
  D4 the form hosts Kit's reCAPTCHA guard iframe when Kit answers `quarantined` (origin-checked), and the privacy section names reCAPTCHA via Kit.

Each question lists the realistic options grounded in the current code and services, the **recommendation (marked)** with its reason, and the stories it gates.
Behavior that this PRD could not verify from the repository (marked "confirm") is checked, not assumed: the sending service's in the US-WL06 spike, and the scheduler's in US-WL07.
With OQ1 and OQ5 settled, the build notes for the chosen options ("under Option A", "under double opt-in" and the like) now apply; the build re-verifies the chosen option's design in full.

### Left to RepToday by the request

**OQ1. Storage - and does Kit stay?**

The store must hold the address, the Fit answer, the beta choice, the Source, the sign-up date and the entry identifier; send the launch email and the beta invitation with an unsubscribe link; delete on removal and at retention; let the producer read the five anonymous fields without the address; and keep every credential out of the checkouts.

- *Option A - Kit stays as the only store and sender, behind a first-party form.*
  The page's own HTML form (replacing Kit's embed script) posts from the visitor's browser straight to Kit's public sign-up endpoint, the same one the embed uses today (V2), carrying the Fit answer, beta choice and Source as Kit custom fields.
  The producer on the founder's Mac assigns each new sign-up its random entry identifier, writes it back as a custom field, and reads the five fields through Kit's API with a credential held in the Keychain.
  Pros: the address never touches any Rep Today-run infrastructure, so the approved sentence "only the founder, when sending a waitlist email, and the service that stores it" is literally true; no server code to run; Kit already sends mail, hosts the unsubscribe link and handles bounces; the smallest change from today.
  Cons: "an answer is required to sign up" is enforced only in the page, so a direct post could arrive with no Fit answer (the view's `null` exists for exactly that, and the producer normalizes out-of-set values); the producer needs a full-power Kit credential on the Mac (acceptable on the founder's side, but not scopable to anonymous fields); Kit's unsubscribe is believed to mark a subscriber unsubscribed rather than delete it, so "deleted within 7 days" needs the sweep in US-WL10, and whether its API can permanently delete one is unverified (confirm both in the spike); a first-party post to Kit's endpoint with custom fields, and whether the browser can read its result, is not an integration this PRD could verify from the repository (confirm in the spike); the entry identifier is a custom field on the same public endpoint, so a direct post might set or overwrite it, planting a value derived from an address or a copy of another sign-up's identifier (confirm in the spike; if it can, the captain decides how the producer keeps identifiers its own before US-WL07); and the producer sees the store only when it runs, so if a resubmission overwrites stored fields, one made before the producer's next run can replace a first sign-up's Source before the producer has recorded it (OQ11; confirm in the spike); and no Rep Today code stamps the date, so `signed_up_on` can come only from a creation time Kit keeps and a resubmission does not reset (confirm in the spike; if it cannot, the captain decides how the date is kept).
- *Option A2 - Kit stays, with a small Cloudflare Pages Function in front of it.*
  The Function validates the post (answer required, tags checked, bot protection), mints the entry identifier at sign-up, forwards to Kit with a Kit credential held as a Cloudflare secret, and may write an address-free row to its own store so the producer never needs Kit's credential.
  Pros: server-side enforcement; identifiers minted once, in one place; the producer's credential can be limited to the anonymous store.
  Cons: Cloudflare's code handles each address in transit, which makes "only the founder ... and the service that stores it" no longer literally true, so the captain would have to approve an amended sentence naming the relay; server code that handles personal data; the site stops being pure static.
- *Option B - an own store (Cloudflare D1 behind Pages Functions), Kit retired.*
  Cons: needs a new sending service with unsubscribe and bounce handling, which is a second service that sees every address and contradicts the approved sentence unless the sender is also the store; the largest build.
- *Option C - Convex.*
  Rejected: the sink's contract is "no identity in any event", its deployment is limited to the `events` and `rateLimits` tables (V18), and storing addresses there would break both.

**Recommendation: Option A** (Kit stays; first-party form; producer assigns identifiers), because it keeps the approved "who sees your address" sentence literally true and adds no new place that handles addresses.
Fall back to **A2** only if the US-WL06 spike shows Kit's endpoint cannot carry the fields or cannot be read by the page; that fallback needs the captain's approval of the amended sentence.
If the spike shows Kit exposes no creation time a resubmission leaves alone, the captain decides how `signed_up_on` is kept under Option A, and under every option how OQ6's existing sign-ups keep their original dates, before US-WL06 and US-WL07 are built.
Gates: US-WL02, US-WL06, US-WL07, US-WL08, US-WL09, US-WL10, US-WL11.

**OQ2. Hosting.**

- *Option a - stay on Cloudflare Pages, static, with `_redirects` and client script.*
  Pros: nothing to migrate, and the deploy procedure in `DEPLOY.md` stays valid.
  Cons: no server-side validation and no real 404s without giving up the fallback the four links currently rely on.
- *Option b - Pages with a Function or `_worker.js`* (case-insensitive routing, real 404s, or A2's relay).
  Pros: server-side routing and validation.
  Cons: a `functions/` directory means the site is no longer pure static, and the deploy gains a build step.
- *Option c - move to another host.*
  Cons: new DNS, TLS and HSTS setup and a rewritten `DEPLOY.md`, with no requirement in the request that another host serves better.

**Recommendation: (a)**, moving to (b) only if OQ1 chooses A2 or OQ3 chooses server-side routing.
Reason: the domain was bought through Cloudflare and its DNS and HSTS preload are already working (`DEPLOY.md`), the site is pure static with no build, and moving hosts adds risk without helping any requirement.
Which deploy route is live (Wrangler or Git integration) cannot be read from the repository; the captain should say.
Gates: US-WL04.

**OQ3. How a link's Source reaches its sign-up.**

Today any unmatched path already serves the landing page (V15), so the four links open the page; nothing records the tag.

- *Option a - client-side.*
  The page script reads the first path segment, lowercases it, accepts it only if it is one of the four tags, keeps it in `sessionStorage` for the tab, and writes it to the form's hidden field and the events.
  Explicit `_redirects` rewrites make the four links independent of the implicit fallback.
  Pros: no server code; no cookie; no server sees visitor-level data.
  Cons: a Source is lost if the visitor opens a site page in a new tab; it depends on a top-level 404 page never being added; the visitor stays on `/tiktok`, so the visible URL carries the tag and a shared URL mislabels everyone it reaches.
- *Option a2 - option (a), then replacing the visible URL with `/` (`history.replaceState`) once the tag is kept.*
  Pros: everything (a) gives, and a copied or shared address carries no tag, so it labels no one.
  Cons: the address bar no longer shows the link the visitor used; one more step in the page script.
- *Option b - server-side* (a Function or `_worker.js`).
  It normalizes case, sets a first-party cookie or rewrites, and can return real 404s for unknown paths.
  Pros: robust routing.
  Cons: server code, a cookie to disclose, and a site that is no longer static.
- *Option c - redirect to `/?s=tiktok`.*
  Pros: simple.
  Cons: the visible URL carries the tag, so a shared URL mislabels everyone it reaches.

*Persistence sub-question:* when one browser tab session sees more than one listed link, which wins?
First-touch keeps the earliest; last-touch keeps the most recent.
**Recommendation: option (a) with last-touch among the four links, and a visit to plain `reptoday.app` or any other path leaving an existing tag in place for that tab session; a trailing slash (`/tiktok/`) counts as the same link.**
Reason: the request says a sign-up keeps "the Source of the link its visitor arrived by, even after they look around the site", which is the most recent listed link in the visit, and looking around (clicking the wordmark, the FAQ, `/privacy`) must not erase it.
Browser-tab storage also keeps the answer scoped to a visit, so a person returning days later by plain `reptoday.app` is `unknown`, as the request says.
The request names only the four bare links; accepting a trailing slash keeps a typed or pasted slash from losing the Source, and is the captain's call because the request does not settle it.
The fallback depends on no top-level 404 page existing, which US-WL04 guards with a test.
Gates: US-WL04.

**OQ4. How and how often the view is produced, and where the file lives.**

- *Trigger.* (i) on demand only; (ii) a scheduled `launchd` agent on the Mac, plus on-demand; (iii) a push from a server (impossible: the file lives on the Mac and the reader uses no network).
- *Cadence.* The reader runs Sunday 16:00 local, at the first moment the Mac is awake after that, and reports the view's age, so freshness is the producer's job.
- *Location.* Any path outside every checkout and git work tree (FR-33).

**Recommendation: (ii), a daily `launchd` run (a morning time) that also runs after each US-WL10 sweep, plus an on-demand command, writing `~/Library/Application Support/RepToday/waitlist/waitlist-view.json` (directory and file owner-only).**
Reason: a daily run keeps the view at most about a day old at the Sunday read and makes a removal visible within a day, well inside the 7-day promise, because every run ends within US-WL07's bound and every removal is followed, no later than the next scheduled run, by a view generated from a store read made after it; a calendar-interval `launchd` job that the Mac slept through runs when it wakes (confirm in US-WL07); that location is outside every checkout and is not one of the places the sandbox reads.
The file's path is hard to change later because gr0wthlab records it (see "Hard to change").
Gates: US-WL07.

**OQ5. Do sign-ups confirm their email?**

- *Single opt-in.*
  Pros: no extra message; the approved copy ("one launch email, plus a beta invitation only if you ask for one") stays exactly true with no further wording.
  Cons: typos and other people's addresses join the list, a bot can inflate the good-Fit opt-in count that gr0wthlab measures against its bar of about 50, and bounces at launch hurt deliverability.
- *Double opt-in (a confirmation message, then the sign-up counts).*
  Pros: only reachable addresses are counted and invited; it is a cheap filter against bots and typos.
  Cons: one more message that the approved promise does not mention, so the captain must approve a short confirmation line and the policy's "why" list gains "to confirm your address"; and before launch the confirmation message is the only waitlist email a sign-up receives, so the policy's "the unsubscribe link in any waitlist email" depends on it carrying one (a US-WL06 spike item).

**Recommendation: double opt-in, with only confirmed sign-ups listed in the view (their `signed_up_on` is the date they submitted).**
Reason: the Beta Cohort bar counts opted-in good-Fit sign-ups, and an unreachable or fake address is worse than a missing one; the approved sentences stay verbatim.
It needs the captain's approval of the confirmation wording and the policy line (Appendix B and C).
Single opt-in is a defensible alternative if the captain prefers the minimal copy.
Whether the live Kit form already confirms is not visible (V13); the captain should read the setting.
Gates: US-WL02, US-WL06, US-WL07, US-WL11.

### Further design choices

**OQ6. Existing sign-ups made through the current Kit form.**
The count is unknown (V13).
Options: (a) keep them, listed as Source `unknown`, Fit `null`, beta `false`, with their original dates; (b) email them to re-join (an extra message they never agreed to); (c) delete them.
**Recommendation: (a).**
Reason: they joined under "we'll tell you the day it ships" and the policy already told them Kit holds the address; the view's `null` Fit exists for a sign-up that holds no answer; they are never sent a beta invitation because they were never asked.
The same retention and removal rules apply.
Gates: US-WL06.

**OQ7. Where do the web events go?**
Options: (a) a new route on the existing Convex sink; (b) Cloudflare Web Analytics (already injected, V3, but it carries no custom property); (c) a third-party analytics service; (d) Workers Analytics Engine through a Pages Function.
**Recommendation: (a) a new `POST` route, separate from `/logEvent`, with its own two-name allow-list, an exact-property validator, an origin check, a web-sized per-IP rate limit, no use of the app's secret, and rows in the existing `events` table under a reserved non-install `installId` value, written through the route's own internal mutation with a two-name union so `logEvent` and its 13-name union stay as they are.**
Reason: it keeps the data on Rep Today's own endpoint, so section 8's "no third-party analytics" statement stays true; it leaves the app's 13-name contract and tests untouched; it adds no third table (FR-6 of the funnel PRD).
A third table would be the alternative if the captain wants web rows kept apart; that would amend FR-6.
The reserved `installId` must be documented so install-based tooling (`tools/reconcile`) ignores it.
A simple `text/plain` cross-origin `POST` avoids needing any preflight handling.
Gates: US-WL05.

**OQ8. When exactly does `waitlist_signup` fire?**
The request says "when an email is submitted".
Options: on the click; after client validation passes; after the destination accepts it.
**Recommendation: once per submission the destination accepted, never on a validation error or a failed post.**
Reason: counting rejected submissions would inflate the pre-registered conversion; a repeat submission by the same person still counts as a submission.
Gates: US-WL05.

**OQ9. New wording the request did not supply (Appendix B).**
The submit label, the in-progress, success and error strings, the hero's lead-in sentence, the FAQ's "nothing more" sentence and the `<noscript>` text are new or changed words.
**Recommendation: use Appendix B's proposals;** in particular keep "Rep Today is pre-launch and not yet on the App Store." as hero copy above or beside the form (so the form component is identical in all four places and still carries exactly the approved sentence), remove the mailbox join, and have the FAQ name what is kept and point to the policy for why and for how long.
Gates: US-WL02, US-WL03.

**OQ10. How the privacy policy is structured, and how the web counts are disclosed.**
Options: (a) a new section 11 "The waitlist" with `id="waitlist"`, section 10 retitled "This website", sections 11-14 renumbered 12-15 (nothing refers to them by number, V11); (b) keep one section 10 and replace its waitlist sentences in place.
The note "This website is static" and the hosting-provider note need an update either way, and the policy should say that each landing-page load and each sign-up sends Rep Today one anonymous count (which link, if any) with no email address and no identifier, and that the hosting provider injects its own page-view analytics (V3).
**Recommendation: (a),** because it gives the five approved points their own heading and anchor and keeps section 10 about the website.
The sentence about counts must claim only what is true of the payload; the existing policy does not mention the ephemeral per-IP throttle counters either, and this PRD does not widen that claim.
Gates: US-WL11.

**OQ11. What a repeat sign-up with the same address does.**
**Recommendation: no second entry; the entry identifier, sign-up date and Source stay from the first sign-up; the Fit answer and the beta choice take the latest values** (a person correcting themselves).
Mechanism depends on OQ1 (with Option A the producer keeps the first-seen Source, because the sending service may overwrite fields on a resubmission - confirm in the spike).
Under Option A that protection has a window: the producer sees the store only when it runs (OQ4), so a resubmission before its next run, such as the same person returning by plain `reptoday.app` in a new tab to tick the beta box, can replace the first Source before the producer has recorded it.
The spike records whether a resubmission overwrites stored fields; the captain decides, with that result, whether the window is acceptable.
Gates: US-WL06.

**OQ12. Do `utm_*` parameters set the Source?**
**Recommendation: no.**
Reason: the request defines the Source as the tag of the link and a visit with no tag as `unknown`/`none`; honoring UTM would add an unreviewed second path to a Source and break the "closed list of tags" the reader enforces.
Gates: US-WL04.

**OQ13. How the retention clock learns the launch-email date.**
Options: read it from the email service's broadcast history; or the founder records it once.
**Recommendation: the founder records it once with `record-launch-email --sent-on`, kept beside the view outside every checkout.**
Reason: reading broadcast history is brittle across services and plan changes, and the date is a single deliberate act.
Sign-ups that arrive after the launch email are kept only until the same 30-day mark, as the approved wording says.
Gates: US-WL10.

**OQ14. Should same-day sign-ups be invited first-come?**
The reader invites opted-in sign-ups good Fit first and then everyone else, each group earliest `signed_up_on` first, and settles a same-day tie by the view's own order; each batch takes at most 20, fewer when the cohort's remaining room (it holds at most 50) is smaller.
US-WL07 orders same-day sign-ups by their random entry identifier, so whenever a batch boundary falls inside a same-day group of two or more opted-in sign-ups, good Fit or not, who on that day is invited first is arbitrary but the same on every run.
Options: (a) keep that date-only order; (b) order same-day sign-ups by submission time.
**Recommendation: (a), under every storage option.**
Reason: the view's order is data the Marketing Engineer reads, and ordering by time would reveal the within-day sequence of sign-ups, beyond the sign-up date the approved privacy wording names.
Choosing (b) later needs a stored submission time, a privacy wording change and an amendment to this PRD before the build.
Gates: none as written; choosing (b) amends US-WL06, US-WL07 and US-WL11 first.

## Appendix A: the approved request, verbatim

The request as approved on 2026-10-19 (item 20261016-reptoday-waitlist), exactly as handed to firstmate.
Two lines of the original (a note that a log entry was recorded and that nothing was sent to firstmate) are not requirements and are omitted.
The request's last paragraph is kept at the end and is carried by Dependencies item 1.

> Build RepToday's Waitlist: a sign-up on `reptoday.app` that records where each person came from and how well they fit, and a copy of the sign-ups without email addresses for the Marketing Engineer to count.
> Once you approve and ask Mandu for it, Mandu gives you a ready message to pass to firstmate, which builds it in RepToday through RepToday's normal reviewed path; the Marketing Engineer never changes RepToday.
> Every quoted wording is for your approval, and an approval note can change any of it.
>
> ### The sign-up
>
> - Exactly one low-pressure call to action, keeping the page's words: "Join the waitlist" and "Add your email and we'll tell you the day it ships."
>   The page asks for nothing else, no download, follow, or share; where the form appears more than once, it is the same form.
> - Three fields and no others:
>   1. Email, required.
>   2. One Fit question, "Which sounds most like you?", with no answer pre-selected: "I used to work out and lost the routine" (`lost-the-routine`), "I work out regularly" (`exercises-regularly`), or "I've never had a routine" (`never-had-a-routine`).
>      An answer is required to sign up.
>   3. A box, unticked until the person ticks it: "Invite me to the beta before launch".
> - The page now promises "one message"; since an opted-in person may also get a beta invitation, it should say "one launch email, plus a beta invitation only if you ask for one".
> - No "how did you hear about us" field: the Source comes from the link.
>
> ### Source, from the link
>
> - One link per Source: `reptoday.app/tiktok`, `reptoday.app/youtube`, `reptoday.app/reddit`, and `reptoday.app/network` (your personal network).
>   Each opens the sign-up page, and the word after the slash is that Source's lowercase tag.
>   TikTok may not give a new account a clickable profile link, so each link is short enough to say aloud, type, or put in a profile.
> - A sign-up keeps the Source of the link its visitor arrived by, even after they look around the site.
>   A sign-up reached any other way, such as by plain `reptoday.app`, is Source `unknown`; the links work in any letter case.
> - A new Source later is a new Dispatch request plus a reviewed gr0wthlab change.
>
> ### Web events
>
> Emit `landing_page_view` when the landing page loads and `waitlist_signup` when an email is submitted, each with `referrer_source`, as RepToday's event schema defines them; `referrer_source` is the visit's tag, or `none`.
> Neither event carries the email address or the entry identifier.
>
> ### Privacy policy
>
> `reptoday.app/privacy` gains a Waitlist section, in place of the waitlist sentences in section 10, that says in the policy's plain voice:
>
> - What is collected: the email address; the answer to the routine question; whether you asked for a beta invitation; which Rep Today link brought you, if any; and the sign-up date.
> - Why: to email you when Rep Today launches; to invite you to the beta, only if you asked; and to count, without your address, which links and which routines bring people.
> - How long it is kept: until 30 days after the launch email goes out, or until you ask to be removed, whichever comes first.
> - How to be removed: the unsubscribe link in any waitlist email, or a message to reptoday.app@gmail.com; your sign-up and answers are then deleted within 7 days.
> - Who sees your address: only the founder, when sending a waitlist email, and the service that stores it for Rep Today; it is never sold or shared.
>
> ### The anonymous view gr0wthlab reads
>
> - RepToday keeps one file on your Mac that gr0wthlab's launcher reads, read-only, at each weekly run, with no network.
> - The file sits outside the gr0wthlab, Mandu, and RepToday checkouts, where the sandboxed Marketing Engineer can never open it; once the build lands, a reviewed gr0wthlab change records its path.
> - It is UTF-8 JSON in exactly this shape:
>
> ```json
> {"view": 1, "generated_at": "2026-10-11T22:00:00+00:00", "entries": [
>   {"entry": "k3P9xQ2m", "source": "tiktok", "fit": "lost-the-routine", "beta_opt_in": true, "signed_up_on": "2026-10-05"}
> ]}
> ```
>
> - `entry`: a random identifier of 1 to 64 letters, digits, `-` or `_`; unique; stable while the sign-up exists; never derived from the address, so never a hash or an encoding of it.
> - `source`: `tiktok`, `youtube`, `reddit`, `network`, or `unknown`.
> - `fit`: `lost-the-routine`, `exercises-regularly`, or `never-had-a-routine`; `null` only for a sign-up that holds no answer, which gr0wthlab counts as unknown Fit, never as not a fit.
> - `beta_opt_in`: `true` or `false`.
> - `signed_up_on`: the sign-up's date in UTC, `YYYY-MM-DD`.
> - `generated_at`: when the file was written, with its UTC offset; each run report says how long before the run that was.
> - Nothing else: no address, name, or other field. A removed sign-up leaves the file.
>
> If any value in the file looks like an email address, gr0wthlab discards the whole read, records no Waitlist Evidence that week, and reports a Guardrail breach to you.
>
> ### Addresses stay on your side
>
> - Addresses are resolved only on your side, at send time: you turn an entry identifier into its address in RepToday's storage or your email tool when you send.
> - No email-service credential, such as the account behind today's Kit form, and no export that holds addresses is ever placed where the Marketing Engineer reads: the gr0wthlab, Mandu, and RepToday checkouts.
>   One such credential would expose every address.
>
> ### Left to RepToday
>
> Storage (including whether Kit stays), hosting, how a link's Source reaches its sign-up, how and how often the view is produced, whether sign-ups confirm their email, and every other implementation choice are RepToday's design under firstmate.
>
> Once firstmate's build lands, gr0wthlab needs one reviewed change to know where the sign-up file is and when the waitlist went live.
> Until then, every post stays marked "can't publish yet".

## Appendix B: strings

**Approved, fixed (carried verbatim; the contract file holds them):**

- Heading: Join the waitlist
- Sentence: Add your email and we'll tell you the day it ships.
- Fit question: Which sounds most like you?
- Fit answers: I used to work out and lost the routine; I work out regularly; I've never had a routine
- Beta box: Invite me to the beta before launch
- Promise phrase: one launch email, plus a beta invitation only if you ask for one

**New or changed, proposed for the captain's approval (OQ9).**
Every proposal is plain, identity-framed and avoids loss framing.

| Where | Proposal |
| --- | --- |
| Email field label | Email |
| Submit button | Join the waitlist |
| In progress | Joining... |
| Success (single opt-in) | You're on the list. We'll tell you the day it ships. |
| Success (if OQ5 is double opt-in) | Check your email to confirm your address. |
| Missing or malformed email | Add a valid email address. |
| No Fit answer | Choose the answer that sounds most like you. |
| Submission failed | That did not go through. Try again in a moment. |
| Hero lead-in (page copy beside the form, not inside it) | Rep Today is pre-launch and not yet on the App Store. |
| FAQ, "Is my data sold?" (replaces the waitlist clause that ends "nothing more") | And the pre-launch waitlist keeps your email, your answers to its form, which Rep Today link brought you, if any, and the date you joined; the Privacy Policy's waitlist section says why and for how long. None of that is ever sold either. |
| No-script message (only if OQ1 cannot post without script) | The sign-up form needs JavaScript. |

## Appendix C: draft Waitlist section for `reptoday.app/privacy`

A draft for the captain's edit and the legal pass the page already requires; the bracketed part follows OQ1 and OQ5.
It uses the policy's own structure (a heading, sub-headings, plain lists) and makes no promise beyond the five approved points.

> **11. The waitlist**
>
> This section covers the pre-launch waitlist on this website.
>
> **What is collected**
> - The email address you enter.
> - Your answer to the question "Which sounds most like you?".
> - Whether you asked for a beta invitation.
> - Which Rep Today link brought you here, if any.
> - The date you signed up.
>
> **Why**
> - To email you when Rep Today launches.
> - To invite you to the beta, only if you asked.
> - To count, without your address, which links and which routines bring people.
> - [If OQ5 is double opt-in: To confirm your address.]
>
> **How long it is kept**
> Until 30 days after the launch email goes out, or until you ask to be removed, whichever comes first.
>
> **How to be removed**
> Use the unsubscribe link in any waitlist email, or send a message to reptoday.app@gmail.com.
> Your sign-up and answers are then deleted within 7 days.
>
> **Who sees your address**
> Only the founder, when sending a waitlist email, and [the service that stores it for Rep Today - Kit, if OQ1 is Option A].
> It is never sold or shared.

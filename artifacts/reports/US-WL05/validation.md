# US-WL05 validation: web events

Date: 2026-10-20.
Spec: `.claude/agent/tasks/prd-waitlist_261019.md`, US-WL05, with OQ7 (a new, separate `POST` route) and OQ8 (`waitlist_signup` once per accepted submission) as the captain settled them.
Code and tests only, nothing deployed: the production Convex deployment was not contacted, and the browser checks posted to the local stub receiver.
No email address appears in this record; the browser checks typed a placeholder address.

## What landed

- `convex/webEvents.ts`: the closed vocabulary (`landing_page_view`, `waitlist_signup`; `referrer_source` one of `tiktok`, `youtube`, `reddit`, `network`, `none`), the reserved `installId` `web`, and the internal mutation `logWebEvent`.
- `convex/http.ts`: `POST /webEvent`.
  The request's `Origin` must be `https://reptoday.app` or `https://www.reptoday.app` (a dev deployment replaces the list with `WEB_EVENT_ALLOWED_ORIGINS`); the body is capped at 1 KiB before it is parsed; the body must be exactly `{name, props: {referrer_source}}` with a name and a value from the lists, or it is a `400`; no secret is used.
- `convex/rateLimit.ts`: `checkAndBumpWeb`, the route's own scope, 120 a minute per source IP (`webip`) and 3,000 a minute for the whole route (`web`); the app's per-install key is never touched.
- `gtm/03-site/waitlist.js`: `landing_page_view` once per load of either landing page (the script is not on `/privacy`), `waitlist_signup` at acceptance (a Kit `success` or the guard's confirmation, never on a validation error or a failed post), each a fire-and-forget `no-cors` `text/plain` POST with `keepalive`, `credentials: 'omit'`, no retry.
  The production route is used only from `reptoday.app` and `www.reptoday.app`; localhost and previews send nothing, unless a local test names a stub.
- The stale "handled outside the app" notes are rewritten: `convex/events.ts`, `convex/README.md` (a new "Web events" section), `ios/RepToday/RepToday/Models/AnalyticsEvent.swift` (comment only), `convex/http.test.ts`'s test name, and the funnel PRD's non-goal (amended in place).
  `AGENTS.md` gets one amendment bullet in the existing style.
- `convex/_generated/api.d.ts` lists the new module (the file is generated; `npx convex dev` would write the same two lines).
- App contract: `POST /logEvent`, its 13 names, its secret header and its tests are unchanged.

## Validation Test

Convex side (`npm test`, in process, no deployment): 118 tests pass, 21 of them new in `convex/webEvents.test.ts`; `npm run typecheck` passes.

- Accepted: exactly the contract file's `source_tags` and `no_source_event`, read from `tools/waitlist/contract.json` (its `unknown_source` is refused); both names with every tag and `none` (10 rows, each exactly `{referrer_source}`, `installId` `web`, no `eventId`, no `@` anywhere in the stored rows); the `www` origin; no secret needed.
- Rejected with no row inserted (step 3): an extra property, a name outside the two (the app's names included), `referrer_source` `unknown`, a UTM-looking or free-text value, an address-shaped value, any other top-level field (an address, an entry identifier, an install id, a timestamp, an event id), a body that is not an object, not JSON, empty or over the cap, a missing or foreign origin (seven variants).
- `landing_page_view` and `waitlist_signup` posted to `/logEvent` are still `400`, and `EVENT_NAMES` is still exactly 13 names without them.
- Rate limit: the per-IP scope answers 429 at 121 and inserts nothing further while another source still works; a request over its source's limit does not count toward the route-wide budget; the route-wide ceiling holds across many sources and a rolled window starts fresh; no per-install bucket is ever written by a web post.
- A failing store answers 500 with no detail.
- Non-vacuity: removing the origin check failed two tests; removing the exact-property check failed one; each file was restored afterwards.

Browser side (local site `wrangler pages dev`, stub receiver, `waitlist.testEndpoints` in `sessionStorage` naming the stub as the event sink; the stub records each request's `Origin`, `Cookie` and `Content-Type`):

1. `/privacy` first: no event. `/`, then `/youtube`, then `/` again in the same tab: three `landing_page_view` rows carrying `none`, `youtube`, `youtube` (the kept tag), each `text/plain`, `Origin` `http://localhost:8788`, no cookie.
2. A sign-up submitted from `/youtube`: one `waitlist_signup` carrying `youtube`; opening `/privacy` afterwards added nothing.
3. See the Convex side: the extra-property, wrong-name and `unknown` posts are rejected and `/logEvent` is unchanged.
4. `/privacy` added no event (step 1 and 2 above).
5. With the event endpoint pointed at an unreachable local address, a sign-up still reached the success wording ("Check your email to confirm your address.") and the page showed no uncaught error; the only console entry was the browser's own `Failed to load resource` notice for the blocked request, which no script can suppress.
6. With nothing stored, `/tiktk` sent one `landing_page_view` carrying `none`.

Widths: the sign-up from `/youtube` at 390 px and 1440 px (`youtube-signup-390.png`, `youtube-signup-1440.png`).

## Node checks of the page script

`node tools/waitlist/test-source.cjs`: 25 tests, six of them for events: exactly one `landing_page_view` per load with only the tag or `none`; a kept tag carried and a poisoned stored value read as `none`, never `unknown`; the request shape (`POST`, `no-cors`, `credentials: 'omit'`, `keepalive`, `text/plain`, no cookie, secret or identifier); nothing sent from localhost, previews or lookalike hosts, with a stub honored on local hosts only; a rejecting, throwing, hanging or non-function `fetch` never throws into the page and is not retried; and a successful sign-up sends one `waitlist_signup` carrying only the tag, with no address, entry or identifier in any event request ("a successful sign-up sends one waitlist_signup carrying only the tag: no address, entry or identifier").

## Not done here, by design

- Deploying the route to the production Convex deployment (credentialed, captain-approved, slice 4), and the preview-deploy repeat.
- Running the route against the dev Convex deployment: the in-process harness the PRD allows stood in, and no deployment credential was used.
- Whether Cloudflare's production Pages forwards `Origin` on a `no-cors` POST exactly as Chrome does here is confirmed by the rehearsal.

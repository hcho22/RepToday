# RepToday pre-launch event and metric schema

RepToday has zero users, so a data warehouse would be infrastructure theater; this one page exists instead of one.
It defines the minimal set of events worth instrumenting before launch, so that on day one every PRD success metric and every kill criterion is measurable from the first cohort (investment thesis, obligation 6).
Privacy is a selling point of the product: the core loop is fully offline and account-free, so analytics must be minimal, on-device-first, and must never require an account; events carry a random per-install ID only, never an email, IDFA, or Sign in with Apple identity.

## Events

Web-side events are the only ones that exist before launch; in-app events ship with the launch build.

| Event | Surface | Trigger moment | Properties (minimal) | Feeds |
|---|---|---|---|---|
| `landing_page_view` | Web | Landing page loads | `referrer_source` (utm or none) | Pre-launch top of funnel; K5 channel signal |
| `waitlist_signup` | Web | Email submitted to waitlist | `referrer_source` | Pre-launch conversion; launch-day install channel size |
| `app_install` | In-app | First open of the app ever | `install_week` (coarse, for cohorting) | Denominator for D7, D30, WAE, free-to-paid; K5 |
| `onboarding_started` | In-app | First onboarding screen shown | none | Onboarding funnel numerator base |
| `onboarding_completed` | In-app | Last onboarding step finished | `elapsed_seconds` | Onboarding -> 1st session (60% / 70%) |
| `ready_screen_shown` | In-app | Ready-on-open session screen renders | `generation_ms` | Generation latency (<100ms); K8 wedge check |
| `session_started` | In-app | User starts a generated session | `requested_minutes` | Session completion denominator; WAE |
| `session_completed` | In-app | Session finishes normally | `requested_minutes`, `completed_minutes`, `was_return`, `perceived_difficulty` | Session completion (>=80%); North Star WAE; Re-entry Ramp tuning |
| `session_abandoned` | In-app | Session exited before finish | `completed_minutes`, `abandon_point` | Session completion complement; fix-iteration diagnosis |
| `day7_return` | In-app | Any open on days 7-13 after install, emitted once | none | D7 retention (20% / 25%); K2 |
| `day30_return` | In-app | Any open on days 30-36 after install, emitted once | none | D30 retention (10% / 15%) |
| `week_active` | In-app | First `session_completed` in a calendar week, emitted once per week | none | Weekly Active Exercisers (35% / 40% of installs) |
| `paywall_shown` | In-app | Paywall screen renders | `entry_point` | Free-to-paid funnel base |
| `trial_started` | In-app | Free trial begins | none | Free-to-paid intermediate step |
| `subscribe` | In-app | Paid subscription starts (trial converts or direct) | `plan` | Free -> Paid (4% / 7%) |

[ASSUMPTION] The 7-day windows on `day7_return` and `day30_return`, and the emit-once dedup on the return and `week_active` events, are instrumentation conventions chosen here; the PRD defines the metrics but not the window mechanics.
[ASSUMPTION] Properties like `abandon_point` and `entry_point` are small closed enums to keep payloads minimal and non-identifying.

## Derived metrics (formula in words, one line each)

- Onboarding -> 1st session: installs with at least one `session_started`, divided by installs with `onboarding_started`.
- D7 retention: installs with a `day7_return`, divided by installs in that weekly cohort.
- D30 retention: installs with a `day30_return`, divided by installs in that weekly cohort.
- Weekly Active Exercisers (North Star): distinct installs emitting `week_active` in a week, divided by cumulative installs.
- Free -> Paid: installs with `subscribe`, divided by all installs in the cohort.
- Session completion: `session_completed` count divided by `session_started` count.
- Generation latency: distribution of `generation_ms` on `ready_screen_shown`; the target is <100ms on-device.
- Pre-launch waitlist conversion: `waitlist_signup` divided by `landing_page_view`, split by `referrer_source`.

## Pre-registration note

Every threshold above comes from the PRD Success Metrics table (`.claude/agent/tasks/prd-fitsnack-mvp-v6_0702.md`) and the kill criteria in `gtm/07-thesis/investment-thesis.md` (K1-K8, minimum-cohort rule, fixed week-8 and week-12 reviews).
This schema defines how the numbers are produced; it does not change any threshold, and it must not be edited to move one after data starts arriving.

## Honest constraints (why first-party events are the primary plane)

ATT means no user-level cross-app attribution without explicit consent: since iOS 14.5 apps must get permission via AppTrackingTransparency before tracking across other companies' apps or touching the IDFA, and denied users return an all-zeros identifier (Apple, User Privacy and Data Use, fetched 2026-08-01: https://developer.apple.com/app-store/user-privacy-and-data-use/).
SKAdNetwork / AdAttributionKit postbacks are the only paid-attribution signal that needs no consent, and they are aggregated, delayed 24-48 hours, capped at up to 64 conversion-value signals, and stripped of their most valuable fields below crowd anonymity thresholds (Apple, Ad Attribution overview, fetched 2026-08-01: https://developer.apple.com/app-store/ad-attribution/).
RepToday runs zero paid spend pre-launch anyway (see `gtm/01-research/ios-attribution-and-paid-vs-organic.md`), so the first-party funnel events above, plus the web-side waitlist events, are the primary measurement plane; SKAN/AAK becomes a secondary, aggregate-only check if paid experiments start post-launch.
Because the app never tracks across apps and never shares identifiers, it does not need to show the ATT prompt at all, which keeps the privacy posture intact.
[ASSUMPTION] Event delivery batches on-device and uploads anonymously; the exact analytics transport (self-hosted endpoint vs a minimal privacy-respecting SDK) is a launch-build implementation decision, not settled here.

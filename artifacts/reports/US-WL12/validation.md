# US-WL12 validation: go-live rehearsal and evidence

Run on 2026-10-21 (UTC) against production, each step on the captain's go-ahead.
No address appears here; sign-ups are named by Kit subscriber id or entry identifier only.

## Production setup

- **Kit.** Production account (form 9786563) holds the four custom fields the contract names, created and read back on 2026-10-21: `fit`, `beta_opt_in`, `source`, `entry`. The account had no sign-ups before go-live, so OQ6 had none to keep.
- **Convex.** `POST /webEvent` deployed to production `sensible-spider-810` from `main` 41c73df (the only change since production's durable-client sink was the US-WL05 route). Refusals checked with nothing written: no `Origin` and a foreign `Origin` answer `403`, an unknown event name `400`; `POST /logEvent` without the app's secret still `401`.
- **Site.** Preview deployment 751c8c33 (branch `waitlist-preview`, source c7ccd51) rechecked, then production deployment `fc6c12eb-40ef-4321-8599-dfaa470c75eb` (branch `main`, source 41c73df; previous 813b938d) on 2026-10-21 at about 13:41 UTC; the preview was then deleted. Before the deploy, the captain saw the full live-versus-main difference and approved publishing all of it.

## Rechecks on reptoday.app (the form never submitted)

The browser session sent every host except reptoday.app to a dead proxy, so no visit reached Convex or Kit.

| Check | Result |
| --- | --- |
| `/` and `/index-b` at 390 px and 1440 px | Both forms, nothing pre-checked (also after picking and reloading), the promise phrase, no "one message", no horizontal scroll; pages byte-identical to 41c73df. `live-{a,b}-{hero,closing}-{390,1440}.png`. |
| `/privacy` at 390 px and 1440 px | "Last updated: October 21, 2026", sections 10 and 11, the contents link, every "section N" reference resolving, no horizontal scroll; Cloudflare's email obfuscation (4 values) decodes to the published contact address. `live-privacy-waitlist-{390,1440}.png`. |
| Source links | `/tiktok`, `/youtube`, `/reddit`, `/network` with and without a trailing slash and in other letter cases: `200`, no redirect, the hidden Source set; kept across a reload, `/privacy` and `/index-b`; a later link replaces it; plain `/` gives `unknown`. |
| `/waitlist.js` | Served as JavaScript and byte-identical to 41c73df. **Known deviation:** reptoday.app's Cloudflare zone serves it with `Cache-Control: max-age=14400` (4 hours) where `_headers` sets `max-age=0` (the same deployment on `reptoday-site.pages.dev` serves `max-age=0`); accepted for now. The fix is a zone setting: Browser Cache TTL "Respect Existing Headers", or a cache rule for `/waitlist.js`. |
| Network | Each page load attempts `POST /webEvent` (blocked in the check session) and nothing goes to Kit. |

## The view and the daily job

- **Job-only clone.** `~/Developer/RepToday-waitlist-job`, `main` at 41c73df, used by nothing else (the captain's choice).
- **First producer run** (on demand, 2026-10-21 13:56 UTC): wrote `~/Library/Application Support/RepToday/waitlist/waitlist-view.json`, format `view` 1, accepted by `check-view.py`; folder `0700`, files `0600`. It held one entry: a confirmed sign-up made through the preview's form at 13:32:59 UTC (Kit subscriber 4350018598, entry `kE8khyuwGtmuu0xS`, Source `unknown`), not by the rechecks, which never submitted; the producer wrote its entry identifier back to Kit's `entry` field.
- **Installed** `app.reptoday.waitlist-daily` (`~/Library/LaunchAgents`, `daily --live` at 06:30 local, counts-only log `~/Library/Logs/RepToday/waitlist-daily.log`); `plutil -lint` OK; kickstarted once: last exit code 0, "daily: all 4 steps ok", the Kit key read from the Keychain without a prompt, no `@` in the log.
- **Updated on 2026-10-21 at 19:14 UTC** (the captain's "reptoday - update the job", after #210): the job-only clone fast-forwarded to `main` f4f2136, the job reinstalled with the README's update steps (`launchctl bootout`, the `sed` line, `launchctl bootstrap`), `plutil -lint` OK, and `launchctl print` reports the 06:30 calendar time and `run interval = 3600 seconds`. Kickstarted once: last exit code 0, "daily: all 4 steps ok", the view written with `"entries": []` and accepted by `check-view.py`, no `@` in the log.
- **Open:** the first runs launchd starts on its own (the next hourly run and the next 06:30), and whether a run the Mac slept through starts on wake; recorded in a later note.
- **Later note (2026-10-22, observed at 06:46 PDT):** launchd started every run on its own after the update, with no kickstart.
  The log shows 18 hourly runs, from 2026-10-21 20:14 UTC to 2026-10-22 13:15 UTC, about an hour apart, and the 06:30 calendar run at 2026-10-22 13:31 UTC (06:31 PDT), each ending "daily: all 4 steps ok" with every count 0.
  `launchctl print` reports `runs = 20` (these 19 plus the update's kickstart) and `last exit code = 0`, and the log holds no `@`.
  The wake case is still unobserved: `pmset -g log` shows no sleep since the 2026-10-21 09:56 PDT wake, before the update, so no run fell while the Mac slept.
  It stays open until a sleep-spanning run is seen.

## A morning run while the Keychain is locked

This Mac idle-sleeps after 1 minute (`pmset`: `sleep 1`, Power Nap off) and its login Keychain is set to `lock-on-sleep`.
A 06:30 calendar run that launchd fires on wake, before the captain unlocks, therefore meets a locked Keychain. From the code (`wl_store.read_api_key`, `waitlist.locked_run`, `waitlist.command_daily`), not from a live lock (locking the captain's Keychain, or a test keychain whose unlock dialog would appear on his screen, was not safe to do):

- **Loud, no partial work.** Each step reads the key before it takes the run lock or reads or writes anything (only the owner-only state folder is ensured). `security find-generic-password` either fails or, if it waits on an unlock dialog, is cut off after 60 seconds; either way the step raises "no Kit API key in the Keychain (service com.reptoday.waitlist.kit, account api-key)", is reported `FAILED (exit 1)`, and the job exits 1. Nothing is erased, no identifier is written and the view is not replaced, so the view's `generated_at` simply ages (which gr0wthlab's reader reports). The message says "no key" where the real cause is a locked Keychain.
- **Catch-up.** A failed morning is not retried that day: the next attempt is the next 06:30 (or the next wake after it). Every run reads Kit's whole state, so the next run that can read the key erases everything due (every unsubscribed or complained sign-up not yet erased, and on or after the retention date every remaining one); nothing depends on the missed run.
- **Deadlines.** A missed morning never moves a delete-by day later: a removal's day is 7 days from when the person asked (Kit's unsubscribe time, else the last day a run saw the sign-up subscribed, else its sign-up day), and retention's is the launch-email date plus 30, so the founder's window to delete in Kit shrinks by a day instead. One missed morning keeps every promise. Several in a row can break one silently: an unsubscribe is not scrubbed and so never appears in `kit-delete` output, and the only sign is the failed steps in the log; retention's 5-day margin (erase at +25, delete by +30) covers four missed mornings. Because this Mac is asleep at 06:30 most days, consecutive failures were the likely case.

The captain chose "job a" and #210 landed it: the job also runs every hour while the Mac is awake, and a locked Keychain is reported as "the Keychain is locked, so the Kit API key ... could not be read; nothing was changed and the next run tries again" instead of "no Kit API key" (`KeychainRead` in `tools/waitlist/test-waitlist.py`, including a live daily run on a locked Keychain that fails all four steps and changes nothing).
launchd does not make up an hourly run that fell while the Mac slept, so after an unlock the work can wait up to an hour of awake time; no delete-by day moves because of it.

## The rehearsal (2026-10-21, 14:17:55 to 17:12:37 UTC)

The captain signed up with addresses he owns, typed and confirmed in his own browser and mailbox; nobody else saw them.
Exclude event rows created inside this window from the pre-registered conversion.

| Step | Result |
| --- | --- |
| Two sign-ups | Address 1 through `reptoday.app/tiktok` in a new private window, address 2 through plain `reptoday.app` in another. |
| Confirmation | Both confirmation emails carried an unsubscribe link (the captain). Address 1's first confirm click did not register (Kit kept it `inactive`, and an unsubscribe click on the unconfirmed sign-up changed nothing); a second click confirmed it. |
| The view | Produced from the job-only clone; `check-view.py` accepted it; gr0wthlab's own reader (`~/gr0wthlab`, read only, its checkout unchanged) read it with status `read`. Address 1 entry `w8pHy9XBz3CViBg5`: Source `tiktok`, Fit `lost-the-routine`, beta `false`. Address 2 entry `0pGs4cIXEH2m9c4m`: Source `unknown`, Fit `exercises-regularly`, beta `false`. No address in the file. |
| Beta answer | The captain remembered ticking the box for address 1; Kit stored `false`. Checked on the live page in a session that could reach neither Kit nor Convex, with the page's `fetch` replaced by a recorder: a tick in the top or the bottom sign-up box posts `fields[beta_opt_in]=true` with that box's Join, and a tick in the top box with the bottom box's Join posts `false`. The two boxes were independent by design at the time; the stored answer matches a tick made in the other box. On 2026-10-21 the captain chose to make the beta choice one per page, so both boxes always agree and either Join sends the tick (FR-2 in the PRD, `gtm/03-site/waitlist.js`); it takes effect at the next publish. |
| Repeat sign-up | The preview address (the captain's sign-up through the preview, Kit 4350018598) signed up again through `/tiktok`: one record and one entry kept (`kE8khyuwGtmuu0xS`); the view kept its first-seen Source `unknown` from the ledger while its Fit and beta took the latest answers (OQ11, D3). A fourth address of his signed up through `/tiktok` too (Kit 4350092770, entry `u8tR8Rg7w8zfKa8N`). |
| Events | Production rows with `installId` `web` inside the window: `landing_page_view` `tiktok` 3 and `none` 1, `waitlist_signup` `tiktok` 3 and `none` 1, one per page load and per accepted sign-up, each carrying only `name` and `referrer_source`. |
| The privacy page | Opened by the captain; it carries the Waitlist section (rechecked above). |
| Removal by the unsubscribe link | Address 1 unsubscribed (Kit `cancelled` at 14:40:52 UTC). The installed job, kickstarted once the listing showed it: `sweep-unsubscribed` erased 1 (placeholder address, name and every field blank) and printed `Kit subscriber id 4350075973 - delete by 2026-10-28 - https://app.kit.com/subscribers/4350075973` (7 days from the unsubscribe); the next view omitted it. The captain deleted it on that page; `kit-deletes` then reported it confirmed deleted, Kit answered `404`, and its tombstone stayed in the ledger. |
| Removal by a message | The captain sent a removal request from address 2 to the contact mailbox. His typed `waitlist.py remove` (address at the hidden prompt) printed `remove: erased one sign-up` and `Kit subscriber id 4350092770 - delete by 2026-10-21 - https://app.kit.com/subscribers/4350092770`: the address he typed was the fourth one, so the typed path worked on that sign-up. Address 2 itself (Kit 4350076569) was then deleted in Kit's web app without a tool erasure, which left one leftover id with its entry identifier in the ledger (harmless: in no listing or view). The preview address was erased with `remove --entry kE8khyuwGtmuu0xS`. After the captain's three deletes, `kit-deletes` confirmed the two erased ones, Kit answered `404` for all four rehearsal ids, its listing was empty, and the view read `"entries": []` (gr0wthlab's reader: `read`, 0 sign-ups). |
| Why a founder removal is due the same day | `remove` is the path for a request sent to the contact mailbox: the founder deletes the record in Kit in the same sitting, and reading the mailbox at least every 5 days keeps that within 7 days of the message. An unsubscribe or a spam complaint, found by the daily job, is due 7 days from Kit's unsubscribe time instead. |
| Test broadcast | A Kit test broadcast to the captain carried an unsubscribe link (US-WL09, US-WL10). |

## The checkout audit

`tools/waitlist/audit-checkouts.sh`, read only, after the rehearsal: `~/gr0wthlab` 551 files, `~/Mandu` 1532, `~/Developer/RepToday` 4204 and `~/Developer/RepToday-waitlist-job` 1377, 0 findings in each (no email-service credential and no export that holds addresses, git-ignored files included; no unlisted address in the RepToday checkouts).

## Hand-off note for the gr0wthlab follow-up

- `waitlist.view.local_path` in `config/products.json`: `~/Library/Application Support/RepToday/waitlist/waitlist-view.json` on the founder's Mac (expand `~` to his home directory), format `view` 1. It lies outside the gr0wthlab, Mandu and RepToday checkouts and every git work tree.
- `waitlist.live_since` in `config/run.json`: `2026-10-21`, the day the Waitlist went live on reptoday.app (production deployment at 13:41 UTC) and this rehearsal passed.
- That change is gr0wthlab's own reviewed change; this story makes none in gr0wthlab or Mandu.

## Known deviations

- **`/waitlist.js` cache time on reptoday.app.** 4 hours (`max-age=14400`) from the reptoday.app Cloudflare zone, where `_headers` sets `max-age=0`; accepted for now, with the dashboard fix recorded in `gtm/03-site/DEPLOY.md`.
- **The preview sign-up.** The captain signed up through the preview's form, which posts to production Kit; that sign-up was removed in the rehearsal.
- **Address 2's removal.** The mailbox request for address 2 ended with a direct delete in Kit's web app (the founder's typed `remove` ran on another of his sign-ups); it left one leftover id with its entry identifier in the ledger, harmless because it is in no listing or view.
- **Local-stub rerun.** The earlier stories' browser Validation Tests were not rerun on the local stub in this slice; the automated suites ran on every PR in CI, and the browser checks ran on the preview and on reptoday.app.

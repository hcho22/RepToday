# Waitlist tooling

Tooling for the `reptoday.app` Waitlist.
The spec is `.claude/agent/tasks/prd-waitlist_261019.md`; the address boundary is `docs/adr/0009-waitlist-anonymous-view-and-address-boundary.md`.
Everything here is Python 3 standard library or plain Node, holds no credential and no address, and runs in CI's `waitlist` job.
The Mac-side commands (`waitlist.py`) run on the founder's Mac; the system `/usr/bin/python3` is enough and is what the scheduled job uses.

| File | What it is |
| --- | --- |
| `contract.json` | The one contract file: approved wording, Fit answers and tags, the four Source tags, `unknown` and `none`, the posted Kit field names, the view's rules. |
| `check-view.py`, `test-check-view.py`, `fixtures/` | The anonymous view checker (mirrors gr0wthlab's reader) and its tests. |
| `check-site.py`, `test-check-site.py` | Static checks on the landing pages: the four placements are one form, the approved strings and field names, no `mailto:` join, no stray address, the Source links, no top-level 404 page. |
| `test-source.cjs` | Node tests that run the page script (`gtm/03-site/waitlist.js`) against a fake page: the Source logic, the posted field names, Kit's answers and guard, and the two web events. |
| `stub-receiver.py` | A local stand-in for Kit's sign-up endpoint and the web-event sink, so no test posts to a real one. |
| `waitlist.py` | The operator command: `produce`, `assign`, `sweep-unsubscribed`, `sweep-retention`, `remove`, `record-launch-email`, `tag`, `show` and `daily`. Documented below. |
| `wl_common.py`, `wl_store.py`, `wl_core.py` | Its parts: paths, the run lock, the run's time limit and atomic writes; the Kit and synthetic stores; the ledger, identifier assignment, the view producer, the sweeps and the send-time lookup. |
| `fake_kit.py`, `test-waitlist.py` | A local fake of the part of Kit's v4 API the tooling uses, and the tests (store logic, the real Kit client over HTTP to the fake, and the command as a subprocess, including a crash, concurrent runs, a hung run and a pseudo-terminal). |
| `launchd/app.reptoday.waitlist-daily.plist` | The daily job's definition, for slice 4 to install. Nothing installs it from the repository. |
| `audit-checkouts.sh` | The read-only audit of the gr0wthlab, Mandu and RepToday checkouts (the address boundary, below). |

## Run the checks

```
python3 tools/waitlist/test-check-view.py
python3 tools/waitlist/check-site.py
python3 tools/waitlist/test-check-site.py
node tools/waitlist/test-source.cjs
python3 tools/waitlist/test-waitlist.py
python3 tools/check-no-waitlist-credentials.py
python3 tools/test-check-no-waitlist-credentials.py
```

## Try the site locally

```
python3 tools/waitlist/stub-receiver.py &
npx wrangler pages dev gtm/03-site --port 8788
```

A page served from `localhost`, `127.0.0.1` or `[::1]` posts its sign-up to the stub on `127.0.0.1:8799` and never to Kit.
In the stub's `quarantined` mode such a page shows the stub's stand-in check, because a local page trusts the stub's origin for the check instead of Kit's; no override is needed.
A local page sends no web events unless a test names a sink: `sessionStorage['waitlist.testEndpoints'] = '{"eventsUrl": "http://127.0.0.1:8799/event"}'`.
`eventsUrl` is the override's only key; the sign-up and the check always use the stub on port 8799, so run the stub on its default port.
On a Mac where the default `python3` is the python.org framework build, loopback connections can hang; `/usr/bin/python3` works.

## The Source links

The four links are `reptoday.app/tiktok`, `/youtube`, `/reddit` and `/network`.
The tags live in one list, `source_tags` in `contract.json`; the page script's copy is compared with it by `test-source.cjs`, and the view checker and the site check read it.
A new Source is a new Dispatch request plus a reviewed gr0wthlab change (its reader keeps its own list); no code here accepts a fifth tag.
Changing a tag after the links are posted means the old links stop recording, so treat the list as fixed once published.

## The Mac-side commands

`tools/waitlist/waitlist.py` is the one command.
It reads Kit through its API with a key from the macOS Keychain, keeps its own state in one owner-only directory, and prints counts, rule names and entry identifiers, never an address, an answer or the key.
Every example below is a command on the founder's Mac; none runs in CI or against anything but a synthetic store or the Kit test account.

### State and credentials

The state directory is `~/Library/Application Support/RepToday/waitlist` (override with `--state-dir`).
It is created owner-only (`0700`) and holds four things, each address-free and each written atomically with mode `0600`:

| File | What it is |
| --- | --- |
| `waitlist-view.json` | The anonymous view gr0wthlab reads (format `1`: `view`, `generated_at`, `entries`; each entry `entry`, `source`, `fit`, `beta_opt_in`, `signed_up_on`). Its path is the one gr0wthlab's `waitlist.view.local_path` records. |
| `ledger.json` | The producer's own record of which entry identifier it gave each Kit subscriber (decision D1), the Source first seen for it (OQ11), and the ids it has erased. Kit subscriber ids and entry identifiers only. The producer trusts only this file: a public post can set Kit's `entry` field, so the producer resets Kit's value to the ledger's. Losing the file means new identifiers, which the captain accepted. |
| `launch-email.json` | The launch-email date, recorded once (OQ13). |
| `.run.lock` | The one lock every command takes, so no two runs overlap. The kernel drops it when a process ends however it ends. |

The producer refuses to write the view, the ledger or the lock in or under any directory that holds a `.git` entry (a directory, or the file a linked worktree has), checked after resolving symbolic links, so the files can never land in a checkout.
A checkout's own `.git` ancestor includes a dotfiles repository in the home directory: if `~` holds one, pass a state directory that does not sit under it.

The Kit API key lives only in the macOS Keychain:

| Use | Keychain service | Account |
| --- | --- | --- |
| Production Kit account (slice 4 creates it) | `com.reptoday.waitlist.kit` | `api-key` |
| The separate Kit test account (the US-WL06 spike's item) | `com.reptoday.waitlist.kit-spike` | `api-key` |

`WAITLIST_KIT_KEYCHAIN_SERVICE` names the service to read (a name, not a secret).
The default is the production item, so a command run without it never reaches the test account by accident, and while that item does not exist a command finds no credential and does nothing.
The client sends the key only to `https://api.kit.com` or to a loopback address a test serves a fake on, and refuses any other base URL.

Two options let a command act on a shared test account without touching what a test did not create: `--synthetic FILE` uses a JSON file as the store, and `--restrict-to-ids A,B` makes a command see only those Kit subscriber ids (a listing leaves the others out; a write to one is refused).

### What each command does

| Command | What it does |
| --- | --- |
| `produce [--output PATH]` | Lists Kit (every state), gives each stored sign-up that lacks an identifier one (16 characters from the 62-letter-and-digit alphabet, about 95 bits, from the system's secure random source), writes it back to Kit's `entry` field, projects the confirmed sign-ups into the view, runs `check-view.py`'s own code over the candidate, and replaces the file only if it passes. An unconfirmed sign-up (Kit state `inactive`) and an unsubscribed one are never projected. `fit` outside the three tags is `null`, `source` outside the four is `unknown`, `beta_opt_in` is `true` only for the stored string `true`, `signed_up_on` is the UTC date of Kit's creation time, and entries are ordered by `signed_up_on` then entry. |
| `assign` | The identifier assignment alone. |
| `sweep-unsubscribed [--live]` | Erases every sign-up Kit reports as unsubscribed (state `cancelled`) that still holds an address or an answer. |
| `sweep-retention [--live]` | Erases every remaining sign-up, in any Kit state (`bounced` and `complained` included), on or after the recorded launch-email date plus 30 days. With no date recorded it deletes nothing and exits 0. One run erases what fits in its time limit; `daily` repeats it (below). |
| `remove [--entry ID] [--dry-run]` | Erases one sign-up: by entry identifier, or by an address typed at a prompt that is never shown, never an argument and refused when stdin is not a terminal. The match is exact. |
| `record-launch-email --sent-on YYYY-MM-DD [--replace]` | Records the launch-email date once. Refuses a future date, a date more than 7 days before today, a malformed date, and a second record without `--replace`. Prints the date the retention sweep will delete on. |
| `tag LABEL ENTRY...` | Tags the named confirmed sign-ups inside Kit, all or nothing. |
| `show ENTRY` | Prints one address, to an interactive terminal only. |
| `daily [--live]` | Both sweeps, then the producer, the retention sweep in repeated passes. |

Both sweeps are dry runs unless `--live` is given.
`--as-of YYYY-MM-DD` moves the retention sweep's clock for a dry run or a synthetic store; it is refused with `--live` against Kit.
Every deletion is followed, in the same run and under the same lock, by a view generated from a store read made after it.

### Erase, not delete

Kit's API cannot delete a subscriber (US-WL06 spike, decision D2).
`erase` unsubscribes the sign-up, overwrites its address with `removed-<subscriber id>` (not an address) and blanks the first name and every custom field the record holds (the four this tooling names and any other the account has), then reads the record back and refuses to call it erased unless the address, the name and every field are gone and Kit mails it nothing.
What Kit keeps is an empty shell: its id, creation time, its state (`cancelled`, or `bounced` or `complained`, which Kit also never mails) and its cancel time.
Open finding (2026-10-20, slice 3): for a sign-up that has confirmed, Kit also stores a geolocation derived from the visitor's connection (city, state, country, latitude and longitude), and its API accepts a write to that block and ignores it, so the scrub cannot clear it.
That block stays on the shell.
The captain decides before the privacy wording ships (slice 4) whether to accept it, look for a dashboard erase, or say so in the policy.

### Runs end, and never block each other

Every command takes the one lock and runs under a time limit of 600 seconds (`WAITLIST_RUN_LIMIT_SECONDS` shortens it for a test).
A run past its limit is cut off and exits 3; it never writes the view after the limit, and a leftover temporary file from an interrupted run is removed by the next run.
A run waits for the lock for the limit plus a minute, so a hung run cannot stall another one indefinitely, and the sweeps (which take the same lock) can never be held up past the limit.
Every network call has a 20 second timeout, a busy answer is retried a bounded number of times (waiting as Kit's `Retry-After` asks on a rate limit, never more than 30 seconds a time), and a deletion Kit refused because of its rate limit is left for the next run.
A run starts no deletion and no entry write-back to Kit in its last 120 seconds; what is left waits for the next run, so the view that follows is still written in time.
A removal started while a producer run is in flight waits for it, deletes, and regenerates the view, so the first view made from a store read after the removal omits the removed sign-up.
Kit's listing trails a write by up to a couple of minutes, so a listing made just after an erasure can still show the old record: the ledger remembers erased ids and a stale record is never given a new identifier, written to, listed in the view or erased a second time.

### Send-time path

1. gr0wthlab's Review Queue item names entry identifiers (it never sees an address).
2. The founder runs `tools/waitlist/waitlist.py tag <label> <entry>...` (at least 20 identifiers per call are fine). An unknown, malformed or unconfirmed identifier is an error naming it (an address pasted by mistake is named by position, never repeated), and nothing is tagged.
3. The founder sends the broadcast from Kit to that label. No address leaves Kit.
4. `show <entry>` prints one address to the terminal when the founder needs to see it; it refuses a pipe or a redirect and never writes or logs one.

Every waitlist email carries Kit's unsubscribe link: send the launch email and the beta invitations from Kit, never from another tool.

### Removal and retention runbook

- **Unsubscribe link.** Kit marks the sign-up `cancelled`. The daily sweep erases it, and the view that follows omits it, within a day.
- **A message to the contact mailbox asking to be removed.** The founder watches that mailbox at least every 5 days while the waitlist is open, so the 7-day promise has headroom. For a message that names an address, the founder runs `waitlist.py remove` and types the address at the prompt; if it reports that no sign-up has that address, the founder replies that nothing is held under it.
- **Launch email.** After sending it, the founder runs `waitlist.py record-launch-email --sent-on YYYY-MM-DD` once, with the day it went out. The command prints the day the retention sweep will delete every remaining sign-up. It refuses a date more than 7 days back so that a mistyped date can never schedule the deletion for tomorrow.
- **Before any date is recorded** the retention sweep deletes nothing and exits 0, while the unsubscribed sweep and the view still run every day.

### The daily job

`waitlist.py daily --live` runs `sweep-unsubscribed`, `sweep-retention` and `produce` in that order.
Each step runs whatever an earlier one did, a step that fails or runs out of time is reported as `FAILED (exit N)`, and the job exits non-zero when any step did.
An interrupt (Ctrl-C) is not a failure: it stops the whole job, exit 130.
One run of the retention sweep erases only what fits before its last 120 seconds, roughly 300 sign-ups at Kit's API-key rate (about 2 requests a second; an erasure is 3 calls), so the job repeats it as separate passes, each under the lock and its own 600 second limit, while the previous pass left sign-ups and erased at least one, up to 20 passes (about 6,000 sign-ups).
The step is reported failed only when sign-ups remain after the last pass or a pass erased none; the next daily run continues from there.
A view that cannot be written after a pass is reported, but the pass's erasures still count and the next pass runs; the job's last step writes the view again.
`launchd/app.reptoday.waitlist-daily.plist` runs it at 06:30 local time, and a calendar job the Mac slept through starts when the Mac next wakes.

Install it (the captain's step, slice 4; nothing in the repository does this):

```
mkdir -p ~/Library/Logs/RepToday
sed -e "s|__REPO_ROOT__|$(git rev-parse --show-toplevel)|" -e "s|__HOME__|$HOME|" \
  tools/waitlist/launchd/app.reptoday.waitlist-daily.plist > ~/Library/LaunchAgents/app.reptoday.waitlist-daily.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/app.reptoday.waitlist-daily.plist
launchctl kickstart gui/$(id -u)/app.reptoday.waitlist-daily
```

The Keychain item must let `security` read it without a prompt when the job runs.
The job writes counts only to `~/Library/Logs/RepToday/waitlist-daily.log`.

## The address boundary

`tools/check-no-waitlist-credentials.py` (CI) fails when a file git would publish holds a literal email-service credential, a bearer or API-key header with a literal value in the Waitlist's own paths, a subscriber export, or an email-shaped address that is not on its allowlist.
Its docstring is the one statement of each rule's file scope and of the allowlist, and a finding names a file and line, never a value.
The export rule reads every CSV, TSV, JSON or JSONL file whatever its encoding (UTF-8, else UTF-16 by its byte-order mark, else a single-byte decoding such as Latin-1), so a Windows-1252 export is found; only the stray-address rule is limited to text files.
An export-suffixed file over the 50 MB cap the other rules keep is still read by the export rule, a line at a time, and one that cannot be read fails the run, named (`unreadable-export`).
`tools/waitlist/audit-checkouts.sh <directory>...` is the read-only audit run at go-live against the gr0wthlab, Mandu and RepToday checkouts.
This repository can enforce only its own side; the matching rule for the other two checkouts is gr0wthlab's Guardrail G6, verified by the audit's credential and export rules with no change made to either.
The view producer's refusal to write in a work tree is covered by `ProducerSafety.test_refuses_a_path_inside_a_work_tree_or_a_symlink_into_one` in `test-waitlist.py`.

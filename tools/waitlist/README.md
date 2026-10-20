# Waitlist tooling

Tooling for the `reptoday.app` Waitlist.
The spec is `.claude/agent/tasks/prd-waitlist_261019.md`; the address boundary is `docs/adr/0009-waitlist-anonymous-view-and-address-boundary.md`.
Everything here is Python 3 standard library or plain Node, holds no credential and no address, and runs in CI's `waitlist` job.

| File | What it is |
| --- | --- |
| `contract.json` | The one contract file: approved wording, Fit answers and tags, the four Source tags, `unknown` and `none`, the posted Kit field names, the view's rules. |
| `check-view.py`, `test-check-view.py`, `fixtures/` | The anonymous view checker (mirrors gr0wthlab's reader) and its tests. |
| `check-site.py`, `test-check-site.py` | Static checks on the landing pages: the four placements are one form, the approved strings and field names, no `mailto:` join, no stray address, the Source links, no top-level 404 page. |
| `test-source.cjs` | Node tests that run the page script (`gtm/03-site/waitlist.js`) against a fake page: the Source logic, the posted field names, Kit's answers and guard, and the two web events. |
| `stub-receiver.py` | A local stand-in for Kit's sign-up endpoint and the web-event sink, so no test posts to a real one. |

## Run the checks

```
python3 tools/waitlist/test-check-view.py
python3 tools/waitlist/check-site.py
python3 tools/waitlist/test-check-site.py
node tools/waitlist/test-source.cjs
```

## Try the site locally

```
python3 tools/waitlist/stub-receiver.py &
npx wrangler pages dev gtm/03-site --port 8788
```

A page served from `localhost`, `127.0.0.1` or `[::1]` posts its sign-up to the stub on `127.0.0.1:8799` and never to Kit.
In the stub's `quarantined` mode such a page shows the stub's stand-in check, because a local page trusts the stub's origin for the check instead of Kit's; no override is needed.
On a Mac where the default `python3` is the python.org framework build, loopback connections can hang; `/usr/bin/python3` works.

## The Source links

The four links are `reptoday.app/tiktok`, `/youtube`, `/reddit` and `/network`.
The tags live in one list, `source_tags` in `contract.json`; the page script's copy is compared with it by `test-source.cjs`, and the view checker and the site check read it.
A new Source is a new Dispatch request plus a reviewed gr0wthlab change (its reader keeps its own list); no code here accepts a fifth tag.
Changing a tag after the links are posted means the old links stop recording, so treat the list as fixed once published.

# Marketing-agent build spec: the Rep Today creative loop

Status: documented and runnable in dry-run mode only.
This system has NEVER been run against a real ad account, has published nothing, and cannot publish anything as built.
Rep Today is pre-launch with zero users and no App Store listing, and the no-spend and no-publish guardrails are absolute for this package.

## Purpose

A founder-operated agentic loop that turns mined pain points into a creative matrix, QA-checks every asset against the brand guide, and logs every asset's angle, hook, pain, and format as structured JSON.
Only when budget exists and the founder flips the switch does it publish via adapters and ingest results to score angles.
Until that day, the loop runs entirely dry: it generates, lints, and logs, and its scoreboard honestly shows null results.

## Why built now

The channel plan's verdict is that paid spend should not happen yet, and pre-launch it structurally cannot (no listing means no app-install campaigns on Apple Ads or Meta; see `../../01-research/ios-attribution-and-paid-vs-organic.md`).
But the day $500/mo appears, the founder should spend that month running the loop, not building it.
Building the system now, against the real mined research, costs nothing and de-risks the first paid dollar later.
The same angle bank also feeds the organic PMF engine today, so the dry-run artifacts are not shelf-ware.

## Why the loop is creative-first

Primary sources show modern delivery systems read the creative and choose the audience: TikTok Smart+ leaves the advertiser only assets, budget, geography, and language; Google App campaigns assemble ads from the store listing; Meta's delivery models consider ad content alongside behavioral signals (`../../01-research/creative-carries-targeting-sources.md`).
So the unit of strategy is the angle, not the audience, and each angle must be self-selecting for a distinct person.
The Ad Library sweep (`../../01-research/meta-ad-library-sweep.md`) is the entropy source: it maps the crowded lanes to avoid (time compression, AI-coach claims, badge challenges) and the open lanes the seed bank occupies (ready-on-open, forgiveness, anti-gamification, offline).

## Architecture

```
angles.seed.json          brand-rules.json
(mined pains + real       (extracted from
 source URLs)              02-brand/brand-guidelines.md)
      |                         |
      v                         v
[1 angle bank] --> [2 variant generation] --> [3 brand-QA pass] --> [4 creative log]
                       (briefs in out/)          (checklist lint       (out/creative-log.json,
                                                  + vision review)      results all null)
                                                                            |
                                              =========================== FOUNDER SWITCH ===
                                                                            |  (does not exist yet;
                                                                            v   nothing below is implemented)
                                        [5 publish adapter]  -->  [6 results ingestion]  -->  [7 angle scoreboard]
                                        (STUBBED, DISABLED:       (SKAN-aware: campaign-      (today: prints nulls and
                                         raises                    level, delayed,             "nothing has been
                                         NotImplementedError)      aggregated)                 published")
```

### Stage descriptions

1. **Angle bank.** 5 to 8 seed angles, each tracing to a real mined pain in `../../01-research/pain-point-frequency.md` with its real source URL and verbatim quote. New angles enter only with a source; no angle may be invented from vibes.
2. **Variant generation.** `generate` emits one creative-brief markdown stub per angle into `out/`, carrying the hook, format, platform, pre-registered success signal, and kill criterion. A/B pairs vary only the hook, so the variable stays isolated.
3. **Brand-QA pass.** Two layers. The runnable layer is `qa`: a checklist lint against `brand-rules.json` (banned words like grind, beast mode, no excuses, streak; hook of 12 words or fewer; pain state named; source URL present; no questions, all-caps, emojis, or social-proof language in hooks; disclosure line present). The second layer, once assets are visual, is a vision-model review of the rendered asset against `../../02-brand/brand-guidelines.md` for palette, type, layout, and imagery rules; it is described here and not yet built.
4. **Creative log.** Every asset's structured JSON record (schema below) in `out/creative-log.json`, so a future system can learn which inputs won. This is a flat file, not a warehouse.
5. **Publish adapter.** A seam only. The `PublishAdapter.publish()` stub raises `NotImplementedError` with a message naming the founder decision required. Per-platform adapters (Apple Ads first, per the channel plan; Meta later) get written only after that decision.
6. **Results ingestion.** Designed SKAN-aware from day one, because iOS attribution is aggregated, campaign-level, delayed 24 hours to 60 days, and threshold-gated by crowd anonymity (`../../01-research/ios-attribution-and-paid-vs-organic.md`). The schema therefore stores campaign-level cost, postback counts, and coarse signal values with an explicit measured window, and never user-level rows. At $500/mo, most reads will sit below crowd-anonymity and learning-phase thresholds, so the scoreboard must render "insufficient data" as its own state, never as a zero.
7. **Angle scoreboard.** The read-out per angle against its pre-registered signal. Today it prints all-null result columns and the line "no data: nothing has been published".

## Creative-log JSON schema

One entry per asset in `out/creative-log.json`:

```json
{
  "angle_id": "A2-streak-grief",
  "pain_source_url": "https://hn.algolia.com/api/v1/items/40903998",
  "hypothesis": "People who quit apps after an unfair reset will respond to a forgiving rolling score with nothing to lose.",
  "hook": "Missing a day never zeroes you out.",
  "format": "12s screen-record video, missed day then unchanged score",
  "platform": "tiktok",
  "brand_qa": {"pass": true, "notes": "all brand-rules checks passed"},
  "status": "draft",
  "preregistered_success_signal": "3-second hold rate above account median over 7 days",
  "kill_criterion": "hold rate below account median on two consecutive 7-day reads",
  "results": {
    "published_at": null,
    "impressions": null,
    "signal_value": null,
    "skan_postbacks": null,
    "campaign_level_cost": null,
    "measured_window": null
  }
}
```

`status` moves draft -> published -> killed, one way.
Result fields stay null until real data exists; the dry run never fills them, and no code path fabricates a value.

## Operating cadence and kill rules

The cadence mirrors the PMF-kit doctrine: pre-registered signals, kill criteria, no vanity metrics.

- **Before anything runs:** every angle carries its success signal and kill criterion in writing, registered in the log before the first impression. Changing a signal after launch is a new angle, not an edit.
- **Weekly (the only loop day):** read the scoreboard once, on the same weekday, against the pre-registered signals only. Kill angles that hit their kill criterion (status becomes killed; killed angles never resurrect silently, they re-enter as new angles with a new hypothesis). Double the variant count on angles that beat their signal, varying only the hook within a pair.
- **Read discipline under SKAN:** no daily dashboard-watching, because postbacks lag 24 hours to 60 days and thin campaigns return stripped postbacks. Wait out the full measured window before any verdict, and log the window with the read.
- **Banned metrics:** follower counts, likes, and any number without a pre-registered target are not read and not stored. Impressions are stored only as the denominator for pre-registered rates.
- **Entropy refresh, monthly:** re-sweep the Meta Ad Library for competitor angles; a lane that has become crowded is grounds to retire an angle even if it has not hit its kill criterion.
- **Honest-n rule:** at $500/mo, many reads will be under-powered; the scoreboard must say "insufficient data" rather than crown a winner, and an under-powered read never kills or scales an angle.

## Safety rails (absolute)

- **Dry-run is the default and the only implemented mode.** There is no flag, environment variable, or config that enables publishing.
- **The publish adapter raises `NotImplementedError`.** Its message names what is required: a written founder decision that budget exists, which platform account to create and fund, and that the no-spend and no-publish guardrail is being lifted.
- **No credentials are read anywhere.** The code reads no environment variables, no keychain, no `.env`, and no config outside its own two JSON files.
- **No network.** Standard library only, no sockets, no HTTP; verified by reading `creative_loop.py`, which imports only `json`, `os`, `re`, and `sys`.
- **Nothing in this repo may ever auto-post.** Even a future implemented adapter must require an explicit per-run human confirmation; scheduled or unattended publishing is out of scope permanently.

## What it does NOT do

- **No data warehouse.** One flat JSON log; there are no users and no data sources, so warehouse infrastructure would be theater.
- **No user-level tracking.** No IDFA, no fingerprinting, no per-user rows; the results schema is aggregate by construction, matching both ATT rules and the brand's posture.
- **No engagement fabrication.** No invented stats, no simulated results, no "here's what happened when we posted" fiction; the scoreboard shows nulls until reality provides numbers.
- **No autonomous spend decisions.** The loop proposes kills and scale-ups against pre-registered criteria; the founder executes them.

## Runbook

The dry run is three commands; see `README.md`.
The implementation is `creative_loop.py` (Python 3 standard library only), with `angles.seed.json` as the angle bank and `brand-rules.json` as the lint rules.
Generated evidence lives in `out/`: the briefs and `creative-log.json` from a verified local dry run that published nothing and touched no network.

# US-WL04 validation: Source links and Source persistence

Date: 2026-10-20.
Spec: `.claude/agent/tasks/prd-waitlist_261019.md`, US-WL04, with OQ2 (stay on Cloudflare Pages, static), OQ3 (per-tab last touch among the four links) and OQ12 (`utm_*` never sets the Source) as the captain settled them.
Site code and tests only; nothing deployed.
No email address appears in this record; the browser checks typed a placeholder address and the stub's output is printed without it.

## What landed

- `gtm/03-site/waitlist.js`: the tag is read from the path only (the whole path must be one of the four tags, any letter case, optional trailing slash).
  The tag is kept for the tab in `sessionStorage` under one key (`reptoday.source`), a later link replaces it, any other path leaves it, and it feeds the form's hidden `fields[source]` input (`unknown` when there is none).
  No query string, `utm_*` value, referrer or cookie is read or written, and nothing outside the four tags can be recorded.
- `gtm/03-site/_redirects`: each of the four links and its trailing-slash form is rewritten (status 200) to `/`.
  A rewrite to `/index.html` was tried first and `wrangler pages dev` answered it with a 308 to `/`, which would have dropped the tag from the URL, so the target is `/` (see Findings).
  Other letter cases (`/TikTok`, `/YOUTUBE`) reach the page through Pages' implicit fallback, which holds only while the site has no top-level `404.html`.
- `tools/waitlist/check-site.py` gained `source-links` (the eight rewrites exist and go to `/`) and `no-404-page`; `tools/waitlist/test-check-site.py` covers each.
  That the script's tag list is the contract's, in order, is checked by running the script: `tools/waitlist/test-source.cjs`, "the script keeps exactly the contract file's four tags, in order".
- `tools/waitlist/test-source.cjs`: 12 Node tests of the tag logic (the contract's tag list, a page restored from the back/forward cache taking the tab's latest tag, casings, trailing slash, what never names a tag, a query string, `utm_*` value, hash or referrer never setting the tag, last touch, a poisoned stored value, unavailable storage, no cookie or `localStorage` write, one storage key).
  CI's `waitlist` job runs it.
- `tools/waitlist/README.md` documents the Source rule: a new Source is a new Dispatch request plus a reviewed gr0wthlab change, and no code path accepts a fifth tag.
  The view checker already builds its allowed sources from the same contract list, so the three readers of the list cannot silently disagree.

## Validation Test (local site `wrangler pages dev`, stub receiver)

1. Each of `/tiktok`, `/TikTok`, `/YOUTUBE`, `/reddit`, `/network` in a fresh page: the hidden Source value was `tiktok`, `tiktok`, `youtube`, `reddit`, `network`, with an empty `document.cookie` and one `sessionStorage` key.
2. `/tiktok`, then the footer Privacy Policy link, then `/` in the same tab: `sessionStorage` still held `tiktok` on `/privacy`, and the field on `/` read `tiktok`; a sign-up submitted there reached the stub with `fields[source]=tiktok`.
3. In a page with cleared storage, `/` read `unknown` and its sign-up reached the stub with `fields[source]=unknown`; then `/index-b`, `/tiktk` and `/?utm_source=tiktok` in turn each read `unknown`, with no stored tag.
4. In the same page `/reddit?x=1` read `reddit`.
5. Not run here: step 5 repeats step 1 on the captain-approved preview deploy (slice 4).

Widths: `/TikTok/` at a true 390 px (`innerWidth` 390, `scrollWidth` 390, Source `tiktok`, `tiktok-390.png`) and `/YOUTUBE` at 1440 px (`youtube-1440.png`, Source `youtube`).
Routes through `wrangler pages dev` (status): `/tiktok`, `/tiktok/`, `/network`, `/reddit?x=1` 200 with the landing page and the URL kept; `/TikTok`, `/YOUTUBE`, `/rEdDiT`, `/Network`, `/tiktk`, `/nosuch` 200 through the fallback.

## Findings

- A `_redirects` rewrite to `/index.html` is answered by Pages' pretty-URL handling with a 308 to `/` (seen locally), which loses the link's path; a rewrite to `/` keeps it.
  Whether Cloudflare's production Pages behaves the same is re-checked on the preview deploy in slice 4 (step 5), since `wrangler pages dev` is an emulation.
- Cloudflare Pages `_redirects` matching is not case-insensitive, so mixed-case links depend on the implicit fallback; `check-site.py` fails if a `404.html` is added.

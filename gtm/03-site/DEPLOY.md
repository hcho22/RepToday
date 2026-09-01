# Deploying the Rep Today landing site to Cloudflare Pages

The marketing site in this directory (`gtm/03-site/`) is **pure static HTML** - no
build step, no bundler, no framework. Both pages are self-contained (inline SVG
and inline CSS only); the sibling `screenshot-*.png` files are A/B report
artifacts and are not referenced by either page. Cloudflare Pages serves this
directory as-is.

- `index.html` - variant **A**, served at the site root (`/`).
- `index-b.html` - variant **B**, reachable at `/index-b` (or `/index-b.html`).

## 1. Deploy from the CLI (Wrangler)

Run from the **repo root** so the directory argument matches:

```bash
npx wrangler pages deploy gtm/03-site --project-name reptoday-site
```

- First run: Wrangler prompts to log in and to create the `reptoday-site` project
  if it does not exist. Answer yes.
- `gtm/03-site` is both the root **and** the output directory - there is no build
  output subfolder because there is no build.
- `_headers` (and `_redirects`, if ever added) at the top of `gtm/03-site` are
  picked up automatically by Pages.

## 2. Or wire it up in the Cloudflare dashboard (Git integration)

If you prefer auto-deploy on push instead of manual Wrangler runs, connect the
repo in **Workers & Pages -> Create -> Pages -> Connect to Git** and use exactly:

| Setting                     | Value                          |
| --------------------------- | ------------------------------ |
| Production branch           | `main`                         |
| Framework preset            | **None**                       |
| Build command               | *(leave empty)*                |
| Build output directory      | `gtm/03-site`                  |
| Root directory              | *(leave empty / repo root)*    |

There is no build command and no build output subdir: the output directory *is*
the source directory.

## 3. One manual step the captain must do (custom domain)

This is the only step that touches the Cloudflare account/DNS, and it is a
one-time click - **the crewmate deliberately does not do it.**

1. Open the `reptoday-site` Pages project -> **Custom domains** -> **Set up a
   custom domain**.
2. Enter `reptoday.app` and confirm.

Because **reptoday.app was purchased through Cloudflare**, DNS is already in this
same account, so Cloudflare adds the CNAME/route automatically - no manual DNS
records needed. Optionally repeat for `www.reptoday.app` and let Cloudflare
redirect it to the apex.

## HTTPS / TLS

Nothing to configure. `.app` is on the **HSTS preload list** (HTTPS-only in every
major browser), and Cloudflare Pages auto-provisions the TLS certificate and
serves every request over HTTPS. That is why `_headers` sets **no**
`Strict-Transport-Security` header by hand - it would be redundant.

## Not in scope here

- **True A/B split between `index.html` and `index-b.html`.** Serving different
  variants to different visitors at the same `/` URL requires a **Cloudflare
  Worker** (or Pages Functions) doing cookie-stable bucketing. That is out of
  scope for this repo-side prep. Until then, variant B lives at its own path
  (`/index-b`) and A is the root.
- **`_redirects` is intentionally absent.** Pages already serves `index.html` at
  `/` automatically, so no redirect rule is warranted today. Add a `_redirects`
  file in this directory only if a real redirect need appears.
- **Content-Security-Policy.** Omitted so the Kit waitlist embed
  (`rep-today.kit.com`) and its form keep working; see the comment in `_headers`.
  Authoring a verified CSP that still allows the Kit form is a follow-up.

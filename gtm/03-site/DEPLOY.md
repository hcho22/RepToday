# Deploying the Rep Today landing site to Cloudflare Pages

The marketing site in this directory (`gtm/03-site/`) is **pure static HTML** - no
build step, no bundler, no framework.
Both pages use inline SVG and inline CSS, and both load the one shared script `/waitlist.js` (the Waitlist form, the Source links and the two web events), so neither page is self-contained: deploy the directory whole.
The sibling `screenshot-*.png` files are A/B report artifacts and are not referenced by either page.
Cloudflare Pages serves this directory as-is.

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
- `_headers` and `_redirects` at the top of `gtm/03-site` are picked up
  automatically by Pages.
  `_redirects` is required: it carries the four Waitlist Source links (see "The Source links" below).

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

## The Source links (`_redirects`)

`_redirects` is required, not optional.
It rewrites the four Waitlist Source links (`/tiktok`, `/youtube`, `/reddit`, `/network`, each with or without a trailing slash) to the landing page, which reads the tag from the URL.
Without it the links rely on Pages' implicit fallback for unmatched paths, which a top-level `404.html` would turn off.
Its header comment explains why the target is `/` rather than `/index.html` and why the site must have no top-level `404.html`; `tools/waitlist/check-site.py` fails when a rewrite is missing or a `404.html` appears.
The two anonymous web events the pages send are described in `convex/README.md` ("Web events").

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
- **Content-Security-Policy.** Omitted for now; see the comment in `_headers`.
  The Kit embed script is gone (the form is first-party, `waitlist.js`), but the form still
  posts to `app.kit.com`, frames Kit's reCAPTCHA check from there when Kit asks, and the web
  events post to the Convex site, so a verified CSP needs `connect-src` and `frame-src` for
  those origins.
  Authoring one is a follow-up.

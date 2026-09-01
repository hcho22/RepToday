# Deploying the Rep Today site to Cloudflare Pages

The public site source in this directory (`gtm/03-site/`) is **pure static HTML** - no
build step, no bundler, no framework. All pages are self-contained (inline SVG
and inline CSS only), apart from the landing pages' external Kit waitlist form.
Cloudflare Pages serves this directory as-is.

- `index.html` - variant **A**, served at the site root (`/`).
- `index-b.html` - variant **B**, reachable at `/index-b` (or `/index-b.html`).
- `privacy.html` - the Privacy Policy, reachable at `/privacy` (or `/privacy.html`).
- `_headers` - the shared security and HTML revalidation headers.

These are the minimum runtime sources restored from repository history after the
larger retired marketing package was removed. Do not add generated screenshots or
unrelated campaign assets back to this directory: Cloudflare Pages deploys the
whole directory, and none is needed by the live pages.

## Publication gate

The source is ready to deploy, but a production deployment changes the public
`reptoday.app` site. Run it only with the captain's publication approval and an
authenticated Cloudflare account that already has access to the existing
`reptoday-site` Pages project. Repository access alone is not deployment authority.

## 1. Deploy from the CLI (Wrangler)

Run from the **repo root** so the directory argument matches:

```bash
npx wrangler pages deploy gtm/03-site --project-name reptoday-site
```

- If Wrangler asks you to log in, stop unless you are the authorized publisher.
- The `reptoday-site` project and `reptoday.app` custom domain already exist. Do
  not create a replacement project or change DNS as part of a content update.
- `gtm/03-site` is both the root **and** the output directory - there is no build
  output subfolder because there is no build.
- `_headers` (and `_redirects`, if ever added) at the top of `gtm/03-site` are
  picked up automatically by Pages.

## 2. Existing Git integration settings

If the existing Pages project uses Git integration, verify these settings before
relying on a push to publish:

| Setting                     | Value                          |
| --------------------------- | ------------------------------ |
| Production branch           | `main`                         |
| Framework preset            | **None**                       |
| Build command               | *(leave empty)*                |
| Build output directory      | `gtm/03-site`                  |
| Root directory              | *(leave empty / repo root)*    |

There is no build command and no build output subdir: the output directory *is*
the source directory.

Do not reconnect the repository, change the production branch, or modify the
custom domain during a routine policy update.

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

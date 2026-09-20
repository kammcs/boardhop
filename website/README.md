# boardhop.dev — the marketing site

Plain static HTML, CSS and one small JavaScript file. No framework, no build
step, no backend, no cookies, no analytics. The whole folder is the site: copy
it into an S3 bucket or an Apache `DocumentRoot` and it works.

## Run it locally

```sh
cd website
python -m http.server 4173 --bind 127.0.0.1
# http://127.0.0.1:4173/
```

Any static server does. There is nothing to compile.

## What is where

| Path | What it is |
|---|---|
| `index.html` | The marketing page: hero, pinned-phone feature showcase, tablets, gallery, pricing summary, roadmap, FAQ, beta call to action |
| `pricing.html` | Pricing in full: the three plans, how per-active-user billing works, setup steps, billing FAQ |
| `legal/*.html` | Privacy, terms, refunds, DPA, subprocessors, security. **Generated — see below.** |
| `css/site.css` | The only stylesheet. Palette and spacing tokens come from the app's `lib/theme/`. |
| `js/site.js` | Scroll reveals, the pinned phone that swaps its screenshot, the sticky header border, the copyright year. Everything degrades: with JS off the page is fully readable. |
| `img/shots/` | Optimized WebP screenshots, 1x and 2x, generated from `assets/shots/` |
| `img/brand/` | The app icon at several sizes, the Apple touch icon, and the social share cards |
| `tools/og-card.html` | Source for the share card; rendered by `tools/make_og_card.py` |
| `404.html` | The not-found page. Uses **root-relative** paths, because Caddy serves it for a miss at any depth. |
| `deploy.sh` | Publishes the site to the relay box |
| `tools/build_legal.py` | Generates `legal/*.html` |

## The legal pages are generated

Six documents sharing a header, a footer and a placeholder banner drift if they
are edited six times, so they are written once in
[`tools/build_legal.py`](tools/build_legal.py) and emitted whole:

```sh
python website/tools/build_legal.py
```

**Edit the Python, not the HTML.** Re-running the script overwrites
`legal/*.html`.

`index.html` and `pricing.html` are hand-written and the script does not touch
them.

## Before this goes public

Every legal page carries a visible placeholder banner. Deleting the banner is
one element with the class `placeholder-note` in the template. Also outstanding:

- [ ] Legal review of all six documents.
- [ ] `[JURISDICTION — to be set before launch]` in `terms.html` (governing law).
- [ ] `[EMAIL PROVIDER — to be named]` in `subprocessors.html`.
- [ ] Postal address in `privacy.html` §12.
- [ ] The addresses `hello@`, `support@`, `privacy@`, `security@` and `billing@`
      at `boardhop.dev` must exist and be monitored. They are used on the site,
      in the store listings and in the Marketplace listing.
- [ ] App Store and Google Play badges in the `#get` section, replacing the
      "links appear here at public launch" line.
- [ ] Confirm the Stripe entity, the trial length and the price against the
      final decisions in `research/paid-tier-billing.md` — the numbers on the
      site were taken from that document's section 0.
- [ ] Remove the placeholder banner.
- [ ] Remove `X-Robots-Tag: noindex, nofollow` from the site block in
      `relay/caddy/Caddyfile`, so the pages and `sitemap.xml` agree.

## Screenshots

`img/shots/` is generated from `assets/shots/`, which is **gitignored**: the raw
simulator captures are large and are kept machine-local. Regenerate the web
copies with the script the site was built from, or re-export by hand at 320 CSS
px wide for phones (1x and 2x) and 640 for tablets, WebP quality 82.

The shots themselves come from the demo build
(`--dart-define=BOARDHOP_DEMO=true`, `tool/demo-shots.sh`), so they contain
invented data about Boardhop building itself — no client data, nothing to
redact.

## Link previews

Every page carries Open Graph and Twitter tags, so a shared link unfurls as a
card in Discord, iMessage, Slack, WhatsApp and the rest. The image is
`img/brand/og-card.png`, 1200x630.

Regenerate it after a brand or screenshot change — it is built from the site's
own CSS, fonts and screenshots, so it cannot drift:

```sh
cd website && python -m http.server 4173 --bind 127.0.0.1 &
python website/tools/make_og_card.py
```

Two deliberate choices. **PNG, not WebP:** WebP is the format link previews
handle worst — Apple's iMessage is unreliable with it, and Facebook and
LinkedIn have declined it outright. **1200x630, not the app icon:** a square
image in a `summary_large_image` card gets letterboxed or silently downgraded.
The explicit `og:image:width` and `og:image:height` let a scraper lay the card
out without fetching the image first.

The `X-Robots-Tag: noindex, nofollow` described below is sent to preview bots
too. Discord, iMessage, Slack, WhatsApp and Telegram build previews regardless
— they do not treat it as a reason to decline. Platforms that gate on robots
directives (Facebook and LinkedIn are the ones to watch) may refuse. If that
bites before launch, the fix is a Caddy matcher that omits the header for
preview user agents; it is not there today because the platforms actually in
use do not need it.

## Hosting on the relay box (what runs today)

The site is a megabyte of files with no backend, so it rides along on
`boardhop-relay-1`, the box that already runs Caddy for the relay. It gets its
own site block, its own document root (`/srv/relay/site`) and its own access
log; no route on it reaches the relay container, and the relay's config is
untouched apart from the new block and a read-only mount.

```sh
SITE_DOMAIN=boardhop.dev sh website/deploy.sh
```

The domain and its `www` alias are remembered in `/srv/relay/.env`, so later
deploys are just `sh website/deploy.sh`. The script copies the files, reloads
Caddy, and then checks that **both** the site and the relay's `/healthz`
answer. A broken Caddyfile fails the reload with the running config left in
place, so a bad deploy here cannot take push intake down.

**Certificates.** Nothing to set up. Caddy takes a Let's Encrypt certificate for
`boardhop.dev` and `www.boardhop.dev` automatically over HTTP-01 on port 80,
using the ACME account already in the Caddyfile's global block. This matters
because `.dev` is on the HSTS preload list — browsers refuse plain HTTP for it
outright, so there is no unencrypted fallback. The only prerequisite is that DNS
already points at the box; a name that does not resolve fails the challenge and
Caddy backs off and retries.

**DNS.** Two A records at the registrar, both to the relay's address:

```
boardhop.dev.      A  2.28.109.139
www.boardhop.dev.  A  2.28.109.139
```

`www` is served by its own block that 301s to the apex.

**While it is unannounced,** every response carries
`X-Robots-Tag: noindex, nofollow`. That is deliberately a header and not a
`robots.txt` `Disallow`: a crawler told not to fetch the page never sees a
noindex and can still list the bare URL. Let it crawl; tell it not to index.
Remove the header from the site block at launch — it is one line, marked.

**Password.** The site block imports a fragment at
`/srv/relay/caddy/site-extra/auth.caddyfile`, empty today. Passing
`SITE_USER` and `SITE_PASSWORD` to `deploy.sh` fills it with a `basic_auth`
block; the password is hashed on the box and the clear text is never written
down. Running without them empties it again.

## Hosting elsewhere

**S3 + CloudFront.** Upload the folder as-is. Set the index document to
`index.html` and the error document to `404.html`. Every link is a relative
path with an explicit `.html`, so no URL rewriting is needed.

Suggested cache headers: one year and `immutable` for `img/`, `css/` and `js/`
(rename a file to bust it); a short max-age for `*.html`.

**Apache.** Drop the folder into `DocumentRoot`. Nothing else is required — no
`.htaccess`, no modules, no rewrite rules. Make sure `image/webp` is in the MIME
types (it is, on anything current).

**External requests.** The only third-party request the site makes is to Google
Fonts for Archivo and Inter. If that is unwanted, self-host the two families
into `css/` and drop the two `<link>` tags; the stylesheet already falls back to
`system-ui`.

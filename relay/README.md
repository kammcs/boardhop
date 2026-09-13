# Boardhop relay

The event receiver from `research/06-notification-relay-and-extension.md`: Azure
DevOps service hooks post here, the relay works out who should be told, and a
push gateway forwards an opaque pointer to the phone. This directory is the
relay's home in the monorepo — a plain Dart package (no Flutter) that ships as a
container.

Today it is a skeleton with two things in it:

- `GET /healthz` — `{"ok":true,"version":"<git sha>","uptime":<seconds>,"db":"ok"}`.
- `POST /capture/{name}` and `GET /capture/{name}` — the recorder for
  **research/06 spike 3** (what a "Minimal" hook payload actually contains).
  HTTP basic auth, user `hook`; every post is written as one JSON file under
  `/data/capture/{name}/`.

Device registration, the event→user mapping and the gateway come next.

## What runs on the box

**Host:** Hetzner CX23 `boardhop-relay-1`, Ubuntu 24.04, `boardhop.relay.kammcs.com`
(A + AAAA), ufw 22/80/443. Reach it as `ssh deploy@boardhop.relay.kammcs.com`.

```
/srv/relay/
  compose.yml        copied from relay/compose.yml by deploy.sh
  .env               RELAY_VERSION / RELAY_PREVIOUS for compose interpolation
  relay.env          RELAY_CAPTURE_SECRET, mode 600, generated on the box
  src/               the relay/ tree, the docker build context
  caddy/Caddyfile    copied from relay/caddy/Caddyfile
  caddy/data/        Caddy's ACME state and access.log (rolled at 10 MB, 5 kept)
  caddy/config/
  data/              the relay's volume: relay.sqlite and capture/
  secrets/           mode 700, empty until Kelly drops in the APNs .p8 and the
                     FCM service account; mounted read-only at /secrets
```

Two containers from `/srv/relay/compose.yml`:

| container | image | ports | notes |
|---|---|---|---|
| `relay-caddy` | `caddy:2` | 80, 443 (tcp + udp) | automatic HTTPS from Let's Encrypt, `support@kammcs.com`; security headers; reverse proxy to `relay:8080` |
| `relay-app` | `boardhop-relay:<git sha>` | none on the host | runs as uid 1000 so files under `/srv/relay/data` stay deploy-owned |

Both have healthchecks and `restart: unless-stopped`, and both log to the
json-file driver capped at 5 × 10 MB.

## Deploy

From the repo root, on any machine whose ssh key the box knows (Git Bash on
Windows is fine — the script falls back to `tar | ssh` where there is no rsync):

```sh
sh relay/deploy.sh
```

It is idempotent: it creates the directories, generates `RELAY_CAPTURE_SECRET`
if `/srv/relay/relay.env` does not have one yet, copies the tree to
`/srv/relay/src`, installs `compose.yml` and the `Caddyfile`, builds and starts
both containers, reloads Caddy (a bind-mounted Caddyfile change is invisible to
`compose up`), and finally polls `https://boardhop.relay.kammcs.com/healthz`.
The image is tagged with the short git sha; the tag it replaces is remembered in
`/srv/relay/.env` as `RELAY_PREVIOUS`.

Override with `RELAY_HOST`, `RELAY_DOMAIN` or `RELAY_VERSION`. Running the
script on the box itself skips the ssh hop.

## Roll back

```sh
sh relay/rollback.sh            # back to RELAY_PREVIOUS
sh relay/rollback.sh a1b2c3d    # or to a specific image tag
```

It checks the image exists, points `/srv/relay/.env` at it, restarts the relay
container without rebuilding (Caddy is left alone) and re-checks `/healthz`.
`docker images boardhop-relay` lists what is still on disk.

## Logs

- **Relay:** one JSON line per request on stdout — `{"ts","level","msg":"request","method","path","status","ms"}`. Never a body, never a header, never the Authorization line. `ssh deploy@boardhop.relay.kammcs.com 'cd /srv/relay && docker compose logs -f relay'`.
- **Caddy access log:** `/srv/relay/caddy/data/access.log` inside the box (the container's `/data`), rolled at 10 MB, 5 kept. Caddy logs request headers by default, so the Caddyfile's `format filter` **deletes `Authorization`, `Proxy-Authorization` and `Cookie`** — without it the capture endpoint's basic-auth secret would be written to disk in base64 on every hook post.
- **Container logs on disk:** the json-file driver, 10 MB × 5 per container.
- **Captures:** `/srv/relay/data/capture/<name>/<utc-timestamp>-<eventType>.json`.

## The capture secret

`/srv/relay/relay.env` holds `RELAY_CAPTURE_SECRET` (32 random bytes, hex), mode
600, deploy-owned. It was generated on the box with `openssl rand -hex 32` and
has never been printed, copied off the box or committed. Compose passes it to
the relay through `env_file`.

A spike that needs it reads it over ssh at run time:

```sh
ssh deploy@boardhop.relay.kammcs.com 'grep ^RELAY_CAPTURE_SECRET= /srv/relay/relay.env'
```

It was rotated once on 2026-09-13, after the first smoke test showed the header in the Caddy access log; that log was truncated and the filter above added.

To rotate it: replace the line in `/srv/relay/relay.env` with a fresh
`openssl rand -hex 32`, `docker compose up -d relay`, and re-create the hook
subscriptions (`W22_MODE=delete` then a fresh run of
`research/spikes/w22_hook_capture.py`), since the secret is stored inside each
subscription's `consumerInputs.basicAuthPassword`.

## Capture endpoint

```sh
# post (this is what Azure DevOps does)
curl -u "hook:$SECRET" -H 'Content-Type: application/json' \
  -d '{"eventType":"workitem.updated"}' \
  https://boardhop.relay.kammcs.com/capture/scratch

# list what has been captured
curl -u "hook:$SECRET" https://boardhop.relay.kammcs.com/capture/scratch
```

Without credentials, or with the wrong ones, both answer 401 (the comparison is
constant time). Each file is capped at 1 MB of body (the rest is dropped and the
file records `"truncated": true`) and each capture name keeps its newest 200
files. The stored JSON is the decoded body plus the timestamp and a header
subset: `content-type`, `user-agent` and every `x-vss-*`.

`research/spikes/w22_hook_capture.py` creates the scratch-project subscriptions
that feed `/capture/scratch`.

## Working on it locally

No Flutter, no emulator:

```sh
cd relay
dart pub get
dart analyze          # must be clean
dart test             # must be green
dart format .
RELAY_CAPTURE_SECRET=dev RELAY_DB=.dart_tool/relay.sqlite \
  RELAY_CAPTURE_DIR=.dart_tool/capture dart run bin/relay.dart
```

The root `analysis_options.yaml` excludes `relay/**`, so `flutter analyze` at the
repo root never sees this package; it has its own lints and its own 120-column
format width.

Dependencies are pinned exactly (`shelf`, `shelf_router`, `sqlite3`, `crypto`,
`logging`) and the Dockerfile builds on `dart:3.13`, the SDK the app uses, so
models can be shared with `lib/data` later.

SQLite: Debian ships the runtime as `libsqlite3.so.0`, and the `sqlite3` package
looks for the bare `libsqlite3.so` that only the `-dev` package provides, so
`lib/src/db.dart` overrides the library lookup on Linux. `/healthz` reports
`"db":"ok"` when the database opened.

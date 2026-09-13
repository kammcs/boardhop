# Boardhop relay

The event receiver from `research/06-notification-relay-and-extension.md`: Azure
DevOps service hooks post here, the relay works out who should be told, and a
push gateway forwards an opaque pointer to the phone. This directory is the
relay's home in the monorepo — a plain Dart package (no Flutter) that ships as a
container.

What it does today (phases R1 and R2.1):

- `GET /healthz` — `{"ok":true,"version":"<git sha>","uptime":<seconds>,"db":"ok",
  "apns":"disabled (no key id)","fcm":"ready"}`.
- **Service-hook ingest** — `POST /hooks/{org}` with per-org HTTP basic auth, a
  subscription registry, delivery dedup and a fast 200 backed by an in-process
  queue, plus the `/v1/admin/orgs/{org}/…` routes that configure it. See
  "Ingest" below.
- **Device registration** — `POST /v1/devices`, `DELETE /v1/devices/{id}`,
  `POST /v1/devices/{id}/heartbeat`, each authenticated with the user's own
  Azure DevOps access token.
- **Push gateway** — APNs (HTTP/2, ES256 JWT from the `.p8`) and FCM HTTP v1,
  behind a pointer-only contract, plus `POST /v1/test-push`.
- `GET /v1/admin/devices?org=` — counts and platforms, never a token.
- `POST /capture/{name}` and `GET /capture/{name}` — the recorder for
  **research/06 spike 3** (what a "Minimal" hook payload actually contains).
  HTTP basic auth, user `hook`; every post is written as one JSON file under
  `/data/capture/{name}/`.

Turning a routed event into an audience is the next phase (R2.2); the design is
research/14 §2 and §5, and "The audience problem" in research/06.

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

## Ingest (`/hooks/{org}`)

The real receiver, as opposed to the capture recorder: this is what the thirteen
service-hook subscriptions of research/14 §1 post to. It is deliberately dull —
authenticate, look the subscription up, dedup, project the body into a typed
`RoutingView`, hand that to an in-process queue, answer 200. No network call on
the request path, and nothing from the body is written anywhere.

```
POST /hooks/{org}
Authorization: Basic aG9vazo…       (user `hook`, password = the org's hook secret)
Content-Type: application/json
{"subscriptionId":"…","eventType":"workitem.updated","resource":{…}}
→ 200 {"accepted":true}
→ 200 {"accepted":true,"duplicate":true}    (a retry of a delivery already seen)
→ 404 {}                                    (everything the relay refuses)
→ 413 / 415 / 400                           (too big, not JSON, not an object)
```

**Auth and the 404 wall.** The secret is stored only as a **sha256 hex hash** in
`orgs.hook_secret_hash` and compared in constant time. Five different failures —
an org with no secret, an unknown org, a disabled org (`orgs.enabled = 0`), a
wrong secret, and a `subscriptionId` (or `X-VSS-SubscriptionId`) that is not
registered for that org — all answer **404 with an empty JSON object**, byte for
byte the same, so the endpoint cannot be probed. Which one it was appears only
in the log, as `{"msg":"hook rejected","org":"…","reason":"bad-secret"}`: a
reason code and nothing else. The body is capped at 1 MB (413 past that) and the
content type must be JSON.

**Registry.** `hook_subscriptions (org, sub_id, event_type, kind, project_id,
project_name, created_at)` is the list of subscriptions the relay will accept a
post from. `kind` is the routing label of research/14 §1 — `pr.created`,
`pr.updated.push|reviewers|status|vote`, `pr.comment`, `pr.merged`, `wi.created`,
`wi.updated`, `wi.commented`, `build.complete`, `run.state`, `stage.state`,
`approval.pending`, `approval.completed` — because `git.pullrequest.updated`
fires for four different things and the body does not say which; the four
`notificationType`-filtered subscriptions do. Registering it is the admin's job:

```sh
# On the box, so neither secret leaves it:
S=$(grep ^RELAY_ADMIN_SECRET= /srv/relay/relay.env | cut -d= -f2)

curl -sS -X PUT -H "Authorization: Bearer $S" -H 'Content-Type: application/json' \
  -d '{"secret":"<32 random bytes, hex>"}' \
  http://127.0.0.1:8080/v1/admin/orgs/puremedia/hook-secret
→ {"org":"puremedia","updated":true}

curl -sS -X PUT -H "Authorization: Bearer $S" -H 'Content-Type: application/json' \
  -d '[{"subId":"…","eventType":"workitem.updated","kind":"wi.updated",
        "projectId":"…","projectName":"DevOps Mobile App"}]' \
  http://127.0.0.1:8080/v1/admin/orgs/puremedia/subscriptions
→ {"org":"puremedia","subscriptions":1}

curl -sS -H "Authorization: Bearer $S" \
  http://127.0.0.1:8080/v1/admin/orgs/puremedia/subscriptions
```

The PUT **replaces** the org's whole set in one transaction, so a half-applied
registry is impossible; an unknown `kind`, or a kind that does not belong to its
`eventType`, is a 400 and leaves the old set alone. The org row is created
enabled if it is new. Without `RELAY_ADMIN_SECRET` all three routes answer 404,
as `/v1/admin/devices` does. The secret is hashed the moment it arrives: it is
never logged, echoed in the response, or stored.

**Dedup and the fast 200.** `X-VSS-ActivityId` is unique per delivery *attempt*,
so `hook_deliveries (org, sub_id, activity_id, received_at)` makes a retry a
no-op: 200, one `hook duplicate` log line, no processing. The body's `id` is the
fallback when the header is absent. Rows are pruned opportunistically on insert
once they are older than 24 h. Everything after the dedup is queued: `HookQueue`
is a bounded (1000) in-process queue with a **single consumer**, so the handler
returns in milliseconds — research/14 §5.2 rule 4, since a slow answer is a
retry, and a retry is another delivery. An overflow is dropped and counted
(`hook dropped`, reason `queue-full`) rather than growing without limit; a
processor that throws is counted and forgotten.

**What the consumer sees.** A `RoutingView`: a typed, immutable projection of
the ~20 fields the R2.2 rules read — ids, the kind, the artifact title, the
actor, assignee, creator, reviewers and their votes, the new state, the changed
field *names*, mention **GUIDs** (pulled out of `data-vss-mention="version:2.0,…"`
and `@<…>` markup, the text itself discarded), comment/thread/parent ids, build
result and branch, approval status and approver ids. It keeps no reference to
the raw body, so nothing downstream can serialise one by accident, and
`toLogFields()` returns ids, the kind and counts only. It also carries the two
noise classifiers of research/14 §5.2 rule 3: `isCommentNoise` (a
`workitem.updated` whose changed fields are all in the comment set — the
`workitem.commented` event is the one that notifies) and `isSystemComment`.

**What is logged, and what is never stored.** For R2.1 the processor is
`LoggingHookProcessor`: one `hook routed` line per event, carrying the kind,
org, event type, subscription id, activity id, project id, artifact id, run id
and actor/assignee/comment/thread ids, plus counts for mentions, reviewers and
changed fields. Never a title, a name, a comment, a description, a field value
or a branch. The only durable trace of an event is the four-column
`hook_deliveries` row, which is ids and a timestamp. `dart test` asserts both:
a synthetic payload carrying a sentinel string in its title, description,
comment content, `System.History` and `message.text` produces no log line and no
byte in the sqlite file containing it. R2.2 swaps the processor for the audience
rule engine; nothing else about the wiring changes.

## Device registration (`/v1/devices`)

The phone proves who it is with **its own Azure DevOps access token**. The relay
spends that token on one call — `GET https://dev.azure.com/{org}/_apis/connectionData?api-version=7.1-preview`
— reads `authenticatedUser.id` out of the answer, and drops it. The token is
never stored, never logged and never forwarded anywhere else
(`lib/src/identity.dart`).

```
POST /v1/devices
Authorization: Bearer <the user's Azure DevOps access token>
{"org":"puremedia","platform":"android","token":"<apns/fcm device token>",
 "appVersion":"1.0.0","locale":"en_GB"}
→ 200 {"deviceId":"<uuid>","userId":"<ado identity guid>","org":"puremedia"}

DELETE /v1/devices/{deviceId}          → 204   (same bearer; must be the owner)
POST   /v1/devices/{deviceId}/heartbeat → 200  (moves lastSeenAt, takes a rotated token)
```

- **Idempotent on `(org, token)`**: the same phone registering again keeps its
  device id.
- A device id belonging to somebody else answers **404**, exactly like one that
  does not exist, so the route cannot be used to enumerate ids.
- **Rate limit**: a token bucket per organization (120 requests, refilling at
  1/s) across registration, heartbeat, delete and test push.
- **Kill switch**: `orgs.enabled`. A row is created enabled on first
  registration; `sqlite3 /srv/relay/data/relay.sqlite "UPDATE orgs SET enabled=0
  WHERE org='x'"` stops that org, and only that org, with a 403.

Stored per device: `(id, org, user_id, user_descriptor, platform, token,
app_version, locale, created_at, last_seen_at)`. No name, no mail, no token of
the user's.

## Push gateway (`lib/src/gateway/`)

Everything that leaves for Apple or Google goes through `PushPointer`, which
holds exactly `org`, `eventType`, `artifactType` (workItem | pullRequest |
build | approval), `artifactId`, `project`, an optional `title` truncated to 80
characters, and an optional `deepLink`. `PushSender.send` takes that type and
nothing else, so there is no way to smuggle a comment body or a diff past the
boundary — the promise in research/06 is a compile-time one.

- **APNs** (`apns.dart`): `api.sandbox.push.apple.com` or `api.push.apple.com`
  by `APNS_ENV`, HTTP/2 through the `http2` package (Dart's `HttpClient` speaks
  1.1 only), ES256 JWT from the `.p8` re-minted every 50 minutes,
  `apns-topic: com.kammcs.boardhop`, `apns-push-type: alert`,
  `apns-collapse-id` per artifact. A `410`, `BadDeviceToken` or `Unregistered`
  deletes the device row.
- **FCM** (`fcm.dart`): HTTP v1 against
  `https://fcm.googleapis.com/v1/projects/$FCM_PROJECT_ID/messages:send` with a
  service-account OAuth2 token from `googleapis_auth` (refreshed before
  expiry). The message carries `notification` (so the OS shows it when the app
  is closed), `data` (the pointer, which the app routes on) and
  `android.notification.channel_id = "activity"`, the app's own channel.
  `UNREGISTERED` / `NOT_FOUND` deletes the device row.
- One JSON log line per send: platform, org, device id, **the last six
  characters of the token only**, artifact, outcome, status and the APNs/FCM id.

```
POST /v1/test-push
Authorization: Bearer <the user's Azure DevOps access token>
{"org":"puremedia"}
→ 200 {"devices":1,"sent":1,"results":[{"deviceId":"…","platform":"android","outcome":"sent","status":200}]}
```

It can only ever reach the caller's own devices in that org, which is what
makes it safe to keep as the support route.

### Sending a test push with curl

The app has no diagnostics page that shows a raw token (on purpose), so the
usual way is the **Send test** button on the Activity feed's push row. With a
token in hand from somewhere else:

```sh
curl -sS -X POST https://boardhop.relay.kammcs.com/v1/test-push \
  -H "Authorization: Bearer $ADO_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"org":"puremedia"}'
```

### Admin

```sh
# On the box, so the secret never leaves it:
ssh deploy@boardhop.relay.kammcs.com \
  'S=$(grep ^RELAY_ADMIN_SECRET= /srv/relay/relay.env | cut -d= -f2);
   curl -sS -H "Authorization: Bearer $S" \
     "http://127.0.0.1:8080/v1/admin/devices?org=puremedia"'
→ {"org":"puremedia","enabled":true,"devices":1,"platforms":{"android":1},"users":1}
```

Counts and platforms only: no token, no identity id. Without
`RELAY_ADMIN_SECRET` set the route answers 404.

`GET /v1/admin/fcm-check` (same bearer) asks Google to **validate** a message
without delivering it, against a deliberately bogus device token. It is the one
call that separates "the Firebase project or service account is wrong" from "the
phone will not register":

```
{"ok":true,"httpStatus":400,"code":"INVALID_ARGUMENT","project":"boardhop-d4b8f"}
```

`INVALID_ARGUMENT` is the healthy answer — the call was authenticated and
reached FCM, and only the fake token was refused. `PERMISSION_DENIED` or
`SERVICE_DISABLED` means the Cloud Messaging API is off for the project, and an
`error` field means the service account never authenticated.

## Settings in `/srv/relay/relay.env`

Mode 600, deploy-owned, never printed or committed. `deploy.sh` creates any that
are missing and never overwrites one that is there.

| name | what it is |
|---|---|
| `RELAY_CAPTURE_SECRET` | the capture endpoint's basic-auth password; generated on the box |
| `RELAY_ADMIN_SECRET` | bearer for `/v1/admin/*`, including the hook registry routes; generated on the box |
| `APNS_KEY_ID` | Apple's ten-character Key ID. `9L94ZN33Y3` since 2026-09-13; empty means APNs is off, which `/healthz` reports as `disabled (no key id)` |
| `APNS_TEAM_ID` | `73W98CESN9` |
| `APNS_TOPIC` | `com.kammcs.boardhop` |
| `APNS_ENV` | `sandbox` (debug builds and TestFlight) or `production` |
| `APNS_KEY_FILE` | `/secrets/apns-authkey.p8` |
| `FCM_PROJECT_ID` | `boardhop-d4b8f` |
| `FCM_SERVICE_ACCOUNT` | `/secrets/fcm-service-account.json` |

The two files under `/secrets` are mounted read only, are never copied off the
box or into an image, and are read by the relay process at send time only.

**Changing one of these needs `up -d`, not `restart`.** Compose reads `env_file`
when it *creates* a container, so `docker compose restart relay` brings the same
process back with the same environment and the edit looks as though it did
nothing — `/healthz` kept reporting `disabled (no key id)` for a full restart
cycle this way on 2026-09-13. Use:

```sh
cd /srv/relay && docker compose up -d --force-recreate relay
```

**A key that is not an APNs key gives `403 InvalidProviderToken`.** `/healthz`
says `ready` as soon as a key file, a key id and a team id are all present; it
cannot tell what Apple will make of them. The first key tried here was a valid
`.p8` for the right team and still failed, because the key had not been enabled
for APNs. Only a real send proves the pair.

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

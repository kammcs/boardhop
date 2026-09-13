# Boardhop relay

The event receiver from `research/06-notification-relay-and-extension.md`: Azure
DevOps service hooks post here, the relay works out who should be told, and a
push gateway forwards an opaque pointer to the phone. This directory is the
relay's home in the monorepo — a plain Dart package (no Flutter) that ships as a
container.

What it does today (phases R1, R2.1, R2.2 and R2.3):

- `GET /healthz` — `{"ok":true,"version":"<git sha>","uptime":<seconds>,"db":"ok",
  "apns":"disabled (no key id)","fcm":"ready"}`.
- **Service-hook ingest** — `POST /hooks/{org}` with per-org HTTP basic auth, a
  subscription registry, delivery dedup and a fast 200 backed by an in-process
  queue, plus the `/v1/admin/orgs/{org}/…` routes that configure it. See
  "Ingest" below.
- **Routing** — the audience rule engine of research/14 §2: one routed event
  becomes zero or more notifications, each with a verb, an anchor, a deep link,
  a collapse key and a set of identity ids. See "Routing" below.
- **Device registration** — `POST /v1/devices`, `DELETE /v1/devices/{id}`,
  `POST /v1/devices/{id}/heartbeat`, each authenticated with the user's own
  Azure DevOps access token.
- **Push gateway** — APNs (HTTP/2, ES256 JWT from the `.p8`, `mutable-content`
  for the enrichment extension) and FCM HTTP v1 (**data-only**, HIGH), behind a
  pointer-only contract, plus `POST /v1/test-push`. A routed notification now
  goes out through it: `GatewayNotificationSink` looks the recipients' devices
  up and sends one pointer to each.
- **Preferences** — `GET/PUT /v1/prefs?org=`, per `(org, userId)`, with quiet
  hours, muted artifacts and the §6 defaults. See "Preferences" below.
- `GET /v1/admin/devices?org=` — counts and platforms, never a token.
- `POST /capture/{name}` and `GET /capture/{name}` — the recorder for
  **research/06 spike 3** (what a "Minimal" hook payload actually contains).
  HTTP basic auth, user `hook`; every post is written as one JSON file under
  `/data/capture/{name}/`.

Next is the app's half (R2.4-R2.7): the pointer's new fields in
`lib/features/notifications/`, the preferences screen, the deep-link anchors and
the two enrichment services (Android `onMessageReceived`, the iOS Notification
Service Extension) that turn the fallback line into the real one.

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

The real receiver, as opposed to the capture recorder: this is what the fourteen
service-hook subscriptions of research/14 §1 post to (`tool/hooks.dart` below
creates them). It is deliberately dull —
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
`workitem.updated` whose changed fields are all in the comment set — since R2.2
that **is** the work item comment event, because the `workitem.commented` body
names nobody by id) and `isSystemComment`. Work item subscriptions are created
at resourceVersion 5.1-preview.3, the only version whose identity fields carry
an `id` (w27/w28).

**What is logged, and what is never stored.** For R2.1 the processor is
`LoggingHookProcessor`: one `hook routed` line per event, carrying the kind,
org, event type, subscription id, activity id, project id, artifact id, run id
and actor/assignee/comment/thread ids, plus counts for mentions, reviewers and
changed fields. Never a title, a name, a comment, a description, a field value
or a branch. The only durable trace of an event is the four-column
`hook_deliveries` row, which is ids and a timestamp. `dart test` asserts both:
a synthetic payload carrying a sentinel string in its title, description,
comment content, `System.History` and `message.text` produces no log line and no
byte in the sqlite file containing it. In R2.2 the processor is the `RuleEngine`
below and the `hook routed` line gains candidate, recipient and drop **counts**;
`LoggingHookProcessor` stays for the tests and for a relay with no database.

## Provisioning hooks (`tool/hooks.dart`)

`w22_hook_capture.py` generalized into the relay's own CLI: it creates the beta's
subscriptions in Azure DevOps and registers them with the relay in one go, so the
two can never disagree. The routing labels come from `HookKind` itself
(`lib/src/hooks/hook_kind.dart`), which is the same enum the ingest route parses.

```sh
cd relay
dart run tool/hooks.dart plan   --org puremedia --project 'DevOps Mobile App'
dart run tool/hooks.dart secret --org puremedia
dart run tool/hooks.dart create --org puremedia --project 'DevOps Mobile App'                                 --secret-file .hooks-secret-puremedia
dart run tool/hooks.dart list   --org puremedia
dart run tool/hooks.dart delete --org puremedia --project 'DevOps Mobile App'
```

| command | what it does |
|---|---|
| `plan` | prints the planned set — publisher, event, resourceVersion, filter, kind — and calls nothing |
| `secret` | generates 32 random bytes as hex, `PUT`s the **hash** to the relay, writes the plaintext to `--out` (default `.hooks-secret-<org>`, mode 600, gitignored as `.hooks-secret-*`) and never prints it |
| `create` | resolves the project id, creates every missing subscription against `{RELAY_URL}/hooks/{org}`, skips the ones already there, then registers the set with the relay |
| `list` | Azure DevOps subscriptions pointing at `{RELAY_URL}/hooks/` beside the relay registry, flagging anything that disagrees (exit 1 on a mismatch) |
| `delete` | deletes only subscriptions whose url is exactly `{RELAY_URL}/hooks/{org}` **and** whose `publisherInputs.projectId` is that project, then takes those rows out of the registry |

**The set is 14 subscriptions over 11 distinct event ids.** research/14 §1 counts
"thirteen" by listing one row per event id including `stage-state-changed`, which
that table itself marks "later"; the beta leaves it out.
`git.pullrequest.updated` is subscribed **four times**, once per
`notificationType` (`PushNotification`, `ReviewersUpdateNotification`,
`StatusUpdateNotification`, `ReviewerVoteNotification`), because the body never
says what changed; `git.pullrequest.merged` is filtered to
`mergeResult=Unsuccessful` because it otherwise fires on every merge *attempt*
(w24); `workitem.commented` is subscribed and then dropped by the relay, whose
`workitem.updated` twin is the one that names the commenter by id. Every other
publisher input goes out as an empty string — what the web UI sends for "any".
Each subscription is created with `resourceDetailsToSend: all` and
`messagesToSend`/`detailedMessagesToSend: text`, basic auth `hook` / the org's
hook secret.

**Environment.**

| name | what it is |
|---|---|
| `ADO_ORG_URL` | `https://dev.azure.com/<org>`; the PAT travels as basic auth `:PAT` |
| `ADO_PAT` | a PAT with the service-hooks scope for that org |
| `RELAY_URL` | default `https://boardhop.relay.kammcs.com` |
| `RELAY_ADMIN_SECRET` | bearer for `/v1/admin/*`; read off the box, never committed |
| `HOOKS_ALLOW_PROJECT` | **the write guard** |

**The guard.** `create` and `delete` write to Azure DevOps, so they refuse any
project whose name is not exactly `HOOKS_ALLOW_PROJECT` — and refuse before the
first network call, so a typo never even resolves a project id. With the variable
unset they refuse outright. That is CLAUDE.md hard rule 1 in code: today the only
value it is ever given is `DevOps Mobile App`. `plan` and `list` are read-only
and need no guard.

**Order for a new org.**

1. `secret --org <org>` — the relay stores the hash, the box never sees the
   plaintext and the plaintext never leaves the file.
2. `create --org <org> --project <name> --secret-file <path>` once **per
   project**. Each run GETs the registry, replaces that project's rows and PUTs
   the union, so provisioning the second project does not unregister the first
   (the admin PUT replaces the whole org set in one transaction).
3. `list --org <org>` to confirm; it exits non-zero if anything disagrees.

**Rotating the secret.** The subscriptions carry the old password inside Azure
DevOps and there is no way to edit it in place that is worth the risk, so:
`secret --org <org> --out <new file>`, then `delete` and `create` for **every**
project in the org. Between the two the relay answers 404 to every delivery and
the events in that window are lost — Azure DevOps retries, but not forever, so do
it in a quiet minute.

**Rate limits.** Calls are sequential and there is one retry on a 429, honouring
`Retry-After` (up to 60 s, then it gives up). A full `create` is 16 calls, about
2.7 TSTU (s39/w24 measurements).

**The scratch project's capture subscriptions are gone.** w22's `/capture/scratch`
and w24/w25's `/capture/scratch-r2` sets were deleted when those spikes finished,
so `create` on `DevOps Mobile App` starts from nothing and the payload captures
on the box are wiped. `list` shows only `/hooks/` urls, so an old capture
subscription would not even appear.

**From a spike runner.** `research/spikes/w26_provision_hooks.py` is the wrapper
the dispatcher uses: it reads `RELAY_ADMIN_SECRET` off the box over ssh, pins
`HOOKS_ALLOW_PROJECT` to `DevOps Mobile App` and runs the command in `W26_ARGS`,
writing the tool's stdout to `research/spikes/results/w26_provision_hooks.md`.

## Routing (R2.2)

What turns one routed event into notifications. The design is research/14 §2
(the event → audience table), §5.2 (the six rules) and §6 (the preferences).

```
receive → auth → dedup → RoutingView → rules → actor → collapse → prefs → caps → sink
          └────────── R2.1 ────────┘   └───────────── R2.2 ──────────────────────┘
```

1. **Rules.** One pure function per family — `work_item_rules.dart`,
   `pull_request_rules.dart`, `build_rules.dart`, `approval_rules.dart` — takes
   the `RoutingView` and the routing state and returns `Candidate`s, each a
   `(userId, verb, detail?, anchor?)`. The same call advances the state, because
   a service-hook body is **rendered at delivery time** (w24) and says nothing
   about what changed: "who was added as a reviewer", "did the source commit
   move" and "was the last build on this branch red" are diffs, not fields.
2. **Actor.** Whoever caused the event is removed from every audience (§5.2
   rule 1). Two exceptions: builds, because you want to hear that your own push
   failed, and the lone approver of their own run. Only `pr.created`, the PR
   comment event, `workitem.*`, `build.complete` and `approval-completed` name
   their actor at all; a PR vote's actor is the reviewer whose vote moved
   against `pr_state`, and a reviewer-list or status change names nobody (there
   is no `closedBy` in the payload), so those go out with the verb alone.
3. **Collapse.** Several rules can select the same person; the highest
   `Verb.priority` wins and that person gets exactly one notification (rule 2):
   `mentioned` > `assigned`/`reviewRequested` > `voted`/`stateChanged`/approvals
   > `commented`/`replied` > `edited`/`pushed`.
4. **Preferences.** `UserPrefs.allows(verb, reason:, detail:, artifactKey:)`
   and `quietHoursSuppress(verb, now, tzOffset)`. The **reason** a rule picked
   somebody — `author`, `assignee`, `creator`, `reviewer`, `votedReviewer`,
   `threadParticipant`, `mention`, `approver`, `requester`, `previousAssignee` —
   travels on the `Candidate`, because "mentions only" and "my threads only" are
   the same verb with a different reason. R2.3 backs the interface with
   `user_prefs` through `DbPrefsSource`; a person with no row is on the §6
   defaults ("Preferences" below).
5. **Caps.** At most 50 recipients per event and 60 per person per hour per
   org (rule 6), counted in `notification_sends`, which is also what makes
   "one notification per person per event" survive a replay.
6. **Sink.** `NotificationSink.deliver(Notification)`.
   `GatewayNotificationSink` (R2.3) looks each recipient's devices up
   (`devicesFor(org, userId)`), builds one `PushPointer` with `sentAt = now` and
   sends it to every device; somebody with no registered device is simply not
   reached, because the relay keeps no inbox (§5.2 rule 7). It logs the same
   `{"msg":"notification", …}` line as before plus device and outcome counts.
   `LoggingNotificationSink` stays for the tests and for a relay with no
   gateway.

**The verbs** (`lib/src/routing/verb.dart`, research/14 §3.2): `assigned`,
`reassigned`, `stateChanged`, `edited`, `created`, `commented`, `replied`,
`mentioned`, `reviewRequested`, `voted`, `prCompleted`, `prAbandoned`,
`prPublished`, `pushed`, `mergeFailed`, `buildFailed`, `buildPartial`,
`buildCanceled`, `buildSucceeded`, `buildFixed`, `approvalPending`,
`approvalCompleted`, `test`. The relay sends the enum name; the app turns it
into words. `detail` is validated against a **closed list per verb** — vote
labels, build results, approval and merge statuses — and anything free-form (a
state name, a stage name) is capped at 40 characters.

**Deep links and collapse keys** are org-relative and exactly research/14 §2:
`/projects/{project}/work-items/{id}[?comment={id}]`
(`{org}.wi.{id}`, `{org}.wi.{id}.comments`),
`/pull-requests/{id}[?thread={id}|?tab=files]` (`{org}.pr.{id}`,
`{org}.pr.{id}.t{threadId}`), `/projects/{p}/pipelines/runs/{id}`
(`{org}.build.{id}`), `/projects/{p}/pipelines?tab=approvals&approval={id}`
(`{org}.approval.{id}`, and a completed approval keeps that collapse key but
opens the run). Collapse keys are **org-scoped**, so a phone registered for two
organizations never collapses two different artifacts together, and capped at
APNs' 64 bytes from the left, where the org prefix is the expendable part. The relay never
names an account; the app prefixes `/a/{accountId}/orgs/{org}`.

**The state tables** (schema 5, research/14 §5.1, pruned after 90 days):

| table | what it holds | why |
|---|---|---|
| `pr_state` | `status, is_draft, source_commit, reviewers_json` (id → vote), `author_id` | added-reviewer, vote, push and draft→published detection |
| `pr_thread_state` | `participant_ids_json` per `(pr, thread)` | the comment audience: the v2 payload carries the comment but not the thread |
| `run_state` | `pipeline_id, requested_for_id, requested_by_id` | the approval events name the requester only by display name (w25) |
| `build_state` | `last_result, build_id` per `(project, definition, branch)` | "fixed" detection |
| `projects` | `project_id → project_name` | the app's routes take a name; the pipelines publisher sends only an id |
| `notification_sends` | `(org, event_key, user_id, sent_at)` | one per person per event, and the hourly cap |
| `user_prefs` | `prefs_json` per `(org, user_id)` | research/14 §6; switches and closed vocabularies, no free text |

**What is never stored.** No title, no display name, no comment, no description,
no field value, no branch — every column above is an id, a status word, a commit
sha, a vote or a timestamp. The one deliberate exception is
`projects.project_name`, which exists only so a route can be built, and `dart
test` asserts the column list of every other routing table against the words
`title`, `name`, `text`, `content`, `description`, `comment`, `body` and
`message`. The three content-adjacent things a notification carries — `title`,
`actorName` and `detail` — live **only** inside the in-flight `Notification`:
they are never written to the database and never logged, which `dart test`
proves by pushing a sentinel string through every event kind and grepping both
the log lines and the sqlite file for it.

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
app_version, locale, tz_offset_minutes, created_at, last_seen_at)`. No name, no
mail, no token of the user's. `tzOffsetMinutes` (minutes east of UTC, −840..840)
is accepted on registration and on every heartbeat, and is the only thing that
makes quiet hours the device's local time rather than UTC.

## Push gateway (`lib/src/gateway/`)

Everything that leaves for Apple or Google goes through `PushPointer`.
`PushSender.send` takes that type and nothing else, so there is no way to
smuggle a comment body or a diff past the boundary — the promise in research/06
is a compile-time one. **v2** (R2.3, research/14 §3.2) is:

| field | what it holds |
|---|---|
| `org`, `eventType`, `artifactType` (workItem \| pullRequest \| build \| approval), `artifactId`, `project` | ids |
| `title` | the artifact line the relay built, `#15545 · …` / `!8348 · …`, truncated to 80 |
| `deepLink` | org-relative route, anchors included; the app prefixes `/a/{accountId}/orgs/{org}` |
| `actor`, `actorId` | display name capped at 60, and the identity GUID; both absent for a service identity |
| `verb` | one of the closed `Verb` names, validated on construction; the app turns it into words |
| `detail` | the verb's own metadata — a vote label, a build result, a state or stage name — from a closed list per verb, else capped at 40 |
| `anchor` | `comment:{id}`, `thread:{id}`, `approval:{id}` or `tab:files`, by regex |
| `runId`, `subId` | the approval's run, and the subscription that produced it (support only, never shown) |
| `sentAt` | ISO-8601 UTC, so enrichment can skip a pointer older than 10 minutes |
| `collapseKey` | the routed key (`contoso.pr.8348.t4821`); `collapseId` falls back to `{org}.{type}.{id}` |

`Verb` lives in `lib/src/verb.dart` — above both directories, because
`routing/` produces verbs and `gateway/` validates and renders them. The
dependency between the two runs in exactly **one** direction: `routing/` imports
`gateway/`, never the other way, which is why the `Notification` → `PushPointer`
adapter (`routing/push_pointer_adapter.dart`) sits on the routing side. A test
pins the longest legal pointer under 1 KB.

**The fallback line** (research/14 §3.1) is what the OS shows before enrichment
runs, or when it fails: the **title** is the artifact line, the **subtitle** is
the project (the pointer carries no repository name), and the **body** is
`{actor} {verb phrase}` — "Ada Example assigned you", "Ada Example replied on
!8348", "Build failed", "Needs your approval" — or the phrase alone when the
event named no actor. The English phrase table is one function in
`lib/src/verb.dart`; the app localises the verb itself.

- **APNs** (`apns.dart`): `api.sandbox.push.apple.com` or `api.push.apple.com`
  by `APNS_ENV`, HTTP/2 through the `http2` package (Dart's `HttpClient` speaks
  1.1 only), ES256 JWT from the `.p8` re-minted every 50 minutes,
  `apns-topic: com.kammcs.boardhop`, `apns-push-type: alert`,
  `apns-collapse-id` = the collapse key. The payload is an alert with
  `mutable-content: 1` (which wakes the Notification Service Extension),
  `thread-id` = the collapse key, `category: boardhop.pointer` and
  `interruption-level: active` for **everything**, approvals included (D6: no
  time-sensitive entitlement in the beta). The pointer's `data` map sits at the
  **top level**, beside `aps`. A `410`, `BadDeviceToken` or `Unregistered`
  deletes the device row.

  ```json
  {"aps":{"alert":{"title":"!8348 · Tidy the thing","subtitle":"Contoso Demo",
                   "body":"Ada Example replied on !8348"},
          "sound":"default","thread-id":"contoso.pr.8348.t4821","mutable-content":1,
          "interruption-level":"active","category":"boardhop.pointer"},
   "org":"contoso","eventType":"ms.vss-code.git-pullrequest-comment-event",
   "artifactType":"pullRequest","artifactId":"8348","project":"Contoso Demo",
   "title":"!8348 · Tidy the thing","deepLink":"/pull-requests/8348?thread=4821",
   "actor":"Ada Example","actorId":"aaaaaaaa-…","verb":"replied",
   "anchor":"thread:4821","subId":"…","sentAt":"2026-09-13T16:00:00.000Z"}
  ```

- **FCM** (`fcm.dart`): HTTP v1 against
  `https://fcm.googleapis.com/v1/projects/$FCM_PROJECT_ID/messages:send` with a
  service-account OAuth2 token from `googleapis_auth` (refreshed before expiry).
  The message is **data-only**: there is no `notification` block any more,
  because the app posts the notification itself after enrichment (research/06
  decision point 4) and needs to control the lock-screen version (D7). `data` is
  the pointer plus `fallbackTitle`, `fallbackBody`, `fallbackSubtitle` and
  `collapseKey`; `android.collapse_key` is the artifact **family** (`wi`, `pr`,
  `build`, `approval`), because FCM allows four collapse keys per device and the
  exact key is the app's notification tag. `UNREGISTERED` / `NOT_FOUND` deletes
  the device row.

  ```json
  {"message":{"token":"<device token>",
    "data":{"org":"contoso","eventType":"ms.vss-code.git-pullrequest-comment-event",
            "artifactType":"pullRequest","artifactId":"8348","project":"Contoso Demo",
            "title":"!8348 · Tidy the thing","deepLink":"/pull-requests/8348?thread=4821",
            "actor":"Ada Example","actorId":"aaaaaaaa-…","verb":"replied",
            "anchor":"thread:4821","subId":"…","sentAt":"2026-09-13T16:00:00.000Z",
            "fallbackTitle":"!8348 · Tidy the thing",
            "fallbackBody":"Ada Example replied on !8348",
            "fallbackSubtitle":"Contoso Demo","collapseKey":"contoso.pr.8348.t4821"},
    "android":{"priority":"HIGH","ttl":"3600s","collapse_key":"pr"}}}
  ```

  `POST /v1/test-push` sends the same data-only shape (verb `test`,
  `fallbackTitle` "Boardhop", `fallbackBody` "Push is working"), so until R2.4
  teaches the app to post a data-only message itself, a test push arrives as
  data the app handles rather than as an OS notification.

- One JSON log line per send: platform, org, device id, **the last six
  characters of the token only**, artifact, outcome, status and the APNs/FCM id.
  One `notification` line per fan-out on top of that, with recipient, device and
  outcome **counts** and no title, name or detail.

```
POST /v1/test-push
Authorization: Bearer <the user's Azure DevOps access token>
{"org":"puremedia"}
→ 200 {"devices":1,"sent":1,"results":[{"deviceId":"…","platform":"android","outcome":"sent","status":200}]}
```

It can only ever reach the caller's own devices in that org, which is what
makes it safe to keep as the support route.

## Preferences (`/v1/prefs`)

Per `(org, userId)` on the relay, not per device, so two phones agree and a
reinstall keeps them (research/14 §6, decision D5). Same auth as `/v1/devices`:
the user's own Azure DevOps token, validated once against the org through
`connectionData` and then dropped, the same per-org rate bucket and the same
kill switch.

```
GET /v1/prefs?org=puremedia
Authorization: Bearer <the user's Azure DevOps access token>
→ 200 (the document below; the defaults when nothing is stored)

PUT /v1/prefs?org=puremedia
{"builds":"all","quietHours":{"enabled":true,"start":"23:00","end":"06:30"}}
→ 200 (the stored document)
→ 400 {"error":"unknown preference \"buidls\" in body"}
```

The document, with its defaults:

```json
{"enabled": true,
 "workItems": {"assigned": true, "stateChanged": true, "comments": "on",
               "anyChangeOnMine": false},
 "pullRequests": {"reviewRequested": true, "votes": "on", "comments": "on",
                  "completedAbandoned": true, "pushes": false},
 "builds": "failuresAndFixed",
 "approvals": true,
 "quietHours": {"enabled": false, "start": "22:00", "end": "07:00",
                "exceptApprovals": true},
 "mutedArtifacts": [],
 "notActor": true}
```

- **Closed vocabularies.** `workItems.comments` is `on | mentionsOnly | off`;
  `pullRequests.votes` is `on | rejectionsAndWaitsOnly | off`;
  `pullRequests.comments` is `on | mentionsOnly | myThreadsOnly | off`;
  `builds` is `failures | failuresAndFixed | all | off` (the default is D3's
  "failures plus fixed"). Everything else is a switch.
- **A typo is a 400.** An unknown key at any level, a value outside its list, a
  `start` that is not `HH:mm`: the PUT is refused and nothing changes, because a
  silently ignored key would silently switch a notification off. A key left out
  keeps its default.
- **`notActor` is reported, not editable** — it is §5.2 rule 1, shown in the app
  as a fixed line. A client that tries to set it gets
  `{"error":"notActor is not editable"}`.
- **`mutedArtifacts`** is `[{type, id, until}]`: "mute this PR for a day". `type`
  is the family (`wi`, `pr`, `build`, `approval`; the `PushArtifactType` names
  are accepted and normalised), `until` is ISO-8601 or absent for "until it is
  removed". A mute drops **everything** about that artifact, mentions included.
- **Quiet hours** are evaluated on the relay in the **device's** local time,
  from the `tzOffsetMinutes` the app sends with `POST /v1/devices` and each
  heartbeat (−840..840; anything else is a 400, and the window falls back to UTC
  when no device has reported one). A window that ends before it starts crosses
  midnight; `start == end` is all day. Approvals are exempt unless
  `exceptApprovals` is turned off. A suppressed notification is **dropped, not
  delayed** — it still appears in the Activity feed when the app is next opened.
- Stored in `user_prefs (org, user_id, prefs_json, updated_at)`, schema 5. The
  document holds switches and closed vocabularies only, so this table has no
  more content in it than the others.

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

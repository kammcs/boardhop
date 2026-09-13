# 06 — Push notifications via a Marketplace extension, a relay and a push gateway

**Status:** design agreed 2026-09-10; revised 2026-09-13 (Kelly): the relay and the push gateway are two tiers, the gateway is kammcs-hosted for every customer, the relay is shared by default and customer-hosted only as an enterprise option, and the beta with puremedia runs on a private extension and a kammcs server with no Microsoft business relationship. Expo is gone (the app is Flutter). Not yet spiked.
**Problem it solves:** Azure DevOps has no notification inbox API and no push relay (see 01 §6, 05 §8). Service hooks are the only real-time channel, and creating them needs a project administrator, per project, per event type.

## Shape

```
Azure DevOps org (customer)
  │  service hooks, created by the extension, one per project × event type,
  │  "Minimal" resource details, per-org secret in the auth header
  ▼
Relay  (shared kammcs instance by default; customer-hosted container as an enterprise option)
  - authenticates the hook by its org secret; tenant = org
  - maps event → affected users (reviewers, assignee, mentioned, PR author)
  - looks up each user's registered devices for that org
  - forwards an opaque pointer to the gateway (device token, org, event type, artifact id, short title)
  ▲  device registration: the app presents its device token and its own ADO bearer token;
  │  the relay validates it against the org (`connectionData` / `profiles/me`) and never stores it
  │
Push gateway  (kammcs-hosted, one instance for every customer)
  - the only place the APNs key and the FCM service account exist
  - accepts pointers only, over an API key issued per relay instance
  - sends through APNs and FCM
  ▼
Mobile app
  - reads the relay URL from the org's extension data store after sign-in
  - registers its APNs/FCM device token with the relay
  - on notification tap, fetches the artifact with the user's own token
```

Payloads are pointers, never content. Titles beyond a short line, comments and code stay in the tenant; the phone fetches details with the user's own token. This keeps the Google Play data-safety declaration and the App Store privacy answers small.

## The three pieces

**Azure DevOps Marketplace extension** (installed once by an org admin; the customer-side piece)

- Contributes a settings hub under Organization settings.
- Requests `vso.hooks_write` (and `vso.project`) extension scopes so the hub can create and repair webhook subscriptions across all projects in one pass. This removes the per-project, admin-only onboarding wall.
- Stores the relay URL and per-org settings in the Extension Data Service so the mobile app can discover them with the user's token (`vso.extension.data` scope, documents under the extension's collection).
- Shows subscription health (the `SubscriptionStatus` failure states such as `onProbation`, `disabledBySystem`, `jailedByNotificationsVolume`) and a "re-create broken hooks" action.
- Extensions cannot run server code and cannot register custom service hook consumers, so the relay is a separate deployable.
- **Publishing:** a Marketplace publisher is free to create and needs no Partner Center or publisher verification; those enter only for a public listing or for charging through Microsoft. A **private** extension shared with named organizations is installable by their Project Collection Administrators and is the standard pre-release path; the same VSIX flips to public later.

**Relay** (event receiver; multi-tenant)

- A plain container: HTTPS receiver, a small database (SQLite or Postgres) for `(org, userId, deviceToken, preferences)`, outbound calls to the gateway. Nothing in it needs Azure. Behind Caddy on a Hetzner box it costs a few euros a month; as an Azure Container App or Function it costs about the same. Building it as a container from day one keeps both hosting options open.
- **Shared by default:** one kammcs instance serves every org. Tenant identity on every inbound hook (per-org secret) and on every registration (the org the token was validated against); per-tenant rate limits and a kill switch so one org's runaway hooks cannot starve the rest; registrations namespaced by org id.
- **Customer-hosted as an option:** the same container deployed in the customer's Azure (Bicep first, a managed application later if wanted) for enterprises that require event metadata to stay in their tenant. It forwards pointers to the kammcs gateway over an API key issued per relay instance, revocable without touching other customers.
- Event handling: hooks configured with **Resource details to send = Minimal**. The relay derives affected users from the payload (reviewer list, assignee, `changedFields`) and uses server-side filters such as `pullrequestReviewersContains` where the event supports them. De-duplication across projects and event types, per-user preferences (which events, quiet hours).
- Device registration: the app sends its device token plus its ADO bearer token; the relay confirms identity for that org with the token and stores only `(org, userId, deviceToken, preferences)`.

**Push gateway** (kammcs-hosted, single instance)

- Holds the APNs key and the FCM service account. These never sit in a customer instance.
- Accepts only the pointer contract: device token, org, event type, artifact id, an optional short title. Rejects anything else at the boundary; this is the sentence for the privacy policy.
- One HTTPS call per push to Apple or Google; a small server handles millions a day. In the shared deployment the gateway is a module of the relay process; the API-key boundary exists for customer-hosted relays.

## Beta with puremedia (no Microsoft business relationship needed)

1. Create the kammcs Marketplace publisher (free). Publish the extension **private**, share it with the `puremedia` organization by name. A puremedia PCA installs it; a project administrator agrees to the hooks on the CloudCover projects.
2. Run the shared relay plus gateway on the kammcs Hetzner server (the multipass box), behind Caddy, as one container. Kelly's approval covers the server cost.
3. Disclosure to puremedia: with the shared relay, hook metadata (ids, links, event types, sometimes a title) leaves their tenant and lands on the kammcs server; comments and code never do. Get that agreed in writing before the hooks go live.
4. The mobile app already has puremedia's admin consent for the Entra registration; the extension needs nothing from Entra.
5. What the beta gives up: charging through Microsoft and public discoverability. Nothing is thrown away when the listing goes public.

## The audience problem (spike w22/w23, 2026-09-13): Minimal payloads cannot be routed

"Resource details = Minimal" delivers only ids (update number, work item id, project GUID); the PR comment event delivers an empty resource. Nothing in it says who is assigned, who reviews, who wrote the comment or which fields changed, so the relay cannot decide which phones to wake. "All" delivers everything the relay needs (assignee, reviewers, author, changed fields) but also the comment text, the PR description and titles, which is the content the pointer-only design keeps inside the tenant. Options, for Kelly to decide:

1. **All details, strip on receipt.** Hooks send `all`; the relay reads the routing fields, builds the pointer and discards the body without persisting it. Content transits the relay in memory (TLS in, nothing written). Simplest; honest disclosure for the beta; the customer-hosted relay remains the answer for tenants that cannot accept transit.
2. **Minimal details plus a relay identity that reads the artifact.** Hooks stay `minimal`; the relay fetches the update or PR by id with its own identity and computes the audience. Nothing beyond ids ever transits, and the same identity answers the live-log SignalR question. The identity has to be provisioned per org: a customer-issued PAT stored in the relay (expires, is a person's token), or a **service principal**: Azure DevOps admits Entra service principals as members, and Boardhop's multi-tenant app registration already exists, so the customer admin adds the Boardhop service principal to their org with Basic access and the relay takes client-credential tokens for that tenant. Costs the customer one Basic seat unless within the free five, needs a client secret or certificate held at kammcs, and one more spike (s40: service principal membership and the scopes it reaches).
3. **Per-user subscriptions with server-side filters.** `git.pullrequest.*` supports `pullrequestReviewersContains`, work item events only `areaPath`, `workItemType` and `changedFields`; so it covers PR review requests but not "assigned to me" or "mentioned me", and multiplies subscriptions by users. Not sufficient on its own.

Recommendation: **1 for the puremedia beta** (with the disclosure already planned), **2 with a service principal as the product path** for the shared relay, and the customer-hosted relay for tenants that want neither. The pointer contract at the gateway is unchanged in every option. **Decided by Kelly the same day: see the next section.**

## Decision (Kelly, 2026-09-13): ingest All, keep metadata, enrich on the device

Kelly's requirement: a push must be meaningful on its own (who did what to which artifact) and deep-link into the work item, pull request, run or approval that raised it. Stripping to a bare pointer would not meet that; forwarding content through the gateway would break the pointer promise. The decision:

1. **Hooks send `resourceDetailsToSend: all`** (Minimal cannot be routed, see above). The relay reads the payload in memory to determine the actor, the audience and the artifact, and **persists nothing from the body**: not the payload, not titles, not comment text. Only the pointer it emits is logged (ids, event type, redacted token).
2. **The pointer carries metadata, never content.** `PushPointer` grows from `org, eventType, artifactType, artifactId, project, title(≤80), deepLink` to also carry `actor` (display name) and a `verb` the app can render ("replied on", "assigned you", "failed at Deploy"). Titles are metadata the customer sees in every list view; comment bodies, descriptions and diffs are content and stay out. The gateway keeps rejecting anything beyond the pointer type at compile time.
3. **The relay sends the pointer line as the visible fallback** (for example "Javier Perez replied on !8261 · Shai triage agent"), so a notification is useful even when enrichment fails or the device is offline.
4. **The device enriches before display, with the user's own token.** iOS: the push is sent as an alert with `mutable-content: 1`; a **Notification Service Extension** target in the Runner wakes on arrival, obtains a silent token from MSAL (the `com.microsoft.adalcache` keychain group is shared with the extension), fetches the comment, PR or run with the app's existing repositories (or a slim client), rewrites title and body, and hands the notification back; on any failure it shows the pointer line unchanged. Android: the push is a **data-only message at `HIGH` priority**; `BoardhopMessagingService.onMessageReceived` (already present from R1) fetches the same details inside its execution window and posts the notification through the existing channel, again falling back to the pointer line. Content therefore never touches the relay, Apple or Google.
5. **No snippet option.** The relay will not forward comment previews; if puremedia wants previews before enrichment ships, that is a request to build enrichment sooner, not to widen the pointer.
6. **Deep links are the pointer's `deepLink`**: the app's account-scoped route (`lib/core/routes.dart`) to the artifact, resolved on tap through the existing router; the event-to-route mapping and the on-device behaviour per event are the next design item (NEXT-STEPS item 19, R2).

Product path unchanged: the service principal per org (spike s40) lets hooks return to Minimal by having the relay read the artifact itself; the enrichment step is the same either way.

## What it buys beyond notifications

- A clean data story: pointer-only pushes, credentials only at kammcs, an enterprise option with the relay in the customer's tenant.
- A natural paid tier: individuals keep the free foreground polling; teams pay for the extension and the shared relay; enterprises run their own relay.
- A place for per-user preferences and future features (digest emails, Teams cards) without touching the mobile app.
- **Live task log tail (deferred here 2026-09-11, Kelly's call).** Spikes s20, s21, w12 and w13 showed the agent uploads a task's log only when the task finishes, even for 18 KB of output, so the app's REST reads cannot follow a running task; the web console gets its live lines from the undocumented SignalR feed the agent appends to (`AppendTimelineRecordFeed`). The relay (shared or customer-hosted; hosting does not change this) holds that SignalR subscription for the runs a person is following and either pushes small line batches through the gateway or buffers them for the app to pull once woken. **Open question:** whose identity the relay subscribes with (a service-account PAT the customer provisions, or the user's delegated token forwarded for the length of a Follow). The app side stays small: a "Follow" toggle on the run and log pages that subscribes through the relay, with the REST log read as the fallback when no relay is configured.

## What it does not fix

- Personal Microsoft account sign-in (still Entra-only at launch).
- Conditional Access tenants that require a managed device.
- Anything while the app is force-quit on iOS is fine (push still arrives), but the app cannot pre-fetch content in the background reliably.

## Server

The relay runs on a dedicated Hetzner CX23, `boardhop-relay-1`, at
**boardhop.relay.kammcs.com** — Caddy (automatic Let's Encrypt HTTPS) in front of
a Dart `shelf` container, both from `/srv/relay/compose.yml`. The source of
truth is **`relay/` in this repo**, and `relay/README.md` covers what runs there,
`relay/deploy.sh`, `relay/rollback.sh`, where the logs are, and how a spike reads
the capture secret over ssh without ever printing it.

As of 2026-09-13 the box serves `GET /healthz` and the spike-3 capture endpoint
`POST|GET /capture/{name}` (HTTP basic, user `hook`, per-post JSON files capped
at 1 MB each and 200 files per name), plus everything in "R1 notes" below.
`/srv/relay/secrets` is mounted read-only at `/secrets` and holds the APNs `.p8`
(B2) and the FCM service account (B3).

## R1 notes (2026-09-13): device registration and the push gateway

**What landed.**

- **Relay.** `POST /v1/devices`, `DELETE /v1/devices/{id}`,
  `POST /v1/devices/{id}/heartbeat` and `POST /v1/test-push`, each
  authenticated with **the user's own Azure DevOps access token**, validated
  once against the org with `GET /_apis/connectionData?api-version=7.1-preview`
  and then dropped — never stored, never logged. Stored per device:
  `(id, org, userId, userDescriptor, platform, token, appVersion, locale,
  createdAt, lastSeenAt)`, idempotent on `(org, token)`. A token bucket per org
  (120, refilling 1/s) and an `orgs` kill-switch table sit in front. A device
  belonging to someone else answers 404, like one that does not exist.
  `GET /v1/admin/devices?org=` (guarded by `RELAY_ADMIN_SECRET`) returns counts
  and platforms only.
- **Gateway.** `PushPointer` — `org`, `eventType`, `artifactType`
  (workItem | pullRequest | build | approval), `artifactId`, `project`, optional
  `title` truncated to 80, optional `deepLink` — is the only thing
  `PushSender.send` accepts, so the pointer-only promise above is enforced by
  the type rather than by review. APNs goes over HTTP/2 (`http2`; Dart's
  `HttpClient` is 1.1 only) with an ES256 JWT from the `.p8` cached for 50
  minutes and a collapse id per artifact; FCM goes over HTTP v1 with a
  service-account token. `410`/`BadDeviceToken` and `UNREGISTERED`/`NOT_FOUND`
  delete the device row. One log line per send carries the platform, status and
  push id, and **at most the last six characters of the device token**.
- **App.** `lib/features/notifications/`: `PushRegistrar` (register, daily
  heartbeat, delete on sign-out, re-register after a 401 or a token rotation),
  `PushService` (FCM on Android; on iOS a method channel to the Runner, because
  there is no Firebase iOS app), `PushCoordinator` (which signed-in account an
  organization belongs to, foreground pushes shown through the feed's existing
  `flutter_local_notifications` channel, taps routed through the existing
  router) and a push row on the Activity feed with a **Send test** button.
  Registration follows the same opt-in as the local notifications: turning them
  off unregisters.

**Getting an FCM token on Android took three changes, and the reason is worth
keeping.** `FirebaseMessaging.getToken()` failed on the Pixel 10 Pro emulator
(Android 17, Play services 26.33) with `java.io.IOException: FCM Registration
failed!` — a message that wraps the real cause and never shows it. The Firebase
project was fine: `GET /v1/admin/fcm-check` on the relay (a `validate_only` send
to a bogus token) answered `INVALID_ARGUMENT`, which means the service account
authenticated and FCM accepted the call. The fault was the client registration
path:

1. `firebase-messaging` 25.x only uses the Firebase-Installations ("v1")
   registration when the app's manifest carries
   `firebase_messaging_installation_id_enabled = true`
   (`GmsRegistrationClient.isV1RegistrationEnabled()` reads exactly that key and
   otherwise returns false). Without it the SDK takes the legacy Play-services
   path, which now fails. With it, registration succeeds.
2. Under that flag the SDK **disables** `getToken()` and `deleteToken()` and
   wants `register()` / `unregister()`, which `firebase_messaging` does not
   expose. Hence the `com.kammcs.boardhop/push` method channel in
   `MainActivity.kt` — the same channel name the iOS Runner answers.
3. `register()` returns `Task<Void>`; the token is reported separately. And
   here is the trap: with the Installations registration in force,
   `FirebaseMessaging.invokeOnRegistrationChanged` still **logs** "Invoking
   onNewToken" but sends the intent action
   `com.google.firebase.messaging.FCM_REGISTERED`, which
   `FirebaseMessagingService` dispatches to **`onRegistered`** — and
   `firebase_messaging` only overrides `onNewToken`. The token was therefore
   minted, logged, delivered to the plugin's service, and silently dropped.
   `BoardhopMessagingService` (the plugin's service plus an `onRegistered` that
   posts into the plugin's own `FlutterFirebaseTokenLiveData`) replaces it in
   the manifest, and `MainActivity` observes that same LiveData and forwards
   the token over the push channel.
4. Even so, the token is announced once. With Firebase auto-init on that
   happens during the `ContentProvider` start, before any Dart listener exists.
   So auto-init is off in the manifest
   (`firebase_messaging_auto_init_enabled = false`), the app calls
   `setAutoInitEnabled(true)` only once the user has turned notifications on —
   which is the privacy behaviour we want anyway, no FCM registration for
   someone who never opts in — and `PushService` writes the token to shared
   preferences, because later launches get no repeat.

A last surprise: a token from this registration path is **22 characters**, not
the ~160 of a classic FCM token, and FCM accepts it (`/v1/test-push` came back
with a message id). The relay's token sanity check was loosened to 16
characters because of it.

**Verified on the Pixel 10 Pro emulator (Android, puremedia):** registration,
the `devices` row, a test push arriving in the foreground and in the shade with
the app backgrounded, and the tap opening the deep link.

**Unverified.**

- **APNs is off.** Apple's ten-character **Key ID** for the `.p8` is still
  unknown (NEXT-STEPS item 19, B2), and without it no JWT can be signed;
  `/healthz` reports `apns: disabled (no key id)` and every APNs send is skipped
  rather than attempted. Nothing on the Apple path — the JWT, the HTTP/2
  connection, the 410 handling — has ever run.
- **The whole iOS client side is unbuilt.** The `com.kammcs.boardhop/push`
  method channel in `AppDelegate.swift`, the `aps-environment` entitlement and
  the `remote-notification` background mode were written on Windows and have
  never been compiled. A pushed notification **tapped** on iOS also has no route
  home yet: `UNUserNotificationCenter`'s delegate belongs to
  `flutter_local_notifications`, which forwards only its own notifications, so
  only foreground and `didReceiveRemoteNotification` deliveries reach Dart.
  Settle that when the Key ID and a physical iPhone (B4) exist — APNs does not
  reach the simulator.
- The relay still has no event→user mapping: the only thing that sends today is
  `/v1/test-push`. "The audience problem" above is unchanged and is the next
  decision.

**One thing to remember before CI exists.** `android/app/google-services.json`
is gitignored (it carries the Firebase Android API key) and the
`com.google.gms.google-services` Gradle plugin **fails the Android build when it
is missing**. A clean clone — and any CI runner, whenever Kelly decides to have
one — therefore needs that file supplied as a secret, exactly like `.env` and
`android/secret.properties`.

## Spikes before building

1. Confirm the Extension Data Service documents are readable from the mobile app with the user's Entra token and the `vso.extension.data` scope.
2. Confirm an extension hub with `vso.hooks_write` can create webhook subscriptions in every project for an org admin, and what happens for projects where the admin lacks rights.
3. ~~Capture webhook payload shape~~ **done 2026-09-13 (w22/w23)**: see "The audience problem" above and `research/spikes/results/README.md`. The Minimal set of nine hooks stays on the scratch project.
4. Push end to end: FCM (Android) and APNs (iOS, needs a physical iPhone or a TestFlight build) from a gateway on the Hetzner box, measuring latency from hook to phone.
5. Private publish: create the publisher, publish a hello-world extension privately, share it with `puremedia`, and confirm the install and the data-store read from the app.
6. SignalR feed: from the relay, subscribe to a running scratch pipeline's timeline feed with a PAT and confirm lines arrive while the task runs; then decide the identity question above.

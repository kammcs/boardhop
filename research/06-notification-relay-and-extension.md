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

## What it buys beyond notifications

- A clean data story: pointer-only pushes, credentials only at kammcs, an enterprise option with the relay in the customer's tenant.
- A natural paid tier: individuals keep the free foreground polling; teams pay for the extension and the shared relay; enterprises run their own relay.
- A place for per-user preferences and future features (digest emails, Teams cards) without touching the mobile app.
- **Live task log tail (deferred here 2026-09-11, Kelly's call).** Spikes s20, s21, w12 and w13 showed the agent uploads a task's log only when the task finishes, even for 18 KB of output, so the app's REST reads cannot follow a running task; the web console gets its live lines from the undocumented SignalR feed the agent appends to (`AppendTimelineRecordFeed`). The relay (shared or customer-hosted; hosting does not change this) holds that SignalR subscription for the runs a person is following and either pushes small line batches through the gateway or buffers them for the app to pull once woken. **Open question:** whose identity the relay subscribes with (a service-account PAT the customer provisions, or the user's delegated token forwarded for the length of a Follow). The app side stays small: a "Follow" toggle on the run and log pages that subscribes through the relay, with the REST log read as the fallback when no relay is configured.

## What it does not fix

- Personal Microsoft account sign-in (still Entra-only at launch).
- Conditional Access tenants that require a managed device.
- Anything while the app is force-quit on iOS is fine (push still arrives), but the app cannot pre-fetch content in the background reliably.

## Spikes before building

1. Confirm the Extension Data Service documents are readable from the mobile app with the user's Entra token and the `vso.extension.data` scope.
2. Confirm an extension hub with `vso.hooks_write` can create webhook subscriptions in every project for an org admin, and what happens for projects where the admin lacks rights.
3. Capture webhook payload shape with "Minimal" resource details for `git.pullrequest.updated`, `workitem.updated`, `ms.vss-work.work-item-comment-event`, `build.complete`, and `ms.vss-pipelinechecks-events.approval-pending`, against the scratch project with a hook pointing at a capture endpoint on the kammcs server; record exactly which fields (and whether titles) leave the tenant.
4. Push end to end: FCM (Android) and APNs (iOS, needs a physical iPhone or a TestFlight build) from a gateway on the Hetzner box, measuring latency from hook to phone.
5. Private publish: create the publisher, publish a hello-world extension privately, share it with `puremedia`, and confirm the install and the data-store read from the app.
6. SignalR feed: from the relay, subscribe to a running scratch pipeline's timeline feed with a PAT and confirm lines arrive while the task runs; then decide the identity question above.

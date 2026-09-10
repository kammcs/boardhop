# 06 — Push notifications via a Marketplace extension and a tenant-hosted relay

**Status:** design sketch, agreed direction (2026-09-10). Not yet spiked.
**Problem it solves:** Azure DevOps has no notification inbox API and no push relay (see 01 §6, 05 §8). Service hooks are the only real-time channel, and creating them needs a project administrator, per project, per event type.

## Shape

```
Azure DevOps org
  │  service hooks (created by the extension, one per project × event type)
  ▼
Relay in the customer's Azure subscription
  Azure Function (HTTPS webhook receiver) + Table storage
  - maps event → affected users (reviewers, assignee, mentioned, PR author)
  - looks up each user's registered devices
  - sends a minimal pointer (org, event type, artifact id) to the push gateway
  ▲  device registration (mobile app, authenticated with the user's own ADO token)
  │
Mobile app
  - reads the relay URL from the org (extension data store) after sign-in
  - registers its Expo push token with the relay
  - on notification tap, fetches the artifact with the user's own token
```

## The two customer-side pieces

**Azure DevOps Marketplace extension** (installed once by an org admin)

- Contributes a settings hub under Organization settings.
- Requests `vso.hooks_write` (and `vso.project`) extension scopes so the hub can create and repair webhook subscriptions across all projects in one pass. This removes the per-project, admin-only onboarding wall.
- Stores the relay URL and per-org settings in the Extension Data Service so the mobile app can discover them with the user's token (`vso.extension.data` scope, documents under the extension's collection).
- Shows subscription health (the `SubscriptionStatus` failure states such as `onProbation`, `disabledBySystem`, `jailedByNotificationsVolume`) and a "re-create broken hooks" action.
- Extensions cannot run server code and cannot register custom service hook consumers, so the relay is a separate deployable.

**Relay** (deployed into the customer's Azure)

- Distribution: a "Deploy to Azure" Bicep/ARM template first; an Azure Marketplace managed application later if customers want controlled updates.
- Runtime: Azure Functions consumption plan, Table storage for the device registry and preferences. Cost is negligible.
- Device registration: the app sends its Expo push token plus its ADO bearer token. The relay confirms identity by calling `profiles/me` (or `connectionData` on the org) with that token, then stores `(userId, deviceToken, preferences)`. It never stores the token.
- Event handling: service hooks configured with **Resource details to send = Minimal**. The relay derives affected users from the event payload (reviewer list, assignee, `changedFields`) and uses server-side filters such as `pullrequestReviewersContains` where the event supports them.
- De-duplication across projects and event types, plus per-user preferences (which events, quiet hours).

## The push-credential wrinkle

Sending to APNs and FCM needs the app's APNs key and FCM service account. Those cannot be distributed to customers. Two options:

1. **Expo Push API.** The relay calls Expo's push service with the device's Expo push token. Simple, but payloads transit Expo's infrastructure.
2. **A tiny gateway you host** that holds the APNs/FCM credentials and accepts only the minimal pointer.

Either way the payload is a pointer, never content. Titles, comments and code stay in the tenant; the phone fetches details with the user's own token. This keeps the Google Play data-safety declaration small and gives enterprises a clean answer to "where does our data go".

## What it buys beyond notifications

- Enterprise trust: no vendor-hosted store of customer data.
- A natural paid tier: individuals keep the free foreground polling; teams pay for the extension and relay.
- A place for per-user preferences and future features (digest emails, Teams cards) without touching the mobile app.

## What it does not fix

- Personal Microsoft account sign-in (still Entra-only at launch).
- Conditional Access tenants that require a managed device.
- Anything while the app is force-quit on iOS is fine (push still arrives), but the app cannot pre-fetch content in the background reliably.

## Spikes before building

1. Confirm the Extension Data Service documents are readable from the mobile app with the user's Entra token and the `vso.extension.data` scope.
2. Confirm an extension hub with `vso.hooks_write` can create webhook subscriptions in every project for an org admin, and what happens for projects where the admin lacks rights.
3. Measure webhook payload shape with "Minimal" resource details for `git.pullrequest.updated`, `workitem.updated`, `ms.vss-work.work-item-comment-event`, `build.complete`, and `ms.vss-pipelinechecks-events.approval-pending`.
4. Decide Expo Push API versus a self-hosted gateway, and test end-to-end latency.
5. Marketplace publisher and Partner Center lead time.

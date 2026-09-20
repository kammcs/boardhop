# Paid tier: billing, accounts and licence enforcement

**Status:** research pass and interview with Kelly on 2026-09-20. Nothing built, nothing spiked.
This file is deliberately unnumbered and standalone (no edits to `research/README.md`,
`NEXT-STEPS.md` or any other document) because other work was in flight; give it a number and
index it when it is merged.

**How this was researched.** Four parallel web-research agents (Microsoft billing options; a survey
of paid Azure DevOps extension vendors; install-validation mechanics; app-store rules and billing
providers), reconciled at the top level. **Their sources were not re-opened at the top level**,
with one exception: the two Stripe Managed Payments pages in section 5 were fetched and read
directly. Nothing was probed against a live Azure DevOps organization. Items the agents could not
verify are collected in section 8; treat everything else as "documented, not tested".

## 0. Decisions (Kelly, 2026-09-20)

1. **Listing:** the extension stays a **free** Marketplace listing; the paid thing is the relay
   service, gated server-side per organization. (A listing marked free can never become paid, so
   this is a one-way door taken on purpose.)
2. **Pricing unit:** per **active user** per month, where active means **the user opened the app
   for that organization during the month** (the app checked in with the relay), whether or not a
   push was delivered.
3. **Price:** **$3 per active user per month**, **$15 monthly minimum** (five users), **annual at
   about ten months' price**. The price assumes the paid tier grows beyond push: **live pipeline
   log tail** is in; the rest of the feature list is not decided yet.
4. **Buyers:** organizations only. No plan an individual buys for themselves; individuals keep the
   free foreground polling (research/06).
5. **Checkout:** inside the extension's admin hub, opening **hosted checkout**; hosted customer
   portal for invoices and cancellation. boardhop.dev carries marketing and legal pages only; no
   separate account portal for now.
6. **Provider:** **Stripe Managed Payments** (Stripe as merchant of record). Kelly already uses it
   for another product and will continue. Paddle and the others in section 5 are recorded for
   context only.
7. **Billing mechanics** (quantity update, metered price, or bands): **decided after a sandbox
   check** in Kelly's existing Stripe account (section 5).
8. **Trial:** 30 days, no card, whole organization, starting at the first admin visit to the hub.
   At the end push pauses and everyone falls back to free polling; hooks stay in place so
   subscribing resumes at once. Reminders 7 days before the end and at the end.
9. **Who can start the trial and subscribe:** Project Collection Administrators only, checked
   server-side. A separate billing-contact email is collected at checkout.
10. **Beta organizations** (puremedia and others): free during the beta, then the normal trial.
    Kelly needs **admin latitude to extend a trial or comp a specific organization**; the same
    mechanism serves the demo organization for App Review.
11. **Microsoft commercial marketplace SaaS offer:** deferred until a customer's procurement asks.
12. **Customer-hosted enterprise relay:** out of scope here; an annual contract by quote later,
    outside Managed Payments.

Already in place: a legal entity, and the domain **boardhop.dev**.

## 1. Does billing run through Microsoft?

No, not through the Visual Studio Marketplace.

- Microsoft stopped first-party billing for third-party Azure DevOps extensions in 2019
  ("A simpler way to buy Azure DevOps", Azure DevOps blog, 2019-05-06:
  https://devblogs.microsoft.com/devops/a-simpler-way-to-buy-azure-devops/).
- The current manifest reference
  (https://learn.microsoft.com/en-us/azure/devops/extend/develop/manifest?view=azure-devops) says:
  "Bring-Your-Own-License (BYOL) means the publisher of the extension provides the billing and
  licensing mechanism for the extension, as it isn't provided by Microsoft for Azure DevOps
  extensions."
- A paid listing is `"galleryFlags": ["Paid"]` plus the tag `__BYOLENFORCED`, a `content.pricing`
  page, privacy, support and EULA links, a `licensing.overrides` entry per contribution
  (`behavior: "AlwaysInclude"`), and optionally `galleryproperties.trialDays`. It buys a "Paid"
  label, a Pricing tab and a trial badge. Microsoft enforces nothing.
- The same page: **"An extension marked free can't be changed to paid."** The publish overview
  says "Only free extensions might be unpublished."
- Boardhop's choice (decision 1) sidesteps all of this, the way Aha!, TestRail and SonarCloud list
  a free extension and charge for the service behind it.

**The one Microsoft-run channel** is a transactable SaaS offer in Microsoft's commercial
marketplace through Partner Center:

- 3% store fee; flat-rate or per-user plans, monthly or annual; private offers; free trials.
- Requires Partner Center enrollment, the SaaS fulfillment API v2, a landing page with Entra
  single sign-on, and a webhook.
- Payout threshold $50; low-volume revenue arrives roughly 45 to 75 days late.
- The buyer needs an Azure subscription; small teams on five free Azure DevOps users often have
  none.
- Counting toward a customer's Azure consumption commitment (MACC) needs about $100k of trailing
  marketplace sales and an Azure-hosted solution; the relay is on Hetzner.
- There is no integration with the Visual Studio Marketplace listing; the organization-to-
  subscription mapping is the same work either way.
- The agents found no Azure DevOps extension vendor that clearly bills through Microsoft. 7pace
  has a Microsoft marketplace listing but sells inside its extension.

If this is ever added (decision 11), design the entitlement table (section 4) so a second billing
source can set the same fields.

## 2. How other vendors do it

A scan of the public gallery API found 119 paid listings among the top 3,000 cloud extensions; the
Pricing tabs of about 25 were read.

- **Checkout** is most often inside the extension, in an organization-settings hub for admins,
  backed by Stripe or Paddle. Sending the buyer to a separate site is rarer. Pasted licence keys
  survive only with on-prem and enterprise vendors.
- **Licence subject** is the Azure DevOps organization.
- **Pricing shapes:** named seats an admin assigns (7pace $8 to $17, Planning Poker $2.50,
  ActionableAgile $20, Enhanced Export PRO about €4 to €6), or flat organization tiers by user
  count (Great Gadgets $10 per month up to 10 users, Documentero $79 under 50 users, Time in
  State free to 10 users). A flat price per organization also exists (InnovaApps code reviewer
  $100 per month). Small utilities cluster at $2.50 to $6 per seat. **No surveyed vendor bills
  per active user**, so Boardhop's unit is unusual and needs a clear explanation in the hub.
- **Trials** declared on the 119 listings: 30 days 61, 14 days 8, 28 days 6, 7 days 5, none 32.
  They start on install or first use with no card. Documentero and Bravo Notes advertise that
  nothing is charged automatically.
- **After the trial** a free tier is common. Boardhop's already exists (foreground polling).
- **Pitfalls vendors mention:** disputes over who counts as a user (letting the customer see the
  counted list defuses it); purchase orders, supplier registration and bank transfer offered only
  above a minimum spend (mskold above €1,000); tax handled by a merchant of record where the
  vendor is small (Documentero uses Paddle); refunds by contacting support, cancellation at period
  end.

## 3. App store rules

The agents' conclusion: an organization-level web subscription can unlock features in the app
without in-app purchase on both stores, **provided the app and its store listings carry no price,
upgrade prompt, "Pro" wording or pricing link.**

- **Apple 3.1.3(c), enterprise services:** "only sold directly by you to organizations or groups
  for their employees… Consumer, single user, or family sales must use in-app purchase." Decision
  4 keeps Boardhop inside it. Per-user pricing is fine when the organization is the buyer.
- **Apple 3.1.3(f):** free companion apps to a paid web tool, "provided there is no purchasing
  inside the app, or calls to action for purchase outside of the app." The second leg.
- US link-outs are currently allowed and free, the EU terms change on 2026-10-01, and both are
  in litigation or flux. **Ship one global binary with no link anywhere.**
- **Google Play:** the payments FAQ says any app may be consumption-only even when it is part of
  a paid service. Do not enroll in the link-out or alternative billing programs.
- **Wording in the app:** "Push notifications for this organization are turned on by an Azure
  DevOps administrator through the Boardhop extension." The same pattern for the log tail.
- **App Review notes:** cite 3.1.3(c) and 3.1.3(f), state that subscriptions are sold to
  organizations only, and provide a demo organization with the relay enabled (decision 10's comp
  flag). One December 2025 forum thread shows a login-only B2B app rejected under 3.1.1; that app
  sold to individuals.
- Comparable US listings with no in-app purchases: PagerDuty, Slack, Linear. GitHub has them
  because it sells to individuals.

## 4. Validating the install and enforcing the licence

**Principle:** enforce only at the relay (hook intake, push fan-out, log-tail sessions). The
extension and the app display state; they never decide it.

**Handshake (agent's recommended pattern, not spiked):**

1. The hub sends the relay `SDK.getAppToken()` (a JWT signed with the extension secret from the
   publisher portal's Certificate action) and `SDK.getAccessToken()` plus the organization name.
2. The relay verifies the app token's signature and expiry. This proves "our extension".
3. The relay calls `GET https://dev.azure.com/{org}/_apis/connectionData` with the access token
   and reads `instanceId` (the immutable organization GUID) and `authenticatedUser.id`. The client
   cannot forge these.
4. The relay calls `GET https://extmgmt.dev.azure.com/{org}/_apis/extensionmanagement/
   installedextensionsbyname/{publisher}/{extension}?api-version=7.1` and checks `installState`.
5. The relay checks Project Collection Administrator membership with the same token (decision 9).
6. The relay mints its own short-lived session token (`org_id`, `user_id`, `plan`) and **discards
   the Azure DevOps access token; it is never stored.**

Why not the app token alone: its claims are undocumented, and an open SDK issue reports `nameid`
mismatches (https://github.com/microsoft/azure-devops-extension-sdk/issues/16). Microsoft also
says to treat Azure DevOps tokens as opaque.

**Operational hazard:** the auth doc says "Scope changes cause the certificate to change." The
relay must accept the current and the previous extension secret during a scope bump.

**Entitlement record, keyed by organization GUID** (never the name; organizations get renamed):
name (refreshed each handshake), Entra tenant id, trial start and end, status (trial, active,
past due, paused, comped), Stripe customer and subscription ids, billing-contact email, comp or
trial-extension override with who set it and why (decision 10), last handshake time.

**Active-user count (decision 2):** the relay records distinct `user id` per organization per
calendar month from app check-ins. The hub shows the counted list to admins so the bill can be
checked. The privacy page must say this is stored.

**Other findings:**

- Extension Data Storage is readable and writable by anyone who can load the extension, so it may
  cache a status for display and must not be the source of truth.
- No webhook exists for install or uninstall. The gallery API `getExtensionEvents` (7.2 preview)
  exposes install, uninstall and acquisition events and can be polled with the Marketplace PAT.
  Hooks going silent is the other signal.
- Payment failure: 7 to 14 days of grace with a banner in the hub, then pause push. Do not delete
  hooks.
- Ownership change does not matter when the licence is on the organization GUID; any Project
  Collection Administrator can reclaim through a handshake.

## 5. Stripe Managed Payments

**Read directly on 2026-09-20** (https://docs.stripe.com/payments/managed-payments and
https://docs.stripe.com/payments/managed-payments/eligibility):

- Stripe is the merchant of record and handles sales tax, VAT and GST in more than 80 countries,
  plus fraud, disputes and transaction-level support.
- Subscriptions are supported through Billing, but only when **created through Checkout or
  Payment Links**. Elements and other advanced integrations, and Connect, are unsupported.
- Unsupported: "Attaching invoice items on a `Customer` object to a Managed Payments
  subscription" and "Generating a one-off invoice… outside the billing period". So usage cannot
  be billed in arrears by adding invoice items, and pay-by-invoice deals do not fit.
- US businesses are supported. Business-use SaaS is an eligible tax code (`txcd_10103001`).
- Eligibility is reviewed per account and needs a low dispute rate. Stripe may refund within 60
  days of purchase in some cases.
- **Neither page mentions metered prices (Billing meters) or changing a subscription's quantity
  after checkout.**

**Fees (agent, from stripe.com, not re-read):** 3.5% for Managed Payments on top of 2.9% + $0.30,
plus 0.7% for Billing and 1.5% for international cards. On the $15 minimum that is roughly $1.40
to $1.65; on a $3 charge the fixed $0.30 alone would be 10%, which is why the floor exists.

**Sandbox checks that decide decision 7** (Kelly's existing account, test mode, no cost):

1. Can a Checkout-created Managed Payments subscription have its **quantity updated** through the
   API, and what happens with proration (prorations create invoice items, which may hit the
   restriction above)? If yes with `proration_behavior: none`: set quantity to
   `max(5, last month's active users)` before each renewal.
2. Does Checkout accept a **metered price** backed by a Billing meter under Managed Payments? If
   yes: report one meter event per active user; the $15 floor then needs a separate fixed
   component or a tier.
3. Failing both: **bands** (for example 1 to 5, 6 to 20, 21 to 50, 51 to 200 active users) as
   fixed prices, moving the subscription between prices at renewal.
4. **Annual plan:** per-active-user does not map cleanly onto a year paid up front. Options to
   test: a committed quantity for the year with growth applied at renewal, or annual offered only
   on bands.
5. A 30-day trial **without a payment method** through Checkout, and tax-id collection with
   reverse charge for EU and UK business buyers.
6. Passing the organization GUID as `client_reference_id` or metadata and getting it back on the
   `checkout.session.completed` and subscription webhooks.

**Provider context (not chosen):** Paddle 5% + $0.50 with invoices, PO numbers and bank transfer,
the agent's pick absent an existing provider; Lemon Squeezy winding into Stripe; Polar and
FastSpring also merchants of record; plain Stripe Billing plus Stripe Tax is cheapest but leaves
tax registration with the seller, and becomes the better choice around $10k to $20k a month or
when buyers insist on invoices in the seller's name.

## 6. What to build

1. **Relay:** entitlement table (section 4), handshake endpoint, monthly active-user ledger,
   Stripe webhook receiver, enforcement at hook intake, push fan-out and log tail, trial clock,
   reminder emails, an admin command to extend a trial or comp an organization.
2. **Extension hub (admins):** plan status, trial days left, the counted active users, Subscribe
   (hosted Checkout with the organization GUID attached), Manage billing (hosted portal), banners
   for trial end and payment failure. `extension/src/plan.ts` stays in step with the relay as
   today.
3. **App:** reads the organization's entitlement from the relay and shows the neutral wording from
   section 3. No price, no upgrade, no link.
4. **boardhop.dev:** pricing, terms of service, privacy policy (including the active-user ledger),
   refund policy, a data processing addendum customers can self-sign, a subprocessor list
   (Hetzner, Apple APNs, Google FCM, Stripe, the email sender), a security page with a contact.
   SOC 2 is deferred until a deal requires it; data minimization (pointer-only pushes) is the
   strong answer in questionnaires.
5. **Entra publisher verification** (research/09 A6) before public launch, so users in tenants
   that allow consent only for verified publishers can sign in. It needs a Partner Center account
   linked to the kammcs tenant, which is also the prerequisite for a later SaaS offer.

**Costs to raise with Kelly before doing them:** an email-sending service for reminders; Partner
Center enrollment (the agent found no fee, unverified). Stripe fees apply only to real charges.

## 7. Open questions

- The paid feature list beyond push and live log tail.
- Decision 7 and the shape of the annual plan, after the sandbox checks.
- Whether the hub's existing scopes are enough for the administrator check, or a scope must be
  added (which rotates the extension secret).
- How a finance buyer without Azure DevOps access pays: the hosted Checkout link can be forwarded,
  but this is untested, and it is the case that would justify a small web portal later.
- Whether the Marketplace listing should mention pricing at all, given the listing is free. The
  app-store restriction applies to the app and its store metadata, not to the Marketplace page or
  boardhop.dev.

## 8. Not verified

From the agents' own flags: whether the app token carries the organization id, and its lifetime;
whether non-admins can call the entitlement endpoints; the property names in `getExtensionEvents`;
the `x-vss-resourcetenant` header on `vssps.dev.azure.com/{org}`; the 2019-07-01 cut-off date;
whether any vendor's Microsoft marketplace listing is transactable; Partner Center enrollment
cost and any minimum plan price; Google's link-out fee; the Supreme Court filing date in Epic v.
Apple; how widely Stripe Managed Payments is available and how it handles tax ids; the payment
processors behind 7pace, Bravo Notes and mskold; VAT and US nexus thresholds (from memory). A
single read-only spike against the scratch organization would settle the first four.

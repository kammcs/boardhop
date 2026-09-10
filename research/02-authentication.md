# 02 — Authentication & Organization Discovery for a Third-Party Azure DevOps Mobile App

**Scope:** React Native / Expo app, iOS + Android, phone + tablet, third-party (not first-party Microsoft), targeting **Azure DevOps Services** (cloud) with Azure DevOps Server (on-prem) as a possible later phase.

**Research date:** 2026-09-10. All Microsoft Learn pages cited were fetched on this date; where a page carries an `ms.date` / `updated_at` stamp it is quoted so staleness can be judged.

**Confidence markers used throughout:** statements sourced directly from Microsoft docs or Microsoft blogs are cited inline. Anything inferred, community-sourced, or not directly confirmed is explicitly marked **(unverified)**.

---

## 1. Executive summary

### 1.1 The short version

1. **The legacy "Azure DevOps OAuth" app platform (`app.vssps.visualstudio.com/oauth2`) is closed to us.** New app registrations stopped **April 23, 2025**, and the platform is scheduled for end-of-life **in 2026** (exact date still unannounced as of this research). We *cannot* register a new app there, so it is not an option at all — not even as a fallback. It is included in the comparison table only for completeness.
2. **Microsoft Entra ID OAuth 2.0 (authorization code + PKCE, public client) is the primary and only viable OAuth path** for a third-party mobile app against Azure DevOps Services. It uses the Azure DevOps resource ID `499b84ac-1321-427f-aa17-267ca6975798` and supports fine-grained `vso.*` delegated scopes (not just `user_impersonation`).
3. **Entra OAuth still does not natively support Microsoft Account (MSA / personal `@outlook.com`, `@hotmail.com`) users for the Azure DevOps resource** — confirmed in Microsoft's own docs as recently as the 2026-05-08 revision of the Entra OAuth page. This is a *hard product gap*, and it disproportionately affects exactly the small/personal Azure DevOps organizations that a third-party mobile client is likely to attract.
4. **Therefore the app needs two login paths from day one: Entra OAuth *and* Personal Access Token (PAT).** PAT is not a nice-to-have fallback; for MSA-backed organizations it is currently the *only* way in. Third-party desktop Git clients have reached the same conclusion (SmartGit, May 2026).
5. **Organization discovery gets harder on 2026-12-01.** Global ("All accessible organizations") PATs are **fully decommissioned on December 1, 2026** — roughly 12 weeks from today. Any PAT-based design that assumes one token can enumerate and access every org is dead on arrival. PAT login must be **per-organization**.
6. **Broker (Microsoft Authenticator) support is the single biggest architectural fork.** Enterprises that enforce Conditional Access "require compliant device" cannot authenticate through a plain system-browser OAuth flow; they need MSAL's native broker integration. `expo-auth-session` cannot do brokered auth. The community `react-native-msal` package has had **no npm release since December 2021** and is effectively unmaintained.
7. **`expo-secure-store` has a historical ~2048-byte iOS limit** and Entra tokens routinely exceed that. Plan for a chunked or envelope-encrypted store from the start.

### 1.2 Recommended auth architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Sign-in screen: "Sign in with Microsoft"  |  "Use access token" │
└───────────────┬──────────────────────────────────┬───────────────┘
                │                                  │
     ┌──────────▼──────────┐              ┌────────▼─────────────┐
     │ Entra ID OAuth 2.0  │              │ PAT (per-org)         │
     │ auth code + PKCE    │              │ user pastes token     │
     │ public client       │              │ + org name/URL        │
     │ multi-tenant        │              │ (MSA orgs, on-prem,   │
     │ (work/school only)  │              │  CA-blocked tenants)  │
     └──────────┬──────────┘              └────────┬─────────────┘
                │                                  │
                │  access token (≈60–90 min)       │  long-lived secret
                │  + refresh token (90d inactive)  │  (max 1 yr, often
                │                                  │   capped at 90d)
     ┌──────────▼──────────────────────────────────▼─────────────┐
     │  Token store: expo-secure-store, chunked (>2KB values)     │
     │  optional biometric gate (expo-local-authentication)       │
     └──────────┬────────────────────────────────────────────────┘
                │
     ┌──────────▼────────────────────────────────────────────────┐
     │  Org discovery                                             │
     │  Entra:  profiles/me → id → /_apis/accounts?memberId=…     │
     │  PAT:    org supplied by user (no cross-org enumeration    │
     │          after 2026-12-01)                                 │
     └───────────────────────────────────────────────────────────┘
```

**Phase plan:**

| Phase | Auth | Rationale |
|---|---|---|
| **v1 (MVP)** | Entra OAuth via `expo-auth-session` (PKCE, system browser) **+** PAT per-org | Covers work/school accounts and MSA users. No native module needed for OAuth → simplest build + OTA-friendly. Requires an Expo **dev build** (custom scheme), not Expo Go. |
| **v1.1** | Add per-org token model, tenant picker, cross-tenant re-auth | Needed as soon as any user belongs to orgs in >1 Entra tenant. |
| **v2 (enterprise)** | Add MSAL native (broker-capable) path behind a build flag | Unblocks tenants with Conditional Access "compliant device" / app-protection-policy requirements. Requires a maintained MSAL RN wrapper or a first-party native module we write ourselves. |
| **v3 (optional)** | Azure DevOps Server via custom base URL + PAT only | Low effort, low reach. Defer. |

### 1.3 Key decisions to make now

- **D1 — Ship PAT login in v1.** Not optional. MSA users have no other path. *(Driven by §4.)*
- **D2 — Design the token store for per-organization, per-tenant tokens.** Do not model "one session = one token". *(Driven by §5, §6.)*
- **D3 — Register the Entra app as multi-tenant, public client, mobile & desktop platform, and request narrow `vso.*` delegated scopes — never `user_impersonation`.** Narrow scopes materially improve the odds of surviving tenant "user consent for verified publishers only" policies. *(Driven by §3.)*
- **D4 — Complete Entra publisher verification before store launch.** Under the common `microsoft-user-default-low` consent policy, unverified publishers cannot get user consent at all — every enterprise user would need an admin. *(Driven by §3.6.)*
- **D5 — Accept that broker/CA-compliant-device tenants are out of scope for v1**, and say so in the app's error copy so users understand it's a tenant policy, not a bug. *(Driven by §8.)*
- **D6 — Build a chunking wrapper over `expo-secure-store` on day one.** Retrofitting it after tokens are already stored is a migration headache. *(Driven by §7.4.)*

---

## 2. Deprecation timeline — what is actually happening and when

### 2.1 Azure DevOps OAuth 2.0 (the legacy `app.vssps.visualstudio.com/oauth2` platform)

| Date | Event | Source |
|---|---|---|
| **April 23, 2025** | "As of April 23, 2025, the Azure DevOps OAuth app platform is no longer accepting new app registrations." | [Azure DevOps Blog — No new Azure DevOps OAuth apps beginning April 2025](https://devblogs.microsoft.com/devops/no-new-azure-devops-oauth-apps/) |
| **2026 (date TBA)** | Full end-of-life. "Existing Azure DevOps OAuth apps stop working when the service is fully deprecated in 2026." | [MS Learn — OAuth 2.0 Authentication for Azure DevOps REST APIs](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops) |

**Current state as of 2026-09-10:** Microsoft's own doc pages (`azure-devops-oauth.md` and `oauth.md`, both last updated 2026-05-08 / 2026-05-07) still say only *"in 2026"* with **no specific EOL date published**. The April 2025 blog promised "the official end-of-life date, which we will announce in 2025"; that announcement does not appear to have been made in a form the public docs reflect. **(Partially unverified — a specific date may exist in a Sprint release note not surfaced by search.)**

**Practical consequence for us:** irrelevant either way. We cannot register. The platform's own FAQ says so explicitly:

> **Q: Can I use OAuth with mobile applications?**
> A: Azure DevOps OAuth only supports the web server flow and requires secure storage of client secrets, making it unsuitable for mobile apps. Microsoft Entra ID OAuth provides better mobile app support.

Note also the legacy platform's secret rotation burden — "Application secrets expire every 60 days" — which is why third-party desktop clients kept breaking (see §4.3).

### 2.2 Global PAT retirement (materially affects org discovery)

This is a *separate* deprecation, and it is the one with a firm near-term date.

| Date | Event | Source |
|---|---|---|
| ~~March 15, 2026~~ | ~~Creation/regeneration of global PATs blocked~~ — **rescinded**. Microsoft's 03/05 update: *"We will no longer be proceeding with blocking global PAT creation on March 15. You may continue creating global PATs until December 1."* | [Azure DevOps Blog — Retirement of Global Personal Access Tokens](https://devblogs.microsoft.com/devops/retirement-of-global-personal-access-tokens-in-azure-devops/) |
| **December 1, 2026** | **"All existing global PATs will be fully decommissioned. Tokens will stop working after this date."** | same |

A "global PAT" is the PAT created with the **"All accessible organizations"** scope selector. After 2026-12-01, every PAT is org-scoped.

**Consequence:** the classic "user pastes one PAT → app calls `/_apis/accounts` → app shows all their orgs" flow **stops working on 2026-12-01**. Since we are shipping after that date, do not build it. PAT login must be organization-at-a-time. This is arguably the single most important date in this document for our design.

### 2.3 Other adjacent changes worth knowing

- **Alternate Credentials** authentication is not supported (long dead). [ref](https://devblogs.microsoft.com/devops/azure-devops-will-no-longer-support-alternate-credentials-authentication/)
- **September 2025:** Azure DevOps removed its dependency on the Azure Resource Manager (`https://management.azure.com`) audience during sign-in and token refresh. Tenants that previously relied on ARM Conditional Access policies to cover Azure DevOps must now create an explicit Azure DevOps CA policy. ([CA policies doc](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies?view=azure-devops))
- **Summer 2025 onward:** "Azure DevOps is further encrypting authentication tokens, which means clients can't read token payloads. Any application that decodes tokens to extract claims breaks." → **Treat all tokens as opaque strings.** Do not JWT-decode an Azure DevOps access token to get the user id, tenant, or expiry; use `profiles/me` and the `expires_in` value from the token response instead. ([Authentication guidance](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/authentication-guidance?view=azure-devops))
- **Public projects** in Azure DevOps are retired; existing public projects convert to private starting 2027. Affects any anonymous/unauthenticated browsing feature. ([ref](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/public-projects-retirement))

---

## 3. Microsoft Entra ID OAuth 2.0 for Azure DevOps

### 3.1 The constants

| Thing | Value | Source |
|---|---|---|
| Azure DevOps resource (application) ID | `499b84ac-1321-427f-aa17-267ca6975798` | [entra-oauth](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra-oauth?view=azure-devops) |
| Azure DevOps resource URI | `https://app.vssps.visualstudio.com` | same |
| Display name in the Entra portal | "Azure DevOps" (older: "Microsoft Visual Studio Team Services") | [CA policies doc](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies?view=azure-devops) |
| Authorize endpoint | `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize` | Entra v2 protocols |
| Token endpoint | `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token` | Entra v2 protocols |

### 3.2 App registration for a mobile public client

Register at **Entra ID → App registrations → New registration** ([quickstart](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)):

1. **Supported account types:** *Accounts in any organizational directory (Any Microsoft Entra ID tenant — Multitenant)*.
   - Do **not** pick "…and personal Microsoft accounts" expecting MSA to work against Azure DevOps — the sign-in will succeed but the Azure DevOps resource will not honor the MSA identity (see §4). Selecting the multitenant-only audience makes the failure mode cleaner (user is told up front their account type isn't supported) rather than issuing a token that then 401s.
2. **Platform:** *Mobile and desktop applications* → this creates a **public client** (no client secret, and `allowPublicClient` semantics). PKCE is mandatory for public clients.
3. **Redirect URIs** — register all of these:

   | Platform | Format | Example |
   |---|---|---|
   | iOS (MSAL default, broker-compatible) | `msauth.{BUNDLE_ID}://auth` | `msauth.com.kammcs.adomobile://auth` |
   | Android (MSAL / broker) | `msauth://{package}/{base64url-encoded-signature-hash}` | `msauth://com.kammcs.adomobile/6/aB1cD2eF3gH4iJ5kL6-mN7oP8qR=` |
   | Plain `expo-auth-session` (no broker) | your own app scheme | `com.kammcs.adomobile://auth` (from `makeRedirectUri({ scheme })`) |

   Sources: [MSAL client application configuration](https://learn.microsoft.com/en-us/entra/identity-platform/msal-client-application-configuration), [Use redirect URIs with MSAL (iOS/macOS)](https://learn.microsoft.com/en-us/entra/msal/objc/redirect-uris-ios).

   The older `msal{clientId}://auth` iOS form is still widely seen in samples but the currently documented default is `msauth.{bundleId}://auth`. **(The continued validity of `msal{clientId}://auth` is unverified — register `msauth.{bundleId}://auth` and use that.)**

   Microsoft also documents a broker-override Android form `msauth-{clientId}://{package}` used by MSAL.NET; **(applicability to RN unverified)**.

4. **API permissions** → *Add a permission* → select **Azure DevOps** (not Microsoft Graph) → **Delegated permissions** → pick the specific `vso.*` scopes you need.

### 3.3 Scopes — fine-grained scopes DO exist for Entra tokens

This is a common misconception worth stating clearly: **it is not all-or-nothing `user_impersonation` any more.**

Microsoft shipped granular Azure DevOps scopes for Microsoft identity platform delegated apps in the [September 28, 2023 announcement](https://devblogs.microsoft.com/devops/new-azure-devops-scopes-now-available-for-microsoft-identity-oauth-delegated-flow-apps/):

> Prior to this release, `user_impersonation` was the only available scope, which granted "full access to all Azure DevOps APIs, which means it will be able to do anything that the user is able to do."

Key facts:

- **Entra OAuth and Azure DevOps OAuth use the same scope catalogue.** "Both Microsoft Entra ID OAuth and Azure DevOps OAuth use the same scope definitions." ([oauth doc](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops))
- **Scope string format for the v2 endpoint:** `{resourceId}/{scopeName}`, e.g.
  - `499b84ac-1321-427f-aa17-267ca6975798/vso.work`
  - `499b84ac-1321-427f-aa17-267ca6975798/vso.code`
  - `499b84ac-1321-427f-aa17-267ca6975798/.default` (everything already consented on the app registration)
  - `499b84ac-1321-427f-aa17-267ca6975798/user_impersonation` (full access — avoid)
- **Granular scopes are delegated-only.** "These new permissions are only available for delegated flows, they do not exist as application permissions on app-only flows." Fine for us — we are purely delegated.
- **Scopes inherit.** e.g. `vso.code_manage` includes `vso.code_write` includes `vso.code`. Requesting a parent implies the children; don't request both.
- **Some scopes are flagged "High privilege"** in the catalogue (e.g. `vso.code_write`, `vso.build_execute`, `vso.advsec`, `vso.tokens`). High-privilege scopes are more likely to require admin consent under a tenant's permission classification policy.

**Suggested scope set for a read-mostly Azure DevOps mobile client** (adjust to features):

```
499b84ac-1321-427f-aa17-267ca6975798/vso.profile      # required for profiles/me + accounts
499b84ac-1321-427f-aa17-267ca6975798/vso.project      # list projects/teams
499b84ac-1321-427f-aa17-267ca6975798/vso.work         # read work items, queries, boards
499b84ac-1321-427f-aa17-267ca6975798/vso.code         # read repos, PR metadata
499b84ac-1321-427f-aa17-267ca6975798/vso.build        # read builds/pipelines
offline_access                                        # refresh tokens
openid profile                                        # id_token for display name (optional)
```

Add write scopes (`vso.work_write`, `vso.code_write`, `vso.threads_full` for PR comments) **only when the corresponding feature ships** — ideally as **incremental consent** on a second `authorize` round-trip rather than up front, because bundling high-privilege scopes into the first-run consent screen is the fastest way to get blocked by a tenant policy.

**Caveat (community-reported, unverified):** at least one report claims `user_impersonation` "only works when it's the only scope" — i.e. you cannot mix `user_impersonation` with granular `vso.*` scopes in a single request. Since we are not using `user_impersonation`, this does not affect us, but note it if migrating existing code.

`.default` vs explicit scopes: `.default` requests every permission already registered/consented for the app and is the pattern Microsoft's own doc recommends ("Use the `.default` scope when requesting a token with all scopes that the app is permissioned for"). For a mobile client doing incremental consent, **prefer explicit scopes** so the consent screen matches what the user is actually enabling.

### 3.4 Flow: authorization code + PKCE

Standard Entra v2 public-client flow — nothing Azure DevOps-specific about the mechanics.

```
GET https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize
  ?client_id={our client id}
  &response_type=code
  &redirect_uri=msauth.com.kammcs.adomobile%3A%2F%2Fauth
  &response_mode=query
  &scope=499b84ac-1321-427f-aa17-267ca6975798%2Fvso.work%20...%20offline_access
  &state={csrf}
  &code_challenge={S256(verifier)}
  &code_challenge_method=S256
  &prompt=select_account          # useful for multi-account users
```

Token exchange (no client secret — public client):

```
POST https://login.microsoftonline.com/organizations/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

client_id={our client id}
&grant_type=authorization_code
&code={code}
&redirect_uri=msauth.com.kammcs.adomobile://auth
&code_verifier={verifier}
&scope=...
```

Refresh:

```
POST .../oauth2/v2.0/token
client_id=...&grant_type=refresh_token&refresh_token=...&scope=...
```

### 3.5 Token lifetimes

From [Configurable token lifetimes (Entra, updated 2026-06-15)](https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes):

| Token | Default | Configurable? |
|---|---|---|
| Access token | **Random 60–90 minutes (≈75 min average)**, varies by client/resource/CA. With **Continuous Access Evaluation (CAE)** negotiated by both client and resource, may extend to **24–28 hours** with near-real-time revocation. | Yes, via `TokenLifetimePolicy` (`AccessTokenLifetime`, min 10 min, max 23:59:59) — tenant admins can shorten it. |
| ID token | 1 hour | Yes (same policy property). |
| Refresh token — **Max Inactive Time** | **90 days** | **No.** Retired as configurable on **January 30, 2021**. |
| Refresh token — **Max Age** (single- and multi-factor) | **Until revoked** | **No.** |

Practical reading for us:

- Assume **~1 hour** access-token validity and refresh proactively (e.g. at 80% of `expires_in`, and always on a 401 with a single retry).
- A refresh token stays valid **indefinitely as long as it's used at least once every 90 days**, so a user who opens the app monthly never re-authenticates. A user who ignores the app for 3 months does.
- **Do not build silent-refresh logic that assumes the refresh token is stable** — Entra issues a **new refresh token on each refresh** (rolling refresh tokens); persist the new one atomically. Losing the write here is a classic "users randomly get logged out" bug.
- **CAE claims challenges:** Azure DevOps supports CAE. A CAE-capable client that receives a `WWW-Authenticate` claims challenge must re-request a token with the `claims` parameter. Microsoft's guidance for .NET clients is to "gracefully handle claims challenges". **(Whether `expo-auth-session` / plain fetch flows need to implement this to avoid hard failures is unverified — but if we do NOT advertise CAE capability, we simply get short-lived tokens, which is the safe default.)**
- Tenant admins can *shorten* access token lifetime to as little as 10 minutes. Refresh logic must not assume ≥1 hour.

### 3.6 Consent: user vs admin, and how tenants block us

This is the highest-risk area for a third-party app.

**How Entra decides** ([Configure user consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent)):

| Tenant setting (built-in policy id) | Effect on us |
|---|---|
| **Allow user consent for apps** (`microsoft-user-default-legacy`) | Any user can consent to any non-admin-consent-required permission. We work with zero admin involvement. |
| **Allow user consent for apps from verified publishers, for selected permissions** (`microsoft-user-default-low`) | We work **only if** (a) our publisher is **verified** and (b) the admin has classified our requested permissions as *low impact*. |
| **Do not allow user consent** | Every user needs an admin to grant consent for the whole tenant. |

Microsoft's own recommendation to admins is the middle option — *"we recommend that you allow user consent only for applications that have been published by a verified publisher"* — so we should assume many tenants are configured that way.

**Actions this implies:**

- **Complete [Publisher Verification](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview) before launch.** Without the blue "verified" badge, every `microsoft-user-default-low` tenant blocks us outright. **(The exact verification requirements — MPN/Partner Center account etc. — were not re-verified in this pass; treat as a task to scope.)**
- **Request as few and as low-impact scopes as possible**, and prefer read scopes. Permission classification is per-permission, so `vso.work` has a much better chance of being classified low-impact than `vso.code_write` or `user_impersonation`.
- **Implement the admin consent request flow gracefully.** When user consent is blocked, Entra returns `AADSTS65001` / `AADSTS90094` ("Need admin approval"). Tenants can enable the [admin consent workflow](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-admin-consent-workflow) so the user can request approval in-place. Our error screen should detect these codes and say "Your IT administrator needs to approve this app" with a copyable admin-consent URL:
  ```
  https://login.microsoftonline.com/{tenant}/adminconsent?client_id={our client id}
  ```
- Note: *"Applications that require users to be assigned to the application must have their permissions consented by an administrator, even if the user consent policies for your directory would otherwise allow a user to consent."* — i.e. if an admin sets "User assignment required" on our enterprise app, user consent is bypassed regardless.

### 3.7 The Azure DevOps org policy — good news

There is an Azure DevOps organization-level policy called **"Third-party application access through OAuth"**, and it is a well-known cause of `TF400813` errors. Critically ([Change application connection and security policies](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/change-application-access-policies?view=azure-devops)):

> **Third-party application access through OAuth**: Enable Azure DevOps OAuth apps to access resources in your organization through OAuth. **This policy is defaulted to *off* for all new organizations.** … **This policy doesn't affect Microsoft Entra ID OAuth app access.**

**So:** that policy is a blocker for the *legacy* platform only. It does **not** affect our Entra OAuth tokens. (It would have been fatal — default-off on all new orgs.) This is a strong additional argument for Entra OAuth over legacy OAuth, independent of the deprecation.

The related legacy symptom to recognize, from the Azure DevOps OAuth FAQ, is:
> "OAuth authorization flows work, but API calls return `TF400813: The user "<GUID>" is not authorized to access this resource.`"

If we ever see `TF400813` with an *Entra* token, the cause is Azure DevOps permissions/licensing (user not a member of the org, or no Basic access), not this policy.

**Other org/tenant policies that do affect us** (all from the same page):

| Policy | Level | Impact on us |
|---|---|---|
| Restrict personal access token creation | Org | Users may be unable to create the PAT our fallback path requires. Sub-policies allow packaging-only PATs or an allow-list. |
| Restrict global PAT creation | Tenant | Kills "all accessible organizations" PATs early (moot after 2026-12-01). |
| Restrict full-scoped PAT creation | Tenant | Users must pick specific scopes — fine, we tell them which. |
| Enforce maximum PAT lifespan | Tenant | Our PAT sessions may expire in 30–90 days regardless of what the user picks. |
| Enable IP Conditional Access policy validation on non-interactive flows | Org | PAT-based REST calls become subject to IP fencing → mobile users on cellular get blocked. |
| External guest access | Org | Guests may be excluded. |

### 3.8 Conditional Access

From [Conditional Access policies on Azure DevOps (updated 2026-05-08)](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies?view=azure-devops):

- Tenant admins target Azure DevOps as a CA resource by ID `499b84ac-1321-427f-aa17-267ca6975798`.
- Conditions include group membership, **location/network**, **operating system**, and **"Use of a managed and enabled device"** ← this is the device-compliance condition that requires a broker (§8).
- "Azure DevOps enforces Conditional Access policy validation on all interactive (web) flows." MFA policies are enforced on web flows; non-interactive flows are *blocked* if the user doesn't meet policy.
- **IP fencing** is supported for IPv4 and IPv6. If the org enables IP CA validation on non-interactive flows, PAT-authenticated REST calls from a phone on a mobile network will fail. Doc explicitly warns about the "sign-in from a different IP than API access" (VPN) case, which is common on mobile.
- **CAE** is supported end-to-end.

---

## 4. Microsoft Account (MSA) users — the hard gap

### 4.1 Current state (as of 2026-09-10): still not supported

Directly from the [Microsoft Entra OAuth apps doc](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra-oauth?view=azure-devops) — page `ms.date: 2026-04-02`, `updated_at: 2026-05-08`:

> **Microsoft Entra apps don't natively support Microsoft account (MSA) users for the Azure DevOps resource.** If you're building an app that must cater to MSA users or support both Microsoft Entra and MSA users, [Azure DevOps OAuth apps](azure-devops-oauth) remain your best option. **Microsoft is currently working on native support for MSA users through Microsoft Entra OAuth.**

That guidance is, as of today, **self-contradictory in practice**: it tells third-party developers to use a platform that (a) has been closed to new registrations since April 2025 and (b) is scheduled to be switched off in 2026. There is no third path documented.

**I could not find any 2025 or 2026 announcement that MSA support has shipped.** Searches of devblogs, Learn, and release notes surfaced only the "currently working on" language. **Mark as: not shipped as of 2026-09-10; no public ETA (unverified whether an ETA exists internally).**

### 4.2 Why this matters more than it sounds

Azure DevOps organizations come in two flavours: **Entra-tenant-backed** (enterprise, `dev.azure.com/contoso` linked to a directory) and **MSA-backed** (personal, the default when a hobbyist signs up with an `@outlook.com` account). Independent developers, small consultancies, and side projects — the population most likely to install a third-party Azure DevOps mobile client from an app store — skew heavily MSA.

An Entra-only app therefore locks out a large slice of the realistic addressable market.

### 4.3 What other third-party clients are doing

SmartGit (syntevo), a mainstream commercial Git client, published [*"Azure DevOps authentication: please switch to personal access tokens"* (2026-05-25)](http://blog.syntevo.com/smartgit/2026/05/25/azure-devops-client-secret-expired.html). Their position:

- Their legacy Azure DevOps OAuth app's **client secret expired (60-day rotation)**, breaking users.
- They cannot move wholesale to Entra OAuth because *"Entra apps do not yet natively support Microsoft account (MSA) users for the Azure DevOps resource."*
- **Their instruction to users is: create a PAT and configure the client with it.**

This is real-world corroboration that PAT-as-a-first-class-login-method is the current industry answer, not a hack.

### 4.4 Our approach

1. **Ship PAT login as a co-equal, clearly-labelled option** — not buried under "Advanced".
2. **Detect and explain.** If a user signs in with Entra and the account turns out to be MSA (or the Azure DevOps calls 401 while the Entra token is valid), show a specific message: *"Personal Microsoft accounts aren't supported for Azure DevOps sign-in yet. Use an access token instead —"* with a deep link to `https://dev.azure.com/{org}/_usersSettings/tokens` and a scope checklist.
3. **Do not offer `common` as the authority for the Entra path** (see §6.4) — using `organizations` produces a clean "this account type isn't supported here" at the identity provider instead of a confusing downstream 401.
4. **Re-test quarterly.** The moment MSA support ships, the PAT path can be demoted to a fallback and the UX simplifies dramatically. Track: the `entra-oauth.md` "Tips for building and migrating" bullet, and the Azure DevOps blog OAuth tag.

---

## 5. Personal Access Tokens (PATs) as a login method

Primary source: [Use personal access tokens (updated 2026-09-04 — six days before this research)](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops).

### 5.1 How a PAT is used

HTTP Basic with an **empty username** and the PAT as the password:

```
Authorization: Basic base64(":" + PAT)
```

```bash
curl -u :{PAT} https://dev.azure.com/{organization}/_apis/build-release/builds
```

Note the Azure DevOps REST API also accepts `Authorization: Bearer {entra_token}` — so our HTTP layer needs a per-credential strategy for building the auth header, not a single hard-coded scheme.

### 5.2 Lifetime and scoping

- **Maximum lifetime: 1 year.** *(This figure is widely reported by third-party sources; the current Microsoft doc describes the UI as "set your token to automatically expire after a set number of days" without stating the ceiling in the section I fetched. **Treat "1 year max" as unverified against first-party docs**, but treat it as the practical upper bound.)*
- **Tenant admins can enforce a maximum lifespan** ("for example, no tokens lasting more than 90 days") via the tenant policy *Enforce maximum personal access token lifespan*. Design for tokens that may expire in **30 days**.
- **Scopes** are the same `vso.*` catalogue as OAuth ([available scopes](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops#available-scopes)). We must tell the user exactly which checkboxes to tick.
- **Organization targeting:** the create dialog asks the user to "select the organization where you want to use the token". The "All accessible organizations" option is the *global PAT* — **dead 2026-12-01** (§2.2).
- **Entra-backed orgs impose a sign-in freshness requirement:** *"For organizations backed by Microsoft Entra ID, sign in with your new PAT within 90 days or it becomes inactive."* And separately: *"PAT authentication requires you to regularly sign in to Azure DevOps by using the full authentication flow. Signing in once every 30 days is sufficient for many users."* → A PAT can stop working even before its stated expiry if the user hasn't signed in interactively. Our error copy must cover this, because "my token just stopped working" will otherwise generate support load.

### 5.3 PAT format and validation

- **84 characters long**, 52 of which are randomized.
- **Fixed `AZDO` signature at positions 76–80.**
- Microsoft explicitly says: *"If you integrate with PATs and have PAT validation built in, ensure your validation code accommodates the 84-character token length."*

**Client-side pre-validation (cheap, do it):**
```ts
const looksLikePat = (s: string) =>
  s.length === 84 && s.slice(75, 79) === 'AZDO';   // positions 76–80, 1-indexed
```
Treat this as a *hint* only — reject obviously-malformed input early, but always confirm with a live call. **(The exact 0-based offset for "positions 76-80" is unverified; validate empirically against a real token before enforcing.)**

**Server-side/live validation:** the cheapest authoritative check is a scoped call against the org the PAT is for, e.g.

```
GET https://dev.azure.com/{org}/_apis/projects?api-version=7.1&$top=1
Authorization: Basic base64(":" + PAT)
```

- `200` → valid and has at least `vso.project`.
- `401` → bad/expired/revoked token, or the org name is wrong.
- `203` (non-authoritative / HTML sign-in page) → classic Azure DevOps symptom of an unauthenticated request; treat as failure, not success. **(Behaviour with modern api-versions unverified — test.)**
- `TF400813` → authenticated but not authorized in that org.

### 5.4 Org policies that can block PAT creation entirely

- **Org policy: Restrict personal access token creation.** Sub-policies permit packaging-only PATs, or an allow-list of Entra users/groups. If a user hits this, the expiry-notification email tells them *"you can no longer regenerate PATs"* and to contact a Project Collection Administrator.
- **Tenant policies:** restrict global PAT creation, restrict full-scoped PAT creation, enforce max lifespan.
- **Leaked PAT auto-revocation:** Azure DevOps scans public GitHub repos and (unless disabled) auto-revokes leaked PATs. Not our problem directly, but it means a PAT can vanish without user action.

### 5.5 PAT Lifecycle Management API — can we create PATs for the user?

Tempting idea: after Entra sign-in, mint a PAT programmatically so the app has a stable credential. **Constraints from the docs:**

- Endpoint: `https://dev.azure.com/{org}/_apis/tokens/pats?api-version=7.1-preview.1` (GET/POST/DELETE). [REST ref](https://learn.microsoft.com/en-us/rest/api/azure/devops/tokens/pats?view=azure-devops-rest-7.1)
- **"Microsoft Entra access tokens are required to access this API."** You cannot manage PATs with a PAT.
- **"Only users or apps that use an 'on-behalf-of user' flow can generate PATs."** Delegated flows only — which is us. Service principals/managed identities cannot.
- **Recommended scope is now `vso.pats`**, replacing `user_impersonation`: *"Previously, the PAT Lifecycle Management APIs supported only the `user_impersonation` scope, but now the `vso.pats` scope is available and is the recommended scope… Downscope all apps that previously relied on `user_impersonation`."*
- Tenant security policies may require **admin consent** before an Entra app can call it (documented FAQ: *"Why do I see a 'Need admin approval' message…"*).

**Assessment:** technically possible for Entra users, but **not useful for our main problem**, because the users who need PATs are precisely the MSA users who cannot get an Entra token in the first place. It would also mean the app requests a high-privilege token-minting scope, which hurts consent odds (§3.6). **Recommendation: do not use the PAT Lifecycle API in v1.** Revisit only if we need automated PAT rotation for Entra users, which we don't (we have refresh tokens).

### 5.6 PAT UX implications (this is the real cost)

PAT login is a genuinely bad mobile experience and should be designed deliberately:

- The user must leave the app, sign in to Azure DevOps **in a browser on a phone**, navigate User settings → Personal access tokens → New Token, pick an org, pick an expiry, tick the right scope checkboxes, create, and **copy an 84-character string that is shown exactly once**.
- Mitigations to build:
  - **Deep link** straight to `https://dev.azure.com/{org}/_usersSettings/tokens` (or `https://dev.azure.com/_usersSettings/tokens`) via `expo-web-browser`.
  - **In-app checklist** of the exact scope names to tick, with copy-to-clipboard.
  - **Paste-from-clipboard button** + auto-trim whitespace/newlines (copying from mobile Safari frequently appends whitespace).
  - **Immediate validation** with a friendly per-error-class message.
  - **Store the expiry date the user selected** and warn in-app at T-7 days ("Regenerate early: create a new PAT at least seven days before expiration" is Microsoft's own guidance).
  - **Never log the token**; redact from crash reports and network logs.

---

## 6. Discovering organizations

### 6.1 The two-call sequence (Entra path)

**Step 1 — get the profile id:**
```http
GET https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1
Authorization: Bearer {entra_access_token}
```
Response (abridged) — [Profiles - Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/profile/profiles/get?view=azure-devops-rest-7.1):
```json
{
  "displayName": "Normal Paulk",
  "publicAlias": "d6245f20-2af8-44f4-9451-8107cb2767db",
  "emailAddress": "fabrikamfiber16@hotmail.com",
  "id": "d6245f20-2af8-44f4-9451-8107cb2767db",
  "coreRevision": 1647,
  "revision": 1647
}
```
Documented scope: **`vso.profile`**.

**Step 2 — list organizations for that member:**
```http
GET https://app.vssps.visualstudio.com/_apis/accounts?memberId={id}&api-version=7.1
Authorization: Bearer {entra_access_token}
```
Response — [Accounts - List](https://learn.microsoft.com/en-us/rest/api/azure/devops/account/accounts/list?view=azure-devops-rest-7.1):
```json
{
  "count": 2,
  "value": [
    { "accountId": "6affcbef-…", "accountUri": "https://vssps.dev.azure.com/Fabrikam-Fiber-Inc/", "accountName": "Fabrikam-Fiber-Inc", "properties": {} },
    { "accountId": "bf83696f-…", "accountUri": "https://vssps.dev.azure.com/NormalPaulk/",        "accountName": "NormalPaulk",        "properties": {} }
  ]
}
```
Documented scope: **`vso.profile`**. Use `accountName` to build the org base URL: `https://dev.azure.com/{accountName}`.

The `Account` object also carries `accountType` (`personal` | `organization`) and `accountStatus` (`enabled` | `disabled` | `deleted` | `moved`) — **filter to `enabled`** before showing the picker, and note `hasMoved` / `newCollectionId` exist for relocated orgs.

Note these are on the `app.vssps.visualstudio.com` host, **not** `dev.azure.com`. Some corporate proxies and network policies treat these hosts differently; a failure here with a working `dev.azure.com` call points at network policy.

### 6.2 Does this work with Entra tokens? Yes — with an important nuance

Yes for **delegated user tokens**. The documented `vso.profile` scope applies, and Microsoft's own troubleshooting content uses exactly this two-call pattern.

**It does NOT work for service principals / client-credentials tokens.** Multiple Microsoft Q&A threads document `/_apis/accounts?memberId=…` returning an empty list for service principals, because *"the API is intended to be used in a user context with a user Object ID (OID)… service principals aren't treated the same way as users."* ([Q&A: Issue with Listing Azure DevOps Organizations for a Service Principal](https://learn.microsoft.com/en-us/answers/questions/2236987/issue-with-listing-azure-devops-organizations-for)). Irrelevant to us (we're delegated-only) but worth knowing if we ever add a service-account mode.

### 6.3 Does it work with PATs? Conflicting documentation — **must test**

There is a direct conflict in Microsoft's own docs:

- The **REST reference** for both Profiles-Get and Accounts-List documents `vso.profile` as the scope, which is a PAT-selectable scope, implying PATs work.
- The **PAT article FAQ (updated 2026-09-04)** says the opposite:
  > **Q. Can I use PATs with all Azure DevOps REST APIs?**
  > A. No. You can use PATs with most Azure DevOps REST APIs, but **organizations and profiles** and the PAT Management Lifecycle APIs **support only Microsoft Entra tokens**.

**Status: unresolved / unverified.** Historically `profiles/me` with a PAT has worked in practice, so this may be new guidance reflecting a planned or shipped restriction. **Action: empirically test both endpoints with (a) an org-scoped PAT and (b) a global PAT, before finalizing the PAT onboarding flow.**

**Design so it doesn't matter:** because global PATs die 2026-12-01 anyway (§2.2), the PAT flow should **not** attempt cross-org enumeration at all. Instead:

- Ask the user for the **organization name or URL** alongside the PAT (`https://dev.azure.com/{org}`), or parse the org out of a pasted URL.
- Validate with a scoped call against that org (§5.3).
- Let the user add **multiple org+PAT pairs**, each stored independently.
- *Optionally*, best-effort attempt `profiles/me` + `/_apis/accounts` to pre-populate a picker, and silently fall back to manual entry when it 401s. Never make it load-bearing.

### 6.4 Multi-tenant reality: one token is not enough

This is the subtlest part of the design.

An Azure DevOps organization backed by Entra tenant **A** will only accept an access token issued **by tenant A** for the Azure DevOps resource. A user who belongs to orgs in tenants A, B, and C needs **three separate access/refresh token pairs**.

**Authority choice** ([MSAL client application configuration](https://learn.microsoft.com/en-us/entra/identity-platform/msal-client-application-configuration)):

| Authority | Signs in | Use for |
|---|---|---|
| `https://login.microsoftonline.com/common/` | Work/school **and personal Microsoft accounts** | ❌ Avoid — lets MSA users through to a broken experience (§4) |
| `https://login.microsoftonline.com/organizations/` | Work/school accounts only | ✅ **Our default for the first sign-in** |
| `https://login.microsoftonline.com/consumers/` | Personal MSA only | ❌ Not usable for Azure DevOps |
| `https://login.microsoftonline.com/{tenantId}/` | One specific tenant | ✅ **For acquiring per-tenant tokens after the first sign-in** |

Note Microsoft's caution: *"It's recommended to specify an audience… If your application is intended for external users, avoid the `common` and `organization` endpoints."* For a multi-tenant ISV, `organizations` for the initial sign-in and `{tenantId}` for subsequent acquisitions is the pragmatic reading. **(The tension in that guidance is noted; using `organizations` for first contact is standard ISV practice — flagged as a judgement call, not a doc-verified prescription.)**

**Recommended tenant flow:**

1. First sign-in against `/organizations/` → user picks their account → we get a token for their **home tenant**.
2. Call `profiles/me` + `/_apis/accounts` with that token → get the list of orgs.
3. For each org, we need to know its tenant. Options:
   - Try the org with the current token; on 401/`TF400813`, treat it as "different tenant, re-auth needed". *(Simplest, works, one wasted round-trip per foreign org.)*
   - **(Unverified)** Some Azure DevOps endpoints return a `WWW-Authenticate: Bearer authorization_uri=https://login.microsoftonline.com/{tenantId}` hint on 401 — this is standard Entra behaviour for ARM and is the clean way to discover the required tenant. **Test whether Azure DevOps emits it**; if it does, use it and skip the guessing.
4. When an org needs another tenant, run a **fresh authorize round-trip against `/{tenantId}/`** with `prompt=none` first (silent, often succeeds if the user has an SSO session), falling back to interactive.
5. **Cache tokens keyed by `(tenantId, scopeSet)`** and orgs keyed by `accountId → tenantId`.

**Tenant-selection UX:** do not expose "tenants" as a first-class concept — users don't think in tenants. Show a flat **organization list**; orgs that need re-auth get an inline "Sign in" affordance and a subtitle like *"Requires signing in with your Contoso account."* Only surface the account/tenant identity when a user has multiple work accounts, in which case an account switcher in settings is appropriate.

### 6.5 Rate limits

Azure DevOps enforces **200 TSTU per 5-minute sliding window per identity**, returning HTTP 429 with `Retry-After`. ([Q&A / rate limits](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits)) A mobile app that fans out "list projects for all 12 orgs" on launch can trip this. **Serialize or throttle org-level fan-out, and honour `Retry-After`.**

---

## 7. Expo / React Native implementation

### 7.1 Option A — `expo-auth-session` (recommended for v1)

**Status:** actively maintained. Latest npm `57.0.11`, published **2026-09-01** (registry checked 2026-09-10).

**Why it fits:**
- **PKCE is on by default.** Per the [AuthSession docs](https://docs.expo.dev/versions/latest/sdk/auth-session/): `usePKCE` defaults to `true` and `codeChallengeMethod` defaults to `CodeChallengeMethod.S256`. That's exactly what an Entra public client needs.
- Pure JS + `expo-web-browser` (ASWebAuthenticationSession on iOS / Chrome Custom Tabs on Android) — no custom native module, no Gradle/Podfile surgery, OTA-updatable.
- Works with any OAuth2 provider via an explicit discovery document, so Entra is straightforward:

```ts
import * as AuthSession from 'expo-auth-session';

const TENANT = 'organizations';
const ADO_RESOURCE = '499b84ac-1321-427f-aa17-267ca6975798';

const discovery = {
  authorizationEndpoint: `https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/authorize`,
  tokenEndpoint:         `https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token`,
  endSessionEndpoint:    `https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/logout`,
};
// or: AuthSession.useAutoDiscovery(`https://login.microsoftonline.com/${TENANT}/v2.0`)

const redirectUri = AuthSession.makeRedirectUri({
  scheme: 'com.kammcs.adomobile',          // must match app.json "scheme"
  path: 'auth',
});

const request = new AuthSession.AuthRequest({
  clientId: ENTRA_CLIENT_ID,
  redirectUri,
  scopes: [
    `${ADO_RESOURCE}/vso.profile`,
    `${ADO_RESOURCE}/vso.project`,
    `${ADO_RESOURCE}/vso.work`,
    `${ADO_RESOURCE}/vso.code`,
    `${ADO_RESOURCE}/vso.build`,
    'offline_access',
  ],
  usePKCE: true,                            // default, stated for clarity
  extraParams: { prompt: 'select_account' },
});
```

**Caveats:**
- **Expo Go will not work** for this. Expo's own guidance: *"Expo Go cannot be used for local development and testing of OAuth or OpenID Connect-enabled apps due to the inability to customize your app scheme. You can instead use a Development Build."* Plan for `expo-dev-client` + EAS builds from day one.
- **Redirect URI must be registered in Entra exactly.** For a plain `expo-auth-session` flow the scheme is *our* scheme (`com.kammcs.adomobile://auth`), not the MSAL `msauth.*` form. Register both if we later add MSAL.
- **The legacy Expo auth proxy (`auth.expo.io` / `useProxy`) is deprecated** and must not be used — it routes the auth code through Expo's servers. **(Its exact current removal status was not confirmed in the docs I fetched — treat "do not use" as the decision regardless.)**
- **No broker support.** This is the big one — see §8.
- **We own token refresh.** `AuthSession.refreshAsync()` exists, but scheduling, rolling-refresh-token persistence, and 401-retry are ours to build.

### 7.2 Option B — MSAL native (`react-native-msal`) — **effectively unmaintained**

npm registry data, checked 2026-09-10:

| Field | Value |
|---|---|
| Latest stable | **`4.0.4`, published 2021-12-23** |
| Latest beta | `4.1.0-beta.2`, published 2022-04-14 |
| Package last modified | 2022-05-14 |
| Weekly downloads | ~10,123 (week of 2026-08-31) |

**~4.5 years with no release.** It still has real usage, but it wraps MSAL iOS/Android SDK versions from 2021–2022. It does document [Expo setup](https://github.com/stashenergy/react-native-msal/blob/master/docs/expo_setup.md) via a config plugin (`androidPackageSignatureHash`), and there is an [equinor fork](https://github.com/equinor/react-native-msal). `react-native-msal-plugin` is older still (3.0.0, 2018).

**There is no `@azure/msal-react-native` package on npm** — the name does not resolve. Microsoft has never shipped an official MSAL for React Native; community reports describe only a Microsoft proof-of-concept explicitly not intended for production. **(The current existence/status of that POC is unverified.)**

**What MSAL native would buy us, and only MSAL native:**
- **Broker integration** with Microsoft Authenticator / Company Portal → device-based Conditional Access, device registration, and app-protection (Intune MAM) policies.
- Cross-app SSO with other Microsoft apps on the device.
- Automatic claims-challenge / CAE handling.
- Battle-tested token cache with correct rolling-refresh semantics.

**Assessment:** using a 2021 wrapper for the *security-critical* path of an enterprise app is a real risk (unpatched native SDKs, no RN New Architecture support, no Expo SDK 5x guarantees). If broker support becomes a requirement, the more honest options are:
1. Fork and maintain `react-native-msal` ourselves against current MSAL iOS/Android, or
2. Write a thin Expo Module wrapping MSAL iOS + MSAL Android directly (a few hundred lines; we only need `acquireTokenInteractive` / `acquireTokenSilent` / `signOut`), or
3. Evaluate `react-native-app-auth` (`8.4.1`, published **2026-07-06** — actively maintained, AppAuth-based). **It does not do brokered auth either**, so it solves the maintenance problem but not the CA problem. Its advantage over `expo-auth-session` is a more mature native token/refresh implementation. **(Its Expo config-plugin story was not verified in this pass.)**

**Recommendation: do not take an MSAL native dependency in v1.** Revisit when an enterprise customer requires it, and budget option (2).

### 7.3 Comparison of client libraries

| | `expo-auth-session` | `react-native-app-auth` | `react-native-msal` | custom Expo Module over MSAL |
|---|---|---|---|---|
| Maintained (2026) | ✅ 57.0.11, Sep 2026 | ✅ 8.4.1, Jul 2026 | ❌ last release Dec 2021 | n/a (ours) |
| Works in Expo Go | ❌ (dev build required) | ❌ | ❌ | ❌ |
| PKCE | ✅ default S256 | ✅ | ✅ | ✅ |
| Config plugin needed | ❌ (scheme only) | ⚠️ likely | ✅ | ✅ |
| **Broker / device CA** | ❌ | ❌ | ✅ | ✅ |
| Cross-app SSO w/ MS apps | ❌ | ❌ | ✅ | ✅ |
| Token cache built-in | ❌ (we build it) | ⚠️ partial | ✅ | ✅ |
| Effort | Low | Low–Med | Med (+ risk) | High |

### 7.4 Token storage — `expo-secure-store` and the ~2KB problem

**The limit,** verbatim from the [SecureStore docs](https://docs.expo.dev/versions/latest/sdk/securestore/):

> "Large payloads can be rejected by the underlying platform. **Historically, some iOS releases refused values above roughly 2048 bytes.**"

Expo itself does not enforce a limit; the platform does, so failures are native errors that must be caught.

**Why this bites us specifically:** Entra JWT access tokens for the Azure DevOps resource are large — commonly 1–4 KB, growing with the number of group claims, roles, and scopes in the token — and refresh tokens are also substantial opaque blobs. **A token pair for an enterprise user with many group memberships will exceed 2048 bytes.** *(The precise byte size of an Azure DevOps Entra token is **unverified** — measure it against a real enterprise tenant early; but the risk is well-documented and must be designed around regardless.)*

**Workaround — chunking wrapper (recommended):**

```ts
import * as SecureStore from 'expo-secure-store';

const CHUNK = 1800;                     // safety margin under 2048

export async function setSecure(key: string, value: string) {
  const n = Math.ceil(value.length / CHUNK);
  await SecureStore.setItemAsync(`${key}__n`, String(n));
  for (let i = 0; i < n; i++) {
    await SecureStore.setItemAsync(`${key}__${i}`, value.slice(i * CHUNK, (i + 1) * CHUNK));
  }
}

export async function getSecure(key: string): Promise<string | null> {
  const nRaw = await SecureStore.getItemAsync(`${key}__n`);
  if (!nRaw) return null;
  const parts: string[] = [];
  for (let i = 0; i < Number(nRaw); i++) {
    const p = await SecureStore.getItemAsync(`${key}__${i}`);
    if (p == null) return null;         // torn write → treat as absent, force re-auth
    parts.push(p);
  }
  return parts.join('');
}
```

Note `value.length` is UTF-16 code units, not bytes — for base64/JWT content (ASCII) they coincide, which is the case here, but a general-purpose helper should measure bytes.

**Alternative — envelope encryption:** store a short random AES key in SecureStore and the AES-256-encrypted token blob in the filesystem. Packages like `@neverdull-agency/expo-unlimited-secure-store` do exactly this. **(Not audited — if we adopt one, review it; otherwise the chunking wrapper above is ~30 lines and has no supply-chain surface.)**

**Other SecureStore behaviours that matter:**

| Behaviour | Detail |
|---|---|
| **Uninstall** | **Android: data is NOT preserved** on uninstall. **iOS: data DOES persist** across uninstall/reinstall with the same bundle ID. → On iOS, a reinstall can silently resurrect a stale token from a previous install. Store an install-id alongside and purge on mismatch. |
| **`keychainAccessible`** | Options: `WHEN_UNLOCKED` (default), `WHEN_UNLOCKED_THIS_DEVICE_ONLY`, `AFTER_FIRST_UNLOCK`, `AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY`, `ALWAYS` (deprecated), `ALWAYS_THIS_DEVICE_ONLY`, `WHEN_PASSCODE_SET_THIS_DEVICE_ONLY`. **Recommend `WHEN_UNLOCKED_THIS_DEVICE_ONLY`** — prevents tokens syncing to iCloud Keychain / other devices. Note this also means tokens don't survive device migration, which is correct for credentials. |
| **`requireAuthentication` (biometric)** | *"This option is not supported in Expo Go when biometric authentication is available due to a missing `NSFaceIDUsageDescription` key."* Android requires auth on **all** operations; iOS prompts only when reading/updating existing values. Requires a real device to test. |
| **Background refresh** | If tokens are stored with `WHEN_UNLOCKED*`, a background task cannot read them while the device is locked. Design background sync to fail silently and retry on foreground. |

### 7.5 Biometric gate

Two viable designs:

1. **`requireAuthentication: true` on the SecureStore item** — the OS gates the keychain read itself. Strongest, but the Android "prompt on every operation" behaviour is intrusive and the Expo Go limitation complicates development.
2. **`expo-local-authentication` gate in front of the app** — call `authenticateAsync()` on cold start / after N minutes background, then read tokens normally. Better UX, weaker guarantee (a rooted/jailbroken attacker with filesystem access bypasses it).

**Recommendation:** ship (2) as an opt-in "Require Face ID / fingerprint to open" setting, and consider (1) only for the PAT (which is a long-lived bearer secret and therefore the highest-value item in the store).

### 7.6 Token refresh strategy

- Persist `{ accessToken, refreshToken, expiresAt, tenantId, scopes }` per tenant.
- Refresh proactively when `expiresAt - now < 5 min`, on app foreground, and reactively on any 401 (once, then fail).
- **Serialize refreshes with a mutex/in-flight promise** — several parallel API calls hitting 401 at once must not fire N concurrent refreshes; the rolling-refresh-token semantics mean the losers invalidate the winner's token.
- **Persist the new refresh token before using the new access token.** A crash between the two loses the session.
- On `invalid_grant` / `AADSTS70008` (expired refresh token, >90 days inactive) or `AADSTS50173` (password changed), clear that tenant's tokens and prompt for interactive sign-in — do not silently retry.
- Background refresh via `expo-background-task` is possible but constrained by iOS scheduling and the keychain-lock issue above. **Recommendation: refresh on foreground, not in background.** Reserve background work for notifications, if any.

---

## 8. Broker apps and Conditional Access — the key decision

**The problem:** Many enterprise tenants apply a Conditional Access policy to Azure DevOps requiring a **compliant / hybrid-joined ("managed and enabled") device**. Azure DevOps documents this explicitly as one of the conditions admins set.

Device compliance state lives with Intune and is attested to Entra during token acquisition **by the broker** — Microsoft Authenticator (iOS) or Microsoft Authenticator / Company Portal (Android). The broker verifies the calling app by *"verifying its redirect URI and signature against the app registration in Entra ID"*, then acquires a token bound to the device's registration.

**A system-browser OAuth flow (`expo-auth-session`, `react-native-app-auth`, any plain AppAuth client) cannot participate in this.** There is no device certificate, no broker hand-off, and therefore no way to satisfy a compliant-device grant control. The user will hit an `AADSTS53000`-class error ("Your device is required to be managed to access this resource") or `AADSTS50097`/`AADSTS530003` and there is nothing the app can do about it.

**Practical implications:**

| Tenant CA posture | Plain `expo-auth-session` | MSAL + broker |
|---|---|---|
| No CA on Azure DevOps | ✅ works | ✅ works |
| CA requires MFA | ✅ works (MFA happens in the browser) | ✅ works |
| CA requires **compliant/managed device** | ❌ **blocked, unfixable in-app** | ✅ works |
| CA requires **approved client app / app protection policy** | ❌ blocked | ✅ works (MSAL + Intune MAM SDK) |
| CA IP fencing | ⚠️ works if the phone's IP is allowed (cellular usually isn't) | ⚠️ same |

**Decision D5: v1 ships without broker support.** Rationale: broker support requires either an unmaintained dependency or a custom native module; the affected population is the subset of enterprise tenants with device-compliance CA; and we can detect and explain the failure clearly. But this **must be a conscious, documented decision**, because it is effectively "this app does not work at some large enterprises", and that will show up in App Store reviews if not communicated.

**Mitigations for v1:**
- Detect `AADSTS530003`, `AADSTS53000`, `AADSTS53001`, `AADSTS50097` in the authorize-error callback and show: *"Your organization requires apps to sign in from a managed device. This app doesn't yet support that. Ask your IT admin about [our app], or use a personal access token if your organization permits it."*
- Note the PAT fallback may *also* be blocked in such tenants (IP CA on non-interactive flows, or restricted PAT creation) — don't over-promise.

**Additional store/security considerations:**
- **App Store / Play review:** using the system browser (ASWebAuthenticationSession / Chrome Custom Tabs) is the required pattern; embedded `WebView` OAuth is both an Apple review risk and disallowed by Microsoft's own guidance. `expo-web-browser` does the right thing.
- **`prompt=select_account` and account switching** must actually clear state — the system browser cookie jar is shared, so "sign out" should call the `end_session` endpoint or open the logout URL, not just delete local tokens.
- **Never log tokens, `code`, or `code_verifier`.** Scrub them from Sentry/crash breadcrumbs and from any HTTP logging middleware.
- **Treat tokens as opaque** (§2.3) — no client-side JWT decoding.
- **Certificate pinning** to `login.microsoftonline.com` is *not* recommended (Microsoft rotates certs and CAs); rely on platform TLS.

---

## 9. Azure DevOps Server (on-premises / TFS)

**Short answer: PAT + custom base URL only, and it should be a later phase.**

Documented facts:

- *"OAuth 2.0 and Microsoft Entra ID authentication are available for Azure DevOps Services only, not Azure DevOps Server. For on-premises scenarios, use .NET client libraries, Windows authentication, or personal access tokens."* ([Authentication guidance, updated 2026-08-05](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/authentication-guidance?view=azure-devops))
- The recommended method for "Azure DevOps Server apps" is *".NET client libraries or Windows Auth"* — neither of which is available to a React Native app.
- PATs **are** supported on Azure DevOps Server and behave the same way, with one trap: *"For Azure DevOps Server, enabling IIS Basic Authentication invalidates PAT usage. Keep IIS Basic Authentication turned off."*
- Windows auth on-prem is **NTLM or Kerberos**; Microsoft [recommends reconfiguring to Kerberos](https://devblogs.microsoft.com/devops/reconfigure-azure-devops-server-to-use-kerberos-instead-of-ntlm/) and Git LFS dropped NTLM in v3.0.
- Azure DevOps Server 2025 reached GA (Dec 2025) but **does not add Entra ID authentication for on-premises user sign-in**; Entra support there is confined to specific pipeline tasks (e.g. Service Bus). **(This characterization is from secondary sources + the Services-only statement above; the ADS 2025 release notes were not read in full — mark as partially unverified.)**

**Feasibility from mobile:**

| Approach | Verdict |
|---|---|
| PAT + user-supplied base URL (`https://{server}/{collection}` or `http://{server}:{port}/tfs/{collection}`) | ✅ Only realistic option. Same Basic-auth header as Services. |
| NTLM / Kerberos from RN | ❌ Not practical. No RN HTTP stack does NTLM/SPNEGO out of the box; would need a native networking module, and Kerberos needs a domain-joined device or a KDC-reachable network. |
| Entra ID | ❌ Not supported on-prem. |

**Additional on-prem obstacles for a mobile client** (all real, all annoying):
- Servers are usually **not internet-reachable** → requires corporate VPN, which many phones won't have configured for this app.
- **Self-signed / internal-CA TLS certificates** are common → RN will reject them unless the CA is in the device trust store; we should surface a clear TLS error rather than offering an "ignore certificate" toggle (which would be an App Store risk and a genuine security hole).
- **API version skew** — an on-prem server pinned to an older Azure DevOps Server release may not support `api-version=7.1` on every endpoint.
- Collection-based URL structure differs from the `dev.azure.com/{org}` shape; the API client must be built around a configurable base URL from day one even if we only ship Services.

**Recommendation: Services first, Server later (or never).** The one thing to do *now* is architectural: make the API client take a **base URL + credential strategy** rather than hard-coding `https://dev.azure.com`. That costs nothing today and makes Server a contained feature later.

---

## 10. Comparison of login options

| | **Entra OAuth via `expo-auth-session`** | **Entra OAuth via MSAL native** | **Personal Access Token** | **Azure DevOps (legacy) OAuth** |
|---|---|---|---|---|
| **Available to us?** | ✅ Yes | ✅ Yes (with a native module we build/fork) | ✅ Yes | ❌ **No — registrations closed Apr 23 2025** |
| **Future-proof** | ✅ Strategic direction | ✅ Strategic direction | ⚠️ Microsoft actively discouraging PATs; global PATs die 2026-12-01 | ❌ EOL in 2026 |
| **Works for Entra (work/school) users** | ✅ | ✅ | ✅ | ✅ |
| **Works for MSA (personal) users** | ❌ **Not supported** | ❌ **Not supported** | ✅ **Only option** | ✅ (but unavailable to us) |
| **Works under CA "compliant device"** | ❌ | ✅ (broker) | ❌ (and may be IP-fenced) | ❌ |
| **Credential lifetime** | Access ~60–90 min; refresh 90-day inactivity, else until revoked | same | Up to 1 yr; often capped at 30–90 d by tenant policy; 90-day interactive-sign-in requirement | Access short; refresh rolling; **secret rotates every 60 d** |
| **Granular scopes** | ✅ `vso.*` delegated | ✅ | ✅ same catalogue | ✅ same catalogue |
| **Cross-org discovery** | ✅ `profiles/me` + `/_apis/accounts` | ✅ | ⚠️ Conflicting docs; **and global PATs die 2026-12-01** → per-org only | ✅ |
| **Cross-tenant** | ⚠️ One token per tenant; re-auth per tenant | ⚠️ same (MSAL handles the cache) | ✅ N/A (per-org anyway) | ⚠️ |
| **Blocked by ADO org policy "3rd-party OAuth"** | ✅ No — **doesn't apply to Entra apps** | ✅ No | ✅ No (separate PAT policies apply) | ❌ Yes — **default OFF on new orgs** |
| **Needs tenant admin?** | ⚠️ Sometimes (consent settings; publisher verification helps) | ⚠️ Sometimes | ⚠️ Sometimes (PAT creation policy) | ⚠️ Yes (org policy toggle) |
| **Mobile UX** | ✅ One tap → system browser → back | ✅ One tap (+ SSO with MS apps) | ❌ Manual, error-prone, expires | ✅ |
| **Client secret required** | ❌ Public client + PKCE | ❌ | n/a | ✅ **Unsuitable for mobile** |
| **Dependency risk** | Low (Expo, actively maintained) | **High** (`react-native-msal` last released Dec 2021) or High effort (own module) | None | n/a |
| **Implementation effort** | Low | Medium–High | Low (but high UX/support cost) | n/a |
| **Verdict** | ✅ **v1 primary** | ⏳ v2, enterprise-gated | ✅ **v1 required fallback** | ❌ Excluded |

---

## 11. Login + organization-selection flow

### 11.1 Entra path (happy case)

```mermaid
sequenceDiagram
    participant U as User
    participant A as Mobile app
    participant B as System browser
    participant E as login.microsoftonline.com
    participant V as app.vssps.visualstudio.com
    participant D as dev.azure.com/{org}

    U->>A: Tap "Sign in with Microsoft"
    A->>A: Generate PKCE verifier + challenge (S256), state
    A->>B: Open /organizations/oauth2/v2.0/authorize<br/>client_id, scopes, redirect_uri, code_challenge
    B->>E: Authenticate (password/MFA/passkey)
    E->>U: Consent screen (first run only)
    E-->>B: 302 to msauth.com.kammcs.adomobile://auth?code=…&state=…
    B-->>A: Deep link back into app
    A->>A: Verify state
    A->>E: POST /token (code + code_verifier, no secret)
    E-->>A: access_token (~60–90 min), refresh_token, expires_in
    A->>A: Store per-tenant in SecureStore (chunked)

    A->>V: GET /_apis/profile/profiles/me?api-version=7.1 (Bearer)
    V-->>A: { id: "d6245f20-…" }
    A->>V: GET /_apis/accounts?memberId=d6245f20-…&api-version=7.1
    V-->>A: [ { accountName, accountId, accountType, accountStatus } … ]
    A->>A: Filter accountStatus == "enabled"; cache list
    A->>U: Show organization picker

    U->>A: Pick "Fabrikam-Fiber-Inc"
    A->>D: GET /_apis/projects?api-version=7.1 (Bearer)
    alt 200
      D-->>A: projects → app home
    else 401 / TF400813
      A->>A: Org belongs to another tenant (or no access)
      A->>B: Re-authorize against /{tenantId}/ with prompt=none, then interactive
      Note over A,B: New token pair cached under that tenantId
    end
```

### 11.2 Numbered flow, including the unhappy paths

1. **Sign-in screen** offers "Sign in with Microsoft" (primary) and "Use an access token" (secondary, equally visible).
2. **Entra chosen:** generate PKCE verifier/challenge + `state`; open `/organizations/oauth2/v2.0/authorize` in the system browser via `expo-web-browser`.
3. **User authenticates.** Possible terminal failures here:
   - `AADSTS50020` / account-type error → **MSA user.** Show the MSA explainer (§4.4) and route to the PAT flow.
   - `AADSTS65001` / `AADSTS90094` → **admin consent required.** Show the admin-consent URL + "request approval" copy.
   - `AADSTS530003` / `AADSTS53000` → **device compliance required.** Show the broker explainer (§8).
   - User cancels → return to sign-in screen, no error toast.
4. **Deep link back**, verify `state`, exchange `code` + `code_verifier` at `/token`. Store `{access, refresh, expiresAt, tenantId, scopes}` chunked in SecureStore.
5. **`GET /_apis/profile/profiles/me?api-version=7.1`** → take `id`.
6. **`GET /_apis/accounts?memberId={id}&api-version=7.1`** → org list. Filter to `accountStatus == "enabled"`. Cache with a short TTL (orgs change rarely; refresh on pull-to-refresh and on 401).
7. **Empty list?** Legitimate — the user has an Entra account but no Azure DevOps orgs, *or* all their orgs are in other tenants. Show "No organizations found" with (a) "Add an organization by name" manual entry and (b) "Sign in with a different account".
8. **Org picker.** Single org → skip the picker and go straight in (but keep an org switcher in the nav).
9. **Probe the chosen org** with a cheap scoped call (`/_apis/projects?$top=1`).
   - `200` → proceed.
   - `401` → likely cross-tenant. Resolve the tenant (see §6.4 step 3), then re-authorize against `/{tenantId}/` with `prompt=none` first, interactive on failure. Cache the new token under that tenant. Retry once.
   - `TF400813` → user is authenticated but not authorized in that org (no Basic access / not a member). Distinct message: "You don't have access to this organization."
   - `429` → back off per `Retry-After`.
10. **PAT chosen instead:**
    a. Ask for the **organization URL or name** first (this frames the whole flow as per-org).
    b. Show the scope checklist and a **"Open Azure DevOps to create a token"** button → `expo-web-browser` to `https://dev.azure.com/{org}/_usersSettings/tokens`.
    c. Paste field with clipboard button + auto-trim; optional 84-char/`AZDO` sanity check.
    d. Validate live against that org; map errors (§5.3).
    e. Store `{org, pat, expiresAt?}` in SecureStore; add to the org list as a separate credential-backed entry.
    f. Repeat per org.
11. **Session persistence:** on cold start, load credentials; for Entra tenants refresh if within 5 min of expiry; for PATs, check the recorded expiry and warn at T-7 days.
12. **Sign out** must (a) delete all SecureStore keys including chunks, (b) clear the org cache, and (c) open the Entra `end_session` endpoint so the shared browser cookie doesn't silently re-authenticate the same account on next sign-in.

---

## 12. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | **MSA users can't use Entra OAuth**, and the officially-recommended alternative (legacy ADO OAuth) is closed to us | **Certain today** | **High** — excludes a large share of likely users | Ship PAT login in v1 as a co-equal path; clear in-app explainer; re-test quarterly for MSA support shipping |
| R2 | **Global PATs decommissioned 2026-12-01** (≈12 weeks out) | **Certain** | High if we build cross-org PAT discovery | Design PAT login as per-organization from the start. Do not ship any "one PAT lists all orgs" flow |
| R3 | **Legacy ADO OAuth EOL date still unannounced**; if it lands early it may take adjacent behaviour with it | Medium | Low for us (we don't use it) | None needed; monitor |
| R4 | **Tenant blocks user consent** (`microsoft-user-default-low` without publisher verification) | **High** | High — enterprise users can't sign in without an admin | Complete publisher verification pre-launch; request minimal low-impact scopes; implement admin-consent request UX |
| R5 | **Conditional Access requires a compliant device** → plain OAuth blocked, no in-app fix | Medium–High in large enterprises | High for those tenants | Detect AADSTS53000-class errors and explain; plan MSAL/broker for v2 |
| R6 | **`react-native-msal` unmaintained since Dec 2021** — if we need broker support there is no good off-the-shelf option | High (if R5 forces our hand) | Medium | Budget a custom Expo Module over MSAL iOS/Android; do not adopt the stale package |
| R7 | **Tokens exceed `expo-secure-store`'s ~2048-byte iOS limit** → silent/native storage failures for exactly the enterprise users with the most group claims | **High** | High (looks like random logouts) | Chunking wrapper on day one (§7.4); measure real token sizes early |
| R8 | **Conflicting docs on whether PATs work with Profiles/Accounts APIs** | Certain (conflict exists) | Medium | Empirically test both; design PAT flow not to depend on them |
| R9 | **Cross-tenant orgs need separate tokens**; naive single-token design breaks for consultants/contractors (a core audience) | High | Medium–High | Token cache keyed by tenant; per-org re-auth affordance; test with a multi-tenant account |
| R10 | **iOS keychain survives app uninstall** → stale credentials resurrect on reinstall | Medium | Low–Medium (confusing) | Store an install-id; purge on mismatch |
| R11 | **Rolling refresh tokens** lost on crash mid-refresh → users logged out | Medium | Medium | Persist new refresh token before use; serialize refreshes with a mutex |
| R12 | **Rate limiting (200 TSTU / 5 min)** tripped by multi-org fan-out on launch | Medium | Medium | Throttle/serialize org fan-out; honour `Retry-After`; lazy-load per org |
| R13 | **Tenant shortens access token lifetime to 10 min**, or enables IP CA on non-interactive flows breaking PATs on cellular | Low–Medium | Medium | Never assume ≥1h token life; surface IP-fencing errors distinctly |
| R14 | **Azure DevOps encrypting tokens** — any client-side token introspection breaks | Certain if we do it | High | Treat tokens as opaque; get all identity info from `profiles/me` |
| R15 | **Expo Go can't run the OAuth flow** → dev-loop friction, and any contributor expecting Expo Go is blocked | Certain | Low | Standardise on `expo-dev-client` + EAS from project setup; document it |
| R16 | **Publisher verification requirements** (Partner Center / MPN) not yet scoped and may take weeks | Medium | Medium | Start the verification process early — it gates R4's mitigation |

---

## 13. Open questions / to verify empirically

These could not be settled from documentation and should be tested against real tenants before the design is frozen:

1. **Do PATs actually work against `/_apis/profile/profiles/me` and `/_apis/accounts` today?** (Docs conflict — §6.3.) Test with an org-scoped PAT *and* a global PAT.
2. **What is the real byte size** of an Entra access token and refresh token for the Azure DevOps resource, for (a) a small MSA-adjacent tenant and (b) an enterprise user with many group memberships? (Drives §7.4.)
3. **Does Azure DevOps return `WWW-Authenticate: Bearer authorization_uri=…{tenantId}` on cross-tenant 401s?** If yes, tenant discovery becomes deterministic instead of guesswork (§6.4).
4. **Has an exact 2026 EOL date for Azure DevOps OAuth been published** in a Sprint release note? (Doesn't change our plan; useful for the risk register.)
5. **Any 2025/2026 announcement of MSA support in Entra OAuth for Azure DevOps?** Re-check quarterly (§4.1).
6. **Is `msal{clientId}://auth` still a valid registered redirect form for MSAL iOS**, or is `msauth.{bundleId}://auth` now the only supported one? (§3.2)
7. **Does the current `expo-auth-session` still support / warn about the Expo auth proxy**, and is it fully removed? (§7.1)
8. **`react-native-app-auth` Expo config-plugin support** and whether its native token handling is materially better than `expo-auth-session` for our case (§7.2).
9. **Exact PAT maximum lifetime** per first-party docs (the "1 year" figure is third-party sourced — §5.2).
10. **Publisher verification prerequisites and lead time** (§3.6, R16).
11. **Whether `user_impersonation` truly cannot be combined with granular scopes** (community claim, §3.3) — only matters if we ever need it.
12. **Whether Azure DevOps Server 2025 adds any Entra-based user auth path** for on-prem (§9) — read the ADS 2025 release notes in full.

---

## 14. Citations

### Azure DevOps — authentication & deprecation
- [OAuth 2.0 Authentication for Azure DevOps REST APIs](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops) — full `vso.*` scope catalogue; deprecation warning. *(updated 2026-05-07)*
- [Build Azure DevOps integrations with Microsoft Entra OAuth apps](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra-oauth?view=azure-devops) — resource ID, resource URI, **MSA limitation**. *(ms.date 2026-04-02; updated 2026-05-08)*
- [Use Azure DevOps OAuth 2.0 (legacy)](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/azure-devops-oauth?view=azure-devops) — deprecation banner, 60-day secret rotation, TF400813 FAQ. *(updated 2026-05-08)*
- [Authentication methods for Azure DevOps integrations](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/authentication-guidance?view=azure-devops) — method-by-scenario table; Services-only OAuth; "treat tokens as opaque". *(updated 2026-08-05)*
- [Authenticate to Azure DevOps with Microsoft Entra ID](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra?view=azure-devops)
- [Azure DevOps Blog — No new Azure DevOps OAuth apps beginning April 2025](https://devblogs.microsoft.com/devops/no-new-azure-devops-oauth-apps/) — **April 23, 2025** registration cutoff; EOL "in 2026".
- [Azure DevOps Blog — New Azure DevOps scopes now available for Microsoft Identity OAuth delegated flow apps](https://devblogs.microsoft.com/devops/new-azure-devops-scopes-now-available-for-microsoft-identity-oauth-delegated-flow-apps/) — granular Entra scopes (2023-09-28).
- [Azure DevOps Blog — Reducing PAT usage across Azure DevOps](https://devblogs.microsoft.com/devops/reducing-pat-usage-across-azure-devops/)
- [Azure DevOps Blog — Azure DevOps will no longer support Alternate Credentials authentication](https://devblogs.microsoft.com/devops/azure-devops-will-no-longer-support-alternate-credentials-authentication/)
- [Azure DevOps Blog — Removing Azure Resource Manager reliance on Azure DevOps sign-ins](https://devblogs.microsoft.com/devops/removing-azure-resource-manager-reliance-on-azure-devops-sign-ins/) (Sept 2025)

### PATs
- [Use personal access tokens](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops) — format (84 chars, `AZDO` at 76–80), Basic auth, rotation, PAT Lifecycle API notes, "profiles/organizations APIs are Entra-only" FAQ. *(updated 2026-09-04)*
- [Manage personal access tokens using policies (admins)](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/manage-pats-with-policies-for-administrators?view=azure-devops)
- [Manage personal access tokens using API](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/manage-personal-access-tokens-via-api?view=azure-devops)
- [PATs — REST API (Azure DevOps Tokens)](https://learn.microsoft.com/en-us/rest/api/azure/devops/tokens/pats?view=azure-devops-rest-7.1)
- [Azure DevOps Blog — Retirement of Global Personal Access Tokens in Azure DevOps](https://devblogs.microsoft.com/devops/retirement-of-global-personal-access-tokens-in-azure-devops/) — **December 1, 2026** decommission; March 15 block rescinded.
- [Sample: PAT Lifecycle Management API Python app](https://github.com/microsoft/azure-devops-auth-samples/tree/master/PersonalAccessTokenAPIAppSample)

### Org / profile discovery
- [Accounts - List (REST 7.1)](https://learn.microsoft.com/en-us/rest/api/azure/devops/account/accounts/list?view=azure-devops-rest-7.1)
- [Profiles - Get (REST 7.1)](https://learn.microsoft.com/en-us/rest/api/azure/devops/profile/profiles/get?view=azure-devops-rest-7.1)
- [Q&A — Issue with Listing Azure DevOps Organizations for a Service Principal](https://learn.microsoft.com/en-us/answers/questions/2236987/issue-with-listing-azure-devops-organizations-for)
- [Q&A — How to Access Azure DevOps Resources via Microsoft Entra OAuth Apps from a Third-Party Application](https://learn.microsoft.com/en-us/answers/questions/2203005/how-to-access-azure-devops-resources-via-microsoft)
- [Azure DevOps rate limits](https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits)

### Org & tenant policies, Conditional Access
- [Change application connection and security policies](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/change-application-access-policies?view=azure-devops) — "Third-party application access through OAuth" **defaults off for new orgs** and **does not affect Entra OAuth apps**. *(updated 2026-05-08)*
- [Conditional Access policies on Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies?view=azure-devops) — resource ID for CA targeting, device conditions, IP fencing, CAE. *(updated 2026-05-08)*
- [Configure how users consent to applications (Entra)](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent) — `microsoft-user-default-low` / `-legacy` policies. *(updated 2026-08-04)*
- [Configure the admin consent workflow](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-admin-consent-workflow)
- [Publisher verification overview](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview)

### Microsoft identity platform / MSAL
- [Configurable token lifetimes](https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes) — 60–90 min access tokens, CAE 24–28h, refresh 90-day inactivity, non-configurable since 2021-01-30. *(updated 2026-06-15)*
- [Client application configuration (MSAL)](https://learn.microsoft.com/en-us/entra/identity-platform/msal-client-application-configuration) — authorities (`common`/`organizations`/`consumers`/`{tenant}`), mobile redirect URI formats. *(ms.date 2025-05-14)*
- [Use redirect URIs with MSAL (iOS/macOS)](https://learn.microsoft.com/en-us/entra/msal/objc/redirect-uris-ios)
- [MSAL Android configuration file](https://learn.microsoft.com/en-us/entra/msal/android/msal-configuration)
- [Brokered auth in Android / single sign-on](https://learn.microsoft.com/en-us/entra/identity-platform/msal-android-single-sign-on)
- [Quickstart: Register an application](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
- [Web API app registration and API permissions](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-configure-app-access-web-apis)
- [Scopes and permissions / the `.default` scope](https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc)
- [Claims challenges and CAE](https://learn.microsoft.com/en-us/entra/identity-platform/claims-challenge)
- [Continuous Access Evaluation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation)

### Azure DevOps Server (on-prem)
- [Azure DevOps Server release notes](https://learn.microsoft.com/en-us/azure/devops/server/release-notes/azuredevopsserver?view=azure-devops)
- [Azure DevOps Blog — Reconfigure Azure DevOps Server to use Kerberos instead of NTLM](https://devblogs.microsoft.com/devops/reconfigure-azure-devops-server-to-use-kerberos-instead-of-ntlm/)
- [Get started with the REST APIs for Azure DevOps Services and Server](https://learn.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-7.2)

### Expo / React Native
- [Expo AuthSession SDK](https://docs.expo.dev/versions/latest/sdk/auth-session/) — `usePKCE` default true, S256, `makeRedirectUri`.
- [Expo Authentication guide](https://docs.expo.dev/guides/authentication/) — "Expo Go cannot be used for local development and testing of OAuth… use a Development Build."
- [Expo SecureStore SDK](https://docs.expo.dev/versions/latest/sdk/securestore/) — "**Historically, some iOS releases refused values above roughly 2048 bytes**"; keychain accessibility; `requireAuthentication`; uninstall behaviour.
- [`react-native-msal` (stashenergy)](https://github.com/stashenergy/react-native-msal) and its [Expo setup doc](https://github.com/stashenergy/react-native-msal/blob/master/docs/expo_setup.md) — npm `4.0.4` published **2021-12-23** (registry checked 2026-09-10).
- [`react-native-msal` fork (equinor)](https://github.com/equinor/react-native-msal)
- `react-native-app-auth` — npm `8.4.1` published **2026-07-06** (registry checked 2026-09-10).
- [`@neverdull-agency/expo-unlimited-secure-store`](https://www.npmjs.com/package/@neverdull-agency/expo-unlimited-secure-store) — AES-256 + FileSystem envelope pattern (not audited).

### Third-party corroboration
- [syntevo / SmartGit — "Azure DevOps authentication: please switch to personal access tokens" (2026-05-25)](http://blog.syntevo.com/smartgit/2026/05/25/azure-devops-client-secret-expired.html) — a mainstream commercial client concluding PATs are the answer because Entra OAuth lacks MSA support.
- [Mend.io — Azure DevOps Global PAT and OAuth deprecation](https://docs.mend.io/integrations/latest/azure-devops-global-pat-and-oauth-1.0-deprecation)
- [Snyk — Microsoft retires Azure global personal access tokens](https://updates.snyk.io/microsoft-retires-azure-global-personal-access-tokens/)
- [microsoft/vsmarketplace #2121 — Support publishing extensions with organization-scoped PATs due to global PATs being retired](https://github.com/microsoft/vsmarketplace/issues/2121)

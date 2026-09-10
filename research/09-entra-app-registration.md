# 09 — Entra ID app registration for Boardhop

**Date:** 2026-09-10
**Purpose:** step-by-step instructions to register the Boardhop mobile app in Microsoft Entra ID and enable it for the puremedia organization, so that Microsoft sign-in with the Authenticator broker works against Azure DevOps.

There are two separate jobs, done by two different people:

| Part | Who | Where | What |
|---|---|---|---|
| **A. Create the app registration** | kammcs (Kelly or a kammcs Global Administrator / Application Administrator) | The **kammcs** Entra tenant | Registers Boardhop as a multi-tenant public client with Azure DevOps permissions |
| **B. Enable it for puremedia** | puremedia Entra administrator | The **puremedia** Entra tenant | Grants admin consent, checks Conditional Access, provides test accounts |

**Why the registration must live in the kammcs tenant.** Boardhop is a product sold to many organizations. The tenant that owns the registration is the publisher: its name appears on every customer's consent screen, publisher verification is tied to its Partner Center account, and it controls the client ID for the life of the app. Registering in puremedia's tenant would make puremedia the publisher of Boardhop. Puremedia only needs to *consent* to the app.

If kammcs does not yet have an Entra tenant with a verified `kammcs.com` domain, that must be created first (any Microsoft 365 or Azure subscription provides one).

---

## Part A — Create the app registration (kammcs tenant)

### A1. Values to decide before starting

| Item | Value | Notes |
|---|---|---|
| Display name | `Boardhop` | Shown on the consent screen. Must not contain "Azure DevOps" or "Microsoft". |
| iOS bundle identifier | `com.kammcs.boardhop` | Proposed. Must match the Xcode project exactly. |
| Android package name | `com.kammcs.boardhop` | Proposed. Must match `applicationId` in `android/app/build.gradle`. |
| Android signature hashes | one per signing key (see A5) | Debug keystore, release keystore, **and** the Google Play app-signing certificate. |
| Publisher domain | `kammcs.com` | Must be a verified domain in the kammcs tenant. |
| Owners | Kelly plus one backup | Owners can rotate credentials and change redirect URIs. |

### A2. Register the application

In the Entra admin center (`https://entra.microsoft.com`), signed in to the kammcs tenant:

1. Go to **Identity → Applications → App registrations → New registration**.
2. **Name:** `Boardhop`.
3. **Supported account types:** **Accounts in any organizational directory (Any Microsoft Entra ID tenant – Multitenant)**.
   Do **not** select the option that includes personal Microsoft accounts. Azure DevOps does not accept Entra tokens for personal accounts, and excluding them gives those users a clean error at sign-in instead of a confusing failure later.
4. **Redirect URI:** leave blank for now (added in A3).
5. Click **Register**. Record the **Application (client) ID** and the **Directory (tenant) ID** from the Overview page.

### A3. Add the mobile platform and redirect URIs

1. Open **Authentication → Add a platform → Mobile and desktop applications**.
2. Under **Custom redirect URIs**, add:

   ```
   msauth.com.kammcs.boardhop://auth
   ```
   This is the iOS redirect used by MSAL and the Authenticator broker.

3. Add one Android redirect per signing key, in the form `msauth://{package}/{url-encoded base64 signature hash}`:

   ```
   msauth://com.kammcs.boardhop/{DEBUG_HASH}
   msauth://com.kammcs.boardhop/{RELEASE_HASH}
   msauth://com.kammcs.boardhop/{PLAY_APP_SIGNING_HASH}
   ```
   Kelly supplies the hashes (see A5). The hash must be URL-encoded: `+` becomes `%2B`, `/` becomes `%2F`, `=` becomes `%3D`.

4. Scroll to **Advanced settings → Allow public client flows** and set it to **Yes**. Mobile apps cannot hold a client secret.
5. Leave **Implicit grant and hybrid flows** unchecked.
6. Save.

Do not create a client secret or certificate. None is needed for a public client, and one must never ship inside a mobile app.

### A4. API permissions

1. Open **API permissions → Add a permission**.
2. On the **Microsoft APIs** tab, scroll to and select **Azure DevOps**. (If it is not listed there, use the **APIs my organization uses** tab and search for `Azure DevOps`; its application ID is `499b84ac-1321-427f-aa17-267ca6975798`.)
3. Choose **Delegated permissions** and tick:

   | Permission | Used for |
   |---|---|
   | `vso.profile` | Identifying the signed-in user and listing their organizations |
   | `vso.project` | Listing projects and teams |
   | `vso.work` | Reading work items, queries, boards, sprints |
   | `vso.work_write` | Editing work items, comments, moving cards |
   | `vso.code` | Reading repositories, pull requests, diffs |
   | `vso.threads_full` | Posting and replying to pull request comments |
   | `vso.code_write` | Voting on and completing pull requests |
   | `vso.build` | Reading pipelines, runs and logs |
   | `vso.build_execute` | Queueing and cancelling runs |
   | `vso.wiki` | Reading wiki pages |
   | `vso.graph` | Looking up people and avatars for pickers |

   The app requests only the read scopes at first sign-in and asks for the write scopes when the user first performs a write, so the initial consent screen stays small. Listing them all here lets a tenant admin consent once for everything.

4. **Add a permission → Microsoft Graph → Delegated** and tick `openid`, `profile`, `offline_access`. `offline_access` is what allows silent refresh without re-prompting. Do **not** add `User.Read` or any other Graph permission.
5. Do not click "Grant admin consent" in the kammcs tenant unless kammcs itself will use the app. Customer tenants grant their own consent (Part B).

### A5. Android signature hashes (Kelly)

The Android redirect URI embeds the SHA-1 of the signing certificate, base64-encoded. There is one hash per keystore.

Debug keystore:

```bash
keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android | openssl sha1 -binary | openssl base64
```

Release keystore:

```bash
keytool -exportcert -alias <release-alias> -keystore <release.keystore> | openssl sha1 -binary | openssl base64
```

Google Play app signing: when Play App Signing is enabled, Google re-signs the store build with its own key. Take the **SHA-1** from Play Console → **Test and release → App integrity → App signing key certificate**, convert it to base64 (hex → bytes → base64), and register that hash too. Without it, sign-in works in debug and internal builds and fails for store installs.

Register each resulting value in A3, URL-encoded.

### A6. Branding and publisher verification (needed before public launch, not for testing)

1. **Branding & properties:** logo (215×215 PNG), home page `https://boardhop.app` (or the chosen domain), terms of service and privacy statement URLs, **Publisher domain** `kammcs.com`.
2. **Publisher verification:** requires a Microsoft Partner Center account with a verified MPN (Partner) ID linked to the kammcs tenant. Once linked, open **Branding & properties → Publisher verification → Add MPN ID to verify publisher**. The blue "verified" badge is what lets users in tenants with the default consent policy ("allow user consent for verified publishers only") sign in without an admin.

### A7. Values to send to the puremedia admin and to the app configuration

After A2 to A5, send the puremedia admin:

- Application (client) ID
- The display name `Boardhop`
- The list of permissions from A4 (so they know what they are consenting to)
- The admin-consent URL from B2 with the client ID filled in

Record for the app configuration (never commit real IDs to a public repo):

- Client ID
- Authority for first sign-in: `https://login.microsoftonline.com/organizations`
- Scopes: `499b84ac-1321-427f-aa17-267ca6975798/vso.profile`, `.../vso.project`, `.../vso.work`, `.../vso.code`, `.../vso.build`, `.../vso.wiki`, `.../vso.graph`, plus `offline_access`, `openid`, `profile`
- Redirect URIs as registered

---

## Part B — Enable Boardhop for puremedia (puremedia Entra administrator)

Boardhop is registered by kammcs as a multi-tenant application. Nothing is created in the puremedia tenant except an enterprise application (service principal) record that appears automatically at first consent. No secrets, no data flows to kammcs; the app talks directly from the phone to Azure DevOps with the signed-in user's own token.

### B1. Information kammcs will send you

- Application (client) ID: `________________________________`
- Display name: `Boardhop`
- Publisher: kammcs (`kammcs.com`)
- Delegated permissions requested: Azure DevOps `vso.profile`, `vso.project`, `vso.work`, `vso.work_write`, `vso.code`, `vso.threads_full`, `vso.code_write`, `vso.build`, `vso.build_execute`, `vso.wiki`, `vso.graph`; Microsoft Graph `openid`, `profile`, `offline_access`.

All permissions are **delegated**: the app can only do what the signed-in user can already do in Azure DevOps. It has no application (app-only) permissions and no access when no user is signed in.

### B2. Grant tenant-wide admin consent

Open this URL in a browser while signed in as a puremedia Global Administrator, Privileged Role Administrator, or Cloud Application Administrator, replacing the client ID:

```
https://login.microsoftonline.com/{puremedia-tenant-id-or-domain}/adminconsent?client_id={client-id}
```

Review the permission list and accept. This creates the **Boardhop** entry under **Identity → Applications → Enterprise applications** and pre-approves the permissions for every user in the tenant, so individual users are not prompted.

Alternative without the URL: after any user first attempts to sign in, the app appears under Enterprise applications; open it, go to **Permissions**, and click **Grant admin consent for puremedia**.

If your tenant's user consent setting is "Allow user consent for apps from verified publishers", users could consent themselves once kammcs completes publisher verification. Admin consent is simpler for the pilot.

### B3. Check the enterprise application settings

Under **Enterprise applications → Boardhop → Properties**:

- **Enabled for users to sign in:** Yes
- **Assignment required:** No for the pilot (or Yes, and then assign the pilot users or a group under **Users and groups**)
- **Visible to users:** either

### B4. Check Conditional Access for Azure DevOps

Boardhop signs in through the Microsoft Authenticator broker, so it can satisfy device-based policies. Please tell kammcs which of these apply to the **Azure DevOps** cloud app (resource ID `499b84ac-1321-427f-aa17-267ca6975798`) in your Conditional Access policies:

| Policy grant | Effect on Boardhop |
|---|---|
| Require multifactor authentication | Works. MFA happens in the broker or browser. |
| Require device to be marked as compliant, or Hybrid Entra joined | Works **only** with Microsoft Authenticator installed and the device registered or enrolled. Pilot devices need Authenticator. |
| Require approved client app | **Blocks** Boardhop. This grant matches only Microsoft's own apps. |
| Require app protection policy | **Blocks** Boardhop today. Requires the Intune App SDK, which kammcs can add as a later phase if required. |
| Location or IP restrictions | Phones on cellular networks will be blocked unless the policy exempts them. |
| Sign-in frequency or persistent browser session | Works; users re-authenticate on the stated schedule. |

For the pilot, kammcs asks for **one test user covered by a compliant-device policy and one not covered**, so both paths are exercised.

Also confirm whether **"Enable IP Conditional Access policy validation on non-interactive flows"** is turned on in the Azure DevOps organization settings (Organization settings → Policies). If it is, API calls from mobile networks will fail even after sign-in succeeds.

### B5. Azure DevOps organization side

Nothing to change. The Azure DevOps policy "Third-party application access via OAuth" applies only to the retired Azure DevOps OAuth platform and does not affect Entra ID applications. Test users need at least **Basic** access in the puremedia Azure DevOps organization and membership in the projects they will test with. The scratch project "DevOps Mobile App" already exists for write testing.

### B6. Test devices and accounts

Please provide or confirm:

1. Puremedia tenant ID (from Entra admin center → Overview).
2. Two test user accounts as described in B4, with Basic access in Azure DevOps and access to the "DevOps Mobile App" project.
3. Microsoft Authenticator installed and signed in on at least one iOS and one Android test device, registered with the puremedia tenant (Settings → Device registration, or via Company Portal if Intune-enrolled).
4. Optionally, a guest (B2B) account from another tenant that has access to the puremedia Azure DevOps organization, for testing cross-tenant sign-in.

### B7. What you will see in logs

Sign-ins appear under **Identity → Monitoring & health → Sign-in logs** with application `Boardhop`, resource `Azure DevOps`. Consent events appear in the audit log as "Consent to application". Boardhop can be disabled at any time from Enterprise applications → Properties, which revokes access for all puremedia users immediately.

---

## Reference

- Azure DevOps resource (application) ID: `499b84ac-1321-427f-aa17-267ca6975798`
- Scopes are requested as `499b84ac-1321-427f-aa17-267ca6975798/vso.work` and so on; both Azure DevOps OAuth and Entra ID OAuth use the same scope catalogue.
- Microsoft Learn: [Build Azure DevOps integrations with Microsoft Entra OAuth apps](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/entra-oauth), [Redirect URIs for MSAL on iOS](https://learn.microsoft.com/en-us/entra/msal/objc/redirect-uris-ios), [MSAL Android configuration](https://learn.microsoft.com/en-us/entra/msal/android/msal-configuration), [Grant tenant-wide admin consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/grant-admin-consent), [Publisher verification](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview), [Conditional Access policies on Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/conditional-access-policies)

# 09 — Entra ID app registration for Boardhop

**Date:** 2026-09-10
**Purpose:** step-by-step instructions to register the Boardhop mobile app in Microsoft Entra ID and enable it for the puremedia organization, so that Microsoft sign-in with the Authenticator broker works against Azure DevOps.

There are two separate jobs, done by two different people:

| Part | Who | Where | What |
|---|---|---|---|
| **A. Create the app registration** | kammcs (Kelly or a kammcs Global Administrator / Application Administrator) | The **kammcs** Entra tenant | Registers Boardhop as a multi-tenant public client with Azure DevOps permissions |
| **B. Enable it for puremedia** | puremedia Entra administrator | The **puremedia** Entra tenant | Grants admin consent, checks Conditional Access, provides test accounts |

**Why the registration must live in the kammcs tenant.** Boardhop is a product sold to many organizations. The tenant that owns the registration is the publisher: its name appears on every customer's consent screen, publisher verification is tied to its Partner Center account, and it controls the client ID for the life of the app. Registering in puremedia's tenant would make puremedia the publisher of Boardhop. Puremedia only needs to *consent* to the app.

kammcs already has an Entra tenant, created for the Multipass Windows code-signing project. Step A0 prepares it.

---

## Part A — Create the app registration (kammcs tenant)

### A0. Prepare the existing kammcs tenant

App registrations need an Entra ID tenant, not a paid Azure subscription; **Entra ID Free** covers app registrations, multi-tenant apps and custom domains. The kammcs tenant from the Multipass code-signing work is the right home. Its tenant ID does not change and is the one referenced throughout this document.

1. Sign in to `https://entra.microsoft.com` for that tenant and record the **Tenant ID** from Overview.
2. **Verify the `kammcs.com` domain** if it is not already listed as verified: Identity → Settings → Domain names → Add custom domain → `kammcs.com`, add the TXT record at the DNS host, then Verify. Required for the publisher domain in A6 and for a non-`.onmicrosoft.com` publisher name on the consent screen. It does not affect email or anything else about kammcs.com.
3. Make sure there is a second Global Administrator account and MFA is on for both.
4. **Do not rename or reuse the existing "Azure Example App" registration.** It was created for code signing and is the wrong shape (single-tenant, holds a secret or certificate, likely has an Azure role). Boardhop needs a multi-tenant public client with delegated Azure DevOps permissions and no secret. Renaming would also keep the old client ID, which the signing pipeline may still reference, and would put a mobile app and a signing credential under one identity. Create a new registration (A2). Leave the old one in place until it is confirmed unused by Multipass, then delete it.

No Azure subscription resources are needed for Boardhop until the push gateway (document 06) is built, and that can run on the free tier of Azure Functions in the same tenant.

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
2. On the **Microsoft APIs** tab, scroll past the "Commonly used" Graph tile to the full list, or type `Azure DevOps` in that tab's search box, and select **Azure DevOps**.

   **If Azure DevOps is not listed anywhere** (as happened in the kammcs tenant on 2026-09-10): the Azure DevOps service principal is only provisioned in a tenant once someone in that tenant has used Azure DevOps, and "APIs my organization uses" lists only provisioned service principals. Create it with the Azure CLI (Cloud Shell in the portal works, no subscription needed):

   ```powershell
   az login --tenant <kammcs-tenant-id> --allow-no-subscriptions
   az ad sp create --id 499b84ac-1321-427f-aa17-267ca6975798
   ```

   or with Microsoft Graph PowerShell:

   ```powershell
   Connect-MgGraph -TenantId <kammcs-tenant-id> -Scopes "Application.ReadWrite.All"
   New-MgServicePrincipal -AppId 499b84ac-1321-427f-aa17-267ca6975798
   ```

   Then reopen Add a permission → **APIs my organization uses** → search `Azure DevOps`. Alternatively, sign in at `https://dev.azure.com` with a kammcs-tenant account and create a free organization; that provisions the service principal as a side effect and gives kammcs a dogfooding org. Customer tenants that already use Azure DevOps (puremedia) are unaffected.
3. Choose **Delegated permissions** and tick:

   | Permission | Used for |
   |---|---|
   | `vso.profile` | Identifying the signed-in user and listing their organizations |
   | `vso.project` | Listing projects and teams |
   | `vso.work` | Reading work items, queries, boards, sprints |
   | `vso.work_write` | Editing work items, comments, moving cards |
   | `vso.code` | Reading repositories, pull requests, diffs |
   | `vso.code_write` | Pull request comments, votes and completion |
   | `vso.build` | Reading pipelines, runs and logs |
   | `vso.build_execute` | Queueing and cancelling runs |
   | `vso.wiki` | Reading wiki pages |
   | `vso.graph` | Looking up people and avatars for pickers |

   The app requests only the read scopes at first sign-in and asks for the write scopes when the user first performs a write, so the initial consent screen stays small. Listing them all here lets a tenant admin consent once for everything.

   **Not every legacy Azure DevOps OAuth scope is exposed on the Entra side.** `vso.threads_full` (PR comment threads without code write) is absent from the Entra permission list as of 2026-09-10, despite the docs saying both platforms share the same catalogue. The threads API also accepts `vso.code_write`, which is already required for votes and completion, so nothing is lost. If any other scope in the table above is missing, skip it and note it; do not substitute `user_impersonation`.

4. **Add a permission → Microsoft Graph → Delegated** and tick `openid`, `profile`, `offline_access`. `offline_access` is what allows silent refresh without re-prompting. Do **not** add `User.Read` or any other Graph permission.
5. Do not click "Grant admin consent" in the kammcs tenant unless kammcs itself will use the app. Customer tenants grant their own consent (Part B).

### A5. Android signature hashes (Kelly)

The Android redirect URI embeds the SHA-1 of the signing certificate, base64-encoded. There is one hash per keystore.

`keytool` ships with a JDK, not on its own. On this machine it is bundled with Android Studio at `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`, and `openssl` is available in Git Bash. Run the commands below in Git Bash.

Debug keystore (already computed on Kelly's machine on 2026-09-10; the debug certificate is machine-specific, so a second developer machine has its own hash):

```bash
KT="/c/Program Files/Android/Android Studio/jbr/bin/keytool.exe"
"$KT" -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android | openssl sha1 -binary | openssl base64
```

Result on Kelly's machine: hash `//ksb0DQrePXmmxPydZ/Ubpze98=`, which URL-encodes to

```
msauth://com.kammcs.boardhop/%2F%2Fksb0DQrePXmmxPydZ%2FUbpze98%3D
```

PowerShell alternative without openssl (any keystore):

```powershell
$kt = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
$sha1 = (& $kt -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android | Select-String "SHA1:").ToString().Split(":",2)[1].Trim()
$bytes = $sha1.Split(":") | ForEach-Object { [Convert]::ToByte($_, 16) }
$b64 = [Convert]::ToBase64String($bytes)
"$b64  ->  msauth://com.kammcs.boardhop/" + [Uri]::EscapeDataString($b64)
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
- Delegated permissions requested: Azure DevOps `vso.profile`, `vso.project`, `vso.work`, `vso.work_write`, `vso.code`, `vso.code_write`, `vso.build`, `vso.build_execute`, `vso.wiki`, `vso.graph`; Microsoft Graph `openid`, `profile`, `offline_access`.

All permissions are **delegated**: the app can only do what the signed-in user can already do in Azure DevOps. It has no application (app-only) permissions and no access when no user is signed in.

### B2. Grant tenant-wide admin consent

Open this URL in a browser while signed in as a puremedia Global Administrator, Privileged Role Administrator, or Cloud Application Administrator, replacing the client ID:

```
https://login.microsoftonline.com/342d4cd1-7ea8-4452-8ceb-542b71d159f6/adminconsent?client_id={client-id}
```

(`342d4cd1-7ea8-4452-8ceb-542b71d159f6` is the Entra tenant that backs the puremedia Azure DevOps organization; its verified domain is `cloudcover.it`. Confirmed 2026-09-10 from the org's Graph users and from the OpenID discovery document for that domain.)

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

1. Confirm the tenant ID `342d4cd1-7ea8-4452-8ceb-542b71d159f6` (Entra admin center → Overview) is the tenant you administer.
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

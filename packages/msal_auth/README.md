# msal_auth (Boardhop fork)

Vendored copy of [msal_auth 3.5.3](https://pub.dev/packages/msal_auth) by Aubergine Solutions (MIT, see LICENSE) with additions Boardhop needs for Azure DevOps Continuous Access Evaluation. Upstream: https://github.com/nayanAubie/msal_auth.

Changes from 3.5.3 (see CHANGELOG.md, sections 3.5.3+boardhop.1 and +boardhop.2):

- `acquireToken(claims:)` and `acquireTokenSilent(claims:, forceRefresh:)` on Dart, Android and iOS.
- `AppleConfig.clientCapabilities` → `MSALPublicClientApplicationConfig.clientApplicationCapabilities`. Android reads `client_capabilities` from the configuration JSON as before.
- iOS: `createPca` mirrors the configuration it is given (`clientId`, `authority`, `authorityType`, `redirectUri`, `clientCapabilities`) into a shared `UserDefaults` suite when the host app's `Info.plist` has a string key `MsalAuthSharedDefaultsSuite` naming an app group, under the key `MsalAuthConfig`. Without that plist key nothing is written and behaviour is unchanged. Apple's MSAL keeps its configuration in memory, so an app extension — Boardhop's Notification Service Extension, which refreshes a token silently to enrich a push — has no other way to build the same client; Android's side already writes `msal_config.json`. Only the values Dart passed are written: no tokens, no accounts.
- macOS is untouched: it ignores the new arguments.

Intended to be offered upstream. Until then, keep the diff small so a rebase onto the next release stays easy.

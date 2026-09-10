# msal_auth (Boardhop fork)

Vendored copy of [msal_auth 3.5.3](https://pub.dev/packages/msal_auth) by Aubergine Solutions (MIT, see LICENSE) with additions Boardhop needs for Azure DevOps Continuous Access Evaluation. Upstream: https://github.com/nayanAubie/msal_auth.

Changes from 3.5.3 (see CHANGELOG.md, section 3.5.3+boardhop.1):

- `acquireToken(claims:)` and `acquireTokenSilent(claims:, forceRefresh:)` on Dart, Android and iOS.
- `AppleConfig.clientCapabilities` → `MSALPublicClientApplicationConfig.clientApplicationCapabilities`. Android reads `client_capabilities` from the configuration JSON as before.
- macOS is untouched: it ignores the new arguments.

Intended to be offered upstream. Until then, keep the diff small so a rebase onto the next release stays easy.

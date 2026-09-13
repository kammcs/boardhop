import Foundation
import MSAL

/// The MSAL configuration the app was built with, mirrored into the app group
/// by the patched `msal_auth` iOS plugin on every start.
///
/// Android gets this for free: its MSAL plugin writes `msal_config.json` into
/// the cache directory and `PushTokens.kt` reads it. The iOS plugin builds
/// `MSALPublicClientApplicationConfig` in memory from the Dart arguments and
/// persists nothing, so R2.7 added the mirror (see packages/msal_auth/README.md).
///
/// `clientId` is a secret by Boardhop's rules: it is read, used and never
/// logged or copied anywhere else.
struct MsalConfig {
  let clientId: String
  let authority: String?
  let authorityType: String
  let redirectUri: String?
  let clientCapabilities: [String]

  static func load(from defaults: UserDefaults? = PushSharedDefaults.defaults) -> MsalConfig? {
    guard let raw = defaults?.dictionary(forKey: PushSharedDefaults.msalConfigKey),
      let clientId = raw["clientId"] as? String, !clientId.isEmpty
    else { return nil }
    return MsalConfig(
      clientId: clientId,
      authority: raw["authority"] as? String,
      authorityType: (raw["authorityType"] as? String) ?? "aad",
      redirectUri: raw["redirectUri"] as? String,
      clientCapabilities: (raw["clientCapabilities"] as? [String]) ?? [])
  }
}

/// An Azure DevOps access token for the account that registered one
/// organization, acquired **silently** inside the notification service
/// extension (research/14 §4.1, "Token").
///
/// How the extension reaches MSAL without a second client id anywhere:
///
/// * **Configuration** comes from the app group ([MsalConfig]).
/// * **Account**: `PushRegistrar` stores the MSAL account identifier per
///   organization, and `PushService.mirrorAccount` copies it into the group
///   defaults for exactly this call.
/// * **Cache**: MSAL keeps its tokens in the keychain group
///   `com.microsoft.adalcache`. Both bundles are signed by team 73W98CESN9 with
///   `$(AppIdentifierPrefix)com.microsoft.adalcache` in `keychain-access-groups`,
///   so the extension opens the same cache the app filled — it never signs
///   anybody in, it only refreshes.
///
/// Anything at all going wrong — no configuration, no account, an expired
/// refresh token, `MSALErrorInteractionRequired`, Conditional Access — returns
/// nil and the caller delivers the fallback line. Interaction is never
/// attempted from here (there is no UI in an extension); the app raises
/// `AuthInteractionRequired` the next time it is opened, as it does today.
enum PushTokens {

  /// research/09: the Azure DevOps resource, the same scope `AppConfig` uses.
  static let adoScope = "499b84ac-1321-427f-aa17-267ca6975798/.default"

  /// The keychain group MSAL shares between the app and its extensions.
  static let keychainGroup = "com.microsoft.adalcache"

  private static var cached: MSALPublicClientApplication?

  /// A token for [org], or nil.
  static func token(org: String, accountId: String, config: MsalConfig) async -> String? {
    guard let application = client(config) else { return nil }
    guard let account = try? application.account(forIdentifier: accountId) else {
      NSLog("%@: token, the registered account is no longer in the MSAL cache", pushLogTag)
      return nil
    }
    let parameters = MSALSilentTokenParameters(scopes: [adoScope], account: account)
    return await withCheckedContinuation { continuation in
      application.acquireTokenSilent(with: parameters) { result, error in
        if let token = result?.accessToken {
          NSLog("%@: token acquired silently", pushLogTag)
          continuation.resume(returning: token)
        } else {
          // MSALErrorInteractionRequired and everything else alike: the
          // fallback line. The error is named by code only, never by message.
          NSLog(
            "%@: token, silent acquisition failed (code %ld)", pushLogTag,
            (error as NSError?)?.code ?? 0)
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private static func client(_ config: MsalConfig) -> MSALPublicClientApplication? {
    if let cached { return cached }
    // There is no broker in an extension: the Authenticator cannot be opened
    // from here, and leaving this on `auto` makes MSAL check for URL schemes
    // this bundle does not have.
    MSALGlobalConfig.brokerAvailability = .none
    do {
      let pcaConfig: MSALPublicClientApplicationConfig
      if let authority = config.authority, let url = URL(string: authority) {
        if config.authorityType == "b2c" {
          let b2c = try MSALB2CAuthority(url: url)
          pcaConfig = MSALPublicClientApplicationConfig(
            clientId: config.clientId, redirectUri: config.redirectUri, authority: b2c)
          pcaConfig.knownAuthorities = [b2c]
        } else {
          let aad = try MSALAuthority(url: url)
          pcaConfig = MSALPublicClientApplicationConfig(
            clientId: config.clientId, redirectUri: config.redirectUri, authority: aad)
        }
      } else {
        pcaConfig = MSALPublicClientApplicationConfig(
          clientId: config.clientId, redirectUri: config.redirectUri, authority: nil)
      }
      // The redirect URI is the **app's**, and this bundle does not (and must
      // not) register its scheme: MSAL would otherwise reject a URI it cannot
      // find in this Info.plist. Nothing interactive ever runs here, so the
      // URI is only ever part of the silent request's parameters.
      pcaConfig.bypassRedirectURIValidation = true
      pcaConfig.cacheConfig.keychainSharingGroup = keychainGroup
      if !config.clientCapabilities.isEmpty {
        pcaConfig.clientApplicationCapabilities = config.clientCapabilities
      }
      let application = try MSALPublicClientApplication(configuration: pcaConfig)
      cached = application
      return application
    } catch {
      NSLog("%@: token, MSAL client creation failed (code %ld)", pushLogTag, (error as NSError).code)
      return nil
    }
  }
}

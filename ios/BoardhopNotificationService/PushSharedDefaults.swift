import Foundation

/// The one place the Runner and BoardhopNotificationService agree on names.
///
/// An app extension is a separate process with its own container: it cannot
/// read the app's standard `UserDefaults`, which is where `shared_preferences`
/// writes (`flutter.` + key), and it cannot read the app's files. The app group
/// is the only door between the two, so the two things the extension needs —
/// which account registered an organization, and the MSAL configuration to
/// build a client from — are mirrored into it.
///
/// Nothing secret is stored here. An MSAL account identifier is not a token,
/// and the configuration is the same public client id the app ships with; both
/// stay inside the group container and neither is ever logged.
///
/// This file is compiled into **both** targets so the key names cannot drift.
enum PushSharedDefaults {

  /// research/14 R2.7: the app group both bundles carry in their entitlements.
  static let suiteName = "group.com.kammcs.boardhop"

  /// Where the patched `msal_auth` iOS plugin writes the configuration it was
  /// given, when `MsalAuthSharedDefaultsSuite` names this suite in the host
  /// app's Info.plist. The same literal lives in
  /// `packages/msal_auth/ios/msal_auth/Sources/msal_auth/MsalAuthPlugin.swift`;
  /// the plugin is a package and cannot import this file.
  static let msalConfigKey = "MsalAuthConfig"

  /// `push.msal.account.{org}` — the same key name `PushRegistrar` uses in
  /// shared preferences, so the two stores read alike.
  static func accountKey(org: String) -> String { "push.msal.account.\(org)" }

  static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

  /// The MSAL account identifier that registered [org] for push, or nil.
  static func accountId(org: String) -> String? {
    guard let value = defaults?.string(forKey: accountKey(org: org)), !value.isEmpty else {
      return nil
    }
    return value
  }

  static func setAccountId(_ accountId: String, org: String) {
    defaults?.set(accountId, forKey: accountKey(org: org))
  }

  static func clearAccountId(org: String) {
    defaults?.removeObject(forKey: accountKey(org: org))
  }
}

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

  /// Pointers the extension handled while the app was not listening, waiting
  /// for Dart to take them (`drainPushed` on the push channel). Without this
  /// the Activity feed's poll finds the same artifact later and announces it
  /// a second time, with the feed row's coarser route. Metadata only: the
  /// relay's pointer, never the enriched body. Capped at [pendingMax].
  static let pendingKey = "push.pending"
  static let pendingMax = 50

  static func appendPending(_ pointer: [String: String]) {
    guard let defaults else { return }
    var pending = (defaults.array(forKey: pendingKey) as? [[String: String]]) ?? []
    pending.append(pointer)
    if pending.count > pendingMax { pending.removeFirst(pending.count - pendingMax) }
    defaults.set(pending, forKey: pendingKey)
  }

  /// Everything queued, and the queue emptied, in one step.
  static func drainPending() -> [[String: String]] {
    guard let defaults else { return [] }
    let pending = (defaults.array(forKey: pendingKey) as? [[String: String]]) ?? []
    defaults.removeObject(forKey: pendingKey)
    return pending
  }

  /// The extension's breadcrumb file, `Library/Caches/push-extension.log` in
  /// the group container: one line per push with the verb, the artifact and
  /// `enriched|fallback (<reason>)`, capped at [breadcrumbLines] lines.
  ///
  /// An extension's `NSLog` is easy to lose (the device's syslog relay stalls,
  /// and the process is gone by the time anyone looks), while a file in the
  /// group container can be pulled with `devicectl device copy from
  /// --domain-type appGroupDataContainer`. The same logging rule as the
  /// console applies: never a token, a title, a body or a response.
  static let breadcrumbLines = 200

  static var breadcrumbURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
      .appendingPathComponent("Library/Caches/push-extension.log")
  }

  static func breadcrumb(_ line: String) {
    guard let url = breadcrumbURL else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    var lines = (try? String(contentsOf: url, encoding: .utf8))?
      .split(separator: "\n", omittingEmptySubsequences: true).map(String.init) ?? []
    lines.append("\(stamp) \(line)")
    if lines.count > breadcrumbLines { lines.removeFirst(lines.count - breadcrumbLines) }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
  }
}

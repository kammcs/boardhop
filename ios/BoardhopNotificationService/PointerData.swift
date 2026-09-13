import Foundation

/// Which fetch a pointer's verb asks for (research/14 §4.1's rows).
enum PointerFamily {
  case workItem
  case workItemComment
  case pullRequest
  case pullRequestComment
  case build
  case approval
  case none
}

/// The pointer as it arrives in the APNs payload, which is the same contract as
/// `lib/features/notifications/push_pointer.dart`,
/// `relay/lib/src/gateway/pointer.dart` and Android's `PointerData`.
///
/// Strings only, and they sit at the **top level of the payload beside `aps`**
/// (`ApnsSender.payload` spreads `pointer.toData()` there), which is also where
/// the Runner's notification-centre proxy reads them.
///
/// One difference from Android, and the reason for the three `fallback…`
/// initialiser arguments: FCM carries the fallback lines as data keys
/// (`fallbackTitle`, `fallbackBody`, `fallbackSubtitle`) because the Android
/// app posts the notification itself, while APNs carries them in `aps.alert`
/// because iOS presents it. The extension therefore takes them from the
/// notification content it was handed and falls back to the data keys, so the
/// same type serves a test fixture written in the FCM shape.
struct PointerData {

  init(
    data: [String: String],
    fallbackTitle: String? = nil,
    fallbackBody: String? = nil,
    fallbackSubtitle: String? = nil
  ) {
    self.data = data
    self.fallbackTitle = PointerData.nonEmpty(fallbackTitle) ?? PointerData.nonEmpty(data["fallbackTitle"])
    self.fallbackBody = PointerData.nonEmpty(fallbackBody) ?? PointerData.nonEmpty(data["fallbackBody"])
    self.fallbackSubtitle =
      PointerData.nonEmpty(fallbackSubtitle) ?? PointerData.nonEmpty(data["fallbackSubtitle"])
  }

  let data: [String: String]

  /// The alert's title, subtitle and body as the relay sent them: the line the
  /// user sees when enrichment does not happen.
  let fallbackTitle: String?
  let fallbackBody: String?
  let fallbackSubtitle: String?

  var org: String { str("org") ?? "" }
  var project: String { str("project") ?? "" }
  var artifactType: String { str("artifactType") ?? "" }
  var artifactId: String { str("artifactId") ?? "" }
  var eventType: String { str("eventType") ?? "" }
  var verb: String? { str("verb") }
  var actorId: String? { str("actorId") }
  var anchor: String? { str("anchor") }
  var sentAt: Date? { EnrichmentFormat.parseIso(str("sentAt")) }

  /// True when the required three fields are there (`PushPointer.tryFrom`).
  var isPointer: Bool { !org.isEmpty && !artifactType.isEmpty && !artifactId.isEmpty }

  /// research/14 §4.1: older than ten minutes → no fetch, fallback line.
  func isStale(at now: Date) -> Bool {
    guard let sentAt else { return false }
    return now.timeIntervalSince(sentAt) > 10 * 60
  }

  /// `comment:42` → `42` when [kind] matches.
  func anchorId(_ kind: String) -> String? {
    guard let anchor else { return nil }
    let prefix = "\(kind):"
    guard anchor.hasPrefix(prefix) else { return nil }
    let id = String(anchor.dropFirst(prefix.count))
    return id.isEmpty ? nil : id
  }

  var family: PointerFamily {
    switch artifactType {
    case "workItem":
      switch verb {
      case "commented", "replied", "mentioned": return .workItemComment
      case "assigned", "reassigned", "stateChanged", "edited", "created": return .workItem
      default: return .none
      }
    case "pullRequest":
      switch verb {
      case "commented", "replied", "mentioned": return .pullRequestComment
      case "reviewRequested", "voted", "prCompleted", "prAbandoned", "prPublished", "pushed",
        "mergeFailed":
        return .pullRequest
      default: return .none
      }
    case "build":
      switch verb {
      case "buildFailed", "buildPartial", "buildCanceled", "buildSucceeded", "buildFixed":
        return .build
      default: return .none
      }
    case "approval":
      switch verb {
      case "approvalPending", "approvalCompleted": return .approval
      default: return .none
      }
    default:
      return .none
    }
  }

  /// The pointer's string keys out of a notification's `userInfo`: everything
  /// beside `aps` whose value is a string. Anything else the payload carries is
  /// left alone, and `userInfo` itself is never modified — the Runner's
  /// notification proxy reads the same keys when the user taps.
  static func stringKeys(of userInfo: [AnyHashable: Any]) -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in userInfo {
      guard let key = key as? String, key != "aps", let value = value as? String else { continue }
      out[key] = value
    }
    return out
  }

  private func str(_ key: String) -> String? { PointerData.nonEmpty(data[key]) }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}

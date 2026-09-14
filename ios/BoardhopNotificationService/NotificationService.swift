import UserNotifications

/// Boardhop's iOS Notification Service Extension (research/14 §4.1, R2.7).
///
/// APNs sends `mutable-content: 1` and category `boardhop.pointer` on every
/// pointer (`relay/lib/src/gateway/apns.dart`), which wakes this process before
/// the notification is shown. The alert it arrives with is the relay's fallback
/// line — metadata only, never a comment or a build log — and the pointer's
/// keys sit at the top level of the payload beside `aps`.
///
/// What happens here is the iOS half of what `BoardhopMessagingService` does on
/// Android: fetch the artifact with **the user's own token**, inside an 8 s
/// budget, and replace the body with what actually happened. Anything at all
/// going wrong delivers the content unchanged, so a notification is never lost.
///
/// What is deliberately left alone: `userInfo` (the Runner's notification proxy
/// reads the pointer from it when the user taps, which is what routes to the
/// anchor), `threadIdentifier`, `categoryIdentifier`, the sound and the title.
///
/// **Logging rule (hard):** verb, artifact type and id, HTTP status and
/// `enriched|fallback`. Never a token, a title, a body or a response.
final class NotificationService: UNNotificationServiceExtension {

  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var content: UNMutableNotificationContent?
  private var pointer: PointerData?
  private var work: Task<Void, Never>?
  private var watchdog: Task<Void, Never>?
  private let lock = NSLock()
  private var delivered = false

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    content = mutable

    // The alert lines are the fallback: APNs carries them in `aps.alert`, not
    // as data keys the way FCM does.
    let pointer = PointerData(
      data: PointerData.stringKeys(of: request.content.userInfo),
      fallbackTitle: mutable.title,
      fallbackBody: mutable.body,
      fallbackSubtitle: mutable.subtitle)
    self.pointer = pointer
    NSLog(
      "%@: received verb=%@ artifact=%@/%@", pushLogTag, pointer.verb ?? "none",
      pointer.artifactType, pointer.artifactId)
    PushSharedDefaults.breadcrumb(
      "received verb=\(pointer.verb ?? "none") artifact=\(pointer.artifactType)/\(pointer.artifactId)")

    guard pointer.isPointer else {
      finish(nil, reason: "not a pointer")
      return
    }
    guard !pointer.isStale(at: Date()) else {
      // research/14 §4.1: a pointer older than ten minutes is not worth a
      // fetch; the line still shows.
      finish(nil, reason: "stale")
      return
    }
    guard pointer.family != .none else {
      finish(nil, reason: "nothing to fetch")
      return
    }
    guard let accountId = PushSharedDefaults.accountId(org: pointer.org) else {
      finish(nil, reason: "no registered account for this org")
      return
    }
    guard let config = MsalConfig.load() else {
      finish(nil, reason: "no MSAL configuration in the app group")
      return
    }

    let deadline = Deadline(seconds: PushEnricher.budget)
    // Belt and braces around the one call whose timeout is not ours: MSAL's
    // silent acquisition. Every fetch already caps itself at what is left.
    watchdog = Task { [weak self] in
      let seconds = max(0, deadline.remaining)
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      self?.finish(nil, reason: "budget")
    }
    work = Task { [weak self] in
      guard
        let token = await PushTokens.token(
          org: pointer.org, accountId: accountId, config: config)
      else {
        self?.finish(nil, reason: "no token")
        return
      }
      let enrichment = await PushEnricher(http: AdoRest()).enrich(
        pointer, token: token, deadline: deadline)
      self?.finish(enrichment, reason: enrichment == nil ? "fetch" : nil)
    }
  }

  /// iOS is about to show the notification whatever state we are in: hand back
  /// the best content there is, which is the fallback line unless the fetch
  /// already came home.
  override func serviceExtensionTimeWillExpire() {
    finish(nil, reason: "expired")
  }

  /// Delivers once. [enrichment] nil means the fallback line, and [reason] says
  /// why for the log; a successful enrichment passes none.
  private func finish(_ enrichment: PushEnricher.Enrichment?, reason: String?) {
    lock.lock()
    if delivered {
      lock.unlock()
      return
    }
    delivered = true
    let handler = contentHandler
    let content = self.content
    let pointer = self.pointer
    lock.unlock()

    work?.cancel()
    watchdog?.cancel()

    if let enrichment, let content {
      content.body = enrichment.body
      // Only a file thread has a location to show; anything else keeps the
      // project line the relay sent.
      if let subtitle = enrichment.subtitle { content.subtitle = subtitle }
    }
    let outcome = enrichment == nil ? "fallback (\(reason ?? "unknown"))" : "enriched"
    // Whatever was shown, Dart has not seen this pointer: queue it for the
    // app's next drain so the feed gets the row and the poll stays quiet.
    if let pointer, pointer.isPointer { PushSharedDefaults.appendPending(pointer.data) }
    NSLog(
      "%@: verb=%@ artifact=%@/%@ → %@", pushLogTag, pointer?.verb ?? "none",
      pointer?.artifactType ?? "none", pointer?.artifactId ?? "none", outcome)
    PushSharedDefaults.breadcrumb(
      "verb=\(pointer?.verb ?? "none") artifact=\(pointer?.artifactType ?? "none")/\(pointer?.artifactId ?? "none") → \(outcome)")
    handler?(content ?? UNNotificationContent())
  }
}

import Foundation

/// The one log tag the whole enrichment path uses.
///
/// **Logging rule (hard):** the verb, the artifact, the HTTP status and
/// `enriched|fallback`. Never a token, a title, a comment or a response body.
let pushLogTag = "Boardhop push"

/// The extension's own time budget, as a monotonic instant.
///
/// `ProcessInfo.systemUptime` is the closest thing iOS has to Android's
/// `SystemClock.elapsedRealtime()`: it cannot be moved by a clock change, and
/// an 8 s budget is meaningless if it can.
struct Deadline {
  init(seconds: TimeInterval) {
    self.at = ProcessInfo.processInfo.systemUptime + seconds
  }

  /// For tests, which need a deadline that is already past.
  init(uptime: TimeInterval) { self.at = uptime }

  let at: TimeInterval

  var remaining: TimeInterval { at - ProcessInfo.processInfo.systemUptime }
  var isPast: Bool { remaining <= 0 }
}

/// One Azure DevOps GET. Stubbed in tests; [AdoRest] is the live one.
protocol AdoFetching {
  /// The decoded JSON object, or nil on any non-2xx, any parse failure, or once
  /// [deadline] has passed.
  func get(_ url: String, token: String, deadline: Deadline) async -> [String: Any]?
}

/// The smallest possible Azure DevOps read: a GET with the user's bearer token,
/// a 5 s per-call timeout and no retry, mirroring `lib/core/http/ado_client.dart`
/// and Android's `AdoRest` (same `Accept` and `X-TFS-FedAuthRedirect: Suppress`,
/// so a sign-in redirect comes back as a 401 rather than as HTML).
///
/// Nothing is cached: the session is ephemeral with its cache removed, because
/// a notification extension has no business leaving Azure DevOps responses on
/// disk.
final class AdoRest: NSObject, AdoFetching, URLSessionTaskDelegate {

  init(perCall: TimeInterval = 5) {
    self.perCall = perCall
    super.init()
  }

  private let perCall: TimeInterval

  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  func get(_ url: String, token: String, deadline: Deadline) async -> [String: Any]? {
    let remaining = deadline.remaining
    if remaining <= 0 {
      NSLog("%@: fetch skipped, past the deadline", pushLogTag)
      return nil
    }
    guard let target = URL(string: url) else { return nil }
    var request = URLRequest(url: target)
    request.httpMethod = "GET"
    request.timeoutInterval = min(perCall, remaining)
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Suppress", forHTTPHeaderField: "X-TFS-FedAuthRedirect")
    do {
      let (data, response) = try await session.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(status) else {
        NSLog("%@: fetch http=%d", pushLogTag, status)
        return nil
      }
      NSLog("%@: fetch http=%d bytes=%d", pushLogTag, status, data.count)
      return JSONSerialization.decodedObject(data)
    } catch {
      NSLog("%@: fetch failed (%@)", pushLogTag, String(describing: type(of: error)))
      return nil
    }
  }

  /// No redirects: a 302 to a sign-in page must read as a failure, never as a
  /// second request carrying the bearer token somewhere else.
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

extension JSONSerialization {
  /// A JSON object, or nil when the bytes are not one.
  static func decodedObject(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}

/// Percent-encodes one path segment (an org, a project, an id), the way
/// Android's `Uri.encode` does for the same URLs.
func urlSegment(_ value: String) -> String {
  var allowed = CharacterSet.alphanumerics
  allowed.insert(charactersIn: "-._~")
  return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

/// JSON helpers that answer nil rather than an empty string, matching
/// `optStringOrNull` / `optIntOrNull` on Android.
extension Dictionary where Key == String, Value == Any {
  /// A string field, **coercing a JSON number** the way Android's
  /// `JSONObject.optString` does: a comment's `id` and a record's `order` come
  /// back as numbers, and the anchor is compared against them as text.
  func string(_ key: String) -> String? {
    if let value = self[key] as? String { return value.isEmpty ? nil : value }
    if let value = self[key] as? NSNumber { return value.stringValue }
    return nil
  }

  func int(_ key: String) -> Int? {
    if let value = self[key] as? Int { return value }
    if let value = self[key] as? NSNumber { return value.intValue }
    if let value = self[key] as? String { return Int(value) }
    return nil
  }

  func object(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }

  func array(_ key: String) -> [[String: Any]]? {
    (self[key] as? [Any])?.compactMap { $0 as? [String: Any] }
  }
}

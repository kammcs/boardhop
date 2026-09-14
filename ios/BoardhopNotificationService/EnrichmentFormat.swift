import Foundation

/// Every pure function the iOS enrichment path needs, and every English string
/// it can show (research/14 §4.1; R2.7).
///
/// The Swift twin of `android/app/src/main/kotlin/com/kammcs/boardhop/
/// EnrichmentFormat.kt`, function for function, so the two platforms word a
/// notification the same way. It is deliberately free of UserNotifications, of
/// MSAL and of the network: given decoded JSON values it returns the line to
/// display, which is what lets `RunnerTests` compile it and cover it without a
/// device (`EnrichmentFormatTests.swift`).
///
/// **No content ever reaches a log from here.** Callers log the verb, the
/// artifact, the HTTP status and `enriched|fallback`, nothing else.
///
/// Two deliberate omissions against the Kotlin: `dartStringHash`,
/// `notificationId` and `summaryId` are not ported. iOS presents the pushed
/// notification itself and the extension only mutates its content, so there is
/// no notification id to reproduce and no group summary to post.
enum EnrichmentFormat {

  /// research/14 §4.1: at most 1,000 characters of comment in the body.
  static let maxBody = 1000

  /// The one separator the notification bodies use.
  static let sep = " · "

  /// The arrow between a pull request's source and target branch.
  static let branchArrow = " → "

  /// The separator between a stage/job and the task that failed.
  static let pathArrow = " › "

  // -------------------------------------------------------------- html

  private static let mention = try? NSRegularExpression(
    pattern: "<a\\b[^>]*data-vss-mention[^>]*>(.*?)</a>",
    options: [.caseInsensitive, .dotMatchesLineSeparators])
  /// The markdown wire form of a person mention, `@<{identityGuid}>` (spike
  /// w30). A pull request comment has no rendered form at all and a work
  /// item's `System.History` stores the comment's raw text, so this is the
  /// shape a mention arrives in on both of the paths this extension enriches.
  /// Replaced before the tag pass, or `<{guid}>` would look like a tag and
  /// leave a bare `@` behind.
  private static let angleMention = try? NSRegularExpression(
    pattern: "@<([0-9a-fA-F-]{36})>")

  /// A mention this extension cannot name. The Dart twin
  /// (`lib/core/text/plain_text.dart`) can be given a resolver and print the
  /// display name; the notification path has no identity cache and no time to
  /// fetch one, so it always lands here — which is exactly what the Dart side
  /// does when a GUID resolves to nobody (research/16 M9).
  static let unknownMention = "@someone"

  private static let blockEnd = try? NSRegularExpression(
    pattern: "</(p|div|li|ul|ol|tr|h[1-6]|blockquote|pre)\\s*>|<br\\s*/?>",
    options: [.caseInsensitive])
  private static let tag = try? NSRegularExpression(pattern: "<[^>]*>")
  private static let manyNewlines = try? NSRegularExpression(pattern: "\\n{3,}")
  /// Space, tab and the non-breaking space `&nbsp;` decodes to.
  private static let spaces = try? NSRegularExpression(pattern: "[ \\t\u{00a0}]{2,}")

  /// Server-rendered comment HTML as the plain text a notification can show.
  ///
  /// `data-vss-mention` anchors become `@Name` (Azure DevOps renders the
  /// display name inside the anchor, sometimes already with the `@`), a
  /// markdown `@<{guid}>` mention becomes `unknownMention`, block ends become
  /// newlines, every other tag goes, entities are decoded.
  static func plainText(_ html: String?) -> String {
    guard let html, !html.isEmpty else { return "" }
    var text = replaceMatches(mention, in: html) { match, source in
      let inner = group(match, 1, source)
      let name = decodeEntities(strip(tag, from: inner)).trimmingCharacters(
        in: .whitespacesAndNewlines)
      if name.isEmpty { return "" }
      return name.hasPrefix("@") ? name : "@\(name)"
    }
    text = replaceMatches(angleMention, in: text) { _, _ in unknownMention }
    text = replaceMatches(blockEnd, in: text) { _, _ in "\n" }
    text = strip(tag, from: text)
    text = decodeEntities(text)
    text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n")
    text = replaceMatches(manyNewlines, in: text) { _, _ in "\n\n" }
    text = replaceMatches(spaces, in: text) { _, _ in " " }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let numericEntity = try? NSRegularExpression(
    pattern: "&#(x?)([0-9a-fA-F]+);")

  static func decodeEntities(_ value: String) -> String {
    guard value.contains("&") else { return value }
    var text = replaceMatches(numericEntity, in: value) { match, source in
      let radix = group(match, 1, source).isEmpty ? 10 : 16
      let digits = group(match, 2, source)
      guard let code = UInt32(digits, radix: radix), let scalar = Unicode.Scalar(code) else {
        return group(match, 0, source)
      }
      return String(Character(scalar))
    }
    for (entity, replacement) in entities {
      text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return text
  }

  private static let entities: [(String, String)] = [
    ("&nbsp;", " "),
    ("&lt;", "<"),
    ("&gt;", ">"),
    ("&quot;", "\""),
    ("&apos;", "'"),
    ("&hellip;", "…"),
    ("&mdash;", "—"),
    ("&ndash;", "–"),
    // Last: an escaped ampersand must not re-open another entity.
    ("&amp;", "&"),
  ]

  /// Cuts a body to [maxBody] on a word boundary where there is one.
  static func clamp(_ value: String, max: Int = maxBody) -> String {
    if value.count <= max { return value }
    let cut = String(value.prefix(max - 1))
    var kept = cut
    if let space = cut.lastIndex(of: " ") {
      let head = String(cut[cut.startIndex..<space])
      if head.count > max / 2 { kept = head }
    }
    return trimTrailing(kept) + "…"
  }

  // ------------------------------------------------------------ pieces

  /// `refs/heads/feature/x` → `feature/x`; anything else unchanged.
  static func shortBranch(_ ref: String?) -> String? {
    let value = ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if value.isEmpty { return nil }
    if value.hasPrefix("refs/heads/") { return String(value.dropFirst("refs/heads/".count)) }
    return value
  }

  /// Joins the non-empty parts with [sep].
  static func join(_ parts: String?...) -> String? { join(parts) }

  static func join(_ parts: [String?]) -> String? {
    let kept = parts.compactMap { part -> String? in
      let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return trimmed.isEmpty ? nil : trimmed
    }
    return kept.isEmpty ? nil : kept.joined(separator: sep)
  }

  // ------------------------------------------------------------- bodies

  /// work item `assigned`/`stateChanged`/…: the fallback line plus the type
  /// and the state — "Ada Example assigned you · User Story · Active".
  static func workItemBody(_ fallbackBody: String?, type: String?, state: String?) -> String? {
    join(fallbackBody, type, state)
  }

  /// PR `reviewRequested`/`voted`/…: the fallback line plus the repository and
  /// the branches — "Ada Example asked you to review !8334 · boardhop ·
  /// feature/x → main".
  ///
  /// The vote label is **not** appended: the relay's fallback line already
  /// carries it (`verbPhrase` → `_votePhrase`), so repeating it would read
  /// twice.
  static func pullRequestBody(
    _ fallbackBody: String?, repository: String?, source: String?, target: String?
  ) -> String? {
    let from = shortBranch(source)
    let to = shortBranch(target)
    let branches: String?
    if let from, let to {
      branches = from + branchArrow + to
    } else {
      branches = from ?? to
    }
    return join(fallbackBody, repository, branches)
  }

  /// A file thread's sub-text: `lib/main.dart:38`.
  static func threadLocation(filePath: String?, line: Int?) -> String? {
    var path = filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if path.hasPrefix("/") { path = String(path.dropFirst()) }
    if path.isEmpty { return nil }
    if let line, line > 0 { return "\(path):\(line)" }
    return path
  }

  /// A failed run: "Deploy › Run tests: 3 tests failed", from the first failed
  /// task record's path and its first issue message.
  static func buildFailureBody(_ fallbackBody: String?, path: String?, issue: String?) -> String? {
    let location = nonEmpty(path)
    let what: String? = {
      guard let raw = nonEmpty(issue) else { return nil }
      let firstLine = raw.split(separator: "\n", omittingEmptySubsequences: false).first
      return nonEmpty(firstLine.map(String.init) ?? raw)
    }()
    let detail: String?
    if let location, let what {
      detail = "\(location): \(what)"
    } else {
      detail = location ?? what
    }
    return join(fallbackBody, detail)
  }

  /// A run that finished well: "… · Succeeded in 1m 20s".
  static func buildSuccessBody(_ fallbackBody: String?, durationMillis: Int64?) -> String? {
    join(fallbackBody, durationMillis.map { "Succeeded in \(durationLabel($0))" })
  }

  /// `90s` → `1m 30s`; `3720s` → `1h 2m`.
  static func durationLabel(_ millis: Int64) -> String {
    let seconds = Swift.max(0, millis / 1000)
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let rest = seconds % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m \(rest)s" }
    return "\(rest)s"
  }

  /// An approval: the pipeline author's instructions and the run name.
  static func approvalBody(_ fallbackBody: String?, instructions: String?, runName: String?)
    -> String?
  {
    join(fallbackBody, nonEmpty(plainText(instructions)), runName)
  }

  // ------------------------------------------------------------- utils

  /// ISO-8601 with an optional fractional part, as Azure DevOps writes it and
  /// as `DateTime.toIso8601String()` does on the relay.
  ///
  /// The fraction is cut rather than parsed: Azure DevOps writes seven digits
  /// where `ISO8601DateFormatter` expects three, and a pointer's age is only
  /// ever compared against ten minutes.
  static func parseIso(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let trimmed = replaceMatches(fraction, in: value) { _, _ in "" }
    return isoFormatter.date(from: trimmed)
  }

  private static let fraction = try? NSRegularExpression(pattern: "\\.\\d+")

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func trimTrailing(_ value: String) -> String {
    var out = value
    while let last = out.last, last.isWhitespace { out.removeLast() }
    return out
  }

  private static func strip(_ regex: NSRegularExpression?, from value: String) -> String {
    replaceMatches(regex, in: value) { _, _ in "" }
  }

  /// One group of a match, as a Swift string.
  private static func group(_ match: NSTextCheckingResult, _ index: Int, _ source: String) -> String
  {
    let range = match.range(at: index)
    guard range.location != NSNotFound else { return "" }
    return (source as NSString).substring(with: range)
  }

  /// Replaces every match through a closure, which `NSRegularExpression`'s own
  /// template substitution cannot do. Matches are rewritten back to front so
  /// the ranges still in play stay valid.
  private static func replaceMatches(
    _ regex: NSRegularExpression?, in value: String,
    transform: (NSTextCheckingResult, String) -> String
  ) -> String {
    guard let regex else { return value }
    let full = NSRange(location: 0, length: (value as NSString).length)
    let matches = regex.matches(in: value, range: full)
    if matches.isEmpty { return value }
    var out = value
    for match in matches.reversed() {
      let replacement = transform(match, value)
      out = (out as NSString).replacingCharacters(in: match.range, with: replacement)
    }
    return out
  }
}

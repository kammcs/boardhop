import Foundation

/// The iOS half of research/14 §4.1: one or two GETs with **the user's own
/// token**, inside an 8 s budget, turning the relay's pointer line into a
/// notification that says what actually happened.
///
/// A line-for-line port of Android's `PushEnricher.kt` — the same URLs, the
/// same api-versions, the same picks — so the two platforms show the same
/// words for the same event. It knows nothing about UserNotifications or MSAL,
/// which is what lets `RunnerTests` drive it with a stubbed [AdoFetching].
///
/// Nothing here is retried and nothing here is cached: a failure of any kind —
/// offline, 401, 404, malformed JSON, the deadline — returns nil and the caller
/// delivers the relay's fallback line, which is always shown.
struct PushEnricher {

  init(http: AdoFetching) { self.http = http }

  private let http: AdoFetching

  /// research/14 §4.1: the extension caps its own work at 8 s.
  static let budget: TimeInterval = 8

  /// What one successful enrichment replaces in the notification.
  struct Enrichment {
    let body: String
    let subtitle: String?

    init(_ body: String, subtitle: String? = nil) {
      self.body = body
      self.subtitle = subtitle
    }
  }

  static func orgBase(_ org: String) -> String { "https://dev.azure.com/\(urlSegment(org))" }

  /// Enriches [pointer] or returns nil.
  func enrich(_ pointer: PointerData, token: String, deadline: Deadline) async -> Enrichment? {
    switch pointer.family {
    case .workItem: return await workItem(pointer, token, deadline)
    case .workItemComment: return await workItemComment(pointer, token, deadline)
    case .pullRequest: return await pullRequest(pointer, token, deadline)
    case .pullRequestComment: return await pullRequestComment(pointer, token, deadline)
    case .build: return await build(pointer, token, deadline)
    case .approval: return await approval(pointer, token, deadline)
    case .none: return nil
    }
  }

  // ------------------------------------------------------------ work items

  private func workItem(_ p: PointerData, _ token: String, _ deadline: Deadline) async
    -> Enrichment?
  {
    guard let item = await http.get(workItemUrl(p), token: token, deadline: deadline),
      let fields = item.object("fields"),
      let body = EnrichmentFormat.workItemBody(
        p.fallbackBody, type: fields.string("System.WorkItemType"),
        state: fields.string("System.State"))
    else { return nil }
    return Enrichment(body)
  }

  private func workItemComment(_ p: PointerData, _ token: String, _ deadline: Deadline) async
    -> Enrichment?
  {
    if p.project.isEmpty { return nil }
    let url =
      "\(Self.orgBase(p.org))/\(urlSegment(p.project))/_apis/wit/workItems/\(urlSegment(p.artifactId))/comments"
      + "?api-version=7.1-preview.4&$expand=renderedText&order=desc&$top=50"
    guard let json = await http.get(url, token: token, deadline: deadline),
      let comments = json.array("comments")
    else { return nil }
    let wanted = p.anchorId("comment")
    let chosen = comments.first { $0.string("id") == wanted } ?? comments.first
    guard let chosen else { return nil }
    let text = EnrichmentFormat.plainText(
      chosen.string("renderedText") ?? chosen.string("text"))
    if text.isEmpty { return nil }
    return Enrichment(EnrichmentFormat.clamp(text))
  }

  private func workItemUrl(_ p: PointerData) -> String {
    "\(Self.orgBase(p.org))/_apis/wit/workitems/\(urlSegment(p.artifactId))?api-version=7.1"
  }

  // --------------------------------------------------------- pull requests

  private func pullRequest(_ p: PointerData, _ token: String, _ deadline: Deadline) async
    -> Enrichment?
  {
    guard let pr = await http.get(pullRequestUrl(p), token: token, deadline: deadline),
      let body = EnrichmentFormat.pullRequestBody(
        p.fallbackBody, repository: pr.object("repository")?.string("name"),
        source: pr.string("sourceRefName"), target: pr.string("targetRefName"))
    else { return nil }
    return Enrichment(body)
  }

  private func pullRequestComment(_ p: PointerData, _ token: String, _ deadline: Deadline) async
    -> Enrichment?
  {
    guard let threadId = p.anchorId("thread"),
      let pr = await http.get(pullRequestUrl(p), token: token, deadline: deadline),
      let repository = pr.object("repository"),
      let repositoryId = repository.string("id"),
      let project = repository.object("project")?.string("id")
        ?? (p.project.isEmpty ? nil : p.project)
    else { return nil }
    let url =
      "\(Self.orgBase(p.org))/\(urlSegment(project))/_apis/git/repositories/\(urlSegment(repositoryId))"
      + "/pullRequests/\(urlSegment(p.artifactId))/threads/\(urlSegment(threadId))?api-version=7.1"
    guard let thread = await http.get(url, token: token, deadline: deadline),
      let comments = thread.array("comments")
    else { return nil }
    let byActor = p.actorId.flatMap { actor in
      comments.last { $0.object("author")?.string("id") == actor }
    }
    guard let chosen = byActor ?? comments.last(where: { $0.string("commentType") != "system" })
    else { return nil }
    let text = EnrichmentFormat.plainText(chosen.string("content"))
    if text.isEmpty { return nil }
    let context = thread.object("threadContext")
    let location = EnrichmentFormat.threadLocation(
      filePath: context?.string("filePath"),
      line: context?.object("rightFileStart")?.int("line")
        ?? context?.object("leftFileStart")?.int("line"))
    return Enrichment(EnrichmentFormat.clamp(text), subtitle: location)
  }

  private func pullRequestUrl(_ p: PointerData) -> String {
    "\(Self.orgBase(p.org))/_apis/git/pullrequests/\(urlSegment(p.artifactId))?api-version=7.1"
  }

  // ---------------------------------------------------------------- builds

  private func build(_ p: PointerData, _ token: String, _ deadline: Deadline) async -> Enrichment? {
    if p.project.isEmpty { return nil }
    let base =
      "\(Self.orgBase(p.org))/\(urlSegment(p.project))/_apis/build/builds/\(urlSegment(p.artifactId))"
    guard let run = await http.get("\(base)?api-version=7.1", token: token, deadline: deadline)
    else { return nil }
    if run.string("result")?.lowercased() == "succeeded" {
      let duration = Self.duration(from: run.string("startTime"), to: run.string("finishTime"))
      guard let body = EnrichmentFormat.buildSuccessBody(p.fallbackBody, durationMillis: duration)
      else { return nil }
      return Enrichment(body)
    }
    guard
      let timeline = await http.get(
        "\(base)/timeline?api-version=7.1", token: token, deadline: deadline),
      let records = timeline.array("records"),
      let failure = Self.firstFailure(records),
      let body = EnrichmentFormat.buildFailureBody(
        p.fallbackBody, path: failure.path, issue: failure.issue)
    else { return nil }
    return Enrichment(body)
  }

  /// The first failed **task** record, as `("Deploy › Run tests", "3 tests
  /// failed")`: its path through the parent records and its first issue's
  /// message. Ordered by `startTime` then by the record's `order`, which is how
  /// the web console reads a timeline.
  static func firstFailure(_ records: [[String: Any]]) -> (path: String, issue: String?)? {
    var byId: [String: [String: Any]] = [:]
    for record in records {
      if let id = record.string("id") { byId[id] = record }
    }
    let failed =
      records
      .filter { $0.string("result")?.lowercased() == "failed" }
      .filter { $0.string("type")?.lowercased() == "task" }
      .sorted { left, right in
        let leftStart = left.string("startTime") ?? ""
        let rightStart = right.string("startTime") ?? ""
        if leftStart != rightStart { return leftStart < rightStart }
        return (left.int("order") ?? 0) < (right.int("order") ?? 0)
      }
      .first
    guard let failed else { return nil }

    var names: [String] = []
    var node: [String: Any]? = failed
    var hops = 0
    while let current = node, hops < 6 {
      if let name = current.string("name") { names.insert(name, at: 0) }
      node = current.string("parentId").flatMap { byId[$0] }
      hops += 1
    }
    let path = names.suffix(2).joined(separator: EnrichmentFormat.pathArrow)
    let issue = failed.array("issues")?.first?.string("message")
    return (path, issue)
  }

  // ------------------------------------------------------------- approvals

  private func approval(_ p: PointerData, _ token: String, _ deadline: Deadline) async
    -> Enrichment?
  {
    if p.project.isEmpty { return nil }
    let url =
      "\(Self.orgBase(p.org))/\(urlSegment(p.project))/_apis/pipelines/approvals/\(urlSegment(p.artifactId))"
      + "?$expand=steps&api-version=7.1-preview.1"
    guard let json = await http.get(url, token: token, deadline: deadline),
      let body = EnrichmentFormat.approvalBody(
        p.fallbackBody, instructions: json.string("instructions"),
        runName: json.object("pipeline")?.object("owner")?.string("name"))
    else { return nil }
    return Enrichment(body)
  }

  // ----------------------------------------------------------------- utils

  static func duration(from start: String?, to finish: String?) -> Int64? {
    guard let from = EnrichmentFormat.parseIso(start),
      let to = EnrichmentFormat.parseIso(finish)
    else { return nil }
    let millis = Int64(to.timeIntervalSince(from) * 1000)
    return millis >= 0 ? millis : nil
  }
}

import XCTest

/// One case per verb family through [PushEnricher] with a stubbed fetcher and
/// canned JSON shaped like the real responses (research/spikes/results, R2.0).
///
/// Nothing here touches the network, MSAL or UserNotifications; the extension's
/// own `didReceive` is the only part left for the device.
final class PushEnricherTests: XCTestCase {

  /// Answers the first canned body whose pattern the URL contains, and records
  /// every URL asked for.
  final class StubFetcher: AdoFetching {
    init(_ canned: [(String, [String: Any])]) { self.canned = canned }

    let canned: [(String, [String: Any])]
    private(set) var urls: [String] = []

    func get(_ url: String, token: String, deadline: Deadline) async -> [String: Any]? {
      urls.append(url)
      for (pattern, body) in canned where url.contains(pattern) { return body }
      return nil
    }
  }

  private let deadline = Deadline(seconds: 30)

  private func pointer(
    _ pairs: [String: String], fallbackBody: String? = nil, fallbackSubtitle: String? = nil
  ) -> PointerData {
    var data = ["org": "puremedia", "project": "DevOps Mobile App"]
    data.merge(pairs) { _, new in new }
    return PointerData(
      data: data, fallbackTitle: "#15545 · Fix the snackbar", fallbackBody: fallbackBody,
      fallbackSubtitle: fallbackSubtitle)
  }

  // ------------------------------------------------------------- work items

  func testWorkItemGainsTypeAndState() async {
    let http = StubFetcher([
      (
        "/_apis/wit/workitems/15545",
        ["fields": ["System.WorkItemType": "User Story", "System.State": "Active"]]
      )
    ])
    let p = pointer(
      ["artifactType": "workItem", "artifactId": "15545", "verb": "assigned"],
      fallbackBody: "Kelly Kamm assigned you")
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertEqual(enriched?.body, "Kelly Kamm assigned you · User Story · Active")
    XCTAssertEqual(http.urls.count, 1)
    XCTAssertTrue(http.urls[0].hasPrefix("https://dev.azure.com/puremedia/_apis/wit/workitems/"))
    XCTAssertTrue(http.urls[0].hasSuffix("api-version=7.1"))
  }

  func testWorkItemCommentPicksTheAnchoredComment() async {
    let http = StubFetcher([
      (
        "/comments?",
        [
          "comments": [
            ["id": 41, "renderedText": "<p>the older one</p>"],
            ["id": 42, "renderedText": "<p>Looks good &amp; shipped</p>"],
          ]
        ]
      )
    ])
    let p = pointer([
      "artifactType": "workItem", "artifactId": "15545", "verb": "commented",
      "anchor": "comment:42",
    ])
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    // The id comes back as a JSON number and the anchor is text; they still
    // have to match.
    XCTAssertEqual(enriched?.body, "Looks good & shipped")
    XCTAssertTrue(http.urls[0].contains("$expand=renderedText"))
  }

  func testWorkItemCommentFallsBackToTheNewestComment() async {
    let http = StubFetcher([
      ("/comments?", ["comments": [["id": 99, "text": "newest first"]]])
    ])
    let p = pointer([
      "artifactType": "workItem", "artifactId": "15545", "verb": "mentioned",
      "anchor": "comment:42",
    ])
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertEqual(enriched?.body, "newest first")
  }

  // ---------------------------------------------------------- pull requests

  func testPullRequestGainsRepositoryAndBranches() async {
    let http = StubFetcher([
      (
        "/_apis/git/pullrequests/8348",
        [
          "repository": ["name": "boardhop", "id": "repo-guid"],
          "sourceRefName": "refs/heads/feature/x", "targetRefName": "refs/heads/main",
        ]
      )
    ])
    let p = pointer(
      ["artifactType": "pullRequest", "artifactId": "8348", "verb": "reviewRequested"],
      fallbackBody: "Ada Example asked you to review !8348")
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertEqual(
      enriched?.body, "Ada Example asked you to review !8348 · boardhop · feature/x → main")
  }

  func testPullRequestCommentTakesTheActorsCommentAndTheFileLocation() async {
    let http = StubFetcher([
      (
        "/_apis/git/pullrequests/8348",
        [
          "repository": [
            "name": "boardhop", "id": "repo-guid", "project": ["id": "project-guid"],
          ]
        ]
      ),
      (
        "/threads/4821",
        [
          "comments": [
            ["author": ["id": "someone-else"], "content": "first", "commentType": "text"],
            ["author": ["id": "actor-guid"], "content": "<p>Please rename this</p>",
             "commentType": "text"],
          ],
          "threadContext": [
            "filePath": "/lib/main.dart", "rightFileStart": ["line": 38],
          ],
        ]
      ),
    ])
    let p = pointer([
      "artifactType": "pullRequest", "artifactId": "8348", "verb": "replied",
      "anchor": "thread:4821", "actorId": "actor-guid",
    ])
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertEqual(enriched?.body, "Please rename this")
    XCTAssertEqual(enriched?.subtitle, "lib/main.dart:38")
    XCTAssertEqual(http.urls.count, 2)
    XCTAssertTrue(http.urls[1].contains("/repositories/repo-guid/pullRequests/8348/threads/4821"))
  }

  func testPullRequestCommentWithoutAThreadAnchorDoesNotFetch() async {
    let http = StubFetcher([])
    let p = pointer(["artifactType": "pullRequest", "artifactId": "8348", "verb": "commented"])
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertNil(enriched)
    XCTAssertTrue(http.urls.isEmpty)
  }

  // ----------------------------------------------------------------- builds

  func testFailedBuildNamesTheFirstFailedTaskAndItsIssue() async {
    let http = StubFetcher([
      ("/timeline?", ["records": timelineRecords]),
      ("/_apis/build/builds/20163", ["result": "failed"]),
    ])
    let p = pointer(
      ["artifactType": "build", "artifactId": "20163", "verb": "buildFailed"],
      fallbackBody: "Kelly Kamm queued a build that failed")
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    // The last two names on the way up — the job and the task — and the first
    // issue's first line; the earlier succeeded task and the later failed one
    // are both passed over.
    XCTAssertEqual(
      enriched?.body,
      "Kelly Kamm queued a build that failed · Agent job 1 › Fail on purpose: "
        + "Bash exited with code '1'.")
  }

  func testSucceededBuildReportsItsDuration() async {
    let http = StubFetcher([
      (
        "/_apis/build/builds/20164",
        [
          "result": "succeeded", "startTime": "2026-09-13T12:00:00.0000000Z",
          "finishTime": "2026-09-13T12:03:41.0000000Z",
        ]
      )
    ])
    let p = pointer(
      ["artifactType": "build", "artifactId": "20164", "verb": "buildFixed"],
      fallbackBody: "Kelly Kamm queued a build that is fixed")
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertEqual(
      enriched?.body, "Kelly Kamm queued a build that is fixed · Succeeded in 3m 41s")
    // A run that finished well costs one call, not two: no timeline is read.
    XCTAssertEqual(http.urls.count, 1)
  }

  /// Shaped like a real timeline: the stage and job wrap the tasks, one task
  /// succeeded before the one that failed, and the job's own failure must not
  /// be picked over the task's.
  private var timelineRecords: [[String: Any]] {
    [
      ["id": "stage", "type": "Stage", "name": "Build", "result": "failed"],
      ["id": "job", "type": "Job", "name": "Agent job 1", "parentId": "stage", "result": "failed"],
      [
        "id": "task-1", "type": "Task", "name": "Checkout", "parentId": "job",
        "result": "succeeded", "order": 1, "startTime": "2026-09-13T12:00:01Z",
      ],
      [
        "id": "task-2", "type": "Task", "name": "Fail on purpose", "parentId": "job",
        "result": "failed", "order": 2, "startTime": "2026-09-13T12:00:02Z",
        "issues": [["type": "error", "message": "Bash exited with code '1'."]],
      ],
      [
        "id": "task-3", "type": "Task", "name": "Later failure", "parentId": "job",
        "result": "failed", "order": 3, "startTime": "2026-09-13T12:00:09Z",
      ],
    ]
  }

  // -------------------------------------------------------------- approvals

  func testApprovalCarriesTheInstructionsAndTheRunName() async {
    let http = StubFetcher([
      (
        "/_apis/pipelines/approvals/",
        [
          "instructions": "Boardhop approval test: approve from the app.",
          "pipeline": ["owner": ["name": "20260913.3"]],
        ]
      )
    ])
    let p = pointer(
      ["artifactType": "approval", "artifactId": "appr-guid", "verb": "approvalPending"],
      fallbackBody: "Needs your approval")
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertEqual(
      enriched?.body,
      "Needs your approval · Boardhop approval test: approve from the app. · 20260913.3")
    XCTAssertTrue(http.urls[0].contains("$expand=steps"))
  }

  // ------------------------------------------------------------- the guards

  func testAFetchThatFailsEnrichesNothing() async {
    let http = StubFetcher([])
    let p = pointer(["artifactType": "workItem", "artifactId": "15545", "verb": "assigned"])
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertNil(enriched)
  }

  func testAVerbWithNothingToFetchIsNotFetched() async {
    let http = StubFetcher([])
    let p = pointer(["artifactType": "workItem", "artifactId": "15545", "verb": "somethingNew"])
    let enriched = await PushEnricher(http: http).enrich(p, token: "t", deadline: deadline)
    XCTAssertNil(enriched)
    XCTAssertTrue(http.urls.isEmpty)
  }

  func testAPastDeadlineStopsTheLiveFetcherBeforeItAsks() async {
    // The live one, not the stub: this is the check that keeps the extension
    // inside its 8 s.
    let enriched = await PushEnricher(http: AdoRest()).enrich(
      pointer(["artifactType": "workItem", "artifactId": "15545", "verb": "assigned"]),
      token: "t", deadline: Deadline(uptime: 0))
    XCTAssertNil(enriched)
  }

  func testOrgAndProjectArePercentEncoded() async {
    let http = StubFetcher([])
    var data = ["artifactType": "build", "artifactId": "1", "verb": "buildFailed"]
    data["org"] = "pure media"
    data["project"] = "DevOps Mobile App"
    _ = await PushEnricher(http: http).enrich(
      PointerData(data: data), token: "t", deadline: deadline)
    XCTAssertEqual(
      http.urls.first,
      "https://dev.azure.com/pure%20media/DevOps%20Mobile%20App/_apis/build/builds/1?api-version=7.1"
    )
  }
}

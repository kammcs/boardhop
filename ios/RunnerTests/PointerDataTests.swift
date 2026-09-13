import XCTest

/// The pointer contract as the extension reads it (research/14 §3.2, §4.1).
final class PointerDataTests: XCTestCase {

  private func pointer(_ pairs: [String: String]) -> PointerData {
    var data = ["org": "puremedia", "artifactType": "workItem", "artifactId": "15545"]
    data.merge(pairs) { _, new in new }
    return PointerData(data: data)
  }

  func testAPointerNeedsOrgTypeAndId() {
    XCTAssertTrue(pointer([:]).isPointer)
    XCTAssertFalse(PointerData(data: ["org": "puremedia"]).isPointer)
    XCTAssertFalse(PointerData(data: [:]).isPointer)
    XCTAssertFalse(pointer(["artifactId": ""]).isPointer)
  }

  func testTheFamilyPerArtifactAndVerb() {
    XCTAssertEqual(pointer(["verb": "assigned"]).family, .workItem)
    XCTAssertEqual(pointer(["verb": "stateChanged"]).family, .workItem)
    XCTAssertEqual(pointer(["verb": "commented"]).family, .workItemComment)
    XCTAssertEqual(pointer(["verb": "mentioned"]).family, .workItemComment)
    XCTAssertEqual(
      pointer(["artifactType": "pullRequest", "verb": "reviewRequested"]).family, .pullRequest)
    XCTAssertEqual(
      pointer(["artifactType": "pullRequest", "verb": "replied"]).family, .pullRequestComment)
    XCTAssertEqual(pointer(["artifactType": "build", "verb": "buildFixed"]).family, .build)
    XCTAssertEqual(
      pointer(["artifactType": "approval", "verb": "approvalPending"]).family, .approval)
  }

  func testAVerbOrArtifactThisBuildDoesNotKnowFetchesNothing() {
    XCTAssertEqual(pointer(["verb": "somethingNew"]).family, .none)
    XCTAssertEqual(pointer([:]).family, .none)
    XCTAssertEqual(pointer(["artifactType": "wiki", "verb": "commented"]).family, .none)
  }

  func testStaleAfterTenMinutes() {
    let now = Date()
    func at(_ minutesAgo: Double) -> PointerData {
      let sent = now.addingTimeInterval(-minutesAgo * 60)
      return pointer(["sentAt": ISO8601DateFormatter().string(from: sent)])
    }
    XCTAssertFalse(at(9).isStale(at: now))
    XCTAssertTrue(at(11).isStale(at: now))
    // No `sentAt` is not a reason to skip the fetch.
    XCTAssertFalse(pointer([:]).isStale(at: now))
  }

  func testAnchorIds() {
    XCTAssertEqual(pointer(["anchor": "comment:42"]).anchorId("comment"), "42")
    XCTAssertNil(pointer(["anchor": "comment:42"]).anchorId("thread"))
    XCTAssertEqual(pointer(["anchor": "thread:4821"]).anchorId("thread"), "4821")
    XCTAssertNil(pointer(["anchor": "tab:files"]).anchorId("comment"))
    XCTAssertNil(pointer(["anchor": "comment:"]).anchorId("comment"))
    XCTAssertNil(pointer([:]).anchorId("comment"))
  }

  func testTheFallbackLinesComeFromTheAlertAndFallBackToTheDataKeys() {
    // APNs: the lines are in `aps.alert`, which the extension hands in.
    let fromAlert = PointerData(
      data: ["org": "o", "artifactType": "build", "artifactId": "1"],
      fallbackTitle: "boardhop-scratch · 20260913.2", fallbackBody: "Build failed",
      fallbackSubtitle: "DevOps Mobile App")
    XCTAssertEqual(fromAlert.fallbackBody, "Build failed")
    XCTAssertEqual(fromAlert.fallbackSubtitle, "DevOps Mobile App")

    // FCM's shape, which the Android fixtures and the relay's data map use.
    let fromData = PointerData(
      data: [
        "org": "o", "artifactType": "build", "artifactId": "1", "fallbackBody": "Build failed",
      ])
    XCTAssertEqual(fromData.fallbackBody, "Build failed")
    XCTAssertNil(fromData.fallbackSubtitle)
  }

  func testTheServiceReadsOnlyTheStringKeysBesideAps() {
    let userInfo: [AnyHashable: Any] = [
      "aps": ["alert": ["title": "t"], "mutable-content": 1],
      "org": "puremedia",
      "artifactId": "15545",
      "runId": 42,
    ]
    let keys = PointerData.stringKeys(of: userInfo)
    XCTAssertEqual(keys, ["org": "puremedia", "artifactId": "15545"])
  }
}

import XCTest

/// The pure half of the Notification Service Extension (R2.7).
///
/// These are the cases the Kotlin twin's doc comments name
/// (`android/app/src/main/kotlin/com/kammcs/boardhop/EnrichmentFormat.kt`), so
/// the two platforms can be compared line by line. The sources under test are
/// compiled into this target as well as into BoardhopNotificationService, which
/// is what lets `xcodebuild test -scheme Runner` cover an extension that cannot
/// otherwise be run anywhere but a physical iPhone.
final class EnrichmentFormatTests: XCTestCase {

  // ------------------------------------------------------------------ html

  func testPlainTextRendersMentionsAndDecodesEntities() {
    let html =
      "<div>Hello <a href=\"#\" data-vss-mention=\"version:2.0,guid\">Kelly Kamm</a>, "
      + "see &amp; check</div>"
    XCTAssertEqual(EnrichmentFormat.plainText(html), "Hello @Kelly Kamm, see & check")
  }

  func testPlainTextLeavesAMentionThatAlreadyHasItsAt() {
    let html = "<p><a data-vss-mention=\"version:2.0\">@Ada Example</a> please look</p>"
    XCTAssertEqual(EnrichmentFormat.plainText(html), "@Ada Example please look")
  }

  func testPlainTextTurnsBlockEndsIntoLines() {
    // One newline per block end, and `<br/>` counts as one too, so the two
    // between "two" and "three" are `</p>` plus the break.
    let html = "<p>one</p><p>two</p><br/><p>three</p>"
    XCTAssertEqual(EnrichmentFormat.plainText(html), "one\ntwo\n\nthree")
  }

  func testPlainTextCollapsesThreeOrMoreNewlines() {
    XCTAssertEqual(
      EnrichmentFormat.plainText("<p>one</p><p></p><p></p><p></p>two"), "one\n\ntwo")
  }

  func testPlainTextOfNothing() {
    XCTAssertEqual(EnrichmentFormat.plainText(nil), "")
    XCTAssertEqual(EnrichmentFormat.plainText(""), "")
  }

  func testDecodeEntitiesHandlesNumericAndNamedForms() {
    XCTAssertEqual(EnrichmentFormat.decodeEntities("&#65;&#x42;"), "AB")
    XCTAssertEqual(EnrichmentFormat.decodeEntities("a &lt;b&gt; &hellip;"), "a <b> …")
    // The escaped ampersand is decoded last, so it cannot re-open an entity.
    XCTAssertEqual(EnrichmentFormat.decodeEntities("&amp;lt;"), "&lt;")
  }

  func testClampCutsOnAWordBoundaryWhenThereIsOne() {
    XCTAssertEqual(EnrichmentFormat.clamp("aaaa bbbb cccc dddd", max: 12), "aaaa bbbb…")
  }

  func testClampKeepsTheCutWhenTheWordBoundaryIsTooEarly() {
    XCTAssertEqual(EnrichmentFormat.clamp("one two three", max: 8), "one two…")
  }

  func testClampLeavesShortTextAlone() {
    XCTAssertEqual(EnrichmentFormat.clamp("short"), "short")
    XCTAssertEqual(EnrichmentFormat.maxBody, 1000)
  }

  // ---------------------------------------------------------------- pieces

  func testShortBranch() {
    XCTAssertEqual(EnrichmentFormat.shortBranch("refs/heads/feature/x"), "feature/x")
    XCTAssertEqual(EnrichmentFormat.shortBranch("main"), "main")
    XCTAssertNil(EnrichmentFormat.shortBranch(nil))
    XCTAssertNil(EnrichmentFormat.shortBranch("   "))
  }

  func testJoinDropsEmptyPartsAndTrims() {
    XCTAssertEqual(EnrichmentFormat.join("a", nil, "", " b "), "a · b")
    XCTAssertNil(EnrichmentFormat.join(nil, "", "  "))
  }

  func testThreadLocation() {
    XCTAssertEqual(
      EnrichmentFormat.threadLocation(filePath: "/lib/main.dart", line: 38), "lib/main.dart:38")
    XCTAssertEqual(
      EnrichmentFormat.threadLocation(filePath: "lib/main.dart", line: nil), "lib/main.dart")
    XCTAssertEqual(
      EnrichmentFormat.threadLocation(filePath: "lib/main.dart", line: 0), "lib/main.dart")
    XCTAssertNil(EnrichmentFormat.threadLocation(filePath: nil, line: 3))
  }

  // ---------------------------------------------------------------- bodies

  func testWorkItemBody() {
    XCTAssertEqual(
      EnrichmentFormat.workItemBody("Ada Example assigned you", type: "User Story", state: "Active"),
      "Ada Example assigned you · User Story · Active")
  }

  func testPullRequestBodyAddsRepositoryAndBranches() {
    XCTAssertEqual(
      EnrichmentFormat.pullRequestBody(
        "Ada Example asked you to review !8334", repository: "boardhop",
        source: "refs/heads/feature/x", target: "refs/heads/main"),
      "Ada Example asked you to review !8334 · boardhop · feature/x → main")
  }

  func testPullRequestBodyWithOneBranchOnly() {
    XCTAssertEqual(
      EnrichmentFormat.pullRequestBody(
        "voted", repository: nil, source: "refs/heads/feature/x", target: nil),
      "voted · feature/x")
  }

  func testBuildFailureBodyTakesTheFirstLineOfTheIssue() {
    XCTAssertEqual(
      EnrichmentFormat.buildFailureBody(
        "Build failed", path: "Deploy › Run tests", issue: "3 tests failed\nsee the log"),
      "Build failed · Deploy › Run tests: 3 tests failed")
  }

  func testBuildFailureBodyWithOnlyOneHalf() {
    XCTAssertEqual(
      EnrichmentFormat.buildFailureBody("Build failed", path: "Deploy › Run tests", issue: nil),
      "Build failed · Deploy › Run tests")
    XCTAssertEqual(
      EnrichmentFormat.buildFailureBody("Build failed", path: nil, issue: nil), "Build failed")
  }

  func testBuildSuccessBody() {
    XCTAssertEqual(
      EnrichmentFormat.buildSuccessBody("queued a build that is fixed", durationMillis: 80_000),
      "queued a build that is fixed · Succeeded in 1m 20s")
    XCTAssertEqual(
      EnrichmentFormat.buildSuccessBody("done", durationMillis: nil), "done")
  }

  func testDurationLabel() {
    XCTAssertEqual(EnrichmentFormat.durationLabel(90_000), "1m 30s")
    XCTAssertEqual(EnrichmentFormat.durationLabel(3_720_000), "1h 2m")
    XCTAssertEqual(EnrichmentFormat.durationLabel(45_000), "45s")
    XCTAssertEqual(EnrichmentFormat.durationLabel(-1), "0s")
  }

  func testApprovalBodyStripsHtmlFromTheInstructions() {
    XCTAssertEqual(
      EnrichmentFormat.approvalBody(
        "Needs your approval", instructions: "<p>Approve <b>from the app</b></p>",
        runName: "20260913.3"),
      "Needs your approval · Approve from the app · 20260913.3")
  }

  // ------------------------------------------------------------------ time

  func testParseIsoAcceptsAzureDevOpsFractions() {
    let withFraction = EnrichmentFormat.parseIso("2026-09-13T12:34:56.7891234Z")
    let without = EnrichmentFormat.parseIso("2026-09-13T12:34:56Z")
    XCTAssertNotNil(withFraction)
    XCTAssertEqual(withFraction, without)
    XCTAssertNil(EnrichmentFormat.parseIso(nil))
    XCTAssertNil(EnrichmentFormat.parseIso("not a date"))
  }
}

import Foundation
import Testing
@testable import SubmitKit

@Test func appleBuildSelectionNeverFallsBackToAnUnrelatedBuild() {
    let payload = JSON(data: Data("""
        {"data":[
          {"id":"wrong","attributes":{"version":"41"}},
          {"id":"right","attributes":{"version":"42"}}
        ]}
        """.utf8))

    #expect(Runner.matchingBuildID(in: payload, buildNumber: "42") == "right")
    #expect(Runner.matchingBuildID(in: payload, buildNumber: "99") == nil)
}

@Test func uploadOperationRangesRejectNegativeAndOverflowingServerValues() {
    #expect(Runner.validUploadRange(offset: -1, length: 4, dataCount: 10) == nil)
    #expect(Runner.validUploadRange(offset: 10, length: 1, dataCount: 10) == nil)
    #expect(Runner.validUploadRange(offset: 2, length: Int.max, dataCount: 10) == 2..<10)
    #expect(Runner.validUploadRange(offset: 2, length: 4, dataCount: 10) == 2..<6)
}

@Test func revenueCatPaginationUsesTheCursorFromNextPage() {
    let next = "https://api.revenuecat.com/v2/projects/p/products?app_id=app&limit=100&starting_after=cursor_42"

    #expect(StateReader.revenueCatNextPagePath(next, expectedPrefix: "/v2/projects/p/products")
        == "/v2/projects/p/products?app_id=app&limit=100&starting_after=cursor_42")
    #expect(StateReader.revenueCatNextPagePath(
        "https://evil.example/v2/projects/p/products?starting_after=x",
        expectedPrefix: "/v2/projects/p/products") == nil)
    #expect(StateReader.revenueCatNextPagePath(next, expectedPrefix: "/v2/projects/other/products")
        == nil)
}

@Test func applePaginationOnlyFollowsTrustedBuildLinks() {
    let next = "https://api.appstoreconnect.apple.com/v1/builds?cursor=next_42"

    #expect(UploadService.appleNextPagePath(next) == "/v1/builds?cursor=next_42")
    #expect(UploadService.appleNextPagePath(
        "https://evil.example/v1/builds?cursor=stolen") == nil)
    #expect(UploadService.appleNextPagePath(
        "https://api.appstoreconnect.apple.com/v1/apps?cursor=wrong-resource") == nil)
}

@Test func appleBuildIdentityIncludesTheRequestedPlatform() {
    let ios = JSON(data: Data("""
        {"data":{"attributes":{"version":"2.0","platform":"IOS"}}}
        """.utf8))

    #expect(UploadService.applePreReleaseMatches(
        ios, marketingVersion: "2.0", platform: .ios))
    #expect(!UploadService.applePreReleaseMatches(
        ios, marketingVersion: "2.0", platform: .macos))
    #expect(!UploadService.applePreReleaseMatches(
        ios, marketingVersion: "1.9", platform: .ios))
}

@Test func googleReconciliationRequiresTheExactTrackAndDraftRelease() {
    let payload = JSON(data: Data("""
        {"tracks":[
          {"track":"beta","releases":[{"status":"draft","versionCodes":["42"]}]},
          {"track":"production","releases":[
            {"status":"completed","versionCodes":["42"]},
            {"status":"draft","versionCodes":["43"]}
          ]}
        ]}
        """.utf8))

    #expect(UploadService.googleTrackContainsCommittedVersion(
        payload, track: "beta", versionCode: 42))
    #expect(UploadService.googleTrackContainsCommittedVersion(
        payload, track: "production", versionCode: 43))
    #expect(!UploadService.googleTrackContainsCommittedVersion(
        payload, track: "production", versionCode: 42))
    #expect(!UploadService.googleTrackContainsCommittedVersion(
        payload, track: "alpha", versionCode: 42))
}

@Test func directoryChecksumCoversEveryFileAndIsStable() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("checksum-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("one".utf8).write(to: root.appendingPathComponent("a.txt"))
    try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"),
                                            withIntermediateDirectories: true)
    let second = root.appendingPathComponent("nested/b.txt")
    try Data("two".utf8).write(to: second)

    let firstHash = try Checksums.sha256(directory: root)
    let repeatedHash = try Checksums.sha256(directory: root)
    #expect(firstHash == repeatedHash)

    try Data("changed".utf8).write(to: second)
    let changedHash = try Checksums.sha256(directory: root)
    #expect(changedHash != firstHash)
}

/// Apple keeps one open review submission per platform. A cancel meant for the
/// Mac took whichever submission the list named first, and that was the iOS
/// review in the queue.
@Test func aCancelTakesOnlyTheSubmissionOfItsOwnPlatform() {
    let payload = JSON(data: Data("""
        {"data":[
          {"id":"ios-queue","attributes":{"state":"WAITING_FOR_REVIEW","platform":"IOS"}},
          {"id":"mac-draft","attributes":{"state":"READY_FOR_REVIEW","platform":"MAC_OS"}}
        ]}
        """.utf8))
    let either: Set<String> = ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW"]

    #expect(ReleaseClient.cancellableSubmission(
        in: payload, platform: "MAC_OS", states: either) == "mac-draft")
    #expect(ReleaseClient.cancellableSubmission(
        in: payload, platform: "IOS", states: either) == "ios-queue")
    // The delete of a draft takes only a submission not yet sent. The iOS one
    // in the queue holds no editable version, so it is not the delete's to end.
    #expect(ReleaseClient.cancellableSubmission(
        in: payload, platform: "IOS", states: ["READY_FOR_REVIEW"]) == nil)
    #expect(ReleaseClient.cancellableSubmission(
        in: payload, platform: "TV_OS", states: either) == nil)
}

/// The read keeps this platform's open submission, and says whose it is.
@Test func theOpenSubmissionOfThisPlatformComesFirst() {
    let payload = JSON(data: Data("""
        {"data":[
          {"id":"old","attributes":{"state":"COMPLETE","platform":"MAC_OS"}},
          {"id":"ios","attributes":{"state":"WAITING_FOR_REVIEW","platform":"IOS"}},
          {"id":"mac","attributes":{"state":"IN_REVIEW","platform":"MAC_OS"}}
        ]}
        """.utf8))

    let mac = StateReader.openReviewSubmission(payload, platform: "MAC_OS")
    #expect(mac.state == "IN_REVIEW")
    #expect(mac.platform == "MAC_OS")

    // Another platform's open submission still counts when this one has none:
    // the hold on the apply stays as it was.
    let tv = StateReader.openReviewSubmission(payload, platform: "TV_OS")
    #expect(tv.state == "WAITING_FOR_REVIEW")
    #expect(tv.platform == "IOS")

    let none = StateReader.openReviewSubmission(JSON(data: Data(#"{"data":[]}"#.utf8)),
                                                platform: "IOS")
    #expect(none.state == nil)
}

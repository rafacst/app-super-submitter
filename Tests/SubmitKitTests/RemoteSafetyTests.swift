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

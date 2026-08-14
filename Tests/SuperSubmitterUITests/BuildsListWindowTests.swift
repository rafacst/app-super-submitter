import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// How much of the App Store Connect build list is on the screen.
///
/// Every build the store held was drawn. An app shipping for a year holds
/// hundreds, so the panel ran off the bottom of the tab and took the Fetch
/// button, the note and the chosen line with it. The newest ten are what a
/// developer comes here for, and the rest arrive ten at a time.

private func builds(_ count: Int) -> [UploadService.RemoteBuild] {
    (0..<count).map {
        UploadService.RemoteBuild(id: "build-\($0)", number: "\($0)", version: "1.0",
                                  processed: true, state: "VALID", expired: false,
                                  uploaded: nil, versionState: nil)
    }
}

@Test func theListOpensOnTheNewestTen() {
    let window = AppleBuildsPanel.window(builds(240), shown: 10)

    #expect(window.count == 10)
    // The newest, because `appleStoreBuilds` sorts by upload date before this
    // sees them. A window onto an unsorted list would be ten arbitrary builds.
    #expect(window.first?.id == "build-0")
    #expect(window.last?.id == "build-9")
}

@Test func showingMoreTakesTheNextTen() {
    #expect(AppleBuildsPanel.window(builds(240), shown: 20).count == 20)
    #expect(AppleBuildsPanel.window(builds(240), shown: 30).last?.id == "build-29")
}

/// The list is exhausted rather than repeating or running short.
@Test func theWindowStopsAtTheEndOfTheList() {
    #expect(AppleBuildsPanel.window(builds(24), shown: 30).count == 24)
    #expect(AppleBuildsPanel.window(builds(4), shown: 10).count == 4)
    #expect(AppleBuildsPanel.window([], shown: 10).isEmpty)
}

/// A window of nothing is empty and not a crash. `prefix` traps on a negative.
@Test func aWindowOfNothingIsEmpty() {
    #expect(AppleBuildsPanel.window(builds(5), shown: 0).isEmpty)
    #expect(AppleBuildsPanel.window(builds(5), shown: -1).isEmpty)
}

import Foundation
import Testing
@testable import SuperSubmitter

@MainActor
@Suite struct StoreFetchTests {
    @Test func everyAppTabOffersOneStoreFetch() {
        let appTabs = Tab.allCases.filter { !$0.standsAlone && $0 != .remoteSave }

        #expect(appTabs.allSatisfy(\.canFetchFromStore))
        #expect(!Tab.stores.canFetchFromStore)
        #expect(!Tab.account.canFetchFromStore)
        #expect(!Tab.settings.canFetchFromStore)
        #expect(!Tab.remoteSave.canFetchFromStore)
    }

    @Test func theSharedFetchWarnsLocksAndShowsProgress() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Shell/RootView.swift"),
            encoding: .utf8)

        #expect(shell.contains("Fetch from store"))
        #expect(shell.contains("Everything not saved in this tab will be overwritten."))
        #expect(shell.contains("ProgressView()"))
        #expect(shell.contains(".disabled(state.isFetchingSelectedTab)"))
    }
}

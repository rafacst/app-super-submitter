import Foundation
import Testing
@testable import SuperSubmitter

@MainActor
@Suite struct StoreFetchTests {
    @Test func everyAppTabOffersOneStoreFetch() {
        let appTabs = Tab.allCases.filter { !$0.standsAlone && $0 != .remoteSave }

        #expect(appTabs.allSatisfy { $0.canFetchFromStore })
        #expect(!Tab.stores.canFetchFromStore)
        #expect(!Tab.account.canFetchFromStore)
        #expect(!Tab.settings.canFetchFromStore)
        #expect(!Tab.remoteSave.canFetchFromStore)
    }

    @Test func theSharedFetchSaysWhatItDoesLocksAndShowsProgress() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Shell/RootView.swift"),
            encoding: .utf8)

        #expect(shell.contains("Fetch from store"))
        // What the read actually does. It fills what the app knows about the
        // stores and leaves `store.yaml` alone, so the message says so and
        // the button is not destructive.
        #expect(shell.contains("Nothing you have written in store.yaml is changed."))
        #expect(!shell.contains("Everything not saved in this tab will be overwritten."))
        #expect(shell.contains("ProgressView()"))
        #expect(shell.contains(".disabled(state.isFetchingSelectedTab)"))
    }
}

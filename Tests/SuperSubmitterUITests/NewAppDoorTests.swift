import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// The way in: read the onboarding, meet the two doors, and land in the app.
@MainActor
struct NewAppDoorTests {

    private func workspace(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("door-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ManifestFile.save(Manifest(), to: folder.appendingPathComponent("store.yaml"))
        return folder
    }

    /// The bug this guards: a first launch opened on the Stores tab.
    ///
    /// `selectedTab` starts on Stores, Stores stands alone, and a tab that
    /// stands alone hides the entry screen — so the two doors were reachable
    /// only through Add app in the tab strip, and a developer who had just
    /// read the onboarding met a credential form for an app that did not
    /// exist. The erase command in Settings has always set this flag and
    /// called it "the first-run screen"; a real first run never did.
    @Test func aLaunchWithNoAppOpensOnTheTwoDoors() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let launch = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/SuperSubmitterApp.swift"),
            encoding: .utf8)
        #expect(launch.contains("if state.linkedApps.isEmpty { state.showEntryScreen = true }"))

        // And the flag survives the tab it is raised over.
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "door-\(UUID().uuidString)")
        #expect(state.selectedTab == .stores)
        #expect(!state.showsEntryScreen, "the bug: Stores stands alone, so it hid the doors")
        state.showEntryScreen = true
        #expect(state.showsEntryScreen)
    }

    /// Removing the last app lands on the doors as well, for the same reason.
    @Test func removingTheLastAppOpensOnTheTwoDoors() throws {
        let folder = try workspace("last")
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "door-\(UUID().uuidString)")
        state.link(manifestAt: folder.appendingPathComponent("store.yaml"))
        #expect(!state.showsEntryScreen)

        state.removeLinkedApp(at: 0)
        #expect(state.linkedApps.isEmpty)
        #expect(state.showsEntryScreen)
    }

    /// Where an app opens is the app's own, not the door's.
    @Test func anAppOpensOnTheScreenItWasLeftOn() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let account = "door-\(UUID().uuidString)"
        let alpha = try workspace("alpha")
        let beta = try workspace("beta")
        defer {
            try? FileManager.default.removeItem(at: alpha)
            try? FileManager.default.removeItem(at: beta)
            defaults.removePersistentDomain(forName: suite)
        }

        let first = AppState(defaults: defaults, storeAccount: account)
        first.link(manifestAt: alpha.appendingPathComponent("store.yaml"))
        // A new app opens on the first screen of the job, and never on Stores:
        // Stores is about the account, so an app that opened there opened on a
        // screen that says nothing about it.
        #expect(first.selectedTab == .build)
        first.selectedTab = .details

        first.link(manifestAt: beta.appendingPathComponent("store.yaml"))
        #expect(first.selectedTab == .build)
        first.selectedTab = .media

        // Pressing a tab in the strip is not a door. The screen stays, so
        // reading one app's Media and then the next one's is one click — and
        // the app switched to is now on that screen, so that is what it
        // remembers. What an app records is what it is showing, never what it
        // showed a week ago while the window says otherwise.
        first.selectApp(at: 0)
        #expect(first.selectedTab == .media)
        first.flushSave()

        // The relaunch opens the app that was last worked on, where it was
        // last left.
        let second = AppState(defaults: defaults, storeAccount: account)
        #expect(second.linkedApps.count == 2)
        #expect(second.currentApp?.name == first.linkedApps[0].name)
        #expect(second.selectedTab == .media)

        // And the app that was not open kept its own screen.
        second.selectApp(at: 1)
        second.flushSave()
        let third = AppState(defaults: defaults, storeAccount: account)
        #expect(third.linkedApps[1].lastTab == Tab.media.rawValue)
    }

    /// What the project already says, filled in once, and never over an answer
    /// the developer has given.
    @Test func theScanFillsWhatIsEmptyAndNothingElse() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "door-\(UUID().uuidString)")
        let found = ScannedProject(store: .apple, platforms: [.macOS],
                                   identifier: "com.acme.deck", version: "2.1",
                                   name: "Deck")

        var draft = Manifest()
        state.apply(found, to: &draft, stores: [.apple])
        #expect(draft.apps.apple?.bundleId == "com.acme.deck")
        #expect(draft.apps.apple?.platforms == [.macOS])
        #expect(draft.versionName(for: .apple) == "2.1")
        // No language was invented to hold the name. Which language a listing
        // is written in first is the developer's answer.
        #expect(draft.listing == nil)

        // A second scan of a manifest that already answers changes nothing.
        var answered = draft
        answered.setAppleApp(appID: "44", bundleID: "com.acme.other", platforms: [.ios])
        state.apply(found, to: &answered, stores: [.apple])
        #expect(answered.apps.apple?.bundleId == "com.acme.other")
        #expect(answered.apps.apple?.appId == "44")
        #expect(answered.apps.apple?.platforms == [.ios])

        // And a store the developer did not pick is not filled at all. An
        // Xcode project says nothing about a Play listing.
        var googleOnly = Manifest()
        state.apply(found, to: &googleOnly, stores: [.google])
        #expect(googleOnly.apps.apple == nil)
        #expect(googleOnly.apps.google == nil)
    }

    /// The name lands where there is a language to hold it.
    @Test func theProjectNameFillsAnEmptyListing() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "door-\(UUID().uuidString)")
        let found = ScannedProject(store: .google, identifier: "com.acme.deck",
                                   version: "3.0", name: "Deck")
        var draft = Manifest()
        draft.addLocale("pt-BR")
        state.apply(found, to: &draft, stores: [.google])

        #expect(draft.apps.google?.packageName == "com.acme.deck")
        #expect(draft.listing?.locales["pt-BR"]?.name == "Deck")

        // A name the developer wrote is theirs.
        var named = Manifest()
        named.addLocale("pt-BR")
        named.setListingText("Baralho", locale: "pt-BR", field: .name)
        state.apply(found, to: &named, stores: [.google])
        #expect(named.listing?.locales["pt-BR"]?.name == "Baralho")
    }
}

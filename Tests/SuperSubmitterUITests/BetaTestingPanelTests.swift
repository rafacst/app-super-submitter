import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The Beta testing tab, where a beta is described and now also started.
///
/// Everything the panel writes reaches a person: an address in a group gets an
/// invitation, and the last row takes a place in a review queue. These hold the
/// rules that keep the panel from promising Apple something Apple refuses.
@Suite(.serialized)
@MainActor
struct BetaTestingPanelTests {
    private func workspace() throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("beta-panel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        try ManifestFile.save(manifest, to: url)
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        try state.load(from: url)
        return (state, folder)
    }

    /// Apple takes a public link on an external group only and faults the whole
    /// request when one reaches an internal group, so the switch that makes a
    /// group internal drops the link with it.
    @Test func pickingInternalDropsThePublicLinkAndItsCap() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.addBetaGroup()
        state.betaGroupFlagBinding(index: 0, flag: .publicLink).wrappedValue = true
        state.betaGroupBinding(index: 0, field: .publicLinkLimit).wrappedValue = "250"
        state.betaGroupFlagBinding(index: 0, flag: .internalGroup).wrappedValue = true

        let group = try #require(state.testFlight?.groups?.first)
        #expect(group.internalGroup == true)
        #expect(group.publicLink == nil)
        #expect(group.publicLinkLimit == nil)
    }

    /// An app with two build trains starts with its primary platform. The
    /// developer can add the other train or select it alone.
    @Test func testFlightCanSendIOSMacOSOrBoth() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.manifest.setAppleApp(
            appID: "1", bundleID: "com.example.app", platforms: [.macOS, .ios])
        state.addTestFlight()

        #expect(state.testFlightPlatforms == [.macOS])
        state.manifest.setAppleApp(
            appID: "1", bundleID: "com.example.app", platforms: [.ios, .macOS])
        #expect(state.testFlightPlatforms == [.ios])
        state.testFlightPlatformBinding(.macOS).wrappedValue = true
        #expect(state.testFlightPlatforms == [.ios, .macOS])
        state.testFlightPlatformBinding(.ios).wrappedValue = false
        #expect(state.testFlightPlatforms == [.macOS])

        // One platform must stay selected.
        state.testFlightPlatformBinding(.macOS).wrappedValue = false
        #expect(state.testFlightPlatforms == [.macOS])
        #expect(state.testFlight?.platforms == [.macOS])
    }

    /// A switch the manifest says nothing about shows what Apple holds, and
    /// writes nothing until the developer moves it. Reading it as `false` would
    /// tell a developer that their testers cannot send feedback when they can.
    @Test func anUnansweredSwitchShowsWhatTheStoreHolds() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.addBetaGroup()
        state.betaGroupBinding(index: 0, field: .name).wrappedValue = "QA"
        #expect(state.betaGroupFlagBinding(index: 0, flag: .feedback).wrappedValue)

        var held = AppleTestFlightClient.BetaGroup(id: "g1", name: "QA")
        held.feedback = false
        held.publicLinkURL = "https://testflight.apple.com/join/abcd1234"
        var apple = ActualState.Apple()
        apple.betaGroups = ["QA": held]
        state.actualState.apple = apple

        #expect(!state.betaGroupFlagBinding(index: 0, flag: .feedback).wrappedValue)
        #expect(state.testFlight?.groups?.first?.feedback == nil)
        // The link Apple minted. No apply produces it, so the read is the only
        // place it can come from.
        #expect(state.betaGroupPublicLink(index: 0) == "https://testflight.apple.com/join/abcd1234")
    }

    /// A CSV is read for addresses and not for columns. An App Store Connect
    /// export carries a header and two name columns, a quoted name carries a
    /// comma of its own, and a list pasted out of a mail client carries the
    /// address in angle brackets. None of that reaches Apple: the addresses
    /// land in `store.yaml`, and "Send to TestFlight" still invites them.
    @Test func aCSVGivesUpItsAddressesAndNothingElse() {
        let csv = """
        First Name,Last Name,Email
        Ada,Lovelace,ada@example.com
        "Doe, John",,JOHN@example.com
        Grace,Hopper,Grace Hopper <grace@example.com>
        Nobody,Here,not-an-address
        Nobody,Here,broken@nodomain
        Ada,Again,ada@example.com
        """

        #expect(AppState.addresses(inCSV: csv)
                == ["ada@example.com", "JOHN@example.com", "grace@example.com"])
    }

    /// The import adds and never replaces, and Apple matches an address
    /// case-insensitively, so the same file imported twice invites nobody.
    @Test func importedAddressesJoinTheTypedOnesAndRepeatNobody() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.addBetaGroup()
        state.betaGroupBinding(index: 0, field: .testers).wrappedValue = "ada@example.com"
        state.addTesters(["ADA@example.com", "grace@example.com"], index: 0)
        state.addTesters(["grace@example.com"], index: 0)

        #expect(state.testFlight?.groups?.first?.testers
                == ["ada@example.com", "grace@example.com"])
    }

    /// The read has always fetched every group of the app, and the panel drew
    /// the manifest alone. A group made in App Store Connect was invisible
    /// here, so the obvious next move was to make it a second time.
    @Test func aGroupTheStoreHoldsCanBeTakenIntoThePanel() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.addTestFlight()
        var held = AppleTestFlightClient.BetaGroup(id: "g1", name: "The office")
        held.internalGroup = true
        held.feedback = false
        held.testers = ["ada@example.com"]
        var apple = ActualState.Apple()
        apple.betaGroups = ["The office": held]
        state.actualState.apple = apple

        #expect(state.unlistedBetaGroups.map(\.name) == ["The office"])
        state.adoptBetaGroup(held)

        let group = try #require(state.testFlight?.groups?.first)
        #expect(group.name == "The office")
        #expect(group.internalGroup == true)
        #expect(group.feedback == false)
        #expect(group.testers == ["ada@example.com"])
        // It is on the panel now, so it is no longer offered.
        #expect(state.unlistedBetaGroups.isEmpty)
    }

    /// The send button owns the beta and nothing else: the upload and the
    /// compliance answer that Apple demands before any tester may install, then
    /// every TestFlight row. `apple.attachBuild` belongs to the App Store
    /// version, and sending it from here would attach a build to a release the
    /// developer never asked to make.
    @Test func theSendTargetTakesEveryBetaRowAndNoReleaseRow() {
        let taken = ["apple.build", "apple.buildCompliance", "apple.attachBuild",
                     "apple.betaGroup.QA", "apple.betaTesters.QA", "apple.betaBuild.QA",
                     "apple.whatToTest", "apple.betaAppLocalizations",
                     "apple.betaLicenseAgreement", "apple.betaReviewDetail",
                     "apple.betaAutoNotify", "apple.betaReview",
                     "apple.locale.en-US", "apple.media.phone", "google.listing.en-US"]
            .filter { id in
                DirectApplyTarget.testFlight.prefixes.contains { id.hasPrefix($0) }
            }

        #expect(taken == ["apple.build", "apple.buildCompliance",
                          "apple.betaGroup.QA", "apple.betaTesters.QA", "apple.betaBuild.QA",
                          "apple.whatToTest", "apple.betaAppLocalizations",
                          "apple.betaLicenseAgreement", "apple.betaReviewDetail",
                          "apple.betaAutoNotify", "apple.betaReview"])
        #expect(DirectApplyTarget.testFlight.destination([.apple, .google]) == "TestFlight")
    }
}

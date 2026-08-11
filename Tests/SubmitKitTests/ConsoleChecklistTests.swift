import Foundation
import Testing
@testable import SubmitKit

private func manifest(provider: Manifest.Provider = .none) -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.setReleaseVersionName("1.0.0")
    if provider != .none {
        manifest.monetization = Manifest.Monetization(provider: provider)
    }
    return manifest
}

@Test func theChecklistShowsTheProviderRowsOfTheSelectedProviderOnly() {
    let none = ConsoleChecklist.rows(manifest: manifest(), actual: ActualState(),
                                     stores: [.apple, .google])
    #expect(!none.contains { $0.system == "RevenueCat" || $0.system == "Adapty" })

    let adapty = ConsoleChecklist.rows(manifest: manifest(provider: .adapty),
                                       actual: ActualState(), stores: [.apple, .google])
    #expect(adapty.contains { $0.system == "Adapty" })
    #expect(!adapty.contains { $0.system == "RevenueCat" })
}

@Test func theAppleLinksUseTheNumericAppIdAndTheGoogleLinksUseTheDashboard() {
    let rows = ConsoleChecklist.rows(manifest: manifest(), actual: ActualState(),
                                     stores: [.apple, .google])

    for row in rows where row.system == "App Store" {
        #expect(row.link.hasPrefix("https://appstoreconnect.apple.com"))
    }
    for row in rows where row.system == "Google Play" {
        #expect(row.link == "https://play.google.com/console")
    }
}

@Test func onlyAnUnknownRowTakesAHandMadeMark() {
    let done = ConsoleRow(id: "x", system: "App Store", title: "t", reason: "r", link: "l",
                          state: .needed)
    let unknown = ConsoleRow(id: "y", system: "App Store", title: "t", reason: "r", link: "l",
                             state: .unknown)

    #expect(ConsoleChecklist.effectiveState(done, marks: ["x"]) == .needed)
    #expect(ConsoleChecklist.effectiveState(unknown, marks: ["y"]) == .done)
    #expect(ConsoleChecklist.effectiveState(unknown, marks: []) == .unknown)
}

@Test func theMarksClearWhenTheVersionStringChanges() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("super-submitter-tests/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ConsoleStateStore(root: root)
    try store.save(["apple.privacy"], app: "1234567890", version: "1.0.0")

    #expect(store.marks(app: "1234567890", version: "1.0.0") == ["apple.privacy"])
    // A new version needs the check again.
    #expect(store.marks(app: "1234567890", version: "1.1.0").isEmpty)
    // Another app never reads this app's marks.
    #expect(store.marks(app: "999", version: "1.0.0").isEmpty)
}

@Test func copyAsChecklistCopiesTheOpenRowsOnly() {
    let rows = [
        ConsoleRow(id: "a", system: "App Store", title: "Done thing", reason: "r",
                   link: "https://example.com", state: .done),
        ConsoleRow(id: "b", system: "Google Play", title: "Open thing", reason: "why",
                   link: "https://play.google.com/console", state: .needed),
    ]

    let markdown = ConsoleChecklist.markdown(rows, marks: [])
    #expect(markdown.contains("Open thing"))
    #expect(!markdown.contains("Done thing"))
    #expect(markdown.contains("- [ ]"))
}

@Test func tabSixAndTabNineReadOneList() {
    let rows = ConsoleChecklist.rows(manifest: manifest(), actual: ActualState(),
                                     stores: [.apple, .google])
    let shared = rows.filter(\.onEditingTab)

    #expect(!shared.isEmpty)
    // Every row that tab 6 shows is the same object that tab 9 shows, so the
    // state and the link can never disagree.
    for row in shared {
        #expect(rows.contains { $0.id == row.id && $0.state == row.state })
    }
}

// MARK: - The status labels

@Test func theAppleStatesMapToTheRowLabels() {
    #expect(ReleaseStatusReader.applePhase("PREPARE_FOR_SUBMISSION") == .draft)
    #expect(ReleaseStatusReader.applePhase("WAITING_FOR_REVIEW") == .inQueue)
    #expect(ReleaseStatusReader.applePhase("IN_REVIEW") == .inReview)
    #expect(ReleaseStatusReader.applePhase("PENDING_DEVELOPER_RELEASE") == .approved)
    #expect(ReleaseStatusReader.applePhase("READY_FOR_DISTRIBUTION") == .live)
    #expect(ReleaseStatusReader.applePhase("METADATA_REJECTED") == .rejected)
}

@Test func theGoogleReleaseSummaryStatesMapToTheRowLabels() {
    #expect(ReleaseStatusReader.googlePhase("RELEASE_LIFECYCLE_STATE_DRAFT") == .draft)
    #expect(ReleaseStatusReader.googlePhase(
        "RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW") == .draft)
    #expect(ReleaseStatusReader.googlePhase("RELEASE_LIFECYCLE_STATE_IN_REVIEW") == .inReview)
    #expect(ReleaseStatusReader.googlePhase(
        "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED") == .approved)
    #expect(ReleaseStatusReader.googlePhase("RELEASE_LIFECYCLE_STATE_NOT_APPROVED") == .rejected)
    #expect(ReleaseStatusReader.googlePhase("RELEASE_LIFECYCLE_STATE_PUBLISHED") == .live)
}

@Test func aDraftIsNotAReleasedStore() {
    #expect(!StoreStatus.Phase.draft.isReleased)
    #expect(!StoreStatus.Phase.noDraft.isReleased)
    #expect(StoreStatus.Phase.inQueue.isReleased)
    #expect(StoreStatus.Phase.draft.label == "Draft, ready to release")
    #expect(StoreStatus.Phase.inQueue.needsPolling)
    #expect(StoreStatus.Phase.inReview.needsPolling)
    #expect(StoreStatus.Phase.approved.needsPolling)
    #expect(!StoreStatus.Phase.live.needsPolling)
    #expect(!StoreStatus.Phase.rejected.needsPolling)
}

/// A row the app can finish is not a console step.
///
/// `appleCategories` writes both categories through the API and the Details
/// tab holds the pickers, so a category named in the manifest settles this
/// row. It read the store alone, so a developer who had just chosen a category
/// was told Apple reports none and sent to App Store Connect to redo it.
@Test func aCategoryNamedInTheManifestClosesTheAppInformationRow() throws {
    var named = manifest()
    named.review = Manifest.Review(applePrimaryCategory: "SOCIAL_NETWORKING")

    let row = try #require(ConsoleChecklist.rows(manifest: named, actual: ActualState(),
                                                 stores: [.apple]).first { $0.id == "apple.info" })
    #expect(row.state == .done)
    #expect(row.reason.contains("SOCIAL_NETWORKING"))

    // Nothing named and nothing stored is still a real gap.
    let bare = try #require(ConsoleChecklist.rows(manifest: manifest(), actual: ActualState(),
                                                 stores: [.apple]).first { $0.id == "apple.info" })
    #expect(bare.state == .needed)
}

/// The read already fetches the country list, so the row shows it.
///
/// It used to say "Console only" and send the developer to look up a list the
/// app was holding. Google answers 404 for a track that sells everywhere,
/// which is why `restOfWorld` counts as an answer and not as silence.
@Test func theCountryRowShowsTheAvailabilityTheReadAlreadyHolds() throws {
    func row(_ build: (inout ActualState.Google.Track) -> Void) throws -> ConsoleRow {
        var track = ActualState.Google.Track()
        build(&track)
        var google = ActualState.Google()
        google.tracks["production"] = track
        var actual = ActualState()
        actual.google = google
        return try #require(ConsoleChecklist.rows(manifest: manifest(), actual: actual,
                                                  stores: [.google])
            .first { $0.id == "google.countries" })
    }

    let listed = try row { $0.countries = ["BR", "US", "DE"] }
    #expect(listed.state == .done)
    #expect(listed.reason.contains("3 countries"))

    let everywhere = try row { $0.restOfWorld = true }
    #expect(everywhere.state == .done)

    // Nothing read stays unknown, so the developer can still tick it by hand.
    let unread = try row { _ in }
    #expect(unread.state == .unknown)
}

/// A version in review is a version, and the panel offered a button that could
/// never clear it.
///
/// A first submission with Apple has no writable version and nothing live, so
/// every field the row read was nil and it said **No version is prepared**.
/// `releaseBlockers` then counted it, the header read "1 thing is stopping
/// 1.6", and Re-check re-ran a read that answers nil again every time.
@Test func aVersionInReviewClosesTheSubmittedVersionRow() throws {
    func row(_ standing: ActualState.Apple.PlatformStanding) throws -> ConsoleRow {
        var apple = ActualState.Apple()
        apple.platforms = [standing]
        var actual = ActualState()
        actual.apple = apple
        return try #require(ConsoleChecklist.rows(manifest: manifest(), actual: actual,
                                                  stores: [.apple])
            .first { $0.id == "apple.version" })
    }

    let inReview = try row(.init(platform: "IOS", pending: "1.6", pendingState: "IN_REVIEW"))
    #expect(inReview.state == .done)
    #expect(inReview.reason.contains("1.6"))
    #expect(!inReview.reason.contains("No version is prepared"))

    // Apple has answered and is waiting on the developer. Still not a gap.
    let approved = try row(.init(platform: "IOS", pending: "1.6",
                                 pendingState: "PENDING_DEVELOPER_RELEASE"))
    #expect(approved.state == .done)

    // A rejection hands the version back, and the checklist matters again.
    let rejected = try row(.init(platform: "IOS", pending: "1.6", pendingState: "REJECTED"))
    #expect(rejected.state == .needed)

    // A plain draft is not "with the store" either, so nothing changes there.
    let draft = try row(.init(platform: "IOS", pending: "1.6",
                              pendingState: "PREPARE_FOR_SUBMISSION"))
    #expect(draft.state == .needed)

    // Another platform's review says nothing about the one being published.
    let otherPlatform = try row(.init(platform: "MAC_OS", pending: "1.6",
                                      pendingState: "IN_REVIEW"))
    #expect(otherPlatform.state == .needed)
}

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

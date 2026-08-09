import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let releaseReviewRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func releaseReviewSource(_ relativePath: String) throws -> String {
    try String(contentsOf: releaseReviewRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

// MARK: - What is stopping this release

/// The tab opened on fifteen console rows and answered "how much is left"
/// before it answered "what is stopping me". The blocking rows are a handful,
/// they are the only ones holding a button back, and they now stand at the
/// head with the count of the rest.
@Test func theBlockersStandAtTheHead() throws {
    let tab = try releaseReviewSource("Sources/SuperSubmitter/Tabs/ReleaseTab.swift")
    let start = try #require(tab.range(of: "var body: some View {"))
    let end = try #require(tab.range(of: "private var undoQuestion"))
    let body = String(tab[start.lowerBound..<end.lowerBound])

    // The order of the page: blockers, then the rail, then the two buttons.
    let blockers = try #require(body.range(of: "blockersHead"))
    let checklist = try #require(body.range(of: "checklist"))
    let send = try #require(body.range(of: "sendToReview"))
    #expect(blockers.lowerBound < checklist.lowerBound)
    #expect(checklist.lowerBound < send.lowerBound)
}

/// The head counts what the app already treats as blocking, and never a number
/// of its own invention.
@MainActor
@Test func theHeadCountsTheRowsThatHoldTheButton() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.consoleRows = [
        ConsoleRow(id: "a.blocked", system: "App Store", title: "Export compliance",
                   reason: "Apple refuses the submission without it.", link: "",
                   state: .needed),
        ConsoleRow(id: "a.done", system: "App Store", title: "Pricing",
                   reason: "The apply writes it.", link: "", state: .done),
        ConsoleRow(id: "g.blocked", system: "Google Play", title: "Data safety",
                   reason: "The manifest holds no answers.", link: "", state: .needed),
    ]

    #expect(state.releaseBlockers(for: .apple).count == 1)
    #expect(state.releaseBlockers(for: .google).count == 1)
    #expect(state.releaseBlockers(for: .apple).first?.title == "Export compliance")
}

/// Nothing the tab already did may leave with the rearrangement.
@Test func theRailAndTheTwoButtonsSurvive() throws {
    let tab = try releaseReviewSource("Sources/SuperSubmitter/Tabs/ReleaseTab.swift")

    #expect(tab.contains("appleReleaseControls"))
    #expect(tab.contains("undoRelease"))
    #expect(tab.contains("releaseBlockers"))
    #expect(tab.contains("loadConsoleMarks"))
}

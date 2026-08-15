import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let screenReportRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func screenReportSource(_ relativePath: String) throws -> String {
    try String(contentsOf: screenReportRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

@MainActor
private func screenReportState() -> AppState {
    AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
             storeAccount: "test-\(UUID().uuidString)")
}

// MARK: - What counts as the screen

/// The ordinary case: the tab the sidebar has selected.
///
/// Settings, because this state has no app linked. The entry screen covers
/// every tab that needs one, and the three that stand alone are the three a
/// developer can reach before their first folder.
@MainActor
@Test func theTabNamesTheScreen() {
    let state = screenReportState()

    state.selectedTab = .settings

    #expect(state.currentScreenName == "Settings")
}

/// The entry screen draws over the content column and leaves the tab selection
/// standing behind it, so the tab is no longer what the developer is looking
/// at. Reporting the tab there filed a session that never left the two doors
/// under whichever screen it happened to be covering.
@MainActor
@Test func theEntryScreenOutranksTheTabBehindIt() {
    let state = screenReportState()
    state.selectedTab = .stores

    state.showEntryScreen = true

    #expect(state.currentScreenName == "Entry screen")
}

/// And it hands the tab back when it closes, rather than pinning the session
/// to the entry screen for as long as the app stays open.
@MainActor
@Test func theTabReturnsWhenTheEntryScreenCloses() {
    let state = screenReportState()
    state.selectedTab = .stores
    state.showEntryScreen = true

    state.showEntryScreen = false

    #expect(state.currentScreenName == "Stores")
}

// MARK: - When the report goes out

/// The report is the last line of the observer, and the ordering is the whole
/// of it: `mode` settles inside that observer, so a report sent before it
/// carries the job the developer is leaving. Clicking a Managing tab from a
/// Publishing one filed the visit under Publishing every time.
@Test func theTabReportsAfterItsModeSettles() throws {
    let source = try screenReportSource("Sources/SuperSubmitter/AppState.swift")
    let observer = try #require(source.range(of: "var selectedTab: Tab"))
    let body = source[observer.lowerBound...]
    let modeSettles = try #require(body.range(of: "mode = owner"))
    let reports = try #require(body.range(of: "trackScreen()"))

    #expect(modeSettles.upperBound < reports.lowerBound)
}

/// A launch is not a tab change. The restore sets `selectedTab` inside `init`,
/// where Swift runs no property observer, so the shell has to report the
/// opening screen itself or the session's first screen is never counted.
@Test func theShellReportsTheScreenALaunchOpensOn() throws {
    let shell = try screenReportSource("Sources/SuperSubmitter/SuperSubmitterApp.swift")

    #expect(shell.contains("state.trackScreen()"))
}

/// A screenshot or demo run walks the app through a dozen screens on purpose.
/// The guard sits ahead of both reads, so a run of the script reports nothing
/// at all rather than a session per picture.
@Test func aScreenshotRunStartsNoAnalytics() throws {
    let source = try screenReportSource("Sources/SuperSubmitter/AptabaseClient.swift")
    let guardsIt = try #require(source.range(of: "guard !ScreenshotMode.isActive else { return }"))
    let starts = try #require(source.range(of: "Aptabase.shared.initialize"))

    #expect(guardsIt.upperBound < starts.lowerBound)
}

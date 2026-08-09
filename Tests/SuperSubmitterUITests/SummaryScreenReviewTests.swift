import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let summaryReviewRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func summaryReviewSource(_ relativePath: String) throws -> String {
    try String(contentsOf: summaryReviewRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

// MARK: - The runway

/// The tab answered "what changes" and never "where am I". A developer landing
/// on it saw a diff with no account of the five things a release passes
/// through, so "does apply send this to a customer" was answered by the small
/// print under a button.
@Test func theSummaryOpensOnTheRunway() throws {
    let tab = try summaryReviewSource("Sources/SuperSubmitter/Tabs/PlanTab.swift")

    #expect(tab.contains("private var runway"))
    #expect(tab.contains("Describe"))
    #expect(tab.contains("Apply"))
    #expect(tab.contains("Release"))
}

/// Every step reports a real number or says plainly that it has none. A step
/// that invents its caption is worse than a step with no caption.
@MainActor
@Test func everyStepReadsTheStateItDescribes() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")

    // Nothing read, nothing planned: the plan step says so rather than zero.
    #expect(state.plan == nil)
    #expect(RunwayStep.plan(state).isEmpty == false)

    var plan = PlanResult()
    plan.steps = []
    state.plan = plan
    #expect(RunwayStep.plan(state).contains("0"))

    // The apply step is the one that says where a run ends, and a dry run
    // ends somewhere else.
    state.dryRun = true
    #expect(RunwayStep.apply(state).lowercased().contains("dry"))
    state.dryRun = false
    #expect(RunwayStep.apply(state).lowercased().contains("draft"))
}

/// Forty writes across three systems is four screens of scrolling before the
/// apply button. Each system folds, and they open shut, so the tab opens on the
/// shape of the release and the developer opens the column they came for.
@Test func everyPlanColumnFoldsAndOpensShut() throws {
    let tab = try summaryReviewSource("Sources/SuperSubmitter/Tabs/PlanTab.swift")

    #expect(tab.contains("openColumns: Set<PlanSystem> = []"))
    #expect(tab.contains("chevron.right"))
    // The same growth the Build folds use, and for the same reason.
    #expect(tab.contains("clipped()"))
}

/// The diff is still the reason the tab exists, and the runway may not push it
/// under the fold or take a column off it.
@Test func theDiffKeepsItsPlaceAndItsActions() throws {
    let tab = try summaryReviewSource("Sources/SuperSubmitter/Tabs/PlanTab.swift")

    #expect(tab.contains("columns(plan)"))
    #expect(tab.contains("counters(plan)"))
    #expect(tab.contains("validations(plan)"))
    #expect(tab.contains("applyRow(plan)"))
    #expect(tab.contains("readStores()"))
}

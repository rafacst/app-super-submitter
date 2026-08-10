import Foundation
import Testing
@testable import SubmitKit
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

// MARK: - What the stores are holding

@MainActor
private func summaryState(findings: [Finding]) -> AppState {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    // A dry run needs no paid capability, so `canApply` answers the question
    // this asks rather than the paywall's.
    state.dryRun = true
    var plan = PlanResult()
    plan.steps = [PlanStep(id: "apple.name", system: .apple, kind: .change,
                           summary: "name", title: "Name", requests: [],
                           operation: .appleVersionLocale("en-US"))]
    plan.findings = findings
    state.plan = plan
    return state
}

/// A version in review stops the apply and is not a fault.
///
/// The screen used to answer the ordinary act of shipping with two red errors,
/// a red "2" beside Summary, and a red dot on the store. Every one of those
/// says the developer broke something. The apply still has to stop, because
/// Apple refuses the write, and that is the only part that survives.
@MainActor
@Test func aVersionInReviewHoldsTheApplyAndRaisesNoBadge() throws {
    let hold = try #require(Validator.appleVersion("WAITING_FOR_REVIEW", version: "1.5"))
    let state = summaryState(findings: [hold])

    #expect(hold.severity == .held)
    #expect(!state.canApply)
    #expect(state.planIsBlocked)
    // Nothing on any tab closes a hold, so no tab wears a number for it.
    #expect(state.badge(for: .plan) == nil)
    #expect(state.badge(for: .details) == nil)
}

/// The tick that unlocks the apply has to be somewhere a developer can reach.
///
/// A refusal is a warning, a warning holds the apply until it is acknowledged,
/// and the card below hides this one because the banner above already says it
/// in more words. Hiding the row hid the only "Acknowledge" in the app that
/// unlocks this apply: the button was off, the note under it asked for an
/// acknowledgement, and there was nothing on the screen to acknowledge. The
/// banner carries the tick, so the sentence is still said once.
@MainActor
@Test func aRefusalLeavesTheTickThatUnlocksTheApplyOnTheScreen() throws {
    let refusal = try #require(Validator.appleVersion("METADATA_REJECTED", version: "1.5"))
    let state = summaryState(findings: [refusal])
    var apple = ActualState.Apple()
    apple.versionState = "METADATA_REJECTED"
    apple.versionString = "1.5"
    state.actualState.apple = apple

    // The banner is up, so the card drops the row. Something else has to ask.
    #expect(state.reviewOutcome?.outcome == .refused)
    #expect(!state.canApply)
    let waiting = try #require(state.reviewWarningNeedingAcknowledgement)
    #expect(waiting.id == Validator.appleVersionFindingID)

    // And it is the real tick, not a second one: the same id the card would
    // have ticked, so acknowledging it here unlocks the apply.
    state.acknowledged.insert(waiting.id)
    #expect(state.reviewWarningNeedingAcknowledgement == nil)
    #expect(state.canApply)
}

/// A hold asks for no tick. Nothing the developer does closes it, so a control
/// that implied otherwise would be a lie with a checkbox on it.
@MainActor
@Test func aVersionApplesStillReadingAsksForNoAcknowledgement() throws {
    let hold = try #require(Validator.appleVersion("IN_REVIEW", version: "1.5"))
    let state = summaryState(findings: [hold])
    var apple = ActualState.Apple()
    apple.versionState = "IN_REVIEW"
    state.actualState.apple = apple

    #expect(state.reviewOutcome?.outcome == .waiting)
    #expect(state.reviewWarningNeedingAcknowledgement == nil)
}

/// The banner draws it. A property nothing reads closes no dead end.
@Test func theBannerIsWhereTheTickIsDrawn() throws {
    let tab = try summaryReviewSource("Sources/SuperSubmitter/Tabs/PlanTab.swift")
    #expect(tab.contains("reviewWarningNeedingAcknowledgement"))
}

/// A refusal is the developer's turn again: one warning, one acknowledgement,
/// and a button that lands on the first field rather than the top of a tab.
@MainActor
@Test func aRefusedListingWarnsAndNamesTheFieldToChange() throws {
    let refusal = try #require(Validator.appleVersion("METADATA_REJECTED", version: "1.5"))
    let state = summaryState(findings: [refusal])

    #expect(refusal.severity == .warning)
    #expect(state.badge(for: .details)?.warnings == 1)
    #expect(state.badge(for: .details)?.errors == 0)
    // The apply unlocks once the warning is acknowledged. A refusal blocks
    // nothing: the version is editable and the fixed listing goes to it.
    #expect(!state.canApply)
    state.acknowledged.insert(refusal.id)
    #expect(state.canApply)

    // The anchor is a field that exists. A jump to a name nothing carries
    // scrolls nowhere, silently.
    let anchor = try #require(refusal.fixAnchor)
    let entry = try #require(FieldIndex.all.first { $0.id == anchor })
    #expect(entry.tab == state.tab(for: refusal.fix))
}

/// A build the store would not take is an error, and it reads as one.
@MainActor
@Test func aRefusedBinaryIsAnErrorOnTheBuildTab() throws {
    let refused = try #require(Validator.appleVersion("INVALID_BINARY", version: "1.5"))
    let state = summaryState(findings: [refused])

    #expect(refused.severity == .error)
    #expect(state.badge(for: .build)?.errors == 1)
    #expect(!state.canApply)
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

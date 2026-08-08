import Foundation
import Testing
@testable import SubmitKit

/// Fields whose names belong to a store, not to this app.
///
/// The age rating shipped five invented attribute names and every apply died
/// on a 409. These are the same shape: a list the app cannot know, so it asks
/// the store or it sends nothing. The rule is one line. **A name the app did
/// not read is a name the app does not send.**

// MARK: - The App Store categories

private func categorised(_ primary: String, _ secondary: String? = nil) -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    var review = Manifest.Review()
    review.applePrimaryCategory = primary
    review.appleSecondaryCategory = secondary
    manifest.review = review
    return manifest
}

private func appleWithCategories(_ ids: Set<String>) -> ActualState {
    var apple = ActualState.Apple()
    apple.appInfoId = "info-1"
    apple.appCategoryIDs = ids
    var state = ActualState()
    state.apple = apple
    return state
}

@Test func aCategoryAppleDoesNotHaveIsCaughtBeforeAnythingIsWritten() {
    let findings = Validator.findings(Planner.Input(
        manifest: categorised("PRODUCTIVITY_TOOLS"),
        actual: appleWithCategories(["PRODUCTIVITY", "GAMES"]), stores: [.apple]))

    let finding = findings.first { $0.id == "review.category.PRODUCTIVITY_TOOLS" }
    // An error, because this value is sent and Apple refuses it. Stopping in
    // the plan beats stopping partway through the writes.
    #expect(finding?.severity == .error)
}

@Test func aCategoryAppleReportedRaisesNothing() {
    let findings = Validator.findings(Planner.Input(
        manifest: categorised("GAMES", "ENTERTAINMENT"),
        actual: appleWithCategories(["GAMES", "ENTERTAINMENT"]), stores: [.apple]))

    #expect(!findings.contains { $0.id.hasPrefix("review.category") })
}

/// The guard that keeps a failed or partial read from blocking a release.
@Test func withNoCategoryReadNoCategoryIsJudged() {
    let findings = Validator.findings(Planner.Input(
        manifest: categorised("ANYTHING_AT_ALL"),
        actual: appleWithCategories([]), stores: [.apple]))

    #expect(!findings.contains { $0.id.hasPrefix("review.category") })
}

// MARK: - The Google data safety declaration

private func googleApp(csv: String? = nil, answers: [String: Bool]? = nil) -> Manifest {
    var manifest = Manifest()
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.review = Manifest.Review(dataSafetyAnswers: answers, dataSafetyCSV: csv)
    return manifest
}

@Test func answersWithInventedQuestionIdsPlanNoDataSafetyWrite() {
    let steps = Planner.plan(Planner.Input(
        manifest: googleApp(answers: ["collects_personal_data": true]),
        actual: ActualState(), stores: [.google])).steps

    // Google publishes its question ids. A body built from the app's own can
    // only be refused, so nothing is planned and Play Console keeps its own.
    #expect(!steps.contains { $0.id == "google.dataSafety" })
}

@Test func aRealCsvPlansTheDataSafetyWrite() {
    let steps = Planner.plan(Planner.Input(
        manifest: googleApp(csv: "safety.csv"), actual: ActualState(),
        stores: [.google])).steps

    #expect(steps.contains { $0.id == "google.dataSafety" })
}

@Test func staleAnswersAreReportedAndDoNotBlockARelease() {
    let findings = Validator.findings(Planner.Input(
        manifest: googleApp(answers: ["collects_personal_data": true]),
        actual: ActualState(), stores: [.google]))

    let finding = findings.first { $0.id == "review.dataSafetyCSV.recommended" }
    #expect(finding?.severity == .warning)
}

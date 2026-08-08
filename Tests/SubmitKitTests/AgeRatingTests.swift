import Foundation
import Testing
@testable import SubmitKit

/// The age rating keeps what App Store Connect holds.
///
/// The sheet used to offer five invented keys and the apply sent them as
/// attribute names. Apple has no `user_generated_content` attribute, so it
/// refused the whole request with a 409 and an update that changed nothing but
/// the release notes could not ship. Apple owns this questionnaire, so the
/// field names come from the store read and from nowhere else.

private func app(_ answers: [String: AgeRatingAnswer]) -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    var review = Manifest.Review()
    review.ageRatingAnswers = answers
    manifest.review = review
    return manifest
}

/// What Apple answered: two enum fields and one flag.
private func store(_ held: [String: AgeRatingAnswer] = [
    "violenceCartoonOrFantasy": .text("NONE"),
    "gamblingSimulated": .text("NONE"),
    "unrestrictedWebAccess": .flag(false),
]) -> ActualState {
    var apple = ActualState.Apple()
    apple.appInfoId = "info-1"
    apple.ageRatingDeclarationId = "rating-1"
    apple.ageRating = held
    var state = ActualState()
    state.apple = apple
    return state
}

@Test func anAnswerThatMatchesTheStoreIsNotAChange() {
    let changes = Planner.appleAgeRatingChanges(
        app(["violenceCartoonOrFantasy": .text("NONE")]).review, store().apple)

    #expect(changes.write.isEmpty)
    #expect(changes.unknown.isEmpty)
}

@Test func onlyTheAnswersYouChangedAreWritten() {
    let changes = Planner.appleAgeRatingChanges(
        app(["violenceCartoonOrFantasy": .text("FREQUENT_OR_INTENSE"),
             "gamblingSimulated": .text("NONE")]).review, store().apple)

    #expect(changes.write == ["violenceCartoonOrFantasy": .text("FREQUENT_OR_INTENSE")])
}

/// The exact shape that stopped the real update.
@Test func aFieldAppStoreConnectDoesNotHaveIsNeverSentAndIsReported() {
    let manifest = app(["user_generated_content": .flag(true)])
    let changes = Planner.appleAgeRatingChanges(manifest.review, store().apple)

    // It never reaches Apple, so the apply cannot die on it.
    #expect(changes.write.isEmpty)
    #expect(changes.unknown == ["user_generated_content"])

    // The plan says so, where the answer was typed. A warning and not an
    // error, because a line that is never sent must not block a release.
    let findings = Validator.findings(Planner.Input(
        manifest: manifest, actual: store(), stores: [.apple]))
    let finding = findings.first { $0.id == "review.ageRating.user_generated_content" }
    #expect(finding?.severity == .warning)
    // Nothing about the age rating blocks a release.
    #expect(!findings.contains { $0.id.hasPrefix("review.ageRating") && $0.severity == .error })
}

@Test func anAppThatOnlyShipsNewTextPlansNoAgeRatingStep() {
    let steps = Planner.plan(Planner.Input(
        manifest: app(["violenceCartoonOrFantasy": .text("NONE")]),
        actual: store(), stores: [.apple])).steps

    #expect(!steps.contains { $0.id == "apple.ageRating" })
}

@Test func aChangedAnswerPlansTheStepAndNamesTheField() {
    let steps = Planner.plan(Planner.Input(
        manifest: app(["unrestrictedWebAccess": .flag(true)]),
        actual: store(), stores: [.apple])).steps

    let step = steps.first { $0.id == "apple.ageRating" }
    #expect(step?.summary.contains("unrestrictedWebAccess") == true)
}

/// With no read the app knows no field names, so it guesses nothing.
@Test func withNoStoreReadNothingIsWritten() {
    let changes = Planner.appleAgeRatingChanges(
        app(["violenceCartoonOrFantasy": .text("NONE")]).review, ActualState.Apple())

    #expect(changes.write.isEmpty)
    #expect(changes.unknown.isEmpty)
}

/// An unanswered demo account question is not the answer "no".
@Test func anUnansweredDemoAccountQuestionOverwritesNothing() {
    var review = Manifest.Review()
    review.contactEmail = "someone@example.com"

    // The manifest says nothing about the demo account, so the plan names no
    // change for it and the writer sends no value.
    let changes = Planner.appleReviewDetailChanges(review, store().apple)
    #expect(!changes.contains("demo account"))
}

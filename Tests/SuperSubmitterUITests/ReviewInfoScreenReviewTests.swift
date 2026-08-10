import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The reviewer's needs, and the console steps that answer them.
///
/// The tab held three boxes and answered for one store. Apple's export
/// compliance question sat two tabs away on the Details inspector, under a
/// toggle that read an unanswered question as a settled "no", while the console
/// row for it told the developer to answer it here. Play's half of the screen
/// was not drawn at all: the reviewer credentials above it can never be sent,
/// because the Android Publisher API publishes no app access endpoint.
@MainActor
@Suite struct ReviewInfoScreenReviewTests {

    private func workspace() throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-info-\(UUID().uuidString)")
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

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    // MARK: - Apple's yes or no question

    /// The third state the old Bool toggle could not say.
    ///
    /// An absent key means Apple is still waiting. Reading it as `false` drew a
    /// settled "no" over every app that had never been asked.
    @Test func anUnansweredQuestionIsNotAnAnsweredNo() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(state.encryptionAnswer == nil)
        state.setEncryptionAnswer(false)
        #expect(state.encryptionAnswer == false)
        #expect(state.manifest.review?.usesNonExemptEncryption == false)
        // And back to unasked, which the Bool binding had no way to reach.
        state.setEncryptionAnswer(nil)
        #expect(state.manifest.review?.usesNonExemptEncryption == nil)
    }

    @Test func theQuestionBlocksTheSendUntilItIsAnswered() {
        var manifest = Manifest()
        #expect(ReviewInfoTab.blocksTheSend(manifest: manifest, actual: ActualState(),
                                            stores: [.apple, .google]))

        manifest.review = Manifest.Review(usesNonExemptEncryption: false)
        #expect(!ReviewInfoTab.blocksTheSend(manifest: manifest, actual: ActualState(),
                                             stores: [.apple, .google]))
    }

    /// `ITSAppUsesNonExemptEncryption` in the build answers it too, and the
    /// read reports what the build carried. The card must not ask again.
    @Test func aBuildThatCarriesTheFlagAnswersItForTheManifest() {
        var actual = ActualState()
        var apple = ActualState.Apple()
        apple.buildUsesNonExemptEncryption = false
        actual.apple = apple

        #expect(!ReviewInfoTab.blocksTheSend(manifest: Manifest(), actual: actual,
                                             stores: [.apple]))
    }

    @Test func aGoogleOnlyAppIsNeverBlockedByApplesQuestion() {
        #expect(!ReviewInfoTab.blocksTheSend(manifest: Manifest(), actual: ActualState(),
                                             stores: [.google]))
    }

    // MARK: - What the next version inherits

    /// Store policy, not an endpoint: Apple carries the review detail into the
    /// next version, so a released app arrives with the last one's answers.
    @Test func theCarriedOverNoteNamesTheVersionItComesFrom() {
        var actual = ActualState()
        var apple = ActualState.Apple()
        apple.liveVersionString = "2.4.0"
        actual.apple = apple

        #expect(ReviewInfoTab.carriedOverNote(actual) ==
                "Apple carries these over from 2.4.0 unless you change them")
    }

    /// A first submission inherits nothing, so it says nothing.
    @Test func aFirstSubmissionCarriesNothingOver() {
        #expect(ReviewInfoTab.carriedOverNote(ActualState()) == nil)
    }

    // MARK: - The two console steps that live here

    @Test func theGoogleColumnHoldsTheTwoStepsAReviewerNeeds() {
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        manifest.setGoogleApp(packageName: "com.example.app")
        let rows = ConsoleChecklist.rows(manifest: manifest, actual: ActualState(),
                                         stores: [.apple, .google])

        let here = ReviewInfoTab.consoleSteps(in: rows).map(\.id)
        #expect(here == ["google.access", "google.dataSafety"])
        // The listing's own steps stay on the Details tab.
        #expect(!here.contains("google.rating"))
        #expect(!here.contains("google.category"))
    }

    // MARK: - The sign-in Play Console has no endpoint for

    @Test func theCopyTakesBothHalvesOfTheSignIn() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.reviewerUsername = "demo@example.com"
        state.reviewerPassword = "hunter2"
        #expect(state.demoAccountClipboard == "demo@example.com\nhunter2")
    }

    /// Apple withholds the password on most accounts, so half a sign-in is
    /// still worth copying. Nothing at all is not.
    @Test func halfASignInCopiesAndAnEmptyOneDoesNot() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(state.demoAccountClipboard == nil)
        state.reviewerUsername = "demo@example.com"
        #expect(state.demoAccountClipboard == "demo@example.com")
    }

    // MARK: - Where the controls ended up

    @Test func theCardAndTheTwoColumnsAreOnTheTab() throws {
        let tab = try source("Sources/SuperSubmitter/Tabs/ReviewInfoTab.swift")

        #expect(tab.contains("Export compliance"))
        #expect(tab.contains("Uses no non-exempt encryption"))
        #expect(tab.contains("It does use encryption"))
        #expect(tab.contains("Blocks the send"))
        // The panel is named for what it is, because the row inside it is
        // already called "App access, the reviewer credentials" and a title
        // over it saying "App access" is the same words twice.
        #expect(tab.contains("Console steps"))
        #expect(tab.contains("review.console"))
        #expect(tab.contains("App access"))
        #expect(tab.contains("Copy the demo account"))
        // The switch names the move, not the state it is already in. One
        // wording for one meaning: the Details tab says the same two words.
        #expect(tab.contains("Split by store"))
        #expect(tab.contains("Merge the columns"))
        // The declaration paperwork came with the answer that owes it.
        #expect(tab.contains("struct ExportCompliance"))
        // Every field the tab already held is still on it.
        #expect(tab.contains("review.contact"))
        #expect(tab.contains("review.demoAccount"))
        #expect(tab.contains("review.notes"))
    }

    /// The console row has always said "answer it on the Review info tab". The
    /// control was on the Details inspector, so the instruction was false.
    @Test func theEncryptionAnswerIsNoLongerOnTheDetailsInspector() throws {
        let declarations = try source("Sources/SuperSubmitter/Tabs/ListingDeclarations.swift")

        #expect(!declarations.contains("The app uses non-exempt encryption"))
        #expect(!declarations.contains("struct ExportCompliance"))
        // The rest of the panel is untouched.
        #expect(declarations.contains("Store declarations"))
        #expect(declarations.contains("Kids age band"))
        #expect(declarations.contains("Google data safety"))
    }
}

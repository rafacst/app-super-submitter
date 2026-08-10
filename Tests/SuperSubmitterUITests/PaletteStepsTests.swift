import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// ⌘F answers with fields and with console steps.
///
/// A developer who types "privacy" means one of two things and does not know
/// which until they see them: the field on the Details tab, or the step in App
/// Store Connect that the field cannot satisfy. The palette answers both, so
/// these hold the half that is not the field index.
@MainActor
@Suite struct PaletteStepsTests {

    private func rows() -> [ConsoleRow] {
        [
            ConsoleRow(id: "apple.privacy", system: "App Store",
                       title: "App privacy",
                       reason: "The App Store will not review an app with no privacy answers.",
                       link: "https://appstoreconnect.apple.com/privacy",
                       state: .needed),
            ConsoleRow(id: "apple.ageRating", system: "App Store",
                       title: "Age rating",
                       reason: "Apple asks the questionnaire once per app.",
                       link: "https://appstoreconnect.apple.com/age",
                       state: .unknown),
            ConsoleRow(id: "google.dataSafety", system: "Google Play",
                       title: "Data safety",
                       reason: "Play holds the release until the form is answered.",
                       link: "https://play.google.com/console",
                       state: .needed),
            ConsoleRow(id: "revenuecat.products", system: "RevenueCat",
                       title: "Products",
                       reason: "The provider mirrors what the stores hold.",
                       link: "https://app.revenuecat.com",
                       state: .done),
        ]
    }

    // MARK: - What it matches

    /// The title is the obvious one. The store and the reason are there because
    /// a developer reaches for "Play" or for the words of the problem as often
    /// as for the name somebody else gave the step.
    @Test func aStepMatchesItsTitleItsStoreAndItsReason() {
        #expect(PaletteMatch.steps("privacy", in: rows()).map(\.id) == ["apple.privacy"])
        #expect(PaletteMatch.steps("google play", in: rows()).map(\.id) == ["google.dataSafety"])
        #expect(PaletteMatch.steps("questionnaire", in: rows()).map(\.id) == ["apple.ageRating"])
    }

    /// An empty query answers nothing at all, the way the field half does. A
    /// palette that lists every step before a letter is typed is a checklist,
    /// and the Release tab is already that.
    @Test func anEmptyQueryMatchesNoStep() {
        #expect(PaletteMatch.steps("", in: rows()).isEmpty)
        #expect(PaletteMatch.steps("   ", in: rows()).isEmpty)
    }

    // MARK: - Which steps reach the palette

    /// Only the steps still open. A step already ticked would offer a trip to
    /// somebody else's website to look at a tick.
    @Test func onlyTheOpenStepsAreOffered() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.consoleRows = rows()

        let open = state.openConsoleSteps.map(\.id)

        #expect(open == ["apple.privacy", "apple.ageRating", "google.dataSafety"])
        #expect(!open.contains("revenuecat.products"), "a finished step was offered")
    }

    /// A step marked by hand leaves the palette, without waiting for a store
    /// read to agree. The mark is the answer for the rows no API can read.
    @Test func aStepMarkedByHandLeavesThePalette() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.consoleRows = rows()
        state.consoleMarks = ["apple.ageRating"]

        #expect(!state.openConsoleSteps.map(\.id).contains("apple.ageRating"))
    }

    // MARK: - Whose console it is

    /// The row draws a store mark, so the store has to be a store and not the
    /// words printed beside it. The purchase providers own steps too and have
    /// no store logo to draw.
    @Test func aStepKnowsWhichStoreAsksForIt() {
        let byID = Dictionary(uniqueKeysWithValues: rows().map { ($0.id, $0) })

        #expect(byID["apple.privacy"]?.store == .apple)
        #expect(byID["google.dataSafety"]?.store == .google)
        #expect(byID["revenuecat.products"]?.store == nil)
    }

    /// The release blockers read the same fact. One store's open steps are the
    /// rows that hold that store's button, so the two lists can never disagree
    /// about which store a row belongs to.
    @Test func theReleaseBlockersReadTheSameStore() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.consoleRows = rows()

        #expect(state.releaseBlockers(for: .apple).map(\.id) == ["apple.privacy"])
        #expect(state.releaseBlockers(for: .google).map(\.id) == ["google.dataSafety"])
    }
}

import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// What was actually sent, and where the developer meets it.
///
/// The listing on screen is the manifest, and the manifest moves on the moment
/// the next version starts being written. What Apple is reading is the version,
/// and only a read of that version answers for it.
@MainActor
@Suite(.serialized) struct ReviewRetrievalTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    // MARK: - The panel that asks

    @Test func theSummaryTabAsksTheQuestionAndOffersBothAnswers() throws {
        let tab = try source("Sources/SuperSubmitter/Tabs/PlanTab.swift")

        #expect(tab.contains("reviewNeedsAChoice"))
        #expect(tab.contains("chooseReviewPath(.inspect)"))
        #expect(tab.contains("chooseReviewPath(.next)"))
        #expect(tab.contains("retrieveVersionInReview"))
    }

    /// The banner is not the question. An answered review still has to say
    /// what Apple answered, and a refusal has to say where the reason is.
    @Test func theOutcomeBannerIsOnTheSummaryTab() throws {
        let tab = try source("Sources/SuperSubmitter/Tabs/PlanTab.swift")

        #expect(tab.contains("reviewOutcome"))
        #expect(tab.contains("Open App Store Connect"))
    }

    // MARK: - The lock, where the characters would have gone

    @Test func theListingEditorRefusesCharactersWhileAppleHoldsIt() throws {
        let details = try source("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

        #expect(details.contains("listingLock"))
        // The sentence moved to the state with the rest of the review
        // vocabulary, because a live listing refuses the same boxes for a
        // different reason and the two answers belong side by side.
        let review = try source("Sources/SuperSubmitter/AppStateReview.swift")
        #expect(review.contains("App Store review is reading this"))
        // The box says why, rather than being dead and silent.
        #expect(details.contains("lock.line"))
    }

    @Test func theMediaTabRefusesAPictureWhileAppleHoldsIt() throws {
        let media = try source("Sources/SuperSubmitter/Tabs/MediaTab.swift")
        #expect(media.contains("mediaLockedByReview"))
    }

    // MARK: - The read itself

    /// Apple's own version id, and never a guess at which version it is. The
    /// artifacts are not fetched: a binary is not something to check by eye,
    /// and the ask was the text and the screenshots.
    @Test func theRetrievalReadsTheVersionAppleIsHolding() throws {
        let reader = try source("Sources/SubmitKit/Clients/StoreImportReader.swift")
        #expect(reader.contains("public func appleVersion(versionID:"))

        let review = try source("Sources/SuperSubmitter/AppStateReview.swift")
        #expect(review.contains("func retrieveVersionInReview"))
        #expect(review.contains("storeSnapshot"))
    }
}

import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The fields the apply layer always sent and no control ever wrote.
///
/// Each one had a request in `AppleApply`, `GoogleApply`, or `AppleMarketing`
/// and no box on any tab, so the only way to fill it was the raw YAML editor.
/// These tests hold the new bindings to the shape those requests read.
@Suite(.serialized)
@MainActor
struct UnsurfacedFieldTests {
    private func workspace() throws -> (state: AppState, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("unsurfaced-\(UUID().uuidString)")
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

    // MARK: - The Google graphics

    @Test func theTwoGoogleGraphicsReachTheMediaBlock() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        // The block starts as nil, so the first keystroke has to create it.
        state.googleGraphicBinding(.icon).wrappedValue = "assets/icon.png"
        state.googleGraphicBinding(.featureGraphic).wrappedValue = "assets/feature.png"
        #expect(state.manifest.media?.icon == "assets/icon.png")
        #expect(state.manifest.media?.featureGraphic == "assets/feature.png")

        // An emptied field clears the key rather than sending an empty path.
        state.googleGraphicBinding(.icon).wrappedValue = "  "
        #expect(state.manifest.media?.icon == nil)
    }

    // MARK: - The export compliance declaration

    @Test func theEncryptionDeclarationIsCreatedByItsFirstAnswer() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!state.hasEncryptionDeclaration)

        state.encryptionFlagBinding(.proprietary).wrappedValue = true
        state.encryptionTextBinding(.codeValue).wrappedValue = "R123456"
        #expect(state.manifest.review?.encryption?.containsProprietaryCryptography == true)
        #expect(state.manifest.review?.encryption?.codeValue == "R123456")

        // Removing it has to leave the rest of the review block alone: the
        // whole point is that `appleEncryptionDeclaration` then writes nothing.
        state.reviewBinding(.notes).wrappedValue = "No login is necessary."
        state.removeEncryptionDeclaration()
        #expect(state.manifest.review?.encryption == nil)
        #expect(state.manifest.review?.notes == "No login is necessary.")
    }

    // MARK: - TestFlight

    @Test func aTestFlightGroupCarriesItsTestersAndItsSwitches() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(state.testFlight == nil)

        state.addBetaGroup()
        state.betaGroupBinding(index: 0, field: .name).wrappedValue = "Friends"
        state.betaGroupBinding(index: 0, field: .testers).wrappedValue =
            "a@example.com, b@example.com"
        state.betaGroupFlagBinding(index: 0, flag: .publicLink).wrappedValue = true
        state.betaGroupBinding(index: 0, field: .publicLinkLimit).wrappedValue = "250"

        let group = try #require(state.testFlight?.groups?.first)
        #expect(group.name == "Friends")
        #expect(group.testers == ["a@example.com", "b@example.com"])
        #expect(group.publicLinkLimit == 250)

        // A limit with no link is a number Apple never reads, so closing the
        // link drops it instead of leaving it behind in the file.
        state.betaGroupFlagBinding(index: 0, flag: .publicLink).wrappedValue = false
        #expect(state.testFlight?.groups?.first?.publicLinkLimit == nil)
    }

    @Test func theTestFlightPageClearsItselfWhenItsLastFieldIsEmptied() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.testFlightPageBinding(locale: "en-US", field: .feedbackEmail)
            .wrappedValue = "beta@example.com"
        #expect(state.testFlight?.localizations?["en-US"]?.feedbackEmail == "beta@example.com")

        // An empty locale entry would make the planner report a TestFlight page
        // to write and then write four nulls to it.
        state.testFlightPageBinding(locale: "en-US", field: .feedbackEmail).wrappedValue = ""
        #expect(state.testFlight?.localizations == nil)
    }

    // MARK: - The Google closed-track testers

    @Test func theTrackTestersAreKeptPerTrack() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }

        state.googleTestersBinding(track: "alpha").wrappedValue =
            "alpha@googlegroups.com, staff@googlegroups.com"
        state.googleTestersBinding(track: "beta").wrappedValue = "beta@googlegroups.com"

        #expect(state.manifest.release?.google?.testers?["alpha"]?.count == 2)
        #expect(state.manifest.release?.google?.testers?["beta"] == ["beta@googlegroups.com"])

        // Clearing one track leaves the other. `GoogleApply.googleTesters`
        // replaces one track's list per call, so a dropped key is a track it
        // never touches.
        state.googleTestersBinding(track: "alpha").wrappedValue = ""
        #expect(state.manifest.release?.google?.testers?["alpha"] == nil)
        #expect(state.manifest.release?.google?.testers?["beta"] != nil)
    }

    // MARK: - The offer codes

    @Test func theCustomCodesRoundTripThroughTheField() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.manifest.purchases = [.init(id: "pro", kind: .nonConsumable)]
        let target = OfferTarget.purchase(0)
        state.addOffer(to: target)

        let field = state.offerCodesBinding(target, index: 0, field: .custom)
        field.wrappedValue = "launch=500, PRESS"
        let codes = try #require(state.offers(for: target).first?.codes?.custom)
        // Apple matches a code either way and stores it upper case, and a code
        // with no number works once.
        #expect(codes["LAUNCH"] == 500)
        #expect(codes["PRESS"] == 1)
        // The text the field shows has to parse back to the same map, or a
        // second edit of an untouched field rewrites what Apple already holds.
        #expect(field.wrappedValue == "LAUNCH=500, PRESS=1")

        state.offerCodesBinding(target, index: 0, field: .oneTimeUse).wrappedValue = "2500"
        state.offerCodesBinding(target, index: 0, field: .expiresOn).wrappedValue = "2026-12-31"
        #expect(state.offers(for: target).first?.codes?.oneTimeUse == 2500)
        #expect(state.offers(for: target).first?.codes?.expiresOn == "2026-12-31")

        // Emptying every part drops the block, so an offer code with no codes
        // is nil rather than an empty object the runner would still post.
        field.wrappedValue = ""
        state.offerCodesBinding(target, index: 0, field: .oneTimeUse).wrappedValue = ""
        state.offerCodesBinding(target, index: 0, field: .expiresOn).wrappedValue = ""
        #expect(state.offers(for: target).first?.codes == nil)
    }

    @Test func anOfferIsOffSaleUntilItIsSwitchedOn() throws {
        let (state, folder) = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        state.manifest.purchases = [.init(id: "pro", kind: .nonConsumable)]
        let target = OfferTarget.purchase(0)
        state.addOffer(to: target)

        // Google creates every offer as a draft, so the default has to read
        // false rather than inherit the "on sale" default a purchase has.
        #expect(!state.offerActiveBinding(target, index: 0).wrappedValue)
        state.offerActiveBinding(target, index: 0).wrappedValue = true
        #expect(state.offers(for: target).first?.active == true)
    }
}

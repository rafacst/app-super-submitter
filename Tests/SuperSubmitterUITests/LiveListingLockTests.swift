import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// What the Manage side may actually change about a listing customers are
/// reading.
///
/// The tab drew every field as a box with a "Required" tag on it, and the App
/// Store takes none of them: a published listing is the version's, and a change
/// to it belongs to the next version. So the developer typed a new description
/// into a live app, pressed the button, and the store answered for a decision
/// the screen had already made look available.
///
/// Google Play is the opposite and that is why this is per store: Play takes a
/// listing update at any time, without a release.
///
/// Which fields is store policy and not the schema. Every one is a plain string
/// on `appStoreVersionLocalizations`, and the endpoint would take any of them.
@MainActor
@Suite(.serialized) struct LiveListingLockTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    private func liveApp(stores: [Store] = [.apple, .google]) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        if stores.contains(.apple) {
            state.manifest.apps.apple = Manifest.Apps.Apple(
                appId: "1234567890", platforms: [.ios], bundleId: "com.example.billsplit")
        }
        if stores.contains(.google) {
            state.manifest.apps.google = Manifest.Apps.Google(packageName: "com.example.billsplit")
        }
        state.mode = .managing
        return state
    }

    // MARK: - What the App Store takes

    @Test func theAppStoreTakesOnlyThePromotionalTextOfALiveListing() {
        let state = liveApp()

        for field in ListingTextField.allCases where AppleVersionState.isLocked(field) {
            #expect(state.appleRefusesListing(field), "\(field) was offered to the App Store")
        }
        // The one Apple documents as changeable without a submission.
        #expect(!state.appleRefusesListing(.promotionalText))
    }

    /// The Publish side writes the next version, which is exactly the thing the
    /// Manage side may not do. Nothing is refused there.
    @Test func thePublishSideStillTakesEveryField() {
        let state = liveApp()
        state.mode = .publishing

        for field in ListingTextField.allCases {
            #expect(!state.appleRefusesListing(field), "\(field) was refused on the publish side")
        }
    }

    // MARK: - What the box does about it

    /// The Apple column stops taking characters, and says why.
    @Test func theAppleColumnGoesStatic() throws {
        let state = liveApp()
        let lock = try #require(state.listingLock(.description, store: .apple))

        #expect(lock.isStatic)
        #expect(!lock.line.isEmpty)
    }

    /// Google Play takes a listing update whenever it is sent, so its column
    /// never locks and never explains itself.
    @Test func theGoogleColumnKeepsTyping() {
        let state = liveApp()

        for field in ListingTextField.allCases {
            #expect(state.listingLock(field, store: .google) == nil,
                    "\(field) locked the Google column")
        }
    }

    /// The merged box stands for both stores at once. While one of them still
    /// takes the characters, typing is still worth something, so the box stays
    /// live and names the store that will not read it.
    @Test func theMergedBoxStaysLiveWhileOneStoreStillTakesIt() throws {
        let state = liveApp()
        let lock = try #require(state.listingLock(.description, store: nil))

        #expect(!lock.isStatic)
        #expect(lock.line.contains("Google Play"))
    }

    /// With no Google Play, nothing takes it and the merged box is text.
    @Test func theMergedBoxGoesStaticForAnAppleOnlyApp() throws {
        let state = liveApp(stores: [.apple])
        let lock = try #require(state.listingLock(.description, store: nil))

        #expect(lock.isStatic)
        // And the promotional text is still a box, on the same app.
        #expect(state.listingLock(.promotionalText, store: nil) == nil)
    }

    // MARK: - What the screen does with it

    @Test func theBoxDrawsTextAndDropsTheRequiredTagWhenNothingTakesIt() throws {
        let tab = try source("Sources/SuperSubmitter/Tabs/DetailsTab.swift")

        #expect(tab.contains("listingLock"))
        // "Required" on a box that cannot be written is a demand nobody can
        // meet: the submission it belonged to has already happened.
        #expect(tab.contains("if let requirement, lock?.isStatic != true"))
    }
}

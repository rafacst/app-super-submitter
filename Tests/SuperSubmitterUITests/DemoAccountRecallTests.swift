import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The reviewer sign-in the store remembers and this Mac does not.
///
/// The demo account lives in the Keychain and never in `store.yaml`, which is
/// right: it is a credential and the manifest is committed. A Keychain is per
/// machine, though, so an app that has shipped three times with a demo account
/// opened Review info with two empty fields on a new Mac, on a re-install, and
/// for every colleague.
///
/// App Store Connect carries the review detail from the released version into
/// the next one, so the store is the one place that still knows. These tests
/// pin the two rules that keep the offer safe: it never appears over something
/// the developer typed, and it never claims a password Apple withheld.
@MainActor
struct DemoAccountRecallTests {

    private func state(_ build: (inout ActualState.Apple) -> Void) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        var apple = ActualState.Apple()
        apple.liveVersionString = "3.1.0"
        build(&apple)
        var actual = ActualState()
        actual.apple = apple
        state.actualState = actual
        return state
    }

    @Test func itOffersTheAccountTheStoreHolds() {
        let state = state {
            $0.reviewDemoAccountName = "reviewer@example.com"
            $0.reviewDemoAccountPassword = "hunter2"
        }

        let offer = try! #require(state.storedDemoAccount)
        #expect(offer.name == "reviewer@example.com")
        #expect(offer.password == "hunter2")
    }

    /// Apple returns the name and, on most accounts, withholds the password.
    /// Half an answer is still worth offering: the developer confirms which
    /// account it was and types one field instead of two.
    @Test func itOffersTheNameEvenWhenApplekeepsThePassword() {
        let state = state { $0.reviewDemoAccountName = "reviewer@example.com" }

        let offer = try! #require(state.storedDemoAccount)
        #expect(offer.name == "reviewer@example.com")
        #expect(offer.password == nil)
    }

    /// The offer is for an empty field and for nothing else. A store value is
    /// older than a value being typed now, so it may never land on top of one.
    @Test func itNeverOffersOverSomethingAlreadyTyped() {
        let state = state { $0.reviewDemoAccountName = "reviewer@example.com" }

        state.reviewerUsername = "someone.else@example.com"
        #expect(state.storedDemoAccount == nil)

        state.reviewerUsername = ""
        state.reviewerPassword = "typed-by-hand"
        #expect(state.storedDemoAccount == nil)
    }

    @Test func itOffersNothingWhenTheStoreWasNeverRead() {
        let state = state { _ in }
        #expect(state.storedDemoAccount == nil)
    }

    /// Taking the offer puts it where the app keeps a reviewer sign-in, which
    /// is the two fields the Review info tab is bound to.
    @Test func takingTheOfferFillsTheFields() {
        let state = state {
            $0.reviewDemoAccountName = "reviewer@example.com"
            $0.reviewDemoAccountPassword = "hunter2"
        }

        state.fillDemoAccountFromStore()

        #expect(state.reviewerUsername == "reviewer@example.com")
        #expect(state.reviewerPassword == "hunter2")
        // And the offer is gone, because the fields now hold something.
        #expect(state.storedDemoAccount == nil)
    }
}

/// The Amount field offers Apple's own prices, or it offers nothing and stays
/// a plain text field.
///
/// The App Store sells at a price point and at nothing else, so the apply
/// resolved whatever was typed to the nearest one and the developer learned the
/// real price afterwards, on the Summary tab. The read has always fetched the
/// whole list and kept one value out of it.
///
/// The empty cases matter more than the full one. A developer with no key, and
/// a Google-only app, both still have to be able to name a price.
@MainActor
struct PricePointChoiceTests {

    /// From a string, the way the reader builds them.
    ///
    /// `Decimal(4.99)` from a literal is 4.990000000000001024, and the label is
    /// the value the manifest writes. The read parses Apple's own
    /// `customerPrice` string, so it never goes near a `Double`, and a fixture
    /// that did would be testing a path the app does not have.
    private func points(_ values: [String]) -> [Decimal] {
        values.compactMap { Decimal(string: $0) }
    }

    private func state(stores: Set<Store>, points: [Decimal],
                       readFor: String? = "USA", territory: String = "",
                       currency: String = "") -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        var apple = ActualState.Apple()
        apple.pricePoints = points
        apple.pricePointTerritory = readFor
        var actual = ActualState()
        actual.apple = apple
        state.actualState = actual
        state.priceTerritory = territory
        state.priceCurrency = currency
        // `stores` is derived from the apps the manifest names, so naming one
        // is how a test says which stores this app goes to.
        if stores.contains(.apple) {
            state.manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
        }
        if stores.contains(.google) {
            state.manifest.setGoogleApp(packageName: "com.example.app")
        }
        return state
    }

    @Test func itOffersThePricesAppleSellsAt() {
        let state = state(stores: [.apple], points: points(["4.99", "0.99", "1.99"]))
        // Sorted by the reader, so the picker reads low to high whatever order
        // Apple returned them in.
        #expect(state.applePricePoints.map(\.value) == ["0.99", "1.99", "4.99"])
    }

    @Test func itOffersNothingBeforeAnybodyReadsTheStore() {
        // No read, so no list, so the field stays free text. A picker with no
        // rows is a field that cannot be filled at all.
        #expect(state(stores: [.apple], points: []).applePricePoints.isEmpty)
    }

    @Test func aGoogleOnlyAppIsNeverHeldToApplesPrices() {
        // The points may be in hand from an earlier App Store read. They do not
        // apply to an app that no longer goes there.
        #expect(state(stores: [.google], points: points(["0.99", "4.99"])).applePricePoints.isEmpty)
    }

    @Test func aLadderReadForOneTerritoryIsNeverOfferedInAnother() {
        // Brazil's prices under a United States base price would be the wrong
        // numbers in the wrong money. Free text is the honest fallback until
        // the next read fetches the ladder this territory sells at.
        let moved = state(stores: [.apple], points: points(["0.99", "4.99"]),
                          readFor: "USA", territory: "BRA")
        #expect(moved.applePricePoints.isEmpty)
        let matched = state(stores: [.apple], points: points(["0.99"]),
                            readFor: "BRA", territory: "BRA")
        #expect(matched.applePricePoints.map(\.value) == ["0.99"])
    }

    @Test func theRowsReadAsMoneyTheWayAppStoreConnectShowsThem() {
        let state = state(stores: [.apple], points: points(["1.99"]), currency: "USD")
        // The value is what the manifest writes; the label is what a person
        // picks. `0.99` in a menu of prices is not a price anybody recognises.
        #expect(state.applePricePoints.map(\.value) == ["1.99"])
        #expect(state.applePricePoints[0].label.contains("1.99"))
        #expect(state.applePricePoints[0].label != "1.99")
    }

    @Test func theTabsOwnReadLeavesTheLadderAloneWithoutAKey() async {
        // The Monetization tab asks for the ladder every time it opens. A
        // project with no App Store key has nothing to ask, and the list a
        // Summary read already put in hand has to survive that.
        let state = state(stores: [.apple], points: points(["0.99", "4.99"]))
        await state.loadApplePricePoints()
        #expect(state.applePricePoints.map(\.value) == ["0.99", "4.99"])
    }

    @Test func aPurchaseIsNeverOfferedTheFreeRow() {
        // The App Store sells the app for nothing. It sells no purchase and no
        // subscription plan for nothing, so that row would be a write Apple
        // refuses.
        let state = state(stores: [.apple], points: points(["0", "0.99"]))
        #expect(state.applePricePoints.map(\.value) == ["0", "0.99"])
        #expect(state.appleProductPricePoints.map(\.value) == ["0.99"])
    }
}

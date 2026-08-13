import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The product table: one row per product, one column per store.
///
/// A product id is one thing the developer names and two things the stores
/// hold. Apple prices the product; Play prices a base plan inside it. The tab
/// stacked twelve fields per product and never said what either store already
/// had, so "is this live yet" was answered on the Summary tab or not at all.
@MainActor
@Suite struct MoneyScreenReviewTests {

    /// A state both stores have answered for.
    ///
    /// `read` is what makes "the store holds nothing" a fact rather than a
    /// guess. It defaults to true because every test below is about what the
    /// stores hold, which is a question that presupposes they were asked; the
    /// unread case has its own tests.
    private func actual(apple: [String] = [], google: [String] = [],
                        applePrice: String = "USD 4.99",
                        googlePlan: String? = "p1m",
                        read: Bool = true) -> ActualState {
        var state = ActualState()
        var appleSide = ActualState.Apple()
        appleSide.catalogRead = read
        for id in apple {
            var product = ActualState.Apple.CatalogProduct()
            product.productId = id
            product.prices = ["USA": applePrice]
            appleSide.catalog[id] = product
        }
        var googleSide = ActualState.Google()
        for id in google {
            var product = ActualState.Google.CatalogProduct()
            product.productId = id
            product.prices = ["US": "USD 4.99"]
            product.basePlanId = googlePlan
            googleSide.catalog[id] = product
        }
        // A store that answered and holds nothing is still a store that
        // answered, so the side is present with an empty catalog rather than
        // nil. Nil is what "nobody asked" looks like.
        state.apple = read || !apple.isEmpty ? appleSide : nil
        state.google = read || !google.isEmpty ? googleSide : nil
        return state
    }

    @Test func aProductNeitherStoreHoldsWillBeAdded() {
        let status = MoneyTab.productStatus("tip_jar", stores: [.apple, .google],
                                            actual: actual())
        #expect(status.text == "Will add")
    }

    @Test func aProductBothStoresHoldIsInSync() {
        let status = MoneyTab.productStatus("pro_monthly", stores: [.apple, .google],
                                            actual: actual(apple: ["pro_monthly"],
                                                           google: ["pro_monthly"]))
        #expect(status.text == "In sync")
    }

    /// The one the banner counts. It is the state that loses money quietly:
    /// the product sells on one store and 404s on the other.
    @Test func aProductOnOneStoreNamesTheStoreThatHasIt() {
        let status = MoneyTab.productStatus("tip_jar", stores: [.apple, .google],
                                            actual: actual(apple: ["tip_jar"]))
        #expect(status.text == "Only on App Store")
    }

    /// Play prices a base plan inside the subscription, so its column says so
    /// and the two ids never look like a mismatch.
    @Test func eachStoreSummaryIsInThatStoresOwnTerms() {
        let state = actual(apple: ["pro_annual"], google: ["pro_annual"], googlePlan: "p1y")

        #expect(MoneyTab.storeSummary("pro_annual", store: .apple, actual: state,
                                      territory: "USA") == "USD 4.99")
        #expect(MoneyTab.storeSummary("pro_annual", store: .google, actual: state,
                                      territory: "US") == "USD 4.99 · base plan p1y")
    }

    /// Apple sells at a rung of a published ladder. The tier number is gone
    /// from the API, so the rung is counted rather than named.
    @Test func anApplePriceCarriesItsLadderPosition() {
        var state = actual(apple: ["pro_annual"])
        state.apple?.pricePoints = [0.99, 1.99, 2.99, 3.99, 4.99]
        state.apple?.pricePointTerritory = "USA"

        #expect(MoneyTab.ladderPoint("USD 4.99", in: state) == 5)
        #expect(MoneyTab.storeSummary("pro_annual", store: .apple, actual: state,
                                      territory: "USA") == "USD 4.99 · point 5")
    }

    /// An unread ladder prints the price and no rung, rather than a guess.
    @Test func anUnreadLadderPrintsNoPoint() {
        let state = actual(apple: ["pro_annual"])
        #expect(MoneyTab.ladderPoint("USD 4.99", in: state) == nil)
        #expect(MoneyTab.storeSummary("pro_annual", store: .apple, actual: state,
                                      territory: "USA") == "USD 4.99")
    }

    /// A store that has never answered is not a store that answered zero.
    @Test func anUnreadStoreSaysNothingRatherThanNought() {
        #expect(MoneyTab.storeSummary("tip_jar", store: .google, actual: actual(),
                                      territory: "US") == nil)
    }

    @Test func theTableAndItsEditorsAreBothOnTheTab() throws {
        let tab = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/SuperSubmitter/Tabs/MoneyTab.swift"),
            encoding: .utf8)

        #expect(tab.contains("productTableHeader"))
        #expect(tab.contains("private func productRow"))
        #expect(tab.contains("oneStoreOnlyNote"))
        // The editors survive the table: a row opens onto them.
        #expect(tab.contains("purchaseEditor(index: index)"))
        #expect(tab.contains("OfferEditor(target: .purchase(index))"))
        #expect(tab.contains("Add in-app purchase"))
        // The plans took the same row, and kept their own fields behind it.
        #expect(tab.contains("togglePlan(groupIndex, planIndex)"))
        #expect(tab.contains("OfferEditor(target: .plan(group: groupIndex, plan: planIndex))"))
        #expect(tab.contains("Add plan"))
    }
}

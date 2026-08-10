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

    private func actual(apple: [String] = [], google: [String] = [],
                        applePrice: String = "USD 4.99",
                        googlePlan: String? = "p1m") -> ActualState {
        var state = ActualState()
        var appleSide = ActualState.Apple()
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
        state.apple = apple.isEmpty ? nil : appleSide
        state.google = google.isEmpty ? nil : googleSide
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
    }
}

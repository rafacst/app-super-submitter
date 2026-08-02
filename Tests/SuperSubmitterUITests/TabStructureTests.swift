import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

@Test func workflowTabsKeepTheirSafetyOrder() {
    #expect(Tab.allCases.map(\.title) == [
        "Stores", "Build", "Details", "Media", "Money", "Marketing",
        "Review info", "Plan", "Submit", "Release",
    ])
    #expect(Tab.plan.zone == .reads)
    #expect(Tab.submit.zone == .writes)
    #expect(Tab.release.zone == .releases)
}

@MainActor
@Test func offerPriceKeepsTheFirstHalfUntilTheSecondFieldIsEntered() throws {
    let state = AppState()
    state.manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable,
        offers: [Manifest.Offer(id: "launch", kind: .promotional)])]
    let target = OfferTarget.purchase(0)

    state.offerBinding(target, index: 0, field: .amount).wrappedValue = "4.99"
    #expect(state.offerBinding(target, index: 0, field: .amount).wrappedValue == "4.99")
    #expect(state.manifest.purchases?[0].offers?[0].price == nil)

    state.offerBinding(target, index: 0, field: .currency).wrappedValue = "usd"
    let price = try #require(state.manifest.purchases?[0].offers?[0].price)
    #expect(price.amount == Decimal(string: "4.99"))
    #expect(price.currency == "USD")
    #expect(state.moneyError == nil)
}

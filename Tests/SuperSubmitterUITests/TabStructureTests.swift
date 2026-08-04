import AppKit
import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A misspelled symbol name draws nothing and says nothing. The sidebar would
/// then show a row with no icon, so every name is resolved here instead.
@Test func everyTabSymbolResolvesInBothStates() {
    let names = Tab.allCases.flatMap { [$0.symbol(selected: false), $0.symbol(selected: true)] }
        + ["gearshape.2", "gearshape.2.fill"]
    for name in names {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "The symbol \(name) is not available.")
    }
}

@Test func workflowTabsKeepTheirSafetyOrder() {
    #expect(Tab.allCases.map(\.title) == [
        "Stores", "Build", "Details", "Media", "Monetization", "Marketing",
        "Review info", "Summary", "Submit", "Release",
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

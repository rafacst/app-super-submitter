import Foundation
import Testing
@testable import SubmitKit

/// What the App Store already knows about a product the manifest names.
///
/// The reported symptom: a subscription that has been selling for a year, read
/// and shown as "1 month · 19.9 · point 78 · Approved" on its row, with "Pick a
/// price", "Pick a currency" and an empty store name in the fields under it.
/// The read had every one of those values. `mergeAppleMoney` writes a catalog
/// only when the manifest holds none, so the moment `store.yaml` had one line
/// about a product, everything else the store said about it stopped at the
/// door.
private func heldSubscription(
    price: String? = "19.90",
    locales: [String: ActualState.Apple.CatalogProduct.ProductLocale] = [:],
    planType: Manifest.ApplePlanType? = .upfront) -> ActualState.Apple {
    var product = ActualState.Apple.CatalogProduct()
    product.productId = "com.example.pro.monthly"
    product.name = "Pro monthly"
    if let price { product.prices = ["USA": price] }
    product.locales = locales
    if let planType { product.subscriptionPlanTerritories[planType] = ["USA"] }
    var apple = ActualState.Apple()
    apple.catalog[product.productId] = product
    apple.catalogRead = true
    return apple
}

private func manifestWithAPlan() -> Manifest {
    var manifest = Manifest()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "22086859", groupName: "Operação",
        plans: [Manifest.SubscriptionGroup.Plan(id: "com.example.pro.monthly",
                                                duration: "P1M")])]
    return manifest
}

@Test func thePriceTheStoreChargesReachesThePlan() {
    var manifest = manifestWithAPlan()

    let wrote = manifest.mergeAppleCatalog(heldSubscription(), territory: "USA",
                                           currency: "USD")
    #expect(wrote)

    let plan = manifest.subscriptions?[0].plans[0]
    #expect(plan?.price?.amount == Decimal(string: "19.90"))
    #expect(plan?.price?.currency == "USD")
    #expect(plan?.price?.territory == "USA")
    // Apple keeps a subscription's territories separated by billing type, so a
    // product that answers under one type has named it.
    #expect(plan?.applePlanType == .upfront)
}

/// Apple answers `customerPrice` as a bare number. A price with no currency
/// beside it is half an answer, and a manifest that names 19.90 of nothing
/// prices the product in whatever the next reader assumes.
@Test func aPriceWithNoCurrencyIsNotWritten() {
    var manifest = manifestWithAPlan()

    let wrote = manifest.mergeAppleCatalog(heldSubscription(planType: nil),
                                           territory: "USA", currency: nil)
    #expect(!wrote)
    #expect(manifest.subscriptions?[0].plans[0].price == nil)
}

/// The store text the developer would otherwise retype.
@Test func theStoreNameAndDescriptionReachThePlan() {
    var manifest = manifestWithAPlan()
    var text = ActualState.Apple.CatalogProduct.ProductLocale()
    text.name = "Operação Pro"
    text.description = "Tudo, todo mês."

    let wrote = manifest.mergeAppleCatalog(heldSubscription(locales: ["pt-BR": text]),
                                           territory: "USA", currency: "USD")
    #expect(wrote)

    #expect(manifest.subscriptions?[0].plans[0].locales?["pt-BR"]?.name == "Operação Pro")
    #expect(manifest.subscriptions?[0].plans[0].locales?["pt-BR"]?.description
            == "Tudo, todo mês.")
}

/// Blanks only. A developer who typed a new price this morning must not have
/// last week's put back by a screen they walked past.
@Test func anAnswerInTheFileSurvivesTheRead() {
    var manifest = manifestWithAPlan()
    manifest.subscriptions?[0].plans[0].price = Price(amount: 5, currency: "EUR",
                                                      territory: "USA")
    manifest.subscriptions?[0].plans[0].applePlanType = .monthly
    manifest.subscriptions?[0].plans[0].locales = [
        "pt-BR": Manifest.ProductLocale(name: "Mine"),
    ]
    var text = ActualState.Apple.CatalogProduct.ProductLocale()
    text.name = "Theirs"

    let wrote = manifest.mergeAppleCatalog(heldSubscription(locales: ["pt-BR": text]),
                                           territory: "USA", currency: "USD")
    #expect(!wrote)

    let plan = manifest.subscriptions?[0].plans[0]
    #expect(plan?.price?.currency == "EUR")
    #expect(plan?.applePlanType == .monthly)
    #expect(plan?.locales?["pt-BR"]?.name == "Mine")
}

/// A second read writes nothing, so the tab does not save the file and take an
/// undo step every time it is opened.
@Test func theSecondReadIsNotAWrite() {
    var manifest = manifestWithAPlan()
    let apple = heldSubscription()

    let first = manifest.mergeAppleCatalog(apple, territory: "USA", currency: "USD")
    let second = manifest.mergeAppleCatalog(apple, territory: "USA", currency: "USD")
    #expect(first)
    #expect(!second)
}

/// Two billing types is a plan Apple splits, and nothing here can choose
/// between them. The validator already asks for the answer.
@Test func aSplitSubscriptionNamesNoPlanType() {
    var manifest = manifestWithAPlan()
    var apple = heldSubscription(planType: nil)
    apple.catalog["com.example.pro.monthly"]?.subscriptionPlanTerritories = [
        .monthly: ["USA"], .upfront: ["BRA"],
    ]

    _ = manifest.mergeAppleCatalog(apple, territory: "USA", currency: "USD")

    #expect(manifest.subscriptions?[0].plans[0].applePlanType == nil)
}

/// The same for a one-time purchase: the name, the review note and the price.
@Test func aPurchaseFillsFromTheSameRead() {
    var manifest = Manifest()
    manifest.purchases = [Manifest.Purchase(id: "com.example.lifetime",
                                            kind: .nonConsumable)]
    var product = ActualState.Apple.CatalogProduct()
    product.productId = "com.example.lifetime"
    product.name = "Lifetime"
    product.reviewNote = "Buy once."
    product.prices = ["USA": "49.99"]
    var apple = ActualState.Apple()
    apple.catalog[product.productId] = product

    let wrote = manifest.mergeAppleCatalog(apple, territory: "USA", currency: "USD")

    #expect(wrote)
    #expect(manifest.purchases?[0].name == "Lifetime")
    #expect(manifest.purchases?[0].reviewNote == "Buy once.")
    #expect(manifest.purchases?[0].price?.amount == Decimal(string: "49.99"))
}

/// A price that arrives with its currency on it keeps that currency. The Play
/// side answers in that shape, and so does every fixture in this app.
@Test func aPriceThatCarriesItsCurrencyKeepsIt() {
    var manifest = manifestWithAPlan()

    _ = manifest.mergeAppleCatalog(heldSubscription(price: "BRL 19.90"),
                                   territory: "USA", currency: "USD")

    #expect(manifest.subscriptions?[0].plans[0].price?.currency == "BRL")
    #expect(manifest.subscriptions?[0].plans[0].price?.amount == Decimal(string: "19.90"))
}

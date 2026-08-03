import Foundation
import Testing
@testable import SubmitKit

/// The steps that used to write blind now compare what the store holds.
///
/// Every check here asserts the same rule twice: a store that already holds
/// the wanted value produces no step, and a store that holds something else
/// names the field that differs.

private func appleManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

private func googleManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

private func appleState(_ build: (inout ActualState.Apple) -> Void) -> ActualState {
    var apple = ActualState.Apple()
    build(&apple)
    var state = ActualState()
    state.apple = apple
    return state
}

private func googleState(_ build: (inout ActualState.Google) -> Void) -> ActualState {
    var google = ActualState.Google()
    build(&google)
    var state = ActualState()
    state.google = google
    return state
}

private func appleSteps(_ manifest: Manifest, _ actual: ActualState) -> [PlanStep] {
    Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
        .steps(for: .apple)
}

private func googleSteps(_ manifest: Manifest, _ actual: ActualState) -> [PlanStep] {
    Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.google]))
        .steps(for: .google)
}

private func json(_ text: String) -> JSON { JSON(data: Data(text.utf8)) }

private func appleLocale(name: String, description: String)
    -> ActualState.Apple.CatalogProduct.ProductLocale {
    var value = ActualState.Apple.CatalogProduct.ProductLocale()
    value.name = name
    value.description = description
    return value
}

// MARK: - The App Store purchases

private func purchaseManifest() -> Manifest {
    var manifest = appleManifest()
    manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable, name: "Pro",
        price: Price(amount: 4.99, currency: "USD", territory: "USA"),
        locales: ["en-US": Manifest.ProductLocale(name: "Pro", description: "Everything.")])]
    return manifest
}

private func livePurchase(price: String = "4.99") -> ActualState.Apple.CatalogProduct {
    var product = ActualState.Apple.CatalogProduct()
    product.productId = "com.example.pro"
    product.id = "6001"
    product.locales = ["en-US": appleLocale(name: "Pro", description: "Everything.")]
    product.prices = ["USA": price]
    product.promoted = false
    return product
}

@Test func aPurchaseThatAppleAlreadyHoldsNeedsNoWrite() {
    let actual = appleState { apple in
        apple.purchaseIds = ["com.example.pro"]
        apple.catalog["com.example.pro"] = livePurchase()
    }

    let steps = appleSteps(purchaseManifest(), actual)

    #expect(!steps.contains { $0.id == "apple.purchases" })
}

@Test func aPurchaseWithADifferentPriceNamesThePriceField() throws {
    let actual = appleState { apple in
        apple.purchaseIds = ["com.example.pro"]
        apple.catalog["com.example.pro"] = livePurchase(price: "2.99")
    }

    let step = try #require(appleSteps(purchaseManifest(), actual)
        .first { $0.id == "apple.purchases" })

    #expect(step.summary.contains("com.example.pro"))
    #expect(step.summary.contains("price"))
    #expect(step.summary.contains("name") == false)
    #expect(step.comparison == .verified)
}

@Test func aPurchaseAppleHoldsAndNobodyCouldReadIsUnverified() throws {
    let actual = appleState { apple in
        apple.purchaseIds = ["com.example.pro"]
        // The list read answered and the detail read failed.
    }

    let step = try #require(appleSteps(purchaseManifest(), actual)
        .first { $0.id == "apple.purchases" })

    #expect(step.comparison == .unverified)
    #expect(step.summary.contains("unread"))
}

@Test func aPurchaseAppleDoesNotHoldReadsAsACreate() throws {
    let step = try #require(appleSteps(purchaseManifest(), appleState { _ in })
        .first { $0.id == "apple.purchases" })

    #expect(step.summary.contains("create"))
}

// MARK: - The App Store subscriptions and their offers

private func subscriptionManifest(offers: [Manifest.Offer] = []) -> Manifest {
    var manifest = appleManifest()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro", groupName: "Pro",
        plans: [Manifest.SubscriptionGroup.Plan(
            id: "pro.monthly", duration: "P1M", basePlanId: "monthly",
            price: Price(amount: 9.99, currency: "USD", territory: "USA"),
            locales: ["en-US": Manifest.ProductLocale(name: "Pro monthly")],
            offers: offers.isEmpty ? nil : offers)])]
    return manifest
}

private func liveSubscription(duration: String = "P1M")
    -> ActualState.Apple.CatalogProduct {
    var product = ActualState.Apple.CatalogProduct()
    product.productId = "pro.monthly"
    product.id = "7001"
    product.locales = ["en-US": appleLocale(name: "Pro monthly", description: "")]
    product.prices = ["USA": "9.99"]
    product.duration = duration
    product.offerCount = 0
    return product
}

@Test func aSubscriptionThatAppleAlreadyHoldsNeedsNoWrite() {
    let actual = appleState { apple in
        apple.subscriptionIds = ["pro.monthly"]
        apple.subscriptionGroupNames = ["Pro"]
        apple.catalog["pro.monthly"] = liveSubscription()
    }

    #expect(!appleSteps(subscriptionManifest(), actual)
        .contains { $0.id == "apple.subscriptions" })
}

@Test func aSubscriptionWithADifferentDurationNamesTheDuration() throws {
    let actual = appleState { apple in
        apple.subscriptionIds = ["pro.monthly"]
        apple.subscriptionGroupNames = ["Pro"]
        apple.catalog["pro.monthly"] = liveSubscription(duration: "P1Y")
    }

    let step = try #require(appleSteps(subscriptionManifest(), actual)
        .first { $0.id == "apple.subscriptions" })

    #expect(step.summary.contains("duration"))
    #expect(step.comparison == .verified)
}

/// The subscription write covers the group as well as its plans, so a group
/// that Apple does not hold keeps the step even when every plan matches.
@Test func aMissingSubscriptionGroupKeepsTheSubscriptionStep() throws {
    let actual = appleState { apple in
        apple.subscriptionIds = ["pro.monthly"]
        apple.catalog["pro.monthly"] = liveSubscription()
        // Apple holds the plan and not the group that carries it.
    }

    let step = try #require(appleSteps(subscriptionManifest(), actual)
        .first { $0.id == "apple.subscriptions" })

    #expect(step.summary.contains("Pro  group create"))
}

@Test func anOfferAppleAlreadyNamesNeedsNoWrite() {
    let offer = Manifest.Offer(id: "PROMO10", kind: .promotional, duration: "P1M")
    let actual = appleState { apple in
        apple.subscriptionIds = ["pro.monthly"]
        apple.subscriptionGroupNames = ["Pro"]
        var product = liveSubscription()
        product.offerIds = ["PROMO10"]
        product.offerCount = 1
        apple.catalog["pro.monthly"] = product
    }

    #expect(!appleSteps(subscriptionManifest(offers: [offer]), actual)
        .contains { $0.id == "apple.subscriptionOffers" })
}

@Test func anOfferReadThatFailedLeavesTheOfferStepUnverified() throws {
    let offer = Manifest.Offer(id: "PROMO10", kind: .promotional, duration: "P1M")
    let actual = appleState { apple in
        apple.subscriptionIds = ["pro.monthly"]
        apple.subscriptionGroupNames = ["Pro"]
        var product = liveSubscription()
        product.offerCount = nil
        apple.catalog["pro.monthly"] = product
    }

    let step = try #require(appleSteps(subscriptionManifest(offers: [offer]), actual)
        .first { $0.id == "apple.subscriptionOffers" })

    #expect(step.comparison == .unverified)
}

// MARK: - The review details and the grace period

@Test func reviewDetailsThatAppleAlreadyHoldsNeedNoWrite() {
    var manifest = appleManifest()
    manifest.review = Manifest.Review(contactEmail: "dev@example.com", notes: "Read me.")
    let actual = appleState { apple in
        apple.reviewDetailId = "9001"
        apple.reviewContactEmail = "dev@example.com"
        apple.reviewNotes = "Read me."
    }

    #expect(!appleSteps(manifest, actual).contains { $0.id == "apple.reviewDetails" })
}

@Test func changedReviewNotesNameTheNotesField() throws {
    var manifest = appleManifest()
    manifest.review = Manifest.Review(contactEmail: "dev@example.com", notes: "New note.")
    let actual = appleState { apple in
        apple.reviewDetailId = "9001"
        apple.reviewContactEmail = "dev@example.com"
        apple.reviewNotes = "Old note."
    }

    let step = try #require(appleSteps(manifest, actual)
        .first { $0.id == "apple.reviewDetails" })

    #expect(step.summary.contains("notes"))
    #expect(step.summary.contains("contact email") == false)
    #expect(step.comparison == .verified)
}

@Test func aGracePeriodThatAlreadyMatchesNeedsNoWrite() {
    var manifest = appleManifest()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro",
        plans: [Manifest.SubscriptionGroup.Plan(id: "pro.monthly", duration: "P1M")],
        gracePeriodDays: 16)]
    let matching = appleState { apple in
        apple.gracePeriodDays = 16
        apple.gracePeriodOptIn = true
    }
    let different = appleState { apple in
        apple.gracePeriodDays = 3
        apple.gracePeriodOptIn = true
    }

    #expect(!appleSteps(manifest, matching).contains { $0.id == "apple.gracePeriod" })
    #expect(appleSteps(manifest, different).contains { $0.id == "apple.gracePeriod" })
}

// MARK: - The App Store marketing block

@Test func aMarketingResourceAppleAlreadyHoldsNeedsNoWrite() {
    var manifest = appleManifest()
    var marketing = Manifest.Marketing()
    marketing.customProductPages = [
        Manifest.Marketing.CustomProductPage(key: "spring", name: "Spring"),
    ]
    marketing.eula = Manifest.Marketing.EULA(text: "The agreement.")
    manifest.marketing = marketing
    let held = appleState { apple in
        apple.customProductPageNames = ["Spring": "5001"]
        apple.eulaText = "The agreement."
    }
    let empty = appleState { _ in }

    let quiet = appleSteps(manifest, held)
    #expect(!quiet.contains { $0.id == "apple.customProductPages" })
    #expect(!quiet.contains { $0.id == "apple.eula" })

    // An app that holds neither still writes both.
    let busy = appleSteps(manifest, empty)
    #expect(busy.contains { $0.id == "apple.customProductPages" })
    #expect(busy.contains { $0.id == "apple.eula" })
}

@Test func onlyTheMissingCustomProductPagesReachTheSummary() throws {
    var manifest = appleManifest()
    var marketing = Manifest.Marketing()
    marketing.customProductPages = [
        Manifest.Marketing.CustomProductPage(key: "spring", name: "Spring"),
        Manifest.Marketing.CustomProductPage(key: "summer", name: "Summer"),
    ]
    manifest.marketing = marketing
    let actual = appleState { apple in
        apple.customProductPageNames = ["Spring": "5001"]
    }

    let step = try #require(appleSteps(manifest, actual)
        .first { $0.id == "apple.customProductPages" })

    #expect(step.summary.contains("1 of 2"))
    #expect(step.summary.contains("Summer"))
    #expect(step.comparison == .verified)
}

// MARK: - The Google states, offers, and migrations

private func googleCatalogManifest(active: Bool? = nil,
                                   migrate: Bool? = nil,
                                   offers: [Manifest.Offer] = []) -> Manifest {
    var manifest = googleManifest()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro", groupName: "Pro",
        plans: [Manifest.SubscriptionGroup.Plan(
            id: "pro.monthly", duration: "P1M", basePlanId: "monthly",
            price: Price(amount: 4.99, currency: "USD", territory: "US"),
            active: active,
            offers: offers.isEmpty ? nil : offers,
            migrateExistingSubscribers: migrate)])]
    return manifest
}

@Test func aBasePlanThatIsAlreadyActiveNeedsNoSwitch() {
    let actual = googleState { google in
        google.subscriptionIds = ["pro.monthly"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "pro.monthly"
        product.basePlanId = "monthly"
        product.basePlanState = "ACTIVE"
        google.catalog["pro.monthly"] = product
    }

    #expect(!googleSteps(googleCatalogManifest(active: true), actual)
        .contains { $0.id == "google.basePlanState.pro.monthly" })
}

@Test func anInactiveBasePlanTheManifestActivatesGetsASwitchThatNamesTheState() throws {
    let actual = googleState { google in
        google.subscriptionIds = ["pro.monthly"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "pro.monthly"
        product.basePlanId = "monthly"
        product.basePlanState = "INACTIVE"
        google.catalog["pro.monthly"] = product
    }

    let step = try #require(googleSteps(googleCatalogManifest(active: true), actual)
        .first { $0.id == "google.basePlanState.pro.monthly" })

    #expect(step.summary.contains("now inactive"))
    #expect(step.comparison == .verified)
}

@Test func anOfferGoogleAlreadyHoldsNeedsNoContentWrite() {
    let offer = Manifest.Offer(id: "trial", kind: .freeTrial, duration: "P1W")
    let actual = googleState { google in
        google.subscriptionIds = ["pro.monthly"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "pro.monthly"
        product.basePlanId = "monthly"
        product.offerStates = ["trial": "ACTIVE"]
        google.catalog["pro.monthly"] = product
    }

    #expect(!googleSteps(googleCatalogManifest(offers: [offer]), actual)
        .contains { $0.id == "google.subscriptionOffers.pro.monthly" })
}

@Test func aPriceThatGoogleAlreadySellsNeedsNoMigration() {
    let settled = googleState { google in
        google.subscriptionIds = ["pro.monthly"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "pro.monthly"
        product.basePlanId = "monthly"
        product.prices = ["US": "USD 4.99"]
        google.catalog["pro.monthly"] = product
    }
    let stale = googleState { google in
        google.subscriptionIds = ["pro.monthly"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "pro.monthly"
        product.basePlanId = "monthly"
        product.prices = ["US": "USD 2.99"]
        google.catalog["pro.monthly"] = product
    }

    #expect(!googleSteps(googleCatalogManifest(migrate: true), settled)
        .contains { $0.id == "google.migratePrices.pro.monthly" })
    #expect(googleSteps(googleCatalogManifest(migrate: true), stale)
        .contains { $0.id == "google.migratePrices.pro.monthly" })
}

// MARK: - The data safety row that no read can close

@Test func theDataSafetyRowSaysThatNoReadExists() throws {
    var manifest = googleManifest()
    manifest.review = Manifest.Review(dataSafetyAnswers: ["collectsLocation": true])

    let result = Planner.plan(Planner.Input(manifest: manifest, actual: ActualState(),
                                            stores: [.google]))
    let step = try #require(result.steps.first { $0.id == "google.dataSafety" })

    #expect(step.comparison == .unverified)
    #expect(result.findings.contains { $0.id == "plan.unreadable" })
}

// MARK: - The App Store catalog parsers

@Test func anApplePurchasePayloadParsesIntoTheComparableShape() throws {
    let product = try #require(AppleCatalogClient.parsePurchase(json("""
    {"id":"6001","attributes":{"productId":"com.example.pro","name":"Pro",
     "reviewNote":"Tap buy."}}
    """)))

    #expect(product.productId == "com.example.pro")
    #expect(product.id == "6001")
    #expect(product.name == "Pro")
    #expect(product.reviewNote == "Tap buy.")
}

@Test func anAppleSubscriptionPayloadCarriesItsDuration() throws {
    let product = try #require(AppleCatalogClient.parseSubscription(json("""
    {"id":"7001","attributes":{"productId":"pro.monthly","name":"Pro monthly",
     "subscriptionPeriod":"ONE_MONTH"}}
    """)))

    #expect(product.duration == "P1M")
    #expect(AppleCatalogClient.duration("ONE_YEAR") == "P1Y")
    #expect(AppleCatalogClient.duration("EVERY_OTHER_TUESDAY") == nil)
}

@Test func anApplePayloadWithoutAProductIdIsSkippedInsteadOfCrashing() {
    #expect(AppleCatalogClient.parsePurchase(json("{}")) == nil)
    #expect(AppleCatalogClient.parseSubscription(json("{}")) == nil)
}

@Test func theSubscriptionPricesJoinTheirTerritoryToTheirPricePoint() {
    let prices = AppleCatalogClient.subscriptionPrices(json("""
    {"data":[{"id":"p1","relationships":{
       "territory":{"data":{"id":"USA"}},
       "subscriptionPricePoint":{"data":{"id":"pt1"}}}}],
     "included":[{"type":"subscriptionPricePoints","id":"pt1",
                  "attributes":{"customerPrice":"9.99"}}]}
    """))

    #expect(prices == ["USA": "9.99"])
}

@Test func theGracePeriodDurationMapsBackToDays() {
    #expect(StateReader.gracePeriodDays("SIXTEEN_DAYS") == 16)
    #expect(StateReader.gracePeriodDays("THREE_DAYS") == 3)
    #expect(StateReader.gracePeriodDays(nil) == nil)
}

// MARK: - The writes that carry more than the diff can read

/// A page that Apple already holds still writes when the manifest carries the
/// localized text, because no read returns that text. The step says so.
@Test func aPageWithLocalizedTextKeepsItsStepAndSaysNobodyComparedIt() throws {
    var manifest = appleManifest()
    var marketing = Manifest.Marketing()
    marketing.customProductPages = [Manifest.Marketing.CustomProductPage(
        key: "spring", name: "Spring",
        locales: ["en-US": Manifest.Marketing.CustomProductPage.PageLocale(
            promotionalText: "Spring sale.")])]
    manifest.marketing = marketing
    let actual = appleState { apple in
        apple.customProductPageNames = ["Spring": "5001"]
    }

    let step = try #require(appleSteps(manifest, actual)
        .first { $0.id == "apple.customProductPages" })

    #expect(step.comparison == .unverified)
}

/// The review screenshot is an upload with no readable counterpart, so a
/// purchase that names one never claims to be verified.
@Test func aPurchaseWithAReviewScreenshotIsNeverCalledVerified() throws {
    var manifest = purchaseManifest()
    manifest.purchases?[0].reviewScreenshot = "media/review.png"
    let actual = appleState { apple in
        apple.purchaseIds = ["com.example.pro"]
        apple.catalog["com.example.pro"] = livePurchase()
    }

    let step = try #require(appleSteps(manifest, actual)
        .first { $0.id == "apple.purchases" })

    #expect(step.comparison == .unverified)
}

/// A decimal literal cannot hold 4.99 exactly. Both sides of the price diff
/// round to the same place, so a matching price never reads as a change.
@Test func aPriceLiteralCompareEqualToTheStringAppleReturns() {
    #expect(Planner.applePriceText(Price(amount: 4.99, currency: "USD"))
        == Planner.appleNormalizedPrice("4.99"))
    #expect(Planner.applePriceText(Price(amount: 0.99, currency: "USD"))
        == Planner.appleNormalizedPrice("0.99"))
    #expect(Planner.applePriceText(Price(amount: 4.99, currency: "USD"))
        != Planner.appleNormalizedPrice("2.99"))
}

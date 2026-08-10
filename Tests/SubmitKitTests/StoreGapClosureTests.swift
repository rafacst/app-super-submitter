import Foundation
import Testing
@testable import SubmitKit

private func input(_ manifest: Manifest, stores: Set<Store> = [.apple, .google],
                   actual: ActualState = ActualState()) -> Planner.Input {
    Planner.Input(manifest: manifest, actual: actual, stores: stores)
}

/// The gaps that the API coverage check found, each one held shut by a check.
///
/// Every test here failed before the fix. None of them checks a helper in
/// isolation: each one asks the planner or the manifest the same question the
/// developer asks, so a regression shows up as the wrong plan and not as a
/// wrong intermediate value.

// MARK: - The Mac App Store reaches RevenueCat

@Test func aMacAppStoreIdGetsItsOwnRevenueCatProduct() {
    var manifest = bothStores()
    manifest.apps.apple?.platforms = [.ios, .macOS]
    manifest.purchases = [Manifest.Purchase(id: "com.example.tip", kind: .consumable)]
    manifest.monetization = Manifest.Monetization(
        provider: .revenuecat,
        revenuecat: Manifest.Monetization.RevenueCat(
            projectId: "proj1",
            appIds: Manifest.Monetization.RevenueCat.AppIds(
                appStore: "app_ios", macAppStore: "app_mac", playStore: "app_play")))

    let ids = Planner.plan(input(manifest)).steps(for: .provider).map(\.id)

    #expect(ids.contains("provider.product.com.example.tip@app_store"))
    #expect(ids.contains("provider.product.com.example.tip@mac_app_store"))
    #expect(ids.contains("provider.product.com.example.tip@play_store"))
}

/// An empty id drops the row rather than sending a product to nowhere.
@Test func anEmptyMacAppStoreIdAddsNoStep() {
    var manifest = bothStores()
    manifest.purchases = [Manifest.Purchase(id: "com.example.tip", kind: .consumable)]
    manifest.monetization = Manifest.Monetization(
        provider: .revenuecat,
        revenuecat: Manifest.Monetization.RevenueCat(
            projectId: "proj1",
            appIds: Manifest.Monetization.RevenueCat.AppIds(appStore: "app_ios")))

    let ids = Planner.plan(input(manifest)).steps(for: .provider).map(\.id)

    #expect(ids.contains("provider.product.com.example.tip@app_store"))
    #expect(!ids.contains { $0.hasSuffix("@mac_app_store") })
}

@Test func aMacBuildWithoutTheMacAppStoreIdIsAWarning() {
    var manifest = bothStores()
    manifest.apps.apple?.platforms = [.ios, .macOS]
    manifest.monetization = Manifest.Monetization(
        provider: .revenuecat,
        revenuecat: Manifest.Monetization.RevenueCat(
            projectId: "proj1",
            appIds: Manifest.Monetization.RevenueCat.AppIds(appStore: "app_ios")))

    let findings = Planner.plan(input(manifest)).findings
    let warning = findings.first { $0.id == "rc.macAppStore" }

    #expect(warning?.severity == .warning)
    // An iOS-only app never sees the row.
    manifest.apps.apple?.platforms = [.ios]
    #expect(!Planner.plan(input(manifest)).findings.contains { $0.id == "rc.macAppStore" })
}

// MARK: - A one-time product that left the manifest stops selling

@Test func aGooglePurchaseThatLeftTheManifestStopsSellingAndIsNeverDeleted() {
    var manifest = bothStores()
    manifest.purchases = [Manifest.Purchase(id: "com.example.tip", kind: .consumable)]
    var google = ActualState.Google()
    google.oneTimeProductIds = ["com.example.tip", "com.example.old"]
    var actual = ActualState()
    actual.google = google

    let steps = Planner.plan(input(manifest, actual: actual)).steps(for: .google)
    let stop = steps.first { $0.id == "google.deactivate.com.example.old" }

    #expect(stop?.kind == .remove)
    #expect(stop?.operation == .googlePurchaseOptionState(
        productId: "com.example.old", purchaseOptionId: "com.example.old", active: false))
    // A delete would break an installed app, so no step ever sends one.
    #expect(stop?.requests.first?.method == "POST")
    #expect(!steps.contains { $0.id == "google.deactivate.com.example.tip" })
}

// MARK: - The TestFlight page of the app

@Test func theTestFlightPageTakesAStepAndDisappearsWhenAppleHoldsIt() {
    let page = Manifest.Release.TestFlight.Localization(
        description: "A beta of the new tab.", feedbackEmail: "beta@example.com")
    var manifest = bothStores()
    manifest.release?.apple = Manifest.Release.AppleRelease(
        testFlight: Manifest.Release.TestFlight(localizations: ["en-US": page]))

    #expect(Planner.plan(input(manifest)).steps(for: .apple)
        .contains { $0.id == "apple.betaAppLocalizations" })

    var apple = ActualState.Apple()
    apple.betaAppLocalizations = ["en-US": page]
    apple.betaAppLocalizationsRead = true
    var actual = ActualState()
    actual.apple = apple

    #expect(!Planner.plan(input(manifest, actual: actual)).steps(for: .apple)
        .contains { $0.id == "apple.betaAppLocalizations" })
}

/// A read that never happened is not a match. The step stays and it says so.
@Test func anUnreadTestFlightPageKeepsTheStepAndMarksItUnverified() {
    var manifest = bothStores()
    manifest.release?.apple = Manifest.Release.AppleRelease(
        testFlight: Manifest.Release.TestFlight(
            localizations: ["en-US": Manifest.Release.TestFlight.Localization(
                description: "A beta.")]))

    let step = Planner.plan(input(manifest)).steps(for: .apple)
        .first { $0.id == "apple.betaAppLocalizations" }

    #expect(step?.comparison == .unverified)
}

@Test func theBetaReviewContactTakesAStepWhenTheReviewBlockExists() {
    var manifest = bothStores()
    manifest.release?.apple = Manifest.Release.AppleRelease(
        testFlight: Manifest.Release.TestFlight(autoNotify: true))

    #expect(!Planner.plan(input(manifest)).steps(for: .apple)
        .contains { $0.id == "apple.betaReviewDetail" })

    manifest.review = Manifest.Review(contactEmail: "dev@example.com")

    #expect(Planner.plan(input(manifest)).steps(for: .apple)
        .contains { $0.id == "apple.betaReviewDetail" })
}

// MARK: - The subscription review controls

@Test func aSubscriptionReviewScreenshotKeepsTheCatalogStepAlive() {
    var manifest = bothStores()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro", groupName: "Pro",
        plans: [Manifest.SubscriptionGroup.Plan(
            id: "pro.monthly", duration: "P1M",
            reviewScreenshot: "metadata/review.png")])]

    var apple = ActualState.Apple()
    apple.subscriptionIds = ["pro.monthly"]
    apple.subscriptionGroupNames = ["Pro"]
    var product = ActualState.Apple.CatalogProduct()
    product.productId = "pro.monthly"
    product.duration = "P1M"
    apple.catalog = ["pro.monthly": product]
    var actual = ActualState()
    actual.apple = apple

    let step = Planner.plan(input(manifest, actual: actual)).steps(for: .apple)
        .first { $0.id == "apple.subscriptions" }

    // Nothing else differs, so without the screenshot the step would be gone.
    #expect(step != nil)
    #expect(step?.summary.contains("review screenshot") == true)
}

@Test func aSubscriptionTerritoryListIsComparedAndNotWrittenTwice() {
    var manifest = bothStores()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro", groupName: "Pro",
        plans: [Manifest.SubscriptionGroup.Plan(
            id: "pro.monthly", duration: "P1M", availableTerritories: ["USA", "DEU"],
            applePlanType: .monthly)])]

    var apple = ActualState.Apple()
    apple.subscriptionIds = ["pro.monthly"]
    apple.subscriptionGroupNames = ["Pro"]
    var product = ActualState.Apple.CatalogProduct()
    product.productId = "pro.monthly"
    product.duration = "P1M"
    product.subscriptionPlanTerritories[.monthly] = ["USA", "DEU"]
    product.subscriptionPlanAvailabilityRead = true
    apple.catalog = ["pro.monthly": product]
    var actual = ActualState()
    actual.apple = apple

    #expect(!Planner.plan(input(manifest, actual: actual)).steps(for: .apple)
        .contains { $0.id == "apple.subscriptions" })

    // One territory less on the store side, and the step returns.
    apple.catalog["pro.monthly"]?.subscriptionPlanTerritories[.monthly] = ["USA"]
    actual.apple = apple
    #expect(Planner.plan(input(manifest, actual: actual)).steps(for: .apple)
        .contains { $0.id == "apple.subscriptions" })
}

@Test func theSubscriptionReviewFieldsSurviveTheManifestRoundTrip() throws {
    var manifest = Manifest()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro", groupName: "Pro",
        plans: [Manifest.SubscriptionGroup.Plan(
            id: "pro.monthly", duration: "P1M",
            reviewScreenshot: "metadata/review.png",
            availableTerritories: ["USA"], applePlanType: .monthly)])]
    manifest.release = Manifest.Release(apple: Manifest.Release.AppleRelease(
        testFlight: Manifest.Release.TestFlight(
            localizations: ["en-US": Manifest.Release.TestFlight.Localization(
                description: "A beta.", feedbackEmail: "beta@example.com")])))

    let decoded = try ManifestFile.decode(ManifestFile.encode(manifest))
    let plan = decoded.subscriptions?.first?.plans.first

    #expect(plan?.reviewScreenshot == "metadata/review.png")
    #expect(plan?.availableTerritories == ["USA"])
    #expect(plan?.applePlanType == .monthly)
    #expect(decoded.release?.apple?.testFlight?.localizations?["en-US"]?.feedbackEmail
        == "beta@example.com")
}

// MARK: - The writers that had no code path at all

/// These four reach the store from a call site that no test can drive without
/// a live account, so the check is that the call exists and names the right
/// verb. A missing verb here is the exact defect the coverage check found.
@Test func everyClosedGapHasAWriterThatNamesItsVerb() throws {
    let apply = try source("Sources/SubmitKit/Run/AppleApply.swift")
    let subscriptions = try source("Sources/SubmitKit/Run/AppleSubscriptions.swift")
    let testFlight = try source("Sources/SubmitKit/Clients/AppleTestFlightClient.swift")
    let release = try source("Sources/SubmitKit/Release/ReleaseClient.swift")

    // A promotion turns off, not only on.
    #expect(apply.contains("DELETE\", \"/v1/promotedPurchases/"))
    // A dropped locale and a dropped device class both go.
    #expect(apply.contains("appleDropLocalizations"))
    #expect(apply.contains("appleDropMediaSets"))
    // The subscription half of the review controls.
    #expect(subscriptions.contains("/v1/subscriptionAppStoreReviewScreenshots"))
    #expect(subscriptions.contains("/v1/subscriptionPlanAvailabilities"))
    // The offers reconcile instead of stacking a duplicate every apply.
    #expect(subscriptions.contains("appleDropOffers"))
    #expect(subscriptions.contains("DELETE\", \"/v1/subscriptionPrices/"))
    // The TestFlight page and its review contact.
    #expect(testFlight.contains("/v1/betaAppLocalizations"))
    #expect(testFlight.contains("/v1/betaAppReviewDetails/"))
    // The subscriptions and the marketing items reach the review queue.
    #expect(release.contains("subscriptionVersion"))
    #expect(release.contains("subscriptionGroupVersion"))
    #expect(release.contains("appCustomProductPageVersion"))
    #expect(release.contains("appStoreVersionExperimentV2"))
    #expect(release.contains("\"appEvent\""))
}

/// The two take-back calls had no caller, and both views promised them.
@Test func theHaltAndTheCancelReachAButton() throws {
    let state = try source("Sources/SuperSubmitter/AppStateRun.swift")
    let tab = try source("Sources/SuperSubmitter/Tabs/ReleaseTab.swift")

    #expect(state.contains("haltGoogleRollout"))
    #expect(state.contains("cancelAppleSubmission"))
    #expect(tab.contains("undoRelease"))
    #expect(tab.contains("canUndoRelease"))
}

/// The provider choice moved off the Monetization tab. The catalog stayed.
@Test func theProviderChoiceLivesInSettingsAndNotOnTheMoneyTab() throws {
    let money = try source("Sources/SuperSubmitter/Tabs/MoneyTab.swift")
    let settings = try source("Sources/SuperSubmitter/Tabs/SettingsTab.swift")

    #expect(!money.contains("Manifest.Provider.revenuecat"))
    #expect(!money.contains("revenueCatAPIKey"))
    #expect(settings.contains("Manifest.Provider.revenuecat"))
    #expect(settings.contains("revenueCatAPIKey"))
    // The entitlements and the offerings belong to the catalog, so they stay.
    #expect(money.contains("providerCatalog"))
}

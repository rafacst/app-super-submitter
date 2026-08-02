import Foundation
import Testing
@testable import SubmitKit

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func source(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

@Test func removedGoogleCategoryCannotSilentlySurviveInTheManifest() throws {
    let manifest = try source("Sources/SubmitKit/Manifest/Manifest.swift")
    let editing = try source("Sources/SubmitKit/Manifest/ManifestEditing.swift")
    #expect(!manifest.contains("googleCategory"))
    #expect(!editing.contains("googleCategory"))
}

@Test func everyPreviouslyDeadReviewAndListingFieldHasAStoreWriter() throws {
    let apple = try source("Sources/SubmitKit/Run/AppleApply.swift")
    let google = try source("Sources/SubmitKit/Run/GoogleApply.swift")

    #expect(apple.contains("usesNonExemptEncryption"))
    #expect(apple.contains("privacyPolicyText"))
    #expect(apple.contains("privacyChoicesUrl"))
    #expect(apple.contains("appStoreReviewAttachments"))
    #expect(google.contains("contactWebsite"))
    #expect(google.contains("dataSafety"))
    #expect(google.contains("dataSafetyCSV"))
}

@Test func exactGoogleDataSafetyCSVSurvivesTheManifestRoundTrip() throws {
    var manifest = Manifest()
    manifest.review = Manifest.Review(dataSafetyCSV: "metadata/data-safety.csv")
    let decoded = try ManifestFile.decode(ManifestFile.encode(manifest))
    #expect(decoded.review?.dataSafetyCSV == "metadata/data-safety.csv")
}

@Test func pricingAvailabilityAndReleaseControlsReachApple() throws {
    let apple = try source("Sources/SubmitKit/Run/AppleApply.swift")
    let release = try source("Sources/SubmitKit/Release/ReleaseClient.swift")
    #expect(apple.contains("/v1/appPriceSchedules"))
    #expect(apple.contains("/v1/inAppPurchasePriceSchedules"))
    #expect(apple.contains("territoryAvailabilities"))
    #expect(release.contains("appStoreVersionReleaseRequests"))
    #expect(apple.contains("PAUSED"))
}

@Test func googleCatalogAndMediaAreFullyReconciled() throws {
    let google = try source("Sources/SubmitKit/Run/GoogleApply.swift")
    let planner = try source("Sources/SubmitKit/Plan/Planner.swift")
    #expect(google.contains("convertRegionPrices"))
    #expect(google.contains("DELETE"))
    #expect(planner.contains("featureGraphic"))
    #expect(planner.contains("media?.icon"))
}

@Test func appStoreMarketingPartialsHaveMediaAndDistinctOfferResources() throws {
    let manifest = try source("Sources/SubmitKit/Manifest/Manifest.swift")
    let subscriptions = try source("Sources/SubmitKit/Run/AppleSubscriptions.swift")
    let marketing = try source("Sources/SubmitKit/Run/AppleMarketing.swift")
    #expect(subscriptions.contains("subscriptionPromotionalOffers"))
    #expect(subscriptions.contains("winBackOffers"))
    #expect(manifest.contains("screenshots"))
    #expect(marketing.contains("Screenshots"))
    #expect(manifest.contains("advancedExperiences"))
}

@Test func uncertainPlanStepsAreExplicitInsteadOfPretendingToBeDiffs() throws {
    let planStep = try source("Sources/SubmitKit/Plan/PlanStep.swift")
    let planner = try source("Sources/SubmitKit/Plan/Planner.swift")
    #expect(planStep.contains("ComparisonConfidence"))
    #expect(planner.contains("unverified"))
}

@Test func schemaAndNativeAppProjectShipWithTheRepository() {
    #expect(FileManager.default.fileExists(atPath: repositoryRoot
        .appendingPathComponent("Sources/SubmitKit/Resources/store.schema.json").path))
    #expect(FileManager.default.fileExists(atPath: repositoryRoot
        .appendingPathComponent("project.yml").path))
    #expect(FileManager.default.fileExists(atPath: repositoryRoot
        .appendingPathComponent("SuperSubmitter.entitlements").path))
}

@Test func legacyGoogleCategoryIsDroppedWhenTheManifestIsSaved() throws {
    let decoded = try ManifestFile.decode("""
    version: 1
    apps: {}
    review:
      googleCategory: PRODUCTIVITY
      usesNonExemptEncryption: false
    """)
    let saved = try ManifestFile.encode(decoded)
    #expect(!saved.contains("googleCategory"))
    #expect(saved.contains("usesNonExemptEncryption"))
}

@Test func buildComplianceAndGoogleContactAreComparedBeforePlanning() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "123", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("https://example.com/support", locale: "en-US",
                            field: .supportURL)
    manifest.review = Manifest.Review(contactEmail: "dev@example.com",
                                      usesNonExemptEncryption: false)

    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.buildUsesNonExemptEncryption = false
    actual.apple = apple
    var google = ActualState.Google()
    google.contactEmail = "dev@example.com"
    google.contactWebsite = "https://example.com/support"
    actual.google = google

    let plan = Planner.plan(Planner.Input(manifest: manifest, actual: actual,
                                          stores: [.apple, .google]))
    #expect(!plan.steps.contains { $0.id == "apple.buildCompliance" })
    #expect(!plan.steps.contains { $0.id == "google.details" })
}

@Test func unreadableCatalogRowsSayTheyAreUnverified() throws {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "123", bundleID: "com.example.app")
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable)]

    let plan = Planner.plan(Planner.Input(manifest: manifest, actual: ActualState(),
                                          stores: [.apple]))
    let purchase = try #require(plan.steps.first { $0.id == "apple.purchases" })
    #expect(purchase.comparison == .unverified)
    #expect(purchase.summary.hasPrefix("unverified"))
    #expect(plan.warnings.contains { $0.id == "plan.unverified" })
}

@Test func releaseRequestLivesOnlyBehindTheIrreversibleReleaseClient() throws {
    let apply = try source("Sources/SubmitKit/Run/AppleApply.swift")
    let release = try source("Sources/SubmitKit/Release/ReleaseClient.swift")
    #expect(!apply.contains("appStoreVersionReleaseRequests"))
    #expect(release.contains("appStoreVersionReleaseRequests"))
}

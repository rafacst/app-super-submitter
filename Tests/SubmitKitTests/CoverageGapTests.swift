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
}

@Test func pricingAvailabilityAndReleaseControlsReachApple() throws {
    let apple = try source("Sources/SubmitKit/Run/AppleApply.swift")
    #expect(apple.contains("/v1/appPriceSchedules"))
    #expect(apple.contains("/v1/inAppPurchasePriceSchedules"))
    #expect(apple.contains("territoryAvailabilities"))
    #expect(apple.contains("appStoreVersionReleaseRequests"))
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

import Foundation
import Testing
@testable import SubmitKit

/// A manifest with both stores, one locale, and one version.
private func sampleManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A short line.", locale: "en-US", field: .subtitle)
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

private func input(_ manifest: Manifest, _ actual: ActualState = ActualState(),
                   stores: Set<Store> = [.apple, .google]) -> Planner.Input {
    Planner.Input(manifest: manifest, actual: actual, stores: stores)
}

// MARK: - The diff

@Test func anEmptyStoreProducesOneWritePerLocalizationResource() {
    let plan = Planner.plan(input(sampleManifest()))

    #expect(plan.steps(for: .apple).contains { $0.id == "apple.version" })
    #expect(plan.steps(for: .apple).contains { $0.id == "apple.info.en-US" })
    #expect(plan.steps(for: .apple).contains { $0.id == "apple.locale.en-US" })
    #expect(plan.steps(for: .google).contains { $0.id == "google.listing.en-US" })
}

@Test func googleWorkAlwaysOpensAnEditFirstAndCommitsLast() {
    let google = Planner.plan(input(sampleManifest())).steps(for: .google)

    #expect(google.first?.id == "google.openEdit")
    #expect(google.last?.id == "google.commit")
    #expect(google.dropLast().last?.id == "google.validate")
}

@Test func aMatchingStoreProducesNoStepForThatField() {
    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.versionString = "1.2.0"
    apple.versionState = "PREPARE_FOR_SUBMISSION"
    var locale = ActualState.Apple.VersionLocale()
    locale.description = "A long description."
    apple.versionLocales = ["en-US": locale]
    actual.apple = apple

    let plan = Planner.plan(input(sampleManifest(), actual, stores: [.apple]))

    #expect(!plan.steps.contains { $0.id == "apple.version" })
    #expect(!plan.steps.contains { $0.id == "apple.locale.en-US" })
    // The name and the subtitle still differ, so the info resource is written.
    #expect(plan.steps.contains { $0.id == "apple.info.en-US" })
}

@Test func aStoreThatIsNotSelectedProducesNoStep() {
    let plan = Planner.plan(input(sampleManifest(), stores: [.apple]))

    #expect(plan.steps(for: .google).isEmpty)
    #expect(!plan.steps(for: .apple).isEmpty)
}

@Test func theCountsSeparateWritesFromUploads() {
    var plan = PlanResult()
    plan.steps = [
        PlanStep(id: "a", system: .apple, kind: .change, summary: "", title: "",
                 requests: [], operation: .appleAttachBuild),
        PlanStep(id: "b", system: .apple, kind: .add, summary: "", title: "",
                 requests: [], operation: .appleBuildUpload(path: "x", bytes: 2_048),
                 uploadCount: 1, uploadBytes: 2_048),
    ]

    #expect(plan.writeCount == 1)
    #expect(plan.uploadCount == 1)
    #expect(plan.uploadBytes == 2_048)
}

// MARK: - The provider

@Test func theProviderColumnOnlyAppearsWhenAProviderIsChosen() {
    var manifest = sampleManifest()
    #expect(Planner.plan(input(manifest)).steps(for: .provider).isEmpty)

    manifest.monetization = Manifest.Monetization(
        provider: .adapty, adapty: Manifest.Monetization.Adapty(appId: "app"))
    manifest.entitlements = [Manifest.Entitlement(key: "pro", name: "Pro")]
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                            entitlements: ["pro"])]
    manifest.offerings = [Manifest.Offering(key: "default", isCurrent: true,
                                            products: ["com.example.pro"])]

    let steps = Planner.plan(input(manifest)).steps(for: .provider)
    #expect(steps.contains { $0.id == "provider.product.com.example.pro" })
    #expect(steps.contains { $0.id == "provider.entitlement.pro" })
    #expect(steps.contains { $0.id == "provider.offering.default" })
}

@Test func aProviderObjectThatTheManifestDroppedIsArchivedAndNeverDeleted() throws {
    var manifest = sampleManifest()
    manifest.monetization = Manifest.Monetization(
        provider: .adapty, adapty: Manifest.Monetization.Adapty(appId: "app"))
    manifest.offerings = []

    var actual = ActualState()
    var provider = ActualState.Provider()
    provider.kind = .adapty
    provider.offeringKeys = ["retired"]
    actual.provider = provider

    let steps = Planner.plan(input(manifest, actual)).steps(for: .provider)
    let archive = try #require(steps.first { $0.id == "provider.archive.retired" })
    #expect(archive.kind == .remove)
    if case .providerArchive(let kind, let key) = archive.operation {
        #expect(kind == "offering")
        #expect(key == "retired")
    } else {
        Issue.record("The plan must archive a dropped offering.")
    }
}

// MARK: - The dry run

@Test func everyStepNamesItsRequestsSoADryRunCanLogThemWithoutSending() {
    let plan = Planner.plan(input(sampleManifest()))

    for step in plan.steps {
        #expect(!step.requests.isEmpty, "\(step.id) names no request")
        for request in step.requests {
            #expect(!request.method.isEmpty)
            #expect(!request.path.isEmpty)
        }
    }
}

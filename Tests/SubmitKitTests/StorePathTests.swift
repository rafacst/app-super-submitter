import Foundation
import Testing
@testable import SubmitKit

private func everySource() throws -> String {
    let root = repositoryRoot.appendingPathComponent("Sources")
    guard let walker = FileManager.default.enumerator(at: root,
                                                      includingPropertiesForKeys: nil) else {
        Issue.record("The Sources directory could not be read.")
        return ""
    }
    var text = ""
    for case let url as URL in walker where url.pathExtension == "swift" {
        text += try String(contentsOf: url, encoding: .utf8)
    }
    return text
}

// MARK: - The paths that the published specifications do not declare
//
// Each string below reached a real store and returned a 404 error. The
// replacement path sits next to it, so a future edit that reintroduces the
// old spelling fails here first.

@Test func theAppStorePriceReadUsesTheAppRelationshipAndNotAV3Collection() throws {
    let text = try everySource()
    // App Store Connect declares /v3/appPricePoints/{id} and no collection.
    #expect(!text.contains("/v3/appPricePoints?"))
    #expect(text.contains("/appPricePoints?filter%5Bterritory%5D="))
}

@Test func theBuildBundleReadUsesAnIncludeAndNotASubPath() throws {
    let diagnostics = try source("Sources/SubmitKit/Clients/StoreDiagnostics.swift")
    #expect(!diagnostics.contains("/buildBundles?limit"))
    #expect(diagnostics.contains("?include=buildBundles"))
}

@Test func theAvailabilityAndExperimentReadsUseTheirDeclaredVersions() throws {
    let text = try everySource()
    #expect(!text.contains("/v2/apps/"))
    #expect(text.contains("/v1/apps/\\(appID)/appAvailabilityV2"))
    #expect(text.contains("appStoreVersionExperimentsV2"))
}

@Test func theExperimentTreatmentIsCreatedOnVersionOne() throws {
    let text = try everySource()
    #expect(!text.contains("\"/v2/appStoreVersionExperimentTreatments\""))
    #expect(text.contains("\"/v1/appStoreVersionExperimentTreatments\""))
}

@Test func thePurchaseVersionsReadUsesTheDeclaredRelationshipName() throws {
    let apply = try source("Sources/SubmitKit/Run/AppleApply.swift")
    #expect(!apply.contains("/inAppPurchaseVersions?limit"))
    #expect(apply.contains("/versions?limit=50"))
}

@Test func theGoogleOneTimeProductReadUsesTheDeclaredCamelCasePath() throws {
    let text = try everySource()
    // Google publishes the lower-case spelling for the patch method only, so
    // a lower-case list read answers 404 and the plan sees an empty catalog.
    #expect(!text.contains("/onetimeproducts"))
    #expect(text.contains("/oneTimeProducts"))
}

@Test func theHostedPurchaseContentWriteIsGoneBecauseAppleRemovedIt() throws {
    let apply = try source("Sources/SubmitKit/Run/AppleApply.swift")
    let planner = try source("Sources/SubmitKit/Plan/Planner.swift")
    // The comment that explains the removal may name the resource. The two
    // requests may not.
    #expect(!apply.contains("\"POST\", \"/v1/inAppPurchaseContents\""))
    #expect(!apply.contains("/v1/inAppPurchaseContents/"))
    #expect(!planner.contains("/v1/inAppPurchaseContents"))
}

@Test func theHostedContentKeyWarnsInsteadOfLookingLikeASuccessfulUpload() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                            content: "content/pro.zip")]

    let findings = Validator.offers(Planner.Input(manifest: manifest, actual: ActualState(),
                                                  stores: [.apple]))
    let warning = findings.first { $0.id == "purchase.content.com.example.pro" }

    #expect(warning?.severity == .warning)
    #expect(warning?.message.contains("no longer uploads hosted content") == true)
}

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

// MARK: - The reads that came back empty and were believed
//
// Each of these asked App Store Connect a real question and threw the answer
// away. None of them failed loudly: a `try?`, a missing `data` member, and a
// local flag stood in for the store, so the app reported "nothing there"
// about state the store was holding the whole time.

@Test func theAttachedBuildIsReadFromTheLinkageAndNotFromTheListRow() throws {
    let reader = try source("Sources/SubmitKit/Plan/StateReader.swift")
    // A list row carries `links` under every relationship and no `data`, so
    // this spelling read nil for every version of every app.
    #expect(!reader.contains("version[\"relationships\"][\"build\"][\"data\"]"))
    #expect(reader.contains("/relationships/build"))
}

@Test func onePricePointIsReadOnTheVersionAppleDeclares() throws {
    let text = try everySource()
    // Reading one point by id is v3. The v1 spelling answered 404, `try?` ate
    // it, and the price schedule was rewritten on every apply.
    #expect(!text.contains("/v1/appPricePoints/"))
    #expect(text.contains("manualPrices"))
    #expect(text.contains("filter%5Bterritory%5D="))
}

@Test func theCurrentPriceIsTheRowWithNoEndDate() {
    // Two territories and a price that stopped last month, which is what a
    // real schedule looks like. Only USA is asked for, and only the open row
    // is the price a customer pays.
    let payload = JSON(data: Data("""
    {"data":[
      {"type":"appPrices","attributes":{"endDate":"2026-02-28"},
       "relationships":{"appPricePoint":{"data":{"id":"old"}}}},
      {"type":"appPrices","attributes":{"endDate":null},
       "relationships":{"appPricePoint":{"data":{"id":"now"}}}}],
     "included":[
      {"type":"appPricePoints","id":"old","attributes":{"customerPrice":"9.99"}},
      {"type":"appPricePoints","id":"now","attributes":{"customerPrice":"4.99"}}]}
    """.utf8))

    #expect(StateReader.currentPrice(payload) == Decimal(string: "4.99"))
}

@Test func aPriceTheStoreAlreadySellsAtPlansNoWrite() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    // Apple sells at a point, so the apply writes 4.99 for this. Comparing
    // the 4.90 that was asked for planned a write that changed nothing, on
    // every run, forever.
    manifest.pricing = Manifest.Pricing(base: .init(amount: Decimal(string: "4.90")!,
                                                    currency: "USD", territory: "USA"))
    var apple = ActualState.Apple()
    apple.priceAmount = Decimal(string: "4.99")
    apple.currentPriceAmount = Decimal(string: "4.99")
    var actual = ActualState()
    actual.apple = apple

    let plan = Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))

    #expect(!plan.steps.contains { $0.id == "apple.appPrice" })
}

@Test func aFreeAppThatIsAlreadyFreePlansNoPriceWrite() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.pricing = Manifest.Pricing(base: .init(amount: 0, currency: "BRL",
                                                    territory: "BRA"))
    var apple = ActualState.Apple()
    apple.priceAmount = 0
    apple.currentPriceAmount = 0
    var actual = ActualState()
    actual.apple = apple

    let plan = Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))

    #expect(!plan.steps.contains { $0.id == "apple.appPrice" })
}

@Test func aPriceTheStoreDoesNotHoldStillPlansTheWrite() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.pricing = Manifest.Pricing(base: .init(amount: 4.90, currency: "USD",
                                                    territory: "USA"))
    var apple = ActualState.Apple()
    apple.priceAmount = Decimal(string: "4.99")
    apple.currentPriceAmount = Decimal(string: "9.99")
    var actual = ActualState()
    actual.apple = apple

    let plan = Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))

    #expect(plan.steps.contains { $0.id == "apple.appPrice" })
}

@Test func anAttachedBuildClosesTheReleaseChecklistRow() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    var apple = ActualState.Apple()
    apple.versionString = "1.5"
    apple.liveVersionString = "1.4"
    apple.attachedBuildId = "build-id"
    var actual = ActualState()
    actual.apple = apple

    let rows = ConsoleChecklist.rows(manifest: manifest, actual: actual, stores: [.apple])
    let build = rows.first { $0.id == "apple.updateBuild" }

    #expect(build?.state == .done)
    #expect(build?.reason.contains("a build is attached") == true)
}

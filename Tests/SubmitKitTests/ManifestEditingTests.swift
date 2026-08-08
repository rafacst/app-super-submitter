import Foundation
import Testing
@testable import SubmitKit

@Test func storeSelectionCreatesAndRemovesOnlyThatStore() {
    var manifest = Manifest()

    manifest.setStore(.apple, enabled: true)
    #expect(manifest.apps.apple?.platforms == [.ios])
    #expect(manifest.apps.google == nil)

    manifest.setStore(.google, enabled: true)
    #expect(manifest.apps.google?.packageName == "")

    manifest.setStore(.apple, enabled: false)
    #expect(manifest.apps.apple == nil)
    #expect(manifest.apps.google != nil)
}

@Test func addingALocaleCreatesTheListingAndDoesNotReplaceExistingText() {
    var manifest = Manifest()
    manifest.addLocale("en-US", name: "First name")
    manifest.addLocale("en-US", name: "Replacement")
    manifest.addLocale("pt-BR")

    #expect(manifest.listing?.defaultLocale == "en-US")
    #expect(manifest.listing?.locales["en-US"]?.name == "First name")
    #expect(manifest.listing?.locales["pt-BR"] != nil)
}

@Test func aDroppedPackageUpdatesTheBuildAndPrefillsOnlyMissingValues() {
    var manifest = Manifest()
    manifest.setStore(.apple, enabled: true)
    var package = AppPackage(kind: .ipa, url: URL(fileURLWithPath: "/repo/build/App.ipa"))
    package.identifier = "com.example.app"
    package.versionName = "3.2.0"
    package.appName = "Example"
    package.locales = ["en-US", "pt-BR"]

    manifest.apply(package: package, path: "build/App.ipa")

    #expect(manifest.release?.build?.ios == "build/App.ipa")
    #expect(manifest.release?.versionName == "3.2.0")
    #expect(manifest.apps.apple?.bundleId == "com.example.app")
    #expect(manifest.listing?.locales["en-US"]?.name == "Example")
    #expect(manifest.listing?.locales["pt-BR"] != nil)
}

@Test func importedStoreListingsMergeWithoutDiscardingAppleSpecificText() {
    var manifest = Manifest()
    var apple = ImportedStoreListing()
    var appleLocale = ImportedStoreListing.Locale()
    appleLocale.name = "Shared name"
    appleLocale.subtitle = "Apple subtitle"
    appleLocale.description = "Shared description"
    appleLocale.keywords = "apple,only"
    apple.locales["en-US"] = appleLocale
    apple.versionName = "3.2.0"
    manifest.mergeAppleImport(apple)

    var google = ImportedStoreListing()
    var googleLocale = ImportedStoreListing.Locale()
    googleLocale.name = "Shared name"
    googleLocale.subtitle = "A longer Google description"
    googleLocale.description = "Shared description"
    googleLocale.video = "https://youtube.com/watch?v=test"
    google.locales["en-US"] = googleLocale
    manifest.mergeGoogleImport(google)

    let locale = manifest.listing?.locales["en-US"]
    #expect(locale?.keywords.value == "apple,only")
    #expect(locale?.google?.shortDescription.value == "A longer Google description")
    #expect(locale?.google?.video.value == "https://youtube.com/watch?v=test")
    #expect(manifest.release?.versionName == "3.2.0")
}

@Test func importedListingCarriesPrivacyFieldsAndDownloadableMedia() {
    var manifest = Manifest()
    var imported = ImportedStoreListing()
    var locale = ImportedStoreListing.Locale()
    locale.name = "Example"
    locale.privacyPolicyText = "Privacy details"
    locale.privacyChoicesURL = "https://example.com/choices"
    imported.locales["en-US"] = locale
    imported.assets = [ImportedStoreAsset(
        locale: "en-US", kind: "phoneScreenshots",
        url: URL(string: "https://example.com/phone.png")!, fileName: "phone.png")]

    manifest.mergeAppleImport(imported)

    #expect(manifest.listingText(locale: "en-US", field: .privacyPolicyText) == "Privacy details")
    #expect(manifest.listingText(locale: "en-US", field: .privacyChoicesURL)
            == "https://example.com/choices")
    #expect(imported.assets[0].deviceClass == .phone)
}

@Test func everySupportedRemoteImageTypeMapsToAManifestBucket() {
    let types = ["phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots",
                 "tvScreenshots", "wearScreenshots", "APP_IPHONE_67",
                 "APP_IPAD_PRO_3GEN_129", "APP_APPLE_TV"]
    for kind in types {
        let asset = ImportedStoreAsset(locale: "en-US", kind: kind,
            url: URL(string: "https://example.com/image.png")!, fileName: "image.png")
        #expect(asset.deviceClass != nil)
    }
}

@Test func googleAppDiscoveryIsAvailableWithoutKnowingAPackageName() {
    let client = StoreConnectionClient()
    let operation: @Sendable (GoogleServiceAccount) async throws -> [RemoteStoreApp]
        = client.googleApps
    _ = operation
}

@Test func aGoogleServiceAccountReadsTheOfficialJSONKeys() throws {
    let data = Data(#"""
    {
      "project_id": "demo-project",
      "private_key_id": "key-id",
      "private_key": "-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----\n",
      "client_email": "submitter@example.iam.gserviceaccount.com",
      "token_uri": "https://oauth2.googleapis.com/token"
    }
    """#.utf8)

    let credential = try GoogleServiceAccount(data: data, fileName: "service.json")
    #expect(credential.projectID == "demo-project")
    #expect(credential.clientEmail == "submitter@example.iam.gserviceaccount.com")
    #expect(credential.fileName == "service.json")
}

@Test func listingFieldsAndGoogleOverridesRoundTripThroughEditingHelpers() {
    var manifest = Manifest()
    manifest.setListingText("Shared subtitle", locale: "en-US", field: .subtitle)
    manifest.setGoogleOverride(true, locale: "en-US", field: .googleShortDescription)
    manifest.setListingText("Longer Google subtitle", locale: "en-US",
                            field: .googleShortDescription)

    #expect(manifest.listingText(locale: "en-US", field: .subtitle) == "Shared subtitle")
    #expect(manifest.hasGoogleOverride(locale: "en-US", field: .googleShortDescription))
    #expect(manifest.listingText(locale: "en-US", field: .googleShortDescription)
            == "Longer Google subtitle")

    manifest.setGoogleOverride(false, locale: "en-US", field: .googleShortDescription)
    #expect(!manifest.hasGoogleOverride(locale: "en-US", field: .googleShortDescription))
}

@Test func mediaPathsCanBeAddedWithoutDuplicatesAndRemoved() {
    var manifest = Manifest()
    manifest.addMediaPaths(["shots/one.png", "shots/one.png", "shots/two.png"],
                           locale: "en-US", deviceClass: .phone)
    manifest.addMediaPaths(["previews/demo.mov"], locale: "en-US",
                           deviceClass: .phone, previews: true)

    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone)
            == ["shots/one.png", "shots/two.png"])
    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone, previews: true)
            == ["previews/demo.mov"])

    manifest.removeMediaPath("shots/one.png", locale: "en-US", deviceClass: .phone)
    manifest.removeMediaPath("previews/demo.mov", locale: "en-US",
                             deviceClass: .phone, previews: true)
    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone) == ["shots/two.png"])
    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone, previews: true).isEmpty)
}

@Test func reviewAnswersAndCategoriesSurviveManifestCoding() throws {
    var manifest = Manifest()
    manifest.setReviewText("Games", field: .applePrimaryCategory)
    // Apple's questionnaire mixes enum strings and flags, so both shapes have
    // to survive the round trip in the same map.
    manifest.review?.ageRatingAnswers = [
        "violenceCartoonOrFantasy": .text("INFREQUENT_OR_MILD"),
        "unrestrictedWebAccess": .flag(false),
    ]
    manifest.review?.dataSafetyAnswers = ["data_encrypted_in_transit": true]
    manifest.review?.usesNonExemptEncryption = true

    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(Manifest.self, from: data)
    #expect(decoded.reviewText(.applePrimaryCategory) == "Games")
    #expect(decoded.review?.ageRatingAnswers?["violenceCartoonOrFantasy"]
            == .text("INFREQUENT_OR_MILD"))
    #expect(decoded.review?.ageRatingAnswers?["unrestrictedWebAccess"] == .flag(false))
    #expect(decoded.review?.dataSafetyAnswers?["data_encrypted_in_transit"] == true)
    #expect(decoded.review?.usesNonExemptEncryption == true)
}

@Test func screenshotDimensionsAreValidatedForTheSelectedBucketAndStores() throws {
    try AssetInspector.validateDimensions(
        ImageAssetInfo(width: 1242, height: 2208, fileSize: 1),
        deviceClass: .phone, stores: [.apple, .google])
    #expect(try AssetInspector.compatibleStores(
        for: ImageAssetInfo(width: 1290, height: 2796, fileSize: 1),
        deviceClass: .phone, selectedStores: [.apple, .google]) == [.apple])
    #expect(try AssetInspector.compatibleStores(
        for: ImageAssetInfo(width: 1080, height: 1920, fileSize: 1),
        deviceClass: .phone, selectedStores: [.apple, .google]) == [.google])
    try AssetInspector.validateDimensions(
        ImageAssetInfo(width: 1080, height: 1920, fileSize: 1),
        deviceClass: .phone, stores: [.google])

    #expect(throws: AssetInspectionError.self) {
        try AssetInspector.validateDimensions(
            ImageAssetInfo(width: 1000, height: 1000, fileSize: 1),
            deviceClass: .phone, stores: [.apple])
    }
    #expect(throws: AssetInspectionError.self) {
        try AssetInspector.validateDimensions(
            ImageAssetInfo(width: 400, height: 500, fileSize: 1),
            deviceClass: .watch, stores: [.google])
    }
}

@Test func listingValidationChecksEveryLocaleAndRespectsGoogleOverrides() {
    var manifest = Manifest()
    manifest.setListingText("Valid", locale: "en-US", field: .keywords)
    manifest.setListingText(String(repeating: "x", count: 101),
                            locale: "pt-BR", field: .keywords)
    #expect(manifest.listingErrorCount(for: [.apple, .google]) == 1)

    manifest.setListingText(String(repeating: "s", count: 40),
                            locale: "en-US", field: .subtitle)
    #expect(manifest.listingErrorCount(for: [.apple, .google]) == 2)
    manifest.setGoogleOverride(true, locale: "en-US", field: .googleShortDescription)
    #expect(manifest.listingErrorCount(for: [.google]) == 0)
}

@Test func priceDraftsClearOrRejectInsteadOfSilentlyKeepingAnOldPrice() {
    #expect(PriceDraft.resolve(amount: "", currency: "USD") == .empty)
    #expect(PriceDraft.resolve(amount: "four", currency: "USD")
            == .invalid("The price must be a valid decimal amount."))
    #expect(PriceDraft.resolve(amount: "4.99", currency: "usd", territory: "us")
            == .valid(Price(amount: Decimal(string: "4.99")!, currency: "USD", territory: "US")))
}

@Test func newCatalogRowsContainNoInventedStoreData() {
    let purchase = Manifest.Purchase(id: "", kind: .nonConsumable)
    #expect(purchase.id.isEmpty)
    #expect(purchase.name == nil)
    #expect(purchase.price == nil)

    let group = Manifest.SubscriptionGroup(groupId: "")
    #expect(group.groupId.isEmpty)
    #expect(group.groupName == nil)
    #expect(group.plans.isEmpty)

    let plan = Manifest.SubscriptionGroup.Plan(id: "", duration: "")
    #expect(plan.id.isEmpty)
    #expect(plan.duration.isEmpty)
    #expect(plan.basePlanId == nil)
    #expect(plan.price == nil)

    let entitlement = Manifest.Entitlement(key: "")
    #expect(entitlement.key.isEmpty)
    #expect(entitlement.name == nil)

    let offering = Manifest.Offering(key: "", isCurrent: true, products: [])
    #expect(offering.key.isEmpty)
    #expect(offering.name == nil)
    #expect(offering.products?.isEmpty == true)
    #expect(offering.isCurrent == true)
}

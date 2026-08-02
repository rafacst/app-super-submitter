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

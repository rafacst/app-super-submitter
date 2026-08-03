import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The import runs before any store read, so a freshly imported app must
/// already know what its stores hold.
@Test func theImportFillsTheSnapshotForBothStores() {
    var listing = ImportedStoreListing()
    var locale = ImportedStoreListing.Locale()
    locale.description = "The App Store description"
    locale.subtitle = "A subtitle"
    listing.locales["en-US"] = locale
    listing.assets = [
        ImportedStoreAsset(locale: "en-US", kind: "APP_IPHONE_67",
                           url: URL(string: "https://example.com/a.png")!, fileName: "a.png"),
        ImportedStoreAsset(locale: "en-US", kind: "APP_IPHONE_67",
                           url: URL(string: "https://example.com/a.mov")!, fileName: "a.mov"),
    ]

    var google = ImportedStoreListing()
    var googleLocale = ImportedStoreListing.Locale()
    googleLocale.description = "The Play description"
    googleLocale.subtitle = "The short description"
    google.locales["en-US"] = googleLocale
    google.googleReleaseNotes["en-US"] = "Fixes"
    google.assets = [ImportedStoreAsset(locale: "en-US", kind: "phoneScreenshots",
                                        url: URL(string: "https://example.com/g.png")!,
                                        fileName: "g.png")]

    var snapshot = StoreSnapshot()
    snapshot.merge(listing, store: .apple)
    snapshot.merge(google, store: .google)

    // Both stores answer for the same field, App Store first.
    let descriptions = snapshot.text(.description, locale: "en-US")
    #expect(descriptions.map(\.store) == [.apple, .google])
    #expect(descriptions.map(\.value) == ["The App Store description", "The Play description"])
    #expect(snapshot.text(.subtitle, locale: "en-US").map(\.value) == ["A subtitle"])
    #expect(snapshot.text(.googleShortDescription, locale: "en-US").map(\.value)
            == ["The short description"])
    #expect(snapshot.text(.googleWhatsNew, locale: "en-US").map(\.value) == ["Fixes"])

    // A video and an image share one Apple bucket. The extension splits them.
    #expect(snapshot.screenshots(locale: "en-US", deviceClass: .phone).count == 2)
    #expect(snapshot.screenshots(locale: "en-US", deviceClass: .phone)[0].urls.count == 1)
    #expect(snapshot.previews(locale: "en-US", deviceClass: .phone).count == 1)
    #expect(snapshot.text(.description, locale: "pt-BR").isEmpty)
}

/// A store read covers apps that were never imported, and it refreshes an
/// imported app after the developer edits.
@Test func aStoreReadFillsTheSnapshotFromTheReadState() {
    var actual = ActualState()
    var apple = ActualState.Apple()
    var info = ActualState.Apple.InfoLocale()
    info.name = "Example"
    info.subtitle = "A subtitle"
    apple.infoLocales["en-US"] = info
    var version = ActualState.Apple.VersionLocale()
    version.description = "The live description"
    version.keywords = "one,two"
    apple.versionLocales["en-US"] = version
    apple.screenshotURLs["en-US/APP_IPHONE_67"] = [URL(string: "https://example.com/1.png")!]
    apple.previewURLs["en-US/APP_IPHONE_67"] = [URL(string: "https://example.com/1.mov")!]
    actual.apple = apple

    var google = ActualState.Google()
    var listing = ActualState.Google.Listing()
    listing.fullDescription = "The live Play description"
    google.listings["en-US"] = listing
    google.imageURLs["en-US/tenInchScreenshots"] = [URL(string: "https://example.com/t.png")!]
    actual.google = google

    var snapshot = StoreSnapshot()
    snapshot.merge(actual)

    #expect(snapshot.text(.description, locale: "en-US").map(\.value)
            == ["The live description", "The live Play description"])
    #expect(snapshot.text(.name, locale: "en-US").map(\.value) == ["Example"])
    #expect(snapshot.text(.keywords, locale: "en-US").map(\.value) == ["one,two"])
    // The stores key media "locale/bucket". Both buckets land on a device class.
    #expect(snapshot.screenshots(locale: "en-US", deviceClass: .phone).map(\.store) == [.apple])
    #expect(snapshot.screenshots(locale: "en-US", deviceClass: .tablet10).map(\.store) == [.google])
    #expect(snapshot.previews(locale: "en-US", deviceClass: .phone).count == 1)
}

@Test func anUnknownStoreBucketIsDroppedRatherThanGuessed() {
    #expect(Manifest.DeviceClass(storeBucket: "APP_IPHONE_67") == .phone)
    #expect(Manifest.DeviceClass(storeBucket: "sevenInchScreenshots") == .tablet7)
    #expect(Manifest.DeviceClass(storeBucket: "APP_WATCH_ULTRA_9000") == nil)

    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.screenshotURLs["en-US/APP_SOMETHING_NEW"] = [URL(string: "https://example.com/x.png")!]
    actual.apple = apple
    var snapshot = StoreSnapshot()
    snapshot.merge(actual)

    #expect(snapshot.screenshots.isEmpty)
}

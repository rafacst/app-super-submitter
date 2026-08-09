import Foundation
import SubmitKit
import SwiftUI
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

/// Grey on a field means "sending this changes nothing". The tab may only say
/// it when every store that holds the field holds this exact text.
@Test func aFieldIsUnchangedOnlyWhenEveryStoreAgreesWithIt() {
    var apple = ImportedStoreListing()
    var appleLocale = ImportedStoreListing.Locale()
    appleLocale.description = "The same words"
    appleLocale.subtitle = "A subtitle"
    apple.locales["en-US"] = appleLocale

    var google = ImportedStoreListing()
    var googleLocale = ImportedStoreListing.Locale()
    googleLocale.description = "The same words"
    google.locales["en-US"] = googleLocale

    var snapshot = StoreSnapshot()
    snapshot.merge(apple, store: .apple)
    snapshot.merge(google, store: .google)

    #expect(snapshot.isUnchanged(.description, locale: "en-US", value: "The same words"))
    #expect(!snapshot.isUnchanged(.description, locale: "en-US", value: "New words"))
    // One store that differs is one write the run still makes.
    snapshot.merge(differentGoogleDescription(), store: .google)
    #expect(!snapshot.isUnchanged(.description, locale: "en-US", value: "The same words"))
    // A field no store holds claims nothing, so it is never grey.
    #expect(!snapshot.isUnchanged(.keywords, locale: "en-US", value: ""))
    #expect(!snapshot.isUnchanged(.subtitle, locale: "pt-BR", value: "A subtitle"))
}

private func differentGoogleDescription() -> ImportedStoreListing {
    var listing = ImportedStoreListing()
    var locale = ImportedStoreListing.Locale()
    locale.description = "Other words"
    listing.locales["en-US"] = locale
    return listing
}

/// The grey survives a quit. Without the file, a reopened workspace showed
/// every field black until somebody ran a read, which claims the developer
/// changed text they never touched.
@Test func theSnapshotSurvivesARelaunchAndBelongsToOneApp() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    var listing = ImportedStoreListing()
    var locale = ImportedStoreListing.Locale()
    locale.description = "The live description"
    listing.locales["en-US"] = locale
    listing.assets = [ImportedStoreAsset(locale: "en-US", kind: "APP_IPHONE_69",
                                         url: URL(string: "https://example.com/a.png")!,
                                         fileName: "a.png")]
    var snapshot = StoreSnapshot()
    snapshot.merge(listing, store: .apple)
    snapshot.save(toRoot: folder)

    let reloaded = StoreSnapshot.load(fromRoot: folder)
    #expect(reloaded.text(.description, locale: "en-US").map(\.value) == ["The live description"])
    #expect(reloaded.screenshots(locale: "en-US", deviceClass: .phone).count == 1)
    #expect(reloaded.isUnchanged(.description, locale: "en-US", value: "The live description"))

    // Another app has its own folder and therefore its own picture.
    #expect(StoreSnapshot.load(fromRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-\(UUID().uuidString)")).isEmpty)
}

/// The App Store answers twice and the two answers mean different things.
///
/// The draft is what a run patches, so it decides "Kept". The live version is
/// what a customer reads, and App Store Connect leaves the draft empty, so
/// reading the draft alone reported an app with no description while its store
/// page was full. Both are kept, and only the draft is allowed near "Kept".
@Test func theLiveTextIsShownWithoutClaimingTheDraftHoldsIt() {
    var actual = ActualState()
    var apple = ActualState.Apple()
    var draft = ActualState.Apple.VersionLocale()
    draft.description = ""
    draft.keywords = "atproto,deck"
    apple.versionLocales["en-US"] = draft
    var live = ActualState.Apple.VersionLocale()
    live.description = "The words the customer reads"
    live.keywords = "atproto,deck"
    apple.liveVersionLocales["en-US"] = live
    actual.apple = apple

    var snapshot = StoreSnapshot()
    snapshot.merge(actual)

    // The tab can print what the store serves.
    #expect(snapshot.liveOnAppStore(.description, locale: "en-US")
            == "The words the customer reads")
    // The draft holds none of it, so the run writes it and the chip must not
    // say the field is kept.
    #expect(!snapshot.isUnchanged(.description, locale: "en-US",
                                  value: "The words the customer reads"))
    // A field the two agree on says nothing twice.
    #expect(snapshot.liveOnAppStore(.keywords, locale: "en-US") == nil)
    #expect(snapshot.isUnchanged(.keywords, locale: "en-US", value: "atproto,deck"))
    #expect(snapshot.liveOnAppStore(.description, locale: "pt-BR") == nil)
}

/// The fields stop at the store's limit while the developer types, and they
/// still never shorten what is already there. Section 7 of context.md: the app
/// never truncates text.
@Test func aFieldRefusesGrowthPastTheLimitAndShortensNothing() {
    var value = "12345"
    let field = Binding(get: { value }, set: { value = $0 })
    let limited = field.limited(to: 8)

    limited.wrappedValue = "12345678"
    #expect(value == "12345678")
    // One character past the limit is refused, and the text stands.
    limited.wrappedValue = "123456789"
    #expect(value == "12345678")

    // A value that arrives over the limit stays whole, because an import and a
    // paste both land this way and neither may lose a word.
    value = "an imported description that is far too long"
    #expect(limited.wrappedValue == "an imported description that is far too long")
    // And it can always be edited back down.
    limited.wrappedValue = "an imported description that is far too lon"
    #expect(value == "an imported description that is far too lon")

    // No limit means no interference.
    let free = field.limited(to: Int?.none)
    free.wrappedValue = String(repeating: "x", count: 5_000)
    #expect(value.count == 5_000)
}

/// A store id holds one line, and the field that takes one refuses a break.
///
/// Return puts a line break into a SwiftUI text field on macOS rather than
/// ending the edit, and an id copied out of a web console arrives with one on
/// the end. Either way the field editor scrolls to a second, empty line and the
/// id reads as cut in half, and the store receives a credential with a break
/// in it.
///
/// The order is the half that is easy to get wrong, so it is the half this
/// pins: the break comes out first, and the length is counted after. The other
/// way round, a 36 character issuer id pasted with a newline is 37 characters
/// and the limit refuses the whole paste.
@Test func anIdFieldTakesOneLineAndCountsItAfterTheBreakIsGone() {
    var value = ""
    let field = Binding(get: { value }, set: { value = $0 })
    let entry = field.limited(to: AppleCredential.issuerIDLength).oneLine

    // A Return pressed in the middle of an issuer id.
    entry.wrappedValue = "fc9538f3-8694\n"
    #expect(value == "fc9538f3-8694")

    // The paste the limit alone used to refuse whole: 36 characters of issuer
    // id, and a newline the console put on the end.
    entry.wrappedValue = "fc9538f3-8694-455f-b34f-50a9053d4d4a\n"
    #expect(value == "fc9538f3-8694-455f-b34f-50a9053d4d4a")
    #expect(value.count == AppleCredential.issuerIDLength)

    // The limit still holds for real text past it.
    entry.wrappedValue = "fc9538f3-8694-455f-b34f-50a9053d4d4a0"
    #expect(value == "fc9538f3-8694-455f-b34f-50a9053d4d4a")
}

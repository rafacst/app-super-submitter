import Foundation
import Testing
@testable import SubmitKit

/// One press that gives the store added second what the first one has.
///
/// `store.yaml` holds one name, one description and one catalog for both
/// stores, so most of a listing needs no copy. What does is what the file
/// leaves to the store, the two fields Google Play takes its own words for,
/// the pictures, and the icon.

private let appleSizes: [String: ImageAssetInfo] = [
    "Store Import/apple/en-US/APP_IPHONE_67/1.png": .init(width: 1320, height: 2868, fileSize: 1),
    "Store Import/apple/en-US/APP_IPHONE_67/2.png": .init(width: 1320, height: 2868, fileSize: 1),
    "Store Import/apple/en-US/APP_IPHONE_55/1.png": .init(width: 1242, height: 2208, fileSize: 1),
    "Store Import/apple/en-US/APP_IPHONE_55/2.png": .init(width: 1242, height: 2208, fileSize: 1),
    "Store Import/apple/en-US/APP_IPHONE_55/3.png": .init(width: 1242, height: 2208, fileSize: 1),
    "Store Import/apple/en-US/APP_DESKTOP/1.png": .init(width: 2880, height: 1800, fileSize: 1),
    "Store Import/apple/en-US/icon/icon.png": .init(width: 512, height: 512, fileSize: 1),
    "Store Import/google/en-US/phoneScreenshots/1.png": .init(width: 1080, height: 1920, fileSize: 1),
    "Store Import/google/en-US/phoneScreenshots/2.png": .init(width: 1242, height: 2208, fileSize: 1),
    "Media/big-icon.png": .init(width: 1024, height: 1024, fileSize: 1),
]

private func size(_ path: String) -> ImageAssetInfo? { appleSizes[path] }

private func twoStores() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US")
    return manifest
}

// MARK: - The text

/// A field the file leaves alone keeps what the App Store holds, so that is
/// what Google Play gets. A field the file already holds reaches both stores
/// and is not copied again.
@Test func aSilentSharedFieldTakesTheSourceStoresText() {
    var manifest = twoStores()
    manifest.setListingText("Held by the file", locale: "en-US", field: .description)
    let live = StoreCopySource(text: ["en-US": [.name: "Example", .description: "From the store"]])

    let report = manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(manifest.listingText(locale: "en-US", field: .name) == "Example")
    #expect(manifest.listingText(locale: "en-US", field: .description) == "Held by the file")
    #expect(report.copied == ["en-US · Name"])
}

/// Google Play reads the subtitle once its own box is off, so the copy turns
/// the box off rather than writing the same words twice.
@Test func theSubtitleBecomesTheGoogleShortDescription() {
    var manifest = twoStores()
    manifest.setListingText("Play's own words", locale: "en-US", field: .googleShortDescription)
    let live = StoreCopySource(text: ["en-US": [.subtitle: "Plan the week"]])

    let report = manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(manifest.listingText(locale: "en-US", field: .subtitle) == "Plan the week")
    #expect(!manifest.hasGoogleOverride(locale: "en-US", field: .googleShortDescription))
    #expect(report.copied == ["en-US · Short description"])
}

/// Google Play takes 500 characters of release notes and the App Store takes
/// 4000. A longer text is left alone and named, and never shortened.
@Test func aReleaseNoteTooLongForGooglePlayIsLeftAlone() {
    var manifest = twoStores()
    manifest.setListingText(String(repeating: "a", count: 612), locale: "en-US", field: .whatsNew)
    manifest.setListingText("Bug fixes", locale: "en-US", field: .googleWhatsNew)

    let report = manifest.copyStore(from: .apple, to: .google, live: StoreCopySource(),
                                    imageSize: size)

    #expect(manifest.listingText(locale: "en-US", field: .googleWhatsNew) == "Bug fixes")
    #expect(report.copied.isEmpty)
    #expect(report.skipped.contains { $0.hasPrefix("en-US · Release notes") && $0.contains("612") })
}

/// The other way. A short description that fits the App Store's 30 becomes
/// the subtitle, and Google goes on reading the same words from it.
@Test func aShortDescriptionThatFitsBecomesTheSubtitle() {
    var manifest = twoStores()
    manifest.setListingText("Apple's own", locale: "en-US", field: .subtitle)
    manifest.setListingText("Plan the week", locale: "en-US", field: .googleShortDescription)
    manifest.setListingText("Fixed the sync", locale: "en-US", field: .googleWhatsNew)

    let report = manifest.copyStore(from: .google, to: .apple, live: StoreCopySource(),
                                    imageSize: size)

    #expect(manifest.listingText(locale: "en-US", field: .subtitle) == "Plan the week")
    #expect(manifest.listingText(locale: "en-US", field: .whatsNew) == "Fixed the sync")
    #expect(!manifest.hasGoogleOverride(locale: "en-US", field: .googleShortDescription))
    #expect(!manifest.hasGoogleOverride(locale: "en-US", field: .googleWhatsNew))
    #expect(report.copied == ["en-US · Subtitle, What is new"])
}

@Test func aShortDescriptionTooLongForTheSubtitleIsLeftAlone() {
    var manifest = twoStores()
    let long = "Plan every week of the year in one calm place"
    manifest.setListingText(long, locale: "en-US", field: .googleShortDescription)

    let report = manifest.copyStore(from: .google, to: .apple, live: StoreCopySource(),
                                    imageSize: size)

    #expect(manifest.listingText(locale: "en-US", field: .subtitle).isEmpty)
    #expect(manifest.listingText(locale: "en-US", field: .googleShortDescription) == long)
    #expect(report.skipped.contains { $0.hasPrefix("en-US · Subtitle") })
}

/// A field cleared on purpose is an answer, and the store's text does not
/// come back over it.
@Test func aClearedFieldIsNotFilledAgain() {
    var manifest = twoStores()
    manifest.listing?.locales["en-US"]?.subtitle = .clear
    let before = manifest
    let live = StoreCopySource(text: ["en-US": [.subtitle: "From the store"]])

    manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(manifest == before)
}

@Test func aSourceWithNothingChangesNothing() {
    var manifest = twoStores()
    let before = manifest

    let report = manifest.copyStore(from: .apple, to: .google, live: StoreCopySource(),
                                    imageSize: size)

    #expect(manifest == before)
    #expect(report.copied.isEmpty)
}

// MARK: - The pictures

/// The App Store keeps a set per screen size. Google Play keeps one set per
/// device and refuses anything longer than twice its width, so it takes the
/// 5.5 inch set and not the 6.9 inch one. The Mac size has no Play twin.
@Test func googlePlayTakesTheOneScreenSizeItAccepts() {
    var manifest = twoStores()
    let phone = [
        "Store Import/apple/en-US/APP_IPHONE_67/1.png",
        "Store Import/apple/en-US/APP_IPHONE_67/2.png",
        "Store Import/apple/en-US/APP_IPHONE_55/1.png",
        "Store Import/apple/en-US/APP_IPHONE_55/2.png",
        "Store Import/apple/en-US/APP_IPHONE_55/3.png",
    ]
    let live = StoreCopySource(screenshots: ["en-US": [
        .phone: phone, .desktop: ["Store Import/apple/en-US/APP_DESKTOP/1.png"]]])

    let report = manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
        == Array(phone.suffix(3)))
    // The App Store keeps what it shows: nothing was queued for it.
    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone, store: .apple).isEmpty)
    #expect(report.copied.contains("en-US · Phone · 3 screenshots"))
    #expect(report.skipped.contains { $0.hasPrefix("en-US · Desktop") })
}

@Test func noPictureThatFitsLeavesTheOtherStoreAlone() {
    var manifest = twoStores()
    let live = StoreCopySource(screenshots: ["en-US": [
        .phone: ["Store Import/apple/en-US/APP_IPHONE_67/1.png"]]])

    let report = manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(!manifest.hasStoreScreenshots(locale: "en-US", deviceClass: .phone, store: .google))
    #expect(report.skipped.contains { $0.hasPrefix("en-US · Phone") })
}

/// The App Store takes its own screen sizes and nothing between them.
@Test func theAppStoreTakesOnlyItsOwnSizesFromGooglePlay() {
    var manifest = twoStores()
    let live = StoreCopySource(screenshots: ["en-US": [.phone: [
        "Store Import/google/en-US/phoneScreenshots/1.png",
        "Store Import/google/en-US/phoneScreenshots/2.png",
    ]]])

    manifest.copyStore(from: .google, to: .apple, live: live, imageSize: size)

    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone, store: .apple)
        == ["Store Import/google/en-US/phoneScreenshots/2.png"])
}

/// Pictures the file already sends the App Store are what it will show, so
/// they win over what it shows today.
@Test func theFilesOwnPicturesComeBeforeTheStoresPictures() {
    var manifest = twoStores()
    manifest.addMediaPaths(["Store Import/apple/en-US/APP_IPHONE_55/1.png"], locale: "en-US",
                           deviceClass: .phone)
    let live = StoreCopySource(screenshots: ["en-US": [.phone: [
        "Store Import/apple/en-US/APP_IPHONE_55/2.png"]]])

    manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
        == ["Store Import/apple/en-US/APP_IPHONE_55/1.png"])
}

// MARK: - The icon

@Test func googlePlayTakesTheAppStoreIconAt512() {
    var manifest = twoStores()
    let live = StoreCopySource(icon: "Store Import/apple/en-US/icon/icon.png")

    let report = manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(manifest.media?.icon == "Store Import/apple/en-US/icon/icon.png")
    #expect(report.copied.contains("App icon"))
}

@Test func anIconOfAnotherSizeIsNotCopied() {
    var manifest = twoStores()
    let live = StoreCopySource(icon: "Media/big-icon.png")

    let report = manifest.copyStore(from: .apple, to: .google, live: live, imageSize: size)

    #expect(manifest.media?.icon == nil)
    #expect(report.skipped.contains { $0.contains("1024 × 1024") })
}

// MARK: - The catalog

private func catalog() -> Manifest {
    var manifest = twoStores()
    manifest.purchases = [
        Manifest.Purchase(id: "pro", kind: .nonConsumable,
                          price: Price(amount: 4.99, currency: "USD")),
        Manifest.Purchase(id: "Coins.Pack", kind: .consumable),
    ]
    manifest.subscriptions = [Manifest.SubscriptionGroup(groupId: "premium", plans: [
        .init(id: "premium.monthly", duration: "P1M",
              price: Price(amount: 2.99, currency: "USD")),
        .init(id: "premium.yearly", duration: "P1Y",
              price: Price(amount: 19.99, currency: "USD")),
    ])]
    return manifest
}

/// The products are shared already. Google Play asks for two details the App
/// Store never had: a base plan, and the sale switch that takes a new product
/// out of its draft.
@Test func productsGooglePlayLacksGetItsTwoDetails() {
    var manifest = catalog()

    let ready = manifest.prepareGooglePlayCatalog()

    #expect(ready == ["pro", "Coins.Pack", "premium.monthly", "premium.yearly"])
    #expect(manifest.purchases?.allSatisfy { $0.active == true } == true)
    let plans = manifest.subscriptions?.first?.plans
    #expect(plans?.map(\.basePlanId) == ["monthly", "yearly"])
    #expect(plans?.allSatisfy { $0.active == true } == true)
}

/// A product Google already holds keeps its own answers: the base plan it has,
/// and the sale switch the Play Console shows.
@Test func aProductOnGooglePlayKeepsItsOwnDetails() {
    var manifest = catalog()

    let ready = manifest.prepareGooglePlayCatalog(
        onGooglePlay: ["pro", "premium.monthly"], basePlans: ["premium.monthly": "month"])

    #expect(ready == ["Coins.Pack", "premium.monthly", "premium.yearly"])
    #expect(manifest.purchases?.first?.active == nil)
    let monthly = manifest.subscriptions?.first?.plans.first
    #expect(monthly?.basePlanId == "month")
    #expect(monthly?.active == nil)
}

@Test func theGapsNameWhatAButtonCannotFix() {
    let gaps = catalog().googlePlayCatalogGaps()

    #expect(gaps.unset.count == 4)
    #expect(gaps.unpriced == ["Coins.Pack"])
    #expect(gaps.refusedIds == ["Coins.Pack"])
    #expect(gaps.warnings.count == 2)
}

@Test func googlePlaysProductIdRule() {
    #expect(Manifest.googleAcceptsProductId("premium.monthly_2"))
    #expect(Manifest.googleAcceptsProductId("1year"))
    #expect(!Manifest.googleAcceptsProductId("Premium"))
    #expect(!Manifest.googleAcceptsProductId("pro-plan"))
    #expect(!Manifest.googleAcceptsProductId("_pro"))
    #expect(!Manifest.googleAcceptsProductId(""))
}

/// Before a read, the copy cannot tell a product Google holds from one it
/// does not, so it leaves the Google details alone and says why.
@Test func theCopyWaitsForAGooglePlayReadBeforeItSetsUpProducts() {
    var manifest = catalog()
    let before = manifest.purchases

    let unread = manifest.copyStore(from: .apple, to: .google, live: StoreCopySource(),
                                    imageSize: size)
    #expect(manifest.purchases == before)
    #expect(unread.skipped.contains { $0.contains("has not been read") })

    let read = manifest.copyStore(from: .apple, to: .google,
                                  live: StoreCopySource(googleProducts: []), imageSize: size)
    #expect(manifest.purchases?.first?.active == true)
    #expect(read.copied.contains { $0.hasPrefix("Products · Google Play details") })
}

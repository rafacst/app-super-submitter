import CoreGraphics
import Foundation
import ImageIO
import SubmitKit
import Testing
import UniformTypeIdentifiers
@testable import SuperSubmitter

/// The copy between the stores, as the Stores tab runs it, and the Google Play
/// side of a catalog that came from the App Store.
///
/// `StoreCopyTests` holds the rules. These hold the app around them: what it
/// hands the rules out of the snapshot, the files it keeps, one undo step, and
/// the Monetization row that sets up Google Play.

/// A real PNG of exactly these dimensions, because the dimensions decide which
/// store takes it.
private func pngData(_ width: Int, _ height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

@MainActor
private func twoStoreApp() throws -> (state: AppState, folder: URL, url: URL) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("store-copy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US")
    let url = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(manifest, to: url)
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "store-copy-\(UUID().uuidString)")
    try state.load(from: url)
    state.locale = "en-US"
    return (state, folder, url)
}

/// A picture the import downloaded, where the import puts it.
private func imported(_ folder: URL, _ relative: String, _ width: Int,
                      _ height: Int) throws -> URL {
    let url = folder.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try pngData(width, height).write(to: url)
    return url
}

/// The App Store's pictures reach Google Play from files of their own.
///
/// `load` drops every `Store Import/` path from `store.yaml`, because those are
/// pictures of a store and not uploads. A copy that named them would have
/// vanished on the next launch, so the pictures it chooses are copied under
/// `Store Copy/` and named from there.
@MainActor
@Test func theAppStorePicturesReachGooglePlayAndSurviveAReload() async throws {
    let (state, folder, url) = try twoStoreApp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let fits = try imported(folder, "Store Import/apple/en-US/APP_IPHONE_55/1.png", 1242, 2208)
    let tall = try imported(folder, "Store Import/apple/en-US/APP_IPHONE_67/1.png", 1320, 2868)
    let icon = try imported(folder, "Store Import/apple/en-US/icon/icon.png", 512, 512)
    var listing = ImportedStoreListing()
    var english = ImportedStoreListing.Locale()
    english.name = "Example"
    english.subtitle = "Plan the week"
    listing.locales = ["en-US": english]
    listing.assets = [
        ImportedStoreAsset(locale: "en-US", kind: "APP_IPHONE_55", url: fits, fileName: "1.png"),
        ImportedStoreAsset(locale: "en-US", kind: "APP_IPHONE_67", url: tall, fileName: "1.png"),
        ImportedStoreAsset(locale: "en-US", kind: "icon", url: icon, fileName: "icon.png"),
    ]
    state.storeSnapshot.merge(listing, store: .apple)

    let result = await state.copyStore(from: .apple)
    let report = try #require(result)

    let kept = "Store Copy/apple/en-US/APP_IPHONE_55/1.png"
    #expect(state.manifest.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
        == [kept])
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(kept).path))
    #expect(state.manifest.media?.icon == "Store Copy/apple/en-US/icon/icon.png")
    #expect(state.manifest.listingText(locale: "en-US", field: .name) == "Example")
    #expect(state.manifest.listingText(locale: "en-US", field: .subtitle) == "Plan the week")
    #expect(report.target == .google)
    #expect(!report.copied.isEmpty)
    // The downloaded original is where it was.
    #expect(FileManager.default.fileExists(atPath: fits.path))

    try state.load(from: url)

    #expect(state.manifest.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
        == [kept])
    #expect(state.manifest.media?.icon == "Store Copy/apple/en-US/icon/icon.png")
}

/// Everything one press wrote goes back with one Command-Z.
@MainActor
@Test func oneUndoTakesTheWholeCopyBack() async throws {
    let (state, folder, _) = try twoStoreApp()
    defer { try? FileManager.default.removeItem(at: folder) }
    var listing = ImportedStoreListing()
    var english = ImportedStoreListing.Locale()
    english.name = "Example"
    english.description = "A calm planner."
    listing.locales = ["en-US": english]
    state.storeSnapshot.merge(listing, store: .apple)

    _ = await state.copyStore(from: .apple)
    #expect(state.manifest.listingText(locale: "en-US", field: .name) == "Example")

    state.undoEdit()

    #expect(state.manifest.listingText(locale: "en-US", field: .name).isEmpty)
    #expect(state.manifest.listingText(locale: "en-US", field: .description).isEmpty)
}

/// One store has nothing to copy to.
@MainActor
@Test func theCopyNeedsBothStores() throws {
    let (state, folder, _) = try twoStoreApp()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(state.canCopyBetweenStores)

    state.manifest.apps.google = nil

    #expect(!state.canCopyBetweenStores)
}

// MARK: - Google Play products

@MainActor
private func appWithAppStoreProducts() throws -> (state: AppState, folder: URL) {
    let (state, folder, _) = try twoStoreApp()
    state.manifest.purchases = [
        Manifest.Purchase(id: "pro", kind: .nonConsumable,
                          price: Price(amount: 4.99, currency: "USD")),
    ]
    state.manifest.subscriptions = [Manifest.SubscriptionGroup(groupId: "premium", plans: [
        .init(id: "premium.monthly", duration: "P1M",
              price: Price(amount: 2.99, currency: "USD")),
    ])]
    return (state, folder)
}

/// The report of a Monetization tab whose products came from iOS: before a
/// read the tab cannot tell a product Google holds from one it does not, so
/// it asks for the read and sets nothing up.
@MainActor
@Test func theGooglePlaySetupWaitsForARead() throws {
    let (state, folder) = try appWithAppStoreProducts()
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(state.googlePlayCatalogUnread)
    #expect(state.googlePlayCatalogGaps == nil)
    #expect(state.setUpGooglePlayCatalog().isEmpty)
    #expect(state.manifest.purchases?.first?.active == nil)
}

/// After the read, one press gives every product Google Play lacks the two
/// details only Google asks for.
@MainActor
@Test func oneButtonSetsTheAppStoreProductsUpForGooglePlay() throws {
    let (state, folder) = try appWithAppStoreProducts()
    defer { try? FileManager.default.removeItem(at: folder) }
    state.actualState.google = ActualState.Google()

    let gaps = try #require(state.googlePlayCatalogGaps)
    #expect(gaps.unset == ["pro", "premium.monthly"])

    let ready = state.setUpGooglePlayCatalog()

    #expect(ready == ["pro", "premium.monthly"])
    #expect(state.manifest.purchases?.first?.active == true)
    let plan = state.manifest.subscriptions?.first?.plans.first
    #expect(plan?.basePlanId == "monthly")
    #expect(plan?.active == true)
    #expect(state.googlePlayCatalogGaps?.isEmpty == true)
}

/// A product Google already sells keeps whatever the Play Console says.
@MainActor
@Test func aProductGooglePlayHoldsIsLeftAsItIs() throws {
    let (state, folder) = try appWithAppStoreProducts()
    defer { try? FileManager.default.removeItem(at: folder) }
    var google = ActualState.Google()
    google.oneTimeProductIds = ["pro"]
    state.actualState.google = google

    let ready = state.setUpGooglePlayCatalog()

    #expect(ready == ["premium.monthly"])
    #expect(state.manifest.purchases?.first?.active == nil)
}

// MARK: - Where the controls stand

private func source(_ path: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: path), encoding: .utf8)
}

/// Under the keys: a second store is added on the grid, connected in the card
/// under it, and then filled from the first one.
@Test func theCopyStandsUnderTheCredentialCards() throws {
    let tab = try source("Sources/SuperSubmitter/Tabs/StoresTab.swift")
    let keys = try #require(tab.range(of: "GoogleCredentialPanel()"))
    let copy = try #require(tab.range(of: "if state.canCopyBetweenStores { StoreCopyPanel() }"))
    let team = try #require(tab.range(of: "AppleTeamPanel()"))

    #expect(keys.lowerBound < copy.lowerBound)
    #expect(copy.lowerBound < team.lowerBound)
}

@Test func monetizationOffersTheGooglePlaySetup() throws {
    let tab = try source("Sources/SuperSubmitter/Tabs/MoneyTab.swift")

    #expect(tab.contains("QuietButton(title: \"Set up for Google Play\")"))
    #expect(tab.contains("oneStoreOnlyNote\n            googlePlaySetup"))
}

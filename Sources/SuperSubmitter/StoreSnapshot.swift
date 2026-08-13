import Foundation
import SubmitKit

/// What the stores hold right now, as far as Super Submitter has seen.
///
/// Two things fill it and neither costs a request of its own: the import of an
/// existing app, and every read on the Summary tab. The editing tabs show it
/// beside the value the developer is about to write, so "what is live" and
/// "what I will send" are never the same box.
///
/// It is saved beside `store.yaml`, under `.super-submitter/`, because the
/// editing tabs grey every field that still matches the store and a field
/// cannot go grey against a picture the app forgot when it quit. `readAt`
/// travels with it, so the age of the picture is always on the screen.
struct StoreSnapshot: Codable, Equatable {
    /// store -> locale -> field -> the text the store holds.
    private(set) var text: [Store: [String: [ListingTextField: String]]] = [:]
    /// locale -> field -> the text the App Store shows customers today.
    ///
    /// The App Store keeps a live version and an editable draft, and `text`
    /// holds the draft, because the draft is what a run writes and therefore
    /// what "Kept" has to mean. The draft is often empty, so this carries the
    /// paragraphs the customer is reading and the tabs print them under the
    /// field. Google Play has one listing and needs no second picture.
    private(set) var appleLive: [String: [ListingTextField: String]] = [:]
    /// store -> locale -> device class -> the images the store shows, in order.
    private(set) var screenshots: [Store: [String: [Manifest.DeviceClass: [URL]]]] = [:]
    /// store -> locale -> the store's own bucket name -> the images in it.
    ///
    /// `screenshots` above collapses nine iPhone display types into one phone
    /// bucket, because that is what the manifest keys media by and what Google
    /// needs. The App Store keeps one set per screen size, so a developer who
    /// ships 6.9 inch and 6.5 inch read one strip with both in it and no way to
    /// tell which picture belonged to which size. This keeps the store's answer
    /// as the store gave it.
    private(set) var screenshotBuckets: [Store: [String: [String: [URL]]]]?
    /// The App Store previews. Google takes a YouTube URL on the listing.
    private(set) var previews: [String: [Manifest.DeviceClass: [URL]]] = [:]
    /// locale -> the icon Google Play shows. Play keys every listing image by
    /// language, so a developer who gave one language its own icon gets it.
    ///
    /// `StateReader` has always read this, and `merge(bucketed:)` has always
    /// thrown it away: that merge keys media by device class and "icon" is not
    /// one, so the `guard` dropped it. The bytes arrived and nothing kept them.
    private(set) var googleIcons: [String: URL]?
    /// The one icon the App Store shows. Apple extracts it from the binary, so
    /// it belongs to the app and never to a language.
    ///
    /// It arrives later than everything else here. There is no icon to read
    /// until a build carrying one reaches App Store Connect, which is why
    /// `AppState.captureAppleIcon()` runs after a submission and not on a read.
    private(set) var appleIcon: URL?
    /// locale -> the Play feature graphic, the banner above a Play listing.
    /// The App Store has no element like it.
    private(set) var featureGraphics: [String: URL]?
    /// A store's own URL for a picture -> the copy of it under `Store Import/`.
    ///
    /// The import downloads every live picture and then had no way to say so.
    /// The Media tab drew the strip from the store's URLs, so each tile fetched
    /// an image that was already on disk, the strip filled in slowly, and a
    /// press downloaded the whole thing again before Quick Look opened it.
    ///
    /// It is a map and not a swap at import time because a store read refreshes
    /// the same buckets with the store's URLs again. Both routes resolve
    /// through here, so a read costs the pictures nothing.
    private(set) var localCopies: [String: URL]?
    /// One row per product page that is not the version's own, per locale and
    /// per screen size. See `StoreProductPage`.
    private(set) var productPages: [ProductPageStrip]?
    private(set) var readAt: Date?

    /// What one custom product page or one test treatment shows, for one
    /// locale and one screen size. Flat, because the tab filters it by both.
    struct ProductPageStrip: Codable, Equatable {
        var name: String
        /// "Custom product page", or the test this treatment belongs to.
        var detail: String
        /// The store's own word for where the page stands.
        var status: String
        var locale: String
        /// The App Store display type, such as `APP_IPHONE_69`.
        var bucket: String
        var urls: [URL]
    }

    /// The three above are optional, and the rest are not, for one reason:
    /// `load` decodes the whole file with `try?`. A non-optional property added
    /// today has no key in a file written yesterday, the decode throws on that
    /// one missing key, and every listing the app had already read is lost.
    /// Optional decodes as nil and the snapshot survives its own upgrade.
    var isEmpty: Bool {
        text.isEmpty && appleLive.isEmpty && screenshots.isEmpty && previews.isEmpty
            && googleIcons == nil && appleIcon == nil && featureGraphics == nil
    }

    /// The icon one store shows for this listing, if the app has seen it.
    func icon(_ store: Store, locale: String) -> URL? {
        switch store {
        case .apple: appleIcon
        case .google: googleIcons?[locale]
        }
    }

    func featureGraphic(locale: String) -> URL? { featureGraphics?[locale] }

    /// The custom product pages and test treatments that show something for
    /// this locale and this device class, in the order the read found them.
    func productPageStrips(locale: String, deviceClass: Manifest.DeviceClass)
        -> [ProductPageStrip] {
        (productPages ?? []).filter {
            $0.locale == locale && Manifest.DeviceClass(storeBucket: $0.bucket) == deviceClass
        }
    }

    /// Replaces every page this read saw. A page the developer deleted in App
    /// Store Connect has to leave the tab, and a nil read leaves what it had
    /// rather than claiming the pages are gone.
    mutating func setProductPages(_ pages: [StoreProductPage]) {
        guard !pages.isEmpty else { return }
        var strips: [ProductPageStrip] = []
        for page in pages {
            var byLocaleAndSize: [String: [String: [URL]]] = [:]
            for asset in page.assets where !Self.isVideo(asset.url) {
                byLocaleAndSize[asset.locale, default: [:]][asset.kind, default: []]
                    .append(resolve(asset.url))
            }
            for locale in byLocaleAndSize.keys.sorted() {
                let sizes = byLocaleAndSize[locale] ?? [:]
                for bucket in sizes.keys.sorted(by: {
                    AssetInspector.appleDisplayRank($0) < AssetInspector.appleDisplayRank($1)
                }) {
                    strips.append(ProductPageStrip(
                        name: page.name, detail: page.detail, status: page.status,
                        locale: locale, bucket: bucket, urls: sizes[bucket] ?? []))
                }
            }
        }
        productPages = strips
    }

    /// The copy on disk, when the import got one. See `localCopies`.
    func resolve(_ url: URL) -> URL {
        guard let local = localCopies?[url.absoluteString],
              FileManager.default.fileExists(atPath: local.path) else { return url }
        return local
    }

    /// Files what the import downloaded, so every later read still draws from
    /// disk. A pair whose two sides match is a file that never landed.
    mutating func rememberLocalCopies(_ pairs: [(remote: URL, local: URL)]) {
        var known = localCopies ?? [:]
        for pair in pairs where pair.remote != pair.local {
            known[pair.remote.absoluteString] = pair.local
        }
        if !known.isEmpty { localCopies = known }
    }

    /// What Apple extracted from the submitted binary. See `appleIcon`.
    mutating func setAppleIcon(_ url: URL) { appleIcon = url }

    /// Whether the snapshot kept the listing the customers are reading.
    ///
    /// `appleLive` fills from `liveVersionLocales` and from nothing else, so
    /// this is true only for an app the App Store has actually shipped. The
    /// rest of the snapshot says the store holds a record, which a draft does
    /// too, and telling the two apart is the whole of `isUpdatingLiveApp`.
    var hasAppleLiveListing: Bool {
        appleLive.values.contains { $0.values.contains { !$0.isEmpty } }
    }

    /// What the App Store shows customers for this field, when the draft that
    /// a run writes does not already say the same thing. Nil means the two
    /// agree, or that nothing is known, and the tab then says nothing.
    func liveOnAppStore(_ field: ListingTextField, locale: String) -> String? {
        guard let live = appleLive[locale]?[field], !live.isEmpty else { return nil }
        return live == text[.apple]?[locale]?[field] ? nil : live
    }

    /// What one store is showing customers for this field, right now.
    ///
    /// It is not `text(_:locale:)` narrowed to one store, and the difference is
    /// the whole reason it exists. `text` holds the App Store *draft*, because
    /// the draft is what a run writes and therefore what "Kept" has to mean on
    /// an editing tab. A page a customer is looking at is the live version, so
    /// Apple answers from `appleLive` here and from nothing else.
    ///
    /// Play has one listing and no draft beside it, so for Google the two
    /// questions have one answer.
    func live(_ field: ListingTextField, store: Store, locale: String) -> String {
        switch store {
        case .apple: appleLive[locale]?[field] ?? ""
        case .google: text[.google]?[locale]?[field] ?? ""
        }
    }

    /// The stores that hold something for this field, and what they hold.
    /// The App Store comes first, the same order the tabs use everywhere.
    func text(_ field: ListingTextField, locale: String) -> [(store: Store, value: String)] {
        [Store.apple, .google].compactMap { store in
            guard let value = text[store]?[locale]?[field], !value.isEmpty else { return nil }
            return (store, value)
        }
    }

    /// One strip per set the store actually keeps, under the device class the
    /// tabs group by.
    ///
    /// The App Store names a set by screen size and shows each size its own
    /// page, so a phone group can hold nine of them. Google keeps one set for
    /// a device class and its `name` is empty, because there is nothing to tell
    /// apart. A snapshot written before this build knows no bucket names and
    /// answers with the one merged strip it has, which is what it showed then.
    func screenshotSizes(locale: String, deviceClass: Manifest.DeviceClass)
        -> [(store: Store, name: String, urls: [URL])] {
        [Store.apple, .google].flatMap { store -> [(Store, String, [URL])] in
            guard let buckets = screenshotBuckets?[store]?[locale] else {
                return screenshots(locale: locale, deviceClass: deviceClass)
                    .filter { $0.store == store }
                    .map { (store, "", $0.urls) }
            }
            return buckets
                .filter { Manifest.DeviceClass(storeBucket: $0.key) == deviceClass
                    && !$0.value.isEmpty }
                .sorted { left, right in
                    let ranks = (AssetInspector.appleDisplayRank(left.key),
                                 AssetInspector.appleDisplayRank(right.key))
                    return ranks.0 == ranks.1 ? left.key < right.key : ranks.0 < ranks.1
                }
                .map { (store, store == .apple
                    ? AssetInspector.appleDisplayName($0.key) : "", $0.value) }
        }
    }

    func screenshots(locale: String,
                     deviceClass: Manifest.DeviceClass) -> [(store: Store, urls: [URL])] {
        [Store.apple, .google].compactMap { store in
            guard let urls = screenshots[store]?[locale]?[deviceClass], !urls.isEmpty else {
                return nil
            }
            return (store, urls)
        }
    }

    func previews(locale: String, deviceClass: Manifest.DeviceClass) -> [URL] {
        previews[locale]?[deviceClass] ?? []
    }

    /// True when sending `value` would change nothing anywhere.
    ///
    /// Every store that holds this field has to hold this exact text. One
    /// store that differs is one write the run still makes, so the field is
    /// not unchanged and the tab must not say it is. A field no store holds
    /// answers false: nothing is known, so nothing is claimed.
    func isUnchanged(_ field: ListingTextField, locale: String, value: String) -> Bool {
        let live = text(field, locale: locale)
        guard !live.isEmpty else { return false }
        return live.allSatisfy { $0.value == value }
    }

    // MARK: - Disk

    /// Beside `store.yaml`, in the one directory the app is allowed to write.
    private static let fileName = ".super-submitter/store-snapshot.json"

    static func load(fromRoot root: URL?) -> StoreSnapshot {
        guard let root,
              let data = try? Data(contentsOf: root.appendingPathComponent(fileName)),
              let stored = try? JSONDecoder().decode(StoreSnapshot.self, from: data)
        else { return StoreSnapshot() }
        return stored
    }

    /// A cache write, so a failure costs the grey fields and never the edit
    /// the developer just made.
    func save(toRoot root: URL?) {
        guard let root else { return }
        let url = root.appendingPathComponent(Self.fileName)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - The two sources

    /// The read that the Summary tab runs. It covers both stores at once.
    mutating func merge(_ actual: ActualState) {
        readAt = actual.readAt ?? readAt
        if let apple = actual.apple {
            for (locale, info) in apple.infoLocales {
                set(.apple, locale, [.name: info.name, .subtitle: info.subtitle,
                                     .privacyPolicyURL: info.privacyPolicyUrl,
                                     .privacyPolicyText: info.privacyPolicyText,
                                     .privacyChoicesURL: info.privacyChoicesUrl])
            }
            for (locale, version) in apple.versionLocales {
                set(.apple, locale, Self.words(of: version))
            }
            for (locale, version) in apple.liveVersionLocales {
                for (field, value) in Self.words(of: version) {
                    guard let value, !value.isEmpty else { continue }
                    appleLive[locale, default: [:]][field] = value
                }
            }
            merge(bucketed: apple.screenshotURLs, store: .apple)
            merge(bucketed: apple.previewURLs, into: &previews)
            setProductPages(apple.productPages)
        }
        if let google = actual.google {
            for (locale, listing) in google.listings {
                set(.google, locale, [.name: listing.title,
                                      .googleShortDescription: listing.shortDescription,
                                      .description: listing.fullDescription,
                                      .googleVideo: listing.video])
            }
            for notes in google.tracks.values.map(\.releaseNotes) {
                for (locale, text) in notes { set(.google, locale, [.googleWhatsNew: text]) }
            }
            merge(art: google.imageURLs)
            merge(bucketed: google.imageURLs, store: .google)
        }
    }

    /// The import of one existing app. It runs before any read, so a freshly
    /// imported app can already show what its store holds.
    mutating func merge(_ imported: ImportedStoreListing, store: Store) {
        for (locale, source) in imported.locales {
            switch store {
            case .apple:
                set(.apple, locale, [.name: source.name, .subtitle: source.subtitle,
                                     .description: source.description,
                                     .whatsNew: source.whatsNew, .keywords: source.keywords,
                                     .promotionalText: source.promotionalText,
                                     .supportURL: source.supportURL,
                                     .marketingURL: source.marketingURL,
                                     .privacyPolicyURL: source.privacyPolicyURL,
                                     .privacyPolicyText: source.privacyPolicyText,
                                     .privacyChoicesURL: source.privacyChoicesURL])
            case .google:
                set(.google, locale, [.name: source.name,
                                      .googleShortDescription: source.subtitle,
                                      .description: source.description,
                                      .googleWhatsNew: imported.googleReleaseNotes[locale],
                                      .googleVideo: source.video])
            }
        }
        // The same replace-what-this-call-fills rule as `merge(bucketed:into:)`,
        // and for the same reason: a second import of one app used to append a
        // second copy of every picture to the first import's.
        var freshShots: [String: [Manifest.DeviceClass: [URL]]] = [:]
        var freshPreviews: [String: [Manifest.DeviceClass: [URL]]] = [:]
        var freshBuckets: [String: [String: [URL]]] = [:]
        for asset in imported.assets {
            guard let device = asset.deviceClass else { continue }
            // Apple names a video bucket by the same display type as a
            // screenshot, so the file extension tells the two apart.
            let url = resolve(asset.url)
            if store == .apple, Self.isVideo(asset.url) {
                freshPreviews[asset.locale, default: [:]][device, default: []].append(url)
            } else {
                freshShots[asset.locale, default: [:]][device, default: []].append(url)
                freshBuckets[asset.locale, default: [:]][asset.kind, default: []].append(url)
            }
        }
        var knownBuckets = screenshotBuckets ?? [:]
        for (locale, buckets) in freshBuckets {
            for (bucket, urls) in buckets {
                knownBuckets[store, default: [:]][locale, default: [:]][bucket] = urls
            }
        }
        if !knownBuckets.isEmpty { screenshotBuckets = knownBuckets }
        for (locale, devices) in freshShots {
            for (device, urls) in devices {
                screenshots[store, default: [:]][locale, default: [:]][device] = urls
            }
        }
        for (locale, devices) in freshPreviews {
            for (device, urls) in devices {
                previews[locale, default: [:]][device] = urls
            }
        }
    }

    private static let videoExtensions: Set<String> = ["mov", "m4v", "mp4"]

    /// Apple names a preview bucket after the same display type as a
    /// screenshot, so the file extension is the only thing that tells a video
    /// from an image. The import asks the same question when it files what it
    /// downloaded.
    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// The six fields an App Store version localization carries. The draft and
    /// the live version go through this one mapping, so neither can drift.
    private static func words(
        of version: ActualState.Apple.VersionLocale) -> [ListingTextField: String?] {
        [.description: version.description, .whatsNew: version.whatsNew,
         .keywords: version.keywords, .promotionalText: version.promotionalText,
         .supportURL: version.supportUrl, .marketingURL: version.marketingUrl]
    }

    private mutating func set(_ store: Store, _ locale: String,
                              _ values: [ListingTextField: String?]) {
        for (field, value) in values {
            guard let value, !value.isEmpty else { continue }
            text[store, default: [:]][locale, default: [:]][field] = value
        }
    }

    /// A store with no media keeps no entry at all, so `isEmpty` stays honest.
    private mutating func merge(bucketed: [String: [URL]], store: Store) {
        var media = screenshots[store] ?? [:]
        merge(bucketed: bucketed, into: &media)
        if !media.isEmpty { screenshots[store] = media }
        // And the same sets under the store's own bucket name. See
        // `screenshotBuckets`: the map above answers "what does the phone group
        // hold", and this one answers "which screen size is each of these".
        var known = screenshotBuckets ?? [:]
        for (key, urls) in bucketed {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, Manifest.DeviceClass(storeBucket: parts[1]) != nil
            else { continue }
            known[store, default: [:]][parts[0], default: [:]][parts[1]] = urls.map(resolve)
        }
        if !known.isEmpty { screenshotBuckets = known }
    }

    /// The two Play images that belong to no device class.
    ///
    /// They travel in `imageURLs` under the same "locale/bucket" key as the
    /// screenshots, and `merge(bucketed:)` drops every bucket that is not a
    /// device size. This runs first and takes the two it names, so that merge
    /// can go on dropping the rest.
    private mutating func merge(art bucketed: [String: [URL]]) {
        for (key, urls) in bucketed {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let url = urls.first else { continue }
            switch parts[1] {
            case "icon": googleIcons = (googleIcons ?? [:]).merging([parts[0]: url]) { _, new in new }
            case "featureGraphic":
                featureGraphics = (featureGraphics ?? [:]).merging([parts[0]: url]) { _, new in new }
            default: continue
            }
        }
    }

    /// The stores key their media "locale/bucket". The tabs group by device
    /// class, so the key splits once here.
    ///
    /// Every bucket this call fills replaces what it held, and only the buckets
    /// this call names are touched. The `+=` below used to run straight against
    /// the stored map, so a store read added the live set to the copy the last
    /// read left behind. The snapshot is saved to disk, so the count grew on
    /// every read and across launches: an app showing 14 pictures reported 182
    /// after thirteen reads. Inside one call the append stays, because several
    /// Apple display sizes answer to one device class and all of them belong.
    private func merge(bucketed: [String: [URL]],
                       into target: inout [String: [Manifest.DeviceClass: [URL]]]) {
        var fresh: [String: [Manifest.DeviceClass: [URL]]] = [:]
        // Sorted, so the order of a device class that several display sizes
        // fill is the same on every read. A dictionary hands its keys over in
        // no particular order, which shuffled the strip under the developer.
        for key in bucketed.keys.sorted() {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let device = Manifest.DeviceClass(storeBucket: parts[1])
            else { continue }
            fresh[parts[0], default: [:]][device, default: []]
                += (bucketed[key] ?? []).map(resolve)
        }
        for (locale, devices) in fresh {
            for (device, urls) in devices {
                target[locale, default: [:]][device] = urls
            }
        }
    }
}

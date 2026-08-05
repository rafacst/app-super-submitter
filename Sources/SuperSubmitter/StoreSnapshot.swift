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
    /// The App Store previews. Google takes a YouTube URL on the listing.
    private(set) var previews: [String: [Manifest.DeviceClass: [URL]]] = [:]
    private(set) var readAt: Date?

    var isEmpty: Bool {
        text.isEmpty && appleLive.isEmpty && screenshots.isEmpty && previews.isEmpty
    }

    /// What the App Store shows customers for this field, when the draft that
    /// a run writes does not already say the same thing. Nil means the two
    /// agree, or that nothing is known, and the tab then says nothing.
    func liveOnAppStore(_ field: ListingTextField, locale: String) -> String? {
        guard let live = appleLive[locale]?[field], !live.isEmpty else { return nil }
        return live == text[.apple]?[locale]?[field] ? nil : live
    }

    /// The stores that hold something for this field, and what they hold.
    /// The App Store comes first, the same order the tabs use everywhere.
    func text(_ field: ListingTextField, locale: String) -> [(store: Store, value: String)] {
        [Store.apple, .google].compactMap { store in
            guard let value = text[store]?[locale]?[field], !value.isEmpty else { return nil }
            return (store, value)
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
        for asset in imported.assets {
            guard let device = asset.deviceClass else { continue }
            // Apple names a video bucket by the same display type as a
            // screenshot, so the file extension tells the two apart.
            if store == .apple, Self.isVideo(asset.url) {
                previews[asset.locale, default: [:]][device, default: []].append(asset.url)
            } else {
                screenshots[store, default: [:]][asset.locale, default: [:]][device, default: []]
                    .append(asset.url)
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
    }

    /// The stores key their media "locale/bucket". The tabs group by device
    /// class, so the key splits once here.
    private func merge(bucketed: [String: [URL]],
                       into target: inout [String: [Manifest.DeviceClass: [URL]]]) {
        for (key, urls) in bucketed {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let device = Manifest.DeviceClass(storeBucket: parts[1])
            else { continue }
            target[parts[0], default: [:]][device, default: []] += urls
        }
    }
}

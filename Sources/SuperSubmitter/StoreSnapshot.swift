import Foundation
import SubmitKit

/// What the stores hold right now, as far as Super Submitter has seen.
///
/// Two things fill it and neither costs a request of its own: the import of an
/// existing app, and every read on the Summary tab. The editing tabs show it
/// beside the value the developer is about to write, so "what is live" and
/// "what I will send" are never the same box.
///
/// ponytail: memory only. It is a picture of a remote system, and a picture
/// saved to disk goes stale without saying so. A read refreshes it.
struct StoreSnapshot: Equatable {
    /// store -> locale -> field -> the text the store holds.
    private(set) var text: [Store: [String: [ListingTextField: String]]] = [:]
    /// store -> locale -> device class -> the images the store shows, in order.
    private(set) var screenshots: [Store: [String: [Manifest.DeviceClass: [URL]]]] = [:]
    /// The App Store previews. Google takes a YouTube URL on the listing.
    private(set) var previews: [String: [Manifest.DeviceClass: [URL]]] = [:]
    private(set) var readAt: Date?

    var isEmpty: Bool { text.isEmpty && screenshots.isEmpty && previews.isEmpty }

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
                set(.apple, locale, [.description: version.description,
                                     .whatsNew: version.whatsNew,
                                     .keywords: version.keywords,
                                     .promotionalText: version.promotionalText,
                                     .supportURL: version.supportUrl,
                                     .marketingURL: version.marketingUrl])
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
            if store == .apple, Self.videoExtensions.contains(asset.url.pathExtension.lowercased()) {
                previews[asset.locale, default: [:]][device, default: []].append(asset.url)
            } else {
                screenshots[store, default: [:]][asset.locale, default: [:]][device, default: []]
                    .append(asset.url)
            }
        }
    }

    private static let videoExtensions: Set<String> = ["mov", "m4v", "mp4"]

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

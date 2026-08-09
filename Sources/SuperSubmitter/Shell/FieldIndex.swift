import Foundation

/// Where every field lives, so ⌘F can answer "which tab holds this".
///
/// Static, and it has to be. SwiftUI builds the open tab and no other, so a
/// registry that filled itself as views rendered would only ever know the tab
/// you were already on. `FieldIndexTests` keeps it honest.
struct FieldEntry: Identifiable, Hashable {
    /// Stable anchor. Matches the `.fieldAnchor(_:)` on the view.
    let id: String
    /// The words on the screen, verbatim. The test asserts this still appears
    /// in the source of a tab, which is what catches a rename in one place.
    let label: String
    let tab: Tab
    /// Words a developer might reach for that the label does not contain.
    var keywords: [String] = []

    init(id: String, label: String, tab: Tab, keywords: [String] = []) {
        self.id = id
        self.label = label
        self.tab = tab
        self.keywords = keywords
    }
}

enum FieldIndex {
    /// Roughly one entry per place a value is entered.
    ///
    /// A field that repeats down a list points at its section rather than at
    /// one row: an anchor is an identity, and the same identity on every
    /// purchase is a bug rather than a jump target.
    static let all: [FieldEntry] = [
        // MARK: Stores
        .init(id: "stores.appleKeyID", label: "Key ID", tab: .stores,
              keywords: ["p8", "credential", "app store connect", "api key"]),
        .init(id: "stores.appleIssuerID", label: "Issuer id", tab: .stores,
              keywords: ["uuid", "credential", "app store connect"]),

        // MARK: Build
        .init(id: "build.identifiers", label: "This app in the stores", tab: .build,
              keywords: ["bundle id", "package name", "app id", "identifier"]),
        .init(id: "build.androidArtifacts", label: "Android artifacts", tab: .build,
              keywords: ["apk", "mapping", "proguard", "symbols", "obb", "expansion"]),
        .init(id: "build.googleTracks", label: "Google tracks and rollout", tab: .build,
              keywords: ["internal", "alpha", "beta", "production", "countries"]),
        .init(id: "build.releaseTrack", label: "Release track", tab: .build,
              keywords: ["track", "production", "rollout"]),
        .init(id: "build.countries", label: "Countries", tab: .build,
              keywords: ["regions", "rollout", "google"]),
        .init(id: "build.googleTesters", label: "Track testers", tab: .build,
              keywords: ["google groups", "closed track", "alpha", "beta"]),
        .init(id: "build.testFlight", label: "TestFlight", tab: .build,
              keywords: ["beta", "testers", "groups", "public link", "apple"]),
        .init(id: "build.whatToTest", label: "What to Test", tab: .build,
              keywords: ["beta notes", "testflight", "release notes", "apple"]),
        .init(id: "build.testFlightPage", label: "TestFlight page", tab: .build,
              keywords: ["feedback email", "beta", "apple"]),

        // MARK: Details
        .init(id: "details.name", label: "Name", tab: .details,
              keywords: ["title", "app name", "listing"]),
        .init(id: "details.subtitle", label: "Subtitle", tab: .details,
              keywords: ["tagline", "short description"]),
        .init(id: "details.description", label: "Description", tab: .details,
              keywords: ["long description", "full description", "body"]),
        .init(id: "details.whatsNew", label: "What is new", tab: .details,
              keywords: ["release notes", "changelog", "what's new"]),
        .init(id: "details.keywords", label: "Keywords", tab: .details,
              keywords: ["aso", "search", "apple"]),
        .init(id: "details.promotionalText", label: "Promotional text", tab: .details,
              keywords: ["promo", "apple"]),
        .init(id: "details.googleShortDescription", label: "Short description",
              tab: .details, keywords: ["google", "play", "80 characters"]),
        .init(id: "details.supportURL", label: "Support URL", tab: .details,
              keywords: ["help", "contact", "url"]),
        .init(id: "details.marketingURL", label: "Marketing URL", tab: .details,
              keywords: ["website", "homepage", "url"]),
        .init(id: "details.privacyPolicyURL", label: "Privacy policy URL", tab: .details,
              keywords: ["gdpr", "legal", "privacy", "url"]),
        .init(id: "details.privacyPolicyText", label: "Privacy policy text", tab: .details,
              keywords: ["gdpr", "legal", "privacy"]),
        .init(id: "details.privacyChoicesURL", label: "Privacy choices URL", tab: .details,
              keywords: ["gdpr", "opt out", "privacy", "url"]),
        .init(id: "details.categories", label: "Categories", tab: .details,
              keywords: ["primary", "secondary", "genre"]),
        .init(id: "details.declarations", label: "Store declarations", tab: .details,
              keywords: ["encryption", "age band", "kids", "content rating"]),
        .init(id: "details.searchKeywords", label: "Search keywords", tab: .details,
              keywords: ["aso", "custom product page", "apple"]),
        .init(id: "details.console", label: "Finish in the console", tab: .details,
              keywords: ["checklist", "manual", "no api", "age rating",
                         "data safety"]),

        // MARK: Media
        .init(id: "media.video", label: "YouTube URL", tab: .media,
              keywords: ["video", "trailer", "google", "promo"]),
        .init(id: "media.googleGraphics", label: "Google graphics", tab: .media,
              keywords: ["icon", "feature graphic", "512", "1024", "play"]),

        // MARK: Monetization
        .init(id: "money.basePrice", label: "Base price", tab: .money,
              keywords: ["price", "cost", "amount", "currency", "tier"]),
        .init(id: "money.baseTerritory", label: "Base territory", tab: .money,
              keywords: ["country", "region", "price point"]),
        .init(id: "money.availability", label: "Countries", tab: .money,
              keywords: ["availability", "territories", "countries", "regions", "where", "play"]),
        .init(id: "money.appStoreTerritories", label: "Territories",
              tab: .money, keywords: ["countries", "regions", "apple", "app store"]),
        .init(id: "money.purchases", label: "In-app purchases", tab: .money,
              keywords: ["iap", "product id", "consumable", "entitlement",
                         "review screenshot", "hosted content"]),
        .init(id: "money.subscriptions", label: "Subscriptions", tab: .money,
              keywords: ["group", "plan", "base plan", "duration", "renewing",
                         "offer", "intro price", "free trial"]),

        // MARK: Marketing
        .init(id: "marketing.customPages", label: "Custom product pages",
              tab: .marketing, keywords: ["cpp", "variant", "apple"]),
        .init(id: "marketing.experiments", label: "Product page experiments",
              tab: .marketing, keywords: ["a/b test", "treatment", "traffic"]),
        .init(id: "marketing.events", label: "In-app events", tab: .marketing,
              keywords: ["live event", "badge", "apple"]),
        .init(id: "marketing.eula", label: "Licence agreement", tab: .marketing,
              keywords: ["eula", "terms", "legal", "licence", "license"]),
        .init(id: "marketing.routing", label: "Routing app coverage",
              tab: .marketing, keywords: ["maps", "geojson", "apple"]),
        .init(id: "marketing.nomination", label: "Featuring nomination",
              tab: .marketing, keywords: ["featured", "editorial", "apple"]),
        .init(id: "marketing.accessibility", label: "Accessibility declaration",
              tab: .marketing, keywords: ["a11y", "voiceover", "apple"]),
        .init(id: "marketing.appClip", label: "App Clip default experience",
              tab: .marketing, keywords: ["clip", "apple"]),

        // MARK: Review info
        .init(id: "review.contact", label: "Review contact", tab: .reviewInfo,
              keywords: ["first name", "last name", "email", "phone", "reviewer"]),
        .init(id: "review.demoAccount", label: "Demo account", tab: .reviewInfo,
              keywords: ["sign in", "username", "password", "login", "reviewer"]),
        .init(id: "review.notes", label: "Notes for the reviewer", tab: .reviewInfo,
              keywords: ["notes", "instructions", "reviewer"]),
    ]

    /// Prefix hits first, then contains. Case and diacritic insensitive.
    ///
    /// An empty query matches nothing on purpose. The palette opens over a
    /// list of every field otherwise, and 40 rows is not an answer.
    static func matches(_ query: String) -> [FieldEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var prefix: [FieldEntry] = []
        var contains: [FieldEntry] = []
        for entry in all {
            if entry.label.hasCaseInsensitivePrefix(needle) {
                prefix.append(entry)
            } else if entry.label.containsCaseInsensitive(needle)
                        || entry.keywords.contains(where: { $0.containsCaseInsensitive(needle) }) {
                contains.append(entry)
            }
        }
        return prefix + contains
    }
}

private extension String {
    /// `.caseInsensitive` alone still separates "e" from "é", and a developer
    /// searching a listing tab types the plain letter.
    static let loose: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    func hasCaseInsensitivePrefix(_ other: String) -> Bool {
        range(of: other, options: [.anchored, Self.loose]) != nil
    }

    func containsCaseInsensitive(_ other: String) -> Bool {
        range(of: other, options: Self.loose) != nil
    }
}

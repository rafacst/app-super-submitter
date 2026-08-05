import Foundation

/// The App Store search keywords, which Apple keeps as its own resource.
///
/// This is **not** the `keywords` field of the listing. That one is a hundred
/// characters of comma-separated text on `appStoreVersionLocalizations`, the
/// manifest owns it, and the plan writes it. This is the newer `appKeywords`
/// resource that Apple links to a localization.
///
/// Apple publishes no create call and no attributes for `appKeywords`. The
/// resource carries an id and nothing else: no text, no locale, no score. So
/// the app can read which keywords Apple holds for the app, read which ones a
/// localization links, and link or unlink them. It cannot invent one.
///
/// That is why no manifest key holds these. A manifest of opaque Apple ids
/// would go into the developer's repository and say nothing to anybody, and a
/// missing manifest key means "do not manage", which is the honest state here.
///
/// ## What the link is worth
///
/// Apple opened custom product pages to organic search in July 2025. A keyword
/// linked to a custom product page sends the customer who searches that word to
/// that page instead of to the default product page. One app, one search term,
/// the screenshots written for that term.
///
/// The pool comes from the Keywords field of the latest approved version. The
/// title and the subtitle contribute nothing, and a page reaches search only
/// once Apple approves it and the developer makes it visible.
public struct AppleKeywordsClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// Which resource owns the link. Apple gives the two the same four
    /// endpoints under different parents.
    public enum Parent: String, Sendable, Equatable, CaseIterable {
        case versionLocalization = "appStoreVersionLocalizations"
        case customProductPageLocalization = "appCustomProductPageLocalizations"

        public var title: String {
            switch self {
            case .versionLocalization: "the App Store version"
            case .customProductPageLocalization: "the custom product page"
            }
        }
    }

    /// One custom product page localization: the thing a keyword attaches to.
    ///
    /// The page carries the name the developer recognises and the visible
    /// switch. The localization carries the locale and the id that the link
    /// call needs.
    public struct Target: Sendable, Equatable, Identifiable {
        /// The localization id, which is what `link` and `unlink` take.
        public var id: String
        public var pageName: String
        public var locale: String
        /// Apple reaches an invisible page from a campaign and never from
        /// search, so a keyword on one is a keyword nobody meets.
        public var visible: Bool

        public init(id: String, pageName: String, locale: String, visible: Bool) {
            self.id = id
            self.pageName = pageName
            self.locale = locale
            self.visible = visible
        }
    }

    /// Every custom product page localization of the app.
    ///
    /// Three reads deep, because Apple nests the localization under a version
    /// under the page. This takes the first version, exactly as the marketing
    /// writer does, so both halves of the app address the same one.
    ///
    /// A page that answers an error contributes nothing and fails no other
    /// page.
    public func targets(appID: String) async throws -> [Target] {
        let pages = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/appCustomProductPages",
            query: [URLQueryItem(name: "limit", value: "200")]).data)

        var result: [Target] = []
        for page in pages["data"].array {
            guard let pageID = page["id"].string else { continue }
            let name = page["attributes"]["name"].string ?? pageID
            let visible = page["attributes"]["visible"].bool ?? false
            guard let versions = try? await api.apple(
                "GET", "/v1/appCustomProductPages/\(pageID)/appCustomProductPageVersions",
                query: [URLQueryItem(name: "limit", value: "200")]),
                  let versionID = JSON(data: versions.data)["data"]
                      .array.first?["id"].string else { continue }
            guard let locales = try? await api.apple(
                "GET", "/v1/appCustomProductPageVersions/\(versionID)"
                    + "/appCustomProductPageLocalizations",
                query: [URLQueryItem(name: "limit", value: "200")]) else { continue }
            for item in JSON(data: locales.data)["data"].array {
                guard let id = item["id"].string,
                      let locale = item["attributes"]["locale"].string else { continue }
                result.append(Target(id: id, pageName: name, locale: locale, visible: visible))
            }
        }
        return result.sorted {
            ($0.pageName, $0.locale) < ($1.pageName, $1.locale)
        }
    }

    /// Every keyword Apple holds for the app. This is the pool a localization
    /// links from, and the app can add nothing to it.
    public func pool(appID: String) async throws -> [String] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/searchKeywords",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap { $0["id"].string }
    }

    /// The keywords one localization links today.
    public func linked(_ parent: Parent, localizationID: String) async throws -> [String] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/\(parent.rawValue)/\(localizationID)/searchKeywords",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap { $0["id"].string }
    }

    /// Links keywords to a localization. Apple takes the ids it does not
    /// already hold and ignores the rest, so this is safe to repeat.
    ///
    /// The linkage carries ids only. `appKeywords` has no attributes, so
    /// there is nothing else to send.
    public func link(_ parent: Parent, localizationID: String,
                     keywordIDs: [String]) async throws {
        guard !keywordIDs.isEmpty else { return }
        try await api.apple(
            "POST", "/v1/\(parent.rawValue)/\(localizationID)/relationships/searchKeywords",
            body: ["data": keywordIDs.map { ["type": "appKeywords", "id": $0] }])
    }

    /// Unlinks keywords from a localization. The keyword itself survives in
    /// the app pool, so nothing here destroys anything.
    public func unlink(_ parent: Parent, localizationID: String,
                       keywordIDs: [String]) async throws {
        guard !keywordIDs.isEmpty else { return }
        try await api.apple(
            "DELETE", "/v1/\(parent.rawValue)/\(localizationID)/relationships/searchKeywords",
            body: ["data": keywordIDs.map { ["type": "appKeywords", "id": $0] }])
    }
}

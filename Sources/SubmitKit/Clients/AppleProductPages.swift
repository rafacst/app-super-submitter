import Foundation

/// A product page of an app that is not the version's own one.
///
/// The App Store shows one page per version, and it also shows custom product
/// pages and the treatments of a product page optimization test. All three keep
/// their own screenshots, and only the version's page belonged to this app's
/// picture of the store. A developer running four custom pages saw none of them
/// here and had to open App Store Connect to answer "what is on that page".
///
/// Nothing writes to these. They are read so the Media tab can name them.
public struct StoreProductPage: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case custom
        /// The treatment of a test, and the test it belongs to.
        case treatment(experiment: String)
    }

    public var kind: Kind
    /// The name App Store Connect shows for the page or the treatment.
    public var name: String
    /// Where the page stands, in the store's own words: "Visible" or "Hidden"
    /// for a custom page, and the test's state for a treatment.
    ///
    /// The state is printed and not read. Apple has nine of them and which ones
    /// serve a customer is its business, so a guess here would put a wrong word
    /// under a real picture.
    public var status: String
    public var assets: [ImportedStoreAsset]

    public init(kind: Kind, name: String, status: String, assets: [ImportedStoreAsset]) {
        self.kind = kind
        self.name = name
        self.status = status
        self.assets = assets
    }

    /// `IN_REVIEW` as "In review". Mechanical, so a state this build has never
    /// seen still reads as words.
    public static func statusText(_ state: String) -> String {
        let words = state.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// What to print under the page name, so a treatment always says which
    /// test it belongs to.
    public var detail: String {
        switch kind {
        case .custom: "Custom product page"
        case .treatment(let experiment): "Test · \(experiment)"
        }
    }
}

/// Reads the screenshots of every product page that is not the version's own.
///
/// Every request here is optional. One page the key cannot read costs that one
/// page and never the read it rides along with, because none of this is
/// something a run writes: it is what the developer already published.
public struct AppleProductPages: Sendable {
    let api: StoreAPI

    public init(api: StoreAPI) { self.api = api }

    public func read(appID: String) async -> [StoreProductPage] {
        await custom(appID: appID) + treatments(appID: appID)
    }

    // MARK: - The custom product pages

    /// The walk `AppleKeywordsClient.targets` already makes for the search
    /// keywords, with the screenshots of each localization on the end of it.
    private func custom(appID: String) async -> [StoreProductPage] {
        guard let payload = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appCustomProductPages?limit=200") else { return [] }
        var result: [StoreProductPage] = []
        for page in JSON(data: payload.data)["data"].array {
            guard let pageID = page["id"].string else { continue }
            let name = page["attributes"]["name"].string ?? pageID
            // A page Apple has switched off keeps its pictures and shows them
            // to nobody, and the tab has to be able to say which is which.
            let visible = page["attributes"]["visible"].bool ?? false
            guard let versions = try? await api.apple(
                "GET", "/v1/appCustomProductPages/\(pageID)/appCustomProductPageVersions"
                    + "?limit=200"),
                  let versionID = JSON(data: versions.data)["data"]
                      .array.first?["id"].string else { continue }
            guard let locales = try? await api.apple(
                "GET", "/v1/appCustomProductPageVersions/\(versionID)"
                    + "/appCustomProductPageLocalizations?limit=200") else { continue }
            var assets: [ImportedStoreAsset] = []
            for item in JSON(data: locales.data)["data"].array {
                guard let id = item["id"].string,
                      let locale = item["attributes"]["locale"].string else { continue }
                assets += await screenshots(
                    path: "/v1/appCustomProductPageLocalizations/\(id)", locale: locale)
            }
            guard !assets.isEmpty else { continue }
            result.append(StoreProductPage(kind: .custom, name: name,
                                           status: visible ? "Visible" : "Hidden",
                                           assets: assets))
        }
        return result
    }

    // MARK: - The treatments of a test

    private func treatments(appID: String) async -> [StoreProductPage] {
        guard let payload = try? await api.apple(
            "GET", "/v1/apps/\(appID)/appStoreVersionExperimentsV2?limit=200")
        else { return [] }
        var result: [StoreProductPage] = []
        for experiment in JSON(data: payload.data)["data"].array {
            guard let id = experiment["id"].string else { continue }
            let name = experiment["attributes"]["name"].string ?? id
            let state = StoreProductPage.statusText(
                experiment["attributes"]["state"].string ?? "")
            guard let payload = try? await api.apple(
                "GET", "/v2/appStoreVersionExperiments/\(id)"
                    + "/appStoreVersionExperimentTreatments?limit=200") else { continue }
            for treatment in JSON(data: payload.data)["data"].array {
                guard let treatmentID = treatment["id"].string else { continue }
                let treatmentName = treatment["attributes"]["name"].string ?? treatmentID
                guard let locales = try? await api.apple(
                    "GET", "/v1/appStoreVersionExperimentTreatments/\(treatmentID)"
                        + "/appStoreVersionExperimentTreatmentLocalizations?limit=200")
                else { continue }
                var assets: [ImportedStoreAsset] = []
                for item in JSON(data: locales.data)["data"].array {
                    guard let localizationID = item["id"].string,
                          let locale = item["attributes"]["locale"].string else { continue }
                    assets += await screenshots(
                        path: "/v1/appStoreVersionExperimentTreatmentLocalizations"
                            + "/\(localizationID)",
                        locale: locale)
                }
                guard !assets.isEmpty else { continue }
                result.append(StoreProductPage(
                    kind: .treatment(experiment: name), name: treatmentName,
                    status: state, assets: assets))
            }
        }
        return result
    }

    /// One localization's screenshots, whatever kind of page holds it. Every
    /// page type hangs the same `appScreenshotSets` off its localization, so
    /// the parsing the import already does covers all three.
    private func screenshots(path: String, locale: String) async -> [ImportedStoreAsset] {
        guard let payload = try? await api.apple(
            "GET", "\(path)/appScreenshotSets?include=appScreenshots&limit=50")
        else { return [] }
        return StoreImportReader.appleAssets(
            JSON(data: payload.data), locale: locale,
            itemType: "appScreenshots", kindKey: "screenshotDisplayType")
    }
}

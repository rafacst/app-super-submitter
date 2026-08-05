import Foundation
import SubmitKit

/// The two App Store reads that answer a question no other screen answers:
/// when the signing identities lapse, and what the store measured.
///
/// None of this is a desired state, so none of it belongs in `store.yaml` or in
/// a plan row. Each call runs on a button and reports its own result, the same
/// as `AppStateAppleActions`.
extension AppState {

    // MARK: - The signing identities

    /// Every certificate, profile, device, and identifier the team holds.
    ///
    /// A resource that answers 403 contributes nothing and fails no other row.
    /// An API key scoped to one app does exactly that, which is a permission
    /// state and not a fault.
    func appleProvisioning() async -> (items: [AppleProvisioningClient.Item],
                                       failures: [String]) {
        do {
            return try await AppleProvisioningClient(api: readOnlyAPI()).inventory()
        } catch {
            return ([], ["App Store: \(error.localizedDescription)"])
        }
    }

    // MARK: - The reports

    func appleReports() -> AppleReportsClient {
        AppleReportsClient(api: readOnlyAPI())
    }

    func appleAnalyticsFeeds() async throws -> [AppleReportsClient.Feed] {
        guard let appID = appleActionAppID else { return [] }
        return try await appleReports().analyticsFeeds(appID: appID)
    }

    /// **This creates a report feed on the account.** The panel confirms it
    /// first. It is reversible, and `stopAppleAnalytics` is the reverse.
    @discardableResult
    func requestAppleAnalytics(ongoing: Bool) async throws -> AppleReportsClient.Feed? {
        guard let appID = appleActionAppID else {
            throw ConnectionError.http(400, "Connect App Store Connect on the Stores tab first.")
        }
        return try await appleReports().requestAnalytics(appID: appID, ongoing: ongoing)
    }

    func stopAppleAnalytics(feedID: String) async throws {
        try await appleReports().stopAnalytics(feedID: feedID)
    }

    // MARK: - The search keywords

    /// The `searchKeywords` of a custom product page, which is **not** the
    /// `keywords` field of the listing.
    ///
    /// That one is a hundred characters of comma-separated text, the manifest
    /// owns it, and the Details editor writes it. This is the newer
    /// `appKeywords` resource, and the link is what Apple opened to organic
    /// search in July 2025: the customer who searches a linked word reaches
    /// that custom product page instead of the default one.
    ///
    /// Apple publishes no create call and no attributes for the resource, so
    /// the app links what the account already holds and invents nothing. No
    /// manifest key holds these: a repository full of opaque Apple ids would
    /// say nothing to anybody.
    func appleKeywordPool() async throws -> [String] {
        guard let appID = appleActionAppID else { return [] }
        return try await AppleKeywordsClient(api: readOnlyAPI()).pool(appID: appID)
    }

    /// The custom product page localizations a keyword can attach to.
    func appleKeywordTargets() async throws -> [AppleKeywordsClient.Target] {
        guard let appID = appleActionAppID else { return [] }
        return try await AppleKeywordsClient(api: readOnlyAPI()).targets(appID: appID)
    }

    /// The keywords each target links today, keyed by the localization id.
    ///
    /// A target that answers an error adds no row and fails no other target.
    func appleLinkedKeywords(
        for targets: [AppleKeywordsClient.Target]) async -> [String: [String]] {
        let client = AppleKeywordsClient(api: readOnlyAPI())
        var result: [String: [String]] = [:]
        for target in targets {
            if let list = try? await client.linked(.customProductPageLocalization,
                                                   localizationID: target.id) {
                result[target.id] = list
            }
        }
        return result
    }

    /// **This changes which page the App Store search reaches.** The panel
    /// confirms it.
    ///
    /// An unlink destroys nothing. The keyword survives in the account pool,
    /// and only the link to this page goes, so the search returns to the
    /// default product page.
    func setAppleKeyword(_ keywordID: String, targetID: String,
                         linked: Bool) async throws {
        let client = AppleKeywordsClient(api: readOnlyAPI())
        if linked {
            try await client.link(.customProductPageLocalization, localizationID: targetID,
                                  keywordIDs: [keywordID])
        } else {
            try await client.unlink(.customProductPageLocalization, localizationID: targetID,
                                    keywordIDs: [keywordID])
        }
    }

    /// One sales report, unpacked. Apple answers 404 for a date it holds no
    /// report for, which is a state and not a failure: today's daily report
    /// does not exist yet.
    func appleSalesReport(frequency: String, reportDate: String?) async throws -> String {
        let vendor = appleVendorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vendor.isEmpty else {
            throw ConnectionError.http(400, "Type the vendor number first. App Store Connect shows it under Payments and Financial Reports.")
        }
        return try await appleReports().salesReport(vendorNumber: vendor,
                                                    frequency: frequency,
                                                    reportDate: reportDate)
    }
}

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
        try await appleReports().salesReport(vendorNumber: try appleVendor(),
                                             frequency: frequency,
                                             reportDate: reportDate)
    }

    /// One finance report, unpacked. It answers what Apple paid, which the
    /// sales report does not: that one counts units, this one counts money
    /// after Apple's commission.
    func appleFinanceReport(month: String, regionCode: String,
                            reportType: String) async throws -> String {
        try await appleReports().financeReport(vendorNumber: try appleVendor(),
                                               reportDate: month,
                                               regionCode: regionCode,
                                               reportType: reportType)
    }

    /// The vendor number both report families need. It belongs to the account
    /// and not to the app, so it stays out of `store.yaml`.
    private func appleVendor() throws -> String {
        let vendor = appleVendorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vendor.isEmpty else {
            throw ConnectionError.http(400, "Type the vendor number first. App Store Connect shows it under Payments and Financial Reports.")
        }
        return vendor
    }

    // MARK: - What went wrong in the app

    func appleDiagnostics() -> AppleDiagnosticsClient {
        AppleDiagnosticsClient(api: readOnlyAPI())
    }

    /// The recurring hangs, launches, and disk writes of the attached build.
    ///
    /// Apple keys these to a build, so a plan that has not read the stores yet
    /// has no build to ask about and the panel says so.
    func appleCrashSignatures(diagnosticType: String?) async throws
        -> [AppleDiagnosticsClient.Signature] {
        guard let buildID = actualState.apple?.attachedBuildId else { return [] }
        return try await appleDiagnostics().signatures(buildID: buildID,
                                                       diagnosticType: diagnosticType)
    }

    func appleCrashLogs(signatureID: String) async throws -> [AppleDiagnosticsClient.Log] {
        try await appleDiagnostics().logs(signatureID: signatureID)
    }

    /// The whole log, as Apple serves it, for the developer who wants the file.
    func appleCrashLogFile(signatureID: String) async throws -> Data {
        try await appleDiagnostics().logJSON(signatureID: signatureID)
    }

    /// The crash report one tester's submission carries. Apple puts the whole
    /// report in the resource, so one call is the file.
    func appleFeedbackCrashLog(submissionID: String) async throws -> String? {
        try await appleDiagnostics().crashLog(submissionID: submissionID)
    }

    /// The crashes and the screenshots that TestFlight testers sent.
    func appleBetaFeedback() async -> (items: [AppleDiagnosticsClient.Feedback],
                                       failures: [String]) {
        guard let appID = appleActionAppID else { return ([], []) }
        do {
            return try await appleDiagnostics().feedback(appID: appID)
        } catch {
            return ([], ["App Store: \(error.localizedDescription)"])
        }
    }

    // MARK: - The tags the store puts on the app

    func appleTags() async throws -> [AppleActionsClient.Tag] {
        guard let appID = appleActionAppID else { return [] }
        return try await appleActions().tags(appID: appID)
    }

    /// **This changes the product page.** The panel confirms it. Apple keeps
    /// the tag either way, so showing it again is the same call.
    func setAppleTagVisible(_ tagID: String, visible: Bool) async throws {
        try await appleActions().setTagVisible(tagID: tagID, visible)
    }

    /// Apple's own summary of the customer reviews.
    func appleReviewSummaries() async throws -> [AppleActionsClient.ReviewSummary] {
        guard let appID = appleActionAppID else { return [] }
        return try await appleActions().reviewSummaries(appID: appID)
    }

    // MARK: - The sandbox

    func appleSandboxTesters() async throws -> [AppleSandboxClient.Tester] {
        try await AppleSandboxClient(api: readOnlyAPI()).testers()
    }

    func setAppleSandboxTester(_ id: String, renewalRate: String?,
                               interruptPurchases: Bool?) async throws {
        try await AppleSandboxClient(api: readOnlyAPI()).update(
            testerID: id, renewalRate: renewalRate, interruptPurchases: interruptPurchases)
    }

    /// **This forgets what the accounts bought.** The panel confirms it. No
    /// paying customer is involved: a sandbox account spends no money.
    func clearAppleSandboxHistory(_ ids: [String]) async throws {
        try await AppleSandboxClient(api: readOnlyAPI()).clearPurchaseHistory(testerIDs: ids)
    }

    // MARK: - The versioned subscription drafts

    func appleSubscriptionDrafts() async throws
        -> [AppleSubscriptionVersionsClient.Product] {
        guard let appID = appleActionAppID else { return [] }
        return try await AppleSubscriptionVersionsClient(api: readOnlyAPI())
            .products(appID: appID)
    }

    /// **This creates a draft on the account.** Nothing a customer sees changes
    /// until somebody submits it and Apple approves it.
    func createAppleSubscriptionDraft(
        _ product: AppleSubscriptionVersionsClient.Product) async throws {
        try await AppleSubscriptionVersionsClient(api: readOnlyAPI())
            .createDraft(kind: product.kind, productID: product.id)
    }

    /// Pushes the manifest's own names and descriptions onto a draft.
    ///
    /// The run writes the live localizations. This writes the same values onto
    /// the versioned draft instead, which is where Apple wants a metadata
    /// change to go from now on.
    func writeAppleSubscriptionDraft(
        _ product: AppleSubscriptionVersionsClient.Product) async throws {
        guard let draft = product.draft else {
            throw ConnectionError.http(400, "Create the draft first.")
        }
        let locales = appleDraftLocales(product)
        guard !locales.isEmpty else {
            throw ConnectionError.http(
                400,
                "The manifest names no localized text for \(product.name), so there is nothing to write.")
        }
        try await AppleSubscriptionVersionsClient(api: readOnlyAPI())
            .writeLocalizations(kind: product.kind, draftID: draft.id, locales: locales)
    }

    /// What the manifest says about one group or one plan, by locale.
    ///
    /// The store names a group by its reference name and a subscription by its
    /// product id, and the manifest keys them the same way, so the match is a
    /// lookup and never a guess. An empty answer is what the panel disables
    /// its button on.
    func appleDraftLocales(_ product: AppleSubscriptionVersionsClient.Product)
        -> [String: (name: String, description: String?)] {
        var result: [String: (name: String, description: String?)] = [:]
        for group in manifest.subscriptions ?? [] {
            if product.kind == .group,
               product.name == (group.groupName ?? group.groupId) || product.name == group.groupId {
                for (locale, text) in group.locales ?? [:] {
                    result[locale] = (text.name ?? group.groupName ?? group.groupId, nil)
                }
            }
            guard product.kind == .subscription else { continue }
            for plan in group.plans where plan.id == product.name {
                for (locale, text) in plan.locales ?? [:] {
                    result[locale] = (text.name ?? plan.id, text.description)
                }
            }
        }
        return result
    }

    // MARK: - The webhooks

    func appleWebhooks() -> AppleWebhooksClient {
        AppleWebhooksClient(api: readOnlyAPI())
    }

    func appleWebhookList() async throws -> [AppleWebhooksClient.Hook] {
        guard let appID = appleActionAppID else { return [] }
        return try await appleWebhooks().hooks(appID: appID)
    }

    /// **This tells Apple to start pushing events to a URL.** The panel
    /// confirms it, and the secret it takes reaches Apple alone: no file this
    /// app writes ever holds it.
    func createAppleWebhook(name: String, url: String, secret: String,
                            eventTypes: [String]) async throws {
        guard let appID = appleActionAppID else {
            throw ConnectionError.http(400, "Connect App Store Connect on the Stores tab first.")
        }
        try await appleWebhooks().create(appID: appID, name: name, url: url,
                                         secret: secret, eventTypes: eventTypes)
    }

    // MARK: - Why an Xcode Cloud run failed

    func xcodeCloudActions(runID: String) async throws -> [XcodeCloudClient.Action] {
        try await XcodeCloudClient(api: readOnlyAPI()).actions(runID: runID)
    }

    func xcodeCloudArtifacts(actionID: String) async throws -> [XcodeCloudClient.Artifact] {
        try await XcodeCloudClient(api: readOnlyAPI()).artifacts(actionID: actionID)
    }

    func xcodeCloudTestFailures(actionID: String) async throws
        -> [XcodeCloudClient.TestFailure] {
        try await XcodeCloudClient(api: readOnlyAPI()).testFailures(actionID: actionID)
    }

    func xcodeCloudRepositories() async throws -> [XcodeCloudClient.Repository] {
        try await XcodeCloudClient(api: readOnlyAPI()).repositories()
    }

    /// Turns a workflow on, or off again. Apple keeps the configuration
    /// either way, so nothing is lost.
    func setXcodeCloudWorkflowEnabled(_ workflowID: String, enabled: Bool) async throws {
        try await XcodeCloudClient(api: readOnlyAPI())
            .setWorkflowEnabled(workflowID: workflowID, enabled)
    }
}

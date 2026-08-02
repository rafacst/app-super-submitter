import Foundation

/// The four states of a console step. Spec section 16.6.
public enum ConsoleState: String, Sendable, Codable, Equatable {
    /// The API confirms the value.
    case done
    /// The API reports the value as missing.
    case needed
    /// No API can read this step. Only these rows take a hand-made mark.
    case unknown
    /// The step does not apply to this app.
    case notApplicable

    public var label: String {
        switch self {
        case .done: "Done"
        case .needed: "Needed"
        case .unknown: "Unknown"
        case .notApplicable: "Not applicable"
        }
    }
}

public struct ConsoleRow: Sendable, Identifiable, Equatable {
    public var id: String
    public var system: String
    public var title: String
    public var reason: String
    public var link: String
    public var state: ConsoleState
    /// True when tab 6 owns this row too. The two tabs read one list, so a row
    /// is never done in one place and open in the other.
    public var onReviewTab: Bool

    public init(id: String, system: String, title: String, reason: String, link: String,
                state: ConsoleState, onReviewTab: Bool = false) {
        self.id = id
        self.system = system
        self.title = title
        self.reason = reason
        self.link = link
        self.state = state
        self.onReviewTab = onReviewTab
    }
}

/// The one list that tab 6 and tab 9 both read. Spec section 16.6.
public enum ConsoleChecklist {

    /// Every Google row opens the main Play Console dashboard. Play Console
    /// URLs need two internal numeric ids that no Android Publisher endpoint
    /// returns, and the app does not guess a URL.
    ///
    /// `// ponytail: one dashboard link over a parsed-id deep link. Add the
    /// // deep link if two clicks per row becomes a real complaint.`
    static let playConsole = "https://play.google.com/console"

    public static func rows(manifest: Manifest, actual: ActualState,
                            stores: Set<Store>) -> [ConsoleRow] {
        var result: [ConsoleRow] = []
        let appID = manifest.apps.apple?.appId ?? ""
        let apple = actual.apple

        if stores.contains(.apple) {
            let base = "https://appstoreconnect.apple.com/apps/\(appID)/distribution"
            result += [
                ConsoleRow(
                    id: "apple.privacy", system: "App Store",
                    title: "App privacy (nutrition labels)",
                    reason: "No API reads or writes them. Open App privacy.",
                    link: "\(base)/privacy", state: .unknown, onReviewTab: true),
                ConsoleRow(
                    id: "apple.info", system: "App Store",
                    title: "App information and categories",
                    reason: apple?.primaryCategory.map { "Confirmed: \($0)." }
                        ?? "The API reports no primary category.",
                    link: "\(base)/info",
                    state: apple?.primaryCategory == nil ? .needed : .done, onReviewTab: true),
                ConsoleRow(
                    id: "apple.pricing", system: "App Store", title: "Pricing and availability",
                    reason: manifest.pricing.map {
                        "Confirmed: \($0.base.amount) \($0.base.currency)."
                    } ?? "The manifest names no base price.",
                    link: "\(base)/pricing",
                    state: manifest.pricing == nil ? .needed : .done),
                ConsoleRow(
                    id: "apple.version", system: "App Store", title: "The submitted version",
                    reason: apple?.versionString.map { "Confirmed: \($0)." }
                        ?? "No version is prepared.",
                    link: "\(base)/ios/version/inflight",
                    state: apple?.versionString == nil ? .needed : .done),
                ConsoleRow(
                    id: "apple.business", system: "App Store",
                    title: "Agreements, tax, and banking",
                    reason: "No API reads this. Open Business.",
                    link: "https://appstoreconnect.apple.com/business", state: .unknown),
            ]
        }

        if stores.contains(.google) {
            let track = manifest.release?.google?.track ?? "production"
            let hasRelease = actual.google?.tracks[track]?.versionCodes.isEmpty == false
            result += [
                ConsoleRow(
                    id: "google.rating", system: "Google Play", title: "Content rating (IARC)",
                    reason: "Console only: Policy, then App content, then Content rating.",
                    link: playConsole, state: .unknown, onReviewTab: true),
                ConsoleRow(
                    id: "google.dataSafety", system: "Google Play", title: "Data safety",
                    reason: (manifest.review?.dataSafetyAnswers?.isEmpty == false)
                        ? "Confirmed: the manifest holds the answers."
                        : "The manifest holds no data safety answers.",
                    link: playConsole,
                    state: (manifest.review?.dataSafetyAnswers?.isEmpty == false)
                        ? .done : .needed,
                    onReviewTab: true),
                ConsoleRow(
                    id: "google.countries", system: "Google Play", title: "Country availability",
                    reason: "Console only: Production, then Countries and regions.",
                    link: playConsole, state: .unknown),
                ConsoleRow(
                    id: "google.release", system: "Google Play", title: "The release in the track",
                    reason: hasRelease
                        ? "Confirmed: a release exists in \(track)."
                        : "No release exists in \(track) yet.",
                    link: playConsole, state: hasRelease ? .done : .needed),
                ConsoleRow(
                    id: "google.signing", system: "Google Play", title: "App signing",
                    reason: "Console only: Setup, then App signing.",
                    link: playConsole, state: .unknown),
                ConsoleRow(
                    id: "google.category", system: "Google Play", title: "App category",
                    reason: "Console only. The Android Publisher API writes no category.",
                    link: playConsole, state: .unknown, onReviewTab: true),
                ConsoleRow(
                    id: "google.access", system: "Google Play",
                    title: "App access, the reviewer credentials",
                    reason: "Console only: Policy, then App content, then App access.",
                    link: playConsole, state: .unknown, onReviewTab: true),
            ]
        }

        // The app shows the provider rows of the selected provider only.
        switch manifest.monetization?.provider ?? .none {
        case .none:
            break
        case .revenuecat:
            result += [
                ConsoleRow(id: "rc.credentials", system: "RevenueCat",
                           title: "The store credential upload",
                           reason: "Dashboard only. Every provider needs it.",
                           link: "https://app.revenuecat.com", state: .unknown),
                ConsoleRow(id: "rc.offering", system: "RevenueCat",
                           title: "The offering, to confirm the packages",
                           reason: (actual.provider?.offeringKeys.isEmpty == false)
                               ? "Confirmed: \(actual.provider?.offeringKeys.count ?? 0) offerings."
                               : "No offering exists yet.",
                           link: "https://app.revenuecat.com",
                           state: (actual.provider?.offeringKeys.isEmpty == false)
                               ? .done : .needed),
            ]
        case .adapty:
            result += [
                ConsoleRow(id: "adapty.credentials", system: "Adapty",
                           title: "The store credential upload",
                           reason: "Dashboard only. Every provider needs it.",
                           link: "https://app.adapty.io", state: .unknown),
                ConsoleRow(id: "adapty.paywall", system: "Adapty",
                           title: "The paywall, to style it and to confirm the products",
                           reason: (actual.provider?.offeringKeys.isEmpty == false)
                               ? "Confirmed: \(actual.provider?.offeringKeys.count ?? 0) placements."
                               : "No placement exists yet.",
                           link: "https://app.adapty.io",
                           state: (actual.provider?.offeringKeys.isEmpty == false)
                               ? .done : .needed),
            ]
        }
        return result
    }

    /// `Copy as checklist` copies every open row as Markdown, for a ticket or
    /// for a message to a colleague.
    public static func markdown(_ rows: [ConsoleRow], marks: Set<String>) -> String {
        let open = rows.filter { effectiveState($0, marks: marks) != .done }
        guard !open.isEmpty else { return "Every console step is done.\n" }
        var lines = ["## Finish in the console\n"]
        for system in ["App Store", "Google Play", "RevenueCat", "Adapty"] {
            let group = open.filter { $0.system == system }
            guard !group.isEmpty else { continue }
            lines.append("### \(system)\n")
            for row in group {
                lines.append("- [ ] \(row.title) — \(row.reason) \(row.link)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Only an Unknown row takes a hand-made mark. No API can read it, so the
    /// developer is the only source.
    public static func effectiveState(_ row: ConsoleRow, marks: Set<String>) -> ConsoleState {
        (row.state == .unknown && marks.contains(row.id)) ? .done : row.state
    }
}

/// `.super-submitter/console-state.json`, keyed by the app and the version.
///
/// The app clears every hand-made mark when the version string changes,
/// because a new version needs the check again. Spec section 16.6.
public struct ConsoleStateStore: Sendable {
    private struct File: Codable {
        var app: String
        var version: String
        var marks: [String]
    }

    private let url: URL

    public init(root: URL) {
        url = root.appendingPathComponent(".super-submitter/console-state.json")
    }

    public func marks(app: String, version: String) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.app == app, file.version == version else { return [] }
        return Set(file.marks)
    }

    public func save(_ marks: Set<String>, app: String, version: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = File(app: app, version: version, marks: marks.sorted())
        try JSONEncoder().encode(file).write(to: url, options: .atomic)
    }
}

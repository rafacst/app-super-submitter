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
    public var onEditingTab: Bool

    /// The store this step belongs to, or nil where it belongs to a purchase
    /// provider instead. `system` is what the row prints; this is what the row
    /// is filtered and marked by, so the two never have to be compared as
    /// strings twice in the app.
    public var store: Store? {
        switch system {
        case "App Store": .apple
        case "Google Play": .google
        default: nil
        }
    }

    public init(id: String, system: String, title: String, reason: String, link: String,
                state: ConsoleState, onEditingTab: Bool = false) {
        self.id = id
        self.system = system
        self.title = title
        self.reason = reason
        self.link = link
        self.state = state
        self.onEditingTab = onEditingTab
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

    /// The one sentence for a declaration nobody read and nobody has to.
    ///
    /// One wording for one meaning, so a developer who meets it on the second
    /// row knows they have already read it, and so a test can name the shape
    /// of an assumed row without matching four separate strings.
    static let assumed = "Assumed: the app is on the App Store, so Apple already holds this."

    /// The three things Apple asks of an update that the manifest alone
    /// cannot answer.
    ///
    /// Each row reads the manifest first, then the store. A field the store
    /// already holds needs nothing from the manifest, because an absent key
    /// means "do not manage this field" and not "clear it".
    /// What Apple demands of any version it is asked to review.
    ///
    /// These were gated on `liveVersionString != nil` and drawn for an update
    /// alone, which read the distinction backwards. A build, an export
    /// compliance answer and a review contact are not things an update needs
    /// *more* than a first submission: they are what Apple refuses a
    /// submission for, and a first submission is the one that has never
    /// supplied any of them. The app checked them only for the developer who
    /// had already done it once.
    ///
    /// Only the review contact differs between the two flows, because only it
    /// is inherited, and it says so where it does.
    private static func appleSubmissionRows(manifest: Manifest,
                                            actual apple: ActualState.Apple?,
                                            isUpdate: Bool,
                                            base: String) -> [ConsoleRow] {
        var result: [ConsoleRow] = []

        // Every version needs its own binary. Nothing inherits a build.
        //
        // An uploaded or named build is apply work, not a manual prerequisite.
        // The release button separately requires a prepared draft, so these
        // states can stop calling work the apply is about to do a blocker.
        let namedBuild = manifest.release?.build?.ios ?? manifest.release?.build?.macos ?? ""
        let attached = apple?.attachedBuildId != nil
        // A build the developer picked from the store's own list, under Ship
        // this build. It is the third way to answer this row and it was the one
        // way that did not count: the row went on saying "Every submission
        // needs a build" on every screen after the choice, and only a store
        // read or an apply cleared it. Nothing about the choice is pending. The
        // number is in `store.yaml`, the plan draws the attach row from it, and
        // the apply sends it, which is exactly what a named build does.
        let picked = manifest.release?.apple?.buildNumber ?? ""
        let ready = attached || apple?.buildIdForVersion != nil
            || !namedBuild.isEmpty || !picked.isEmpty
        let reason: String
        if attached {
            reason = "Confirmed: a build is attached."
        } else if apple?.buildIdForVersion != nil {
            reason = "A build is uploaded and no version holds it. Run the apply to attach it."
        } else if !namedBuild.isEmpty {
            reason = "The manifest names \(namedBuild). Run the apply to upload and attach it."
        } else if !picked.isEmpty {
            reason = "store.yaml ships build \(picked) from App Store Connect. Run the apply to attach it."
        } else {
            reason = "Every submission needs a build. Build one on the Build tab, or pick one that App Store Connect already holds under Builds in App Store Connect."
        }
        result.append(ConsoleRow(
            id: "apple.updateBuild", system: "App Store", title: "A build for this version",
            reason: reason,
            link: "\(base)/ios/version/inflight",
            state: ready ? .done : .needed))

        // Apple asks the export compliance question once per build, and it
        // refuses the submission until the build carries an answer.
        let answered = manifest.review?.usesNonExemptEncryption != nil
            || apple?.buildUsesNonExemptEncryption != nil
        result.append(ConsoleRow(
            id: "apple.updateEncryption", system: "App Store", title: "Export compliance",
            reason: answered
                ? "Confirmed: the encryption question has an answer."
                : "Answer the encryption question on the Review info tab, or set ITSAppUsesNonExemptEncryption in the build.",
            link: "\(base)/ios/version/inflight",
            state: answered ? .done : .needed))

        // An update carries the contact over from the released version, so the
        // app can only judge one once the next version exists. Before that the
        // honest answer is "not read yet", and `.unknown` holds no button.
        //
        // A first submission inherits nothing, and that same `.unknown` said
        // "the app cannot read what it inherits" about an app with nothing to
        // inherit from. There the manifest is the whole answer, and an empty
        // one is a real gap: Apple refuses a first submission without a
        // contact name, an email and a phone number.
        let review = manifest.review
        let missing = [
            ("first name", review?.contactFirstName, apple?.reviewContactFirstName),
            ("last name", review?.contactLastName, apple?.reviewContactLastName),
            ("email", review?.contactEmail, apple?.reviewContactEmail),
            ("phone", review?.contactPhone, apple?.reviewContactPhone),
        ].filter { _, wanted, stored in
            (wanted ?? "").isEmpty && (stored ?? "").isEmpty
        }.map(\.0)
        let cannotJudge = isUpdate && apple?.versionId == nil

        result.append(ConsoleRow(
            id: "apple.updateReviewContact", system: "App Store",
            title: "App review contact",
            reason: cannotJudge
                ? "The next version does not exist yet, so the app cannot read what it inherits."
                : (missing.isEmpty
                    ? "Confirmed: the contact is complete."
                    : "App review needs the \(missing.joined(separator: ", "))."),
            link: "\(base)/ios/version/inflight",
            state: cannotJudge ? .unknown : (missing.isEmpty ? .done : .needed),
            onEditingTab: true))

        return result
    }

    public static func rows(manifest: Manifest, actual: ActualState,
                            stores: Set<Store>) -> [ConsoleRow] {
        var result: [ConsoleRow] = []
        let appID = manifest.apps.apple?.appId ?? ""
        let apple = actual.apple
        // The version with Apple, which is never the writable one. It reads off
        // the platform this manifest publishes, the same one every other read
        // here is narrowed to.
        let submitted = apple?.submittedVersion(
            platform: (manifest.apps.apple?.platforms.first ?? .ios).rawValue)

        if stores.contains(.apple) {
            let base = "https://appstoreconnect.apple.com/apps/\(appID)/distribution"
            // An app that is on the App Store answered these once, to get
            // there. Apple asks them per app and not per version, so a read
            // that cannot see the answer is a gap in the API and not a gap in
            // the app, and a row that says "needed" on that reading holds the
            // release button over a question that was settled a year ago.
            //
            // So a published app assumes them and says which ones it assumed.
            // Nothing here writes, so a wrong assumption costs no bytes: Apple
            // refuses the submission and names the field, which is the one
            // moment the developer can act on it. `release` says so.
            let published = apple?.isUpdate == true
            // The category is not a console step at all when the app can
            // answer it. `appleCategories` writes both through
            // `PATCH /v1/appInfos/{id}` and the Details tab holds the two
            // pickers, so this is one of the few rows here the app finishes by
            // itself. It read the store alone, so a developer who had just
            // chosen a category on the Details tab was told that Apple reports
            // none, and sent to the console to redo work the apply was about
            // to do.
            let storedCategory = apple?.primaryCategory
            let namedCategory = manifest.review?.applePrimaryCategory
                .flatMap { $0.isEmpty ? nil : $0 }
            result += [
                ConsoleRow(
                    id: "apple.privacy", system: "App Store",
                    title: "App privacy (nutrition labels)",
                    reason: published
                        ? "\(Self.assumed) Open App privacy if this version changes what the app collects."
                        : "App Store Connect publishes no endpoint for the nutrition labels, so no app can read or write them. Open App privacy.",
                    link: "\(base)/privacy", state: published ? .done : .unknown,
                    onEditingTab: true),
                ConsoleRow(
                    id: "apple.info", system: "App Store",
                    title: "App information and categories",
                    reason: storedCategory.map { "Confirmed: \($0)." }
                        ?? namedCategory.map {
                            "The Details tab names \($0). The apply writes it, so this needs no console visit."
                        }
                        ?? (published ? Self.assumed : "No category is set. Pick one on the Details tab."),
                    link: "\(base)/info",
                    state: storedCategory == nil && namedCategory == nil && !published
                        ? .needed : .done,
                    onEditingTab: true),
                // The one declaration on this list that the API does answer.
                //
                // Apple asks the questionnaire once per app and refuses a
                // submission without it, so it belongs here, and reading it
                // costs nothing: `ageRating` is already on the state, filled
                // from Apple's own answer. An empty map means the read never
                // reached the declaration, not that the app has no rating.
                //
                // It never says Needed. A first publish leaves it Unknown for
                // the developer to tick, the same as App privacy, because a
                // read that failed must not hold the button on a guess.
                ConsoleRow(
                    id: "apple.ageRating", system: "App Store", title: "Age rating",
                    reason: apple?.ageRating.isEmpty == false
                        ? "Confirmed: App Store Connect holds the questionnaire."
                        : (published ? Self.assumed
                            : "No answer was read. Fill it on the Review info tab, or in App information."),
                    link: "\(base)/info",
                    state: apple?.ageRating.isEmpty == false || published ? .done : .unknown,
                    onEditingTab: true),
                // The store first, the manifest second, the same order as the
                // category row above. This read the manifest alone, so it
                // confirmed the number the developer had typed against itself:
                // "Confirmed: 0 BRL" sat here while the plan queued a price
                // write, because only the plan was asking the store.
                ConsoleRow(
                    id: "apple.pricing", system: "App Store", title: "Pricing and availability",
                    reason: apple?.currentPriceAmount.map {
                        "Confirmed: the App Store sells at \($0)"
                            + (apple?.pricePointTerritory.map { " in \($0)" } ?? "") + "."
                    } ?? manifest.pricing.map {
                        "The Monetization tab names \($0.base.amount) \($0.base.currency). The apply writes it, so this needs no console visit."
                    } ?? (published ? Self.assumed : "The manifest names no base price."),
                    link: "\(base)/pricing",
                    state: apple?.currentPriceAmount == nil && manifest.pricing == nil && !published
                        ? .needed : .done),
                // `versionString` names the version the app may write to, and
                // a live version is not one. Reading any version here would
                // report the released number as confirmed while the apply was
                // still waiting to create the next one.
                //
                // A version in review is not writable either, so it answered
                // nil here and this row read **No version is prepared** over an
                // app whose version Apple was holding. `submitted` is that
                // version, and the row is only `needed` when neither exists.
                ConsoleRow(
                    id: "apple.version", system: "App Store", title: "The submitted version",
                    reason: apple?.versionString.map { "Confirmed: \($0)." }
                        ?? submitted.map { standing in
                            let phase = ReleaseStatusReader.applePhase(standing.state).label
                            return standing.version.map { "\($0) is with the App Store. \(phase)." }
                                ?? "A version is with the App Store. \(phase)."
                        }
                        ?? manifest.versionName(for: .apple).flatMap { desired in
                            desired.isEmpty ? nil : "\(desired) is ready. The apply creates it."
                        }
                        ?? apple?.liveVersionString.map { "\($0) is live." }
                        ?? "No version is prepared.",
                    link: "\(base)/ios/version/inflight",
                    state: apple?.versionString == nil && submitted == nil
                        && (manifest.versionName(for: .apple) ?? "").isEmpty ? .needed : .done),
                // Once per account, not even once per app. A developer with an
                // app on sale has signed the agreements and given Apple the
                // bank details, or no version of this app would have shipped.
                ConsoleRow(
                    id: "apple.business", system: "App Store",
                    title: "Agreements, tax, and banking",
                    reason: published
                        ? "\(Self.assumed) No version ships without them."
                        : "These live on the account and not on the app, and App Store Connect publishes no endpoint for either. Open Business.",
                    link: "https://appstoreconnect.apple.com/business",
                    state: published ? .done : .unknown),
            ]
            // What Apple requires of a submission, beyond the manifest.
            //
            // These sit here and not in the validator on purpose. An apply
            // leaves a draft, and a draft may wait for its build. A release
            // may not: `releaseBlockers` holds the button while a row is
            // needed, which is the moment these actually have to be true.
            result += appleSubmissionRows(manifest: manifest, actual: apple,
                                          isUpdate: apple?.liveVersionString != nil,
                                          base: base)
        }

        if stores.contains(.google) {
            let track = manifest.googlePrimaryTrack
            let hasRelease = actual.google?.tracks[track]?.versionCodes.isEmpty == false
            // The read already fetches this, from
            // `GET /edits/{id}/countryAvailability/{track}`, and the row used
            // to send the developer to the console to look at a list the app
            // was holding. Google answers 404 for a track that sells
            // everywhere, which is why "no answer" is not the same as "none".
            let availability = actual.google?.tracks[track]
            let countries = availability?.countries ?? []
            result += [
                ConsoleRow(
                    id: "google.rating", system: "Google Play", title: "Content rating (IARC)",
                    reason: "The Android Publisher API publishes no content rating endpoint, so no app can read or set it. Console only: Policy, then App content, then Content rating.",
                    link: playConsole, state: .unknown, onEditingTab: true),
                ConsoleRow(
                    id: "google.dataSafety", system: "Google Play", title: "Data safety",
                    reason: (manifest.review?.dataSafetyAnswers?.isEmpty == false)
                        ? "Confirmed: the manifest holds the answers."
                        : "The manifest holds no data safety answers.",
                    link: playConsole,
                    state: (manifest.review?.dataSafetyAnswers?.isEmpty == false)
                        ? .done : .needed,
                    onEditingTab: true),
                ConsoleRow(
                    id: "google.countries", system: "Google Play", title: "Country availability",
                    reason: availability?.restOfWorld == true
                        ? "Confirmed: \(track) sells in every country Google reaches."
                        : (countries.isEmpty
                            ? "No country list was read for \(track). Run a read, or set it under Production, then Countries and regions."
                            : "Confirmed: \(countries.count) countries on \(track)."),
                    link: playConsole,
                    state: availability?.restOfWorld == true || !countries.isEmpty
                        ? .done : .unknown),
                ConsoleRow(
                    id: "google.release", system: "Google Play", title: "The release in the track",
                    reason: hasRelease
                        ? "Confirmed: a release exists in \(track)."
                        : "No release exists in \(track) yet.",
                    link: playConsole, state: hasRelease ? .done : .needed),
                ConsoleRow(
                    id: "google.signing", system: "Google Play", title: "App signing",
                    reason: "The API uploads a bundle and never reads the signing key it is signed with. Console only: Setup, then App signing.",
                    link: playConsole, state: .unknown),
                ConsoleRow(
                    id: "google.category", system: "Google Play", title: "App category",
                    reason: "The edit details carry the contact email, the website and the phone, and no category. Console only.",
                    link: playConsole, state: .unknown, onEditingTab: true),
                ConsoleRow(
                    id: "google.access", system: "Google Play",
                    title: "App access, the reviewer credentials",
                    reason: "The Android Publisher API publishes no app access endpoint. Console only: Policy, then App content, then App access.",
                    link: playConsole, state: .unknown, onEditingTab: true),
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
                lines.append("- [ ] \(row.title): \(row.reason) \(row.link)")
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

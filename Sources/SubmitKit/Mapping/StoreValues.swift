import Foundation

/// The values a store accepts for a field that holds one of a set, and the
/// words a person reads for each one.
///
/// They live here for the same reason `BindingLimits` does: they are the
/// stores' rules, they change when a store changes, and a test can read them.
/// A view that held its own copy would drift from the one the run sends.
///
/// **The screen shows the label and the manifest keeps the value.** Nobody
/// should have to know that Apple calls it `FOOD_AND_DRINK`, and Apple will
/// not take "Food and Drink". The chooser maps one to the other, so the words
/// are on the screen and the code is in `store.yaml`.
///
/// A value that no list here carries still survives. The chooser shows it as
/// its own code, and the raw YAML side of every tab writes one the stores
/// added after this build shipped.
public enum StoreValues {

    /// One row of a chooser: what the store stores, and what a person reads.
    public struct Choice: Sendable, Equatable, Identifiable, Hashable {
        public let value: String
        public let label: String
        public var id: String { value }

        public init(_ value: String, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    // MARK: - The App Store

    /// The `appCategories` ids. Apple takes the id, never the name.
    public static let appleCategories: [Choice] = [
        Choice("BOOKS", "Books"),
        Choice("BUSINESS", "Business"),
        Choice("DEVELOPER_TOOLS", "Developer tools"),
        Choice("EDUCATION", "Education"),
        Choice("ENTERTAINMENT", "Entertainment"),
        Choice("FINANCE", "Finance"),
        Choice("FOOD_AND_DRINK", "Food and drink"),
        Choice("GAMES", "Games"),
        Choice("GRAPHICS_AND_DESIGN", "Graphics and design"),
        Choice("HEALTH_AND_FITNESS", "Health and fitness"),
        Choice("LIFESTYLE", "Lifestyle"),
        Choice("MAGAZINES_AND_NEWSPAPERS", "Magazines and newspapers"),
        Choice("MEDICAL", "Medical"),
        Choice("MUSIC", "Music"),
        Choice("NAVIGATION", "Navigation"),
        Choice("NEWS", "News"),
        Choice("PHOTO_AND_VIDEO", "Photo and video"),
        Choice("PRODUCTIVITY", "Productivity"),
        Choice("REFERENCE", "Reference"),
        Choice("SHOPPING", "Shopping"),
        Choice("SOCIAL_NETWORKING", "Social networking"),
        Choice("SPORTS", "Sports"),
        Choice("STICKERS", "Stickers"),
        Choice("TRAVEL", "Travel"),
        Choice("UTILITIES", "Utilities"),
        Choice("WEATHER", "Weather"),
    ]

    /// The Kids category age bands. Apple asks for one only when the app sits
    /// in the Kids category.
    public static let kidsAgeBands: [Choice] = [
        Choice("FIVE_AND_UNDER", "Five and under"),
        Choice("SIX_TO_EIGHT", "Six to eight"),
        Choice("NINE_TO_ELEVEN", "Nine to eleven"),
    ]

    /// The badge an in-app event wears in the App Store.
    public static let eventBadges: [Choice] = [
        Choice("BADGE_LIVE_EVENT", "Live event"),
        Choice("BADGE_PREMIERE", "Premiere"),
        Choice("BADGE_CHALLENGE", "Challenge"),
        Choice("BADGE_COMPETITION", "Competition"),
        Choice("BADGE_NEW_SEASON", "New season"),
        Choice("BADGE_MAJOR_UPDATE", "Major update"),
        Choice("BADGE_SPECIAL_EVENT", "Special event"),
    ]

    public static let eventPriorities: [Choice] = [
        Choice("HIGH", "High"), Choice("NORMAL", "Normal"), Choice("LOW", "Low"),
    ]

    public static let eventPurposes: [Choice] = [
        Choice("APP_STORE_PROMOTION", "Promote the app"),
        Choice("REENGAGEMENT", "Bring customers back"),
    ]

    public static let nominationTypes: [Choice] = [
        Choice("APP_LAUNCH", "App launch"),
        Choice("APP_ENHANCEMENTS", "App enhancements"),
        Choice("IN_APP_EVENT", "In-app event"),
        Choice("NEW_CONTENT", "New content"),
    ]

    public static let appClipActions: [Choice] = [
        Choice("OPEN", "Open"), Choice("VIEW", "View"), Choice("PLAY", "Play"),
    ]

    /// The accessibility features Apple lists on the nutrition label.
    public static let accessibilityFeatures: [Choice] = [
        Choice("VOICE_OVER", "VoiceOver"),
        Choice("VOICE_CONTROL", "Voice Control"),
        Choice("LARGER_TEXT", "Larger text"),
        Choice("SUFFICIENT_CONTRAST", "Sufficient contrast"),
        Choice("DIFFERENTIATE_WITHOUT_COLOR_ALONE", "Differentiate without colour alone"),
        Choice("REDUCED_MOTION", "Reduced motion"),
        Choice("DARK_INTERFACE", "Dark interface"),
        Choice("CAPTIONS", "Captions"),
        Choice("AUDIO_DESCRIPTIONS", "Audio descriptions"),
    ]

    /// What a colleague may do in App Store Connect. It is the App Store twin
    /// of `googleAccountPermissions` below.
    ///
    /// `ACCOUNT_HOLDER` is left out on purpose: Apple gives that role to the
    /// person who enrolled and refuses every attempt to hand it over through
    /// the API, so offering it in a chooser is offering a 409. The three
    /// deprecated permissions are left out for the same reason the deprecated
    /// Google rows are.
    public static let appleUserRoles: [Choice] = [
        Choice("ADMIN", "Admin, everything but the legal agreements"),
        Choice("APP_MANAGER", "App Manager, the whole of an app"),
        Choice("DEVELOPER", "Developer, build and deliver"),
        Choice("MARKETING", "Marketing, the promotional material"),
        Choice("SALES", "Sales, the downloads and the analytics"),
        Choice("FINANCE", "Finance, the reports and the tax forms"),
        Choice("CUSTOMER_SUPPORT", "Customer Support, the ratings and reviews"),
        Choice("CREATE_APPS", "May create app records"),
        Choice("CLOUD_MANAGED_APP_DISTRIBUTION", "May sign with the cloud distribution certificate"),
        Choice("CLOUD_MANAGED_DEVELOPER_ID", "May sign with the cloud Developer ID certificate"),
        Choice("GENERATE_INDIVIDUAL_KEYS", "May generate an individual API key"),
    ]

    // MARK: - Google Play

    /// The four tracks every Play app already has. A closed track that the
    /// developer made in the Play Console is valid too, and the chooser keeps
    /// one that the manifest already names.
    public static let googleTracks: [Choice] = [
        Choice("internal", "Internal testing"),
        Choice("alpha", "Closed testing (alpha)"),
        Choice("beta", "Open testing (beta)"),
        Choice("production", "Production"),
    ]

    /// The Play tax category of one product.
    public static let taxCategories: [Choice] = [
        Choice("TAX_CATEGORY_UNSPECIFIED", "The standard rate"),
        Choice("TAX_CATEGORY_EBOOK", "Ebook"),
        Choice("TAX_CATEGORY_AUDIOBOOK", "Audiobook"),
        Choice("TAX_CATEGORY_NEWS_PUBLICATION", "News publication"),
        Choice("TAX_CATEGORY_MAGAZINE_PUBLICATION", "Magazine publication"),
    ]

    /// The EU withdrawal right. `GoogleApply` sends one of these two.
    public static let withdrawalRights: [Choice] = [
        Choice("WITHDRAWAL_RIGHT_DIGITAL_CONTENT", "Digital content"),
        Choice("WITHDRAWAL_RIGHT_SERVICE", "Service"),
    ]

    /// What a colleague may do across the whole developer account.
    ///
    /// Google's own two deprecated rows are left out: `CAN_SEE_ALL_APPS` is
    /// superseded by `CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL`, and offering a
    /// deprecated permission in a chooser is offering a mistake. A person who
    /// already holds one still shows it, because the chooser keeps a value it
    /// does not carry.
    public static let googleAccountPermissions: [Choice] = [
        Choice("CAN_MANAGE_PERMISSIONS_GLOBAL", "Admin, every permission"),
        Choice("CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "View app information and reports"),
        Choice("CAN_VIEW_FINANCIAL_DATA_GLOBAL", "View financial data and orders"),
        Choice("CAN_VIEW_APP_QUALITY_GLOBAL", "View app quality"),
        Choice("CAN_MANAGE_PUBLIC_APKS_GLOBAL", "Release to production"),
        Choice("CAN_MANAGE_TRACK_APKS_GLOBAL", "Release to testing tracks"),
        Choice("CAN_MANAGE_TRACK_USERS_GLOBAL", "Manage tracks and tester lists"),
        Choice("CAN_MANAGE_PUBLIC_LISTING_GLOBAL", "Manage store presence"),
        Choice("CAN_MANAGE_DRAFT_APPS_GLOBAL", "Create and edit draft apps"),
        Choice("CAN_MANAGE_ORDERS_GLOBAL", "Manage orders and subscriptions"),
        Choice("CAN_MANAGE_APP_CONTENT_GLOBAL", "Manage the policy pages"),
        Choice("CAN_REPLY_TO_REVIEWS_GLOBAL", "Reply to reviews"),
        Choice("CAN_MANAGE_DEEPLINKS_GLOBAL", "Manage the deep links"),
        Choice("CAN_EDIT_GAMES_GLOBAL", "Edit Play Games Services projects"),
        Choice("CAN_PUBLISH_GAMES_GLOBAL", "Publish Play Games Services projects"),
        Choice("CAN_CREATE_MANAGED_PLAY_APPS_GLOBAL", "Create private apps"),
        Choice("CAN_CHANGE_MANAGED_PLAY_SETTING_GLOBAL", "Change the private app setting"),
        Choice("CAN_VIEW_CONNECTED_APPS_GLOBAL", "View connected apps"),
        Choice("CAN_EDIT_CONNECTED_APPS_GLOBAL", "Edit connected apps"),
    ]

    /// What a colleague may do with one app. `CAN_ACCESS_APP` is the
    /// deprecated twin of `CAN_VIEW_NON_FINANCIAL_DATA` and is left out.
    public static let googleAppPermissions: [Choice] = [
        Choice("CAN_MANAGE_PERMISSIONS", "Admin, every permission"),
        Choice("CAN_VIEW_NON_FINANCIAL_DATA", "View app information"),
        Choice("CAN_VIEW_FINANCIAL_DATA", "View financial data"),
        Choice("CAN_VIEW_APP_QUALITY", "View app quality"),
        Choice("CAN_MANAGE_PUBLIC_APKS", "Release to production"),
        Choice("CAN_MANAGE_TRACK_APKS", "Release to testing tracks"),
        Choice("CAN_MANAGE_TRACK_USERS", "Manage tracks and tester lists"),
        Choice("CAN_MANAGE_PUBLIC_LISTING", "Manage store presence"),
        Choice("CAN_MANAGE_DRAFT_APPS", "Edit and delete draft apps"),
        Choice("CAN_MANAGE_ORDERS", "Manage orders and subscriptions"),
        Choice("CAN_MANAGE_APP_CONTENT", "Manage the policy pages"),
        Choice("CAN_REPLY_TO_REVIEWS", "Reply to reviews"),
        Choice("CAN_MANAGE_DEEPLINKS", "Manage the deep links"),
    ]

    // MARK: - Languages

    /// The listing languages the App Store sells in. Google Play takes a
    /// longer list, and the manifest code maps to each store's own code, so
    /// this is the set both stores answer for.
    public static let listingLocales: [Choice] = [
        "ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB",
        "en-US", "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr",
        "hu", "id", "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR",
        "pt-PT", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans",
        "zh-Hant",
    ].map { code in
        let name = Locale.current.localizedString(
            forIdentifier: code.replacingOccurrences(of: "-", with: "_"))
        return Choice(code, name.map { "\($0) (\(code))" } ?? code)
    }.sorted { $0.label < $1.label }

    // MARK: - Money and time

    /// The subscription periods both stores sell. Apple takes these six and no
    /// others.
    public static let subscriptionDurations: [Choice] = [
        Choice("P1W", "1 week"), Choice("P1M", "1 month"), Choice("P2M", "2 months"),
        Choice("P3M", "3 months"), Choice("P6M", "6 months"), Choice("P1Y", "1 year"),
    ]

    /// An offer runs for a shorter span than a plan, so a trial adds the days.
    public static let offerDurations: [Choice] = [
        Choice("P3D", "3 days"), Choice("P1W", "1 week"), Choice("P2W", "2 weeks"),
        Choice("P1M", "1 month"), Choice("P2M", "2 months"), Choice("P3M", "3 months"),
        Choice("P6M", "6 months"), Choice("P1Y", "1 year"),
    ]

    /// Every current ISO 4217 code, named. The code stays in the label because
    /// a price is the one place a developer wants to read `USD` back.
    ///
    /// `// ponytail: the system list, not a table in this repository. It is
    /// // already right and it already updates.`
    public static let currencies: [Choice] = Locale.commonISOCurrencyCodes.map { code in
        let name = Locale.current.localizedString(forCurrencyCode: code)
        return Choice(code, name.map { "\($0) (\(code))" } ?? code)
    }.sorted { $0.label < $1.label }

    // MARK: - Countries

    /// Google Play targets a release by ISO 3166-1 alpha-2.
    public static let googleCountries: [Choice] = Locale.Region.isoRegions
        .filter { $0.identifier.count == 2 }
        .compactMap { region in
            guard let name = Locale.current.localizedString(forRegionCode: region.identifier)
            else { return nil }
            return Choice(region.identifier, "\(name) (\(region.identifier))")
        }
        .sorted { $0.label < $1.label }

    /// The App Store names a territory by ISO 3166-1 alpha-3.
    ///
    /// Foundation publishes no alpha-2 to alpha-3 map, and a table of 250 rows
    /// typed by hand would be wrong in one of them. So this asks ICU instead:
    /// ICU normalises a real alpha-3 to its alpha-2, and every combination
    /// that survives that round trip is a real code.
    ///
    /// `// ponytail: 17576 lookups, about 75 ms, once per process and only
    /// // when a territory chooser first opens. A generated table would be
    /// // faster and would go stale the next time ISO moves.`
    public static let appleTerritories: [Choice] = {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var seen = Set<String>()
        var result: [Choice] = []
        for a in letters {
            for b in letters {
                for c in letters {
                    let three = String([a, b, c])
                    guard let two = Locale(identifier: "und_\(three)").region?.identifier,
                          two.count == 2, two != three, seen.insert(two).inserted,
                          let name = Locale.current.localizedString(forRegionCode: two)
                    else { continue }
                    result.append(Choice(three, "\(name) (\(three))"))
                }
            }
        }
        return result.sorted { $0.label < $1.label }
    }()
}

// MARK: - The text a chooser reads and writes

/// The pure half of the choosers: no view, no AppKit, and every rule tested.
///
/// A manifest field holds one value or a comma-separated list of them. These
/// turn that text into what the screen shows and back again.
public enum ChoiceText {

    /// The words for one value, or the value itself when no list carries it.
    /// A code the stores added last week reads as its code, which is honest
    /// and never blank.
    public static func label(for value: String, in choices: [StoreValues.Choice]) -> String {
        choices.first { $0.value == value }?.label ?? value
    }

    public static func values(from text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func text(from values: [String]) -> String {
        values.joined(separator: ", ")
    }

    /// The whole list in words, for the line under a chooser button.
    public static func summary(of text: String, in choices: [StoreValues.Choice],
                               empty: String) -> String {
        let values = values(from: text)
        guard !values.isEmpty else { return empty }
        return values.map { label(for: $0, in: choices) }.joined(separator: ", ")
    }

    /// Adds a value or takes it out, and keeps the order the developer built.
    public static func toggling(_ value: String, in text: String) -> String {
        var values = values(from: text)
        if let index = values.firstIndex(of: value) {
            values.remove(at: index)
        } else {
            values.append(value)
        }
        return self.text(from: values)
    }

    /// The rows a chooser draws: the known ones, plus any value the manifest
    /// holds that no list carries. Without the second half, opening a chooser
    /// on a value this build has never heard of would hide it, and the next
    /// click would drop it from the file.
    public static func rows(for text: String,
                            in choices: [StoreValues.Choice]) -> [StoreValues.Choice] {
        let known = Set(choices.map(\.value))
        let extra = values(from: text).filter { !known.contains($0) }
            .map { StoreValues.Choice($0, $0) }
        return extra + choices
    }
}

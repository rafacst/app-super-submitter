import Foundation

public enum Store: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case apple, google

    public var id: String { rawValue }

    /// How a read failure names this store. `StateReader` writes it in front
    /// of every failure it reports, so a caller that asked only some of the
    /// stores can tell the answers apart afterwards.
    public var readFailureLabel: String {
        switch self {
        case .apple: "App Store"
        case .google: "Google Play"
        }
    }
}

/// One text field of the store listing. Spec section 6.1.
public enum ListingField: String, Sendable, CaseIterable {
    case name
    case subtitle
    case description
    case whatsNew
    case keywords
    case promotionalText
    case shortDescription   // the Google override of `subtitle`
}

/// The character limit of every listing field, per store.
///
/// The **binding limit** is the smallest limit among the stores that receive
/// the shared value. A per-store override removes that store from the
/// calculation, because the store then reads its own value.
///
/// The app warns over the binding limit. It never shortens the text.
public enum BindingLimits {
    /// nil means the store holds no equivalent field.
    public static func limit(for field: ListingField, in store: Store) -> Int? {
        switch (field, store) {
        case (.name, _): return 30
        case (.subtitle, .apple): return 30
        case (.subtitle, .google): return 80
        case (.description, _): return 4000
        case (.whatsNew, .apple): return 4000
        case (.whatsNew, .google): return 500
        case (.keywords, .apple): return 100
        case (.keywords, .google): return nil
        case (.promotionalText, .apple): return 170
        case (.promotionalText, .google): return nil
        case (.shortDescription, .apple): return nil
        case (.shortDescription, .google): return 80
        }
    }

    /// The limit that the shared value must respect.
    ///
    /// Returns nil when no selected store reads the shared value. The field
    /// then holds no limit, because nothing receives it.
    public static func binding(
        for field: ListingField,
        stores: Set<Store>,
        overriddenIn overrides: Set<Store> = []
    ) -> Int? {
        stores.subtracting(overrides)
            .compactMap { limit(for: field, in: $0) }
            .min()
    }

    /// The count of characters over the binding limit. Zero means it fits.
    public static func overflow(
        _ text: String,
        for field: ListingField,
        stores: Set<Store>,
        overriddenIn overrides: Set<Store> = []
    ) -> Int {
        guard let limit = binding(for: field, stores: stores, overriddenIn: overrides) else { return 0 }
        return max(0, text.count - limit)
    }
}

/// The limits Apple sets on the marketing resources.
///
/// They are not listing fields, so they stay out of `ListingField`, but a
/// limit is a rule and a rule does not live in a view. The Marketing tab
/// already printed these numbers as help text; now the fields keep them.
public enum MarketingLimits {
    public static let customProductPagePromotionalText = 170
    public static let appEventName = 30
    public static let appEventShortDescription = 50
    public static let appEventLongDescription = 120
}

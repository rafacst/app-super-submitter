import SwiftUI

/// The two jobs the app does.
///
/// Publishing gets a version out of the door. Managing runs the app that is
/// already out there. The two share the Stores tab, because both need the
/// credentials, and they share nothing else: a publisher never wants a crash
/// rate on the way to a submission, and a manager never wants a build step.
enum Mode: String, CaseIterable, Identifiable, Codable {
    case publishing
    case managing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publishing: "Publishing"
        case .managing: "Managing"
        }
    }

    var line: String {
        switch self {
        case .publishing: "Send a new app or an update to the stores."
        case .managing: "Run the app that is already live."
        }
    }

    var symbol: String {
        switch self {
        case .publishing: "paperplane.fill"
        case .managing: "dial.medium.fill"
        }
    }

    /// Two jobs, two colours. The switch is the one control that changes
    /// which tabs exist, so it earns a colour of its own.
    var tint: Color {
        switch self {
        case .publishing: Theme.accentFill
        case .managing: Theme.purpleFill
        }
    }
}

/// The tabs, in the order of the work. Spec section 16.3.
enum Tab: Int, CaseIterable, Identifiable, Hashable {
    case stores = 1
    case build
    case details
    case media
    case money
    case marketing
    case reviewInfo
    case plan
    case release
    // Managing. One tab that reads a live app and acts on it one button at
    // a time. It was three, and the three together held six sentences and
    // five buttons: three destinations for one question.
    case liveApp

    var id: Int { rawValue }

    /// The name of the tab in the mode that is showing it.
    ///
    /// Details and Media are the two tabs that appear in both modes, and they
    /// show different things in each: the publisher edits the version that has
    /// not shipped, the manager edits the listing the customers are reading
    /// now. Under one word each, the two are one row apart with nothing to
    /// tell them apart, and the sidebar cannot say which one you are standing
    /// on. The manager's copies say which listing they touch, which also puts
    /// them in the same voice as Live app, the tab beside them.
    func title(in mode: Mode) -> String {
        switch (self, mode) {
        case (.details, .managing): "Live listing"
        case (.media, .managing): "Live media"
        default: title
        }
    }

    /// The publishing name. `title(in:)` is the one the shell draws.
    var title: String {
        switch self {
        case .stores: "Stores"
        case .build: "Build"
        case .details: "Details"
        case .media: "Media"
        case .money: "Monetization"
        case .marketing: "Marketing"
        case .reviewInfo: "Review info"
        case .plan: "Summary"
        case .release: "Release"
        case .liveApp: "Live app"
        }
    }

    /// Which mode shows the tab. Stores shows in both.
    var modes: Set<Mode> {
        switch self {
        case .stores: [.publishing, .managing]
        case .build, .money, .reviewInfo, .plan, .release: [.publishing]
        // What the listing says and what it shows are the two things a
        // manager changes most, and Managing had nowhere to show them: an
        // imported app filled these tabs and the mode that imported it could
        // not open either one. Each writes on its own button here.
        case .details, .media: [.publishing, .managing]
        // Marketing edits a live listing, so it belongs to the manager. The
        // publishing plan still writes it when the manifest holds it, so an
        // import loses nothing.
        case .marketing, .liveApp: [.managing]
        }
    }

    static func tabs(in mode: Mode) -> [Tab] {
        allCases.filter { $0.modes.contains(mode) }
    }

    /// The outline reads as "not here", the filled one as "here". Release is
    /// the exception: the dotted path says the flight already left.
    func symbol(selected: Bool) -> String {
        switch self {
        case .stores: selected ? "storefront.fill" : "storefront"
        case .build: selected ? "shippingbox.fill" : "shippingbox"
        case .details: selected ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
        case .media: selected ? "photo.stack.fill" : "photo.stack"
        case .money: selected ? "dollarsign.square.fill" : "dollarsign.square"
        case .marketing: selected ? "megaphone.fill" : "megaphone"
        case .reviewInfo: selected ? "checkmark.square.fill" : "checkmark.square"
        case .plan: selected ? "text.bubble.fill" : "text.bubble"
        case .release: selected ? "airplane.path.dotted" : "airplane"
        case .liveApp: selected ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg.rectangle"
        }
    }

    /// The colour of the tab in the sidebar.
    ///
    /// One accent, not thirteen. A colour per tab was meant to make the column
    /// thirteen findable places, but the shape already does that: each row has
    /// its own glyph and its own word. What the colours actually did was
    /// override the accent the user chose in System Settings, thirteen times,
    /// and spend the whole palette on decoration — so when one row genuinely
    /// had something to say, there was no colour left to say it in.
    ///
    /// Release is the exception, and the only one. Red says irreversible
    /// everywhere else in the app, and Release is the tab that is.
    var tint: Color { self == .release ? Theme.red : Theme.accent }

    /// The question the tab answers. Spec section 16.3.
    var question: String {
        switch self {
        // One question, not two. It asked "Where does this app go, and who am
        // I?", and the two halves were unrelated: a destination and an
        // identity. The tab holds one thing, the store accounts, and picking
        // an account is what turns a store on.
        case .stores: "Which store accounts do I use?"
        case .build: "What do I submit?"
        case .details: "What does the listing say?"
        case .media: "What does the listing show?"
        // "what can I buy" put the developer in the customer's seat. Every
        // other line here is the developer's own question, and the developer
        // is the one selling.
        case .money: "What does it cost, and what is for sale inside it?"
        case .marketing: "How does the App Store sell it?"
        case .reviewInfo: "What does the reviewer need?"
        case .plan: "What changes, exactly?"
        case .release: "Is it ready, and shall I send it?"
        case .liveApp: "What are the customers seeing, and what can I fix?"
        }
    }

    /// The three zones of the app. The sidebar draws a divider between them,
    /// because the zone tells the user what a tab can do to a live store.
    ///
    /// There used to be a fourth, for the tab that wrote the drafts. Summary
    /// reads and then writes, from one screen, so the read and the write are
    /// one zone: you cannot reach the second half without passing the first.
    enum Zone: Int, CaseIterable {
        case edits, reads, releases

        var label: String {
            switch self {
            case .edits: "Edit the manifest"
            case .reads: "Check, then write the drafts"
            case .releases: "Release"
            }
        }
    }

    var zone: Zone {
        switch self {
        case .stores, .build, .details, .media, .money, .marketing, .reviewInfo: .edits
        case .plan: .reads
        case .release, .liveApp: .releases
        }
    }

    static func tabs(in zone: Zone) -> [Tab] {
        allCases.filter { $0.zone == zone }
    }

    /// A rule sits before tab 7 and before tab 9.
    ///
    /// The first marks where the app stops editing a file and starts reading
    /// the stores. The second marks the only tab that can send a version to
    /// review. Two hairlines carry the whole mental model.
    ///
    /// Managing has one rule, before the tabs that touch a live app.
    ///
    /// Stores draws no rule of its own. The sidebar pins it to the foot,
    /// under everything, because one credential covers the whole account and
    /// the tab is a setting rather than step one.
    var startsZone: Bool { self == .plan || self == .release || self == .liveApp }
}

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

    /// One word per job, and the one the sidebar group already uses.
    ///
    /// "Publishing" and "Managing" named the same two jobs in a longer voice
    /// than every other label in the column, and the switch stands directly
    /// above groups that say "Publish", "Send" and "Manage".
    var title: String {
        switch self {
        case .publishing: "Publish"
        case .managing: "Manage"
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
    // The person, not the app. It was a section of the Settings panel, four
    // clicks from the paywall and behind a sheet, so the one screen that says
    // what the account costs and what it covers was the hardest to find.
    case account

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
        case .account: "Account"
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
        // The account covers every app on the machine, so it belongs to both
        // jobs the same way the store credentials do.
        case .account: [.publishing, .managing]
        }
    }

    static func tabs(in mode: Mode) -> [Tab] {
        allCases.filter { $0.modes.contains(mode) }
    }

    /// One symbol, whether the row is selected or not.
    ///
    /// It used to be two, an outline and a fill, so that "here" and "not here"
    /// read differently. A `List` in its sidebar style already says which row
    /// you are standing on, in the way the whole system says it, and swapping
    /// the glyph underneath that is a second answer to a question already
    /// answered. No sidebar on the Mac swaps its symbols.
    var symbol: String {
        switch self {
        case .stores: "storefront"
        case .build: "shippingbox"
        case .details: "list.bullet.rectangle"
        case .media: "photo.stack"
        case .money: "dollarsign.square"
        case .marketing: "megaphone"
        case .reviewInfo: "checkmark.square"
        // The tab answers "what changes, exactly?", which is a list to read
        // before you send it and not a message. It was `text.bubble`.
        case .plan: "checklist"
        case .release: "airplane"
        case .liveApp: "waveform.path.ecg.rectangle"
        case .account: "person.crop.circle"
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
        case .account: "Who am I, and what does my plan cover?"
        }
    }

    /// The three zones of the app. The zone tells the user what a tab can do
    /// to a live store, and it is what splits the sidebar's Publish section
    /// from its Send one: everything that only edits the manifest, then the
    /// two screens that talk to a store.
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
        case .stores, .account, .build, .details, .media, .money, .marketing,
             .reviewInfo: .edits
        case .plan: .reads
        case .release, .liveApp: .releases
        }
    }

    static func tabs(in zone: Zone) -> [Tab] {
        allCases.filter { $0.zone == zone }
    }


    /// Whether the tab works with no app open, in the sense the sidebar means.
    ///
    /// Two tabs do, and neither is a step of the work. Account answers who you
    /// are and what you have paid for. Stores holds one App Store Connect key
    /// for the whole team and one Play service account for the whole developer
    /// account, so it is answered once and covers every app, including the ones
    /// not added yet.
    ///
    /// Stores also has to be reachable with nothing linked, because "Forget"
    /// lives there and it is the only way to remove a store key on purpose.
    /// The sidebar already said both of these work with no app; the row was
    /// greyed anyway, so the one screen that could undo a credential was shut
    /// exactly when a developer went looking for it.
    ///
    /// Every other tab edits or reads one app, so without one there is nothing
    /// on it. Stores is the only row the sidebar keeps on an empty window,
    /// because a key is what the rest waits on. Account is reached from the
    /// control at the foot of the column, which is available at all times.
    var standsAlone: Bool {
        switch self {
        case .stores, .account: true
        default: false
        }
    }
}

/// A group of sidebar rows.
///
/// The sections replaced the Publishing and Managing segmented control. That
/// control was a second navigation system stacked on top of the first: it
/// decided which rows existed, so half of the app lived behind a switch that
/// named neither half, and a developer who never pressed it never learned the
/// other half was there. A sidebar says the same thing by showing it, which is
/// the job a macOS sidebar has.
///
/// Title case, not capitals. `List` in its sidebar style already draws a
/// section header small and subdued, and setting the word in capitals on top
/// of that is a second emphasis for one boundary. `Section_` states the same
/// rule for the whole app, and no Apple sidebar heads its groups in capitals.
enum SidebarSection: Int, CaseIterable, Identifiable {
    /// Everything that only edits `store.yaml`.
    case publish
    /// The two screens that talk to a store.
    case send
    /// The app that is already out there.
    case manage

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .publish: "Publish"
        case .send: "Send"
        case .manage: "Manage"
        }
    }

    /// The job this group belongs to.
    ///
    /// The switch above the column shows one job's groups at a time. Every
    /// group went into the column when the shell became a
    /// `NavigationSplitView`, so that nothing hid behind a control that named
    /// neither half, and it cost the height: twelve destinations and three
    /// headings stand where four or eight are wanted, and the app list at the
    /// top is what gets squeezed.
    var mode: Mode {
        switch self {
        case .publish, .send: .publishing
        case .manage: .managing
        }
    }

    /// Whether the group needs a heading over it.
    ///
    /// Only where the job has more than one. The switch above the column names
    /// the job already, so a lone "Manage" heading under a "Manage" button is
    /// the same word twice with two rows between them. Publishing has two
    /// steps and they still have to be told apart.
    func showsHeader(in mode: Mode) -> Bool {
        SidebarSection.allCases.filter { $0.mode == mode }.count > 1
    }
}

/// One row of the sidebar: a tab, and the job it is opened for.
///
/// A `Tab` alone cannot name a row. Details and Media belong to both jobs and
/// read differently in each: the publisher edits the version that has not
/// shipped, the manager edits the listing the customers are reading now, and
/// the manager's copy carries a bar that writes straight to the live store.
/// The shell used to tell the two apart with a switch above the column; the
/// column holds both now, so a row is the pair.
///
/// It holds no state. It is a projection of `AppState.selectedTab` and
/// `AppState.mode`, and the sidebar's selection binding reads those two and
/// writes those two.
struct Destination: Hashable, Identifiable {
    let tab: Tab
    let mode: Mode

    var id: Self { self }

    /// "Details" under Publish, "Live listing" under Manage.
    var title: String { tab.title(in: mode) }

    /// The rows of one section, in order.
    ///
    /// Stores survives an empty window and no other row does: the rest edit an
    /// app. They used to show greyed, which reads as a place you have not
    /// earned rather than a place that does not apply.
    ///
    /// The account is in no section. It is not a step of the work, and the
    /// control at the foot of the sidebar opens it.
    static func rows(in section: SidebarSection, hasApp: Bool) -> [Destination] {
        let mode: Mode = section == .manage ? .managing : .publishing
        let tabs = switch section {
        case .publish: Tab.tabs(in: .publishing).filter { $0.zone == .edits }
        case .send: Tab.tabs(in: .publishing).filter { $0.zone != .edits }
        // Stores stands here too. It was listed once, under Publish, which
        // was right while every group was on screen at once; with one job
        // showing, that same rule hid the credentials from a manager.
        case .manage: Tab.tabs(in: .managing)
        }
        return tabs
            .filter { $0 != .account && (hasApp || $0.standsAlone) }
            .map { Destination(tab: $0, mode: mode) }
    }

    /// Every row the sidebar can draw, in the order it draws them.
    static func all(hasApp: Bool) -> [Destination] {
        SidebarSection.allCases.flatMap { rows(in: $0, hasApp: hasApp) }
    }
}

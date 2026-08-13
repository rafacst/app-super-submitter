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
    // Where touching an app's name lands. Every other tab answers "what am I
    // sending"; this one answers "what will they see", which is the question a
    // developer opens an app to look at. It is a whole screen like the rest
    // and the only one the sidebar lists nowhere: the name at the top of the
    // column opens it, so a row of its own would be one destination twice.
    case storePage
    case build
    // Everything that reaches a tester before a customer reaches it. It was a
    // fold on Build, beside the drop wells, so the screen that takes a package
    // also held every group, address, note and licence a beta needs. Those are
    // two jobs, and the second one is where a release actually starts.
    case betaTesting
    case details
    case media
    // Everything a game holds that an app does not: the achievements, the
    // leaderboards, the challenges and the matchmaking. It is one tab and not
    // a fold on Details, because it is the largest untouched surface of the
    // App Store Connect API and none of it is a listing field.
    //
    // Inserting the case here renumbers every raw value below it, and that is
    // safe: nothing reads `Tab(rawValue:)`, nothing writes `selectedTab` to
    // disk, and no snapshot or draft encodes a `Tab`. The numbers fix the
    // sidebar order and do nothing else.
    case gaming
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
    // This Mac, not the app. It was a sheet over the window with a strip of
    // four sections across the top: a second navigation system, inside a
    // panel, over the first one. A screen of this size is a screen.
    case settings

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
        // The same screen from two sources, and one name for both: the
        // publisher sees the page their draft will make, the manager sees the
        // page the store is serving now. "Preview" would promise the manager a
        // mockup of what they have already shipped.
        case .storePage: "Store page"
        case .build: "Build"
        case .betaTesting: "Beta testing"
        case .details: "Details"
        case .media: "Media"
        case .gaming: "Gaming"
        case .money: "Monetization"
        case .marketing: "Marketing"
        case .reviewInfo: "Review info"
        case .plan: "Summary"
        case .release: "Release"
        case .liveApp: "Live app"
        case .account: "Account"
        case .settings: "Settings"
        }
    }

    /// Which mode shows the tab. Stores shows in both.
    var modes: Set<Mode> {
        switch self {
        case .stores: [.publishing, .managing]
        case .build, .betaTesting, .gaming, .money, .reviewInfo, .plan,
             .release: [.publishing]
        // What the listing says and what it shows are the two things a
        // manager changes most, and Managing had nowhere to show them: an
        // imported app filled these tabs and the mode that imported it could
        // not open either one. Each writes on its own button here.
        case .details, .media: [.publishing, .managing]
        // Both jobs, for the same reason Details and Media are both: a draft
        // has a page it will make and a live app has a page it is making, and
        // a developer wants to look at whichever one they have.
        case .storePage: [.publishing, .managing]
        // Marketing edits a live listing, so it belongs to the manager. The
        // publishing plan still writes it when the manifest holds it, so an
        // import loses nothing.
        case .marketing, .liveApp: [.managing]
        // The account covers every app on the machine, so it belongs to both
        // jobs the same way the store credentials do. Settings is the same
        // machine again, in its other half: what this program does on it.
        case .account, .settings: [.publishing, .managing]
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
        case .storePage: "eye"
        case .build: "shippingbox"
        case .betaTesting: "testtube.2"
        case .details: "list.bullet.rectangle"
        case .media: "photo.stack"
        case .gaming: "gamecontroller"
        case .money: "dollarsign.square"
        case .marketing: "megaphone"
        case .reviewInfo: "checkmark.square"
        // The tab answers "what changes, exactly?", which is a list to read
        // before you send it and not a message. It was `text.bubble`.
        case .plan: "checklist"
        case .release: "airplane"
        case .liveApp: "waveform.path.ecg.rectangle"
        case .account: "person.crop.circle"
        case .settings: "gearshape"
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

    /// What the tab is for, under its name. Spec section 16.3.
    ///
    /// A statement of the work, not a question about it. Twelve questions read
    /// as an interview: the line under the title was the one place that could
    /// say what a screen holds, and it spent that place asking the developer
    /// something instead. Each of these names the things the tab edits, so a
    /// developer who has never opened it knows what is inside before scrolling.
    var summary: String {
        switch self {
        case .stores: "Connect the App Store and Google Play accounts"
        case .storePage: "See the app the way a customer sees it in the store"
        case .build: "Import or build the package, and set the release version"
        case .betaTesting: "Invite the testers, and say what they get to try"
        case .details: "Write the listing text, the keywords and the support links"
        case .media: "Add the screenshots, the icon and the promotional video"
        case .gaming: "Set up the achievements, the leaderboards and the matchmaking of a game"
        case .money: "Define selling price, in-app purchases, subscriptions and more"
        case .marketing: "Set up custom product pages, tests and in-app events"
        case .reviewInfo: "Give the reviewer the contact, the demo account and the notes"
        case .plan: "Check every change before it reaches a store"
        case .release: "Send the version to review and release it to customers"
        case .liveApp: "Follow the ratings, the crashes and the sales of the live app"
        case .account: "Manage the account, the plan and the payment"
        case .settings: "Set how Super Submitter works on this Mac"
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
        // Beta testing is an `edits` zone, and its two buttons do not make it
        // a Send one: a group, an address and a note are manifest values that
        // the run carries, and the zone is what keeps the sidebar's Send group
        // down to the two screens that release a version to customers. The
        // store page writes nothing at all and is filed the same way, for the
        // same reason: the wrong answer is the one that puts a read-only
        // screen under Send, beside the two buttons that talk to a store.
        case .stores, .account, .settings, .storePage, .build, .betaTesting,
             .details, .media, .gaming, .money, .marketing, .reviewInfo: .edits
        case .plan: .reads
        case .release, .liveApp: .releases
        }
    }

    static func tabs(in zone: Zone) -> [Tab] {
        allCases.filter { $0.zone == zone }
    }


    /// Whether the tab is about this Mac rather than about one app.
    ///
    /// Three are, and none of them is a step of the work. Stores holds one App
    /// Store Connect key for the whole team and one Play service account for
    /// the whole developer account. Account answers who you are and what you
    /// have paid for. Settings is what this program does on the machine: the
    /// appearance, the poll interval, the provider, the files it writes.
    ///
    /// Each is answered once and covers every app, including the ones not added
    /// yet, so each of them opens with nothing linked. Stores has to: "Forget"
    /// lives there and it is the only way to remove a store key on purpose. The
    /// sidebar used to grey that row on an empty window, so the one screen that
    /// could undo a credential was shut exactly when a developer went looking
    /// for it.
    ///
    /// It is also what the sidebar sorts by. These three sit in the box at the
    /// foot of the column, away from the groups, because the groups are the
    /// steps of one app's submission and these three are not steps at all. Every
    /// other tab edits or reads one app, so without one there is nothing on it.
    var standsAlone: Bool {
        switch self {
        case .stores, .account, .settings: true
        default: false
        }
    }

    /// Whether the sidebar draws a row for the tab.
    ///
    /// Every one but the store page, and that one is not hidden: it is opened
    /// by the app's own name at the head of the column, which is the control a
    /// developer already presses to look at one of their apps. A row beside it
    /// would put one destination in the column twice, and the column's
    /// selection can stand on only one of them.
    ///
    /// It is not `standsAlone`. Those three are about this Mac and live in the
    /// box at the foot of the column; this one is about one app, and it is the
    /// most app-specific screen there is.
    var isListed: Bool { self != .storePage }
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
    /// Every row here is a step of one app's submission, and every one of them
    /// needs that app: with nothing linked the groups are empty and the sidebar
    /// draws none of them. They used to show greyed, which reads as a place you
    /// have not earned rather than a place that does not apply.
    ///
    /// Stores, Settings and Account are in no section. None of them is a step of
    /// the work — each is answered once for the whole Mac — and the box at the
    /// foot of the column holds all three. Stores was listed under Publish and
    /// again under Manage, which is the same screen twice in a column whose
    /// selection can only be standing on one of them.
    ///
    /// The store page is in no section either, and for that same rule: the app
    /// list above these groups already opens it. See `Tab.isListed`.
    static func rows(in section: SidebarSection, hasApp: Bool) -> [Destination] {
        guard hasApp else { return [] }
        let mode: Mode = section == .manage ? .managing : .publishing
        let tabs = switch section {
        case .publish: Tab.tabs(in: .publishing).filter { $0.zone == .edits }
        case .send: Tab.tabs(in: .publishing).filter { $0.zone != .edits }
        case .manage: Tab.tabs(in: .managing)
        }
        return tabs
            .filter { !$0.standsAlone && $0.isListed }
            .map { Destination(tab: $0, mode: mode) }
    }

    /// Every row the sidebar can draw, in the order it draws them.
    static func all(hasApp: Bool) -> [Destination] {
        SidebarSection.allCases.flatMap { rows(in: $0, hasApp: hasApp) }
    }
}

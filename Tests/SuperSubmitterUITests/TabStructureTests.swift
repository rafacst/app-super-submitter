import AppKit
import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A misspelled symbol name draws nothing and says nothing. The sidebar would
/// then show a row with no icon, so every name is resolved here instead.
@Test func everyTabSymbolResolves() {
    // The tabs, plus the three glyphs the sidebar writes as literals: the app
    // switcher with no app open, and the account control.
    let names = Tab.allCases.map(\.symbol)
        + ["square.stack.3d.up", "person.crop.circle", "checkmark"]
    for name in names {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "The symbol \(name) is not available.")
    }
}

/// Summary reads the stores and then writes the drafts, from one screen. The
/// run used to be a tab of its own, which put a navigation step between the
/// decision and its consequence and left a dead end behind whenever no plan
/// existed yet.
@Test func workflowTabsKeepTheirSafetyOrder() {
    #expect(Tab.tabs(in: .publishing).map(\.title) == [
        "Stores", "Preview store", "Build", "Beta testing", "Details", "Media",
        "Gaming", "Availability", "Monetization", "Review info", "Summary",
        "Release", "Account", "Settings",
    ])
    #expect(Tab.plan.zone == .reads)
    #expect(Tab.release.zone == .releases)
    // Nothing writes to a store before the tab that shows the diff.
    #expect(Tab.tabs(in: .publishing).firstIndex(of: .plan)!
        < Tab.tabs(in: .publishing).firstIndex(of: .release)!)
}

/// The shape of the sidebar, which is the shape of the app.
///
/// Every row is a step of one app's submission, in a group that says which job
/// it belongs to. The switch above the column then shows one job's groups at a
/// time: see `SidebarModeSwitchTests` for what that hides and what it may not.
@Test func theSidebarListsEveryDestinationInItsSection() {
    // Beta testing follows Build, because it is what happens to the package
    // Build made before a customer ever sees it. Gaming follows Media, because
    // an achievement image is the last thing a game describes before it is
    // priced.
    // The store page leads both groups. It is the one screen that answers
    // "what will they see", which is what a developer opens an app to look at,
    // and it had no row at all while the app list was in this column.
    // Availability precedes Monetization: what the app costs and where it
    // sells is one question, and what it sells inside itself is the next one.
    #expect(Destination.rows(in: .publish, hasApp: true).map(\.title)
        == ["Preview store", "Build", "Beta testing", "Details", "Media", "Gaming",
            "Availability", "Monetization", "Review info"])
    #expect(Destination.rows(in: .send, hasApp: true).map(\.title)
        == ["Summary", "Release"])
    #expect(Destination.rows(in: .manage, hasApp: true).map(\.title)
        == ["Preview store", "Live listing", "Live media", "Marketing", "Live app"])

    // Publish and Send are the manifest against the stores: everything that
    // only edits `store.yaml`, then the two screens that talk to a store.
    #expect(Destination.rows(in: .publish, hasApp: true).allSatisfy { $0.tab.zone == .edits })
    #expect(Destination.rows(in: .send, hasApp: true).allSatisfy { $0.tab.zone != .edits })

    // Nothing is lost. The three off the list are about this Mac rather than
    // about an app, and the box at the foot of the sidebar holds them.
    let listed = Set(Destination.all(hasApp: true).map(\.tab))
    #expect(Set(Tab.allCases).subtracting(listed) == [.stores, .settings, .account])
    // Every tab about one app is on a row now. The store page was the one
    // exception, opened by the app's name while the app list was in this
    // column, and that list is the tab bar at the top of the window.
    #expect(Tab.allCases.filter { !$0.isListed }.isEmpty)
    #expect(Set(Tab.allCases.filter(\.standsAlone)) == [.stores, .settings, .account])
    // Stores was listed under Publish and again under Manage, which is one
    // screen in two rows of a column that can only stand on one of them.
    #expect(Destination.all(hasApp: true).allSatisfy { !$0.tab.standsAlone })
}

/// With no app linked there is nothing to edit, and a row that edits nothing
/// used to show greyed. The groups are empty instead, and the three screens
/// that need no app are in the footer, which is on the screen at all times.
@Test func anEmptyWindowListsNoStepOfTheWork() {
    #expect(Destination.all(hasApp: false).isEmpty)
    for section in SidebarSection.allCases {
        #expect(Destination.rows(in: section, hasApp: false).isEmpty)
    }
}

/// The sidebar's selection is `mode` and `selectedTab`, and nothing else.
///
/// Both have a `didSet` that moves the other: choosing a tab of the other mode
/// switches the mode, and switching the mode moves off a tab it does not hold.
/// Writing them in the wrong order lands the user on a row they did not pick,
/// so every row is round-tripped here.
@MainActor
@Test func everySidebarRowSelectsItselfAndStaysThere() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")

    for destination in Destination.all(hasApp: true) {
        // The order the sidebar's binding writes them in.
        state.mode = destination.mode
        state.selectedTab = destination.tab

        #expect(Destination(tab: state.selectedTab, mode: state.mode) == destination,
                "\(destination.title) selected \(state.selectedTab.title(in: state.mode))")
    }
}

/// The two modes describe two jobs. A publisher never wants a crash rate on
/// the way to a submission, and a manager never wants a build step.
///
/// They share the credentials and the two tabs that describe the listing. A
/// manager changes a description and a screenshot more often than anything
/// else, and Managing used to hold neither: an import filled both tabs and
/// the mode that imported the app could open neither one.
@Test func theTwoModesShareTheStoresAndTheListingTabs() {
    let publishing = Set(Tab.tabs(in: .publishing))
    let managing = Set(Tab.tabs(in: .managing))

    // The store page joins the shared three for the same reason Details and
    // Media are shared: a draft has a page it will make and a live app has one
    // it is making, and a developer wants to look at whichever one they have.
    #expect(publishing.intersection(managing)
        == [.stores, .account, .settings, .storePage, .details, .media])
    #expect(publishing.union(managing) == Set(Tab.allCases))
    #expect(Tab.tabs(in: .managing).map { $0.title(in: .managing) }
        == ["Stores", "Preview store", "Live listing", "Live media", "Marketing",
            "Live app", "Account", "Settings"])
    // Nothing that builds, tests, plans, writes, or releases reaches a manager.
    #expect(managing.isDisjoint(with: [.build, .betaTesting, .availability, .money,
                                       .reviewInfo, .plan, .release]))
    // Every tab belongs somewhere, or the sidebar would hide it for good.
    #expect(Tab.allCases.allSatisfy { !$0.modes.isEmpty })
}

/// Two rows of one sidebar may never read the same.
///
/// Details and Media belong to both modes, so the plain `title` repeats inside
/// Managing. The shell draws `title(in:)` for that reason, and a tab added to
/// a second mode later would repeat again with nothing to catch it.
@Test func noModeShowsTwoTabsUnderOneName() {
    for mode in Mode.allCases {
        let names = Tab.tabs(in: mode).map { $0.title(in: mode) }
        #expect(Set(names).count == names.count,
                "\(mode.title) repeats a tab name in \(names).")
    }
}

/// Choosing a tab of the other mode switches the shell, so the content and the
/// sidebar never disagree.
@MainActor
@Test func aTabOfTheOtherModeSwitchesTheMode() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    #expect(state.mode == .publishing)

    state.selectedTab = .liveApp
    #expect(state.mode == .managing)

    state.selectedTab = .build
    #expect(state.mode == .publishing)

    // Switching the mode moves off a tab the new mode does not hold.
    state.mode = .managing
    #expect(Tab.tabs(in: .managing).contains(state.selectedTab))
}

/// The mode outlives a launch, the same way the open app does.
@MainActor
@Test func theModeSurvivesARelaunch() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let account = "test-\(UUID().uuidString)"
    let first = AppState(defaults: defaults, storeAccount: account)
    first.mode = .managing

    let relaunched = AppState(defaults: defaults, storeAccount: account)

    #expect(relaunched.mode == .managing)
    #expect(Tab.tabs(in: .managing).contains(relaunched.selectedTab))
}

@MainActor
@Test func offerPriceKeepsTheFirstHalfUntilTheSecondFieldIsEntered() throws {
    let state = AppState()
    state.manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable,
        offers: [Manifest.Offer(id: "launch", kind: .promotional)])]
    let target = OfferTarget.purchase(0)

    state.offerBinding(target, index: 0, field: .amount).wrappedValue = "4.99"
    #expect(state.offerBinding(target, index: 0, field: .amount).wrappedValue == "4.99")
    #expect(state.manifest.purchases?[0].offers?[0].price == nil)

    state.offerBinding(target, index: 0, field: .currency).wrappedValue = "usd"
    let price = try #require(state.manifest.purchases?[0].offers?[0].price)
    #expect(price.amount == Decimal(string: "4.99"))
    #expect(price.currency == "USD")
    #expect(state.moneyError == nil)
}

/// The sidebar draws these in the box at the foot of the column, at a fixed
/// place that does not depend on the mode. One that belonged to a single mode
/// would keep its place in the other one and open a tab that mode does not
/// hold.
@Test func theStandAloneTabsBelongToEveryMode() {
    for tab in Tab.allCases.filter(\.standsAlone) {
        #expect(tab.modes == Set(Mode.allCases), "\(tab.title) is missing from a mode.")
    }
}

/// Account answers who you are and what you have paid for, and both are true
/// before the first folder is linked. Sending a developer to "pick an app"
/// before they can sign in is a door that leads back to the door.
@MainActor
@Test func theAccountTabOpensWithNoAppLinked() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    #expect(state.manifestURL == nil)
    #expect(state.hasNoOpenApp)

    state.selectedTab = .account
    #expect(!state.showsEntryScreen, "The Account tab must survive the entry screen.")

    state.selectedTab = .build
    #expect(state.showsEntryScreen, "Every other tab needs an app.")
}

/// About is the label on the tin: a panel, and never a step of the work.
///
/// Settings was one of these until it grew four sections behind a strip of its
/// own. A screen of that size is a screen, and it is a tab now, in the footer
/// box with the other two that are about this Mac rather than about an app.
@Test func theAboutRowIsNotATab() {
    #expect(!Tab.allCases.map(\.title).contains("About"))
    #expect(Tab.settings.standsAlone)
}

/// Every screen that stands alone opens with nothing linked, or the developer
/// meets a door that leads back to the door: no key, no account, and no way to
/// change a setting until a folder is picked.
@MainActor
@Test func theMachineTabsSurviveAnEmptyWindow() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    #expect(state.manifestURL == nil)

    for tab in Tab.allCases.filter(\.standsAlone) {
        state.selectedTab = tab
        #expect(!state.showsEntryScreen, "\(tab.title) is covered by the entry screen.")
    }
}

/// A universal app holds a version train per platform under one app id, each
/// with its own numbers, text, and screenshots. Nothing chose between them:
/// the import wrote the platforms in `allCases` order and every read took
/// `.first`, so a developer publishing the Mac build silently got the iOS
/// train and an empty Media tab.
@MainActor
@Test func choosingThePlatformPutsItAtTheHeadOfTheList() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.manifest.setAppleApp(appID: "6790568884", bundleID: "com.example.app",
                               platforms: [.ios, .macOS])

    #expect(state.applePlatform == .ios)
    #expect(state.appleplatformChoices == [.ios, .macOS])

    state.applePlatform = .macOS

    #expect(state.applePlatform == .macOS)
    // Both stay, so switching back needs no re-import.
    #expect(state.manifest.apps.apple?.platforms == [.macOS, .ios])
    // The picture was read against the other train.
    #expect(state.storeSnapshot.isEmpty)
}

/// One platform is no choice, so the picker stays off the screen.
@MainActor
@Test func oneplatformOffersNoPicker() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.manifest.setAppleApp(appID: "1", bundleID: "com.example.app", platforms: [.macOS])

    #expect(state.appleplatformChoices.isEmpty)
    #expect(state.applePlatform == .macOS)
}

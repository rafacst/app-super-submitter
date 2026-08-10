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
        "Stores", "Build", "Details", "Media", "Monetization",
        "Review info", "Summary", "Release", "Account",
    ])
    #expect(Tab.plan.zone == .reads)
    #expect(Tab.release.zone == .releases)
    // Nothing writes to a store before the tab that shows the diff.
    #expect(Tab.tabs(in: .publishing).firstIndex(of: .plan)!
        < Tab.tabs(in: .publishing).firstIndex(of: .release)!)
}

/// The shape of the sidebar, which is the shape of the app.
///
/// Every row is in a group, and the group says which job it belongs to. The
/// switch above the column then shows one job's groups at a time: see
/// `SidebarModeSwitchTests` for what that hides and what it may not.
@Test func theSidebarListsEveryDestinationInItsSection() {
    #expect(Destination.rows(in: .publish, hasApp: true).map(\.title)
        == ["Stores", "Build", "Details", "Media", "Monetization", "Review info"])
    #expect(Destination.rows(in: .send, hasApp: true).map(\.title)
        == ["Summary", "Release"])
    // Stores heads this one too. Both jobs read the same credentials, and a
    // manager who cannot reach them has to switch jobs to sign in.
    #expect(Destination.rows(in: .manage, hasApp: true).map(\.title)
        == ["Stores", "Live listing", "Live media", "Marketing", "Live app"])

    // Publish and Send are the manifest against the stores: everything that
    // only edits `store.yaml`, then the two screens that talk to a store.
    #expect(Destination.rows(in: .publish, hasApp: true).allSatisfy { $0.tab.zone == .edits })
    #expect(Destination.rows(in: .send, hasApp: true).allSatisfy { $0.tab.zone != .edits })

    // Nothing is lost. Account is the one tab off the list, and the control at
    // the foot of the sidebar opens it.
    let listed = Set(Destination.all(hasApp: true).map(\.tab))
    #expect(Set(Tab.allCases).subtracting(listed) == [.account])
    // Once per job and never twice in one column, which is the claim that
    // matters and the one `SidebarModeSwitchTests` makes.
    #expect(Destination.all(hasApp: true).filter { $0.tab == .stores }.count
        == Mode.allCases.count)
}

/// With no app linked there is nothing to edit, and a row that edits nothing
/// used to show greyed. Stores survives, because it holds the keys the rest
/// waits on and because "Forget" is the only way to remove one on purpose.
@Test func anEmptyWindowKeepsStoresAndNothingElse() {
    #expect(Set(Destination.all(hasApp: false).map(\.title)) == ["Stores"])
    #expect(Destination.rows(in: .send, hasApp: false).isEmpty)
    // Whichever job the switch is on, the empty window offers the one row that
    // fills it.
    #expect(Destination.rows(in: .manage, hasApp: false).map(\.title) == ["Stores"])
    #expect(Destination.rows(in: .publish, hasApp: false).map(\.title) == ["Stores"])
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

    #expect(publishing.intersection(managing) == [.stores, .account, .details, .media])
    #expect(publishing.union(managing) == Set(Tab.allCases))
    #expect(Tab.tabs(in: .managing).map { $0.title(in: .managing) }
        == ["Stores", "Live listing", "Live media", "Marketing", "Live app", "Account"])
    // Nothing that builds, plans, writes, or releases reaches a manager.
    #expect(managing.isDisjoint(with: [.build, .money, .reviewInfo, .plan, .release]))
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

/// The sidebar draws these outside the work column, at a fixed place that does
/// not depend on the mode: Stores at the head, Account in the group about this
/// program. One that belonged to a single mode would keep its place in the
/// other one and open a tab that mode does not hold.
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

/// About and Settings open panels, not tabs, so neither may take a tab's
/// place in the enum and become a tenth step of the work.
@Test func theAboutRowIsNotATab() {
    #expect(!Tab.allCases.map(\.title).contains("About"))
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

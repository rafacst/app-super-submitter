import AppKit
import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A misspelled symbol name draws nothing and says nothing. The sidebar would
/// then show a row with no icon, so every name is resolved here instead.
@Test func everyTabSymbolResolvesInBothStates() {
    let names = Tab.allCases.flatMap { [$0.symbol(selected: false), $0.symbol(selected: true)] }
        + ["gearshape.2", "gearshape.2.fill"]
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

/// The sidebar pins these two under the work and draws every other tab above
/// them. A tab added to `footer` and not to a mode, or the other way round,
/// leaves a row the sidebar draws twice or not at all.
@Test func theFooterTabsBelongToEveryMode() {
    for tab in Tab.footer {
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

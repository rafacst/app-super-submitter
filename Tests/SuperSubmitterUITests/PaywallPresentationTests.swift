import Foundation
import Testing
@testable import SuperSubmitter

/// The paywall was a sheet, and the shell hosts one sheet at a time. Settings
/// is a sheet, so asking for the paywall from inside it set a trigger,
/// presented nothing, and "See plans" did nothing at all. The fix was a queue:
/// close Settings, wait for the dismissal callback, then present.
///
/// None of that is left. The Account tab is part of the window, it is reachable
/// from anywhere including with no app linked, and it carries the plans, the
/// discount code, and the checkout button itself. A gate moves you to it and
/// writes the reason at the top.
@MainActor
private func state() -> AppState {
    AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
             storeAccount: "test-\(UUID().uuidString)")
}

@MainActor
@Test func aGateSendsYouToTheAccountTabAndSaysWhy() {
    let app = state()
    app.openPaywall(.apply)

    #expect(app.selectedTab == .account)
    #expect(app.paywallReason == .apply)
}

/// The detour Settings needed is gone: nothing waits, because nothing is
/// modal. Settings closes and the tab is already there behind it.
@MainActor
@Test func aGateFromInsideSettingsNeedsNoQueue() {
    let app = state()
    app.showSettings = true

    app.openPaywall(.settings)

    #expect(app.showSettings == false)
    #expect(app.selectedTab == .account)
    #expect(app.paywallReason == .settings)
}

/// The reason is a line on a tab, so it has to be dismissable without leaving
/// the tab. The plans stay either way.
@MainActor
@Test func theReasonClearsAndTheTabStays() {
    let app = state()
    app.openPaywall(.upload)

    app.paywallReason = nil

    #expect(app.selectedTab == .account)
}

/// A gate that is satisfied moves nobody and writes no reason.
///
/// A Debug build with no licensing service configured allows every capability
/// and says so on stderr, which is exactly the satisfied case. The Release
/// build refuses at the boundary instead.
@MainActor
@Test func aSatisfiedGateDoesNotSendYouAnywhere() {
    let app = state()
    app.selectedTab = .build

    #expect(app.requirePaid(.storeWrite, .apply))
    #expect(app.selectedTab == .build)
    #expect(app.paywallReason == nil)
}

/// Debug may bypass the write gate for local development, but that bypass is
/// not a paid entitlement and must never be presented as one in Account.
@MainActor
@Test func theDebugGateBypassDoesNotPretendAFreeAccountIsPaid() {
    let app = state()

    #expect(app.can(.storeWrite))
    #expect(!app.entitlement.isPaid)
    #expect(!app.isPaid)
    #expect(app.planLabel == "Free")
    #expect(app.statusLabel == nil)
}

/// A failed provider read is fixed in Settings; store reads are fixed on the
/// Stores tab. The action beside each error must take the same route its copy
/// names.
@MainActor
@Test func readFailureActionsOpenTheRightSurface() {
    let app = state()
    app.selectedTab = .plan

    app.fixReadFailure("Provider: RevenueCat refused the key.")
    #expect(app.showSettings)
    #expect(app.selectedTab == .plan)

    app.showSettings = false
    app.fixReadFailure("Google Play: The credentials were refused.")
    #expect(!app.showSettings)
    #expect(app.selectedTab == .stores)
}

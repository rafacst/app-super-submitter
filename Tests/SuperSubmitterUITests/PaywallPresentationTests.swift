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
/// discount code, and the checkout button itself. A gate moves you to it, and
/// the tab is the answer.
///
/// The gate no longer writes a line on the tab either. The trigger survives as
/// the analytics property on `paywall_gate_hit` and `paywall_shown`, so what a
/// gate is asserted to do is now where it sends you and nothing more.
@MainActor
private func state() -> AppState {
    AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
             storeAccount: "test-\(UUID().uuidString)")
}

@MainActor
@Test func aGateSendsYouToTheAccountTab() {
    let app = state()
    app.openPaywall(.apply)

    #expect(app.selectedTab == .account)
}

/// The detour Settings needed is gone: nothing waits, because nothing is
/// modal. Settings is a tab, and the gate moves the selection to another one.
@MainActor
@Test func aGateFromInsideSettingsNeedsNoQueue() {
    let app = state()
    app.selectedTab = .settings

    app.openPaywall(.settings)

    #expect(app.selectedTab == .account)
}

/// A gate that is satisfied moves nobody.
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
/// names, and both of those are tabs now.
@MainActor
@Test func readFailureActionsOpenTheRightSurface() {
    let app = state()
    app.selectedTab = .plan

    app.fixReadFailure("Provider: RevenueCat refused the key.")
    #expect(app.selectedTab == .settings)

    app.fixReadFailure("Google Play: The credentials were refused.")
    #expect(app.selectedTab == .stores)
}

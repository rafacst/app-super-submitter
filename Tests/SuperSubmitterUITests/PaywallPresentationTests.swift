import Foundation
import Testing
@testable import SuperSubmitter

/// The shell hosts one sheet at a time. Settings is a sheet, so asking for the
/// paywall from inside it used to set the trigger while nothing presented, and
/// "See plans" did nothing at all.
@MainActor
@Test func seePlansFromSettingsWaitsForSettingsToClose() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    state.showSettings = true

    state.openPaywall(.settings)

    // Nothing presents yet, and Settings is on its way out.
    #expect(state.paywall == nil)
    #expect(state.showSettings == false)
    #expect(state.pendingPaywall == .settings)

    // RootView calls this when the Settings sheet finishes dismissing.
    state.openPendingPaywall()

    #expect(state.paywall == .settings)
    #expect(state.pendingPaywall == nil)
}

@MainActor
@Test func aPaywallFromATabPresentsWithNoDetour() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!)

    state.openPaywall(.apply)

    #expect(state.paywall == .apply)
    #expect(state.pendingPaywall == nil)
}

/// Without this the trigger would fire again on the next Settings close, and
/// the paywall would reappear over whatever the user moved on to.
@MainActor
@Test func closingSettingsAgainDoesNotReopenTheSamePaywall() {
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    state.showSettings = true
    state.openPaywall(.settings)
    state.openPendingPaywall()
    state.paywall = nil

    state.openPendingPaywall()

    #expect(state.paywall == nil)
}

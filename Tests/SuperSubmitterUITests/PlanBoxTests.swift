import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The plan box holds three strings: the plan name, a line under it, and a
/// pill. Each one has to carry a different fact.
///
/// The box used to read `Lifetime` over `Active.` with an `Active` pill beside
/// it, and `Free` with a `Free` pill. A word repeated in one box reads as two
/// findings, so the reader looks for the difference between them and there is
/// none.
@MainActor
struct PlanBoxTests {

    private func state() -> AppState {
        AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                 storeAccount: "test-\(UUID().uuidString)")
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func paid(_ plan: AccessPlan, endsOn end: Date? = nil,
                      cancels: Bool? = nil) -> Entitlement {
        Entitlement(subject: "u", status: .active, plan: plan,
                    capabilities: [.storeWrite], issuedAt: now, refreshAfter: now,
                    expiresAt: now.addingTimeInterval(2_592_000),
                    currentPeriodEnd: end, cancelAtPeriodEnd: cancels)
    }

    /// The rule that removes the `Free` beside `Free`: the pill goes silent
    /// where the title is already its word.
    ///
    /// A test build carries no licensing configuration, so `can(_:)` unlocks
    /// everything and the pill here always reads Active. The invariant holds
    /// either way, which is the point of asserting it and not the word.
    @Test func theStatusPillNeverRepeatsThePlanName() {
        let state = state()

        for plan in [AccessPlan.free, .lifetime, .monthly, .annual, .complimentary] {
            state.entitlement = plan == .free ? .free(at: now) : paid(plan)

            #expect(state.statusLabel != state.planLabel,
                    "\(plan.rawValue) puts its own name on the pill beside it")
        }
    }

    @Test func anActivePlanSaysActiveOnThePillAndNowhereElse() {
        let state = state()

        for plan in [AccessPlan.lifetime, .monthly, .annual, .complimentary] {
            state.entitlement = paid(plan, endsOn: plan == .lifetime ? nil : now)

            #expect(state.statusLabel == "Active")
            #expect(!state.entitlementLabel.contains("Active"),
                    "\(plan.rawValue) repeats the pill: \(state.entitlementLabel)")
            #expect(state.entitlementLabel != state.planLabel)
        }
    }

    /// The line under the name carries what the pill cannot: a date, or the
    /// fact that no date exists.
    @Test func theLineUnderTheNameCarriesTheDateAndNotTheStatus() {
        let state = state()

        state.entitlement = paid(.lifetime)
        #expect(state.entitlementLabel == "It does not expire.")

        state.entitlement = paid(.monthly, endsOn: now)
        #expect(state.entitlementLabel.hasPrefix("It renews on"))

        state.entitlement = paid(.annual, endsOn: now, cancels: true)
        #expect(state.entitlementLabel.hasPrefix("It does not renew."))
    }
}

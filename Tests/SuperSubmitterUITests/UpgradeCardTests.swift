import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The offer at the foot of the sidebar, and the four states it may not appear
/// in.
///
/// A card that sells a plan to somebody who already bought one is the failure
/// this file exists to catch. It is asserted here and not in a screenshot: the
/// answer is a boolean, and a boolean is cheaper to assert than to photograph
/// and far harder to misread.
///
/// The three states beside `.free` are the ones that matter most. Each is a
/// person who has paid at some point, and the card is written for a person who
/// never has.
@MainActor
struct UpgradeCardTests {

    private func state() -> AppState {
        AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                 storeAccount: "test-\(UUID().uuidString)")
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entitlement(_ status: EntitlementStatus,
                             plan: AccessPlan = .monthly) -> Entitlement {
        Entitlement(subject: "u", status: status, plan: plan,
                    capabilities: status == .free ? [] : [.storeWrite],
                    issuedAt: now, refreshAfter: now,
                    expiresAt: now.addingTimeInterval(2_592_000))
    }

    @Test func itShowsOnlyForAnAccountThatHasNeverPaid() {
        let state = state()

        state.entitlement = .free(at: now)
        #expect(state.showsUpgradeCard)

        // Each of these is somebody who paid. None of them may be sold to in
        // the words written for somebody who did not.
        for status in [EntitlementStatus.active, .grace, .expired, .revoked] {
            state.entitlement = entitlement(status)
            #expect(!state.showsUpgradeCard,
                    "\(status.rawValue) was offered the first-time upgrade card")
        }
    }

    /// With no plan read, the line states what is free. It has to agree with
    /// `entitlementLabel`, which makes the same promise on the Account tab, or
    /// the app contradicts itself one click apart.
    @Test func theLineNeverContradictsTheFreeTierPromise() {
        let state = state()
        state.entitlement = .free(at: now)

        #expect(state.plan == nil)
        let line = state.upgradeCardLine
        #expect(line.contains("free"))
        // The offer names the one thing that is actually withheld, and nothing
        // else. A card that implies builds or plans are paid would be selling
        // something this app gives away.
        #expect(line.lowercased().contains("sending"))
        #expect(!line.contains("writes are ready"))
    }
}

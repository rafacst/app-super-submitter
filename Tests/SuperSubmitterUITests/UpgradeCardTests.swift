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

    /// The offer never contradicts the free tier.
    ///
    /// It has to agree with `entitlementLabel`, which makes the same promise on
    /// the Account tab, or the app sells one story in the sidebar and another
    /// one click away. The headline leads with the work and the note carries
    /// the promise, so the promise is on the card every time it asks for money.
    @Test func theOfferNeverContradictsTheFreeTierPromise() {
        let state = state()
        state.entitlement = .free(at: now)

        #expect(state.plan == nil)
        // The one thing that is actually withheld, and nothing else. A card
        // that implied builds or plans were paid would be selling something
        // this app gives away.
        #expect(state.upgradeCardNote.lowercased().contains("send"))
        #expect(state.upgradeCardNote.lowercased().contains("free"))
    }

    /// The headline leads with the developer's own work.
    ///
    /// "Sending to a store needs Pro" is true and it is a sentence about what
    /// the app withholds. A developer with writes waiting reads a count and
    /// knows both what they have and what it is for.
    @Test func theHeadlineNamesTheWorkWaitingAndNotTheWall() {
        let state = state()
        state.entitlement = .free(at: now)

        #expect(!state.upgradeCardLine.lowercased().contains("needs pro"))
        #expect(!state.upgradeCardLine.contains("writes"))

        var plan = PlanResult()
        plan.steps = (1...39).map {
            PlanStep(id: "apple.\($0)", system: .apple, kind: .change,
                     summary: "row", title: "Row", requests: [],
                     operation: .appleVersionLocale("en-US"))
        }
        state.plan = plan

        #expect(state.upgradeCardLine.contains("39"))
        #expect(state.upgradeCardLine.lowercased().contains("one pass"))
    }

    /// The button is a verb. "See the plans" invites browsing; a developer who
    /// pressed it wants the one thing the card just named.
    @Test func theButtonSaysWhatPressingItDoes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sidebar = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Shell/Sidebar.swift"),
            encoding: .utf8)

        #expect(sidebar.contains("Text(\"Send with Pro\")"))
        #expect(sidebar.contains("upgradeCardNote"))
        // The label, not the word. The comment above the button still names
        // the copy it replaced, which is the point of the comment.
        #expect(!sidebar.contains("Text(\"See the plans\")"))
    }
}

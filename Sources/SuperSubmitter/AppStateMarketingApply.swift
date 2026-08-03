import Foundation
import SubmitKit

/// The direct write that the Managing mode uses for the marketing resources.
///
/// Publishing writes through the plan: read the stores, show a diff, then
/// apply every row. A manager editing one custom product page wants none of
/// that, so this plans only the marketing rows and runs them on one button.
///
/// The confirmation lives in the view, because the view is where the user is.
/// The safety that stays is the safety that matters here: the resources below
/// all land in a draft or an unstarted state, and none of them reaches a
/// customer until somebody publishes it in App Store Connect.
@MainActor
extension AppState {

    /// The plan rows that the Marketing tab owns.
    static let marketingStepPrefixes = [
        "apple.customProductPages", "apple.experiments", "apple.events",
        "apple.eula", "apple.routingCoverage", "apple.nomination",
        "apple.accessibility", "apple.appClip",
    ]

    /// What the apply would write, named for the confirmation.
    ///
    /// It plans against the state the app already read. Nothing here calls a
    /// store, so the button can label itself without waiting.
    var marketingChanges: [String] {
        let plan = Planner.plan(Planner.Input(
            manifest: manifest, actual: actualState, stores: stores, root: manifestRoot))
        return plan.steps
            .filter { step in
                Self.marketingStepPrefixes.contains { step.id.hasPrefix($0) }
            }
            .map(\.summary)
    }

    var marketingApplyRunning: Bool { marketingApplyState == .running }

    /// Writes the marketing resources, and nothing else.
    ///
    /// A failure names the row that failed and stops there, the same rule the
    /// full run follows. The read afterwards refreshes the comparison, so a
    /// second press writes only what is still missing.
    func applyMarketing() {
        guard !marketingApplyRunning else { return }
        marketingApplyState = .running
        marketingApplyMessage = ""
        let generation = stateGeneration

        Task {
            let plan = Planner.plan(Planner.Input(
                manifest: manifest, actual: actualState, stores: stores, root: manifestRoot))
            var only = PlanResult()
            only.steps = plan.steps.filter { step in
                Self.marketingStepPrefixes.contains { step.id.hasPrefix($0) }
            }
            guard !only.steps.isEmpty else {
                marketingApplyState = .idle
                marketingApplyMessage = "Nothing to write. The App Store already holds it."
                return
            }

            // The runner reports through a stream, and this apply needs one
            // answer: did every row land. A box collects the first failure.
            let box = FailureBox()
            let runner = Runner(
                plan: only, manifest: manifest, actual: actualState, root: manifestRoot,
                credentials: credentials, dryRun: false,
                emit: { event in
                    if case .failure(let failure) = event { box.record(failure.message) }
                    if case .providerFailed(let message) = event { box.record(message) }
                })
            await runner.run()
            guard generation == stateGeneration else { return }

            if let failure = box.message {
                marketingApplyState = .failed
                marketingApplyMessage = failure
            } else {
                marketingApplyState = .done
                marketingApplyMessage = "\(only.steps.count) marketing resources written."
                // The plan compared against a state that is now stale, so the
                // next read is the honest one.
                invalidatePlan()
            }
        }
    }
}

/// Where the one button is.
enum MarketingApplyState: Equatable {
    case idle, running, done, failed
}

/// Holds the first failure a run reported.
///
/// The runner emits from its own actor, so the closure cannot write a local
/// variable. One lock around one optional is the whole need here.
private final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var message: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        if stored == nil { stored = text }
    }
}

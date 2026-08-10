import Foundation
import SubmitKit

/// The direct write that the Managing mode uses.
///
/// Publishing writes through the plan: read the stores, show a diff, then
/// apply every row. A manager editing one description or one custom product
/// page wants none of that, so this plans only the rows of the tab they are
/// on and runs them on one button.
///
/// The confirmation lives in the view, because the view is where the user is.
/// The safety that stays is the safety that matters here: every row below
/// lands in a draft or an unstarted state, and none of them reaches a
/// customer until somebody publishes it in the store console.
@MainActor
extension AppState {

    /// What the apply would write, named for the confirmation.
    ///
    /// It plans against the state the app already read. Nothing here calls a
    /// store, so the button can label itself without waiting.
    func changes(for target: DirectApplyTarget) -> [String] {
        rows(for: target).map(\.summary)
    }

    func directApplyRunning(_ target: DirectApplyTarget) -> Bool {
        directApplyState == .running && directApplyTarget == target
    }

    /// The message belongs to the tab that started the write. Without the
    /// target, the Media tab showed what the Marketing tab had just written.
    func directApplyMessage(for target: DirectApplyTarget) -> String {
        directApplyTarget == target ? directApplyMessage : ""
    }

    func directApplyFailed(_ target: DirectApplyTarget) -> Bool {
        directApplyState == .failed && directApplyTarget == target
    }

    /// Writes the rows of one tab, and nothing else.
    ///
    /// A failure names the row that failed and stops there, the same rule the
    /// full run follows. The read afterwards refreshes the comparison, so a
    /// second press writes only what is still missing.
    func applyDirectly(_ target: DirectApplyTarget) {
        guard directApplyState != .running else { return }
        // These rows land in a store, so they are a store write like any
        // other. Reading and editing them stays free.
        guard requirePaid(.storeWrite, target.trigger) else { return }
        directApplyTarget = target
        directApplyState = .running
        directApplyMessage = ""
        let generation = stateGeneration

        Task {
            var only = PlanResult()
            only.steps = rows(for: target)
            guard !only.steps.isEmpty else {
                directApplyState = .idle
                directApplyMessage = "Nothing to write. The stores already hold it."
                return
            }

            // The runner reports through a stream, and this apply needs one
            // answer: did every row land. A box collects the first failure.
            let box = FailureBox()
            let runner = Runner(
                plan: only, manifest: manifest, actual: actualState, root: manifestRoot,
                credentials: credentials, dryRun: false, access: access,
                emit: { event in
                    if case .failure(let failure) = event { box.record(failure.message) }
                    if case .providerFailed(let message) = event { box.record(message) }
                })
            await runner.run()
            guard generation == stateGeneration else { return }

            if let failure = box.message {
                directApplyState = .failed
                directApplyMessage = failure
            } else {
                directApplyState = .done
                directApplyMessage = "\(only.steps.count) \(target.noun) written."
                // The plan compared against a state that is now stale, so the
                // next read is the honest one.
                invalidatePlan()
            }
        }
    }

    /// The plan rows one tab owns, in plan order.
    ///
    /// Google wraps every write of its own in one edit, so the three
    /// lifecycle rows join whenever a Google row does. Without them the run
    /// would write a listing into an edit that was never opened.
    private func rows(for target: DirectApplyTarget) -> [PlanStep] {
        let plan = directPlan()
        var owned = plan.steps.filter { step in
            target.prefixes.contains { step.id.hasPrefix($0) }
        }
        // The App Store takes no change to a listing customers are reading, so
        // the Manage side counts none of its rows. Offering them made a button
        // whose only outcome was a refusal, and it counted the next version's
        // draft as though the live listing were about to receive it.
        //
        // The promotional text goes with them, which is a real loss: Apple does
        // take that one live. It cannot be sent alone, because the planner ids
        // an Apple listing row per locale rather than per field, so one request
        // carries the description and the keywords beside it.
        if target == .listing, !directApplyOffersAppleListing {
            owned.removeAll { $0.id.hasPrefix("apple.") }
        }
        guard owned.contains(where: { $0.id.hasPrefix("google.") }) else { return owned }
        let lifecycle = Set(["google.openEdit", "google.validate", "google.commit"])
        let ownedIDs = Set(owned.map(\.id))
        return plan.steps.filter { lifecycle.contains($0.id) || ownedIDs.contains($0.id) }
    }

    /// The plan behind the button, kept until the manifest or the store read
    /// changes.
    ///
    /// The bar draws on every keystroke and `Planner.plan` reads and hashes
    /// every screenshot on disk to decide the media rows. Planning per
    /// keystroke rehashed the whole media folder between two letters of a
    /// description.
    private func directPlan() -> PlanResult {
        if let cached = directPlanCache, cached.generation == stateGeneration,
           cached.manifest == manifest {
            return cached.plan
        }
        let plan = Planner.plan(Planner.Input(
            manifest: manifest, actual: actualState, stores: stores, root: manifestRoot))
        directPlanCache = (stateGeneration, manifest, plan)
        return plan
    }
}

/// The Managing tabs that write on one button.
enum DirectApplyTarget: Equatable {
    case listing, media, marketing

    /// The plan rows the tab owns, named by id prefix. They are the same ids
    /// the Summary tab draws, so a row can never mean one thing here and
    /// another there.
    var prefixes: [String] {
        switch self {
        case .listing:
            ["apple.info.", "apple.locale.", "google.listing.", "google.details"]
        case .media:
            ["apple.media.", "apple.preview.", "google.media."]
        case .marketing:
            ["apple.customProductPages", "apple.experiments", "apple.events",
             "apple.eula", "apple.routingCoverage", "apple.nomination",
             "apple.accessibility", "apple.appClip"]
        }
    }

    var noun: String {
        switch self {
        case .listing: "listing fields"
        case .media: "media sets"
        case .marketing: "marketing resources"
        }
    }

    /// The listing and the media are an ordinary store write, so they carry
    /// the same paywall line as the plan does.
    var trigger: PaywallTrigger {
        switch self {
        case .listing, .media: .apply
        case .marketing: .marketing
        }
    }

    /// Where the write lands, for the button and the confirmation. The
    /// marketing resources are the App Store alone.
    func destination(_ stores: Set<Store>) -> String {
        guard self != .marketing else { return "the App Store" }
        let named = [Store.apple, .google].filter(stores.contains).map(\.storeName)
        return named.isEmpty ? "the stores" : named.joined(separator: " and ")
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

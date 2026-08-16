import Foundation
import SubmitKit

struct TestFlightSendPlan: Sendable {
    let platform: Manifest.Platform
    let manifest: Manifest
    let actual: ActualState
    let steps: [PlanStep]
    let generation: Int
}

/// The direct write that the Managing mode uses.
///
/// Publishing writes through the plan: read the stores, show a diff, then
/// apply every row. A manager editing one description or one custom product
/// page wants none of that, so this plans only the rows of the tab they are
/// on and runs them on one button.
///
/// The confirmation lives in the view, because the view is where the user is.
/// The safety that stays is the safety that matters here: every listing, media
/// and marketing row lands in a draft or an unstarted state, and none of them
/// reaches a customer until somebody publishes it in the store console.
///
/// `.testFlight` is the one target that claim does not cover. Its rows email
/// real testers and its last row takes a place in a review queue, so that
/// button reads the store first and says in its own words what it is about to
/// do. `prepareTestFlightSend()` below is the whole difference.
@MainActor
extension AppState {

    /// Reads and plans each selected build train. TestFlight groups belong to
    /// the app, so only the first plan carries their shared rows.
    func prepareTestFlightSend() async -> [TestFlightSendPlan] {
        guard !planReading else { return [] }
        let generation = stateGeneration
        planReading = true
        defer { planReading = false }

        var plans: [TestFlightSendPlan] = []
        for platform in testFlightPlatforms {
            let includesSharedRows = plans.isEmpty
            let plan = await testFlightSendPlan(
                platform: platform, generation: generation,
                includesSharedRows: includesSharedRows)
            plans.append(plan)
        }
        guard generation == stateGeneration else { return [] }
        return plans
    }

    /// Runs the prepared platform plans in order. A later platform gets a new
    /// read after the earlier platform writes the shared group resources.
    func applyTestFlight(_ prepared: [TestFlightSendPlan]) {
        guard directApplyState != .running else { return }
        guard requirePaid(.storeWrite, DirectApplyTarget.testFlight.trigger) else { return }
        guard let generation = prepared.first?.generation,
              generation == stateGeneration else {
            directApplyTarget = .testFlight
            directApplyState = .idle
            directApplyMessage = "The TestFlight settings changed. Read them again."
            return
        }

        directApplyTarget = .testFlight
        directApplyState = .running
        directApplyMessage = ""

        Task {
            let box = FailureBox()
            var written = 0
            for (index, saved) in prepared.enumerated() {
                let current = index == 0 ? saved : await testFlightSendPlan(
                    platform: saved.platform, generation: generation,
                    includesSharedRows: false)
                guard !current.steps.isEmpty else { continue }

                var only = PlanResult()
                only.steps = current.steps
                let runner = Runner(
                    plan: only, manifest: current.manifest, actual: current.actual,
                    root: manifestRoot, credentials: credentials, dryRun: false,
                    access: access, emit: { event in
                        if case .failure(let failure) = event { box.record(failure.message) }
                        if case .providerFailed(let message) = event { box.record(message) }
                    })
                await runner.run()
                if box.message != nil { break }
                written += current.steps.count
            }
            guard generation == stateGeneration else { return }

            if let failure = box.message {
                directApplyState = .failed
                directApplyMessage = failure
            } else {
                directApplyState = .done
                directApplyMessage = "\(written) TestFlight \(written == 1 ? "row" : "rows") written."
                remoteSavedAt = Date()
                invalidatePlan()
            }
        }
    }

    /// The Game Center errors that would stop the apply partway.
    ///
    /// The send button reads these before it offers to write. Every one of
    /// them is a value Apple refuses, and a refusal halfway through leaves the
    /// objects written before it in App Store Connect: the id rules, the point
    /// limits, and a link that names an object the manifest does not hold.
    func gameCenterErrors() -> [Finding] {
        directPlan().findings.filter { $0.fix == .gaming && $0.severity == .error }
    }

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

    /// Reads the stores first, then writes only the rows owned by one tab.
    func saveRemotely(_ target: DirectApplyTarget) {
        guard directApplyState != .running, !planReading, !showsRun || runDone else { return }
        guard requirePaid(.storeWrite, target.trigger) else { return }
        flushSave()

        if target == .testFlight {
            Task {
                let prepared = await prepareTestFlightSend()
                guard !prepared.flatMap(\.steps).isEmpty else {
                    directApplyTarget = target
                    directApplyState = .idle
                    directApplyMessage = "Nothing to write. The store already holds it."
                    remoteSavedAt = Date()
                    return
                }
                applyTestFlight(prepared)
            }
            return
        }

        directApplyTarget = target
        directApplyState = .running
        directApplyMessage = "Reading the stores…"
        let generation = stateGeneration
        Task {
            await readStores()
            guard generation == stateGeneration else {
                directApplyState = .failed
                directApplyMessage = "The tab changed during the store read. Save it again."
                return
            }
            guard planReadFailures.isEmpty else {
                directApplyState = .failed
                directApplyMessage = planReadFailures.first ?? "The stores could not be read."
                return
            }
            directApplyState = .idle
            applyDirectly(target)
        }
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
                remoteSavedAt = Date()
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
                remoteSavedAt = Date()
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
        rows(for: target, in: directPlan())
    }

    private func rows(for target: DirectApplyTarget, in plan: PlanResult) -> [PlanStep] {
        var owned = plan.steps.filter { target.owns($0.id) }
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

    private func testFlightSendPlan(
        platform: Manifest.Platform, generation: Int,
        includesSharedRows: Bool) async -> TestFlightSendPlan {
        var platformManifest = manifest
        if let apple = platformManifest.apps.apple {
            var platforms = apple.platforms.filter { $0 != platform }
            platforms.insert(platform, at: 0)
            platformManifest.setAppleApp(
                appID: apple.appId, bundleID: apple.bundleId, platforms: platforms)
        }
        let actual = await StateReader(api: readOnlyAPI()).read(
            manifest: platformManifest, stores: [.apple], provider: .none)
        let result = Planner.plan(Planner.Input(
            manifest: platformManifest, actual: actual, stores: [.apple],
            root: manifestRoot, packages: packages))
        var steps = rows(for: .testFlight, in: result)
        if !includesSharedRows {
            steps.removeAll { !Self.isBuildSpecificTestFlightStep($0) }
        }
        return TestFlightSendPlan(
            platform: platform, manifest: platformManifest, actual: actual,
            steps: steps, generation: generation)
    }

    private static func isBuildSpecificTestFlightStep(_ step: PlanStep) -> Bool {
        step.id.hasPrefix("apple.build")
            || step.id.hasPrefix("apple.betaBuild.")
            || step.id == "apple.whatToTest"
            || step.id == "apple.betaAutoNotify"
            || step.id == "apple.betaReview"
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

/// The rows that one editing tab can write without a release.
enum DirectApplyTarget: Equatable {
    case build, listing, media, availability, money, marketing, reviewInfo,
         testFlight, gameCenter

    /// The plan rows the tab owns, named by id prefix. They are the same ids
    /// the Summary tab draws, so a row can never mean one thing here and
    /// another there.
    var prefixes: [String] {
        switch self {
        case .build:
            ["apple.version", "apple.build", "apple.attachBuild", "apple.encryption",
             "google.bundle", "google.apk", "google.externalApk", "google.deobfuscation.",
             "google.expansion.", "google.deviceTierConfig", "google.createTrack.",
             "google.track."]
        case .listing:
            ["apple.info.", "apple.locale.", "apple.categories", "apple.eula",
             "apple.accessibility", "google.listing.", "google.details"]
        case .media:
            ["apple.media.", "apple.preview.", "google.media."]
        case .availability:
            ["apple.appPrice", "apple.availability"]
        case .money:
            ["apple.purchases", "apple.purchaseOfferCodes.", "apple.subscriptions",
             "apple.subscriptionOffers", "apple.gracePeriod", "google.products",
             "google.oneTime", "google.purchaseOptionState.", "google.basePlanState.",
             "google.subscription", "google.migratePrices.", "provider."]
        case .marketing:
            ["apple.customProductPages", "apple.experiments", "apple.events",
             "apple.routingCoverage", "apple.nomination", "apple.appClip"]
        case .reviewInfo:
            ["apple.reviewDetails", "apple.ageRating", "google.dataSafety", "google.details"]
        // The whole beta, in plan order: the upload and its compliance answer,
        // then the groups, the testers, the build each group receives, the
        // notes, the page, the licence, the review contact, and the queue.
        //
        // "apple.build" catches `apple.buildCompliance` beside `apple.build`
        // and that is deliberate: Apple gives no build to a tester until the
        // encryption question on it is answered. It does not catch
        // `apple.attachBuild`, which belongs to the App Store version and to
        // no part of TestFlight.
        case .testFlight:
            ["apple.build", "apple.beta", "apple.whatToTest"]
        // The whole Game Center configuration, in plan order: the detail, the
        // group, the five families with their locales and their pictures, the
        // matchmaking, and last the App Store version that carries it.
        //
        // One prefix catches all of it, because every step id here starts with
        // it and no other step does. It catches no build row: none of this
        // needs one, which is why the tab has a button at all.
        case .gameCenter:
            ["apple.gameCenter."]
        }
    }

    func owns(_ id: String) -> Bool {
        if self == .build, id == "apple.versionAttributes" { return false }
        return prefixes.contains { id.hasPrefix($0) }
    }

    var noun: String {
        switch self {
        case .build: "build rows"
        case .listing: "listing fields"
        case .media: "media sets"
        case .availability: "availability rows"
        case .money: "monetization rows"
        case .marketing: "marketing resources"
        case .reviewInfo: "review rows"
        case .testFlight: "TestFlight rows"
        case .gameCenter: "Game Center rows"
        }
    }

    /// The listing and the media are an ordinary store write, so they carry
    /// the same paywall line as the plan does.
    var trigger: PaywallTrigger {
        switch self {
        case .build, .listing, .media, .availability, .money, .reviewInfo,
             .testFlight, .gameCenter: .apply
        case .marketing: .marketing
        }
    }

    /// Where the write lands, for the button and the confirmation. The
    /// marketing resources are the App Store alone.
    func destination(_ stores: Set<Store>) -> String {
        if self == .marketing || self == .availability { return "the App Store" }
        if self == .testFlight { return "TestFlight" }
        if self == .gameCenter { return "Game Center" }
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

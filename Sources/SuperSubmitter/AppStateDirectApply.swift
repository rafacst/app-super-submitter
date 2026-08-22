import Foundation
import SubmitKit

struct TestFlightSendPlan: Sendable {
    let platform: Manifest.Platform
    let manifest: Manifest
    let actual: ActualState
    let steps: [PlanStep]
    let generation: Int
}

enum RemoteSaveRequirement: Equatable {
    case ready
    case needsAppStoreDraft
    case uploadBuildAndSaveDraft
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

    var remoteSaveProgress: Double? {
        guard !remoteSaveStepStates.isEmpty else { return nil }
        let completed = remoteSaveStepStates.filter {
            $0 == .done || $0 == .failed || $0 == .skipped
        }.count
        return Double(completed) / Double(remoteSaveStepStates.count)
    }

    var remoteSaveLogText: String { remoteSaveLogFullLines.joined(separator: "\n") }

    /// Starts one temporary activity tab for the remote save.
    func beginRemoteSave(_ target: DirectApplyTarget) {
        remoteSaveContinuation?.finish()
        remoteSaveEventTask?.cancel()
        remoteSaveSourceTitle = selectedTab.title(in: mode)
        remoteSaveVisible = true
        remoteSaveSteps = []
        remoteSaveStepStates = []
        remoteSaveDetail = "Preparing the remote save…"
        remoteSaveLogLines = []
        remoteSaveLogFullLines = []
        remoteSaveLoggedCalls = 0
        directApplyTarget = target

        let events = AsyncStream<RunEvent>.makeStream()
        remoteSaveContinuation = events.continuation
        remoteSaveEventTask = Task { @MainActor [weak self] in
            for await event in events.stream { self?.handleRemoteSave(event) }
        }
        mode = .publishing
        selectedTab = .remoteSave
    }

    /// Removes the activity tab and its temporary data.
    func clearRemoteSave() {
        remoteSaveVisible = false
        remoteSaveSteps = []
        remoteSaveStepStates = []
        remoteSaveDetail = ""
        remoteSaveLogLines = []
        remoteSaveLogFullLines = []
        remoteSaveLoggedCalls = 0
        remoteSaveContinuation?.finish()
        remoteSaveContinuation = nil
        remoteSaveEventTask?.cancel()
        remoteSaveEventTask = nil
    }

    /// Records one sanitized store call in the temporary log.
    func recordRemoteSave(_ call: APICall, at date: Date = Date()) {
        guard remoteSaveVisible else { return }
        remoteSaveLoggedCalls += 1
        remoteSaveLogLines.append(call.line(at: date))
        remoteSaveLogFullLines.append(call.fullLine(at: date))
        if remoteSaveLogLines.count > 500 {
            remoteSaveLogLines.removeFirst(remoteSaveLogLines.count - 500)
        }
        if remoteSaveLogFullLines.count > Self.logLimit {
            remoteSaveLogFullLines.removeFirst(remoteSaveLogFullLines.count - Self.logLimit)
        }
    }

    private func remoteSaveRecorder() -> CallRecorder {
        { [weak self] call in await self?.recordRemoteSave(call) }
    }

    private func handleRemoteSave(_ event: RunEvent) {
        guard remoteSaveVisible else { return }
        switch event {
        case .step(let index, let state, _):
            guard remoteSaveStepStates.indices.contains(index) else { return }
            remoteSaveStepStates[index] = state
            if state == .running {
                remoteSaveDetail = remoteSaveSteps[index].title
            }
        case .progress(_, _, let detail):
            remoteSaveDetail = detail
        case .log(let call, let date):
            recordRemoteSave(call, at: date)
        case .failure(let failure):
            remoteSaveDetail = failure.message
        case .providerFailed(let message):
            remoteSaveDetail = message
        case .finished:
            break
        }
    }

    /// Reads and plans each selected build train. TestFlight groups belong to
    /// the app, so only the first plan carries their shared rows.
    func prepareTestFlightSend(record: @escaping CallRecorder = { _ in }) async
        -> [TestFlightSendPlan] {
        guard !planReading else { return [] }
        let generation = stateGeneration
        planReading = true
        defer { planReading = false }

        var plans: [TestFlightSendPlan] = []
        for platform in testFlightPlatforms {
            let includesSharedRows = plans.isEmpty
            let plan = await testFlightSendPlan(
                platform: platform, generation: generation,
                includesSharedRows: includesSharedRows, record: record)
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
                    includesSharedRows: false, record: remoteSaveRecorder())
                guard !current.steps.isEmpty else { continue }

                var only = PlanResult()
                only.steps = current.steps
                let continuation = remoteSaveContinuation
                let runner = Runner(
                    plan: only, manifest: current.manifest, actual: current.actual,
                    root: manifestRoot, credentials: credentials, dryRun: false,
                    access: access, emit: { event in
                        continuation?.yield(event)
                        if case .failure(let failure) = event { box.record(failure.message) }
                        if case .providerFailed(let message) = event { box.record(message) }
                    })
                if remoteSaveVisible {
                    remoteSaveSteps = current.steps
                    remoteSaveStepStates = Array(repeating: .pending, count: current.steps.count)
                }
                await runner.run()
                if box.message != nil { break }
                written += current.steps.count
            }
            guard generation == stateGeneration else { return }

            if let failure = box.message {
                directApplyState = .failed
                directApplyMessage = failure
                remoteSaveDetail = failure
            } else {
                directApplyState = .done
                directApplyMessage = "\(written) TestFlight \(written == 1 ? "row" : "rows") written."
                remoteSaveDetail = directApplyMessage
                remoteSavedAt = Date()
                invalidatePlan()
            }
            remoteSaveContinuation?.finish()
            remoteSaveContinuation = nil
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

    func remoteSaveRequirement(for target: DirectApplyTarget, actual: ActualState,
                               hasLocalBuild: Bool) -> RemoteSaveRequirement {
        guard target != .build, stores.contains(.apple),
              actual.apple?.versionId == nil else { return .ready }
        return hasLocalBuild ? .uploadBuildAndSaveDraft : .needsAppStoreDraft
    }

    private static let buildAndDraftOffer = "No App Store draft is available. "
        + "Super Submitter found a local build. Upload the build and save this tab as a draft?"

    var remoteSaveOffersBuildUpload: Bool {
        remoteSaveVisible && directApplyMessage == Self.buildAndDraftOffer
    }

    var remoteSaveUploadsBuild: Bool {
        remoteSaveVisible && directApplyMessage == "Uploading the build…"
    }

    func uploadBuildAndSaveDraft() {
        guard let target = directApplyTarget else { return }
        saveRemotely(target, includeAppleBuild: true)
    }

    /// Reads the stores first, then writes only the rows owned by one tab.
    func saveRemotely(_ target: DirectApplyTarget) {
        saveRemotely(target, includeAppleBuild: false)
    }

    private func saveRemotely(_ target: DirectApplyTarget, includeAppleBuild: Bool,
                              didUploadBuild: Bool = false) {
        guard directApplyState != .running, !planReading, !showsRun || runDone else { return }
        guard requirePaid(.storeWrite, target.trigger) else { return }
        flushSave()
        beginRemoteSave(target)

        directApplyTarget = target
        directApplyState = .running
        directApplyMessage = "Reading the stores…"
        let generation = stateGeneration
        Task {
            let prepared = await remoteSaveRead(
                for: target, includeAppleBuild: includeAppleBuild,
                record: remoteSaveRecorder())
            guard generation == stateGeneration else {
                directApplyState = .failed
                directApplyMessage = "The tab changed during the store read. Save it again."
                remoteSaveDetail = directApplyMessage
                return
            }
            guard prepared.failures.isEmpty else {
                directApplyState = .failed
                directApplyMessage = prepared.failures.first ?? "The stores could not be read."
                remoteSaveDetail = directApplyMessage
                return
            }
            switch remoteSaveRequirement(
                for: target, actual: prepared.actual,
                hasLocalBuild: prepared.hasLocalBuild) {
            case .ready:
                break
            case .needsAppStoreDraft:
                guard didUploadBuild else {
                    stopRemoteSave("No App Store draft is available. Create a draft in App "
                        + "Store Connect, or create a build in Super Submitter and upload it.")
                    return
                }
            case .uploadBuildAndSaveDraft:
                guard includeAppleBuild else {
                    stopRemoteSave(Self.buildAndDraftOffer)
                    return
                }
                guard prepared.hasPlannedAppleBuild else {
                    uploadLocalBuildThenSave(target)
                    return
                }
            }
            if target == .testFlight, !includeAppleBuild {
                directApplyState = .idle
                saveTestFlightRemotely()
                return
            }
            directApplyState = .idle
            applyDirectly(target, using: (
                actual: prepared.actual, steps: prepared.steps,
                failures: prepared.failures), includesAppleBuild: includeAppleBuild)
        }
    }

    private func saveTestFlightRemotely() {
        Task {
            let prepared = await prepareTestFlightSend(record: remoteSaveRecorder())
            guard !prepared.flatMap(\.steps).isEmpty else {
                directApplyState = .idle
                directApplyMessage = "Nothing to write. The store already holds it."
                remoteSaveDetail = directApplyMessage
                remoteSavedAt = Date()
                remoteSaveContinuation?.finish()
                remoteSaveContinuation = nil
                return
            }
            applyTestFlight(prepared)
        }
    }

    private func stopRemoteSave(_ message: String) {
        directApplyState = .failed
        directApplyMessage = message
        remoteSaveDetail = message
        remoteSaveContinuation?.finish()
        remoteSaveContinuation = nil
    }

    /// Reads the one area this tab writes, and plans its rows against it.
    ///
    /// It is deliberately not `readStores`. That read is the plan's read: it
    /// publishes `actualState`, the store snapshot, the console checklist and
    /// the dock badge, so every tab in the app draws what it returned. An area
    /// of it left unread would blank the "what the store holds" column
    /// everywhere, so a narrowed read cannot be that one. This keeps its answer
    /// to itself, and the save is the only thing planned from it.
    ///
    /// The same shape `prepareTestFlightSend` already uses.
    private func remoteSaveRead(for target: DirectApplyTarget,
                                includeAppleBuild: Bool,
                                record: @escaping CallRecorder) async
        -> (actual: ActualState, steps: [PlanStep], failures: [String],
            hasLocalBuild: Bool, hasPlannedAppleBuild: Bool) {
        guard !planReading else { return (ActualState(), [], [], false, false) }
        planReading = true
        defer { planReading = false }

        let areas = target.readAreas
        let actual = await StateReader(api: readOnlyAPI(record: record)).read(
            manifest: manifest, stores: stores,
            // The provider mirrors the catalog, so a tab that does not read one
            // has nothing to compare the other against.
            provider: areas.contains(.catalog) ? provider : .none,
            areas: areas)
        let result = Planner.plan(Planner.Input(
            manifest: manifest, actual: actual, stores: stores,
            root: manifestRoot, packages: packages))
        let hasPlannedAppleBuild = result.steps.contains {
            $0.system == .apple && $0.id == "apple.build"
        }
        return (actual,
                remoteSaveRows(for: target, in: result,
                               includeAppleBuild: includeAppleBuild),
                actual.failures + result.readFailures,
                hasPlannedAppleBuild || hasLocalAppleBuild,
                hasPlannedAppleBuild)
    }

    private var hasLocalAppleBuild: Bool {
        let flow = buildFlow
        guard let candidate = flow.candidate,
              candidate.platform != .android,
              candidate.artifactURL.pathExtension.lowercased() == "xcarchive",
              !candidate.deleted,
              FileManager.default.fileExists(atPath: candidate.artifactPath),
              !flow.state.isActive,
              candidate.blockingMismatches.isEmpty,
              flow.blocking == nil,
              flow.uploadBlockedByReview == nil else { return false }
        return flow.state == .needsUploadConfirmation
            || (flow.state == .complete && flow.artifactOnly)
            || (flow.state == .failed && flow.uploadStatus == .failed)
    }

    private func uploadLocalBuildThenSave(_ target: DirectApplyTarget) {
        let flow = buildFlow
        guard hasLocalAppleBuild, let candidate = flow.candidate else {
            stopRemoteSave("The local build is no longer available. Create or import a build, "
                + "then save this tab again.")
            return
        }
        if flow.state == .complete, flow.artifactOnly {
            flow.run = UploadRun(platform: candidate.platform,
                                 linkedProjectID: flow.project?.id,
                                 state: .needsUploadConfirmation)
            flow.run.candidateIdentity = candidate.logicalIdentity
            flow.candidate?.settled = false
            flow.artifactOnly = false
        } else if flow.state == .failed {
            flow.run.move(to: .needsUploadConfirmation)
        }
        guard flow.state == .needsUploadConfirmation, flow.canUpload else {
            stopRemoteSave("The local build cannot be uploaded. Open the Build tab for details.")
            return
        }

        directApplyState = .running
        directApplyMessage = "Uploading the build…"
        remoteSaveDetail = directApplyMessage
        flow.task = nil
        flow.startUpload()
        guard let upload = flow.task else {
            stopRemoteSave("The build upload did not start.")
            return
        }
        Task {
            await upload.value
            guard flow.state == .complete, flow.uploadStatus == .succeeded else {
                stopRemoteSave(flow.failure?.message
                    ?? "The build did not reach App Store Connect.")
                return
            }
            adoptBuiltArtifact(from: flow)
            directApplyState = .idle
            saveRemotely(target, includeAppleBuild: true, didUploadBuild: true)
        }
    }

    /// Writes the rows of one tab, and nothing else.
    ///
    /// A failure names the row that failed and stops there, the same rule the
    /// full run follows. The read afterwards refreshes the comparison, so a
    /// second press writes only what is still missing.
    func applyDirectly(
        _ target: DirectApplyTarget,
        using prepared: (actual: ActualState, steps: [PlanStep], failures: [String])? = nil,
        includesAppleBuild: Bool = false
    ) {
        guard directApplyState != .running else { return }
        // These rows land in a store, so they are a store write like any
        // other. Reading and editing them stays free.
        guard requirePaid(.storeWrite, target.trigger) else { return }
        directApplyTarget = target
        directApplyState = .running
        directApplyMessage = ""
        let generation = stateGeneration
        // The read that planned these rows, where there was one. It knows only
        // this tab's area of the store, and the rows below are this tab's, so
        // the pair match. `actualState` is the plan's, read in full, and it is
        // what an apply that did its own planning still uses.
        let actual = prepared?.actual ?? actualState

        Task {
            var only = PlanResult()
            only.steps = prepared?.steps ?? rows(for: target)
            // Nothing this tab does not own reaches a store.
            //
            // The read above knows one area of the app, so the planner it fed
            // saw no purchase, no product page and no Game Center object, and a
            // planner that sees none of a thing plans to create it. Those rows
            // are not this tab's and `rows(for:in:)` drops them, and this is the
            // second lock on the same door: a prefix list that stops matching
            // the planner's ids fails the save here rather than writing a row
            // out of an area nobody read.
            let foreign = only.steps.filter {
                !target.owns($0.id)
                    && !(includesAppleBuild && $0.system == .apple
                         && DirectApplyTarget.build.owns($0.id))
                    && !Self.googleLifecycleIDs.contains($0.id)
            }
            guard foreign.isEmpty else {
                directApplyState = .failed
                directApplyMessage = "This save planned a row it does not own "
                    + "(\(foreign.map(\.id).joined(separator: ", "))). Nothing was written."
                remoteSaveDetail = directApplyMessage
                remoteSaveContinuation?.finish()
                remoteSaveContinuation = nil
                return
            }
            guard !only.steps.isEmpty else {
                directApplyState = .idle
                directApplyMessage = "Nothing to write. The stores already hold it."
                remoteSaveDetail = directApplyMessage
                remoteSavedAt = Date()
                remoteSaveContinuation?.finish()
                remoteSaveContinuation = nil
                return
            }

            if remoteSaveVisible {
                remoteSaveSteps = only.steps
                remoteSaveStepStates = Array(repeating: .pending, count: only.steps.count)
            }

            // The runner reports through a stream, and this apply needs one
            // answer: did every row land. A box collects the first failure.
            let box = FailureBox()
            let continuation = remoteSaveContinuation
            let runner = Runner(
                plan: only, manifest: manifest, actual: actual, root: manifestRoot,
                credentials: credentials, dryRun: false, access: access,
                emit: { event in
                    continuation?.yield(event)
                    if case .failure(let failure) = event { box.record(failure.message) }
                    if case .providerFailed(let message) = event { box.record(message) }
                })
            await runner.run()
            guard generation == stateGeneration else { return }

            if let failure = box.message {
                directApplyState = .failed
                directApplyMessage = failure
                remoteSaveDetail = failure
            } else {
                directApplyState = .done
                directApplyMessage = "\(only.steps.count) \(target.noun) written."
                remoteSaveDetail = directApplyMessage
                remoteSavedAt = Date()
                // The plan compared against a state that is now stale, so the
                // next read is the honest one.
                invalidatePlan()
                // The pictures belong to the store from here on, so the local
                // list goes and the store answers for them. The read is the
                // second half of that sentence: without it the tab would show
                // the strip from before the upload and call it live.
                if adoptSentMedia(only.steps) { await readStores() }
            }
            continuation?.finish()
            if remoteSaveContinuation != nil { remoteSaveContinuation = nil }
        }
    }

    /// The plan rows one tab owns, in plan order.
    ///
    /// Google wraps every write of its own in one edit, so the three
    /// lifecycle rows join whenever a Google row does. Without them the run
    /// would write a listing into an edit that was never opened.
    private func rows(for target: DirectApplyTarget) -> [PlanStep] {
        remoteSaveRows(for: target, in: directPlan())
    }

    func remoteSaveRows(for target: DirectApplyTarget, in plan: PlanResult,
                        includeAppleBuild: Bool = false) -> [PlanStep] {
        var owned = plan.steps.filter { target.owns($0.id) }
        if includeAppleBuild {
            let ownedIDs = Set(owned.map(\.id)).union(plan.steps.compactMap { step in
                step.system == .apple && DirectApplyTarget.build.owns(step.id) ? step.id : nil
            })
            owned = plan.steps.filter { ownedIDs.contains($0.id) }
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
        let ownedIDs = Set(owned.map(\.id))
        return plan.steps.filter {
            Self.googleLifecycleIDs.contains($0.id) || ownedIDs.contains($0.id)
        }
    }

    /// The three rows that wrap every Google write. No tab owns them, and any
    /// tab that writes to Google needs all three.
    static let googleLifecycleIDs = Set(["google.openEdit", "google.validate",
                                         "google.commit"])

    private func testFlightSendPlan(
        platform: Manifest.Platform, generation: Int,
        includesSharedRows: Bool, record: @escaping CallRecorder) async -> TestFlightSendPlan {
        var platformManifest = manifest
        if let apple = platformManifest.apps.apple {
            var platforms = apple.platforms.filter { $0 != platform }
            platforms.insert(platform, at: 0)
            platformManifest.setAppleApp(
                appID: apple.appId, bundleID: apple.bundleId, platforms: platforms)
        }
        let actual = await StateReader(api: readOnlyAPI(record: record)).read(
            manifest: platformManifest, stores: [.apple], provider: .none)
        let result = Planner.plan(Planner.Input(
            manifest: platformManifest, actual: actual, stores: [.apple],
            root: manifestRoot, packages: packages))
        var steps = remoteSaveRows(for: .testFlight, in: result)
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

    /// What a save of this tab has to read before it writes.
    ///
    /// A save compares one tab against the store and writes the rows that
    /// differ, so it reads that tab's area and no other. Saving a description
    /// used to read the whole app: every in-app purchase, every subscription
    /// and its group, the price ladder, the marketing resources, TestFlight and
    /// the Game Center configuration. Forty requests to build a comparison that
    /// only the listing rows were ever taken from.
    ///
    /// The plan needs the app, its version, its localizations, its categories
    /// and its build for any diff at all, and `StateReader` reads those at all
    /// times. These are the blocks on top.
    var readAreas: StateReader.Areas {
        switch self {
        // The version, the build and the tracks are all read anyway.
        case .build, .listing, .media, .reviewInfo: []
        case .availability: .pricing
        // A price on a product is compared against the ladder Apple sells at.
        case .money: [.catalog, .pricing]
        case .marketing: .marketing
        case .testFlight: .testFlight
        case .gameCenter: .gameCenter
        }
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

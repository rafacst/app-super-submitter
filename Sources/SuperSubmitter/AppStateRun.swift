import AppKit
import Foundation
import PostHog
import SubmitKit
import SwiftUI
import UserNotifications

/// Tabs 7, 8, and 9, and the status behind the menu bar item.
///
/// The views stay thin: every rule lives in SubmitKit, and this file only
/// moves values between the kit and the screen.
@MainActor
extension AppState {

    func appleReleaseTypeBinding() -> Binding<Manifest.Release.ReleaseType> {
        Binding(get: { self.manifest.release?.apple?.releaseType ?? .manual }, set: { value in
            var release = self.manifest.release ?? Manifest.Release()
            var apple = release.apple ?? Manifest.Release.AppleRelease(
                releaseType: nil, phasedRelease: nil,
                phasedReleaseState: nil)
            apple.releaseType = value
            release.apple = apple
            self.manifest.release = release
            self.saveManifestReportingErrors()
        })
    }

    func applePhasedReleaseBinding() -> Binding<Bool> {
        Binding(get: { self.manifest.release?.apple?.phasedRelease ?? false }, set: { value in
            var release = self.manifest.release ?? Manifest.Release()
            var apple = release.apple ?? Manifest.Release.AppleRelease(
                releaseType: nil, phasedRelease: nil,
                phasedReleaseState: nil)
            apple.phasedRelease = value
            apple.phasedReleaseState = value ? (apple.phasedReleaseState ?? .active) : nil
            release.apple = apple
            self.manifest.release = release
            self.saveManifestReportingErrors()
        })
    }

    func applePhasedStateBinding() -> Binding<Manifest.Release.PhasedReleaseState> {
        Binding(get: { self.manifest.release?.apple?.phasedReleaseState ?? .active }, set: { value in
            var release = self.manifest.release ?? Manifest.Release()
            var apple = release.apple ?? Manifest.Release.AppleRelease(
                releaseType: nil, phasedRelease: nil,
                phasedReleaseState: nil)
            apple.phasedRelease = true
            apple.phasedReleaseState = value
            release.apple = apple
            self.manifest.release = release
            self.saveManifestReportingErrors()
        })
    }

    // MARK: - Tab 7. The plan

    /// Takes a failed plan read to the credentials that can fix it.
    func fixReadFailure(_ message: String) {
        if message.hasPrefix("Provider:") {
            showSettings = true
        } else {
            selectedTab = .stores
        }
    }

    var credentials: StoreCredentials {
        StoreCredentials(
            apple: applePrivateKeyPEM.isEmpty ? nil : AppleCredential(
                keyID: appleKeyID, issuerID: appleIssuerID,
                privateKeyPEM: applePrivateKeyPEM, fileName: appleCredentialFileName),
            google: googleCredentialChoice == .serviceAccount ? googleCredential : nil,
            googleOAuth: googleCredentialChoice == .oauth ? googleOAuthCredential : nil,
            revenueCatKey: revenueCatAPIKey.isEmpty ? nil : revenueCatAPIKey,
            reviewer: reviewerUsername.isEmpty ? nil : ReviewerCredential(
                username: reviewerUsername, password: reviewerPassword))
    }

    /// A `StoreAPI` that writes no run log. The plan and the status poll use
    /// it; only a run opens a log file.
    func readOnlyAPI() -> StoreAPI {
        StoreAPI(credentials: credentials, record: { _ in })
    }

    /// The reads that answer a question and change nothing: the generated
    /// APKs, the device tier configurations, the build bundles, the build
    /// icons, and the territory list. None of them belongs in the plan,
    /// because none of them is a desired state.
    func diagnostics() -> StoreDiagnostics {
        StoreDiagnostics(api: readOnlyAPI())
    }

    /// What Google built from the uploaded bundle.
    func googleGeneratedApks(versionCode: Int) async throws -> [StoreDiagnostics.GeneratedApk] {
        guard let packageName = manifest.apps.google?.packageName, !packageName.isEmpty else {
            return []
        }
        return try await diagnostics().generatedApks(packageName: packageName,
                                                     versionCode: versionCode)
    }

    /// The device tier configurations that Google already holds.
    func googleDeviceTierConfigs() async throws -> [StoreDiagnostics.DeviceTierConfig] {
        guard let packageName = manifest.apps.google?.packageName, !packageName.isEmpty else {
            return []
        }
        return try await diagnostics().deviceTierConfigs(packageName: packageName)
    }

    /// Whether the newest configuration already says what the manifest file
    /// says, which is exactly the question the apply asks before it creates
    /// one. Nil when the manifest names no file or Google holds none.
    func googleDeviceTierMatchesManifest() async throws -> Bool? {
        guard let packageName = manifest.apps.google?.packageName, !packageName.isEmpty,
              let path = manifest.release?.google?.deviceTierConfig, !path.isEmpty,
              let url = Planner.resolve(path, root: manifestRoot),
              let body = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)),
              let live = try await diagnostics()
                  .newestDeviceTierFingerprint(packageName: packageName) else { return nil }
        return live == StoreDiagnostics.deviceTierFingerprint(body)
    }

    /// What is inside the build that the version holds: the app bundle, the
    /// extensions, the download size, and the encryption flag.
    func appleBuildBundles() async throws -> [StoreDiagnostics.BuildBundle] {
        guard let buildID = actualState.apple?.attachedBuildId else { return [] }
        return try await diagnostics().buildBundles(buildID: buildID)
    }

    /// Every icon that Apple extracted from the attached build.
    func appleBuildIcons() async throws -> [String] {
        guard let buildID = actualState.apple?.attachedBuildId else { return [] }
        return try await diagnostics().buildIcons(buildID: buildID)
    }

    /// Every App Store territory id, for the availability and the licence
    /// agreement. The developer has no other list to check a code against.
    func appleTerritories() async throws -> [StoreDiagnostics.Territory] {
        try await diagnostics().territories()
    }

    func appleAppCategories() async throws -> [StoreDiagnostics.AppCategory] {
        try await diagnostics().appCategories(
            platform: manifest.apps.apple?.platforms.first?.rawValue)
    }

    /// Reads every store, then diffs. Spec section 7.2. This writes nothing.
    func readStores() async {
        guard !planReading, !showsRun || runDone else { return }
        let generation = stateGeneration
        planReading = true
        planReadFailures = []
        let manifest = self.manifest
        let stores = self.stores
        let provider = self.provider
        let root = manifestRoot
        let packages = self.packages
        let api = readOnlyAPI()

        let actual = await StateReader(api: api).read(manifest: manifest, stores: stores,
                                                      provider: provider)
        let result = Planner.plan(Planner.Input(manifest: manifest, actual: actual,
                                                stores: stores, root: root, packages: packages))
        guard generation == stateGeneration else { return }
        // A new plan invalidates the runner that held the old one.
        runTask?.cancel()
        runTask = nil
        DockTile.clear()
        runContinuation?.finish()
        runContinuation = nil
        eventTask?.cancel()
        eventTask = nil
        runner = nil
        runIndex = -1
        runDone = false
        runProgress = 0
        runDetail = ""
        logLines = []
        // The failure belonged to the run this plan replaces. Its step index
        // points into the old step list, so the panel named no step at all and
        // Retry from the failed step would have started at whatever now sits
        // at that number.
        runFailure = nil
        providerFailure = nil
        plan = result
        actualState = actual
        storeSnapshot.merge(actual)
        storeSnapshot.save(toRoot: manifestRoot)
        consoleRows = ConsoleChecklist.rows(manifest: manifest, actual: actual, stores: stores)
        refreshDockBadge()
        planReadFailures = result.readFailures
        stepStates = Array(repeating: .pending, count: result.steps.count)
        stepMeta = Array(repeating: "", count: result.steps.count)
        refreshDraftStatuses()
        PostHogSDK.shared.capture("plan_generated", properties: [
            "store_count": stores.count,
            "step_count": result.steps.count,
            "is_blocked": result.isBlocked,
            "is_dry_run": dryRun
        ])
        planReading = false
    }

    // MARK: - The build storage. upload-spec section 11.

    var buildStorageSummary: String {
        let storage = BuildStorage()
        let archives = storage.retainedArchives()
        let runs = (try? FileManager.default.contentsOfDirectory(
            atPath: storage.runs.path))?.count ?? 0
        return "\(archives.count) retained \(archives.count == 1 ? "archive" : "archives") · "
            + "\(runs) \(runs == 1 ? "run" : "runs")"
    }

    func revealBuildStorage() {
        let storage = BuildStorage()
        try? FileManager.default.createDirectory(at: storage.root,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([storage.root])
    }

    func pruneBuildStorage() {
        let removed = BuildStorage().prune(olderThan: 30 * 24 * 60 * 60)
        errorMessage = removed.isEmpty
            ? "No run data is older than 30 days."
            : "Removed \(removed.count) run \(removed.count == 1 ? "folder" : "folders"). Every retained archive and App Bundle is untouched."
    }

    /// Carries what Build from Project produced into `store.yaml`, so the
    /// existing Plan reads it. upload-spec section 13.
    ///
    /// Only Android names a file. Its artifact is the exact `.aab` that the
    /// plan uploads. An Apple artifact is an `.xcarchive`, which is a folder
    /// and not a package, and `xcodebuild -exportArchive` already sent the
    /// binary to App Store Connect. A path here made the plan read that folder
    /// as a package, so the apply failed on it and uploaded a build twice.
    /// The store read finds the uploaded build instead, and the plan attaches
    /// it.
    func adoptBuiltArtifact() {
        guard let candidate = buildFlow.candidate else { return }
        var release = manifest.release ?? Manifest.Release()
        if candidate.platform == .android {
            var build = release.build ?? Manifest.Release.Build()
            build.android = candidate.artifactPath
            release.build = build
        }
        if release.versionName?.isEmpty != false {
            release.versionName = candidate.marketingVersion
        }
        manifest.release = release
        saveManifest()
        // The plan must read the store again now that a build landed.
        invalidatePlan()
    }

    func saveManifest() {
        do { try save() }
        catch { errorMessage = "The manifest could not be saved. \(error.localizedDescription)" }
    }

    /// How far the resolved App Store price point sits from the request, as a
    /// fraction. Nil until a read supplies the point.
    var priceGap: Double? {
        guard let resolved = actualState.apple?.priceAmount,
              let requested = manifest.pricing?.base else { return nil }
        let base = (requested.amount as NSDecimalNumber).doubleValue
        guard base > 0 else { return nil }
        return abs((resolved as NSDecimalNumber).doubleValue - base) / base
    }

    /// The tab that fixes a finding. SubmitKit names the target; the app owns
    /// the `Tab` enum.
    func tab(for target: FixTarget) -> Tab {
        switch target {
        case .stores: .stores
        case .build: .build
        case .details: .details
        case .media: .media
        case .money: .money
        case .marketing: .marketing
        case .reviewInfo: .reviewInfo
        case .plan: .plan
        }
    }

    /// Every warning needs one acknowledgement before the apply runs.
    var unacknowledgedWarnings: Int {
        (plan?.warnings ?? []).filter { !acknowledged.contains($0.id) }.count
    }

    var canApply: Bool {
        guard let plan, !plan.isEmpty else { return false }
        // A dry run writes nothing, so it stays free. Anything else needs the
        // capability, and `Runner` asks again before the first request.
        guard dryRun || can(.storeWrite) else { return false }
        return !plan.isBlocked && unacknowledgedWarnings == 0 && !isRunning
    }

    // MARK: - The run, under the plan

    var isRunning: Bool { runIndex >= 0 && !runDone && runFailure == nil }

    /// True while the Summary tab shows the run instead of the diff.
    var showsRun: Bool { runIndex >= 0 }

    /// Puts the plan back in view once a run has finished.
    ///
    /// It clears the view and not the result. `resetRunState` throws the plan
    /// away too, which would make the way back from a dry run a second read of
    /// both stores for a diff that has not changed.
    func dismissRun() {
        guard runDone else { return }
        runIndex = -1
        runDone = false
    }

    var runSteps: [PlanStep] { plan?.steps ?? [] }

    var logText: String { logLines.joined(separator: "\n") }

    func startRun(from start: Int = 0) {
        guard let plan, !plan.steps.isEmpty else { return }
        guard !isRunning else { return }
        // A retry skips `canApply`, so the paywall check cannot live in it.
        guard dryRun || requirePaid(.storeWrite, .apply) else { return }
        guard start > 0 || canApply else { return }
        let previous = runTask
        previous?.cancel()
        PostHogSDK.shared.capture("submission_run_started", properties: [
            "start_step": start,
            "step_count": plan.steps.count,
            "is_dry_run": dryRun
        ])
        runFailure = nil
        providerFailure = nil
        runDone = false
        runIndex = start
        runProgress = 0
        runDetail = ""
        if stepStates.count != plan.steps.count {
            stepStates = Array(repeating: .pending, count: plan.steps.count)
            stepMeta = Array(repeating: "", count: plan.steps.count)
        }
        for index in stepStates.indices where index >= start { stepStates[index] = .pending }

        // A retry keeps the runner, because it holds the Google edit and the
        // ids that the earlier steps created. A fresh apply builds a new one,
        // so a re-read or a flipped dry run takes effect.
        //
        // One runner owns one stream for its whole life: a second stream would
        // leave a retry writing into a finished one and the tab would freeze.
        let runner = start > 0 ? (self.runner ?? makeRunner(for: plan)) : makeRunner(for: plan)
        runTask = Task {
            _ = await previous?.result
            guard !Task.isCancelled else { return }
            await runner.run(from: start)
        }
    }

    private func makeRunner(for plan: PlanResult) -> Runner {
        runContinuation?.finish()
        eventTask?.cancel()
        let events = AsyncStream<RunEvent>.makeStream()
        runContinuation = events.continuation
        let runner = Runner(
            plan: plan, manifest: manifest, actual: actualState, root: manifestRoot,
            credentials: credentials, dryRun: dryRun, access: access,
            emit: { event in events.continuation.yield(event) })
        self.runner = runner
        eventTask = Task { @MainActor [weak self] in
            for await event in events.stream { self?.handle(event) }
        }
        return runner
    }

    private func handle(_ event: RunEvent) {
        switch event {
        case .step(let index, let state, let meta):
            guard stepStates.indices.contains(index), stepMeta.indices.contains(index) else { return }
            stepStates[index] = state
            stepMeta[index] = meta
            if state == .running {
                runIndex = index
                runProgress = 0
                runDetail = ""
            }
        case .progress(let index, let fraction, let detail):
            runIndex = index
            runProgress = fraction
            runDetail = detail
            // The one long wait in the app, said outside the window. Only for
            // an upload: a write finishes faster than the Dock can draw, and a
            // bar that flashed on every step would be an animation about
            // nothing. `DockTile` drops repeats within the same whole percent.
            if runSteps[safe: index]?.isUpload == true { DockTile.progress(fraction) }
        case .log(let line):
            logLines.append(line)
            if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
        case .failure(let failure):
            runFailure = failure
            runIndex = failure.stepIndex
            // A run that stopped mid-upload would otherwise leave a bar frozen
            // at whatever fraction it reached, which reads as work still going.
            DockTile.clear()
            PostHogSDK.shared.capture("submission_run_failed", properties: [
                "step_index": failure.stepIndex,
                "is_dry_run": dryRun
            ])
        case .providerFailed(let message):
            providerFailure = message
        case .finished:
            finishRun()
        }
    }

    private func finishRun() {
        runDone = true
        runIndex = runSteps.count
        runProgress = 1
        applied = !dryRun
        runFailure = nil
        // The icon goes back to being an icon. Left set, the bar would sit at
        // 100% in the Dock until the app quit.
        DockTile.clear()
        PostHogSDK.shared.capture("submission_run_completed", properties: [
            "step_count": runSteps.count,
            "is_dry_run": dryRun
        ])
        refreshDraftStatuses()
        // `applied` has just become true, so the console steps are now the
        // work that remains and the badge may show them.
        refreshDockBadge()
        // The tab moves on by itself when the run ends. Spec 16.3.
        //
        // Only after a real apply. A dry run wrote nothing, so there is no
        // draft to release and the developer is still reading the log; the
        // guard used to be "am I on the Submit tab", which was true for a dry
        // run too, so a dry run threw the reader onto Release after 1.4
        // seconds and the button underneath said "Back to Summary".
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_400))
            guard let self, runDone, !dryRun, selectedTab == .plan else { return }
            selectedTab = .release
        }
    }

    func cancelRun() {
        let previous = runTask
        previous?.cancel()
        DockTile.clear()
        runDetail = "Cleaning up the interrupted run…"
        runTask = Task { [weak self, runner] in
            _ = await previous?.result
            await runner?.undo()
            guard let self else { return }
            runIndex = -1
            runProgress = 0
            runDone = false
            runDetail = ""
            runTask = nil
        }
    }

    /// Spec 11.1, button 1.
    func retryFromFailure() {
        guard let failure = runFailure else { return }
        startRun(from: failure.stepIndex)
    }

    /// Spec 11.1, button 2. The undo deletes the Google edit and archives what
    /// this run created in the provider. It removes no Apple screenshot.
    func undoRun() {
        runFailure = nil
        runDetail = "Undoing the recoverable parts of this run…"
        let previous = runTask
        previous?.cancel()
        runTask = Task { [weak self, runner] in
            _ = await previous?.result
            await runner?.undo()
            guard let self else { return }
            runIndex = -1
            runDetail = ""
            stepStates = Array(repeating: .pending, count: runSteps.count)
            runTask = nil
        }
    }

    /// Spec 11.2, button 2.
    func retryProviderSync() {
        providerFailure = nil
        Task { [runner] in
            await runner?.retryProvider()
        }
    }

    // MARK: - Tab 9. The checklist

    func markedState(_ row: ConsoleRow) -> ConsoleState {
        ConsoleChecklist.effectiveState(row, marks: consoleMarks)
    }

    var consoleDone: Int {
        consoleRows.filter { markedState($0) == .done }.count
    }

    /// The steps left that no API performs. This is what the Dock badge counts.
    var consolePending: Int { consoleRows.count - consoleDone }

    /// Puts the count of remaining console steps on the Dock icon.
    ///
    /// Only after a real apply. Before one, these rows describe work the
    /// developer has not been asked for yet, and a badge on an app that was
    /// opened a minute ago is a badge that creates worry without offering
    /// anything to resolve. A dry run leaves `applied` false, so it never
    /// raises one.
    func refreshDockBadge() {
        DockTile.badge(applied ? consolePending : 0)
    }

    func toggleConsoleMark(_ id: String) {
        if consoleMarks.contains(id) { consoleMarks.remove(id) } else { consoleMarks.insert(id) }
        saveConsoleMarks()
        refreshDockBadge()
    }

    func loadConsoleMarks() {
        guard let root = manifestRoot else {
            consoleMarks = []
            refreshDockBadge()
            return
        }
        consoleMarks = ConsoleStateStore(root: root).marks(
            app: currentAppKey, version: manifest.release?.versionName ?? "")
        consoleRows = ConsoleChecklist.rows(manifest: manifest, actual: actualState,
                                            stores: stores)
        refreshDockBadge()
    }

    private func saveConsoleMarks() {
        guard let root = manifestRoot else { return }
        do {
            try ConsoleStateStore(root: root).save(
                consoleMarks, app: currentAppKey,
                version: manifest.release?.versionName ?? "")
        } catch {
            errorMessage = "The console checklist could not be saved. \(error.localizedDescription)"
        }
    }

    private var currentAppKey: String {
        manifest.apps.apple?.appId
            ?? manifest.apps.google?.packageName
            ?? credentialAccount
            ?? "unlinked"
    }

    /// Runs the read calls again and updates the states. It writes nothing.
    func recheck() async {
        rechecking = true
        await readStores()
        await pollStatuses()
        rechecking = false
    }

    func copyChecklist() {
        copyToPasteboard(ConsoleChecklist.markdown(consoleRows, marks: consoleMarks))
    }

    func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Tab 9. The status and the two buttons

    /// A store that a run prepared but nobody released reads
    /// **Draft, ready to release**. No poll is needed to know that.
    func refreshDraftStatuses() {
        for store in stores where statuses[store]?.phase.isReleased != true {
            statuses[store] = StoreStatus(store: store, phase: storePhase(store),
                                          detail: detail(for: store), checkedAt: Date())
        }
    }

    /// What the store itself holds, and this run only when the store said
    /// nothing.
    ///
    /// This used to be `applied ? .draft : .noDraft` and nothing else. The
    /// card then reported the session rather than the store: a draft made on
    /// the App Store Connect website, or by yesterday's apply, read **No draft
    /// yet** on a version the store had been holding for a week, and the row
    /// went back to saying it every time the app was relaunched or another app
    /// was opened. The read that answers this already runs on every plan.
    private func storePhase(_ store: Store) -> StoreStatus.Phase {
        switch store {
        case .apple:
            guard let state = actualState.apple?.versionState else {
                return applied ? .draft : .noDraft
            }
            return ReleaseStatusReader.applePhase(state)
        case .google:
            // Google's edits API names a track release `draft`, `inProgress`,
            // `halted` or `completed`, which is not the vocabulary the poll
            // reads off `/tracks/{track}/releases`. Only the draft question is
            // asked here; `pollStatuses` owns everything after a release.
            guard let track = actualState.google?.tracks[manifest.googlePrimaryTrack],
                  !track.versionCodes.isEmpty else {
                return applied ? .draft : .noDraft
            }
            return track.status == "draft" ? .draft : .live
        }
    }

    func detail(for store: Store) -> String {
        let version = manifest.release?.versionName ?? "no version"
        switch store {
        case .apple:
            return "Version \(version)"
        case .google:
            let track = manifest.googlePrimaryTrack
            return "Version \(version) · \(track)"
        }
    }

    var appleReleased: Bool { statuses[.apple]?.phase.isReleased ?? false }
    var googleReleased: Bool { statuses[.google]?.phase.isReleased ?? false }

    /// Spec 16.6: the checklist sits between the draft and the review, and a
    /// needed row holds the button back.
    func releaseBlockers(for store: Store) -> [ConsoleRow] {
        let system = store == .apple ? "App Store" : "Google Play"
        return consoleRows.filter { $0.system == system && markedState($0) == .needed }
    }

    /// One store, one button, one failure. Spec 7.9 and 11.3.
    func release(_ store: Store) async {
        guard releasing == nil else { return }
        guard requirePaid(.storeRelease, .release) else { return }
        releasing = store
        releaseError = nil
        let client = ReleaseClient(api: readOnlyAPI(), access: access)
        do {
            switch store {
            case .apple:
                guard let appID = manifest.apps.apple?.appId, !appID.isEmpty,
                      let versionID = actualState.apple?.versionId else {
                    throw ReleaseInputError.noAppleVersion
                }
                if actualState.apple?.versionState == "PENDING_DEVELOPER_RELEASE" {
                    appleSubmissionID = try await client.releaseApprovedAppleVersion(
                        versionID: versionID)
                } else {
                    appleSubmissionID = try await client.releaseApple(
                        appID: appID,
                        platform: manifest.apps.apple?.platforms.first?.rawValue ?? "IOS",
                        versionID: versionID)
                }
                statuses[.apple] = StoreStatus(store: .apple, phase: .inQueue,
                                               detail: detail(for: .apple), checkedAt: Date())
            case .google:
                guard let packageName = manifest.apps.google?.packageName, !packageName.isEmpty
                else { throw ReleaseInputError.noGooglePackage }
                _ = try await client.releaseGoogle(
                    packageName: packageName,
                    track: manifest.googlePrimaryTrack,
                    status: manifest.release?.google?.status ?? "completed",
                    userFraction: manifest.release?.google?.userFraction,
                    versionName: manifest.release?.versionName)
                statuses[.google] = StoreStatus(store: .google, phase: .inQueue,
                                                detail: detail(for: .google), checkedAt: Date())
            }
            PostHogSDK.shared.capture("release_submitted", properties: [
                "store": store == .apple ? "apple" : "google"
            ])
            startPolling()
        } catch {
            PostHogSDK.shared.capture("release_submission_failed", properties: [
                "store": store == .apple ? "apple" : "google"
            ])
            releaseError = "\(store == .apple ? "App Store" : "Google Play"): \(error.localizedDescription)"
                + Self.assumedDeclarationsNote(store: store, actual: actualState)
        }
        releasing = nil
    }

    /// The one place the checklist's assumption is allowed to speak up.
    ///
    /// An update never blocks on the once-per-app declarations. Apple asks
    /// them per app, the app is already on the store, and no API reads several
    /// of them, so the checklist assumes them and lets the developer through.
    /// See `ConsoleChecklist.assumed`.
    ///
    /// A refused submission is the moment that assumption could be wrong, and
    /// the only moment a developer can do anything about it. Apple names the
    /// field in its own message; this names the reason the app did not ask
    /// first, so the two read as one answer instead of a surprise.
    ///
    /// It rides on every Apple update failure and not on a matched error
    /// string. Apple's wording here is not a contract, and a note that is
    /// occasionally beside the point costs a sentence, where a missed one
    /// costs a developer the afternoon.
    static func assumedDeclarationsNote(store: Store, actual: ActualState) -> String {
        guard store == .apple, actual.apple?.isUpdate == true else { return "" }
        return "\n\nThe checklist assumed the once-per-app declarations were already answered, "
            + "because the app is on the App Store. If Apple names one of them, answer it in "
            + "App Store Connect and press Release again."
    }

    /// True while the store still accepts a take-back.
    ///
    /// Apple takes the cancel until a reviewer opens the submission. Google
    /// halts a staged rollout and never a completed one. Neither one restores
    /// what already reached a customer, so both stay behind a confirmation.
    func canUndoRelease(_ store: Store) -> Bool {
        switch store {
        case .apple:
            return statuses[.apple]?.phase == .inQueue
        case .google:
            guard googleReleased else { return false }
            return (manifest.release?.google?.status ?? "completed") == "inProgress"
        }
    }

    /// The other half of `release`. One store, one button, one failure.
    func undoRelease(_ store: Store) async {
        guard releasing == nil else { return }
        guard requirePaid(.storeRelease, .release) else { return }
        releasing = store
        releaseError = nil
        let client = ReleaseClient(api: readOnlyAPI(), access: access)
        do {
            switch store {
            case .apple:
                guard let appID = manifest.apps.apple?.appId, !appID.isEmpty else {
                    throw ReleaseInputError.noAppleVersion
                }
                // The session id is the fast path. The read is the one that
                // still works after a restart.
                let id = try await client.cancellableAppleSubmission(appID: appID)
                    ?? appleSubmissionID
                guard let id else { throw ReleaseInputError.noOpenAppleSubmission }
                try await client.cancelAppleSubmission(id: id)
                appleSubmissionID = nil
                statuses[.apple] = StoreStatus(store: .apple, phase: .draft,
                                               detail: detail(for: .apple), checkedAt: Date())
            case .google:
                guard let packageName = manifest.apps.google?.packageName, !packageName.isEmpty
                else { throw ReleaseInputError.noGooglePackage }
                try await client.haltGoogleRollout(packageName: packageName,
                                                   track: manifest.googlePrimaryTrack)
                statuses[.google] = StoreStatus(store: .google, phase: .draft,
                                                detail: detail(for: .google), checkedAt: Date())
            }
            PostHogSDK.shared.capture("release_undone", properties: [
                "store": store == .apple ? "apple" : "google"
            ])
        } catch {
            releaseError = "\(store == .apple ? "App Store" : "Google Play"): \(error.localizedDescription)"
        }
        releasing = nil
    }

    // MARK: - The status poll, section 7.10

    var pollInterval: TimeInterval {
        let minutes = defaults.object(forKey: "pollIntervalMinutes") as? Int ?? 5
        return TimeInterval(max(1, minutes) * 60)
    }

    /// The app polls a store only after a release for review.
    func startPolling() {
        pollTask?.cancel()
        guard statuses.values.contains(where: { $0.phase.needsPolling }) else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.pollStatuses()
                guard self?.statuses.values.contains(where: { $0.phase.needsPolling }) == true
                else { return }
            }
        }
    }

    func pollStatuses() async {
        let reader = ReleaseStatusReader(api: readOnlyAPI())
        for store in stores where statuses[store]?.phase.needsPolling == true {
            do {
                let fresh: StoreStatus
                switch store {
                case .apple:
                    guard let versionID = actualState.apple?.versionId else { continue }
                    fresh = try await reader.readApple(versionID: versionID)
                case .google:
                    guard let packageName = manifest.apps.google?.packageName else { continue }
                    fresh = try await reader.readGoogle(
                        packageName: packageName,
                        track: manifest.googlePrimaryTrack)
                }
                let previous = statuses[store]?.phase
                statuses[store] = StoreStatus(store: store, phase: fresh.phase,
                                              detail: detail(for: store), checkedAt: Date())
                if previous != fresh.phase {
                    notify(store: store, phase: fresh.phase)
                }
            } catch {
                // A failed poll is not a failed release. The row keeps its
                // last known state and the time it was checked.
                statuses[store]?.checkedAt = Date()
            }
        }
    }

    /// The app posts a macOS notification on every state change.
    ///
    /// `UNUserNotificationCenter` needs a bundle identifier, and this target
    /// still builds a plain executable. Without a bundle the app bounces the
    /// Dock icon instead, which is the loudest signal it can send honestly.
    ///
    /// `// ponytail: the Dock bounce until the signed .app target lands. One
    /// // branch, no notification framework wrapper.`
    private func notify(store: Store, phase: StoreStatus.Phase) {
        let name = manifest.listing?.locales[manifest.listing?.defaultLocale ?? ""]?.name
            ?? "Your app"
        let title = store == .apple ? "App Store" : "Google Play"
        guard Bundle.main.bundleIdentifier != nil else {
            NSApp.requestUserAttention(.informationalRequest)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(name): \(phase.label)"
        let identifier = UUID().uuidString
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else {
                return
            }
            try? await center.add(UNNotificationRequest(identifier: identifier,
                                                        content: content, trigger: nil))
        }
    }
}

enum ReleaseInputError: LocalizedError {
    case noAppleVersion
    case noGooglePackage
    case noOpenAppleSubmission

    var errorDescription: String? {
        switch self {
        case .noAppleVersion:
            "No App Store version is prepared. Run an apply first."
        case .noGooglePackage:
            "Enter the Google Play package name on the Stores tab first."
        case .noOpenAppleSubmission:
            "Apple holds no submission that a cancel can still reach. A reviewer already opened it."
        }
    }
}

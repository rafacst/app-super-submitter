import AppKit
import Foundation
import SubmitKit
import SwiftUI
import UserNotifications

/// Tabs 7, 8, and 9, and the status behind the menu bar item.
///
/// The views stay thin: every rule lives in SubmitKit, and this file only
/// moves values between the kit and the screen.
@MainActor
extension AppState {

    // MARK: - Tab 7. The plan

    var credentials: StoreCredentials {
        StoreCredentials(
            apple: applePrivateKeyPEM.isEmpty ? nil : AppleCredential(
                keyID: appleKeyID, issuerID: appleIssuerID,
                privateKeyPEM: applePrivateKeyPEM, fileName: appleCredentialFileName),
            google: googleCredential,
            revenueCatKey: revenueCatAPIKey.isEmpty ? nil : revenueCatAPIKey,
            reviewer: reviewerUsername.isEmpty ? nil : ReviewerCredential(
                username: reviewerUsername, password: reviewerPassword))
    }

    /// A `StoreAPI` that writes no run log. The plan and the status poll use
    /// it; only a run opens a log file.
    func readOnlyAPI() -> StoreAPI {
        StoreAPI(credentials: credentials, record: { _ in })
    }

    /// Reads every store, then diffs. Spec section 7.2. This writes nothing.
    func readStores() async {
        guard !planReading else { return }
        planReading = true
        planError = nil
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
        // A new plan invalidates the runner that held the old one.
        runContinuation?.finish()
        runContinuation = nil
        eventTask?.cancel()
        eventTask = nil
        runner = nil
        plan = result
        actualState = actual
        consoleRows = ConsoleChecklist.rows(manifest: manifest, actual: actual, stores: stores)
        planError = result.readFailures.isEmpty ? nil : result.readFailures.joined(separator: "\n")
        stepStates = Array(repeating: .pending, count: result.steps.count)
        stepMeta = Array(repeating: "", count: result.steps.count)
        refreshDraftStatuses()
        planReading = false
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
        return !plan.isBlocked && unacknowledgedWarnings == 0 && !isRunning
    }

    // MARK: - Tab 8. The run

    var isRunning: Bool { runIndex >= 0 && !runDone && runFailure == nil }

    var runSteps: [PlanStep] { plan?.steps ?? [] }

    var logText: String { logLines.joined(separator: "\n") }

    func startRun(from start: Int = 0) {
        guard let plan, !plan.steps.isEmpty else { return }
        guard start > 0 || canApply else { return }
        runTask?.cancel()
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
        runTask = Task { await runner.run(from: start) }
    }

    private func makeRunner(for plan: PlanResult) -> Runner {
        runContinuation?.finish()
        eventTask?.cancel()
        let events = AsyncStream<RunEvent>.makeStream()
        runContinuation = events.continuation
        let runner = Runner(
            plan: plan, manifest: manifest, actual: actualState, root: manifestRoot,
            credentials: credentials, dryRun: dryRun,
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
            guard stepStates.indices.contains(index) else { return }
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
        case .log(let line):
            logLines.append(line)
            if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
        case .failure(let failure):
            runFailure = failure
            runIndex = failure.stepIndex
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
        refreshDraftStatuses()
        // The tab moves to tab 9 by itself when the run ends. Spec 16.3.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_400))
            guard let self, runDone, selectedTab == .submit else { return }
            selectedTab = .release
        }
    }

    func cancelRun() {
        runTask?.cancel()
        runTask = nil
        Task { [runner] in await runner?.undo() }
        runIndex = -1
        runProgress = 0
        runDone = false
        runDetail = ""
    }

    /// Spec 11.1, button 1.
    func retryFromFailure() {
        guard let failure = runFailure else { return }
        startRun(from: failure.stepIndex)
    }

    /// Spec 11.1, button 2. The undo deletes the Google edit and archives what
    /// this run created in the provider. It removes no Apple screenshot.
    func undoRun() {
        Task { [runner] in await runner?.undo() }
        runFailure = nil
        runIndex = -1
        stepStates = Array(repeating: .pending, count: runSteps.count)
    }

    /// Spec 11.2, button 2.
    func retryProviderSync() {
        providerFailure = nil
        Task { [weak self, runner] in
            await runner?.retryProvider()
            self?.providerFailure = nil
        }
    }

    // MARK: - Tab 9. The checklist

    func markedState(_ row: ConsoleRow) -> ConsoleState {
        ConsoleChecklist.effectiveState(row, marks: consoleMarks)
    }

    var consoleDone: Int {
        consoleRows.filter { markedState($0) == .done }.count
    }

    func toggleConsoleMark(_ id: String) {
        if consoleMarks.contains(id) { consoleMarks.remove(id) } else { consoleMarks.insert(id) }
        saveConsoleMarks()
    }

    func loadConsoleMarks() {
        guard let root = manifestRoot else { consoleMarks = []; return }
        consoleMarks = ConsoleStateStore(root: root).marks(
            app: currentAppKey, version: manifest.release?.versionName ?? "")
        consoleRows = ConsoleChecklist.rows(manifest: manifest, actual: actualState,
                                            stores: stores)
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
        manifest.apps.apple?.appId ?? manifest.apps.google?.packageName ?? "app"
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
            let phase: StoreStatus.Phase = applied ? .draft : .noDraft
            statuses[store] = StoreStatus(store: store, phase: phase,
                                          detail: detail(for: store), checkedAt: Date())
        }
    }

    func detail(for store: Store) -> String {
        let version = manifest.release?.versionName ?? "no version"
        switch store {
        case .apple:
            return "Version \(version)"
        case .google:
            let track = manifest.release?.google?.track ?? "production"
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
        releasing = store
        releaseError = nil
        let client = ReleaseClient(api: readOnlyAPI())
        do {
            switch store {
            case .apple:
                guard let appID = manifest.apps.apple?.appId, !appID.isEmpty,
                      let versionID = actualState.apple?.versionId else {
                    throw ReleaseInputError.noAppleVersion
                }
                appleSubmissionID = try await client.releaseApple(
                    appID: appID, platform: manifest.apps.apple?.platforms.first?.rawValue ?? "IOS",
                    versionID: versionID)
                statuses[.apple] = StoreStatus(store: .apple, phase: .inQueue,
                                               detail: detail(for: .apple), checkedAt: Date())
            case .google:
                guard let packageName = manifest.apps.google?.packageName, !packageName.isEmpty
                else { throw ReleaseInputError.noGooglePackage }
                _ = try await client.releaseGoogle(
                    packageName: packageName,
                    track: manifest.release?.google?.track ?? "production",
                    status: manifest.release?.google?.status ?? "completed",
                    userFraction: manifest.release?.google?.userFraction,
                    versionName: manifest.release?.versionName)
                statuses[.google] = StoreStatus(store: .google, phase: .inQueue,
                                                detail: detail(for: .google), checkedAt: Date())
            }
            startPolling()
        } catch {
            releaseError = "\(store == .apple ? "App Store" : "Google Play"): \(error.localizedDescription)"
        }
        releasing = nil
    }

    // MARK: - The status poll, section 7.10

    var pollInterval: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: "pollIntervalMinutes") as? Int ?? 5
        return TimeInterval(max(1, minutes) * 60)
    }

    /// The app polls a store only after a release for review.
    func startPolling() {
        pollTask?.cancel()
        guard statuses.values.contains(where: { $0.phase.isReleased }) else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.pollStatuses()
            }
        }
    }

    func pollStatuses() async {
        let reader = ReleaseStatusReader(api: readOnlyAPI())
        for store in stores where statuses[store]?.phase.isReleased == true {
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
                        track: manifest.release?.google?.track ?? "production")
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

    var errorDescription: String? {
        switch self {
        case .noAppleVersion:
            "No App Store version is prepared. Run an apply first."
        case .noGooglePackage:
            "Enter the Google Play package name on the Stores tab first."
        }
    }
}

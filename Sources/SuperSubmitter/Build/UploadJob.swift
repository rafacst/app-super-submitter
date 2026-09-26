import Aptabase
import Foundation
import Observation
import SubmitKit

/// One artifact's upload, running on its own, beside the others.
///
/// The Build tab produces two Apple archives at once, and a developer who
/// waited out one upload before starting the next was paying twice for a wait
/// that has nothing to share. Each built candidate gets one of these, so iOS
/// and macOS reach App Store Connect at the same time, each with its own
/// process, its own poll, and its own record on disk.
///
/// The flow keeps one `run`/`candidate` of its own for the selected artifact —
/// the path the direct apply, the sidebar and the live-run panel all read — and
/// this leaves that path exactly as it was. A job is the *second* and later
/// uploads, and it carries everything one upload owns so two never cross:
///
/// ponytail: the upload lifecycle lives twice, here and on `BuildFlow`. The
/// flow's copy stays the source of truth for the selected artifact and for the
/// direct apply that drives it; this copy is the same shape for the artifacts
/// that upload beside it. Fold the two together only if a third caller appears.
///
/// The context, keys and folder are captured once, at the moment the upload
/// starts, and never read live: the developer is free to open another tab and
/// edit another `store.yaml` while this runs, and an upload that re-read the
/// front-most app would send one app's binary against another's answers. This
/// is the same rule `BuildContext` keeps for the flow.
@Observable
@MainActor
final class UploadJob: Identifiable {
    let id = UUID()
    let candidate: BuildCandidate

    @ObservationIgnored weak var flow: BuildFlow?
    @ObservationIgnored weak var app: AppState?
    @ObservationIgnored let context: BuildContext
    @ObservationIgnored let storage: BuildStorage
    @ObservationIgnored let redactor: Redactor
    @ObservationIgnored let allowProvisioningUpdates: Bool

    var run: UploadRun
    var progress = 0.0
    var processingLabel: String?
    var successLink: String?
    var failure: BuildFailure?
    /// What the store answered when it was asked right before the send. It
    /// stops the upload and the card shows it.
    var blocking: String?
    @ObservationIgnored var task: Task<Void, Never>?

    init(candidate: BuildCandidate, flow: BuildFlow) {
        self.candidate = candidate
        self.flow = flow
        self.app = flow.app
        self.context = flow.context
        self.storage = flow.storage
        self.redactor = flow.redactor
        self.allowProvisioningUpdates = flow.allowProvisioningUpdates
        run = UploadRun(platform: candidate.platform,
                        linkedProjectID: flow.project?.id,
                        state: .needsUploadConfirmation)
        run.candidateIdentity = candidate.logicalIdentity
    }

    var isActive: Bool { run.state.isActive }

    /// The card reads this to draw a green tick, a red one, or a spinner. It
    /// mirrors `BuildFlow.uploadStatus` for the selected artifact.
    var status: BuildSidebarStatus? {
        switch run.state {
        case .uploading, .processingOrValidating, .recoveryRequired: .running
        case .complete: .succeeded
        case .failed: .failed
        default: nil
        }
    }

    var canUpload: Bool {
        run.state == .needsUploadConfirmation && !candidate.deleted
            && candidate.blockingMismatches.isEmpty && blocking == nil
    }

    // MARK: - The upload

    func start() {
        guard let app, canUpload else { return }
        // Building and inspecting were free. Only the send is not, and pressing
        // upload again after paying costs no second send.
        guard app.requirePaid(.storeUpload, .upload) else { return }
        failure = nil
        blocking = nil
        progress = 0
        guard run.move(to: .uploading) else { return }
        Aptabase.shared.trackEvent("artifact_upload_started", with: [
            "platform": candidate.platform == .android ? "android" : "apple",
            "concurrent": 1
        ])
        try? storage.save(run)

        task = Task { [weak self] in
            guard let self else { return }
            await recheckRemote()
            guard !Task.isCancelled else { return await finishCancel() }
            guard blocking == nil else {
                run.move(to: .needsUploadConfirmation)
                return
            }
            do {
                switch candidate.platform {
                case .ios, .macos: try await uploadApple()
                case .android: try await uploadGoogle()
                }
            } catch is CancellationError {
                await finishCancel()
            } catch let failure as BuildFailure {
                fail(failure)
            } catch {
                fail(BuildFailure(category: .upload, stage: "Upload",
                                  message: error.localizedDescription,
                                  retainedArtifact: candidate.artifactPath))
            }
        }
    }

    private func uploadApple() async throws {
        let service = AppleBuildService(runner: ToolProcess(redactor: redactor),
                                        storage: storage)
        var authentication: AppleAuthenticationFiles?
        if let credential = context.appleCredential {
            authentication = try AppleAuthenticationFiles.materialize(
                credential: credential, runID: run.id, storage: storage)
        }
        let snapshot = candidate.preflightSnapshot
        let options = try service.writeExportOptions(
            runID: run.id, platform: candidate.platform,
            team: candidate.signingSummary.team ?? snapshot?.team,
            signingStyle: snapshot?.signingStyle,
            distributionBundleIdentifier: (candidate.archiveInfo?.eligibleApplications.count ?? 0) > 1
                ? candidate.productIdentifier : nil)
        defer { storage.removeScratch(runID: run.id) }

        record("xcodebuild -exportArchive · destination upload")
        progress = 0.2
        try await service.exportAndUpload(
            archive: candidate.artifactURL,
            exportPath: try storage.exportURL(runID: run.id), optionsPlist: options,
            authentication: authentication,
            allowProvisioningUpdates: allowProvisioningUpdates,
            access: app?.access ?? UnconfiguredAccess(),
            onLine: { [weak self] _, line in
                Task { @MainActor in self?.log(line) }
            })
        progress = 1
        run.move(to: .processingOrValidating)
        try? storage.save(run)
        await pollApple()
    }

    /// The same poll the flow runs, for this artifact's own build. Apple keeps
    /// no edit to clean up, so a cancelled Apple upload strands nothing.
    private func pollApple() async {
        guard let appID = context.appleAppID, !appID.isEmpty else {
            run.move(to: .recoveryRequired)
            processingLabel = "The upload finished, but no App Store app is linked for processing checks."
            try? storage.save(run)
            return
        }
        let service = UploadService(api: context.api)
        var attempt = 0
        while !Task.isCancelled, attempt < 40 {
            attempt += 1
            do {
                let state = try await service.appleProcessingState(
                    appID: appID, platform: candidate.platform,
                    marketingVersion: candidate.marketingVersion,
                    buildVersion: candidate.buildVersion)
                switch state {
                case .waitingToAppear:
                    processingLabel = "Uploaded. Waiting for the build to appear."
                case .processing(let buildID):
                    processingLabel = "App Store Connect is processing the build."
                    run.remoteIDs["appleBuild"] = buildID
                case .processed(let buildID):
                    run.remoteIDs["appleBuild"] = buildID
                    processingLabel = nil
                    successLink = "https://appstoreconnect.apple.com/apps/\(appID)/testflight/"
                        + (candidate.platform == .macos ? "macos" : "ios")
                    run.move(to: .complete)
                    finishSuccess()
                    return
                case .failed(let buildID, let detail):
                    run.remoteIDs["appleBuild"] = buildID
                    fail(BuildFailure(
                        category: .remoteValidation, stage: "Process the build",
                        message: detail,
                        recovery: "Read Apple's diagnostic in App Store Connect, fix it, then build again.",
                        retainedArtifact: candidate.artifactPath))
                    return
                }
            } catch {
                processingLabel = "The last check failed: \(error.localizedDescription)"
            }
            try? await Task.sleep(for: .seconds(UploadService.pollDelay(attempt: attempt)))
        }
        run.move(to: .recoveryRequired)
        processingLabel = "Still processing at App Store Connect. Press Resume checking later."
        try? storage.save(run)
    }

    func stopWaiting() {
        task?.cancel()
        processingLabel = "Stopped checking. The upload was not cancelled."
        run.move(to: .recoveryRequired)
        try? storage.save(run)
    }

    func resumeChecking() {
        run.move(to: .processingOrValidating)
        task = Task { [weak self] in await self?.pollApple() }
    }

    private func uploadGoogle() async throws {
        guard let packageName = context.googlePackageName, !packageName.isEmpty else {
            throw BuildFailure(category: .authentication, stage: "Upload the bundle",
                               message: "Enter the Google Play package name on the Stores tab.")
        }
        guard let versionCode = Int(candidate.buildVersion), versionCode > 0 else {
            throw BuildFailure(category: .artifactValidation, stage: "Upload the bundle",
                               message: "The inspected bundle has no valid positive version code.",
                               retainedArtifact: candidate.artifactPath)
        }
        let service = UploadService(api: context.api)
        record("POST edits · upload bundle · commit changesNotSentForReview=true")
        run.cleanupState = .pending
        let result = try await service.uploadGoogleBundle(
            packageName: packageName, track: context.googleTrack,
            bundle: candidate.artifactURL, expectedVersionCode: versionCode,
            versionName: candidate.marketingVersion,
            access: app?.access ?? UnconfiguredAccess(),
            onEditCreated: { [weak self] editID in
                await self?.rememberGoogleEdit(editID)
            },
            onProgress: { [weak self] value in
                Task { @MainActor in self?.progress = value }
            })
        run.remoteIDs["googleEdit"] = result.editID
        run.remoteIDs["versionCode"] = String(result.versionCode)
        run.cleanupState = .complete
        successLink = "https://play.google.com/console"
        run.move(to: .complete)
        finishSuccess()
    }

    private func rememberGoogleEdit(_ editID: String) {
        run.remoteIDs["googleEdit"] = editID
        try? storage.save(run)
    }

    /// One read-only conflict check right before the send, the same one the
    /// flow runs for the selected artifact.
    private func recheckRemote() async {
        let service = UploadService(api: context.api)
        do {
            switch candidate.platform {
            case .ios, .macos:
                guard let appID = context.appleAppID, !appID.isEmpty else { return }
                let check = try await service.checkApple(
                    appID: appID, platform: candidate.platform,
                    bundleIdentifier: candidate.productIdentifier,
                    marketingVersion: candidate.marketingVersion,
                    buildVersion: candidate.buildVersion)
                blocking = check.blocking
                if check.existingBuildID != nil {
                    blocking = "\(check.blocking ?? "") Use the existing build instead of uploading it again."
                }
            case .android:
                guard let packageName = context.googlePackageName,
                      !packageName.isEmpty else { return }
                let check = try await service.checkGoogle(
                    packageName: packageName, track: context.googleTrack,
                    versionCode: Int(candidate.buildVersion))
                blocking = check.blocking
            }
        } catch {
            // A read that failed is not a conflict. The upload's own errors are
            // reported where they happen.
        }
    }

    // MARK: - Cancellation and failure

    func cancel() {
        guard run.state.isActive else { return }
        run.move(to: .cancelling)
        run.cancelRequestedAt = Date()
        task?.cancel()
        task = Task { [weak self] in await self?.finishCancel() }
    }

    func finishCancel() async {
        storage.removeScratch(runID: run.id)
        if run.state == .uploading || run.cleanupState == .pending {
            await reconcileAfterCancel()
        } else {
            run.move(to: .cancelled)
        }
        try? storage.save(run)
    }

    /// A cancelled local process is no proof the remote upload was refused, so
    /// this reconciles a Google edit before it reports. Apple keeps no edit.
    private func reconcileAfterCancel() async {
        guard candidate.platform == .android,
              let packageName = context.googlePackageName else {
            run.move(to: .cancelled)
            return
        }
        let service = UploadService(api: context.api)
        if let landed = try? await service.reconcileGoogle(
            packageName: packageName, track: context.googleTrack,
            versionCode: Int(candidate.buildVersion) ?? 0), landed {
            processingLabel = "The upload had already reached Google Play, so it was not undone."
            run.cleanupState = .complete
            run.move(to: .complete)
            finishSuccess()
            return
        }
        if let editID = run.remoteIDs["googleEdit"] {
            do {
                try await service.deleteEdit(packageName: packageName, editID: editID)
                run.cleanupState = .complete
            } catch {
                run.cleanupState = .needsAttention
            }
        }
        run.move(to: .cancelled)
    }

    func retryCleanup() {
        guard let packageName = context.googlePackageName,
              let editID = run.remoteIDs["googleEdit"] else { return }
        let api = context.api
        Task { [weak self] in
            do {
                try await UploadService(api: api)
                    .deleteEdit(packageName: packageName, editID: editID)
                self?.run.cleanupState = .complete
            } catch {
                self?.run.cleanupState = .needsAttention
            }
        }
    }

    private func fail(_ value: BuildFailure) {
        storage.removeScratch(runID: run.id)
        failure = value
        run.lastError = value
        run.move(to: value.category.needsReconciliation ? .recoveryRequired : .failed)
        Aptabase.shared.trackEvent("build_flow_failed", with: ["stage": value.stage])
        try? storage.save(run)
    }

    /// The store now holds a build it did not, so the plan is stale, and this
    /// artifact is spent. See `BuildFlow.markUploaded`.
    private func finishSuccess() {
        Aptabase.shared.trackEvent("artifact_upload_completed", with: [
            "platform": candidate.platform == .android ? "android" : "apple",
            "concurrent": 1
        ])
        try? storage.save(run)
        flow?.markUploaded(candidate.id)
        app?.invalidatePlan()
    }

    // MARK: - Logging

    /// Into the flow's one shared log, tagged with the platform so the two
    /// uploads that print at once stay legible.
    private func log(_ line: String) {
        flow?.append("[\(candidate.platform.label)] \(line)")
    }

    private func record(_ preview: String) {
        run.commandPreviews.append(preview)
        log("$ \(preview)")
    }
}

import AppKit
import Foundation
import PostHog
import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

/// The build, the inspection, and the upload. upload-spec 8.10 to 8.17 and
/// 9.10 to 9.17.
@MainActor
extension BuildFlow {

    // MARK: - The build

    var canBuild: Bool {
        run.state == .readyToBuild && blocking == nil && project?.selection.isComplete == true
    }

    /// The exact language of upload-spec 10.5. No "Are you sure?".
    var buildConfirmationText: String {
        let what = project?.selection.scheme ?? project?.selection.variantTask ?? "this project"
        let folder = project?.rootURL.lastPathComponent ?? "the selected folder"
        return "Build \(what) from \(folder) using \(snapshot.toolchain ?? "the selected toolchain"). "
            + "This can run scripts and plug-ins supplied by the selected project."
    }

    func startBuild() {
        guard canBuild, let project else { return }
        showBuildConfirmation = false
        failure = nil
        logLines = []
        candidate = nil
        artifactOnly = false
        uploadProgress = 0
        startedAt = Date()
        run.move(to: .building)
        PostHogSDK.shared.capture("project_build_started", properties: [
            "platform": project.platform == .android ? "android" : "apple",
            "allow_provisioning_updates": allowProvisioningUpdates
        ])
        try? storage.save(run)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let artifact: URL
                switch project.platform {
                case .ios, .macos: artifact = try await buildApple(project)
                case .android: artifact = try await buildAndroid(project)
                }
                guard !Task.isCancelled else { return await finishCancel() }
                run.move(to: .inspectingArtifact)
                try await inspect(artifact: artifact, project: project)
            } catch is CancellationError {
                await finishCancel()
            } catch let failure as BuildFailure {
                fail(failure)
            } catch {
                fail(BuildFailure(category: .build, stage: run.state.stepTitle,
                                  message: error.localizedDescription))
            }
        }
    }

    private func buildApple(_ project: LinkedSourceProject) async throws -> URL {
        let service = AppleBuildService(runner: ToolProcess(redactor: redactor),
                                        storage: storage)
        let bundleID = snapshot.productIdentifier ?? "unknown"
        let archivePath = try storage.archiveURL(bundleID: bundleID, runID: run.id)
        var authentication: AppleAuthenticationFiles?
        if let credential = app?.credentials.apple, !credential.privateKeyPEM.isEmpty {
            authentication = try AppleAuthenticationFiles.materialize(
                credential: credential, runID: run.id, storage: storage)
        }
        // Unconditional cleanup: the .p8 goes on success, on error, and on a
        // cancel. upload-spec 8.7.
        defer { storage.removeScratch(runID: run.id) }

        record(preview: "xcodebuild archive · \(project.selection.scheme ?? "")")
        return try await service.archive(
            container: project.containerURL, kind: project.containerKind,
            scheme: project.selection.scheme ?? "",
            configuration: project.selection.configuration,
            platform: run.platform, archivePath: archivePath,
            authentication: authentication,
            allowProvisioningUpdates: allowProvisioningUpdates,
            onLine: { [weak self] _, line in
                Task { @MainActor in self?.append(line) }
            })
    }

    private func buildAndroid(_ project: LinkedSourceProject) async throws -> URL {
        guard let toolchain = androidToolchain,
              let variant = variants.first(where: {
                  $0.qualifiedTask == project.selection.variantTask
              }) else {
            throw BuildFailure(category: .selectionRequired, stage: "Build the App Bundle",
                               message: "Choose a module and a variant first.")
        }
        let service = AndroidBuildService(runner: ToolProcess(redactor: redactor),
                                          storage: storage)
        record(preview: "gradlew \(variant.qualifiedTask) --console=plain")
        let produced = try await service.buildBundle(
            root: project.containerURL, toolchain: toolchain, variant: variant,
            onLine: { [weak self] _, line in
                Task { @MainActor in self?.append(line) }
            })
        guard produced.count == 1 else {
            throw BuildFailure(
                category: .artifactDiscovery, stage: "Find the App Bundle",
                message: "This run produced \(produced.count) App Bundles.",
                diagnostics: produced.map(\.path).joined(separator: "\n"),
                recovery: "Use Choose Built AAB to pick the exact file to upload.")
        }
        return produced[0]
    }

    /// upload-spec 13.3. An imported `.ipa`, `.pkg`, or `.aab` skips the
    /// source build and skips nothing else: it still passes authoritative
    /// inspection, signing verification, identity comparison, the remote
    /// conflict check, and the upload confirmation.
    func adoptImported(_ url: URL) {
        reset()
        run.platform = url.pathExtension.lowercased() == "aab" ? .android
            : (url.pathExtension.lowercased() == "pkg" ? .macos : .ios)
        snapshot = PreflightSnapshot()
        snapshot.toolchain = "Imported package"
        snapshot.uncertainFields = ["productIdentifier", "marketingVersion", "buildVersion"]
        run.move(to: .discovering)
        run.move(to: .preflight)
        run.move(to: .readyToBuild)
        run.move(to: .building)
        run.move(to: .inspectingArtifact)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                if run.platform == .android, androidToolchain == nil {
                    androidToolchain = try await AndroidBuildService(storage: storage)
                        .toolchain(root: url.deletingLastPathComponent(),
                                   preferredJavaHome: nil)
                }
                try await inspectImported(url)
            } catch let failure as BuildFailure {
                fail(failure)
            } catch {
                fail(BuildFailure(category: .artifactValidation,
                                  stage: "Inspect the artifact",
                                  message: error.localizedDescription))
            }
        }
    }

    private func inspectImported(_ url: URL) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var candidate: BuildCandidate

        if run.platform == .android {
            guard let toolchain = androidToolchain, !toolchain.javaHome.isEmpty else {
                throw BuildFailure(
                    category: .toolchainUnavailable, stage: "Verify the bundle signature",
                    message: "No JDK was found, so the bundle signature cannot be verified.",
                    recovery: "Install a JDK. An unverified bundle is never uploaded.")
            }
            let info = try await AndroidBuildService(storage: storage)
                .inspect(bundle: url, toolchain: toolchain)
            candidate = BuildCandidate(
                platform: .android, productName: info.applicationID,
                productIdentifier: info.applicationID, marketingVersion: info.versionName,
                buildVersion: String(info.versionCode), artifactPath: url.path,
                artifactSize: info.size, sha256: info.sha256,
                signingSummary: .init(certificateSubject: info.certificateSubject,
                                      certificateFingerprint: info.certificateFingerprint,
                                      verified: info.signatureVerified,
                                      verificationDetail: info.signatureDetail),
                preflightSnapshot: snapshot)
        } else {
            // An .ipa and a .pkg carry their identity in the package itself.
            let package = try PackageReader().read(url)
            candidate = BuildCandidate(
                platform: run.platform, productName: package.appName ?? url.lastPathComponent,
                productIdentifier: package.identifier ?? "",
                marketingVersion: package.versionName ?? "",
                buildVersion: package.buildNumber ?? "",
                artifactPath: url.path, artifactSize: Int64(data.count),
                sha256: Checksums.sha256(data), preflightSnapshot: snapshot)
        }
        candidate.mismatches = mismatches(for: candidate)
        self.candidate = candidate
        run.candidateIdentity = candidate.logicalIdentity
        PostHogSDK.shared.capture("artifact_inspected", properties: [
            "platform": run.platform == .android ? "android" : "apple",
            "source": "imported",
            "has_blocking_mismatches": !candidate.blockingMismatches.isEmpty
        ])
        await recheckRemote(for: candidate)
        run.move(to: .needsUploadConfirmation)
    }

    /// The developer picks the file when a custom Gradle layout defeats
    /// discovery. It still passes every identity, signing, and remote check.
    func chooseBuiltBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose the built App Bundle"
        panel.allowedContentTypes = [UTType(filenameExtension: "aab")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url, let project else { return }
        run.move(to: .inspectingArtifact)
        task = Task { [weak self] in
            do { try await self?.inspect(artifact: url, project: project) }
            catch let failure as BuildFailure { self?.fail(failure) }
            catch { self?.fail(BuildFailure(category: .artifactValidation,
                                            stage: "Inspect the artifact",
                                            message: error.localizedDescription)) }
        }
    }

    // MARK: - The artifact is authoritative

    private func inspect(artifact: URL, project: LinkedSourceProject) async throws {
        var candidate: BuildCandidate
        switch project.platform {
        case .ios, .macos:
            let info = try await AppleBuildService(storage: storage)
                .inspect(archive: artifact, platform: run.platform)
            candidate = BuildCandidate(
                platform: run.platform, productName: info.applicationName,
                productIdentifier: info.bundleIdentifier,
                marketingVersion: info.shortVersion, buildVersion: info.buildVersion,
                artifactPath: artifact.path, artifactSize: info.size,
                sha256: try Checksums.sha256(directory: artifact),
                signingSummary: .init(style: snapshot.signingStyle, team: info.team,
                                      identity: info.signingIdentity, profile: info.profileName,
                                      verified: info.signatureVerified,
                                      verificationDetail: info.signatureDetail),
                preflightSnapshot: snapshot)
            appleArchiveInfo = info
        case .android:
            guard let toolchain = androidToolchain else {
                throw BuildFailure(category: .toolchainUnavailable,
                                   stage: "Inspect the artifact",
                                   message: "No JDK is selected.")
            }
            let info = try await AndroidBuildService(storage: storage)
                .inspect(bundle: artifact, toolchain: toolchain)
            candidate = BuildCandidate(
                platform: .android, productName: info.applicationID,
                productIdentifier: info.applicationID, marketingVersion: info.versionName,
                buildVersion: String(info.versionCode), artifactPath: artifact.path,
                artifactSize: info.size, sha256: info.sha256,
                signingSummary: .init(certificateSubject: info.certificateSubject,
                                      certificateFingerprint: info.certificateFingerprint,
                                      verified: info.signatureVerified,
                                      verificationDetail: info.signatureDetail),
                preflightSnapshot: snapshot)
        }
        candidate.sourceRevision = ProjectDiscovery.revision(at: project.rootURL)
        candidate.mismatches = mismatches(for: candidate)
        self.candidate = candidate
        run.candidateIdentity = candidate.logicalIdentity
        PostHogSDK.shared.capture("artifact_inspected", properties: [
            "platform": project.platform == .android ? "android" : "apple",
            "source": "project_build",
            "has_blocking_mismatches": !candidate.blockingMismatches.isEmpty
        ])
        try? storage.save(run)

        // A build script can change a version, so any difference matters.
        // Every difference forces a fresh remote check and a new confirmation.
        if !candidate.mismatches.isEmpty {
            await recheckRemote(for: candidate)
        }
        run.move(to: .needsUploadConfirmation)

        // upload-spec 8.14. The app continues by itself only when the first
        // confirmation said it would, no material field changed, and nothing
        // blocks. Android always pauses, because its preflight is a guess.
        if !alwaysReviewArtifact, project.platform != .android,
           candidate.mismatches.isEmpty, blocking == nil {
            startUpload()
        }
    }

    /// upload-spec 8.12 and 9.12.
    private func mismatches(for candidate: BuildCandidate) -> [BuildCandidate.Mismatch] {
        var result: [BuildCandidate.Mismatch] = []
        func compare(_ field: String, _ expected: String?, _ actual: String,
                     blocks: Bool) {
            guard let expected, !expected.isEmpty, expected != actual else { return }
            result.append(.init(field: field, expected: expected, actual: actual,
                                blocksUpload: blocks))
        }
        compare("Bundle identifier", snapshot.productIdentifier, candidate.productIdentifier,
                blocks: true)
        compare("Marketing version", snapshot.marketingVersion, candidate.marketingVersion,
                blocks: false)
        compare("Build number", snapshot.buildVersion, candidate.buildVersion, blocks: false)
        compare("Team", snapshot.team, candidate.signingSummary.team ?? snapshot.team ?? "",
                blocks: false)

        // The manifest is a validation constraint. A mismatch blocks upload.
        if let manifest = app?.manifest {
            let expectedIdentifier = candidate.platform == .android
                ? manifest.apps.google?.packageName
                : manifest.apps.apple?.bundleId
            compare("store.yaml identifier", expectedIdentifier, candidate.productIdentifier,
                    blocks: true)
            if let versionName = manifest.release?.versionName, !versionName.isEmpty,
               versionName != candidate.marketingVersion {
                result.append(.init(field: "store.yaml version", expected: versionName,
                                    actual: candidate.marketingVersion, blocksUpload: true))
            }
        }
        if candidate.signingSummary.verified == false {
            result.append(.init(field: "Signature", expected: "verified",
                                actual: "not verified", blocksUpload: true))
        }
        return result
    }

    // MARK: - The upload

    var canUpload: Bool {
        guard run.state == .needsUploadConfirmation, let candidate else { return false }
        return candidate.blockingMismatches.isEmpty && blocking == nil
    }

    var uploadConfirmationText: String {
        guard let candidate else { return "" }
        let destination = candidate.platform == .android
            ? "Google Play · \(app?.manifest.apps.google?.packageName ?? "")"
            : "App Store Connect · \(app?.manifest.apps.apple?.appId ?? "")"
        return "Upload \(candidate.productIdentifier) version \(candidate.marketingVersion) "
            + "build \(candidate.buildVersion) to \(destination). The upload creates or "
            + "supplies a draft and does not submit it for review."
    }

    /// One fresh read-only conflict check runs immediately before the upload.
    private func recheckRemote(for candidate: BuildCandidate) async {
        guard let app else { return }
        let service = UploadService(api: app.readOnlyAPI())
        do {
            switch candidate.platform {
            case .ios, .macos:
                guard let appID = app.manifest.apps.apple?.appId, !appID.isEmpty else { return }
                let check = try await service.checkApple(
                    appID: appID, platform: candidate.platform,
                    bundleIdentifier: candidate.productIdentifier,
                    marketingVersion: candidate.marketingVersion,
                    buildVersion: candidate.buildVersion)
                snapshot.remoteConflict = check.blocking ?? "No conflict."
                blocking = check.blocking
                if check.existingBuildID != nil {
                    // upload-spec 5.2 step 3.
                    blocking = "\(check.blocking ?? "") Use the existing build instead of uploading it again."
                }
            case .android:
                guard let packageName = app.manifest.apps.google?.packageName,
                      !packageName.isEmpty else { return }
                let check = try await service.checkGoogle(
                    packageName: packageName,
                    track: app.manifest.googlePrimaryTrack,
                    versionCode: Int(candidate.buildVersion))
                snapshot.remoteConflict = check.blocking
                    ?? "No conflict. The highest version code is \(check.highestVersionCode.map(String.init) ?? "none")."
                blocking = check.blocking
            }
        } catch {
            snapshot.remoteConflict = "The store could not be read: \(error.localizedDescription)"
        }
    }

    func startUpload() {
        guard let candidate, let app else { return }
        showUploadConfirmation = false
        failure = nil
        uploadProgress = 0
        artifactOnly = false
        run.move(to: .uploading)
        PostHogSDK.shared.capture("artifact_upload_started", properties: [
            "platform": candidate.platform == .android ? "android" : "apple"
        ])
        try? storage.save(run)

        task = Task { [weak self] in
            guard let self else { return }
            await recheckRemote(for: candidate)
            guard !Task.isCancelled else { return await finishCancel() }
            guard blocking == nil else {
                run.move(to: .needsUploadConfirmation)
                return
            }
            do {
                switch candidate.platform {
                case .ios, .macos: try await uploadApple(candidate)
                case .android: try await uploadGoogle(candidate, app: app)
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

    private func uploadApple(_ candidate: BuildCandidate) async throws {
        let service = AppleBuildService(runner: ToolProcess(redactor: redactor),
                                        storage: storage)
        var authentication: AppleAuthenticationFiles?
        if let credential = app?.credentials.apple, !credential.privateKeyPEM.isEmpty {
            authentication = try AppleAuthenticationFiles.materialize(
                credential: credential, runID: run.id, storage: storage)
        }
        let options = try service.writeExportOptions(
            runID: run.id, platform: candidate.platform,
            team: candidate.signingSummary.team ?? snapshot.team,
            signingStyle: snapshot.signingStyle,
            distributionBundleIdentifier: (appleArchiveInfo?.eligibleApplications.count ?? 0) > 1
                ? candidate.productIdentifier : nil)
        defer { storage.removeScratch(runID: run.id) }

        record(preview: "xcodebuild -exportArchive · destination upload")
        uploadProgress = 0.2
        try await service.exportAndUpload(
            archive: candidate.artifactURL,
            exportPath: try storage.exportURL(runID: run.id), optionsPlist: options,
            authentication: authentication,
            allowProvisioningUpdates: allowProvisioningUpdates,
            onLine: { [weak self] _, line in
                Task { @MainActor in self?.append(line) }
            })
        uploadProgress = 1
        run.move(to: .processingOrValidating)
        try? storage.save(run)
        await pollApple(candidate)
    }

    /// upload-spec 8.16. The poll survives a relaunch, and **Stop waiting**
    /// never pretends that the upload was cancelled.
    func pollApple(_ candidate: BuildCandidate) async {
        guard let app, let appID = app.manifest.apps.apple?.appId, !appID.isEmpty else {
            run.move(to: .recoveryRequired)
            processingLabel = "The upload finished, but no App Store app is linked for processing checks."
            try? storage.save(run)
            return
        }
        let service = UploadService(api: app.readOnlyAPI())
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
                case .processing(let id):
                    processingLabel = "App Store Connect is processing the build."
                    run.remoteIDs["appleBuild"] = id
                case .processed(let id):
                    run.remoteIDs["appleBuild"] = id
                    processingLabel = nil
                    successLink = "https://appstoreconnect.apple.com/apps/\(appID)/testflight/ios"
                    run.move(to: .complete)
                    PostHogSDK.shared.capture("artifact_upload_completed", properties: [
                        "platform": "apple"
                    ])
                    try? storage.save(run)
                    return
                case .failed(let id, let detail):
                    run.remoteIDs["appleBuild"] = id
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
        // Timed out locally. The remote state is still pending, and this says
        // so rather than claiming a failure.
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
        guard let candidate else { return }
        run.move(to: .processingOrValidating)
        task = Task { [weak self] in await self?.pollApple(candidate) }
    }

    private func uploadGoogle(_ candidate: BuildCandidate, app: AppState) async throws {
        guard let packageName = app.manifest.apps.google?.packageName, !packageName.isEmpty else {
            throw BuildFailure(category: .authentication, stage: "Upload the bundle",
                               message: "Enter the Google Play package name on the Stores tab.")
        }
        guard let versionCode = Int(candidate.buildVersion), versionCode > 0 else {
            throw BuildFailure(category: .artifactValidation, stage: "Upload the bundle",
                               message: "The inspected bundle has no valid positive version code.",
                               retainedArtifact: candidate.artifactPath)
        }
        let track = app.manifest.googlePrimaryTrack
        let service = UploadService(api: app.readOnlyAPI())
        record(preview: "POST edits · upload bundle · commit changesNotSentForReview=true")
        run.cleanupState = .pending
        let result = try await service.uploadGoogleBundle(
            packageName: packageName,
            track: track,
            bundle: candidate.artifactURL,
            expectedVersionCode: versionCode,
            versionName: candidate.marketingVersion,
            onEditCreated: { [weak self] editID in
                await self?.rememberGoogleEdit(editID)
            },
            onProgress: { [weak self] value in
                Task { @MainActor in self?.uploadProgress = value }
            })
        run.remoteIDs["googleEdit"] = result.editID
        run.remoteIDs["versionCode"] = String(result.versionCode)
        run.cleanupState = .complete
        successLink = "https://play.google.com/console"
        run.move(to: .complete)
        PostHogSDK.shared.capture("artifact_upload_completed", properties: [
            "platform": "android"
        ])
        try? storage.save(run)
    }

    private func rememberGoogleEdit(_ editID: String) {
        run.remoteIDs["googleEdit"] = editID
        try? storage.save(run)
    }

    // MARK: - Cancellation and failure

    /// upload-spec 6.4 and 3.10. A cancelled local process is not proof that a
    /// remote upload was rejected, so this reconciles before it reports.
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

    private func reconcileAfterCancel() async {
        guard let app, let candidate, candidate.platform == .android,
              let packageName = app.manifest.apps.google?.packageName else {
            run.move(to: .cancelled)
            return
        }
        let service = UploadService(api: app.readOnlyAPI())
        let track = app.manifest.googlePrimaryTrack
        if let landed = try? await service.reconcileGoogle(
            packageName: packageName, track: track,
            versionCode: Int(candidate.buildVersion) ?? 0), landed {
            processingLabel = "The upload had already reached Google Play, so it was not undone."
            run.cleanupState = .complete
            run.move(to: .complete)
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

    /// Retries only the cleanup. It is idempotent.
    func retryCleanup() {
        guard let app, let packageName = app.manifest.apps.google?.packageName,
              let editID = run.remoteIDs["googleEdit"] else { return }
        Task { [weak self] in
            do {
                try await UploadService(api: app.readOnlyAPI())
                    .deleteEdit(packageName: packageName, editID: editID)
                self?.run.cleanupState = .complete
            } catch {
                self?.run.cleanupState = .needsAttention
            }
        }
    }

    /// upload-spec 5.1: a poll and a cleanup may outlive the app process, so
    /// a relaunch picks them up instead of leaving a stranded edit behind.
    func resumeUnfinishedRuns() {
        guard !run.state.isActive else { return }
        guard let stranded = storage.unfinishedRuns().first else { return }
        run = stranded
        switch stranded.state {
        case .processingOrValidating, .recoveryRequired:
            processingLabel = stranded.remoteIDs["appleBuild"] == nil
                ? "A run from \(stranded.startedAt.formatted(date: .abbreviated, time: .shortened)) was still waiting for the store."
                : "The build from \(stranded.startedAt.formatted(date: .abbreviated, time: .shortened)) may still be processing."
        default:
            break
        }
        if stranded.cleanupState == .pending || stranded.cleanupState == .needsAttention {
            run.cleanupState = .needsAttention
            processingLabel = "A Google edit from an earlier run was not confirmed as deleted."
        }
    }

    func fail(_ value: BuildFailure) {
        storage.removeScratch(runID: run.id)
        failure = value
        run.lastError = value
        run.move(to: value.category.needsReconciliation ? .recoveryRequired : .failed)
        PostHogSDK.shared.capture("build_flow_failed", properties: [
            "stage": value.stage
        ])
        try? storage.save(run)
    }

    func retry() {
        failure = nil
        run.move(to: .readyToBuild)
        Task { await refreshPreflight() }
    }

    func keepArtifact() {
        artifactOnly = true
        successLink = nil
        run.move(to: .complete)
        try? storage.save(run)
    }

    func reset() {
        task?.cancel()
        task = nil
        storage.removeScratch(runID: run.id)
        run = UploadRun(platform: run.platform)
        project = nil
        discovery = nil
        containers = []
        containerInfo = nil
        variants = []
        snapshot = PreflightSnapshot()
        candidate = nil
        appleArchiveInfo = nil
        logLines = []
        failure = nil
        blocking = nil
        warnings = []
        processingLabel = nil
        successLink = nil
        artifactOnly = false
        uploadProgress = 0
    }

    // MARK: - Logging

    /// The literals that must never reach a log, a preview, or a diagnostic.
    var redactor: Redactor {
        var literals: [String] = []
        if let apple = app?.credentials.apple { literals.append(apple.privateKeyPEM) }
        if let google = app?.credentials.google { literals.append(google.privateKey) }
        if let key = app?.credentials.revenueCatKey { literals.append(key) }
        if let reviewer = app?.credentials.reviewer { literals.append(reviewer.password) }
        return Redactor(literals: literals)
    }

    func append(_ line: String) {
        logLines.append(line)
        if logLines.count > 2_000 { logLines.removeFirst(logLines.count - 2_000) }
    }

    func record(preview: String) {
        run.commandPreviews.append(preview)
        append("$ \(preview)")
    }

    var logText: String { logLines.joined(separator: "\n") }

    var elapsed: String {
        guard let startedAt else { return "" }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openInIDE() {
        guard let project else { return }
        NSWorkspace.shared.open(project.containerURL)
    }

    func copyDiagnostics() {
        guard let failure else { return }
        app?.copyToPasteboard(failure.report(redactor: redactor))
    }
}

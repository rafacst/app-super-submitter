import AppKit
import Aptabase
import Foundation
import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

/// The build, the inspection, and the upload. upload-spec 8.10 to 8.17 and
/// 9.10 to 9.17.
@MainActor
extension BuildFlow {

    // MARK: - The build

    var canBuild: Bool {
        run.state == .readyToBuild && blockingReason == nil
            && project?.selection.isComplete == true
    }

    /// What stops the build, whether preflight found it or the manifest did.
    ///
    /// `blocking` is what preflight read from the project and from the store.
    /// This adds the one thing neither of them reads. Apple asks the export
    /// compliance question once per build and refuses the submission until the
    /// build carries an answer, so the answer is owed before the archive exists
    /// rather than after it has been uploaded and rejected.
    ///
    /// Store policy and not an API constraint: no endpoint refuses a request
    /// for the missing flag, and the refusal arrives at review. Google asks
    /// nothing of the kind, so an App Bundle is never held for it, and a flow
    /// with no app open has no manifest to answer from.
    ///
    /// The two conditions are the same two the row on the Build tab draws
    /// itself under, on purpose: an answer the tab does not ask for may never
    /// hold the button, or the build stops with nowhere to unstop it.
    var blockingReason: String? {
        if let blocking { return blocking }
        guard let app, run.platform != .android, context.stores.contains(.apple),
              app.encryptionAnswer == nil else { return nil }
        return "Answer the export compliance question in Build setup. Apple asks it once per build and refuses the submission without it."
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
        // The app this build is for, held from here until the run ends. The
        // developer is free to open another tab the moment this returns, and
        // everything after it compares the artifact against a manifest. See
        // `BuildContext`.
        holdContext()
        failure = nil
        clearLog()
        candidate = nil
        artifactOnly = false
        uploadProgress = 0
        startedAt = Date()
        run.move(to: .building)
        Aptabase.shared.trackEvent("project_build_started", with: [
            "platform": project.platform == .android ? "android" : "apple",
            "allow_provisioning_updates": allowProvisioningUpdates ? 1 : 0
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
        if let credential = context.appleCredential {
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
            buildNumber: project.selection.buildNumberOverride,
            marketingVersion: project.selection.marketingVersionOverride,
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
        Aptabase.shared.trackEvent("artifact_inspected", with: [
            "platform": run.platform == .android ? "android" : "apple",
            "source": "imported",
            "has_blocking_mismatches": candidate.blockingMismatches.isEmpty ? 0 : 1
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
            candidate.archiveInfo = info
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
        Aptabase.shared.trackEvent("artifact_inspected", with: [
            "platform": project.platform == .android ? "android" : "apple",
            "source": "project_build",
            "has_blocking_mismatches": candidate.blockingMismatches.isEmpty ? 0 : 1
        ])
        try? storage.save(run)

        // A build script can change a version, so any difference matters.
        // Every difference forces a fresh remote check and a new confirmation.
        if !candidate.mismatches.isEmpty {
            await recheckRemote(for: candidate)
        }
        run.move(to: .needsUploadConfirmation)

        // The other store's build, when one press asked for both. It comes
        // before the upload below: the second artifact is built, never sent,
        // and sending is a separate confirmation either way.
        if queuedStore != nil { return await startQueuedBuild() }
        if queuedApplePlatform != nil { return await startQueuedAppleBuild() }

        // upload-spec 8.14. The app continues by itself only when the first
        // confirmation said it would, no material field changed, and nothing
        // blocks. Android always pauses, because its preflight is a guess.
        if !alwaysReviewArtifact, project.platform != .android, otherCandidates.isEmpty,
           candidate.mismatches.isEmpty, blocking == nil {
            startUpload()
        }
    }

    /// Whether the artifact's build number came out below the one this run
    /// asked for.
    ///
    /// The override exists to get past a number App Store Connect already
    /// holds, so the only artifact that defeats it is one carrying a number
    /// that is no higher than before: a project hardcoding `CFBundleVersion`
    /// ignores the setting, and uploading the number the developer was trying
    /// to get past is the one outcome that helps nobody.
    ///
    /// Higher is not wrong, and blocking it was the bug. A project that stamps
    /// its own number, as a commit-count script phase does, lands above the
    /// chosen one and clears the same conflict. The app was refusing an upload
    /// the store would have taken, and the only way on was to build again.
    ///
    /// Nothing asked for means nothing falls short. Two plain numbers compare
    /// numerically, because 215 against 191 is a question about counting and
    /// not about text. Anything that is not a plain number cannot be reasoned
    /// about at all, so a difference blocks and the developer decides.
    nonisolated static func buildNumberFallsShort(asked: String?, built: String) -> Bool {
        guard let asked, !asked.isEmpty, asked != built else { return false }
        guard let wanted = Int(asked), let carried = Int(built) else { return true }
        return carried < wanted
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
        // A build script that bumps the number is ordinary, so the difference
        // is reported and does not stop the upload. It stops the upload only
        // when the number went the wrong way. See `buildNumberFallsShort`.
        compare("Build number", snapshot.buildVersion, candidate.buildVersion,
                blocks: Self.buildNumberFallsShort(asked: buildNumberOverride,
                                                   built: candidate.buildVersion))
        compare("Team", snapshot.team, candidate.signingSummary.team ?? snapshot.team ?? "",
                blocks: false)

        // The manifest is a validation constraint. A mismatch blocks upload.
        //
        // This flow's own manifest, and it used to be the front-most app's.
        // Two artifacts built at once reported each other: "store.yaml
        // identifier: the preflight said com.rafacst.receitorio and the
        // artifact holds com.rafacst.deckdeckdeck". Both halves were true, and
        // neither belonged in the same sentence. See `BuildContext`.
        let manifest = context.manifest
        let expectedIdentifier = candidate.platform == .android
            ? manifest.apps.google?.packageName
            : manifest.apps.apple?.bundleId
        compare("store.yaml identifier", expectedIdentifier, candidate.productIdentifier,
                blocks: true)
        // The version of the store this artifact is going to. Comparing an
        // App Bundle against the App Store's number is what blocked an
        // upload of the version the Android project has always built.
        if let versionName = manifest.versionName(
            for: candidate.platform == .android ? .google : .apple),
           !versionName.isEmpty, versionName != candidate.marketingVersion {
            result.append(.init(field: "store.yaml version", expected: versionName,
                                actual: candidate.marketingVersion, blocksUpload: true))
        }
        if candidate.signingSummary.verified == false {
            result.append(.init(field: "Signature", expected: "verified",
                                actual: "not verified", blocksUpload: true))
        }
        return result
    }

    // MARK: - The upload

    var canUpload: Bool {
        guard run.state == .needsUploadConfirmation, let candidate,
              // Nothing to send. The developer deleted the file this run made.
              !artifactDeleted else { return false }
        return candidate.blockingMismatches.isEmpty && blocking == nil
            && uploadBlockedByReview == nil
    }

    /// Why a binary may not go up, when Apple is holding the version.
    ///
    /// The apply already refused this state and was the only door that did, so
    /// a build could still be pushed into an app whose version App Store
    /// Connect had locked. Google runs its own queue and Apple's review says
    /// nothing about it, so an App Bundle is never held here.
    ///
    /// Building stays open. What the wait blocks is the send, and an archive
    /// on this machine has been sent nowhere.
    var uploadBlockedByReview: String? {
        guard run.platform != .android,
              let state = app?.actualState.apple?.versionState,
              AppleVersionState.withApple.contains(state) else { return nil }
        return "\(app?.actualState.apple?.versionString ?? "This version") is with App Store review. Apple takes no new build until it answers."
    }

    var uploadConfirmationText: String {
        guard let candidate else { return "" }
        let destination = candidate.platform == .android
            ? "Google Play · \(context.googlePackageName ?? "")"
            : "App Store Connect · \(context.appleAppID ?? "")"
        return "Upload \(candidate.productIdentifier) version \(candidate.marketingVersion) "
            + "build \(candidate.buildVersion) to \(destination). The upload creates or "
            + "supplies a draft and does not submit it for review."
    }

    /// One fresh read-only conflict check runs immediately before the upload.
    private func recheckRemote(for candidate: BuildCandidate) async {
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
                snapshot.remoteConflict = check.blocking ?? "No conflict."
                blocking = check.blocking
                nextFreeBuildNumber = nil
                if check.existingBuildID != nil {
                    // upload-spec 5.2 step 3.
                    blocking = "\(check.blocking ?? "") Use the existing build instead of uploading it again."
                    // The other way out. The store took this number while this
                    // archive was being built, and the number is the only thing
                    // wrong with it, so the offer is to build the next one.
                    nextFreeBuildNumber = String(max(check.highestBuildNumber ?? 0,
                                                     Int(candidate.buildVersion) ?? 0) + 1)
                }
            case .android:
                guard let packageName = context.googlePackageName,
                      !packageName.isEmpty else { return }
                let check = try await service.checkGoogle(
                    packageName: packageName,
                    track: context.googleTrack,
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
        // Building, archiving, and inspecting are free. Only the send is not.
        // The artifact is kept and the run stays where it is, so pressing
        // upload again after paying costs no second build.
        guard app.requirePaid(.storeUpload, .upload) else {
            showUploadConfirmation = false
            return
        }
        showUploadConfirmation = false
        // The app this send is for, held from here on. See `BuildContext`:
        // every step below runs while the developer is free to open another
        // tab and edit another manifest.
        holdContext()
        failure = nil
        uploadProgress = 0
        artifactOnly = false
        run.move(to: .uploading)
        Aptabase.shared.trackEvent("artifact_upload_started", with: [
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
                case .android: try await uploadGoogle(candidate)
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

    /// Makes one retained archive the active upload choice.
    func selectBuiltCandidate(_ selected: BuildCandidate) {
        guard !state.isActive, candidate?.id != selected.id,
              let index = otherCandidates.firstIndex(where: { $0.id == selected.id })
        else { return }
        // The stored element, never the copy the card drew with: only that one
        // carries what happened to the archive since.
        let picked = otherCandidates.remove(at: index)
        if let previous = candidate { otherCandidates.append(previous) }
        candidate = picked
        snapshot = picked.preflightSnapshot ?? PreflightSnapshot()
        appleArchiveInfo = picked.archiveInfo
        project?.platform = picked.platform
        adoptAppleTrain()
        blocking = nil
        nextFreeBuildNumber = nil
        failure = nil
        artifactOnly = false
        successLink = nil
        run = UploadRun(platform: picked.platform, linkedProjectID: project?.id,
                        state: .needsUploadConfirmation)
        run.candidateIdentity = picked.logicalIdentity
        try? storage.save(run)
        task = Task { [weak self] in
            guard let self else { return }
            await recheckRemote(for: picked)
        }
    }

    private func uploadApple(_ candidate: BuildCandidate) async throws {
        let service = AppleBuildService(runner: ToolProcess(redactor: redactor),
                                        storage: storage)
        var authentication: AppleAuthenticationFiles?
        if let credential = context.appleCredential {
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
            access: app?.access ?? UnconfiguredAccess(),
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
                case .processing(let id):
                    processingLabel = "App Store Connect is processing the build."
                    run.remoteIDs["appleBuild"] = id
                case .processed(let id):
                    run.remoteIDs["appleBuild"] = id
                    processingLabel = nil
                    successLink = "https://appstoreconnect.apple.com/apps/\(appID)/testflight/ios"
                    run.move(to: .complete)
                    self.candidate?.settled = true
                    storeGainedABuild()
                    Aptabase.shared.trackEvent("artifact_upload_completed", with: [
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
        // A relaunch keeps the run and loses the held copy with it, so the poll
        // is pointed at this flow's own app. It is the right one either way: a
        // run belongs to one flow and a flow belongs to one app.
        holdContext()
        run.move(to: .processingOrValidating)
        task = Task { [weak self] in await self?.pollApple(candidate) }
    }

    private func uploadGoogle(_ candidate: BuildCandidate) async throws {
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
        record(preview: "POST edits · upload bundle · commit changesNotSentForReview=true")
        run.cleanupState = .pending
        let result = try await service.uploadGoogleBundle(
            packageName: packageName,
            track: context.googleTrack,
            bundle: candidate.artifactURL,
            expectedVersionCode: versionCode,
            versionName: candidate.marketingVersion,
            // The account gate, which belongs to the developer and not to the
            // app, so it stays live.
            access: app?.access ?? UnconfiguredAccess(),
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
        self.candidate?.settled = true
        storeGainedABuild()
        Aptabase.shared.trackEvent("artifact_upload_completed", with: [
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
        queuedStore = nil
        queuedApplePlatform = nil
        if run.state == .uploading || run.cleanupState == .pending {
            await reconcileAfterCancel()
        } else {
            run.move(to: .cancelled)
        }
        try? storage.save(run)
    }

    /// The same frozen target the send used, and for a stronger reason than the
    /// send had: this deletes an edit. Reading the package name off the
    /// front-most app here would have deleted a draft belonging to whichever app
    /// the developer had opened while the cancel was reconciling.
    private func reconcileAfterCancel() async {
        guard let candidate, candidate.platform == .android,
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
            // A cancel that arrived too late still left a build on the store.
            storeGainedABuild()
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
        // The target the edit was made under. A relaunch loses it, and the flow
        // belongs to one app, so its own app answers for it after that.
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
        queuedStore = nil
        queuedApplePlatform = nil
        failure = value
        run.lastError = value
        // The panel tells the developer to read the log, so the log is on the
        // screen when the panel arrives, and it holds every line rather than
        // every line but the last tenth of a second's worth.
        flushLog()
        if !logLines.isEmpty { logOpen = true }
        run.move(to: value.category.needsReconciliation ? .recoveryRequired : .failed)
        Aptabase.shared.trackEvent("build_flow_failed", with: [
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
        candidate?.settled = true
        artifactOnly = true
        successLink = nil
        run.move(to: .complete)
        try? storage.save(run)
    }

    /// The next build, after one finished.
    ///
    /// A run that reached `complete` had no control that left it: the Build
    /// button asks for `readyToBuild`, and **Start over** is for an imported
    /// artifact. So the tab allowed one build per session, and a developer who
    /// changed the app afterwards had to send the artifact of the build before
    /// the change, or nothing at all.
    ///
    /// A new `UploadRun` rather than a move back. The run id names the archive
    /// file, the saved run record, and the command previews, so a second build
    /// under the first run's id would write over the record of an upload that
    /// already happened.
    ///
    /// The linked project, the platform, and the provisioning choice stay: the
    /// developer chose those, and a rebuild is not a reason to ask again.
    func buildAgain() {
        guard !state.isActive, let project else { return }
        task?.cancel()
        task = nil
        storage.removeScratch(runID: run.id)
        run = UploadRun(platform: run.platform, linkedProjectID: project.id)
        candidate = nil
        otherCandidates = []
        supportsBothApplePlatforms = false
        appleArchiveInfo = nil
        clearLog()
        failure = nil
        blocking = nil
        processingLabel = nil
        successLink = nil
        artifactOnly = false
        uploadProgress = 0
        startedAt = nil
        task = Task { [weak self] in await self?.refreshPreflight() }
    }

    func reset() {
        task?.cancel()
        task = nil
        storage.removeScratch(runID: run.id)
        run = UploadRun(platform: run.platform)
        project = nil
        discovery = nil
        discoveryRoot = nil
        containers = []
        containerInfo = nil
        variants = []
        snapshot = PreflightSnapshot()
        candidate = nil
        otherCandidates = []
        supportsBothApplePlatforms = false
        appleArchiveInfo = nil
        clearLog()
        failure = nil
        blocking = nil
        warnings = []
        processingLabel = nil
        successLink = nil
        artifactOnly = false
        uploadProgress = 0
        // A queue outlives nothing. A second build that fires after the first
        // was reset, cancelled, or failed is a build nobody asked for.
        queuedStore = nil
        queuedApplePlatform = nil
    }

    // MARK: - Logging

    /// The literals that must never reach a log, a preview, or a diagnostic.
    var redactor: Redactor {
        var literals: [String] = []
        // This app's own keys, so a log redacts the secrets of the build that
        // wrote it and never those of whichever tab is in front.
        let credentials = context.credentials
        if let apple = credentials.apple { literals.append(apple.privateKeyPEM) }
        if let google = credentials.google { literals.append(google.privateKey) }
        if let key = credentials.revenueCatKey { literals.append(key) }
        if let reviewer = credentials.reviewer { literals.append(reviewer.password) }
        return Redactor(literals: literals)
    }

    /// Collects a line, and publishes at ten frames a second.
    ///
    /// `xcodebuild` prints several hundred lines a second. Appending each one
    /// straight to `logLines` invalidated the view that many times a second,
    /// and the window stopped answering while the log was open. The buffer is
    /// not observed, so a line costs an array append until the flush.
    ///
    /// The flush is a `Task` and not a timer: it holds no reference when
    /// nothing is running, so a finished build schedules nothing.
    func append(_ line: String) {
        logBuffer.append(line)
        if logBuffer.count > Self.logLimit {
            logBuffer.removeFirst(logBuffer.count - Self.logLimit)
        }
        scheduleLogFlush()
    }

    /// Drops the log and the flush waiting to publish it. Without the cancel,
    /// a flush scheduled by the last line of the previous run would republish
    /// that run's log a tenth of a second into this one.
    func clearLog() {
        logFlush?.cancel()
        logFlush = nil
        logBuffer = []
        logLines = []
    }

    /// Publishes the buffer now, and drops the flush that was going to.
    ///
    /// The scheduled flush covers the end of a run on its own, which is right
    /// while the run is only printing. A failure is the one moment worth a
    /// hundred milliseconds: the panel appears in the same frame and it says to
    /// read the log, so the log may not be a tenth of a second behind it.
    func flushLog() {
        logFlush?.cancel()
        logFlush = nil
        if logLines != logBuffer { logLines = logBuffer }
    }

    /// The flush that publishes the buffer, a tenth of a second from now.
    ///
    /// It doubles as the last flush of a run. A run that stops printing leaves
    /// one scheduled, and it fires, so no separate "the build finished" flush
    /// has to exist and be remembered at five call sites.
    private func scheduleLogFlush() {
        guard logFlush == nil else { return }
        logFlush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, !Task.isCancelled else { return }
            logFlush = nil
            if logLines != logBuffer { logLines = logBuffer }
        }
    }

    func record(preview: String) {
        run.commandPreviews.append(preview)
        append("$ \(preview)")
    }

    /// Every line, for the pasteboard. `logLines` is what the box drew at
    /// the last flush; the buffer is the whole run.
    var logText: String { logBuffer.joined(separator: "\n") }

    /// How long the run took, and how long it has taken so far.
    ///
    /// The end is the run's own finish and not the clock. Reading the clock
    /// after the build was over kept the number climbing for as long as the
    /// result stayed on screen, so a two minute build read four minutes by the
    /// time anybody looked at it.
    var elapsed: String {
        guard let startedAt else { return "" }
        let seconds = Int((run.finishedAt ?? Date()).timeIntervalSince(startedAt))
        return String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    /// The store now holds something it did not hold when the plan was read.
    ///
    /// The plan, the runway steps and the release blockers are all built from
    /// one store read, and nothing in them noticed an upload. `adoptBuiltArtifact`
    /// invalidates the plan, but only the **Continue to Summary** button calls
    /// it, so a developer who reached the Summary from the sidebar was shown
    /// the store as it stood before the build existed: a blocker describing a
    /// build from an earlier read, beside a build that had just landed.
    ///
    /// It invalidates and does not read. `readStores` refuses to run while a
    /// run is unfinished, and this is called from inside one; the Summary
    /// reads for itself when it opens and finds no plan.
    private func storeGainedABuild() {
        app?.invalidatePlan()
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Whether the artifact on screen is one this app made and may remove.
    ///
    /// Never during a run: the upload is reading the file it is sending. And
    /// never for an Android bundle, which is not a platform rule but the same
    /// path rule `BuildStorage` enforces: Gradle writes the `.aab` inside the
    /// developer's own project, and a bundle chosen by hand is any file on the
    /// disk.
    var artifactIsDeletable: Bool {
        guard let candidate, !artifactDeleted, !state.isActive else { return false }
        return storage.owns(candidate.artifactURL)
    }

    /// Removes the artifact this run made.
    ///
    /// An archive is the largest thing this app leaves behind, and until now
    /// the only way to be rid of one was the Finder or the nuclear option in
    /// Settings, which also forgets every account.
    func deleteArtifact() {
        guard let candidate, artifactIsDeletable else { return }
        do {
            try storage.removeArtifact(at: candidate.artifactURL)
            artifactDeleted = true
            app?.errorMessage = "The artifact was deleted. \(candidate.productIdentifier) \(candidate.marketingVersion) (\(candidate.buildVersion)) is no longer on this Mac."
        } catch {
            app?.errorMessage = "The artifact could not be deleted: \(error.localizedDescription)"
        }
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

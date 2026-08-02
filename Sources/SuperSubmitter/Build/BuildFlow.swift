import AppKit
import Foundation
import Observation
import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

/// Build from Project. upload-spec sections 5 and 10.
///
/// The state machine lives in `UploadRun`; this type moves it and holds what
/// each screen shows. Every rule stays in SubmitKit.
@Observable
@MainActor
final class BuildFlow {
    @ObservationIgnored weak var app: AppState?
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored let storage = BuildStorage()
    /// Kept so the export can name a distribution bundle when the archive
    /// holds more than one eligible application.
    @ObservationIgnored var appleArchiveInfo: ArchiveInfo?

    var run: UploadRun
    var project: LinkedSourceProject?
    var discovery: DiscoveryResult?
    var containers: [DiscoveryResult.Container] = []

    var appleToolchain: AppleToolchain?
    var androidToolchain: AndroidToolchain?
    var containerInfo: XcodeContainerInfo?
    var variants: [GradleVariant] = []

    var snapshot = PreflightSnapshot()
    var candidate: BuildCandidate?
    var logLines: [String] = []
    var logOpen = false
    var failure: BuildFailure?
    var processingLabel: String?
    var successLink: String?
    var artifactOnly = false
    var uploadProgress = 0.0
    var blocking: String?
    var warnings: [String] = []
    var startedAt: Date?

    /// Off by default, and shown on every confirmation. Xcode may create App
    /// IDs, certificates, and profiles with it on. upload-spec 8.6.
    var allowProvisioningUpdates = false
    /// Defaults on. upload-spec 8.14.
    var alwaysReviewArtifact = true
    var showBuildConfirmation = false
    var showUploadConfirmation = false

    init(app: AppState) {
        self.app = app
        self.run = UploadRun(platform: .ios)
    }

    // MARK: - Linking

    var state: UploadState { run.state }
    var isBusy: Bool { run.state.isActive }

    var platform: BuildPlatform {
        get { run.platform }
        set { run.platform = newValue }
    }

    /// upload-spec 7.1. Explicit selection is the consent boundary, so the
    /// panel states what a build can execute before the developer chooses.
    func linkFolder() {
        let panel = NSOpenPanel()
        panel.title = "Link a project folder"
        panel.message = "Super Submitter will inspect this project and run its build. "
            + "Building may execute scripts, package plug-ins, compiler macros, and other "
            + "code supplied by the project."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Link"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        discover(root: url)
    }

    func discover(root: URL) {
        reset()
        run.move(to: .discovering)
        task = Task { [weak self] in
            let result = await Task.detached { ProjectDiscovery.scan(root: root) }.value
            guard let self, !Task.isCancelled else { return }
            discovery = result
            containers = result.containers
            warnings = result.notes

            if let recommended = ProjectDiscovery.recommended(result.containers) {
                await select(container: recommended, root: root)
            } else if result.containers.isEmpty {
                fail(BuildFailure(
                    category: .projectDiscovery, stage: "Validate the project",
                    message: "No Xcode workspace, Xcode project, or Gradle wrapper is in this folder.",
                    recovery: "Choose the folder that holds the project."))
            } else {
                run.move(to: .needsSelection)
            }
        }
    }

    /// A workspace never wins silently when a second container exists, so this
    /// is always an explicit act.
    func select(container: DiscoveryResult.Container, root: URL) async {
        let platform: BuildPlatform = container.kind == .gradle ? .android : .ios
        var project = LinkedSourceProject(
            platform: platform, rootPath: root.path,
            containerPath: container.path, containerKind: container.kind)
        project.folderBookmark = try? root.bookmarkData(includingResourceValuesForKeys: nil,
                                                        relativeTo: nil)
        project.selection.allowProvisioningUpdates = allowProvisioningUpdates
        self.project = project
        run.platform = platform
        run.linkedProjectID = project.id
        persistProject()
        await refreshPreflight()
    }

    func unlink() {
        guard let project else { return }
        var list = storage.loadProjects()
        list.removeAll { $0.id == project.id }
        try? storage.saveProjects(list)
        reset()
    }

    private func persistProject() {
        guard var project else { return }
        project.lastValidatedAt = Date()
        self.project = project
        var list = storage.loadProjects()
        list.removeAll { $0.id == project.id || $0.rootPath == project.rootPath }
        list.append(project)
        try? storage.saveProjects(list)
    }

    func loadSavedProject() {
        guard project == nil, let saved = storage.loadProjects().last else { return }
        project = saved
        run.platform = saved.platform
        run.linkedProjectID = saved.id
        allowProvisioningUpdates = saved.selection.allowProvisioningUpdates
    }

    // MARK: - Preflight

    /// upload-spec 8.1 to 8.8 and 9.3 to 9.8. Read-only. Nothing here builds.
    func refreshPreflight() async {
        guard let project else { return }
        candidate = nil
        artifactOnly = false
        // A saved link is not proof that the folder still holds the project.
        guard FileManager.default.fileExists(atPath: project.containerPath) else {
            fail(BuildFailure(
                category: .projectAccess, stage: "Validate the project",
                message: "\(project.containerURL.lastPathComponent) is no longer at the saved path.",
                recovery: "Press Link Project Folder and locate it again."))
            return
        }
        run.move(to: .preflight)
        blocking = nil
        failure = nil
        snapshot = PreflightSnapshot()
        snapshot.containerPath = project.containerPath

        do {
            switch project.platform {
            case .ios, .macos: try await applePreflight(project)
            case .android: try await androidPreflight(project)
            }
        } catch let failure as BuildFailure {
            fail(failure)
            return
        } catch {
            fail(BuildFailure(category: .configuration, stage: "Resolve the toolchain",
                              message: error.localizedDescription))
            return
        }
        if run.state == .preflight, run.state.canMove(to: .readyToBuild) {
            run.move(to: .readyToBuild)
        }
        persistProject()
    }

    private func applePreflight(_ project: LinkedSourceProject) async throws {
        let service = AppleBuildService(storage: storage)
        let toolchain = try await service.toolchain()
        appleToolchain = toolchain
        if let failure = toolchain.failure { throw failure }
        snapshot.toolchain = toolchain.label

        let info = try await service.list(container: project.containerURL,
                                          kind: project.containerKind)
        containerInfo = info
        if project.selection.scheme == nil || !info.schemes.contains(project.selection.scheme ?? "") {
            guard info.schemes.count == 1 else {
                self.project?.selection.scheme = nil
                run.move(to: .needsSelection)
                return
            }
            self.project?.selection.scheme = info.schemes[0]
        }
        guard let scheme = self.project?.selection.scheme else {
            run.move(to: .needsSelection)
            return
        }
        let configuration = self.project?.selection.configuration
            ?? (info.configurations.contains("Release") ? "Release" : info.configurations.first)
        self.project?.selection.configuration = configuration
        snapshot.scheme = scheme
        snapshot.configuration = configuration
        snapshot.destination = run.platform.appleDestination

        let settings = try await service.settings(
            container: project.containerURL, kind: project.containerKind, scheme: scheme,
            configuration: configuration, platform: run.platform)
        snapshot.productName = settings.productName
        snapshot.productIdentifier = settings.bundleIdentifier
        snapshot.marketingVersion = settings.marketingVersion
        snapshot.buildVersion = settings.currentProjectVersion
        snapshot.team = settings.team
        snapshot.signingStyle = settings.signingStyle
        snapshot.signingIdentity = settings.signingIdentity
        snapshot.provisioningProfile = settings.provisioningProfile
        snapshot.sdk = settings.sdkRoot
        snapshot.signingReady = settings.team?.isEmpty == false
        self.project?.productIdentifier = settings.bundleIdentifier

        // The manifest is a constraint, never a command to edit the project.
        if let expected = app?.manifest.apps.apple?.bundleId, !expected.isEmpty,
           let actual = settings.bundleIdentifier, expected != actual {
            blocking = "The project builds \(actual) and store.yaml names \(expected). Change the selection or the manifest."
        }
        await appleRemoteCheck(settings: settings)
    }

    private func appleRemoteCheck(settings: AppleBuildSettings) async {
        guard let app, let appID = app.manifest.apps.apple?.appId, !appID.isEmpty,
              let bundleIdentifier = settings.bundleIdentifier else {
            snapshot.remoteConflict = "No App Store app is connected, so no conflict check ran."
            return
        }
        do {
            let check = try await UploadService(api: app.readOnlyAPI()).checkApple(
                appID: appID, platform: run.platform, bundleIdentifier: bundleIdentifier,
                marketingVersion: settings.marketingVersion ?? "",
                buildVersion: settings.currentProjectVersion)
            snapshot.remoteConflict = check.blocking
                ?? "No conflict. The highest build in App Store Connect is \(check.highestBuildNumber.map(String.init) ?? "none")."
            if let message = check.blocking { blocking = message }
        } catch {
            snapshot.remoteConflict = "The App Store could not be read: \(error.localizedDescription)"
        }
    }

    private func androidPreflight(_ project: LinkedSourceProject) async throws {
        let service = AndroidBuildService(storage: storage)
        let toolchain = try await service.toolchain(root: project.containerURL,
                                                    preferredJavaHome: project.selection.javaHome)
        androidToolchain = toolchain
        if let failure = toolchain.failure { throw failure }
        snapshot.toolchain = toolchain.label
        snapshot.gradleVersion = toolchain.gradleVersion
        snapshot.javaVersion = "\(toolchain.javaVersion) · \(toolchain.javaHome)"
        snapshot.androidSDKPath = toolchain.androidSDKPath
        self.project?.selection.javaHome = toolchain.javaHome

        if variants.isEmpty {
            variants = try await service.variants(root: project.containerURL,
                                                  toolchain: toolchain,
                                                  onLine: { [weak self] _, line in
                Task { @MainActor in self?.append(line) }
            })
        }
        if project.selection.variantTask == nil || !variants.contains(where: {
            $0.qualifiedTask == project.selection.variantTask
        }) {
            guard variants.count == 1 else {
                self.project?.selection.variantTask = nil
                run.move(to: .needsSelection)
                return
            }
            self.project?.selection.module = variants[0].module
            self.project?.selection.variantTask = variants[0].qualifiedTask
        }
        snapshot.module = self.project?.selection.module
        snapshot.variantTask = self.project?.selection.variantTask
        snapshot.outputExpectation = "\(project.containerPath)/…/build/outputs/bundle/"

        // Gradle computes these. They are unknown, not wrong.
        snapshot.productIdentifier = app?.manifest.apps.google?.packageName
        snapshot.uncertainFields = ["productIdentifier", "marketingVersion", "buildVersion",
                                    "signingReady"]
        await googleRemoteCheck()
    }

    private func googleRemoteCheck() async {
        guard let app, let packageName = app.manifest.apps.google?.packageName,
              !packageName.isEmpty else {
            snapshot.remoteConflict = "No Google Play package is connected, so no conflict check ran."
            return
        }
        do {
            let check = try await UploadService(api: app.readOnlyAPI()).checkGoogle(
                packageName: packageName,
                track: app.manifest.release?.google?.track ?? "production",
                versionCode: nil)
            snapshot.remoteConflict = check.highestVersionCode
                .map { "The highest version code in Google Play is \($0)." }
                ?? "Google Play holds no bundle yet."
        } catch {
            snapshot.remoteConflict = "Google Play could not be read: \(error.localizedDescription)"
        }
    }

    // MARK: - Selection

    func chooseScheme(_ scheme: String) {
        project?.selection.scheme = scheme
        restartPreflight()
    }

    func chooseVariant(_ variant: GradleVariant) {
        project?.selection.module = variant.module
        project?.selection.variantTask = variant.qualifiedTask
        restartPreflight()
    }

    func chooseJDK(_ home: String) {
        project?.selection.javaHome = home
        restartPreflight()
    }

    func choosePlatform(_ platform: BuildPlatform) {
        run.platform = platform
        restartPreflight()
    }

    private func restartPreflight() {
        task?.cancel()
        task = Task { [weak self] in await self?.refreshPreflight() }
    }
}

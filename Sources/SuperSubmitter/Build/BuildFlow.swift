import AppKit
import Foundation
import Observation
import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

/// How one half of a run stands. The half it belongs to supplies the words.
enum BuildSidebarStatus: Equatable {
    case running, succeeded, failed

    func spoken(_ job: String) -> String {
        switch self {
        case .running: "\(job) in progress"
        case .succeeded: "\(job) succeeded"
        case .failed: "\(job) failed"
        }
    }
}

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
    /// What the log box draws. It is written by `flushLog`, ten times a second
    /// at most, and never once per line: a build prints hundreds a second, and
    /// an observed write per line is what froze the window.
    var logLines: [String] = []
    /// Every line the tools printed. Not observed, so a line costs an append.
    @ObservationIgnored var logBuffer: [String] = []
    @ObservationIgnored var logFlush: Task<Void, Never>?
    /// How much of a build log is worth keeping. Beyond this the head goes,
    /// because the end of a log is the half that says what went wrong.
    static let logLimit = 5_000
    var logOpen = false
    var failure: BuildFailure?
    var processingLabel: String?
    var successLink: String?
    var artifactOnly = false
    var uploadProgress = 0.0
    var blocking: String?
    var warnings: [String] = []
    var startedAt: Date?
    /// The first build number the store does not hold, when it holds the one
    /// this project carries. Nil the rest of the time, and nil is the usual
    /// state: it is set only by a conflict that a higher number would clear.
    var nextFreeBuildNumber: String?

    /// Off by default, and shown on every confirmation. Xcode may create App
    /// IDs, certificates, and profiles with it on. upload-spec 8.6.
    var allowProvisioningUpdates = false
    /// Defaults on. upload-spec 8.14.
    var alwaysReviewArtifact = true
    var showBuildConfirmation = false
    var showUploadConfirmation = false

    /// `app` is already weak and optional, so the initialiser says so too. It
    /// lets the log tests build a flow without an `AppState`, which reads the
    /// Keychain and the defaults and answers nothing this flow needs.
    init(app: AppState?) {
        self.app = app
        self.run = UploadRun(platform: .ios)
    }

    // MARK: - Linking

    var state: UploadState { run.state }
    var isBusy: Bool { run.state.isActive }

    /// Making the artifact, shown beside Build in the sidebar. `startedAt`
    /// keeps discovery and preflight from looking like a build the user
    /// started.
    var artifactStatus: BuildSidebarStatus? {
        guard startedAt != nil else { return nil }
        switch state {
        case .building, .inspectingArtifact, .cancelling:
            return .running
        case .needsUploadConfirmation, .uploading, .processingOrValidating,
             .recoveryRequired, .complete:
            return .succeeded
        case .failed:
            return failedDuringUpload ? nil : .failed
        default:
            return nil
        }
    }

    /// Sending it, which is a separate job with a separate outcome.
    ///
    /// One indicator reported both, so an archive that was built and never
    /// sent drew the same green tick as one the store had accepted. That is
    /// the app claiming a store holds something it does not, and it is the
    /// claim a developer acts on.
    var uploadStatus: BuildSidebarStatus? {
        guard startedAt != nil else { return nil }
        switch state {
        case .uploading, .processingOrValidating:
            return .running
        case .recoveryRequired:
            return .running
        // Keeping the artifact ends the run without an upload, so the tick
        // belongs to the build alone.
        case .complete:
            return artifactOnly ? nil : .succeeded
        case .failed:
            return failedDuringUpload ? .failed : nil
        default:
            return nil
        }
    }

    /// Which half a failure belongs to. The category already says it, and it
    /// is the only thing that does: the state is `failed` either way.
    private var failedDuringUpload: Bool {
        switch failure?.category {
        case .upload, .remoteValidation, .remoteAmbiguous, .authentication,
             .remoteConflict, .cleanup:
            true
        default:
            false
        }
    }

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

    /// The folder the developer already chose, without asking for it again.
    ///
    /// The import asks for the app folder and writes `store.yaml` inside it,
    /// so by the time the Build tab opens, the app already knows where the
    /// project is. Asking a second time is the app forgetting what it was
    /// told one screen ago.
    ///
    /// A scan reads the folder and runs nothing. The build itself still asks
    /// on its own sheet, so the consent boundary in upload-spec 7.1 stays
    /// exactly where it was.
    func adoptTheAppFolder() {
        guard project == nil, candidate == nil, failure == nil, !state.isActive,
              let root = app?.manifestRoot else { return }
        discover(root: root, quietWhenEmpty: true)
    }

    /// `quietWhenEmpty` is for the folder the app chose for itself. A folder
    /// with no project in it is an ordinary answer there, and an error panel
    /// about a choice the developer never made is not.
    func discover(root: URL, quietWhenEmpty: Bool = false) {
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
                guard !quietWhenEmpty else { reset(); return }
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
            containerPath: container.path, containerKind: container.kind,
            manifestPath: app?.manifestURL?.path)
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

    /// The project of the app that is open, and no other.
    ///
    /// The links are one list for the whole Mac. Taking the last one showed
    /// the app you linked most recently under whichever app you had open,
    /// which is nine wrong answers in a sidebar of ten. A link written before
    /// the manifest path existed still matches, by its folder.
    func loadSavedProject() {
        // The sidebar can change the open app while this tab holds another
        // app's project. A running build keeps the tab as it is, because
        // killing it to redraw a card would cost the developer the build.
        if let held = project?.manifestPath, !state.isActive,
           held != app?.manifestURL?.standardizedFileURL.path {
            reset()
        }
        guard project == nil else { return }
        guard let saved = savedProjectForOpenApp() else {
            // Nothing linked for this app. The folder the developer already
            // chose for it is the answer often enough that asking first is
            // the wrong order.
            adoptTheAppFolder()
            return
        }
        project = saved
        run.platform = saved.platform
        run.linkedProjectID = saved.id
        allowProvisioningUpdates = saved.selection.allowProvisioningUpdates
        // A restored link is a linked project, so the tab owes the same
        // preflight the first link got. Without it the card sat there with
        // no toolchain, no scheme, and no Build button until the developer
        // unlinked the project and chose the folder again.
        //
        // The state is read again inside the task, not here. `.task` calls
        // `resumeUnfinishedRuns` immediately after this line, and a run that
        // outlived the last launch is the one that belongs on screen. Only an
        // untouched run is still `unlinked` by the time this body runs.
        task = Task { [weak self] in
            guard let self, run.state == .unlinked else { return }
            await refreshPreflight()
        }
    }

    private func savedProjectForOpenApp() -> LinkedSourceProject? {
        guard let manifest = app?.manifestURL?.standardizedFileURL.path else { return nil }
        let root = (manifest as NSString).deletingLastPathComponent
        let list = storage.loadProjects()
        return list.last { $0.manifestPath == manifest }
            ?? list.last { $0.manifestPath == nil && Self.folder($0.rootPath, isInside: root) }
    }

    /// True when the project sits in the app's own folder or under it. Pure
    /// string work, so it needs no actor and a test can call it directly.
    nonisolated static func folder(_ path: String, isInside root: String) -> Bool {
        let project = (path as NSString).standardizingPath
        let root = (root as NSString).standardizingPath
        return project == root || project.hasPrefix(root + "/")
    }

    // MARK: - Preflight

    /// upload-spec 8.1 to 8.8 and 9.3 to 9.8. Read-only. Nothing here builds.
    func refreshPreflight() async {
        guard let project else { return }
        // A saved link is not proof that the folder still holds the project.
        guard FileManager.default.fileExists(atPath: project.containerPath) else {
            fail(BuildFailure(
                category: .projectAccess, stage: "Validate the project",
                message: "\(project.containerURL.lastPathComponent) is no longer at the saved path.",
                recovery: "Press Link Project Folder and locate it again."))
            return
        }
        // Not `move(to: .preflight)`. A finished run, a link restored from
        // disk, and a fresh launch all sit in a state that cannot reach the
        // preflight in one move, and `move` refuses those in silence: the
        // snapshot below then filled for a run that was still `complete` or
        // `unlinked`, the guard at the end never reached `readyToBuild`, and
        // the tab drew a project card with no Build button.
        guard run.moveToPreflight() else { return }
        // After the move and not before it. A refused call leaves the run and
        // the artifact it holds exactly as they were.
        candidate = nil
        artifactOnly = false
        blocking = nil
        nextFreeBuildNumber = nil
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
            configuration: configuration, platform: run.platform,
            buildNumber: buildNumberOverride)
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
        nextFreeBuildNumber = nil
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
            // Only the duplicate. A missing app and a bundle identifier that
            // belongs to another app both block too, and no build number
            // clears either of them.
            if check.existingBuildID != nil {
                let held = max(check.highestBuildNumber ?? 0,
                               Int(settings.currentProjectVersion ?? "") ?? 0)
                nextFreeBuildNumber = String(held + 1)
            }
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
                track: app.manifest.googlePrimaryTrack,
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

    /// The build number this run archives with, or nil while the project
    /// decides. It belongs to the link, so it outlives a relaunch the way the
    /// scheme and the configuration do.
    var buildNumberOverride: String? { project?.selection.buildNumberOverride }

    /// Build the next number the store does not hold.
    ///
    /// App Store Connect refuses a build number it already has, and the only
    /// way past it was Xcode: change the number in the project, come back, and
    /// press Recheck. The number now travels as a command-line setting
    /// override, so nothing in the project is opened or written, and the
    /// preflight runs again from the top: the store is asked a second time
    /// with the new number, and the archive that follows carries it too.
    func useNextBuildNumber() {
        guard let number = nextFreeBuildNumber else { return }
        project?.selection.buildNumberOverride = number
        persistProject()
        restartPreflight()
    }

    /// Back to the number the project itself carries. An override that nobody
    /// can see off is an app quietly deciding a developer's version numbers
    /// for every build after this one.
    func useProjectBuildNumber() {
        guard buildNumberOverride != nil else { return }
        project?.selection.buildNumberOverride = nil
        persistProject()
        restartPreflight()
    }

    /// The link carries the answer too, not only the run.
    ///
    /// `loadSavedProject` restores `run.platform` from the saved project, so a
    /// choice that stopped at the run came back as iOS at the next launch and
    /// the developer had to make it again. Every switch on this value reads
    /// `.ios` and `.macos` the same way; only Android parts anywhere.
    /// `refreshPreflight` writes the link at the end, so this needs no save of
    /// its own.
    func choosePlatform(_ platform: BuildPlatform) {
        run.platform = platform
        project?.platform = platform
        restartPreflight()
    }

    private func restartPreflight() {
        task?.cancel()
        task = Task { [weak self] in await self?.refreshPreflight() }
    }
}

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

/// The app one build belongs to: its manifest, its keys, its folder.
///
/// A build runs for minutes and the window does not wait for it. The app tabs
/// exist so another app can be worked on meanwhile, and every field below used
/// to be read off the front-most `AppState` at the moment the background work
/// happened to ask. Two artifacts built at once came out crossed:
///
///     store.yaml identifier: the preflight said com.rafacst.receitorio
///     and the artifact holds com.rafacst.deckdeckdeck.
///     store.yaml version: the preflight said 1.5 and the artifact holds 1.6.1.
///
/// Both halves of that sentence were right. The artifact was DeckDeckDeck's and
/// the `store.yaml` was Receitório's, because the developer had moved on by the
/// time the archive finished and the comparison read whatever tab was in front.
/// The same read decided which App Store id the conflict check asked about and,
/// worse, which `store.yaml` the finished artifact was written into.
///
/// So a flow carries its app rather than looking it up. See `BuildFlow.context`
/// for when this is refreshed and when it is held still.
struct BuildContext {
    /// The linked record this build belongs to. Every write goes back to this
    /// app and to no other.
    var appID: UUID
    var manifest: Manifest
    var manifestURL: URL?
    var stores: Set<Store>
    var applePlatform: Manifest.Platform
    var appleCredential: AppleCredential?
    var credentials: StoreCredentials
    /// An actor built from the credentials of that moment, so a key changed on
    /// another tab cannot re-sign a send already under way.
    var api: StoreAPI

    var manifestRoot: URL? { manifestURL?.deletingLastPathComponent() }
    var appleAppID: String? { manifest.apps.apple?.appId }
    var googlePackageName: String? { manifest.apps.google?.packageName }
    var googleTrack: String { manifest.googlePrimaryTrack }

    @MainActor init(_ app: AppState, appID: UUID) {
        self.appID = appID
        manifest = app.manifest
        manifestURL = app.manifestURL
        stores = app.stores
        applePlatform = app.applePlatform
        credentials = app.credentials
        appleCredential = app.credentials.apple.flatMap {
            $0.privateKeyPEM.isEmpty ? nil : $0
        }
        api = app.readOnlyAPI()
    }

    /// An app that is not there, for a flow built without one. Every field is
    /// the empty answer, so nothing falls back to another app's.
    init(appID: UUID) {
        self.appID = appID
        manifest = Manifest()
        stores = []
        applePlatform = .ios
        credentials = StoreCredentials()
        api = StoreAPI(credentials: StoreCredentials(), record: { _ in })
    }
}

/// Build from Project. upload-spec sections 5 and 10.
///
/// The state machine lives in `UploadRun`; this type moves it and holds what
/// each screen shows. Every rule stays in SubmitKit.
///
/// One of these per app, kept by `AppState.buildFlows`. It was one for the whole
/// window, so the tab bar would have handed app B the controls of app A's
/// running build: B's Build tab drew A's log and A's progress, and pressing
/// Build there drove the same run.
@Observable
@MainActor
final class BuildFlow {
    @ObservationIgnored weak var app: AppState?
    @ObservationIgnored var task: Task<Void, Never>?

    /// The app this flow builds for. It never changes.
    @ObservationIgnored let owner: UUID

    /// The owner's manifest, keys and folder. See `BuildContext` for the two
    /// artifacts this crossed.
    ///
    /// Live while this flow's app is the one on screen and nothing is running,
    /// so an edit to `store.yaml` is seen by the next preflight. Held still
    /// otherwise, which covers both ways a flow stops being the front-most
    /// thing: the developer opens another tab, or the run starts and they carry
    /// on editing. A run that reads a manifest halfway through an edit is the
    /// same class of bug as one that reads another app's.
    var context: BuildContext {
        guard let app, !isBusy, app.isOpenApp(owner) else { return heldContext }
        heldContext = BuildContext(app, appID: owner)
        return heldContext
    }

    /// Mutated from `context`'s getter, which a class allows, and unobserved so
    /// that refreshing it inside a view's body invalidates nothing.
    @ObservationIgnored private var heldContext: BuildContext

    /// Takes the copy the run will use, at the moment the run starts.
    ///
    /// `context` refreshes itself whenever it is asked and the flow is idle, so
    /// this is usually the same value it already holds. It is explicit because
    /// "usually" is not a guarantee: nothing promises that a view read the
    /// context between the last edit and the press.
    func holdContext() {
        guard let app, app.isOpenApp(owner) else { return }
        heldContext = BuildContext(app, appID: owner)
    }
    /// Injectable so a test can link and restore projects against a folder of
    /// its own. The default is the one the app ships with; nothing but a test
    /// ever passes another.
    @ObservationIgnored let storage: BuildStorage
    /// Kept so the export can name a distribution bundle when the archive
    /// holds more than one eligible application.
    @ObservationIgnored var appleArchiveInfo: ArchiveInfo?

    var run: UploadRun
    var project: LinkedSourceProject?
    var discovery: DiscoveryResult?
    @ObservationIgnored var discoveryRoot: URL?
    var containers: [DiscoveryResult.Container] = []

    var appleToolchain: AppleToolchain?
    var androidToolchain: AndroidToolchain?
    /// What the linked Gradle module's files say it builds. A hint, kept
    /// because the store check reads it as well as the preflight rows do.
    var androidIdentity = AndroidProjectIdentity()
    var containerInfo: XcodeContainerInfo?
    var variants: [GradleVariant] = []

    var snapshot = PreflightSnapshot()
    var candidate: BuildCandidate?
    /// Earlier artifacts from a multi-platform build. `candidate` remains the
    /// artifact selected for upload, so the existing upload flow stays single-file.
    var otherCandidates: [BuildCandidate] = []
    var supportsBothApplePlatforms = false
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
    /// The artifact this run made is no longer on the disk, because the
    /// developer deleted it from the artifact card. The candidate stays: it is
    /// the record of what was built, and the success card, the Summary hand-off
    /// and the sidebar all read it.
    var artifactDeleted: Bool {
        get { candidate?.deleted ?? false }
        set { candidate?.deleted = newValue }
    }
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
    /// The one press that builds both stores has its own question, because it
    /// names two projects and runs the scripts of each.
    var showBuildBothConfirmation = false
    var showBuildBothApplePlatformsConfirmation = false
    var showUploadConfirmation = false

    /// `app` is already weak and optional, so the initialiser says so too. It
    /// lets the log tests build a flow without an `AppState`, which reads the
    /// Keychain and the defaults and answers nothing this flow needs.
    init(app: AppState?, owner: UUID = UUID(), storage: BuildStorage = BuildStorage()) {
        self.app = app
        self.owner = owner
        self.storage = storage
        self.run = UploadRun(platform: .ios)
        // A flow with no app is a test's flow. It answers about an app that
        // does not exist rather than about whichever one is open, which is the
        // same rule the rest of this type follows.
        heldContext = app.map { BuildContext($0, appID: owner) }
            ?? BuildContext(appID: owner)
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
    ///
    /// One sentence, and it used to be three. The full paragraph named scripts,
    /// package plug-ins and compiler macros separately, which is 173 characters
    /// on one line, and AppKit widens the panel until that line fits: it opened
    /// wider than the window with every sidebar location truncated to six
    /// letters. See `NSSavePanel.explain`.
    ///
    /// Nothing is lost by saying it once. Linking a folder runs none of it, and
    /// the sentence is said again at the moment code actually runs, on the
    /// build confirmation sheet. See `buildConfirmationText`.
    func linkFolder() {
        let panel = NSOpenPanel()
        panel.title = "Link a project folder"
        panel.explain("Building this project runs scripts and code the project supplies.")
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
              let root = context.manifestRoot else { return }
        discover(root: root, quietWhenEmpty: true)
    }

    /// `quietWhenEmpty` is for the folder the app chose for itself. A folder
    /// with no project in it is an ordinary answer there, and an error panel
    /// about a choice the developer never made is not.
    func discover(root: URL, quietWhenEmpty: Bool = false) {
        reset()
        discoveryRoot = root
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
        // The scan's own notes go with the choosing. "The scan stopped at its
        // depth or entry limit" answers "why is my project not in this list",
        // and every project with a deep source tree trips the depth limit, so
        // it sat on the preflight card of a linked project as a permanent
        // yellow line about a list nobody is reading any more.
        warnings = []
        // Before `context` is read below: a deferred import left `store.yaml`
        // in Super Submitter's own folder, and this is the first time the
        // developer has pointed at a real one. See
        // `relocateManifestIfPending`.
        relocateManifestIfPending(to: root)
        let platform: BuildPlatform = container.kind == .gradle ? .android : .ios
        var project = LinkedSourceProject(
            platform: platform, rootPath: root.path,
            containerPath: container.path, containerKind: container.kind,
            manifestPath: context.manifestURL?.path)
        project.folderBookmark = try? root.bookmarkData(includingResourceValuesForKeys: nil,
                                                        relativeTo: nil)
        project.selection.allowProvisioningUpdates = allowProvisioningUpdates
        self.project = project
        discoveryRoot = nil
        containers = []
        run.platform = platform
        run.linkedProjectID = project.id
        persistProject()
        await refreshPreflight()
    }

    /// Moves `store.yaml`, its downloaded media, and its store snapshot out
    /// of Super Submitter's own folder and into the project root just
    /// linked.
    ///
    /// A Publishing import of one app already writes `store.yaml` where the
    /// project lives. A Publishing import of several apps defers that
    /// question and writes into `BuildStorage.managed` instead, the same as
    /// a Managing import; `awaitingProjectFolder` marks the difference. This
    /// is the moment that deferred promise is kept, so the developer's
    /// `store.yaml` ends up exactly where a single-app import would have put
    /// it, just later.
    ///
    /// Silent and automatic: linking a project is already the developer's
    /// own deliberate act, and asking a second question about a promise this
    /// app already made would be asking twice for one answer.
    private func relocateManifestIfPending(to root: URL) {
        guard let app, app.isOpenApp(owner),
              let index = app.linkedApps.firstIndex(where: { $0.id == owner }),
              app.linkedApps[index].awaitingProjectFolder == true,
              let oldRoot = app.manifestURL?.deletingLastPathComponent()
        else { return }
        let newManifestURL = root.appendingPathComponent(ManifestFile.defaultName)
        // A folder that already holds a `store.yaml` is not empty ground to
        // move into: leave the deferred copy where it is rather than
        // overwrite whatever is already there.
        guard !FileManager.default.fileExists(atPath: newManifestURL.path) else { return }
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: oldRoot, includingPropertiesForKeys: nil)
            for item in items {
                let destination = root.appendingPathComponent(item.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                try FileManager.default.moveItem(at: item, to: destination)
            }
            try? FileManager.default.removeItem(at: oldRoot)
            app.linkedApps[index].manifestPath = newManifestURL.path
            app.linkedApps[index].awaitingProjectFolder = false
            app.persistLinkedApps()
            app.manifestURL = newManifestURL
        } catch {
            app.errorMessage = "This app's store.yaml could not move into the linked "
                + "folder. \(error.localizedDescription)"
        }
    }

    /// Forgets the link. It removes the record and touches no file the
    /// developer owns: the project folder and everything in it stay exactly
    /// where they are.
    func unlink() {
        guard let project else { return }
        var list = storage.loadProjects()
        list.removeAll { $0.id == project.id }
        do { try storage.saveProjects(list) }
        catch {
            app?.errorMessage = "That link could not be removed. \(error.localizedDescription)"
        }
        reset()
    }

    private func persistProject() {
        guard var project else { return }
        project.lastValidatedAt = Date()
        self.project = project
        write(project)
    }

    /// Puts one link in the list and writes the list back.
    ///
    /// A failure here is reported. It used to be `try?`, and a write that
    /// cannot land is exactly the bug this file was carrying: the developer
    /// links a folder, the app draws it as linked, and the next launch has
    /// never heard of it. Silence made that indistinguishable from working.
    private func write(_ project: LinkedSourceProject) {
        var list = storage.loadProjects()
        // One link per app per store, and it used to dedup on the folder. A
        // monorepo holding an Xcode project beside a Gradle one is one folder
        // and two links, so removing by `rootPath` deleted the sibling every
        // time the other one was saved.
        //
        // `store` and not `platform`: iOS and macOS are one App Store app that
        // archives from the same project, and two links for them would make
        // the platform switch on this tab lose the scheme.
        list.removeAll {
            $0.id == project.id
                || ($0.manifestPath == project.manifestPath
                    && $0.platform.store == project.platform.store)
                || ($0.manifestPath == nil && $0.rootPath == project.rootPath)
        }
        list.append(project)
        do { try storage.saveProjects(list) }
        catch {
            app?.errorMessage = "The link to \(project.rootPath) could not be saved, "
                + "so it will not be here on the next launch. \(error.localizedDescription)"
        }
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
           held != context.manifestURL?.standardizedFileURL.path {
            reset()
        }
        guard project == nil else { return }
        guard var saved = savedProjectForOpenApp() else {
            // Nothing linked for this app. The folder the developer already
            // chose for it is the answer often enough that asking first is
            // the wrong order.
            adoptTheAppFolder()
            return
        }
        // The bookmark is what finds the folder after it has been renamed or
        // moved. It was written on every link and read by nothing, so the
        // saved path was the only route back and a moved folder unlinked
        // itself. Writing the record back keeps the next launch cheap.
        if Self.followBookmark(&saved) { write(saved) }
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

    /// Every link this app has, one per store at most.
    func savedProjectsForOpenApp() -> [LinkedSourceProject] {
        guard let manifest = context.manifestURL?.standardizedFileURL.path else { return [] }
        let root = (manifest as NSString).deletingLastPathComponent
        let list = storage.loadProjects()
        let named = list.filter { $0.manifestPath == manifest }
        guard named.isEmpty else { return named }
        // A link written before the manifest path existed still matches, by
        // its folder.
        return list.filter { $0.manifestPath == nil && Self.folder($0.rootPath, isInside: root) }
    }

    /// The link for one store, or nil when that store has none.
    ///
    /// An app can ship an Xcode project and a Gradle project, and they are two
    /// folders as often as they are two folders inside one. This used to take
    /// the last link the app had whatever store it built for, so linking the
    /// Gradle folder replaced the Xcode one and the Build tab had one of the
    /// two at a time.
    func savedProject(for store: Store) -> LinkedSourceProject? {
        savedProjectsForOpenApp().last { $0.platform.store == store }
    }

    private func savedProjectForOpenApp() -> LinkedSourceProject? {
        // The store this tab is on. A run that has not chosen yet takes the
        // link the app has, and prefers Apple when it has both, because that
        // is the platform a fresh run starts on.
        savedProject(for: run.platform.store)
            ?? savedProjectsForOpenApp().last { $0.platform.store == .apple }
            ?? savedProjectsForOpenApp().last
    }

    /// Follows the linked folder to wherever it is now, and refreshes the
    /// bookmark that found it. It answers true when the record changed and has
    /// to be written back.
    ///
    /// `folderBookmark` was stored on every link and resolved nowhere, so it
    /// was a field that cost bytes and did nothing. A bookmark tracks the
    /// folder itself rather than its name, which is the whole reason to keep
    /// one: a developer who renames `~/apps/deck` to `~/apps/deck-ios` has the
    /// same project, and the saved path alone says the link is gone.
    ///
    /// The saved path stays the fallback. A bookmark that resolves to nothing,
    /// on a volume that is not mounted or a folder that was really deleted,
    /// leaves the record exactly as it was: the path may still be right, and
    /// the preflight is what reports a folder that is not there.
    ///
    /// No security scope. This app is not sandboxed, so a plain bookmark
    /// resolves without one and `startAccessingSecurityScopedResource` would
    /// be machinery for a permission the process already has.
    ///
    /// `withoutUI` and `withoutMounting` because this runs while the Build tab
    /// draws. Without them, resolving a bookmark to a network volume can put
    /// up a mount dialog, or block, on the main actor.
    nonisolated static func followBookmark(_ project: inout LinkedSourceProject) -> Bool {
        guard let data = project.folderBookmark else { return false }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              // A bookmark can resolve to a path that is no longer there.
              FileManager.default.fileExists(atPath: url.path) else { return false }

        var changed = false
        let moved = url.standardizedFileURL.path
        if moved != project.rootPath {
            // The container sits inside the root, so it moves with it. Rebased
            // and not rebuilt: the workspace or the `gradlew` keeps its own
            // name and its own depth under the folder.
            project.containerPath = rebase(project.containerPath,
                                           from: project.rootPath, to: moved)
            project.rootPath = moved
            changed = true
        }
        // A stale bookmark still resolved, and it will not keep doing so. The
        // fresh one is what makes the next move findable too.
        if stale, let fresh = try? url.bookmarkData(includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            project.folderBookmark = fresh
            changed = true
        }
        return changed
    }

    /// One path under a folder that moved, under where the folder is now. A
    /// path that was never under it is left alone.
    nonisolated static func rebase(_ path: String, from old: String, to new: String) -> String {
        guard path != old else { return new }
        guard path.hasPrefix(old + "/") else { return path }
        return new + String(path.dropFirst(old.count))
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
        // Capture current identifiers and credentials before preflight makes
        // the context immutable for the active operation.
        holdContext()
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

        // The scheme comes before the checks. The last read already listed the
        // container, so when the scheme is open and the list holds more than
        // one, the question is asked at once: no toolchain read, no package
        // graph, and no card of Checking… rows that ends in a question anyway.
        if project.platform.store == .apple, project.selection.scheme == nil,
           (containerInfo?.schemes.count ?? 0) > 1 {
            run.move(to: .needsSelection)
            return
        }

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
            buildNumber: buildNumberOverride,
            marketingVersion: marketingVersionOverride)
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
        supportsBothApplePlatforms = settings.supportsBothApplePlatforms
        self.project?.productIdentifier = settings.bundleIdentifier

        // The manifest is a constraint, never a command to edit the project.
        if let expected = context.manifest.apps.apple?.bundleId, !expected.isEmpty,
           let actual = settings.bundleIdentifier, expected != actual {
            blocking = "The project builds \(actual) and store.yaml names \(expected). Change the selection or the manifest."
        }
        await appleRemoteCheck(settings: settings)
    }

    private func appleRemoteCheck(settings: AppleBuildSettings) async {
        nextFreeBuildNumber = nil
        guard let appID = context.appleAppID, !appID.isEmpty,
              let bundleIdentifier = settings.bundleIdentifier else {
            snapshot.remoteConflict = "No App Store app is connected, so no conflict check ran."
            return
        }
        do {
            let check = try await UploadService(api: context.api).checkApple(
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

        // What the module's own files say, which is a hint and not the answer:
        // Gradle computes these and only the built bundle settles them. They
        // stay in `uncertainFields` for that reason, and the four rows now
        // carry the values that sit as literals in `build.gradle` instead of
        // reading "Not read" on a project the developer has just linked.
        let identity = AndroidBuildService.identity(root: project.containerURL,
                                                    module: self.project?.selection.module)
        androidIdentity = identity
        snapshot.productName = identity.appName
        // The project's own id first. This row says what the build will
        // produce, and the manifest says where it is going: a package name
        // typed on the tab above cannot make Gradle build that package.
        snapshot.productIdentifier = identity.applicationID
            ?? context.googlePackageName
        // No override is read here. `buildBundle` runs the variant task and
        // passes no property, because a plain Android project takes neither
        // number from the command line, and a row showing a number Gradle will
        // not build is worse than the row that said nothing.
        snapshot.marketingVersion = identity.versionName
        snapshot.buildVersion = identity.versionCode
        snapshot.uncertainFields = ["productName", "productIdentifier", "marketingVersion",
                                    "buildVersion", "signingReady"]
        await googleRemoteCheck()
    }

    private func googleRemoteCheck() async {
        guard let packageName = context.googlePackageName,
              !packageName.isEmpty else {
            // The project's own applicationId goes in the sentence. The row
            // said the package was missing while the module beside it named
            // one, and the developer had to go and find in Android Studio the
            // value this card had just read.
            snapshot.remoteConflict = androidIdentity.applicationID.map {
                "No Google Play package is on the tab above, so no conflict check ran. This project builds \($0)."
            } ?? "No Google Play package is connected, so no conflict check ran."
            return
        }
        do {
            let check = try await UploadService(api: context.api).checkGoogle(
                packageName: packageName,
                track: context.googleTrack,
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

    /// The marketing version this run archives with, or nil while the project
    /// decides. It belongs to the link, like the build number above.
    var marketingVersionOverride: String? { project?.selection.marketingVersionOverride }

    /// The release version `store.yaml` names, when the project builds another
    /// one. Nil the rest of the time, and nil is the usual state.
    ///
    /// The identifier has been compared here since the beginning and the
    /// version never was, although both are blocking mismatches once the
    /// artifact exists. So a developer who typed 1.6 into Release version was
    /// shown the project's 1.5 on this card with a green tick beside it, and
    /// learnt that the two disagreed only after a whole archive had been
    /// built and the upload was refused.
    ///
    /// The store's own number, and not the other one's. An Android project
    /// that has always built 1.0.0 is not disagreeing with the App Store's
    /// 1.4.1: the two stores number apart.
    var versionFromManifest: String? {
        guard let wanted = context.manifest.versionName(for: run.platform.store), !wanted.isEmpty,
              let building = snapshot.marketingVersion, !building.isEmpty,
              wanted != building else { return nil }
        return wanted
    }

    /// Whether the disagreement above has a button beside it.
    ///
    /// Only Apple. `xcodebuild` takes `MARKETING_VERSION` on the command line,
    /// so the app can build the number the manifest names without touching the
    /// project. A plain Gradle build takes no such property, so on Android the
    /// row says the two numbers and the developer settles it: either the store
    /// field on the tab above, or the project.
    var canBuildTheManifestVersion: Bool { run.platform != .android }

    /// Build the version `store.yaml` names.
    ///
    /// It travels as a command-line setting override, so nothing in the
    /// project is opened or written, and the preflight runs again from the
    /// top: the store is asked a second time about that version, and the
    /// archive that follows carries it too.
    func useManifestVersion() {
        guard let version = versionFromManifest else { return }
        project?.selection.marketingVersionOverride = version
        persistProject()
        restartPreflight()
    }

    /// Back to the version the project itself carries.
    func useProjectVersion() {
        guard marketingVersionOverride != nil else { return }
        project?.selection.marketingVersionOverride = nil
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
        // Across the two stores it is a different project, not the same one
        // relabelled. iOS and macOS archive from one Xcode project, so those
        // two stay on the link they are on; Android is a Gradle folder, and
        // rewriting the platform on the Apple link is what made an app able to
        // hold one of the two at a time.
        if project?.platform.store != platform.store {
            guard adoptLink(for: platform.store) else { return }
        } else {
            project?.platform = platform
            // One scheme slot serves both Apple platforms, and a project that
            // ships on both usually has a scheme for each. Unless the scheme's
            // own settings named both, the new platform needs its own: the
            // preflight would otherwise read the settings of a scheme Xcode has
            // no destination for, and answer a question with an error.
            if platform.store == .apple, !supportsBothApplePlatforms {
                project?.selection.scheme = nil
            }
        }
        adoptAppleTrain()
        restartPreflight()
    }

    /// The store side follows the build side.
    ///
    /// Two platforms decided two different things and nothing kept them
    /// together. `run.platform` chose what to archive and where the binary was
    /// uploaded; `manifest.apps.apple.platforms.first` chose which App Store
    /// version every read and every write of the plan meant. One app id carries
    /// a train per platform, so a developer who switched this picker to macOS
    /// built a Mac binary, sent it to the Mac train, and then watched the apply
    /// renumber the **iOS** version and write the listing into it. Both halves
    /// were certain they were on the right one.
    ///
    /// The picker on this tab is the one a developer actually uses, so it is
    /// the one that decides. The platform is inserted at the front of the
    /// manifest's list, which adds it when the app had never named it: a Mac
    /// binary uploaded under this app id is that app shipping on macOS,
    /// whatever the manifest said before the build.
    ///
    /// The setter throws away the store snapshot and the plan, which is right:
    /// both describe the other train.
    func adoptAppleTrain() {
        guard let app, run.platform.store == .apple, context.manifest.apps.apple != nil else {
            return
        }
        let wanted: Manifest.Platform = run.platform == .macos ? .macOS : .ios
        guard app.applePlatform != wanted else { return }
        app.applePlatform = wanted
    }

    /// Puts the other store's linked project on the tab, and clears the card
    /// that belongs to the one leaving.
    ///
    /// False when that store has no folder linked. Nil is a state and not a
    /// failure there: the card offers to link one.
    @discardableResult
    private func adoptLink(for store: Store) -> Bool {
        project = savedProject(for: store)
        // The link's own platform wins. An Apple link may be a macOS one, and
        // forcing the platform the switch asked for would archive the wrong
        // destination from the right project.
        if let saved = project { run.platform = saved.platform }
        run.linkedProjectID = project?.id
        containers = []
        containerInfo = nil
        variants = []
        supportsBothApplePlatforms = false
        snapshot = PreflightSnapshot()
        candidate = nil
        blocking = nil
        warnings = []
        guard project != nil else {
            run.move(to: .unlinked)
            return false
        }
        return true
    }

    /// Whether this app can produce both stores' artifacts from one press.
    ///
    /// It goes to both stores and both have a project linked. One store, or
    /// one link, is one build, and a second button for it would do what the
    /// first one already does.
    var canBuildBothStores: Bool {
        let stores = context.stores
        guard stores.count > 1 else { return false }
        return stores.allSatisfy { savedProject(for: $0) != nil }
    }

    /// The store whose build follows this one, when the developer asked for
    /// both. Nil during an ordinary single build, which is every other build.
    var queuedStore: Store?

    /// The second native Apple archive from one multi-platform project.
    var queuedApplePlatform: BuildPlatform?

    var canBuildBothApplePlatforms: Bool {
        project?.platform.store == .apple && supportsBothApplePlatforms && canBuild
    }

    var builtCandidates: [BuildCandidate] {
        otherCandidates + (candidate.map { [$0] } ?? [])
    }

    /// Builds the selected platform first, then the other native Apple platform.
    func buildBothApplePlatforms() {
        guard canBuildBothApplePlatforms else { return }
        showBuildBothApplePlatformsConfirmation = false
        queuedApplePlatform = run.platform == .ios ? .macos : .ios
        startBuild()
    }

    /// Starts the second Apple archive after the first archive passes inspection.
    func startQueuedAppleBuild() async {
        guard let next = queuedApplePlatform else { return }
        queuedApplePlatform = nil
        guard failure == nil, blocking == nil,
              candidate?.blockingMismatches.isEmpty == true else { return }
        if let candidate, !otherCandidates.contains(where: { $0.id == candidate.id }) {
            otherCandidates.append(candidate)
        }
        run.platform = next
        project?.platform = next
        adoptAppleTrain()
        await refreshPreflight()
        guard canBuild else { return }
        startBuild()
    }

    /// Builds both stores' artifacts, one after the other.
    ///
    /// Google Play first and the App Store second, always, and the order is
    /// not a preference. An App Bundle's path goes into `store.yaml`, so it
    /// survives the tab moving on to the other store, and the apply picks it
    /// up from there. An archive has nowhere to be written down: it is the
    /// card's own candidate and the upload button beside it is the only way it
    /// reaches Apple, so it has to be the artifact left on screen at the end.
    ///
    /// One press and two projects, so the confirmation names both. Building
    /// runs the scripts of each.
    func buildBothStores() {
        guard canBuildBothStores else { return }
        showBuildBothConfirmation = false
        queuedStore = .apple
        guard run.platform.store != .google else { return startBuild() }
        task = Task { [weak self] in
            guard let self, adoptLink(for: .google) else {
                self?.queuedStore = nil
                return
            }
            await refreshPreflight()
            guard canBuild else { return }
            startBuild()
        }
    }

    /// The second half of a both-stores build.
    ///
    /// It runs when the first artifact has been inspected and nothing about it
    /// blocks. A block stops the chain where it is: the card holds the artifact
    /// and the reason, and the developer decides what the second build should
    /// be before it runs.
    func startQueuedBuild() async {
        guard let next = queuedStore else { return }
        queuedStore = nil
        guard failure == nil, blocking == nil,
              candidate?.blockingMismatches.isEmpty == true else { return }
        // The App Bundle goes into `store.yaml` before the tab moves on. It is
        // the only record of it, and the card is about to draw another store.
        app?.adoptBuiltArtifact(from: self)
        guard adoptLink(for: next) else { return }
        await refreshPreflight()
        guard canBuild else { return }
        startBuild()
    }

    private func restartPreflight() {
        task?.cancel()
        task = Task { [weak self] in await self?.refreshPreflight() }
    }
}

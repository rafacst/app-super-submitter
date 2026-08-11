import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The import asks for the app folder and writes `store.yaml` inside it. The
/// Build tab then asked for the same folder again, which is the app
/// forgetting what it was told one screen ago.
@Test func aProjectInsideTheAppFolderCountsAsThatAppsProject() {
    #expect(BuildFlow.folder("/Users/me/apps/deck", isInside: "/Users/me/apps/deck"))
    #expect(BuildFlow.folder("/Users/me/apps/deck/ios", isInside: "/Users/me/apps/deck"))
    // A neighbour whose name merely starts the same way is a different app.
    #expect(!BuildFlow.folder("/Users/me/apps/deck-two", isInside: "/Users/me/apps/deck"))
    #expect(!BuildFlow.folder("/Users/me/apps/other", isInside: "/Users/me/apps/deck"))
}

/// The links are one list for the whole Mac, and the Build tab used to open
/// whichever one was linked last. In a sidebar of ten apps that is nine wrong
/// answers, and it also hid the folder the app already knew about.
@MainActor
@Test func theBuildTabOpensTheProjectOfTheAppThatIsOpen() throws {
    let storage = BuildStorage()
    let previous = storage.loadProjects()
    defer { try? storage.saveProjects(previous) }

    let mine = "/Users/me/apps/mine/store.yaml"
    let theirs = "/Users/me/apps/theirs/store.yaml"
    let projects = [
        LinkedSourceProject(platform: .ios, rootPath: "/Users/me/apps/mine",
                            containerPath: "/Users/me/apps/mine/Mine.xcodeproj",
                            containerKind: .project, manifestPath: mine),
        // Linked later, and belonging to another app.
        LinkedSourceProject(platform: .android, rootPath: "/Users/me/apps/theirs",
                            containerPath: "/Users/me/apps/theirs/gradlew",
                            containerKind: .gradle, manifestPath: theirs),
    ]
    try storage.saveProjects(projects)

    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.manifestURL = URL(fileURLWithPath: mine)
    let flow = BuildFlow(app: state)

    flow.loadSavedProject()

    #expect(flow.project?.manifestPath == mine)
    #expect(flow.project?.platform == .ios)
}

/// One press, both artifacts. An app that goes to both stores keeps a link per
/// store, and building each one meant switching the tab over by hand.
@MainActor
@Test func bothStoresBuildFromOnePressWhenEachHasAProject() throws {
    let storage = BuildStorage()
    let previous = storage.loadProjects()
    defer { try? storage.saveProjects(previous) }

    let mine = "/Users/me/apps/mine/store.yaml"
    try storage.saveProjects([
        LinkedSourceProject(platform: .ios, rootPath: "/Users/me/apps/mine",
                            containerPath: "/Users/me/apps/mine/Mine.xcodeproj",
                            containerKind: .project, manifestPath: mine),
        LinkedSourceProject(platform: .android, rootPath: "/Users/me/apps/mine/android",
                            containerPath: "/Users/me/apps/mine/android/gradlew",
                            containerKind: .gradle, manifestPath: mine),
    ])

    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "test-\(UUID().uuidString)")
    state.manifestURL = URL(fileURLWithPath: mine)
    state.setStore(.apple, enabled: true)
    state.setStore(.google, enabled: true)
    let flow = BuildFlow(app: state)

    #expect(flow.canBuildBothStores)
    #expect(flow.savedProject(for: .apple)?.containerKind == .project)
    #expect(flow.savedProject(for: .google)?.containerKind == .gradle)

    // One store, or one link, is one build. A second button for it would do
    // what the first one already does.
    state.setStore(.google, enabled: false)
    #expect(!flow.canBuildBothStores)
}

/// The queue never outlives the run that set it. A second build firing after
/// the first was reset, cancelled, or failed is a build nobody asked for.
@MainActor
@Test func aStoppedRunCarriesNoQueuedBuild() async {
    let flow = BuildFlow(app: nil)
    flow.queuedStore = .apple
    flow.reset()
    #expect(flow.queuedStore == nil)

    flow.queuedStore = .apple
    flow.fail(BuildFailure(category: .build, stage: "Build", message: "no"))
    #expect(flow.queuedStore == nil)

    // And a queue with nothing built behind it starts nothing.
    flow.queuedStore = .apple
    await flow.startQueuedBuild()
    #expect(flow.queuedStore == nil)
    #expect(flow.project == nil)
}

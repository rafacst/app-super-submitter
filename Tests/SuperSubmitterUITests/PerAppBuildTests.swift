import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A build belongs to the app it was started on, not to the window.
///
/// The bug this guards: `buildFlow` was one object for the whole window and
/// nothing cancelled or rebound it on a switch, so opening another app handed
/// that app the controls of the first one's running build. Its Build tab drew
/// the other app's log and its progress, and pressing Build there drove the
/// same run. The app tabs make switching mid-build the ordinary thing to do,
/// which is the point of them, so the flow follows the app.

@MainActor
private func window(_ count: Int) throws -> (state: AppState, folder: URL) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("per-app-\(UUID().uuidString)")
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "per-app-\(UUID().uuidString)")
    for index in 0..<count {
        let app = folder.appendingPathComponent("app-\(index)")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "10000000\(index)", bundleID: "com.example.app\(index)")
        let url = app.appendingPathComponent("store.yaml")
        try ManifestFile.save(manifest, to: url)
        state.link(manifestAt: url)
    }
    return (state, folder)
}

@MainActor
@Test func eachAppHasItsOwnBuild() throws {
    let (state, folder) = try window(2)
    defer { try? FileManager.default.removeItem(at: folder) }

    state.selectApp(at: 0)
    let first = state.buildFlow
    // The same app answers with the same flow, so a redraw does not restart a
    // build or lose a log.
    #expect(state.buildFlow === first)

    state.selectApp(at: 1)
    let second = state.buildFlow
    #expect(second !== first)

    // And going back finds the first one still there, running or not.
    state.selectApp(at: 0)
    #expect(state.buildFlow === first)
}

/// The mark on a tab the developer has left. Without it a build that is no
/// longer on the screen has no way to say it is still going.
@MainActor
@Test func aBusyAppSaysSoFromAnotherTab() throws {
    let (state, folder) = try window(2)
    defer { try? FileManager.default.removeItem(at: folder) }

    state.selectApp(at: 0)
    let building = state.linkedApps[0].id
    // Through the states the table allows. `move` refuses a jump it does not
    // carry, and it refuses in silence.
    let reached = state.buildFlow.run.moveToPreflight()
        && state.buildFlow.run.move(to: .readyToBuild)
        && state.buildFlow.run.move(to: .building)
    #expect(reached)
    state.selectApp(at: 1)

    #expect(state.isBuilding(appID: building))
    #expect(!state.isBuilding(appID: state.linkedApps[1].id))
    // The open app's own flow is a fresh one and not the busy one.
    #expect(!state.buildFlow.isBusy)
}

/// The app a build compares itself against, once the developer has moved on.
///
/// This is the reported bug. Two artifacts were built at once and the finished
/// one reported the other app's manifest:
///
///     store.yaml identifier: the preflight said com.rafacst.receitorio
///     and the artifact holds com.rafacst.deckdeckdeck.
///
/// Every read went through the front-most `AppState`, so the identity check,
/// the conflict check, the signing key and the write of the finished artifact
/// all followed the tab rather than the build.
@MainActor
@Test func aBuildComparesItselfAgainstItsOwnApp() throws {
    let (state, folder) = try window(2)
    defer { try? FileManager.default.removeItem(at: folder) }

    state.selectApp(at: 0)
    let first = state.buildFlow
    #expect(first.context.appleAppID == "100000000")

    // The developer opens the other app while the first one is building.
    state.selectApp(at: 1)
    #expect(state.manifest.apps.apple?.appId == "100000001")
    #expect(state.buildFlow.context.appleAppID == "100000001")
    // The build that is still running answers for the app it belongs to.
    #expect(first.context.appleAppID == "100000000")
    #expect(first.context.appID == state.linkedApps[0].id)
}

/// And it stops following the front-most app the moment it starts running, so
/// an edit made on another tab cannot reach a run that is already comparing.
@MainActor
@Test func aRunningBuildHoldsTheManifestItStartedWith() throws {
    let (state, folder) = try window(1)
    defer { try? FileManager.default.removeItem(at: folder) }

    state.selectApp(at: 0)
    let flow = state.buildFlow
    flow.holdContext()
    let reached = flow.run.moveToPreflight()
        && flow.run.move(to: .readyToBuild)
        && flow.run.move(to: .building)
    #expect(reached)

    // The developer keeps working on the same app while it builds.
    state.manifest.setAppleApp(appID: "999999999", bundleID: "com.example.changed")

    #expect(state.manifest.apps.apple?.appId == "999999999")
    #expect(flow.context.appleAppID == "100000000")
}

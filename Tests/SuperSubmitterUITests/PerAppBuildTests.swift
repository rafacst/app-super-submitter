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

/// The store record a send is for, frozen when the developer pressed Upload.
///
/// Reading it off the front-most `AppState` mid-send pointed the upload, the
/// processing poll, the conflict re-check and the cancel cleanup at whichever
/// app was open by then. The cleanup is the one that would have deleted a draft
/// belonging to the wrong app.
@MainActor
@Test func aSendKeepsTheAppItWasStartedFor() throws {
    let (state, folder) = try window(2)
    defer { try? FileManager.default.removeItem(at: folder) }

    state.selectApp(at: 0)
    let target = BuildTarget(state)
    #expect(target.appleAppID == "100000000")

    state.selectApp(at: 1)
    // The window moved on. The frozen target did not.
    #expect(state.manifest.apps.apple?.appId == "100000001")
    #expect(target.appleAppID == "100000000")
}

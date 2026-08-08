import Foundation
import Testing
@testable import SubmitKit

/// The Build tab allowed one build per session.
///
/// `refreshPreflight` moved the run to `preflight` with a bare `move`, and
/// `move` refuses a jump the table does not carry without saying so. A run that
/// reached `complete` and a link restored from disk both sit in a state that
/// cannot reach `preflight` in one step, so the preflight filled a snapshot for
/// a run that never left `complete` or `unlinked`, the guard at the end never
/// reached `readyToBuild`, and the Build button never came back.
///
/// A developer who then changed the app outside Super Submitter had no way to
/// build the change, so the artifact the app still held was the one before it.
@Suite struct BuildAgainTests {

    @Test func aFinishedRunGoesBackToThePreflight() {
        var run = UploadRun(platform: .ios)
        // The whole journey of one upload.
        for state in [UploadState.discovering, .preflight, .readyToBuild, .building,
                      .inspectingArtifact, .needsUploadConfirmation, .uploading,
                      .processingOrValidating, .complete] {
            let moved = run.move(to: state)
            #expect(moved, "a run could not reach \(state)")
        }
        #expect(run.state == .complete)

        let restarted = run.moveToPreflight()
        #expect(restarted)
        #expect(run.state == .preflight)
        let ready = run.move(to: .readyToBuild)
        #expect(ready)
    }

    /// The state a fresh launch and a link restored from disk both sit in. It
    /// reaches the preflight only through `discovering`, which is the step the
    /// old call skipped.
    @Test func anUnlinkedRunReachesThePreflightThroughDiscovering() {
        var run = UploadRun(platform: .ios)
        #expect(run.state == .unlinked)
        let direct = run.move(to: .preflight)
        #expect(!direct, "the one-step move is what used to fail silently")
        #expect(run.state == .unlinked)

        let restarted = run.moveToPreflight()
        #expect(restarted)
        #expect(run.state == .preflight)
    }

    @Test func everyStateARunStopsInCanStartTheNextBuild() {
        for state in [UploadState.complete, .cancelled, .failed, .needsSelection,
                      .readyToBuild, .needsUploadConfirmation, .unlinked] {
            var run = UploadRun(platform: .ios, state: state)
            let restarted = run.moveToPreflight()
            #expect(restarted, "\(state) could not start the next build")
            #expect(run.state == .preflight)
        }
    }

    /// A build that is running is not a run to throw back to the start.
    @Test func aRunningBuildRefusesToRestart() {
        for state in [UploadState.building, .uploading, .processingOrValidating,
                      .inspectingArtifact, .cancelling] {
            var run = UploadRun(platform: .ios, state: state)
            let restarted = run.moveToPreflight()
            #expect(!restarted, "\(state) restarted itself")
            #expect(run.state == state)
        }
    }
}

/// The other half of the same report: an apply must not send an old artifact
/// without saying that it is old.
@Suite struct ArtifactAgeTests {

    @Test func anUploadRowSaysHowOldTheArtifactIs() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-age-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("app.ipa")
        try Data("bytes".utf8).write(to: file)

        let built = try #require(file.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)

        #expect(Planner.builtText(file, now: built) == "built just now")
        #expect(Planner.builtText(file, now: built.addingTimeInterval(60)) == "built 1 minute ago")
        #expect(Planner.builtText(file, now: built.addingTimeInterval(45 * 60))
                == "built 45 minutes ago")
        #expect(Planner.builtText(file, now: built.addingTimeInterval(3 * 3_600))
                == "built 3 hours ago")
        #expect(Planner.builtText(file, now: built.addingTimeInterval(24 * 3_600))
                == "built 1 day ago")
        // The one the report is about: an artifact from before the change the
        // developer just made somewhere else.
        #expect(Planner.builtText(file, now: built.addingTimeInterval(9 * 24 * 3_600))
                == "built 9 days ago")

        // A row that cannot read the date still names the file and the size.
        let summary = Planner.artifactSummary(file, bytes: 5, prefix: "build ")
        #expect(summary.hasPrefix("build app.ipa"))
        #expect(summary.contains("built"))
    }
}

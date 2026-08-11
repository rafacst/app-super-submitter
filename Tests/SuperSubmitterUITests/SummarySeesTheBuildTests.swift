import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The Summary, after a build reaches the store.
///
/// The bug this guards: an upload landed and the Summary said nothing had. The
/// runway step read "no artifact named" and the blocker described the store as
/// it stood at the last read, which was before the build existed. Two separate
/// causes, one symptom, and both are here.
@MainActor
struct SummarySeesTheBuildTests {

    private func state(_ build: (inout ActualState.Apple) -> Void) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        var apple = ActualState.Apple()
        build(&apple)
        var actual = ActualState()
        actual.apple = apple
        state.actualState = actual
        return state
    }

    // MARK: - The runway step

    /// The reported case. An Apple build names no file on purpose, so the step
    /// read the manifest, found nothing, and said so beside a build the store
    /// was already holding.
    @Test func anUploadedBuildIsNamedInsteadOfNothing() {
        let state = state {
            $0.buildIdForVersion = "42"
            $0.highestBuildNumber = 215
        }

        #expect(RunwayStep.build(state) == "build 215 uploaded, not attached")
    }

    @Test func anAttachedBuildSaysSo() {
        let state = state {
            $0.buildIdForVersion = "42"
            $0.attachedBuildId = "42"
            $0.highestBuildNumber = 215
        }

        #expect(RunwayStep.build(state) == "build 215 attached")
    }

    /// A version may hold an older build than the newest one on the store. The
    /// highest number is then somebody else's, and printing it beside
    /// "attached" would name the wrong build.
    @Test func anOlderAttachedBuildIsNotGivenTheNewestNumber() {
        let state = state {
            $0.buildIdForVersion = "215"
            $0.attachedBuildId = "210"
            $0.highestBuildNumber = 215
        }

        #expect(RunwayStep.build(state) == "a build attached")
    }

    /// The build is the answer and the number is the detail. A store that holds
    /// one and cannot name it still beats "no artifact named".
    @Test func aBuildWithNoNumberIsStillABuild() {
        let state = state { $0.buildIdForVersion = "42" }

        #expect(RunwayStep.build(state) == "a build uploaded, not attached")
    }

    /// Unchanged where it was already right: nothing named and nothing in the
    /// store is still nothing.
    @Test func anEmptyStoreAndAnEmptyManifestStillSayNothingIsNamed() {
        let state = state { _ in }

        #expect(RunwayStep.build(state) == "no artifact named")
    }

    /// Android names its file, because the `.aab` on this Mac is the exact one
    /// the apply uploads. That answer wins: it is about this run, and the
    /// store's build is about the last one.
    @Test func anAndroidArtifactStillReportsTheFile() throws {
        let state = state { $0.buildIdForVersion = "42" }
        var release = Manifest.Release()
        release.build = Manifest.Release.Build(android: "/nowhere/app.aab")
        state.manifest.release = release

        #expect(RunwayStep.build(state).contains("artifact"))
    }

    // MARK: - The plan goes stale the moment a build lands

    /// Every path that leaves a build on a store has to say so, or the Summary
    /// keeps a plan that was read before the build existed. Only **Continue to
    /// Summary** used to call it, and reaching the Summary from the sidebar is
    /// the ordinary way to get there.
    @Test func everyUploadThatLandsInvalidatesThePlan() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/SuperSubmitter/Build/BuildFlowRun.swift"),
            encoding: .utf8)

        // Four mentions: the declaration, and the three paths that leave a
        // build on a store. Apple's, once Apple has finished processing it;
        // Google's; and Google's again when a cancel arrived too late to undo
        // the upload.
        let mentions = source.components(separatedBy: "storeGainedABuild()").count - 1
        #expect(mentions >= 4, "an upload path lands a build without invalidating the plan")
        #expect(source.contains("app?.invalidatePlan()"))
    }
}

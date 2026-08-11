import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A run's result is an answer about the manifest that produced it.
///
/// The bug this guards: an apply that failed on a version number left the
/// Summary tab stuck. A failure is not `runDone`, so `showsRun` stayed true and
/// the failure panel covered the tab; `readStores` refuses to run while a run
/// is unfinished, so no fresh plan could arrive behind it; and `startRun` needs
/// a plan, which the edit had just thrown away, so Retry did nothing. The
/// developer changed the very number the failure named and was shown the same
/// sentence about the old one, with no way forward on the tab.
@Suite(.serialized)
@MainActor
struct StaleRunTests {

    private func state() -> AppState {
        AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                 storeAccount: "test-\(UUID().uuidString)")
    }

    @Test func anEditClearsAFailedRun() {
        let state = state()
        state.runIndex = 2
        state.runFailure = RunFailure(stepIndex: 2, system: .apple,
                                      message: "Version 1.0.4 is not above 1.0.4.")

        state.invalidatePlan()

        #expect(!state.showsRun, "the failed run was still covering the tab")
        #expect(state.runFailure == nil)
    }

    @Test func anEditClearsAFinishedRun() {
        let state = state()
        state.runIndex = 3
        state.runDone = true

        state.invalidatePlan()

        #expect(!state.showsRun)
        #expect(!state.runDone)
    }

    /// The one it must never do. A manifest write during a run must not clear
    /// the screen the run is reporting on.
    @Test func anEditDuringARunLeavesItAlone() {
        let state = state()
        state.runIndex = 1

        #expect(state.isRunning)
        state.invalidatePlan()

        #expect(state.showsRun)
        #expect(state.runIndex == 1)
    }

    /// What the stuck tab actually cost: the read that would have produced a
    /// fresh plan refuses to run while a run is unfinished.
    @Test func aClearedRunLetsTheNextReadThrough() {
        let state = state()
        state.runIndex = 2
        state.runFailure = RunFailure(stepIndex: 2, system: .apple,
                                      message: "Version 1.0.4 is not above 1.0.4.")
        #expect(state.showsRun && !state.runDone, "the guard readStores stops at")

        state.invalidatePlan()

        #expect(!state.showsRun || state.runDone)
    }
}

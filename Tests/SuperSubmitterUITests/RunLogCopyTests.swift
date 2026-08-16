import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// "Copy the log" put unusable text on the pasteboard.
///
/// Three things were wrong at once, and this holds the two that live in the
/// app: the copy took the lines the box drew, which are cut to its width, and
/// the run kept only the last 500 calls, so a long run could not be copied
/// whole. The third, the dropped query string, is `RunLogTests` in the kit.
@MainActor
@Suite struct RunLogCopyTests {

    private func state() -> AppState {
        AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                 storeAccount: "test-\(UUID().uuidString)")
    }

    private func call(_ index: Int) -> APICall {
        APICall(system: "apple", method: "GET",
                path: "/v2/appAvailabilities/6790568884/territoryAvailabilities"
                    + "?limit=200&include=territory&page=\(index)",
                status: 200, durationMs: 12)
    }

    /// The box keeps its cap and the pasteboard does not.
    @Test func aRunOfMoreThanFiveHundredCallsCopiesEveryOne() {
        let state = state()
        let date = Date()
        for index in 1...640 { state.record(call(index), at: date) }

        #expect(state.logLines.count == 500)
        let copied = state.logText.split(separator: "\n")
        #expect(copied.count == 640)
        // The first calls of a run are where a failure usually starts, and they
        // were the ones the cap dropped.
        #expect(copied.first?.contains("page=1") == true)
        #expect(copied.last?.contains("page=640") == true)
    }

    /// Whole paths, whole query strings, and no ellipsis anywhere.
    @Test func theCopiedTextHoldsThePathAndTheQueryInFull() {
        let state = state()
        state.record(call(1), at: Date())

        #expect(state.logText.contains(
            "/v2/appAvailabilities/6790568884/territoryAvailabilities"))
        #expect(state.logText.contains("limit=200&include=territory"))
        #expect(!state.logText.contains("…"))
        // And the box still draws the line that fits it.
        #expect(state.logLines.first?.contains("…") == true)
    }

    /// A new run starts with an empty log and no file behind it.
    @Test func theLogAndItsFileGoWithTheRunThatMadeThem() {
        let state = state()
        state.logFileURL = URL(fileURLWithPath: "/tmp/runs/one.jsonl")
        state.record(call(1), at: Date())

        state.clearRunLog()

        #expect(state.logLines.isEmpty)
        #expect(state.logText.isEmpty)
        #expect(state.loggedCalls == 0)
        #expect(state.logFileURL == nil)
    }

    /// The copy has a cap now, and it stops growing at it.
    ///
    /// `logText` joins the whole array, and the log box reads it as an
    /// argument, so an uncapped array made a run pay for its own length on
    /// every redraw of a panel that is on screen for the length of the run.
    @Test func theCopyStopsGrowingAtTheCap() {
        let state = state()
        let date = Date()
        let over = AppState.logLimit + 300

        for index in 1...over { state.record(call(index), at: date) }

        #expect(state.logFullLines.count == AppState.logLimit)
        // The tail is kept, so the calls around a failure at the end are there.
        #expect(state.logFullLines.last?.contains("page=\(over)") == true)
    }

    /// A truncated copy says it is one. A tail pasted into a ticket as though
    /// it were the whole run hides every call before it.
    @Test func aTruncatedCopySaysWhatIsMissingAndWhereToFindIt() {
        let state = state()
        let date = Date()
        let over = AppState.logLimit + 300

        for index in 1...over { state.record(call(index), at: date) }

        #expect(state.loggedCalls == over)
        #expect(state.logText.hasPrefix("300 earlier calls are not in this copy."))
        #expect(state.logText.contains("log file"))
    }

    /// And a run that stays under the cap says nothing, because nothing is
    /// missing. The 640 call run above copies whole and unannotated.
    @Test func aWholeCopyCarriesNoNotice() {
        let state = state()
        for index in 1...640 { state.record(call(index), at: Date()) }

        #expect(!state.logText.contains("earlier calls"))
        #expect(state.logText.split(separator: "\n").count == 640)
    }
}

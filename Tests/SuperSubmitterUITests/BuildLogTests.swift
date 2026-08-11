import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The window froze after Build Archive and then Show log.
///
/// `xcodebuild` prints several hundred lines a second, and every line was
/// appended straight to an observed array. SwiftUI invalidated the log box that
/// many times a second, each redraw joined the whole log into one string, and a
/// single selectable `Text` laid out all two thousand lines to draw the fifteen
/// the box is tall. The main thread never got a frame in.
///
/// The lines now land in a buffer nothing observes, and a flush publishes them
/// ten times a second. This holds that shape: a burst of output costs one
/// redraw, not one per line.
@Suite(.serialized)
@MainActor
struct BuildLogTests {
    /// No `AppState`. The flow holds it weakly and the log path never asks it
    /// anything, and building one reads the Keychain and the user defaults.
    private func flow() -> BuildFlow { BuildFlow(app: nil) }

    /// Waits for the flush rather than assuming it lands inside a fixed sleep.
    ///
    /// The flush is a tenth of a second, and a sleep of a quarter passed alone
    /// and failed beside the other 600 tests: they hold the main actor, and the
    /// flush waits its turn. The deadline is five seconds, which a stuck flush
    /// still reaches and a busy one never does.
    private func flushed(_ done: () -> Bool) async {
        for _ in 0..<200 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test func aBurstOfOutputDoesNotRedrawPerLine() async throws {
        let flow = flow()

        for index in 1...500 { flow.append("line \(index)") }

        // Nothing the view reads has changed yet, so the burst cost no redraw.
        #expect(flow.logLines.isEmpty)
        #expect(flow.logBuffer.count == 500)

        // The flush that was scheduled by the first line publishes all of them.
        await flushed { flow.logLines.count == 500 }
        #expect(flow.logLines.count == 500)
        #expect(flow.logLines.last == "line 500")
    }

    /// The end of a run needs no flush of its own. The last line leaves one
    /// scheduled, and it fires.
    @Test func theLastLineOfARunStillReachesTheBox() async throws {
        let flow = flow()
        flow.append("** ARCHIVE SUCCEEDED **")
        await flushed { !flow.logLines.isEmpty }
        #expect(flow.logLines == ["** ARCHIVE SUCCEEDED **"])
    }

    /// A log has to stop growing somewhere, and the end is the half that says
    /// what went wrong.
    @Test func theBufferKeepsTheEndAndDropsTheHead() async throws {
        let flow = flow()
        for index in 1...(BuildFlow.logLimit + 250) { flow.append("line \(index)") }

        #expect(flow.logBuffer.count == BuildFlow.logLimit)
        #expect(flow.logBuffer.last == "line \(BuildFlow.logLimit + 250)")
        #expect(flow.logBuffer.first == "line 251")
    }

    /// Without the cancel, the flush scheduled by the last line of the previous
    /// run republishes that run's log a tenth of a second into this one.
    @Test func aNewRunDoesNotInheritTheLastOnesLog() async throws {
        let flow = flow()
        flow.append("the previous run")
        flow.clearLog()

        #expect(flow.logLines.isEmpty)
        #expect(flow.logBuffer.isEmpty)
        #expect(flow.logFlush == nil, "a flush is still holding the old log")

        try await Task.sleep(for: .milliseconds(250))
        #expect(flow.logLines.isEmpty, "a cancelled flush came back")
        #expect(flow.logText.isEmpty)
    }

    /// A failure is the one moment worth a hundred milliseconds.
    ///
    /// The panel appears in the same frame and tells the developer to read the
    /// log, so the log may not be a tenth of a second behind it. The scheduled
    /// flush covers the end of a run that is only printing; it does not cover
    /// the frame a panel arrives in.
    @Test func aFailureFlushesTheLogInTheSameFrame() {
        let flow = flow()
        flow.append("error: no such module 'Foo'")
        #expect(flow.logLines.isEmpty, "the flush is still a tenth of a second away")

        flow.flushLog()

        #expect(flow.logLines == ["error: no such module 'Foo'"])
        #expect(flow.logFlush == nil, "the scheduled flush was left to fire again")
    }

    /// The panel says "read the diagnostics and the build log". The log is on
    /// the screen when the panel arrives, and not behind Show log.
    @Test func aFailureOpensTheLogItTellsTheDeveloperToRead() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Build/BuildFlowRun.swift"),
            encoding: .utf8)
        let start = try #require(source.range(of: "func fail(_ value: BuildFailure)"))
        let end = try #require(source.range(of: "func retry()"))
        let fail = String(source[start.lowerBound..<end.lowerBound])

        #expect(fail.contains("flushLog()"))
        #expect(fail.contains("logOpen = true"))
        // An empty log box under "read the log" is worse than no box.
        #expect(fail.contains("!logLines.isEmpty"))
    }

    /// The box draws the tail. Copy has to give every line the run printed.
    @Test func theCopiedLogIsTheWholeRunAndNotTheTail() async throws {
        let flow = flow()
        for index in 1...300 { flow.append("line \(index)") }
        #expect(flow.logText.hasPrefix("line 1\n"))
        #expect(flow.logText.hasSuffix("line 300"))
    }
}

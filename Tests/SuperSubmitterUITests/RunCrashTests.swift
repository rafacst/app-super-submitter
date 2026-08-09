import Foundation
import Testing

private let runCrashRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func runSource(_ path: String) throws -> String {
    try String(contentsOf: runCrashRoot.appendingPathComponent(path), encoding: .utf8)
}

@Test func replacingAPlanDismissesStaleRunRowsBeforeTheyRender() throws {
    let state = try runSource("Sources/SuperSubmitter/AppStateRun.swift")
    let view = try runSource("Sources/SuperSubmitter/Tabs/RunSection.swift")

    #expect(state.contains("guard !planReading, !showsRun || runDone else { return }"))
    #expect(state.contains("runTask?.cancel()\n        runTask = nil"))
    #expect(state.contains("runner = nil\n        runIndex = -1"))
    #expect(view.contains("if let step = state.runSteps[safe: index]"))
    #expect(!view.contains("let step = state.runSteps[index]"))
}

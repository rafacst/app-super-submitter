import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The Build tab now answers the question the Summary tab used to answer three
/// tabs later: is the file this path names actually there?
///
/// The check has to agree with `Validator.build`, so both call
/// `Planner.resolve`. A second rule here would drift and the field would say
/// one thing while the plan said another.
@MainActor
@Test func aPathFieldReportsAFileThatIsNotThere() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("path-note-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let mapping = folder.appendingPathComponent("mapping.txt")
    try Data("obfuscated".utf8).write(to: mapping)
    let url = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(Manifest(), to: url)

    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "path-note-\(UUID().uuidString)")
    try state.load(from: url)

    // An empty box is not a fault. Nobody has answered yet.
    #expect(state.missingFileNote(for: "") == nil)
    #expect(state.missingFileNote(for: "   ") == nil)
    #expect(state.missingFileNote(for: "mapping.txt") == nil)
    #expect(state.missingFileNote(for: "build/gone.txt") != nil)
    #expect(state.missingFileNote(for: "/nowhere/gone.txt") != nil)
}

/// A build named by an earlier session and since moved. The well used to draw
/// itself empty and healthy, because it only ever showed a package that a drop
/// had read during this session.
@MainActor
@Test func aBuildTheManifestNamesButNoLongerHasIsReportedOnTheWell() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("build-note-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let aab = folder.appendingPathComponent("app.aab")
    try Data("bundle".utf8).write(to: aab)
    let url = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(Manifest(), to: url)

    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "build-note-\(UUID().uuidString)")
    try state.load(from: url)

    state.manifest.release = Manifest.Release(
        build: Manifest.Release.Build(ios: "build/FastBillSplit.ipa", android: "app.aab"))

    #expect(state.missingBuildNote(.aab) == nil)
    let note = try #require(state.missingBuildNote(.ipa))
    #expect(note.contains("build/FastBillSplit.ipa"))
    // Nothing named, nothing to report.
    #expect(state.missingBuildNote(.pkg) == nil)
}

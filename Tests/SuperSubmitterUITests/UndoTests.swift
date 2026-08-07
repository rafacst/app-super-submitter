import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The undo stack, and the one thing that is easy to get wrong about it.
///
/// The baseline has to advance on a coalesced keystroke as well as on a
/// registered one. If it only advanced when a step was filed, the step after a
/// burst would restore the state from the middle of the burst rather than the
/// state at its end.
@MainActor
private func makeState() throws -> (AppState, URL) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("undo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(Manifest(), to: url)
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "undo-test-\(UUID().uuidString)")
    try state.load(from: url)
    state.manifest.addLocale("en-US")
    state.locale = "en-US"
    state.saveManifestReportingErrors()
    return (state, folder)
}

@MainActor
@Test func anEditGoesBackAndThenForward() throws {
    let (state, folder) = try makeState()
    defer { try? FileManager.default.removeItem(at: folder) }

    let name = state.listingBinding(.name)
    name.wrappedValue = "First"
    #expect(state.canUndoEdit)

    state.undoEdit()
    #expect(name.wrappedValue == "")
    #expect(state.canRedoEdit)

    state.redoEdit()
    #expect(name.wrappedValue == "First")
    // The file follows the stack, not just the field.
    let onDisk = try ManifestFile.load(from: state.manifestURL!)
    #expect(onDisk.listing?.locales["en-US"]?.name == "First")
}

@MainActor
@Test func aBurstOfKeystrokesIsOneStep() throws {
    let (state, folder) = try makeState()
    defer { try? FileManager.default.removeItem(at: folder) }

    let name = state.listingBinding(.name)
    for text in ["F", "Fa", "Fas", "Fast"] { name.wrappedValue = text }

    state.undoEdit()
    #expect(name.wrappedValue == "")
    #expect(!state.canUndoEdit)
}

/// The regression the baseline advance prevents. The second burst must go back
/// to the end of the first one, not into the middle of it.
@MainActor
@Test func theStepAfterABurstGoesBackToTheEndOfIt() throws {
    let (state, folder) = try makeState()
    defer { try? FileManager.default.removeItem(at: folder) }

    let name = state.listingBinding(.name)
    for text in ["F", "Fa", "Fast"] { name.wrappedValue = text }

    // A pause longer than the coalesce window opens the next step.
    state.lastUndoRegistration = Date(timeIntervalSinceNow: -5)
    name.wrappedValue = "Fast Bill Split"

    state.undoEdit()
    #expect(name.wrappedValue == "Fast")
    state.undoEdit()
    #expect(name.wrappedValue == "")
}

/// A step holds a whole manifest, so a stack that survived the switch would let
/// one Command-Z write the previous app's listing into this app's file.
@MainActor
@Test func openingAnotherAppClearsTheStack() throws {
    let (state, folder) = try makeState()
    defer { try? FileManager.default.removeItem(at: folder) }

    state.listingBinding(.name).wrappedValue = "First"
    #expect(state.canUndoEdit)

    let second = folder.appendingPathComponent("other.yaml")
    try ManifestFile.save(Manifest(), to: second)
    try state.load(from: second)

    #expect(!state.canUndoEdit)
    #expect(!state.canRedoEdit)
}

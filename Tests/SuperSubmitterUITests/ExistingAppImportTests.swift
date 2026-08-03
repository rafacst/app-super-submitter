import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

@Test func existingAppSelectionSupportsMultipleStoresAndMultipleApps() {
    let first = ExistingAppCandidate(store: .apple, remoteID: "1",
                                     name: "Alpha", identifier: "com.example.alpha")
    let second = ExistingAppCandidate(store: .apple, remoteID: "2",
                                      name: "Beta", identifier: "com.example.beta")
    let google = ExistingAppCandidate(store: .google, remoteID: "com.example.alpha",
                                      name: "com.example.alpha",
                                      identifier: "com.example.alpha")
    var selection = ExistingAppSelection()

    selection.toggle(first)
    selection.toggle(second)
    selection.toggle(google)

    #expect(selection.contains(first))
    #expect(selection.contains(second))
    #expect(selection.contains(google))
    #expect(selection.count == 3)
}

@Test func matchingAppleAndGoogleAppsImportIntoOneWorkspace() {
    let apple = ExistingAppCandidate(store: .apple, remoteID: "123",
                                     name: "Example", identifier: "com.example.app")
    let google = ExistingAppCandidate(store: .google, remoteID: "com.example.app",
                                      name: "com.example.app", identifier: "com.example.app")
    let other = ExistingAppCandidate(store: .apple, remoteID: "456",
                                     name: "Other / App", identifier: "com.example.other")

    let groups = ExistingAppImportPlan.group([apple, google, other])

    #expect(groups.count == 2)
    #expect(groups.first { $0.identifier == "com.example.app" }?.candidates.count == 2)
    #expect(groups.first { $0.identifier == "com.example.other" }?.folderName == "Other App")
}

@Test func emptyAndDuplicateCandidatesDoNotCreateDuplicateImports() {
    let app = ExistingAppCandidate(store: .apple, remoteID: "123",
                                   name: "Example", identifier: "com.example.app")
    let duplicate = ExistingAppCandidate(store: .apple, remoteID: "123",
                                         name: "Example", identifier: "com.example.app")

    #expect(ExistingAppImportPlan.group([]).isEmpty)
    #expect(ExistingAppImportPlan.group([app, duplicate]).first?.candidates.count == 1)
}

/// The picker draws one block per store, the App Store first, so a mixed
/// account never interleaves the two.
@MainActor
@Test func theAppleAppsListBeforeTheGoogleApps() {
    let model = ExistingAppImportModel()
    model.candidates = [
        ExistingAppCandidate(store: .google, remoteID: "com.example.b", name: "Beta",
                             identifier: "com.example.b"),
        ExistingAppCandidate(store: .apple, remoteID: "1", name: "Alpha",
                             identifier: "com.example.a"),
    ]

    #expect(model.candidates(for: .apple).map(\.name) == ["Alpha"])
    #expect(model.candidates(for: .google).map(\.name) == ["Beta"])
}

/// One selected app writes into the folder the user picks. Two need a parent.
@MainActor
@Test func oneSelectedAppNamesTheFolderAndTwoDoNot() {
    let model = ExistingAppImportModel()
    let alpha = ExistingAppCandidate(store: .apple, remoteID: "1", name: "Alpha",
                                     identifier: "com.example.a")
    let alphaGoogle = ExistingAppCandidate(store: .google, remoteID: "com.example.a",
                                           name: "Alpha", identifier: "com.example.a")
    let beta = ExistingAppCandidate(store: .apple, remoteID: "2", name: "Beta",
                                    identifier: "com.example.b")
    model.candidates = [alpha, alphaGoogle, beta]

    model.selection.toggle(alpha)
    model.selection.toggle(alphaGoogle)
    // Both stores of one app are still one app, and one folder.
    #expect(model.selectedGroupCount == 1)
    #expect(model.selectedGroupName == "Alpha")

    model.selection.toggle(beta)
    #expect(model.selectedGroupCount == 2)
    #expect(model.selectedGroupName == nil)
}

/// Dropping the .p8 fills the key id, and never overwrites a typed one.
@MainActor
@Test func droppingTheP8FillsTheKeyIDOnlyWhenItIsEmpty() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("p8-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let key = folder.appendingPathComponent("AuthKey_Z2YFP2FP9D.p8")
    try "-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----".write(
        to: key, atomically: true, encoding: .utf8)

    let model = ExistingAppImportModel()
    try model.importAppleKey(key)
    #expect(model.appleKeyID == "Z2YFP2FP9D")

    model.appleKeyID = "TYPEDBYUSR"
    try model.importAppleKey(key)
    #expect(model.appleKeyID == "TYPEDBYUSR")
}

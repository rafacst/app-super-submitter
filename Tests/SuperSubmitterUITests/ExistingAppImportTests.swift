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

/// Writes two workspaces and links both into a state with its own Keychain
/// account, so a test run never reads or writes the real key.
@MainActor
private func stateWithTwoApps(storeAccount: String) throws -> (AppState, [URL]) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("import-\(UUID().uuidString)")
    var urls: [URL] = []
    for name in ["Alpha", "Beta"] {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.\(name.lowercased())")
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        try ManifestFile.save(manifest, to: url)
        urls.append(url)
    }
    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: storeAccount)
    for url in urls { state.link(manifestAt: url) }
    return (state, urls)
}

private let sampleKey = AppleCredential(keyID: "Z2YFP2FP9D", issuerID: "issuer",
                                        privateKeyPEM: "pem",
                                        fileName: "AuthKey_Z2YFP2FP9D.p8")

/// One App Store Connect key covers the whole team, so a second app reads the
/// key the first app saved and no tab asks for the .p8 again.
@MainActor
@Test func everyLinkedAppReadsTheOneStoreCredential() throws {
    let account = "test-\(UUID().uuidString)"
    defer { try? KeychainCredentials.delete(kind: .apple, account: account) }
    let (state, urls) = try stateWithTwoApps(storeAccount: account)
    // Nothing is saved yet, which is what the user saw on the tab.
    #expect(state.appleCredentialFileName.isEmpty)

    try KeychainCredentials.save(sampleKey, kind: .apple, account: account)
    state.link(manifestAt: urls[0])

    #expect(state.appleKeyID == "Z2YFP2FP9D")
    #expect(state.appleIssuerID == "issuer")
    #expect(state.appleCredentialFileName == "AuthKey_Z2YFP2FP9D.p8")
}

/// A key an earlier version saved under one app is adopted, because Apple
/// offers the .p8 file once and a lost key cannot be downloaded again.
@MainActor
@Test func aKeySavedUnderOneAppIsAdopted() throws {
    let account = "test-\(UUID().uuidString)"
    defer { try? KeychainCredentials.delete(kind: .apple, account: account) }
    let (state, urls) = try stateWithTwoApps(storeAccount: account)
    let own = try #require(state.credentialAccount)
    defer { try? KeychainCredentials.delete(kind: .apple, account: own) }

    try KeychainCredentials.save(sampleKey, kind: .apple, account: own)
    state.link(manifestAt: urls[1])
    #expect(state.appleKeyID == "Z2YFP2FP9D")

    // It moved to the shared account, so the other app reads it too.
    let shared = try KeychainCredentials.load(AppleCredential.self, kind: .apple,
                                              account: account)
    #expect(shared == sampleKey)
}

/// Managing has no repository to sit beside, so the import asks for no folder
/// and Super Submitter keeps the workspace itself.
@MainActor
@Test func theManagedWorkspaceLivesInsideTheApp() throws {
    let storage = BuildStorage(root: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("managed-\(UUID().uuidString)"))

    let folder = try storage.managedFolder(name: "Stamp Hunt",
                                           identifier: "com.rafacst.stamphunt")

    #expect(FileManager.default.fileExists(atPath: folder.path))
    #expect(folder.path.contains("Managed"))
    // Two apps that share a display name keep their own folders.
    let other = try storage.managedFolder(name: "Stamp Hunt",
                                          identifier: "com.rafacst.stamphunt.brasil")
    #expect(folder != other)
}

/// A missing icon and a failed icon read used to look the same on screen.
@Test func theIconReadNamesWhyItFoundNothing() {
    var withoutBuild = StoreConnectionClient.AppleIcons()
    withoutBuild.withoutBuild = ["1", "2"]
    #expect(withoutBuild.explanation?.contains("carry no build") == true)

    var failed = StoreConnectionClient.AppleIcons()
    failed.failures = ["1: the request failed"]
    #expect(failed.explanation?.contains("could not be read") == true)

    var processing = StoreConnectionClient.AppleIcons()
    processing.withoutIcon = ["1"]
    #expect(processing.explanation?.contains("finishes processing") == true)

    // A read that found icons explains nothing, because there is nothing to
    // explain.
    var found = StoreConnectionClient.AppleIcons()
    found.urls = ["1": URL(string: "https://example.com/icon.png")!]
    #expect(found.explanation == nil)
}

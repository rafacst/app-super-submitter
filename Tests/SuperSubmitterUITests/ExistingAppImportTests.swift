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

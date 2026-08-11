import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// An identifier the store can answer is not a question for the developer.
///
/// Both stores hold the identifiers this app needs, and both can be asked for
/// them: App Store Connect lists every app a key can see, and the Play
/// Developer Reporting API lists every app a service account can see. The app
/// asked Apple on connect and never asked Google at all, so the package name
/// was a required field with no way in but memory.
///
/// The rule the fill follows: one visible app is a fact and goes straight into
/// the field, several are a choice and the picker makes it, and anything
/// already in the field is a decision that a read may not undo.
@MainActor
struct IdentifierFetchTests {

    private func state() -> AppState {
        AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                 storeAccount: "test-\(UUID().uuidString)")
    }

    private func apps(_ count: Int, prefix: String) -> [RemoteStoreApp] {
        (0..<count).map {
            RemoteStoreApp(id: "\(prefix)-id-\($0)", name: "\(prefix) \($0)",
                           identifier: "com.example.\(prefix)\($0)")
        }
    }

    @Test func oneVisibleAppFillsTheFieldWithoutAsking() {
        let state = state()
        state.setStore(.apple, enabled: true)
        state.setStore(.google, enabled: true)

        state.remoteAppleApps = apps(1, prefix: "apple")
        state.adoptTheOnlyVisibleApp(.apple)
        #expect(state.appleAppID == "apple-id-0")
        #expect(state.appleBundleID == "com.example.apple0")

        state.remoteGoogleApps = apps(1, prefix: "google")
        state.adoptTheOnlyVisibleApp(.google)
        #expect(state.googlePackageName == "com.example.google0")
    }

    @Test func severalVisibleAppsAreAChoiceAndNothingIsGuessed() {
        let state = state()
        state.setStore(.apple, enabled: true)
        state.setStore(.google, enabled: true)

        state.remoteAppleApps = apps(3, prefix: "apple")
        state.adoptTheOnlyVisibleApp(.apple)
        #expect(state.appleAppID.isEmpty)
        #expect(state.appleBundleID.isEmpty)

        state.remoteGoogleApps = apps(3, prefix: "google")
        state.adoptTheOnlyVisibleApp(.google)
        #expect(state.googlePackageName.isEmpty)

        // The picker still fills them, which is the whole point of the list.
        state.chooseRemoteGoogleApp(state.remoteGoogleApps[1])
        #expect(state.googlePackageName == "com.example.google1")
    }

    /// A typed identifier is a decision. A read is not grounds to undo it.
    @Test func aValueAlreadyOnScreenIsNeverOverwritten() {
        let state = state()
        state.setStore(.apple, enabled: true)
        state.setStore(.google, enabled: true)
        state.appleBundleID = "com.example.typed"
        state.googlePackageName = "com.example.typed"

        state.remoteAppleApps = apps(1, prefix: "apple")
        state.remoteGoogleApps = apps(1, prefix: "google")
        state.adoptTheOnlyVisibleApp(.apple)
        state.adoptTheOnlyVisibleApp(.google)

        #expect(state.appleBundleID == "com.example.typed")
        #expect(state.googlePackageName == "com.example.typed")
    }

    /// Nothing visible is the first-submission case, and it fills nothing.
    @Test func noVisibleAppLeavesTheFieldsAlone() {
        let state = state()
        state.setStore(.apple, enabled: true)
        state.setStore(.google, enabled: true)

        state.adoptTheOnlyVisibleApp(.apple)
        state.adoptTheOnlyVisibleApp(.google)

        #expect(state.appleAppID.isEmpty)
        #expect(state.appleBundleID.isEmpty)
        #expect(state.googlePackageName.isEmpty)
        // And that is exactly when the panel has to say who assigns them.
        #expect(state.showsNewAppFields)
    }
}

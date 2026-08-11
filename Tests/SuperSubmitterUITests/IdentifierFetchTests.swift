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

    // MARK: - What a shipped app may no longer change

    /// The store assigned it and holds every install, review and purchase
    /// against it. Neither store publishes a call that changes one, so a box
    /// that took characters was offering a change that reaches nothing.
    @Test func aShippedAppKeepsTheIdentifiersItsStoreAssigned() {
        let state = state()
        state.setStore(.apple, enabled: true)
        state.setStore(.google, enabled: true)

        // Nobody has read either store. A box held shut here would be a
        // developer who cannot type the id that lets the app ask.
        #expect(!state.storeFixedTheIdentifiers(.apple))
        #expect(!state.storeFixedTheIdentifiers(.google))

        var apple = ActualState.Apple()
        apple.liveVersionString = "1.4"
        state.actualState.apple = apple

        #expect(state.storeFixedTheIdentifiers(.apple))
        // Per store. An app that is out on one and unwritten on the other is
        // a first submission on the other, and that submission needs the box.
        #expect(!state.storeFixedTheIdentifiers(.google))
    }

    /// A production release with a build in it is an app the public installs.
    /// A draft release is not, and nor is a build that only testers have.
    @Test func playFixesThePackageNameOnceThePublicCanInstallIt() {
        let state = state()
        state.setStore(.google, enabled: true)
        var google = ActualState.Google()

        var draft = ActualState.Google.Track()
        draft.versionCodes = [8]
        draft.status = "draft"
        google.tracks = ["production": draft]
        state.actualState.google = google
        #expect(!state.storeFixedTheIdentifiers(.google))

        var live = ActualState.Google.Track()
        live.versionCodes = [8]
        live.status = "completed"
        google.tracks = ["production": live]
        state.actualState.google = google
        #expect(state.storeFixedTheIdentifiers(.google))
    }

    /// Both screens that draw these boxes have to obey the same rule, and the
    /// picker beside them goes with them: choosing another app rewrites the
    /// very identifiers the store refuses to change.
    @Test func bothScreensLockTheBoxesAndThePickerWithThem() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        for path in ["Sources/SuperSubmitter/Tabs/AppIdentifiers.swift",
                     "Sources/SuperSubmitter/Tabs/BuildTab.swift"] {
            let source = try String(contentsOf: root.appending(path: path), encoding: .utf8)
            #expect(source.contains("storeFixedTheIdentifiers(.apple)"), "\(path)")
            #expect(source.contains("storeFixedTheIdentifiers(.google)"), "\(path)")
            #expect(source.contains("locked"), "\(path)")
            #expect(source.contains("!fixed"), "\(path)")
        }
    }
}

/// The version the developer types goes to the store whose box it is, and the
/// tick hands one number to both.
@MainActor
struct VersionPerStoreTests {

    private func state() -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.setStore(.apple, enabled: true)
        state.setStore(.google, enabled: true)
        return state
    }

    @Test func twoStoresGetTwoFieldsAndTheTickJoinsThem() {
        let state = state()
        // Two stores, nothing typed: a field each, which is the honest
        // default. The numbers are independent until the developer says so.
        #expect(state.showsVersionPerStore)
        #expect(!state.sharesOneVersion)

        state.releaseVersionBinding(for: .apple).wrappedValue = "1.4.1"
        state.releaseVersionBinding(for: .google).wrappedValue = "1.0.0"
        #expect(state.manifest.versionName(for: .apple) == "1.4.1")
        #expect(state.manifest.versionName(for: .google) == "1.0.0")

        // One release across both stores takes the App Store's number, which
        // is the one a customer sees first.
        state.sharesOneVersion = true
        #expect(state.manifest.versionName(for: .google) == "1.4.1")
        #expect(state.manifest.release?.versionName == "1.4.1")

        // And splitting hands each store what it is holding.
        state.sharesOneVersion = false
        #expect(!state.sharesOneVersion)
        #expect(state.manifest.versionName(for: .apple) == "1.4.1")
        #expect(state.manifest.versionName(for: .google) == "1.4.1")
    }

    /// One store is one number. A checkbox offering to share it with nobody is
    /// a control that does nothing.
    @Test func oneStoreDrawsOneField() {
        let state = state()
        state.setStore(.google, enabled: false)
        #expect(!state.showsVersionPerStore)
    }
}

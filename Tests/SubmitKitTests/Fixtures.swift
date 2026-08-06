import Foundation
import Testing
@testable import SubmitKit

/// The manifests, the states, and the two one-line readers that more than one
/// test file wants.
///
/// Each of these used to sit `private` in two or three files at once. A test
/// that changed the shared shape then had to find every copy, and a copy that
/// drifted made two files disagree about what "the example app" is.

// MARK: - The manifests

func appleManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

func googleManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

func bothStores() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

// MARK: - The actual state

func appleState(_ build: (inout ActualState.Apple) -> Void) -> ActualState {
    var apple = ActualState.Apple()
    build(&apple)
    var state = ActualState()
    state.apple = apple
    return state
}

func googleState(_ build: (inout ActualState.Google) -> Void) -> ActualState {
    var google = ActualState.Google()
    build(&google)
    var state = ActualState()
    state.google = google
    return state
}

// MARK: - The plan

// `input` and `findings` stay private per file on purpose. Several files build
// one of each, every version with its own default store set and its own extra
// parameters. A shared name overloads with all of them, and a two-argument call
// then binds to the shared one and quietly asks about the wrong stores.

/// The App Store rows of the plan. Both callers ask about Apple only.
func steps(_ manifest: Manifest, _ actual: ActualState) -> [PlanStep] {
    Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
        .steps(for: .apple)
}

// MARK: - Reading the repository back

func json(_ text: String) -> JSON { JSON(data: Data(text.utf8)) }

/// The checkout root. `#filePath` is `<root>/Tests/SubmitKitTests/Fixtures.swift`,
/// so three parents up is the root itself.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

func source(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

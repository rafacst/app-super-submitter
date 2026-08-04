import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func source(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

// MARK: - The panels reach a tab

@Test func theGoogleActionPanelsAreOnATabAndNotOnlyInTheKit() throws {
    let build = try source("Sources/SuperSubmitter/Tabs/BuildTab.swift")
    let managing = try source("Sources/SuperSubmitter/Tabs/ManagingTabs.swift")

    // An unreachable client is the same as no client. Internal sharing belongs
    // to a build, so it stays on the Build tab; the reviews, the recovery, and
    // the signed APKs belong to a live app, so they moved to Managing.
    #expect(build.contains("InternalSharingPanel()"))
    #expect(build.contains("state.stores.contains(.google)"))
    #expect(managing.contains("GoogleReviewsPanel()"))
    #expect(managing.contains("GoogleRecoveryPanel()"))
    #expect(managing.contains("GeneratedAPKPanel()"))
    // Every one sits behind a store check, so an Apple-only manifest draws
    // none of them.
    #expect(managing.contains("state.stores.contains(.google)"))
}

/// The App Store twins reach a tab too.
@Test func theAppleActionPanelsReachTheSameTabs() throws {
    let managing = try source("Sources/SuperSubmitter/Tabs/ManagingTabs.swift")
    let build = try source("Sources/SuperSubmitter/Tabs/BuildTab.swift")

    #expect(managing.contains("AppStoreActionsPanel()"))
    #expect(managing.contains("VitalsPanel()"))
    #expect(build.contains("XcodeCloudPanel()"))
}

/// Managing writes the marketing resources on one button, so that button asks
/// first. It is the only write in Managing that a publish flow would have
/// shown a diff for.
@Test func theMarketingApplyAsksBeforeItWrites() throws {
    let marketing = try source("Sources/SuperSubmitter/Tabs/MarketingTab.swift")

    #expect(marketing.contains("confirmationDialog(\"Write these to the App Store?\""))
    #expect(marketing.contains("state.applyMarketing()"))
}

@Test func theTwoOutwardFacingActionsAskBeforeTheyRun() throws {
    let panels = try source("Sources/SuperSubmitter/Tabs/GooglePlayPanels.swift")

    // A review reply is public and a recovery deploy reaches real devices.
    // Neither may run straight off a click.
    #expect(panels.contains("confirmationDialog(\"Publish this reply?\""))
    #expect(panels.contains("confirmationDialog(\"Deploy this recovery?\""))
    #expect(panels.contains("role: .destructive"))
}

// MARK: - The artifact that internal sharing uploads

@MainActor
@Test func internalSharingPrefersTheAppBundleOverTheApk() {
    let state = AppState()
    state.manifest.release = Manifest.Release(
        build: Manifest.Release.Build(android: "build/app.aab", androidApk: "build/app.apk"))

    let artifact = state.googleSharableArtifact
    #expect(artifact?.path == "build/app.aab")
    #expect(artifact?.isBundle == true)
}

@MainActor
@Test func internalSharingFallsBackToTheApkAndThenToNothing() {
    let state = AppState()
    #expect(state.googleSharableArtifact == nil)

    state.manifest.release = Manifest.Release(
        build: Manifest.Release.Build(androidApk: "build/app.apk"))
    #expect(state.googleSharableArtifact?.path == "build/app.apk")
    #expect(state.googleSharableArtifact?.isBundle == false)
}

@MainActor
@Test func theActionPackageComesFromTheManifestAndNotFromTheStoresTabField() {
    let state = AppState()
    // The Stores tab field is empty until a connection lands. The manifest is
    // what says which app these calls address.
    state.googlePackageName = "com.example.typed"
    #expect(state.googleActionPackage == nil)

    state.manifest.setGoogleApp(packageName: "com.example.app")
    #expect(state.googleActionPackage == "com.example.app")
}

@MainActor
@Test func everyGoogleActionRefusesWithoutAPackageInsteadOfCallingTheStore() async {
    let state = AppState()

    for call in ["reply", "share", "draft", "deploy", "cancel", "widen"] {
        do {
            switch call {
            case "reply": try await state.replyToGoogleReview(id: "a", text: "Thanks.")
            case "share": _ = try await state.shareGoogleArtifactInternally()
            case "draft": _ = try await state.createGoogleRecoveryDraft()
            case "deploy": try await state.deployGoogleRecovery(id: "1")
            case "cancel": try await state.cancelGoogleRecovery(id: "1")
            default: try await state.widenGoogleRecovery(id: "1")
            }
            Issue.record("\(call) should refuse without a package name.")
        } catch ConnectionError.http(let status, _) {
            #expect(status == 400)
        } catch {
            Issue.record("\(call) failed with the wrong error: \(error)")
        }
    }
}

@MainActor
@Test func theTwoReadsAnswerEmptyWithoutAPackageAndNeverReachTheStore() async throws {
    let state = AppState()
    #expect(try await state.googleReviews().isEmpty)
    #expect(try await state.googleRecoveryActions().isEmpty)
}

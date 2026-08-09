import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let buildReviewRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func buildReviewSource(_ relativePath: String) throws -> String {
    try String(contentsOf: buildReviewRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

@MainActor
private func buildReviewState() -> AppState {
    AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
             storeAccount: "test-\(UUID().uuidString)")
}

// MARK: - The Google column folds

/// A two-store app draws the Apple column beside a Google column that carries
/// tracks, rollout, testers, countries, and six artifact paths. Open, the
/// Google half is several screens long and the Apple half ends in white space.
@Test func theGoogleBuildBlocksFoldAway() throws {
    let section = try buildReviewSource("Sources/SuperSubmitter/Design/Section.swift")
    let build = try buildReviewSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")
    let android = try buildReviewSource("Sources/SuperSubmitter/Tabs/AndroidArtifactsSection.swift")

    #expect(section.contains("var folds"))
    #expect(section.contains("var startsOpen"))
    #expect(build.contains("private var googleOptions"))
    #expect(android.contains("folds: true"))
}

/// One fold, drawn one way. `DisclosureGroup` puts its chevron where the
/// label's own layout leaves room, which on a two-line label is beside neither
/// line.
@Test func theBuildFoldsShareOneAlignedHeader() throws {
    let build = try buildReviewSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")

    #expect(!build.contains("DisclosureGroup"))
    #expect(build.contains("folds: true"))
}

// MARK: - Nothing uneditable is clickable

/// The bundle id and the package name belong to the store. Drawn as a control
/// that opens another tab, they read as a field you may edit and answer a
/// press by navigating away from the work.
@Test func anIdentityWithNothingToChooseIsNotAControl() throws {
    let build = try buildReviewSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")
    let start = try #require(build.range(of: "private var appleIdentity"))
    let end = try #require(build.range(of: "private func identityValue"))
    let identity = String(build[start.lowerBound..<end.lowerBound])

    #expect(!identity.contains("PickerActionRow(value: state.appleBundleID"))
    #expect(!identity.contains("PickerActionRow(value: state.googlePackageName"))
    #expect(identity.contains("identityValue(state.appleBundleID"))
    #expect(identity.contains("identityValue(state.googlePackageName"))
}

// MARK: - Build from project uses the width

/// One store means one platform, and the column of full-width cards left half
/// the screen empty next to it.
@Test func buildFromProjectPairsItsCards() throws {
    let view = try buildReviewSource("Sources/SuperSubmitter/Build/BuildFromProjectView.swift")

    #expect(view.contains("ViewThatFits(in: .horizontal)"))
    #expect(view.contains("private func pair"))
}

// MARK: - The two flows

/// A field that only a first submission uses is noise on an update, and the
/// worst of them writes to Apple: creating a bundle ID for an app that has
/// shipped under one already.
@MainActor
@Test func theNewAppFieldsGoAwayOnAnUpdate() throws {
    let state = buildReviewState()
    #expect(state.showsNewAppFields)

    var apple = ActualState.Apple()
    apple.liveVersionString = "1.5"
    var actual = ActualState()
    actual.apple = apple
    state.actualState = actual

    #expect(!state.showsNewAppFields)

    let panel = try buildReviewSource("Sources/SuperSubmitter/Tabs/SigningIdentitiesPanel.swift")
    #expect(panel.contains("state.showsNewAppFields"))
}

// MARK: - One size for the action row

/// Two buttons on one row, both ending a run, drawn at two heights.
@Test func theArtifactActionsShareOneButtonSize() throws {
    let view = try buildReviewSource("Sources/SuperSubmitter/Build/BuildFromProjectView.swift")
    let start = try #require(view.range(of: "private var actionRow"))
    let end = try #require(view.range(of: "// MARK: - 10.5"))
    let row = String(view[start.lowerBound..<end.lowerBound])

    #expect(row.contains("ActionButton(title: \"Upload to the store\""))
    #expect(row.contains("ActionButton(title: \"Keep the artifact and stop\""))
    #expect(!row.contains("QuietButton(title: \"Keep the artifact and stop\""))
}

// MARK: - The lock

/// A free account may build, inspect, and keep the artifact. Only the send is
/// paid, and the button that sends has to say so before it is pressed.
@MainActor
@Test func aPaidOnlyActionWearsALockAndSellsTheAccountTab() {
    let state = buildReviewState()
    #expect(state.showsLock(.storeUpload))

    state.entitlement = Entitlement(
        subject: "someone", status: .active, plan: .monthly,
        capabilities: [.storeUpload], issuedAt: Date(),
        refreshAfter: Date(), expiresAt: Date().addingTimeInterval(3_600))
    #expect(!state.showsLock(.storeUpload))
    #expect(state.showsLock(.storeRelease))
}

@Test func theLockedButtonRoutesThroughTheGate() throws {
    let button = try buildReviewSource("Sources/SuperSubmitter/Design/ActionButton.swift")

    #expect(button.contains("lock.fill"))
    #expect(button.contains("requirePaid"))
}

// MARK: - Two indicators beside Build

/// Building an artifact and sending it are two jobs with two outcomes. One
/// indicator reported an archive that had never been uploaded as a green tick,
/// which is the app claiming the store has something it does not.
@MainActor
@Test func theSidebarSeparatesTheArtifactFromTheUpload() {
    let flow = BuildFlow(app: nil)
    #expect(flow.artifactStatus == nil)
    #expect(flow.uploadStatus == nil)

    flow.startedAt = Date()
    flow.run.state = .building
    #expect(flow.artifactStatus == .running)
    #expect(flow.uploadStatus == nil)

    flow.run.state = .needsUploadConfirmation
    #expect(flow.artifactStatus == .succeeded)
    #expect(flow.uploadStatus == nil)

    flow.run.state = .uploading
    #expect(flow.artifactStatus == .succeeded)
    #expect(flow.uploadStatus == .running)

    flow.run.state = .complete
    #expect(flow.uploadStatus == .succeeded)
}

/// Keeping the artifact ends the run without an upload. The upload indicator
/// must stay silent rather than inherit the build's tick.
@MainActor
@Test func keepingTheArtifactNeverReportsAnUpload() {
    let flow = BuildFlow(app: nil)
    flow.startedAt = Date()
    flow.run.state = .complete
    flow.artifactOnly = true

    #expect(flow.artifactStatus == .succeeded)
    #expect(flow.uploadStatus == nil)
}

/// The category says which half failed, so a signing failure never lights the
/// upload indicator and a rejected upload never blames the build.
@MainActor
@Test func aFailureLightsTheIndicatorThatOwnsIt() {
    let flow = BuildFlow(app: nil)
    flow.startedAt = Date()
    flow.run.state = .failed

    flow.failure = BuildFailure(category: .signing, stage: "Build", message: "no identity")
    #expect(flow.artifactStatus == .failed)
    #expect(flow.uploadStatus == nil)

    flow.candidate = nil
    flow.failure = BuildFailure(category: .upload, stage: "Upload", message: "refused")
    #expect(flow.uploadStatus == .failed)
}

@Test func theSidebarDrawsBothIndicators() throws {
    let sidebar = try buildReviewSource("Sources/SuperSubmitter/Shell/Sidebar.swift")

    #expect(sidebar.contains("artifactStatus"))
    #expect(sidebar.contains("uploadStatus"))
    #expect(sidebar.contains("hammer"))
    #expect(sidebar.contains("arrow.up"))
}

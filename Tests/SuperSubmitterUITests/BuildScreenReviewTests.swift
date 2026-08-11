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

/// A shut fold was a bare header row beside the cards it belongs with, and an
/// open one dropped a panel in under it. The fold owns the box either way: a
/// title-high card shut, the whole block open, and one height between the two.
@Test func aFoldIsOneBoxThatGrows() throws {
    let section = try buildReviewSource("Sources/SuperSubmitter/Design/Section.swift")

    #expect(section.contains("storePanel"))
    #expect(section.contains("value: isOpen"))
    #expect(section.contains("clipped()"))
}

/// The box moved into the fold, so no caller may draw a second one: two panels
/// nest into a border inside a border.
@Test func aFoldDrawsTheOnlyBoxAroundIt() throws {
    let android = try buildReviewSource("Sources/SuperSubmitter/Tabs/AndroidArtifactsSection.swift")
    let build = try buildReviewSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")
    let start = try #require(build.range(of: "private var storeTools"))
    let end = try #require(build.range(of: "private var sortedPackages"))
    let tools = String(build[start.lowerBound..<end.lowerBound])

    #expect(!android.contains(".storePanel("))
    #expect(!tools.contains(".storePanel("))
}

// MARK: - Nothing uneditable is clickable

/// The bundle id belongs to the store. Drawn as a control that opens another
/// tab, it reads as a field you may edit and answers a press by navigating away
/// from the work.
///
/// The package name is the exception, and it is not one the rule ever meant to
/// cover. Apple assigns a bundle id and the Menu beside it lists the real apps
/// a credential can see; the Android Publisher API publishes no way to list
/// anything, so nobody can pick a package name and somebody has to type it. A
/// fact-shaped box was all this row had, the value it wanted lived on another
/// tab, and a developer standing on this one had no way to supply it.
@Test func anIdentityWithNothingToChooseIsNotAControl() throws {
    let build = try buildReviewSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")
    let start = try #require(build.range(of: "private var appleIdentity"))
    let end = try #require(build.range(of: "private func identityValue"))
    let identity = String(build[start.lowerBound..<end.lowerBound])

    #expect(!identity.contains("PickerActionRow(value: state.appleBundleID"))
    #expect(!identity.contains("PickerActionRow(value: state.googlePackageName"))
    #expect(identity.contains("identityValue(state.appleBundleID"))
    // Typed, and typed here. Not a control that answers a press by leaving.
    #expect(identity.contains("TextField(\"Package name\""))
    #expect(identity.contains("state.updateGoogleAppFields()"))
    #expect(!identity.contains("identityValue(state.googlePackageName"))
}

// MARK: - Build from project uses the width

/// One store means one platform, and the column of full-width cards left half
/// the screen empty next to it. The rows fill it, because a row shrinks and a
/// card of five buttons on one line does not.
///
/// The two columns are unconditional. They were a `ViewThatFits` with one
/// column behind them, and that measures the contents rather than the card: one
/// long value — an SDK path, a store message of a full sentence — restacked the
/// whole list, so the preflight changed shape as its values arrived. The layout
/// belongs to the card, and a value too long for its half wraps inside it.
@Test func buildFromProjectFillsTheWidthWithItsRows() throws {
    let view = try buildReviewSource("Sources/SuperSubmitter/Build/BuildFromProjectView.swift")

    #expect(!view.contains("ViewThatFits(in: .horizontal)"))
    #expect(view.contains("private func twoColumns"))
    #expect(view.contains("twoColumns(preflightRows(snapshot))"))
    #expect(view.contains("twoColumns(artifactRows(candidate))"))

    // The wrap itself: a preflight value takes the height its text needs.
    let start = try #require(view.range(of: "struct PreflightRow"))
    let row = String(view[start.lowerBound...])
    #expect(row.contains(".fixedSize(horizontal: false, vertical: true)"))
}

/// The command that starts the work belongs to the checks that decide whether
/// it may run.
///
/// It stood at the foot of the screen, under the live run, the artifact card
/// and the error panel, so on a tall window the one button that builds was
/// below the fold while the card that says whether it can was at the top.
@Test func theBuildCommandIsInThePreflightCard() throws {
    let view = try buildReviewSource("Sources/SuperSubmitter/Build/BuildFromProjectView.swift")
    let card = try #require(view.range(of: "private var preflightCard"))
    let rows = try #require(view.range(of: "private func preflightRows"))
    let preflight = String(view[card.lowerBound..<rows.lowerBound])
    let actions = try #require(view.range(of: "private var actionRow"))
    let confirmations = try #require(view.range(of: "private var buildConfirmation"))
    let row = String(view[actions.lowerBound..<confirmations.lowerBound])

    #expect(preflight.contains("Build Archive"))
    #expect(preflight.contains("showBuildConfirmation = true"))
    #expect(!row.contains("Build Archive"))
    // The upload and the artifact are still answered at the foot of the screen,
    // beside the artifact they describe.
    #expect(row.contains("Upload to the store"))
    #expect(row.contains("Keep the artifact and stop"))
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

// MARK: - Apple's export compliance question

/// Apple asks it once per build and refuses the submission without an answer.
///
/// It was a toggle on the Details inspector that read an unanswered question
/// as a settled "no", two tabs from the build it belongs to, and nothing made
/// the developer meet it until the store did. It is asked here now, and the
/// archive waits for it.
@MainActor
@Test func anAppleBuildWaitsForTheExportComplianceAnswer() throws {
    let state = buildReviewState()
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("build-encryption-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent(ManifestFile.defaultName)
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
    try ManifestFile.save(manifest, to: url)
    try state.load(from: url)

    let flow = BuildFlow(app: state)
    flow.run.platform = .ios
    #expect(flow.blockingReason != nil)

    state.setEncryptionAnswer(false)
    #expect(flow.blockingReason == nil)
}

/// Google asks no such question, so an App Bundle is never held for it.
@MainActor
@Test func anAndroidBuildIsNeverHeldForApplesQuestion() throws {
    let state = buildReviewState()
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("build-encryption-android-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent(ManifestFile.defaultName)
    var manifest = Manifest()
    manifest.setGoogleApp(packageName: "com.example.app")
    try ManifestFile.save(manifest, to: url)
    try state.load(from: url)

    let flow = BuildFlow(app: state)
    flow.run.platform = .android
    #expect(flow.blockingReason == nil)
}

/// A flow with no app open has no manifest to answer from, and a question
/// nobody can be asked may not hold a button.
@MainActor
@Test func aFlowWithNoAppOpenIsNotHeldForAnAnswer() {
    let flow = BuildFlow(app: nil)
    flow.run.platform = .ios
    #expect(flow.blockingReason == nil)
}

/// One row, not a card. It is a yes or no question with two words of context,
/// and the paperwork under it belongs to the app that answers yes.
@Test func theQuestionIsOneRowOnTheBuildTab() throws {
    let build = try buildReviewSource("Sources/SuperSubmitter/Tabs/BuildTab.swift")

    #expect(build.contains("Export compliance"))
    #expect(build.contains("Uses no non-exempt encryption"))
    #expect(build.contains("It does use encryption"))
    #expect(build.contains("build.encryption"))
    #expect(build.contains("struct ExportCompliance"))
    // The reason a disabled button gives, in the place the tab already puts
    // every other reason a build cannot start.
    let project = try buildReviewSource("Sources/SuperSubmitter/Build/BuildFromProjectView.swift")
    #expect(project.contains("flow.blockingReason"))
}

// MARK: - The platform is a choice

/// One app id ships iOS and macOS and the two are not in step: the Mac app can
/// be the only one on sale. The row that chooses between them was written and
/// then left out of the body by a layout change, so every apple project
/// archived `generic/platform=iOS` and nothing on screen could say otherwise.
/// The scheme, the Gradle variant, and the JDK live in the same row and were
/// unreachable with it.
///
/// A view nobody draws still compiles, so this reads the body.
@Test func theProjectFlowDrawsTheRowThatChoosesThePlatform() throws {
    let view = try buildReviewSource("Sources/SuperSubmitter/Build/BuildFromProjectView.swift")
    let body = try #require(view.range(of: "var body: some View"))
    let end = try #require(view.range(of: "private func twoColumns"))

    #expect(String(view[body.lowerBound..<end.lowerBound]).contains("selectionRow"))
    #expect(view.contains("flow.choosePlatform($0)"))
    #expect(view.contains("Text(\"macOS\").tag(BuildPlatform.macos)"))
}

/// The choice has to outlive the launch. `loadSavedProject` restores the
/// platform from the saved link, so an answer that stopped at the run came
/// back as iOS the next morning.
@MainActor
@Test func choosingMacOSReachesTheLinkAndNotOnlyTheRun() {
    let flow = BuildFlow(app: nil)
    flow.project = LinkedSourceProject(
        platform: .ios, rootPath: "/Users/me/apps/deck",
        containerPath: "/Users/me/apps/deck/Deck.xcodeproj",
        containerKind: .project, manifestPath: "/Users/me/apps/deck/store.yaml")

    flow.choosePlatform(.macos)

    #expect(flow.run.platform == .macos)
    #expect(flow.project?.platform == .macos)
    #expect(flow.snapshot.destination != "generic/platform=iOS")
}

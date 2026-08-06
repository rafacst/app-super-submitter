import Foundation
import Testing
@testable import SubmitKit

private func findings(_ manifest: Manifest, _ actual: ActualState) -> [Finding] {
    Validator.findings(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
}

/// What Apple demands of a version that follows a released one.
///
/// Every rule here fires only when the app is already on the App Store. A
/// first submission fills the same fields over several sittings, and an error
/// on a half-built manifest teaches the developer to ignore the Summary tab.
///
/// The rules split across two gates on purpose. What's New is manifest content
/// that the apply writes, so it blocks the apply. A build and an export
/// compliance answer arrive later by design, so they hold the release button
/// instead: an apply leaves a draft, and a draft may be unfinished.

private func updatable(whatsNew: String? = "Faster scanning.") -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    if let whatsNew { manifest.setListingText(whatsNew, locale: "en-US", field: .whatsNew) }
    manifest.setReleaseVersionName("3.2.0")
    return manifest
}

/// A live app, and no version in preparation yet.
private func live(_ build: (inout ActualState.Apple) -> Void = { _ in }) -> ActualState {
    var apple = ActualState.Apple()
    apple.liveVersionString = "3.1.0"
    build(&apple)
    var state = ActualState()
    state.apple = apple
    return state
}

private func rows(_ manifest: Manifest, _ actual: ActualState) -> [ConsoleRow] {
    ConsoleChecklist.rows(manifest: manifest, actual: actual, stores: [.apple])
}

private func row(_ id: String, _ manifest: Manifest, _ actual: ActualState) -> ConsoleRow? {
    rows(manifest, actual).first { $0.id == id }
}

// MARK: - What's New blocks the apply

@Test func anUpdateWithNoWhatsNewBlocksTheApply() {
    let finding = try! #require(findings(updatable(whatsNew: nil), live())
        .first { $0.id == "update.whatsNew.en-US" })

    #expect(finding.severity == .error)
    #expect(finding.fix == .details)
}

@Test func anUpdateWithWhatsNewPasses() {
    #expect(!findings(updatable(), live()).contains { $0.id.hasPrefix("update.whatsNew") })
}

@Test func aDraftThatAlreadyHoldsTheNoteNeedsNothingFromTheManifest() {
    // An absent key means "do not manage this field", never "clear it". A rule
    // that demanded the manifest hold a value the store already has would
    // break that.
    let actual = live { apple in
        apple.versionId = "version-next"
        apple.versionLocales["en-US"] = {
            var locale = ActualState.Apple.VersionLocale()
            locale.whatsNew = "Already written in App Store Connect."
            return locale
        }()
    }

    #expect(!findings(updatable(whatsNew: nil), actual)
        .contains { $0.id.hasPrefix("update.whatsNew") })
}

@Test func aFirstSubmissionNeverAsksForWhatsNew() {
    // No live version, so this is not an update.
    #expect(!findings(updatable(whatsNew: nil), ActualState())
        .contains { $0.id.hasPrefix("update.whatsNew") })
}

@Test func everyManagedLocaleNeedsItsOwnNote() {
    var manifest = updatable(whatsNew: nil)
    manifest.addLocale("pt-BR", name: "Exemplo")
    manifest.setListingText("Leitura mais rapida.", locale: "pt-BR", field: .whatsNew)

    let ids = Set(findings(manifest, live()).map(\.id))
    #expect(ids.contains("update.whatsNew.en-US"))
    #expect(!ids.contains("update.whatsNew.pt-BR"))
}

// MARK: - The build and the compliance answer hold the release button

@Test func aFirstSubmissionShowsNoUpdateRows() {
    let ids = Set(rows(updatable(), ActualState()).map(\.id))
    #expect(!ids.contains("apple.updateBuild"))
    #expect(!ids.contains("apple.updateEncryption"))
    #expect(!ids.contains("apple.updateReviewContact"))
}

@Test func anUpdateWithNoBuildAnywhereHoldsTheReleaseButton() {
    #expect(row("apple.updateBuild", updatable(), live())?.state == .needed)
}

@Test func aBuildNamedInTheManifestSatisfiesTheRow() {
    var manifest = updatable()
    manifest.apply(package: AppPackage(kind: .ipa, url: URL(fileURLWithPath: "/tmp/App.ipa")),
                   path: "build/App.ipa")

    #expect(row("apple.updateBuild", manifest, live())?.state == .done)
}

@Test func aBuildAlreadyAttachedInAppStoreConnectSatisfiesTheRow() {
    let actual = live { $0.attachedBuildId = "build-77" }
    #expect(row("apple.updateBuild", updatable(), actual)?.state == .done)
}

@Test func anUnansweredEncryptionQuestionHoldsTheReleaseButton() {
    #expect(row("apple.updateEncryption", updatable(), live())?.state == .needed)
}

@Test func theEncryptionAnswerMayComeFromTheManifestOrTheBuild() {
    var manifest = updatable()
    manifest.review = Manifest.Review()
    manifest.review?.usesNonExemptEncryption = false
    #expect(row("apple.updateEncryption", manifest, live())?.state == .done)

    let fromBuild = live { $0.buildUsesNonExemptEncryption = false }
    #expect(row("apple.updateEncryption", updatable(), fromBuild)?.state == .done)
}

// MARK: - The review contact

@Test func theReviewContactStaysUnknownUntilTheNextVersionExists() {
    // Apple carries the contact over from the released version. Before the
    // next version exists there is nothing to read, and a needed row would
    // hold the button on a guess.
    let contact = row("apple.updateReviewContact", updatable(), live())
    #expect(contact?.state == .unknown)
}

@Test func anEmptyContactOnAnExistingDraftHoldsTheReleaseButton() {
    let actual = live { $0.versionId = "version-next" }
    let contact = try! #require(row("apple.updateReviewContact", updatable(), actual))

    #expect(contact.state == .needed)
    #expect(contact.reason.contains("first name"))
    #expect(contact.reason.contains("phone"))
}

@Test func aContactTheStoreAlreadyHoldsSatisfiesTheRow() {
    let actual = live { apple in
        apple.versionId = "version-next"
        apple.reviewContactFirstName = "Rafa"
        apple.reviewContactLastName = "C"
        apple.reviewContactEmail = "dev@example.com"
        apple.reviewContactPhone = "+351000000000"
    }

    #expect(row("apple.updateReviewContact", updatable(), actual)?.state == .done)
}

@Test func everyUpdateRowIsAnAppStoreRowSoTheGateFindsIt() {
    // `releaseBlockers` filters by system name. A row with another name would
    // never hold the button.
    let updateRows = rows(updatable(), live()).filter { $0.id.hasPrefix("apple.update") }
    #expect(updateRows.count == 3)
    #expect(updateRows.allSatisfy { $0.system == "App Store" })
}

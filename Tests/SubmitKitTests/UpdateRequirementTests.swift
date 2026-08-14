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

// MARK: - The note of the release that already shipped

/// The gap an import of a live app leaves, and the one no other screen catches.
///
/// The import fills What's New from the version customers are reading, so the
/// field is full and the rule above stays quiet. The plan then compares the
/// manifest against that same released version, finds them identical, and
/// writes nothing, which is correct and silent. Apple pre-fills a new version
/// from the last one, so the words reach the store either way.
private func shipped(_ note: String) -> ActualState {
    live { apple in
        apple.liveVersionLocales["en-US"] = {
            var locale = ActualState.Apple.VersionLocale()
            locale.id = "loc-live"
            locale.whatsNew = note
            return locale
        }()
    }
}

@Test func theNotesOfTheLiveVersionAreNotTheNotesOfTheNextOne() {
    let finding = try! #require(findings(updatable(), shipped("Faster scanning."))
        .first { $0.id == "update.staleWhatsNew.en-US" })

    #expect(finding.severity == .warning)
    #expect(finding.fix == .details)
    // It names the version whose words these are, because "still the old
    // notes" is not actionable without knowing which release wrote them.
    #expect(finding.message.contains("3.1.0"))
}

@Test func aNoteTheDeveloperRewroteRaisesNothing() {
    #expect(!findings(updatable(whatsNew: "Now with widgets."), shipped("Faster scanning."))
        .contains { $0.id.hasPrefix("update.staleWhatsNew") })
}

@Test func aFirstSubmissionHasNoLiveNoteToRepeat() {
    #expect(!findings(updatable(), ActualState())
        .contains { $0.id.hasPrefix("update.staleWhatsNew") })
}

@Test func anEmptyNoteIsTheMissingRuleAndNotThisOne() {
    // One row per locale, never two. The field is empty, so it is the error
    // above and this rule has nothing to add.
    let ids = findings(updatable(whatsNew: nil), shipped("Faster scanning.")).map(\.id)
    #expect(ids.contains("update.whatsNew.en-US"))
    #expect(!ids.contains("update.staleWhatsNew.en-US"))
}

// MARK: - The build and the compliance answer hold the release button

/// A first submission needs every one of these, and used to be asked for none.
///
/// The rows were drawn only for an app with a released version, which reads the
/// distinction backwards. A build, an export compliance answer and a review
/// contact are what Apple refuses a submission without, and the developer who
/// has never shipped is the one who has never supplied any of them. The release
/// button checked the developer who had already done it once, and waved the
/// other one through.
@Test func aFirstSubmissionIsCheckedForWhatAppleRefusesWithout() {
    let ids = Set(rows(updatable(), ActualState()).map(\.id))
    #expect(ids.contains("apple.updateBuild"))
    #expect(ids.contains("apple.updateEncryption"))
    #expect(ids.contains("apple.updateReviewContact"))

    // Real gaps, and not decoration: each one holds the release button.
    #expect(row("apple.updateBuild", updatable(), ActualState())?.state == .needed)
    #expect(row("apple.updateEncryption", updatable(), ActualState())?.state == .needed)
}

/// The review contact is the one row where the two flows really differ.
///
/// Apple carries it forward from the released version, so an update with no
/// next version yet has an answer the app cannot read. A first submission
/// inherits nothing, and an empty manifest there is a gap and not an unread
/// answer.
@Test func onlyAnUpdateInheritsItsReviewContact() {
    #expect(row("apple.updateReviewContact", updatable(), ActualState())?.state == .needed)
    #expect(row("apple.updateReviewContact", updatable(), live())?.state == .unknown)
}

@Test func anUpdateWithNoBuildAnywhereHoldsTheReleaseButton() {
    #expect(row("apple.updateBuild", updatable(), live())?.state == .needed)
}

@Test func aBuildNamedInTheManifestIsApplyWorkNotAReleaseBlocker() {
    var manifest = updatable()
    manifest.apply(package: AppPackage(kind: .ipa, url: URL(fileURLWithPath: "/tmp/App.ipa")),
                   path: "build/App.ipa")

    let named = try! #require(row("apple.updateBuild", manifest, live()))
    #expect(named.state == .done)
    #expect(named.reason.contains("Run the apply"))
}

@Test func anUploadedProcessedBuildIsApplyWorkNotAReleaseBlocker() {
    let actual = live { $0.buildIdForVersion = "build-91" }
    let uploaded = try! #require(row("apple.updateBuild", updatable(), actual))
    #expect(uploaded.state == .done)
    #expect(uploaded.reason.contains("uploaded"))
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

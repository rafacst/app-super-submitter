import SubmitKit
import SwiftUI

/// A version App Store review is holding, and the two ways forward from it.
///
/// The app has always known this state and did one thing with it: it refused
/// the apply and printed two errors. A developer meeting that had two real
/// questions and no way to ask either one inside the app.
///
/// - **What did I actually send?** The listing on screen is the manifest, and
///   the manifest has moved on. What Apple is reading is the version, and only
///   a read answers for it.
/// - **How do I start the next one?** Every keystroke during a review belongs
///   to the version after the one under review, and it had nowhere to land.
///
/// Editing is never blocked. A draft in `store.yaml` reaches no store, and the
/// wait is exactly when the next version gets written. What the wait blocks is
/// the send, and that is `sendBlockedByReview` and `uploadBlockedByReview`.
extension AppState {

    /// Which of the two the developer picked for the version under review.
    enum ReviewPath: String, Codable, Sendable {
        /// Look at what was sent. The listing goes read-only, because Apple
        /// holds it and a box that took characters would be a box whose
        /// characters can never be sent.
        case inspect
        /// Write the version after this one. Everything unlocks: the writes
        /// land on a version the developer owns.
        case next
    }

    /// Whether Apple is holding a version at all.
    var appleHoldsAVersion: Bool {
        guard let state = actualState.apple?.versionState else { return false }
        return AppleVersionState.withApple.contains(state)
    }

    // MARK: - Every linked app, not only the open one

    /// Whether App Store review is holding this app's version.
    ///
    /// Nil means nobody has asked, and an app nobody has asked is not an app
    /// that is free. It locks nothing and claims nothing, which is the same
    /// rule every other read in this app follows.
    func isAppLocked(appKey: String) -> Bool {
        guard let state = appReviewStates[appKey] else { return false }
        return AppleVersionState.withApple.contains(state)
    }

    /// The mark the sidebar puts beside one row.
    ///
    /// A draft earns none. It is the ordinary state, and a column where every
    /// row wears a badge is a column with no signal left in it.
    func appReviewMark(appKey: String) -> (text: String, colour: Color)? {
        switch AppleVersionState.outcome(of: appReviewStates[appKey]) {
        case .waiting: ("In review", Theme.yellow)
        case .approved: ("Approved", Theme.green)
        case .refused: ("Refused", Theme.red)
        case nil: nil
        }
    }

    /// The open app is read twice, by the plan read and by the sweep below,
    /// and the two may never disagree about it. The plan read is the better
    /// answer because it is the fuller one, so it wins.
    func rememberOpenAppReviewState() {
        guard let state = actualState.apple?.versionState else { return }
        appReviewStates[currentAppKey] = state
    }

    /// Reads the version state of every linked app.
    ///
    /// The rules about a version under review all read `actualState`, and
    /// `actualState` only ever describes the app that happens to be open. A
    /// developer with six linked apps had to open each one to learn which were
    /// frozen, and the list that shows all six said nothing.
    ///
    /// One small read per app: the versions of that app and nothing else. The
    /// full plan read is far heavier and answers a question this does not ask.
    /// An app that cannot be read keeps whatever it had, because a failed read
    /// is not news about the store.
    func refreshReviewStates() async {
        guard !applePrivateKeyPEM.isEmpty else { return }
        rememberOpenAppReviewState()
        let reader = StoreImportReader(credentials: credentials)
        for record in linkedApps {
            let url = URL(fileURLWithPath: record.manifestPath)
            guard let loaded = try? ManifestFile.load(from: url),
                  let appID = loaded.apps.apple?.appId, !appID.isEmpty,
                  appID != currentAppKey || actualState.apple?.versionState == nil
            else { continue }
            if let state = await reader.appleVersionState(appID: appID) {
                appReviewStates[appID] = state
            }
        }
    }

    /// The key the choice is remembered under.
    ///
    /// The version string and not the app alone. "I looked at 3.2.0" says
    /// nothing about 3.3.0, and a choice that outlived its version would put a
    /// developer back into a locked listing for a version nobody had sent.
    private var reviewChoiceKey: String {
        "reviewPath.\(currentAppKey).\(actualState.apple?.versionString ?? "")"
    }

    var reviewPath: ReviewPath? {
        defaults.string(forKey: reviewChoiceKey).flatMap(ReviewPath.init(rawValue:))
    }

    /// Whether the app should still be asking.
    var reviewNeedsAChoice: Bool { appleHoldsAVersion && reviewPath == nil }

    func chooseReviewPath(_ path: ReviewPath) {
        defaults.set(path.rawValue, forKey: reviewChoiceKey)
    }

    /// Puts the question back. A developer who looked at what was sent and now
    /// wants to write the next version has to be able to say so.
    func clearReviewPath() {
        defaults.removeObject(forKey: reviewChoiceKey)
    }

    /// Whether the App Store refuses a write to this listing field right now.
    ///
    /// Two states refuse it, and neither one is a fault:
    ///
    /// - Apple is holding the version and the developer chose to look at what
    ///   was sent. Choosing to write the next version instead unlocks
    ///   everything, because those writes are for a version this one is not.
    /// - The listing on screen is the one customers are reading, which is every
    ///   field on the Manage side. App Store Connect takes no change to a
    ///   published listing: the change belongs to the next version, and the
    ///   next version is the Publish side of this app.
    ///
    /// Which fields is store policy and not the schema. Every one of them is a
    /// plain string on `appStoreVersionLocalizations` and the endpoint would
    /// take any of them, so nothing in the API reference says this. See
    /// `AppleVersionState.isLocked` for the one exception Apple documents.
    func appleRefusesListing(_ field: ListingTextField) -> Bool {
        guard AppleVersionState.isLocked(field) else { return false }
        if appleHoldsAVersion, reviewPath == .inspect { return true }
        return mode == .managing
    }

    /// Whether a listing field refuses characters right now.
    ///
    /// Kept for the review lock's own call sites and for the tests that name
    /// it. `listingLock(_:store:)` is what a box asks, because a box stands in
    /// a column and the two stores answer differently.
    func isListingLocked(_ field: ListingTextField) -> Bool {
        guard appleHoldsAVersion, reviewPath == .inspect else { return false }
        return AppleVersionState.isLocked(field)
    }

    /// What one listing box says about itself, or nil while every store it
    /// stands for takes the characters.
    ///
    /// `store` is the column the box is in. Nil is the merged box, which stands
    /// for every selected store at once and goes static only when nothing at
    /// all would take the typing: while Google Play still takes it, the
    /// characters are still worth something and the box names the store that
    /// will not read them.
    ///
    /// Google Play never appears here. Play takes a listing update whenever it
    /// is sent, without a release and without a new version, which is the whole
    /// reason this answer is per store rather than per field.
    func listingLock(_ field: ListingTextField, store: Store?) -> ListingLock? {
        guard appleRefusesListing(field) else { return nil }
        let shown = store.map { [$0] }
            ?? (stores.isEmpty ? [.apple] : Store.allCases.filter(stores.contains))
        guard shown.contains(.apple) else { return nil }

        guard !shown.contains(.google) else {
            return ListingLock(
                isStatic: false,
                line: "Google Play takes this now. The App Store takes it with the next version.")
        }
        if appleHoldsAVersion, reviewPath == .inspect {
            return ListingLock(isStatic: true, line: "App Store review is reading this")
        }
        return ListingLock(
            isStatic: true,
            line: "Customers are reading this. The App Store takes a change with the next version.")
    }

    /// Why a listing box is not taking characters, and whether it is a box at
    /// all.
    struct ListingLock: Equatable {
        /// The box is text. Nothing shown would take the typing.
        var isStatic: Bool
        var line: String
    }

    /// The one line the Manage listing puts above its rows, or nil where every
    /// row answers for itself.
    ///
    /// A merged box stands for both stores, so nearly every row on that screen
    /// carries the same sentence about the App Store: six identical lines down
    /// one column, which is the habit of saying a thing twice that the rest of
    /// this screen spent a pass undoing. The rows that differ still speak for
    /// themselves, which is the Apple-only fields and anything gone static.
    /// Only the merged two-store view. A column per store lets the Apple boxes
    /// go static and say it themselves, and a one-store app has no split
    /// answer to give.
    var listingLockBanner: String? {
        guard mode == .managing, detailsMerged,
              stores.contains(.apple), stores.contains(.google) else { return nil }
        return "Google Play takes these now. The App Store takes them with the next version."
    }

    /// Reads the version App Store review is holding, so the developer can see
    /// what was actually sent.
    ///
    /// It lands in `storeSnapshot`, which every editing tab already draws under
    /// the field it belongs to, and never in the manifest. The manifest is the
    /// next version being written; overwriting it with the one under review
    /// would throw away the work the wait exists for.
    ///
    /// The text and the screenshots. No artifact: a binary is not something
    /// anybody checks by eye.
    func retrieveVersionInReview() async {
        guard let versionID = actualState.apple?.versionId else { return }
        reviewRetrieving = true
        reviewRetrievalError = nil
        defer { reviewRetrieving = false }
        let listing = await StoreImportReader(credentials: credentials)
            .appleVersion(versionID: versionID)
        guard listing.failures.isEmpty || !listing.locales.isEmpty else {
            reviewRetrievalError = listing.failures.first
                ?? "App Store Connect returned nothing for this version."
            return
        }
        var snapshot = storeSnapshot
        snapshot.merge(listing, store: .apple)
        storeSnapshot = snapshot
        if let root = manifestRoot { snapshot.save(toRoot: root) }
        if !listing.failures.isEmpty { reviewRetrievalError = listing.failures.first }
    }

    /// The refusal the banner has to carry a tick for, or nil when nothing is
    /// waiting on one.
    ///
    /// A refusal is a warning, a warning holds the apply until it is
    /// acknowledged, and the Summary card drops this one row because the banner
    /// above already says it in more words. That is right, and it took the only
    /// "Acknowledge" in the app that unlocks this apply with it: the button was
    /// off, the note under it asked for an acknowledgement, and the screen
    /// carried nothing to acknowledge.
    ///
    /// So the banner grows the tick rather than the card growing the row back.
    /// The sentence is still said once, and the control sits under the sentence
    /// it belongs to.
    ///
    /// A hold gets none. Nothing the developer does closes a hold, and a
    /// checkbox beside it would promise otherwise.
    var reviewWarningNeedingAcknowledgement: Finding? {
        guard reviewOutcome?.outcome == .refused else { return nil }
        return plan?.warnings.first {
            $0.id == Validator.appleVersionFindingID && !acknowledged.contains($0.id)
        }
    }

    /// What Apple said, for the banner that says it.
    struct ReviewAnswer: Equatable {
        var outcome: AppleVersionState.Outcome
        var line: String
    }

    /// Apple's answer about the version, in one sentence, or nil while there
    /// is no answer to report.
    ///
    /// A refusal names the kind and never a reason. The App Store Connect API
    /// publishes no Resolution Center resource: no `rejectionReason`, no
    /// message, no attachment of Apple's reply. The kind comes from the state
    /// and the sentence exists only in App Store Connect, so the app says the
    /// kind and sends the developer where the rest is written.
    var reviewOutcome: ReviewAnswer? {
        let state = actualState.apple?.versionState
        guard let outcome = AppleVersionState.outcome(of: state) else { return nil }
        let version = actualState.apple?.versionString ?? "This version"
        switch outcome {
        case .waiting:
            return ReviewAnswer(outcome: .waiting,
                                line: "\(version) is with App Store review.")
        case .approved:
            return ReviewAnswer(
                outcome: .approved,
                line: state == "PENDING_DEVELOPER_RELEASE"
                    ? "App Store review approved \(version). It goes on sale when you release it."
                    : "App Store review approved \(version).")
        case .refused:
            let kind = AppleVersionState.refusalKind(state) ?? "the submission"
            return ReviewAnswer(
                outcome: .refused,
                line: "App Store review refused \(kind) of \(version). Apple writes the reason in App Store Connect, and no endpoint returns it.")
        }
    }
}

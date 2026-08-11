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
    /// `AppleStanding` and not a second vocabulary. It went through
    /// `Outcome`, which knows three answers, and the column paid for both ends
    /// of that: a live app and an approved one both read "Approved", so the
    /// word never said the thing a developer opens the list to see, and every
    /// draft read as nothing at all. `AppleStanding` is the same fifteen states
    /// the Build tab collapses, so one app cannot be "Approved" in the column
    /// and "Live" on the tab.
    ///
    /// Two sources, in this order. An App Store version state is the fuller
    /// answer and wins wherever there is one. Everything else falls back on the
    /// one fact both stores answer, which is what a Google Play app has: Play
    /// publishes no review state at all, so a Play app used to wear nothing
    /// whatever anybody had read about it.
    ///
    /// A word for every row, including "Unknown". An app nobody has asked about
    /// is in no state this app may claim, and a blank beside a name is not that
    /// claim being withheld: it reads as an app with nothing to say. "Unknown"
    /// says which of the two it is, and it is the state every app wears between
    /// being linked and its first read answering.
    func appMark(appKey: String) -> AppleStanding {
        guard let state = appReviewStates[appKey], !state.isEmpty else {
            return AppleStanding(shipped: appLiveStates[appKey])
        }
        return AppleStanding(state: state)
    }

    /// Whether a store has this app on sale, or has had it.
    ///
    /// The Manage side is the app that is already live, so this is what decides
    /// which apps that side lists at all. A draft belongs to Publishing alone:
    /// there are no customers to manage, no listing anybody is reading, and no
    /// crash rate to watch.
    ///
    /// An app nobody has read is not live, because it is not known to be. The
    /// answer arrives when the app is linked, which is the one moment that
    /// names a single app and can therefore ask Google Play as well: see
    /// `readAppLiveness(for:)`.
    func isAppLive(appKey: String) -> Bool { appLiveStates[appKey] == true }

    /// Remembers what a store answered about this app.
    ///
    /// A yes is never taken back. An app pulled from sale was still published,
    /// its listing is still the one customers last read, and the developer who
    /// pulled it is exactly the person who has managing left to do. A no
    /// therefore writes only where nothing was known, which is what turns
    /// "Unknown" into an answer without ever unpublishing an app on screen.
    func rememberAppLiveness(_ key: String, live: Bool) {
        guard !key.isEmpty, appLiveStates[key] != live else { return }
        // A no writes only into the silence.
        guard live || appLiveStates[key] == nil else { return }
        appLiveStates[key] = live
        defaults.set(appLiveStates, forKey: liveAppsKey)
    }

    /// The open app's own answer, kept for the sidebar to read about it later.
    ///
    /// `isUpdatingLiveApp` is the question and it asks the current read, which
    /// covers both stores and is gone the moment another app opens.
    ///
    /// A yes only. False here is "this read found nothing", and the read may be
    /// the empty one an app carries before anything has been fetched, which is
    /// not a store saying no.
    func rememberOpenAppLiveState() {
        guard isUpdatingLiveApp else { return }
        rememberAppLiveness(currentAppKey, live: true)
    }

    /// Asks both stores whether they have ever had this one app, once.
    ///
    /// It runs when the app is linked. That is the only moment in this app that
    /// names one app rather than all of them, and it is what makes the Google
    /// Play half affordable: Play answers this per package and only inside an
    /// edit, so one app costs an edit opened, a track list read, and the edit
    /// thrown away, while the same question over every linked app at launch
    /// would open and abandon one edit per app before the window was usable.
    ///
    /// Nothing is asked twice. The answer is a fact that stands and it is kept
    /// in the defaults, so this returns at once for every app already answered
    /// for, and a store that could not be reached leaves the app unknown and
    /// asks again next time.
    ///
    /// An app whose manifest names no store id needs no request to answer for:
    /// there is no record for a store to hold.
    func readAppLiveness(for record: LinkedAppRecord) async {
        let url = URL(fileURLWithPath: record.manifestPath)
        let loaded = try? ManifestFile.load(from: url)
        let key = appKey(loaded, record: record)
        guard appLiveStates[key] == nil else { return }

        let appID = loaded?.apps.apple?.appId ?? ""
        let package = loaded?.apps.google?.packageName ?? ""
        guard !appID.isEmpty || !package.isEmpty else {
            return rememberAppLiveness(key, live: false)
        }

        let reader = StoreImportReader(credentials: credentials)
        var answered = false
        var shipped = false
        if !appID.isEmpty, !applePrivateKeyPEM.isEmpty,
           let apple = await reader.appleVersionState(appID: appID) {
            // The same read the sweep makes, so the chip gets the fuller word
            // as well as the fact underneath it.
            if !apple.state.isEmpty { appReviewStates[appID] = apple.state }
            answered = true
            shipped = apple.shipped
        }
        // Only when the App Store has not already said yes. One store is
        // enough, and the Play half is the expensive one.
        if !shipped, !package.isEmpty, hasGoogleCredential,
           let play = await reader.googleProductionShipped(packageName: package) {
            answered = true
            shipped = play
        }
        guard answered else { return }
        rememberAppLiveness(key, live: shipped)
    }

    /// Whether Google Play would take a signed request at all.
    ///
    /// The two routes are one answer here. A service account and an OAuth token
    /// both sign the same reads, and `credentials` carries whichever the
    /// developer picked.
    private var hasGoogleCredential: Bool {
        credentials.google != nil || credentials.googleOAuth != nil
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
    ///
    /// The same list says whether the app has ever been on sale, which is what
    /// the Manage side lists its apps by. That answer costs no request of its
    /// own and it is the only one that reaches an app nobody has opened.
    func refreshReviewStates() async {
        guard !applePrivateKeyPEM.isEmpty else { return }
        rememberOpenAppReviewState()
        rememberOpenAppLiveState()
        let reader = StoreImportReader(credentials: credentials)
        for record in linkedApps {
            let url = URL(fileURLWithPath: record.manifestPath)
            guard let loaded = try? ManifestFile.load(from: url),
                  let appID = loaded.apps.apple?.appId, !appID.isEmpty,
                  appID != currentAppKey || actualState.apple?.versionState == nil
            else { continue }
            guard let answer = await reader.appleVersionState(appID: appID) else { continue }
            // An app with no version at all answers with no word. Writing the
            // empty string over what a fuller read left would turn a state the
            // sidebar draws into a row with nothing beside it.
            if !answer.state.isEmpty { appReviewStates[appID] = answer.state }
            // A no as well as a yes, so an app the App Store answers for on its
            // own is never left unknown. An app that also goes to Google Play
            // is not one of those: Apple saying no leaves the question open,
            // and writing that no down would close it against a store nobody
            // asked. Linking is where Play is asked. See `readAppLiveness`.
            let package = loaded.apps.google?.packageName ?? ""
            if answer.shipped || package.isEmpty {
                rememberAppLiveness(appID, live: answer.shipped)
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

    /// Whether the App Store takes a change to this field while the listing is
    /// live, on a screen where the fields beside it do not.
    ///
    /// A tab of read-only boxes hides its one working control. The promotional
    /// text is the whole answer to "what can I change right now?", and telling
    /// it apart by the absence of a lock asks the developer to notice a thing
    /// that is not there.
    ///
    /// Only where something else is locked. On the Publish side every field
    /// writes, so a mark on one of them would say the others do not.
    func appleTakesLiveChange(_ field: ListingTextField) -> Bool {
        mode == .managing && stores.contains(.apple) && !AppleVersionState.isLocked(field)
    }

    /// Whether the Manage listing has anything to explain about itself.
    ///
    /// The reason is the same for every box on the tab, so a line over each one
    /// was one sentence six times down a column. It is one ⓘ beside the tab's
    /// own controls instead.
    ///
    /// The App Store alone raises it. Google Play takes a listing update at any
    /// time, without a release and without a new version, so a Play-only app
    /// has nothing here to explain.
    var showsLiveListingNote: Bool {
        mode == .managing && stores.contains(.apple)
    }

    /// Whether the button over the boxes has a store that would take a row.
    ///
    /// Google Play alone, on this side. With no Play the tab can write nothing
    /// at all, and a bar that counts to zero is a control that says the screen
    /// does something it does not.
    var showsLiveListingApplyBar: Bool {
        mode == .managing && stores.contains(.google)
    }

    /// Whether a direct apply of the listing may carry the App Store's rows.
    ///
    /// It may not on the Manage side. Apple takes no change to a listing
    /// customers are reading, so offering those rows is a button built to be
    /// refused.
    ///
    /// The promotional text goes with them, and that is a real loss: Apple does
    /// take that one on a live version. It cannot be sent alone, because the
    /// planner ids an Apple listing row per locale rather than per field, so
    /// `apple.locale.en-US` carries the description and the keywords in the
    /// same request. Sending the one field needs those steps split per field.
    var directApplyOffersAppleListing: Bool { mode != .managing }

    /// The stores a direct apply of this tab can really reach.
    ///
    /// The button names its destination, and naming a store whose rows were
    /// just dropped is a button that promises a write it will not make.
    func directApplyStores(for target: DirectApplyTarget) -> Set<Store> {
        guard target == .listing, !directApplyOffersAppleListing else { return stores }
        return stores.subtracting([.apple])
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

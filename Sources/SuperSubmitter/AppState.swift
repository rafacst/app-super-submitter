import AppKit
import Aptabase
import Foundation
import Observation
import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

struct LinkedAppRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var manifestPath: String
    /// True until the developer links a real project folder in the Build
    /// tab. Set only by a Publishing import of two or more apps, which
    /// writes `store.yaml` into Super Submitter's own folder rather than
    /// asking for a folder per app up front; linking a project later moves
    /// it into that folder. See `BuildFlow.relocateManifestIfPending`.
    ///
    /// Optional, so a record written before this field existed still decodes.
    var awaitingProjectFolder: Bool?
}

enum ConnectionStatus: Equatable {
    case notConnected
    case connecting
    case connected(String)
    case failed(String)

    var label: String {
        switch self {
        case .notConnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected(let message): message
        case .failed(let message): message
        }
    }

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    /// A refusal, as opposed to a question nobody has asked yet. The two used
    /// to draw the same grey, so a failed connection read as "not tested".
    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

enum GoogleCredentialChoice: String, CaseIterable, Identifiable {
    case oauth
    case serviceAccount

    var id: Self { self }
}

enum PurchaseTextField { case id, name, amount, currency, entitlement }
enum PlanTextField {
    case id, duration, basePlanID, applePlanType, amount, currency, entitlement, packageKey
}

struct CatalogPriceInput {
    var amount: String
    var currency: String
}

enum MediaInputError: LocalizedError {
    case tooMany(limit: Int)

    var errorDescription: String? {
        switch self {
        case .tooMany(let limit): "You can add at most \(limit) files to this device size."
        }
    }
}

enum Severity {
    case error, warning

    var color: Color { self == .error ? Theme.red : Theme.yellow }
    var background: Color { self == .error ? Theme.redBg : Theme.yellowBg }
}

/// What a tab has open, split by whether it blocks the apply.
///
/// One count in one colour said two different things at once: a tab holding
/// 1 error and 5 warnings drew a red 6, and six blockers is not what that
/// tab held. An error stops the apply and a warning asks to be acknowledged,
/// so the two never belonged in one number.
/// `Equatable` so the sidebar can animate on it. `BadgeView` watches the whole
/// badge rather than the two counts separately: they change together, in one
/// read of the stores, and two `animation(value:)` modifiers would put the
/// error pill and the warning pill on two clocks.
struct TabBadge: Equatable {
    var errors = 0
    var warnings = 0

    /// The two pills differ by hue alone on screen, and colour is not a
    /// distinction on its own (WCAG 1.4.1). This is what the row reads out
    /// and what the tooltip says.
    var spoken: String {
        [errors > 0 ? "\(errors) \(errors == 1 ? "error" : "errors")" : nil,
         warnings > 0 ? "\(warnings) \(warnings == 1 ? "warning" : "warnings")" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

@Observable
@MainActor
final class AppState {
    @ObservationIgnored var runTask: Task<Void, Never>?
    @ObservationIgnored var runner: Runner?
    @ObservationIgnored var eventTask: Task<Void, Never>?
    @ObservationIgnored var runContinuation: AsyncStream<RunEvent>.Continuation?
    @ObservationIgnored var pollTask: Task<Void, Never>?
    @ObservationIgnored var stateGeneration = 0
    /// The coalesced write. See `scheduleSave`.
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSave = false
    var applePrivateKeyPEM = ""
    var googleCredential: GoogleServiceAccount?
    var googleOAuthCredential: GoogleOAuthCredential?
    @ObservationIgnored private let linkedAppsDefaultsKey = "linkedApps.v1"
    @ObservationIgnored private let lastOpenAppKey = "lastOpenApp.v1"
    @ObservationIgnored private let modeDefaultsKey = "mode.v1"
    /// Not private: `rememberAppLiveness` writes it, and it lives in the review
    /// extension one file over.
    @ObservationIgnored let liveAppsKey = "appLiveStates.v1"
    @ObservationIgnored private let googleCredentialChoiceKey = "googleCredentialChoice.v1"

    // The manifest and the file behind it.
    var manifest = Manifest()
    var manifestURL: URL?
    var linkedApps: [LinkedAppRecord] = []
    var errorMessage: String?

    // The two gates in front of Settings ▸ Nuclear. See `eraseEverything()`.
    var nuclearFirstConfirm = false
    var nuclearSecondConfirm = false

    // Undo. See AppStateUndo.swift.
    /// The stack for `store.yaml`. The app owns it rather than the window,
    /// because every field writes the manifest as it is typed, so the manifest
    /// stack *is* the typing stack and Command-Z has to reach it.
    @ObservationIgnored let undoManager = UndoManager()
    /// The manifest as it stood before the edit now being saved.
    @ObservationIgnored var undoBaseline = Manifest()
    @ObservationIgnored var lastUndoRegistration: Date?
    /// `UndoManager` is not observable, so the menu reads these instead.
    var canUndoEdit = false
    var canRedoEdit = false
    /// When the app last wrote `store.yaml`. Every edit writes the file, so
    /// the shell shows this and the user knows the work is on disk.
    var lastSavedAt: Date?
    /// When the app last wrote a local draft. The header button reports it,
    /// and Settings re-reads the folder whenever it changes. See `Draft`.
    var draftSavedAt: Date?
    /// When one tab last wrote its draft rows to a store.
    var remoteSavedAt: Date?

    // Navigation.
    /// Publishing or Managing. It is one choice for the app, not one per app,
    /// because it describes the job the user came to do.
    var mode: Mode = .publishing {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: modeDefaultsKey)
            // The tab of the other mode has no place here. Stores shows in
            // both, so it is always a safe landing.
            if !selectedTab.modes.contains(mode) {
                selectedTab = Tab.tabs(in: mode).first ?? .stores
            }
            openALiveAppForManaging()
        }
    }
    var selectedTab: Tab = .stores {
        didSet {
            guard selectedTab != oldValue else { return }
            if oldValue == .remoteSave { clearRemoteSave() }
            // Leaving a tab is a write boundary, the same as switching app,
            // resigning active, quitting and Command-S. The autosave coalesces
            // for 250 ms, so the last thing typed before a tab was clicked was
            // still waiting, and `pendingListingEdit` holds a draft the
            // manifest has not seen at all: a field typed and then left by
            // clicking another tab lost its last characters.
            //
            // `flushSave` drains both and costs nothing when nothing waits, so
            // this adds no write to a plain tab switch and no timer anywhere.
            flushSave()
            // Picking a tab answers the entry screen: you asked for the two
            // doors and then chose a third thing instead. Without this,
            // pressing "Add app" and changing your mind left the flag set, and
            // the entry screen covered every footer tab you went to next.
            if selectedTab.standsAlone { showEntryScreen = false }
            // A tab names its own mode. Anything that jumps to one, such as
            // the import landing on Build, switches the shell rather than
            // showing a tab the sidebar hides.
            if !selectedTab.modes.contains(mode), let owner = selectedTab.modes.first {
                mode = owner
            }
            // Last of the four, and that ordering is the point. This used to
            // be the second line of the observer, which reported the mode the
            // tab was leaving rather than the one it lands in: clicking a
            // Managing tab from a Publishing one filed the visit under
            // Publishing every time. The two lines above settle both the
            // entry screen and the mode, so reporting after them describes
            // the screen the developer is now looking at.
            trackScreen()
        }
    }

    /// The screen the developer is looking at, which is not always the tab:
    /// the entry screen draws over the content column and leaves the tab
    /// selection standing behind it.
    var currentScreenName: String {
        showsEntryScreen ? "Entry screen" : selectedTab.title
    }

    /// Reports the screen that is on the window now.
    ///
    /// A tab is this app's screen, and the SDK has no screen-view call of its
    /// own: an event is the only unit it sends, so the screen is a property
    /// on one.
    ///
    /// The shell calls this once at launch, which the observer above cannot
    /// do for it. Swift runs no property observer for a value set inside
    /// `init`, and the restore at the foot of this file's initialiser is what
    /// sets the tab a session opens on. So every session reported its *second*
    /// screen first and its first not at all, and a developer who opened the
    /// app to look at one thing and then closed it counted as no screen.
    func trackScreen() {
        Aptabase.shared.trackEvent("screen_view",
                                   with: ["screen": currentScreenName, "mode": mode.rawValue])
    }

    /// A full-screen overlay is a screen too, and none of them is a tab.
    ///
    /// Onboarding is the first thing a new developer sees, the entry screen is
    /// where a session with no app begins, and the import sheet is the whole
    /// of the Managing door. Counting tabs alone measured none of the three.
    ///
    /// The utility sheets stay out of this on purpose. About, the ⌘F palette,
    /// Add locale and the blockers panel are controls *over* a screen rather
    /// than screens, and reporting them would bury the tab they were opened
    /// from under the panel that covered it for four seconds.
    private func trackOverlay(_ name: String, shown: Bool, was: Bool) {
        guard shown, !was else { return }
        Aptabase.shared.trackEvent("screen_view",
                                   with: ["screen": name, "mode": mode.rawValue])
    }

    var selectedAppIndex = 0

    /// What is stopping the release. The header band opens it from any tab,
    /// because the question is asked from every screen and the answer used to
    /// live only at the head of the last one.
    var showBlockers = false
    /// What the app is, who makes it, and how to reach a person. It sits at
    /// the foot of the sidebar and under the app menu, the two places a Mac
    /// user looks for it.
    var showAbout = false
    var showOnboarding = false {
        didSet { trackOverlay("Onboarding", shown: showOnboarding, was: oldValue) }
    }
    var showExistingAppImport = false {
        didSet { trackOverlay("Update existing apps", shown: showExistingAppImport, was: oldValue) }
    }
    /// Shows the entry screen over an app that is already open.
    ///
    /// "Add app" used to open a folder picker, which answers one of the three
    /// doors before the developer has chosen a door. Any app that opens clears
    /// this, so nothing has to remember to put it back.
    var showEntryScreen = false {
        didSet { trackOverlay("Entry screen", shown: showEntryScreen, was: oldValue) }
    }
    /// The index of the app the user asked to remove. It holds the choice
    /// while the confirmation is open.
    var appPendingRemoval: Int?
    var releaseSheet: Store?
    var showAddLocale = false
    /// The ⌘F palette. See FieldSearchSheet and FieldIndex.
    var showFieldSearch = false
    /// The `FieldAnchor` id the content column should scroll to, set together
    /// with `selectedTab` and cleared by the scroll that consumes it.
    var jumpTarget: String?

    /// Opens the tab that holds a field, then asks the scroll to reach it.
    ///
    /// The order matters and is not an accident: the tab has to change first,
    /// so that by the time the content column reacts to `jumpTarget` the
    /// anchor is on a view that is about to exist.
    func jump(to entry: FieldEntry) {
        selectedTab = entry.tab
        jumpTarget = entry.id
    }

    /// Takes every sheet off the shell.
    ///
    /// AppKit refuses to quit an app that has a modal sheet on a window, and
    /// Sparkle installs an update by quitting. "Check for updates" is reachable
    /// from the About panel, which is itself a sheet, so the install waited for
    /// the user to close a panel that nothing on the screen connected to the
    /// update. See Updater.
    ///
    /// Every sheet in `RootView`, and the test below it holds this list to
    /// that: a sheet added to the shell and forgotten here brings the bug
    /// straight back, and it looks like the app simply refusing to quit.
    func closeEverySheet() {
        showAbout = false
        showOnboarding = false
        showExistingAppImport = false
        showAddLocale = false
        showFieldSearch = false
        showSignIn = false
        showBlockers = false
        releaseSheet = nil
    }

    // Paid access. Every gate reads `entitlement`; nothing keeps its own
    // `isPaid` boolean. See AppStateAccess.swift.
    /// The gate every mutation boundary in SubmitKit receives. It refuses
    /// until `configureAccess` replaces it.
    @ObservationIgnored var access: any AccessGate = UnconfiguredAccess()
    @ObservationIgnored var accessController: AccessController?
    @ObservationIgnored var authController: SupabaseAuth?
    var entitlement = Entitlement.free(at: .distantPast)
    var billingPlans: BillingPlans?
    var billingOperation: BillingOperation = .idle
    var billingMessage: String?
    var selectedPlan = "annual"
    var promotionCode = ""
    var promotionPreview: PromotionPreview?
    /// Why this Mac could not verify the document the service sent.
    ///
    /// Only the failures that mean "this build cannot read a real answer", never
    /// "the account has not paid" and never "the network is down". It is the one
    /// state where the app shows Free and the card may already have been
    /// charged, so it is never silent.
    var entitlementProblem: String?
    /// Why the discount code did not take, under the field that holds it.
    ///
    /// Its own value and not `billingMessage`. That one is drawn inside the
    /// identity card at the top of the tab, and the code field is most of a
    /// screen below it, so a refused code wrote its reason somewhere the person
    /// who typed it was not looking. The Apply button read as a dead button.
    var promotionMessage: String?
    /// The address the Supabase account is signed in with.
    ///
    /// Every door that signs a developer in writes it, and signing out clears
    /// it, so it is the one value that says who is using the app.
    var accountEmail: String?
    /// Whether the sign-in form is open beside the Account tab.
    ///
    /// A panel on the right, not a sheet. It was a sheet over a sheet: the
    /// paywall presented it, so a developer signing in from there had two
    /// modal layers between them and the plan they were trying to buy.
    var showSignIn = false
    var accountCreating = false
    var accountEmailInput = ""
    var accountPassword = ""
    var accountBusy = false
    var accountMessage: String?
    @ObservationIgnored var pendingAccountSession: SupabaseSession?
    var pendingAccountEmail: String?

    // Tab 1.
    var appleGuideOpen = false
    var googleGuideOpen = false
    /// Whether a credential card shows its fields, for the developer who said
    /// so by hand. A store that is missing here follows its own connection.
    var credentialOpen: [Store: Bool] = [:]
    var appleKeyID = ""
    var appleIssuerID = ""
    var appleCredentialFileName = ""
    var appleAppID = ""
    var appleBundleID = ""
    var googlePackageName = ""
    var googleCredentialFileName = ""
    var googleAccountEmail = ""
    var googleCredentialChoice: GoogleCredentialChoice = .serviceAccount {
        didSet {
            guard googleCredentialChoice != oldValue else { return }
            defaults.set(googleCredentialChoice.rawValue, forKey: googleCredentialChoiceKey)
            googleConnection = .notConnected
        }
    }
    var appleConnection: ConnectionStatus = .notConnected
    var googleConnection: ConnectionStatus = .notConnected
    var remoteAppleApps: [RemoteStoreApp] = []
    /// The Play apps the connected credential can see.
    ///
    /// The Publishing API is package-scoped and cannot list anything, which is
    /// why this arrived late and why the package name was the one required
    /// identifier with no way in but the keyboard. The Reporting API answers
    /// it, `StoreConnectionClient.googleApps` has read it since the import
    /// sheet was written, and nothing outside that sheet ever asked.
    var remoteGoogleApps: [RemoteStoreApp] = []
    var listingImportStatus: ConnectionStatus = .notConnected
    var confirmsListingImportReplacement = false

    // Tab 2.
    /// Build from Project. upload-spec section 10.
    /// Where the linked projects are kept. Injectable for the same reason
    /// `defaults` and `storeAccount` are: the links are one list for the whole
    /// Mac, so a test that writes the real one unlinks the developer's own
    /// projects. Nothing but a test passes another.
    @ObservationIgnored let buildStorage: BuildStorage
    /// One flow per linked app, so a build is the app's and not the window's.
    ///
    /// It was one flow for the whole window. Nothing cancelled it on a switch
    /// and nothing rebound it, so opening another app handed that app the
    /// controls of the first one's running build: its Build tab drew the other
    /// app's log and its progress, and pressing Build there drove the same run.
    /// The app tabs make that switch a normal thing to do, which is the point of
    /// them, so the flow now belongs to the app it was started on.
    ///
    /// Kept for the life of the window and never pruned. A flow is small, a
    /// developer has a handful of apps, and dropping one would drop a build that
    /// is still running.
    @ObservationIgnored private var buildFlows: [UUID: BuildFlow] = [:]
    /// The open app's flow. A window with no app linked yet still needs one:
    /// the Build tab is reachable before any app exists, and the entry screen
    /// builds from a project that has no `store.yaml` beside it yet.
    var buildFlow: BuildFlow { flow(for: openAppID) }

    /// The app a flow belongs to, or a fixed key while none is open.
    var openAppID: UUID {
        linkedApps.indices.contains(selectedAppIndex)
            ? linkedApps[selectedAppIndex].id
            : Self.unlinkedFlowID
    }

    private static let unlinkedFlowID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()

    private func flow(for id: UUID) -> BuildFlow {
        if let existing = buildFlows[id] { return existing }
        let created = BuildFlow(app: self, owner: id, storage: buildStorage)
        buildFlows[id] = created
        return created
    }

    /// Whether one linked app is the one on screen.
    ///
    /// Every background job asks this before it reads or writes through this
    /// object. A build runs for minutes and the developer is free to open
    /// another tab while it does, so "the app" and "the app in front" are two
    /// different questions and the second one is never the one a running build
    /// means. See `BuildContext`.
    func isOpenApp(_ id: UUID) -> Bool { openAppID == id }

    /// Whether any app other than the open one has a build or a send in flight.
    /// The tab bar draws a mark on those tabs, so work that is no longer on the
    /// screen still says it is happening.
    func isBuilding(appID: UUID) -> Bool {
        buildFlows[appID]?.isBusy ?? false
    }
    /// The Build tab opens on the project builder.
    ///
    /// Importing a package is the answer for a build somebody else produced,
    /// and it was the one the tab opened on, so the ordinary case — this Mac
    /// has the project, build it — was one click away every single time.
    var showBuildFromProject = true
    var buildRead = false
    var packages: [AppPackage.Kind: AppPackage] = [:]
    var packageErrors: [AppPackage.Kind: String] = [:]
    var readingPackages: Set<AppPackage.Kind> = []

    // Tabs 3 and 4.
    var mediaError: String?

    // Managing. The Details, Media, and Marketing tabs write on their own
    // button, so they carry this small state instead of the run state that
    // tab 8 uses. One write runs at a time, and the target says whose message
    // is on the screen.
    var directApplyState: MarketingApplyState = .idle
    var directApplyMessage = ""
    var directApplyTarget: DirectApplyTarget?
    var remoteSaveVisible = false
    var remoteSaveSourceTitle = ""
    var remoteSaveSteps: [PlanStep] = []
    var remoteSaveStepStates: [StepState] = []
    var remoteSaveDetail = ""
    var remoteSaveLogLines: [String] = []
    var remoteSaveLogFullLines: [String] = []
    var remoteSaveLoggedCalls = 0
    @ObservationIgnored
    var remoteSaveContinuation: AsyncStream<RunEvent>.Continuation?
    @ObservationIgnored
    var remoteSaveEventTask: Task<Void, Never>?
    /// The plan the button counts its rows from. `stateGeneration` covers the
    /// store read and the manifest covers the edits, so the pair is the whole
    /// input of a plan. See `directPlan()`.
    @ObservationIgnored
    var directPlanCache: (generation: Int, manifest: Manifest, plan: PlanResult)?

    // The Gaming tab. Its send button uses the direct-apply state above like
    // every other tab; these two belong to the calls beside it that are not a
    // plan at all: a delete, a metric read, and a test submission. One message
    // rather than one per panel, because one of them runs at a time and the
    // panel that started it is the one the developer is looking at.
    var gamingActionMessage = ""
    var gamingActionFailed = false

    // Tab 3.
    var locale = ""
    /// Whether the listing stands in one column instead of one per store.
    ///
    /// Merged is where the tab opens: one box per value, with every store's
    /// budget named over it. Two columns are the study of a listing that
    /// differs by store, they want the width, and a developer who wants them
    /// asks.
    var detailsMerged = true

    // Review info has no such switch. Merging there only stacked two columns
    // that hold different things, so both spellings drew the same boxes and
    // the control answered nothing. See ReviewInfoTab.

    // The YAML toggle that every editing tab holds. Spec 16.1.
    var showYAML = false
    var yamlText = ""
    var yamlDirty = false
    var yamlError: String?

    // Tab 5.
    var provider: Manifest.Provider = .none
    var revenueCatAPIKey = ""
    var revenueCatProjectID = ""
    var revenueCatConnection: ConnectionStatus = .notConnected
    var adaptyConnection: ConnectionStatus = .notConnected
    var priceAmount = ""
    var priceCurrency = ""
    var priceTerritory = ""
    var moneyError: String?
    /// The app and territory pairs whose store money has been read this
    /// launch. See `loadStoreMonetization`.
    private var moneyReadApps: Set<String> = []
    private var purchasePriceInputs: [Int: CatalogPriceInput] = [:]
    private var planPriceInputs: [String: CatalogPriceInput] = [:]
    var offerPriceInputs: [String: CatalogPriceInput] = [:]

    // Tab 6.
    var reviewerUsername = ""
    var reviewerPassword = ""
    /// The one-button read of the reviewer sign-in App Store Connect holds:
    /// whether it is running, and what it has to say when it filled nothing.
    /// See `readDemoAccountFromStore`.
    var demoAccountReading = false
    var demoAccountReadNote: String?
    var showAgeRating = false
    var showDataSafety = false

    // Tab 7. The plan.
    var plan: PlanResult?
    /// The same diff validated one store at a time, so one store's errors do
    /// not disable a run that never calls it.
    var storePlans: [Store: PlanResult] = [:]
    var planReading = false
    /// The app tab whose store values are being replaced by a fresh read.
    var fetchingStoreTab: Tab?

    var isFetchingSelectedTab: Bool { fetchingStoreTab == selectedTab }
    /// The stores that refused the read, one entry each.
    ///
    /// A list and not one joined string. Three stores failing put three
    /// sentences in one banner, and two of them opened with the same twelve
    /// words, so the block read as a paragraph rather than as three problems
    /// with three fixes.
    var planReadFailures: [String] = []

    var planError: String? {
        planReadFailures.isEmpty ? nil : planReadFailures.joined(separator: "\n")
    }
    var dryRun = true
    var acknowledged: Set<String> = []

    // Tab 8. The run.
    var stepStates: [StepState] = []
    var stepMeta: [String] = []
    var runIndex = -1
    var runDone = false
    var runProgress = 0.0
    var runDetail = ""
    /// The last 500 calls, as the box draws them. Cut to the width of the box.
    var logLines: [String] = []
    /// The last `logLimit` calls of the run, whole, for the pasteboard. See
    /// `logText`.
    ///
    /// The build log has held this pair since it froze the window, and the run
    /// log kept only the capped half, so a long run could not be copied whole.
    /// One line per API call and not per line of compiler output, so both
    /// halves are published and the pair costs one more append per call.
    var logFullLines: [String] = []
    /// How many calls this run has made, which is not `logFullLines.count`
    /// once a run passes the cap. The panel counts calls and the copy says how
    /// many of them it left behind, and both need the number that kept
    /// climbing after the array stopped.
    var loggedCalls = 0
    /// The `.jsonl` this run appends to, for the button that reveals it.
    var logFileURL: URL?
    var logOpen = false
    var applied = false
    var runFailure: RunFailure?
    var providerFailure: String?

    // Tab 9. The checklist, the status, and the two buttons.
    var actualState = ActualState()
    /// What the stores hold right now. The import fills it, and so does every
    /// read, and the editing tabs show it beside the value being written.
    var storeSnapshot = StoreSnapshot()
    /// The read of the version App Store review is holding. See AppStateReview.
    var reviewRetrieving = false
    var reviewRetrievalError: String?
    /// App id -> the version state Apple last reported, for every linked app
    /// and not only the open one. See `refreshReviewStates`.
    var appReviewStates: [String: String] = [:]
    /// What a store answered about each linked app, and not only the open one.
    ///
    /// Three answers and not two. True is an app a store has on sale or has
    /// had, false is a read that answered and found none, and a missing key is
    /// an app nobody has asked about. "Nobody asked" is not "not on the store",
    /// the sidebar draws a different word for each, and the Manage side lists
    /// the first of the three. See `isAppLive(appKey:)` and `appStoreMark`.
    ///
    /// Kept in the defaults, unlike `appReviewStates`. A review state is news
    /// of the hour and this one is a fact that stands: the Manage side lists
    /// these apps, and a sidebar that opens empty every morning and fills
    /// itself once a read returns is a sidebar that looks broken.
    var appLiveStates: [String: Bool] = [:]
    var consoleRows: [ConsoleRow] = []
    var consoleMarks: Set<String> = []
    var statuses: [Store: StoreStatus] = [:]
    var releasing: Store?
    var releaseError: String?
    var appleSubmissionID: String?
    var rechecking = false

    /// The vendor number of the App Store account, which only the sales and
    /// the finance reports need.
    ///
    /// It stays in the defaults and out of `store.yaml`. It says nothing about
    /// the listing, it is the same for every app on the account, and a second
    /// developer who clones the repository has a different one.
    var appleVendorNumber = "" {
        didSet {
            guard appleVendorNumber != oldValue else { return }
            defaults.set(appleVendorNumber, forKey: "appleVendorNumber")
        }
    }

    /// The Google Play developer account id, which only the team panel needs.
    ///
    /// It belongs to the account the same way the vendor number does, so it
    /// keeps the same home: the defaults, never `store.yaml`. Google publishes
    /// no method that answers it, so the developer reads it out of the Play
    /// Console URL and it is typed once.
    var googleDeveloperId = "" {
        didSet {
            guard googleDeveloperId != oldValue else { return }
            defaults.set(googleDeveloperId, forKey: "googleDeveloperId")
        }
    }

    /// The app list and the two settings live here. A test passes its own
    /// suite, so a test run never rewrites the real app list.
    @ObservationIgnored let defaults: UserDefaults

    /// The Keychain account of the two store credentials.
    ///
    /// An App Store Connect key belongs to the team, and a Play service
    /// account belongs to the developer account. One of each covers every app,
    /// so the app asks for the `.p8` and the JSON once and every linked app
    /// reads the same copy. The RevenueCat key and the reviewer demo account
    /// describe one app, so they stay under `credentialAccount`.
    ///
    /// A test passes its own name. Apple offers a `.p8` once, so a test run
    /// never writes over the real key.
    @ObservationIgnored let storeAccount: String

    init(defaults: UserDefaults = .standard, storeAccount: String = "store-credentials",
         buildStorage: BuildStorage = BuildStorage()) {
        self.defaults = defaults
        self.storeAccount = storeAccount
        self.buildStorage = buildStorage
        // Each level holds a whole manifest. Fifty covers a work session and
        // caps what a long day of edits can retain.
        undoManager.levelsOfUndo = 50
        // The app decides what one step is, by the pause between edits. Event
        // grouping would decide it instead, and it would put two mutations
        // made by one action into one step and two keystrokes into two.
        undoManager.groupsByEvent = false
        // A coalesced write must not outlive the app or the moment the
        // developer looks somewhere else. Both of these arrive on the main
        // thread before the process goes, and a flush with nothing waiting
        // costs nothing, so this can be blunt.
        for name in [NSApplication.willTerminateNotification,
                     NSApplication.willResignActiveNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushSave() }
            }
        }
        if let data = defaults.data(forKey: linkedAppsDefaultsKey),
           let decoded = try? JSONDecoder().decode([LinkedAppRecord].self, from: data) {
            linkedApps = decoded.filter { FileManager.default.fileExists(atPath: $0.manifestPath) }
        }
        appLiveStates = defaults.dictionary(forKey: liveAppsKey) as? [String: Bool] ?? [:]
        appleVendorNumber = defaults.string(forKey: "appleVendorNumber") ?? ""
        googleDeveloperId = defaults.string(forKey: "googleDeveloperId") ?? ""
        if let value = defaults.string(forKey: googleCredentialChoiceKey),
           let choice = GoogleCredentialChoice(rawValue: value) {
            googleCredentialChoice = choice
        }
        if let saved = defaults.string(forKey: modeDefaultsKey),
           let restored = Mode(rawValue: saved) {
            mode = restored
            selectedTab = Tab.tabs(in: restored).first ?? .stores
        }
        // The app the user worked on last, so a relaunch continues that work
        // and does not open the first app of the list.
        let last = defaults.string(forKey: lastOpenAppKey)
        let index = linkedApps.firstIndex { $0.id.uuidString == last } ?? 0
        if !linkedApps.isEmpty {
            activateLinkedApp(at: index)
        } else {
            // A launch with no app still holds the two store keys, and the
            // Stores tab is reachable without one. Without this line a
            // developer who removed their last app was asked for the .p8 again
            // by an app that had it the whole time.
            loadCredentials()
        }
    }

    var appRows: [AppSummary] {
        return linkedApps.enumerated().map { index, record in
            let url = URL(fileURLWithPath: record.manifestPath)
            let loaded = index == selectedAppIndex ? manifest : (try? ManifestFile.load(from: url))
            let version = loaded?.displayVersionName ?? "No version"
            let selected = index == selectedAppIndex
            let key = appKey(loaded, record: record)
            return AppSummary(
                id: record.id,
                name: record.name,
                initials: Self.initials(for: record.name),
                icon: rowIcon(loaded, root: url.deletingLastPathComponent(),
                              selected: selected),
                summary: "\(version) · \(summary(for: loaded, selected: selected))",
                apple: health(.apple, manifest: loaded, selected: selected),
                google: health(.google, manifest: loaded, selected: selected),
                key: key,
                // The open app answers from the read it already has, which is
                // the freshest answer anywhere: an app that goes live while it
                // is open joins the Manage list on that read rather than on the
                // next launch. Every other row answers from what was learned.
                isLive: (selected && isUpdatingLiveApp) || isAppLive(appKey: key))
        }
    }

    /// The picture beside one app's name, wherever this Mac has one.
    ///
    /// `media.icon` leads: it is a file the developer chose and Play uploads it.
    /// Apple takes no icon file at all, so an App Store app has none of its own
    /// here, and the answer for it is the copy the import downloaded out of the
    /// build. That is in the store snapshot beside `store.yaml`.
    ///
    /// The same rule as the run and as the Media tab: relative to the manifest,
    /// absolute when it says so, and nil when the file is gone. The row then
    /// draws the initials.
    ///
    /// `// ponytail: one snapshot read per unopened row, which is the cost this
    /// // property already pays to read that row's manifest. Cache both together
    /// // if a developer with thirty apps ever feels it.`
    private func rowIcon(_ loaded: Manifest?, root: URL, selected: Bool) -> URL? {
        if let chosen = loaded?.media?.icon.flatMap({ Planner.resolve($0, root: root) }),
           FileManager.default.fileExists(atPath: chosen.path) {
            return chosen
        }
        let snapshot = selected ? storeSnapshot : StoreSnapshot.load(fromRoot: root)
        return snapshot.localIcon(defaultLocale: loaded?.listing?.defaultLocale)
    }

    /// The key one app is remembered under, open or not.
    ///
    /// Its store identifier, because that is what a store answers about, and
    /// the linked record for an app that has neither yet. `currentAppKey` is
    /// this same question about the open app, and the two may not drift: the
    /// sweep writes what it learns under the id it read, and the open app reads
    /// it back under the id in its own manifest.
    /// An id the manifest carries and leaves empty is no id. `apps.apple` is a
    /// block with an empty `appId` for every app whose store row is half
    /// filled, so `??` alone handed all of them the same key: one bucket, and
    /// every app in it wearing whatever the last one learned.
    func appKey(_ loaded: Manifest?, record: LinkedAppRecord?) -> String {
        if let appID = loaded?.apps.apple?.appId, !appID.isEmpty { return appID }
        if let package = loaded?.apps.google?.packageName, !package.isEmpty { return package }
        return record?.id.uuidString ?? "unlinked"
    }

    private func summary(for loaded: Manifest?, selected: Bool) -> String {
        if selected, let plan {
            let count = plan.steps.count
            let errors = plan.errors.count
            if errors > 0 {
                return "\(errors) \(errors == 1 ? "error blocks" : "errors block") the plan"
            }
            // A hold is not a fault, so it does not borrow the word "error".
            if !plan.held.isEmpty { return "waiting on the store" }
            return count == 0 ? "both stores match" : "\(count) changes wait"
        }
        let storeCount = [loaded?.apps.apple != nil, loaded?.apps.google != nil]
            .filter { $0 }.count
        return "\(storeCount) \(storeCount == 1 ? "store" : "stores")"
    }

    /// A dot per store. Only the open app can claim a match, because only the
    /// open app has been read.
    /// Nil for a store this app does not go to. It is not a fault, so the
    /// sidebar shows nothing rather than a red cross.
    private func health(_ store: Store, manifest loaded: Manifest?,
                        selected: Bool) -> StoreHealth? {
        let configured = store == .apple ? loaded?.apps.apple != nil : loaded?.apps.google != nil
        guard configured else { return nil }
        guard selected, let plan else { return .changed }
        let scoped = storePlans[store] ?? plan
        // The dot describes this store. A failure in the other store does not
        // block this one's apply and therefore cannot paint this one red.
        guard scoped.errors.isEmpty else { return .blocked }
        let system: PlanSystem = store == .apple ? .apple : .google
        return scoped.steps(for: system).isEmpty ? .matched : .changed
    }

    // MARK: - The YAML toggle

    /// The raw block behind the open tab, or nil for a tab that edits nothing.
    var yamlBlock: ManifestBlock? {
        switch selectedTab {
        case .stores: .stores
        case .build: .build
        case .details: .details
        case .media: .media
        case .gaming: .gaming
        case .availability: .availability
        case .money: .money
        case .marketing: .marketing
        case .reviewInfo: .reviewInfo
        default: nil
        }
    }

    func loadYAML(_ block: ManifestBlock) {
        do {
            yamlText = try ManifestFile.encode(manifest, block: block)
            yamlDirty = false
            yamlError = nil
        } catch {
            yamlError = error.localizedDescription
        }
    }

    /// Both sides edit the same file, so a save here goes through the same
    /// decoder that a load uses. A block that does not parse changes nothing.
    func saveYAML(_ block: ManifestBlock) {
        do {
            manifest = try ManifestFile.apply(yamlText, block: block, to: manifest)
            // The raw side edits the same file, so it takes the same step back.
            registerManifestUndo()
            try save()
            syncStoreFieldsFromManifest()
            syncEditingStateFromManifest()
            if manifest.listing?.locales[locale] == nil {
                locale = manifest.listing?.defaultLocale ?? locale
            }
            yamlDirty = false
            yamlError = nil
            invalidatePlan()
        } catch {
            yamlError = error.localizedDescription
        }
    }

    /// Spec 16.5. The settings panel names the manifest, and this opens it.
    func revealManifest() {
        guard let manifestURL else { return }
        // The developer is about to read the file, so it says what the screen
        // says.
        flushSave()
        NSWorkspace.shared.activateFileViewerSelecting([manifestURL])
    }

    var currentApp: AppSummary? {
        guard appRows.indices.contains(selectedAppIndex) else { return nil }
        return appRows[selectedAppIndex]
    }

    var stores: Set<Store> {
        var result: Set<Store> = []
        if manifest.apps.apple != nil { result.insert(.apple) }
        if manifest.apps.google != nil { result.insert(.google) }
        return result
    }

    /// The stores this app goes to, as words.
    var storeListText: String {
        let names = stores.sorted { $0.rawValue < $1.rawValue }.map(\.storeName)
        guard !names.isEmpty else { return "the stores" }
        guard names.count > 1 else { return names[0] }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// No app is open, or the developer asked for the entry screen over one.
    ///
    /// The sidebar reads this to decide whether the per-app tabs are worth
    /// drawing at all.
    var hasNoOpenApp: Bool { manifestURL == nil || showEntryScreen }

    /// Whether the content pane is showing the two doors instead of a tab.
    ///
    /// The shell branched on this expression in three places and each one
    /// wrote it again. The header, the pane, and the sidebar have to agree:
    /// a sidebar offering nine per-app tabs beside a screen that says "pick an
    /// app" offers nine places that cannot work.
    ///
    /// `showEntryScreen` is the developer asking for it, and it always wins.
    /// Without that first line "Add app" did nothing at all while a footer tab
    /// was open: it set the flag, the flag lost to the exception below, and the
    /// pane kept drawing Stores. Entering a credential leaves you on Stores, so
    /// that was the state almost everyone was in when they went to add an app.
    ///
    /// The exception below is only for the implicit case, no app linked.
    /// Account and Stores stand on their own there: neither is about an app,
    /// and sending someone to "pick an app" before they can sign in or enter a
    /// key is a door that leads back to the door.
    var showsEntryScreen: Bool {
        if showEntryScreen { return true }
        return manifestURL == nil && !selectedTab.standsAlone
    }

    /// Whether the shell shows the armed-write strip.
    ///
    /// Publishing alone. A Managing tab writes on its own button, which asks
    /// first every time and never reads the dry run.
    var showsLiveWriteWarning: Bool {
        mode == .publishing && manifestURL != nil && !dryRun && !stores.isEmpty
    }

    var locales: [String] {
        manifest.listing?.locales.keys.sorted() ?? []
    }

    // MARK: - Linked apps and manifest editing

    func selectApp(at index: Int) {
        selectedAppIndex = index
        guard !linkedApps.isEmpty else { return }
        activateLinkedApp(at: index)
        // The tab stays where it is, for every caller now. Pressing an app in
        // the sidebar used to open that app's store page, which meant switching
        // app also moved you off whatever you were reading. The apps are a tab
        // bar across the top of the window, and a tab bar changes which app you
        // are working on and not which screen of it you are looking at, so
        // comparing one app's Details with another's is two clicks.
        // Where App Store review has each of them. Picking an app is the
        // moment a developer needs to know whether this one is frozen, and
        // whether the others are, so the sweep runs on every change as well as
        // at launch. See `SuperSubmitterApp` for the launch half: without it
        // the status column opened empty and filled only once something had
        // been clicked.
        Task { await refreshReviewStates() }
    }

    /// Leaves an app the Manage side does not list, for one it does.
    ///
    /// The same rule the mode already follows for a tab, one level up:
    /// Managing runs the app that is already live, so a draft is not one of its
    /// apps and the sidebar stops listing it there. Without this the developer
    /// arrived on the Manage tabs of an app the column beside them had just
    /// stopped showing, with the tick nowhere and the live listing of an app
    /// that has no customers.
    ///
    /// It moves only when there is somewhere to go. A developer whose apps are
    /// all drafts has nothing to manage, and putting them on another draft
    /// would be a move that changes nothing.
    private func openALiveAppForManaging() {
        guard mode == .managing, !linkedApps.isEmpty else { return }
        let rows = appRows
        guard !(rows.indices.contains(selectedAppIndex) && rows[selectedAppIndex].isLive),
              let next = rows.firstIndex(where: \.isLive) else { return }
        selectApp(at: next)
    }

    /// The name in the removal question, so the user reads which app leaves.
    var removalName: String {
        guard let index = appPendingRemoval, linkedApps.indices.contains(index) else {
            return "this app"
        }
        return linkedApps[index].name
    }

    func askToRemoveApp(at index: Int) {
        guard linkedApps.indices.contains(index) else { return }
        appPendingRemoval = index
    }

    func removePendingApp() {
        guard let index = appPendingRemoval else { return }
        appPendingRemoval = nil
        removeLinkedApp(at: index)
    }

    /// Takes the app out of the list, and out of nothing else.
    ///
    /// The `store.yaml` file stays in its folder, the Keychain keeps the store
    /// keys, and neither store hears about it. The user opens the same file
    /// again through "Open store.yaml…" whenever they want it back.
    func removeLinkedApp(at index: Int) {
        guard linkedApps.indices.contains(index) else { return }
        linkedApps.remove(at: index)
        persistLinkedApps()
        guard !linkedApps.isEmpty else {
            // The two store keys stay. They belong to the team and the
            // developer account, not to the app that happened to enter them,
            // and only "Forget" on the Stores tab removes one. This clears the
            // RevenueCat key and the reviewer account, which do describe one
            // app, and reloads the two that do not.
            loadCredentials()
            manifest = Manifest()
            manifestURL = nil
            resetUndo()
            selectedAppIndex = 0
            selectedTab = .stores
            locale = ""
            packages = [:]
            packageErrors = [:]
            buildRead = false
            syncStoreFieldsFromManifest()
            syncEditingStateFromManifest()
            resetRunState()
            return
        }
        activateLinkedApp(at: min(index, linkedApps.count - 1))
    }

    /// The one way in. The user picks the folder of an app that already exists.
    /// We open the `store.yaml` that is already there, or we write a new one.
    ///
    /// Nobody who has built an app wants to "create a new app", so the app
    /// never asks for one. It asks for the folder and does the rest.
    func chooseAppFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select your app folder"
        panel.explain("Choose the folder of your app. store.yaml goes inside it.")
        panel.prompt = "Select"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try ManifestFile.save(Manifest(), to: url)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        link(manifestAt: url)
    }

    /// The second door, for a folder that already carries the file but is not
    /// linked on this Mac yet.
    func chooseExistingManifest() {
        let panel = NSOpenPanel()
        panel.title = "Continue work on an app"
        panel.explain("Choose the store.yaml file of the app you want to continue.")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        link(manifestAt: url)
    }

    /// Both doors end here: read the file, add it once, and select it.
    func link(manifestAt url: URL, awaitingProjectFolder: Bool = false) {
        do {
            let loaded = try ManifestFile.load(from: url)
            if let index = linkedApps.firstIndex(where: { $0.manifestPath == url.path }) {
                activateLinkedApp(at: index)
                selectedTab = .stores
                return
            }
            let defaultLocale = loaded.listing?.defaultLocale
            let listedName = defaultLocale.flatMap { loaded.listing?.locales[$0]?.name }
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let name = listedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = if let name, !name.isEmpty {
                name
            } else {
                Self.displayName(from: folderName)
            }
            let record = LinkedAppRecord(
                id: UUID(),
                name: displayName,
                manifestPath: url.path,
                awaitingProjectFolder: awaitingProjectFolder)
            linkedApps.append(record)
            persistLinkedApps()
            activateLinkedApp(at: linkedApps.count - 1)
            selectedTab = .stores
            // What the stores hold for this one app, asked once, here. Linking
            // is the moment a developer hands the app over, it is the only
            // moment that names one app rather than all of them, and both
            // stores answer for the price of the app being added.
            //
            // After `activateLinkedApp`, which loads this app's keys out of the
            // Keychain. A read fired before that line would sign with whatever
            // the app before it used.
            Task { await readAppLiveness(for: record) }
        } catch {
            errorMessage = "That file is not a valid store file. \(error.localizedDescription)"
        }
    }

    func addLocale(_ rawCode: String) -> Bool {
        let code = Self.normalizedLocale(rawCode)
        guard Self.isValidLocale(code) else {
            errorMessage = "Use a locale such as en-US, pt-BR, ja, or zh-Hans."
            return false
        }
        guard manifest.listing?.locales[code] == nil else {
            locale = code
            return true
        }
        manifest.addLocale(code)
        locale = code
        saveManifestReportingErrors()
        return true
    }

    func setStore(_ store: Store, enabled: Bool) {
        manifest.setStore(store, enabled: enabled)
        syncStoreFieldsFromManifest()
        saveManifestReportingErrors()
    }

    func updateAppleAppFields() {
        guard stores.contains(.apple) else { return }
        manifest.setAppleApp(appID: appleAppID.trimmingCharacters(in: .whitespacesAndNewlines),
                             bundleID: appleBundleID.trimmingCharacters(in: .whitespacesAndNewlines),
                             platforms: manifest.apps.apple?.platforms ?? [.ios])
        saveManifestReportingErrors()
    }

    /// Which platform's listing this app is. It leads `platforms`, and
    /// everything that reads a version reads that first entry.
    ///
    /// An app on iOS and macOS holds a version train per platform under one
    /// app id, with its own numbers, its own text, and its own screenshots.
    /// Nothing chose between them: the import wrote the platforms it found in
    /// `Platform.allCases` order and every read took `.first`, so a universal
    /// app silently got its iOS train and a developer publishing the Mac one
    /// saw an empty Media tab with nothing to explain it.
    var applePlatform: Manifest.Platform {
        get { manifest.apps.apple?.platforms.first ?? .ios }
        set {
            guard let apple = manifest.apps.apple else { return }
            var platforms = apple.platforms.filter { $0 != newValue }
            platforms.insert(newValue, at: 0)
            manifest.setAppleApp(appID: apple.appId, bundleID: apple.bundleId,
                                 platforms: platforms)
            saveManifestReportingErrors()
            // The snapshot and the plan were read against the other train.
            storeSnapshot = StoreSnapshot()
            storeSnapshot.save(toRoot: manifestRoot)
            invalidatePlan()
        }
    }

    /// The platforms this app ships on, when there is more than one to choose
    /// between. One platform needs no picker.
    var appleplatformChoices: [Manifest.Platform] {
        let platforms = manifest.apps.apple?.platforms ?? []
        return platforms.count > 1 ? Manifest.Platform.allCases.filter(platforms.contains) : []
    }

    func updateGoogleAppFields() {
        guard stores.contains(.google) else { return }
        manifest.setGoogleApp(packageName: googlePackageName.trimmingCharacters(in: .whitespacesAndNewlines))
        saveManifestReportingErrors()
    }

    // MARK: - Credentials

    func importAppleCredential(from url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            applePrivateKeyPEM = try String(contentsOf: url, encoding: .utf8)
            appleCredentialFileName = url.lastPathComponent
            // Apple names the file after the key, so a typed id is usually
            // unnecessary. One the user already typed always wins.
            if appleKeyID.trimmingCharacters(in: .whitespaces).isEmpty,
               let keyID = AppleCredential.keyID(fromFileName: url.lastPathComponent) {
                appleKeyID = keyID
            }
            try persistAppleCredential()
            if !stores.contains(.apple) { setStore(.apple, enabled: true) }
            appleConnection = .notConnected
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importGoogleCredential(from url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let credential = try GoogleServiceAccount(
                data: Data(contentsOf: url), fileName: url.lastPathComponent)
            try KeychainCredentials.save(credential, kind: .google,
                                         account: storeAccount)
            googleCredential = credential
            googleCredentialChoice = .serviceAccount
            if !stores.contains(.google) { setStore(.google, enabled: true) }
            googleCredentialFileName = url.lastPathComponent
            googleAccountEmail = credential.clientEmail
            googleConnection = .notConnected
        } catch {
            errorMessage = "That service-account file could not be imported. \(error.localizedDescription)"
        }
    }

    func appleCredentialFieldsChanged() {
        guard !applePrivateKeyPEM.isEmpty else { return }
        do { try persistAppleCredential() }
        catch { errorMessage = error.localizedDescription }
        appleConnection = .notConnected
    }

    /// Checks the keys the Keychain already holds, once, at launch.
    ///
    /// The two connection states live in memory and start at `.notConnected`,
    /// so every launch opened on "App Store is not connected" beside a key id,
    /// an issuer id and the name of the `.p8` the app had just read back out of
    /// the Keychain. Nothing was missing and nothing had expired: the app had
    /// simply not asked yet, and it made the developer ask for it, every day,
    /// on a screen that had every answer already.
    ///
    /// It presses the same button. A refusal is the refusal that button
    /// reports, because a key that stopped working overnight is news whether or
    /// not anybody asked, and a launch is exactly when it is cheapest to hear.
    ///
    /// Google's OAuth route is not checked. Connecting there opens a browser
    /// authorization window, and a window that opens itself at launch is not a
    /// check, it is an interruption.
    func verifyStoredConnections() {
        if appleConnection == .notConnected, !applePrivateKeyPEM.isEmpty,
           !appleKeyID.isEmpty, !appleIssuerID.isEmpty {
            connectAppleStore()
        }
        if googleConnection == .notConnected, googleCredentialChoice == .serviceAccount,
           googleCredential != nil {
            connectGoogleStore()
        }
    }

    /// Saves the key, then calls App Store Connect with it. The button that
    /// runs this says Connect, and both halves are why.
    func connectAppleStore() {
        guard !applePrivateKeyPEM.isEmpty else {
            appleConnection = .failed("Choose the .p8 private key first.")
            return
        }
        guard !appleKeyID.isEmpty, !appleIssuerID.isEmpty else {
            appleConnection = .failed("Enter the key id and issuer id.")
            return
        }
        let credential = AppleCredential(keyID: appleKeyID, issuerID: appleIssuerID,
                                         privateKeyPEM: applePrivateKeyPEM,
                                         fileName: appleCredentialFileName)
        let generation = stateGeneration
        appleConnection = .connecting
        Task {
            do {
                try KeychainCredentials.save(credential, kind: .apple,
                                             account: storeAccount)
                let apps = try await StoreConnectionClient().appleApps(credential: credential)
                guard generation == stateGeneration else { return }
                remoteAppleApps = apps
                adoptTheOnlyVisibleApp(.apple)
                let suffix = apps.count == 1 ? "app" : "apps"
                appleConnection = .connected("Connected · \(apps.count) \(suffix) visible")
            } catch {
                guard generation == stateGeneration else { return }
                appleConnection = .failed(error.localizedDescription)
            }
        }
    }

    func connectGoogleStore() {
        if googleCredentialChoice == .oauth {
            connectGoogleOAuth()
            return
        }
        guard let credential = googleCredential else {
            googleConnection = .failed("Choose the service-account JSON first.")
            return
        }
        let generation = stateGeneration
        googleConnection = .connecting
        Task {
            do {
                try KeychainCredentials.save(credential, kind: .google,
                                             account: storeAccount)
                await readVisibleGoogleApps(generation: generation) {
                    try await StoreConnectionClient().googleApps(credential: credential)
                }
                let message = try await StoreConnectionClient().testGoogle(
                    credential: credential, packageName: googlePackageName)
                guard generation == stateGeneration else { return }
                googleConnection = .connected(message)
            } catch {
                guard generation == stateGeneration else { return }
                googleConnection = .failed(error.localizedDescription)
            }
        }
    }

    /// Reads the apps a Play credential can see, and never fails the connect
    /// over it.
    ///
    /// The listing needs the Play Developer Reporting API switched on for the
    /// project, and the Publishing API works whether or not it is. A developer
    /// who has one and not the other stays connected and types the package
    /// name, which is what everybody did before this read existed.
    private func readVisibleGoogleApps(
        generation: Int,
        _ read: @Sendable () async throws -> [RemoteStoreApp]
    ) async {
        guard let apps = try? await read(), generation == stateGeneration else { return }
        remoteGoogleApps = apps
        adoptTheOnlyVisibleApp(.google)
    }

    /// Fills an identifier the store just answered, when there is only one
    /// answer and nothing to overwrite.
    ///
    /// One visible app is not a choice, and presenting it as one asked the
    /// developer to confirm a fact the app had already read. More than one is
    /// a real choice and the picker makes it. A value already on screen is
    /// never touched: a typed identifier is a decision, and a read is not
    /// grounds to undo it.
    func adoptTheOnlyVisibleApp(_ store: Store) {
        switch store {
        case .apple:
            guard remoteAppleApps.count == 1, let app = remoteAppleApps.first,
                  appleAppID.isEmpty, appleBundleID.isEmpty else { return }
            chooseRemoteAppleApp(app)
        case .google:
            guard remoteGoogleApps.count == 1, let app = remoteGoogleApps.first,
                  googlePackageName.isEmpty else { return }
            chooseRemoteGoogleApp(app)
        }
    }

    func chooseRemoteGoogleApp(_ app: RemoteStoreApp) {
        googlePackageName = app.identifier
        updateGoogleAppFields()
    }

    private func connectGoogleOAuth() {
        guard let clientID = GoogleOAuthConfiguration.clientID
                ?? googleOAuthCredential?.clientID else {
            googleConnection = .notConnected
            errorMessage = "This build needs a Google OAuth desktop client ID before it can connect."
            return
        }
        googleConnection = .connecting
        Task {
            do {
                let credential = try await GoogleOAuthSession.authorize(clientID: clientID)
                try KeychainCredentials.save(credential, kind: .googleOAuth,
                                             account: storeAccount)
                googleOAuthCredential = credential
                if !stores.contains(.google) { setStore(.google, enabled: true) }
                await readVisibleGoogleApps(generation: stateGeneration) {
                    try await StoreConnectionClient().googleApps(credential: credential)
                }
                let message = try await StoreConnectionClient().testGoogle(
                    credential: credential, packageName: googlePackageName)
                googleConnection = .connected(message)
            } catch is CancellationError {
                googleConnection = .notConnected
            } catch {
                googleConnection = .failed(error.localizedDescription)
            }
        }
    }

    func chooseRemoteAppleApp(_ app: RemoteStoreApp) {
        appleAppID = app.id
        appleBundleID = app.identifier
        updateAppleAppFields()
    }

    func importExistingListing(replacingLocalData: Bool = false) {
        if stores.contains(.apple),
           (applePrivateKeyPEM.isEmpty || appleKeyID.isEmpty || appleIssuerID.isEmpty || appleAppID.isEmpty) {
            listingImportStatus = .failed("Connect App Store and choose an app on Stores first.")
            return
        }
        if stores.contains(.google), (!hasCredential(for: .google) || googlePackageName.isEmpty) {
            listingImportStatus = .failed("Connect Google Play and enter its package name on Stores first.")
            return
        }

        guard replacingLocalData else {
            confirmsListingImportReplacement = true
            return
        }

        let appleCredential = AppleCredential(
            keyID: appleKeyID, issuerID: appleIssuerID,
            privateKeyPEM: applePrivateKeyPEM, fileName: appleCredentialFileName)
        let credentials = credentials
        listingImportStatus = .connecting
        Task {
            do {
                let client = StoreConnectionClient()
                if stores.contains(.apple) {
                    let imported = try await client.importApple(
                        appID: appleAppID, credential: appleCredential,
                        platform: manifest.apps.apple?.platforms.first?.rawValue)
                    manifest.mergeAppleImport(imported)
                    await adopt(imported, store: .apple)
                }
                if stores.contains(.google) {
                    let imported = try await StoreImportReader(credentials: credentials)
                        .google(packageName: googlePackageName)
                    manifest.mergeGoogleImport(imported)
                    await adopt(imported, store: .google)
                }
                // An import rewrites the listing wholesale, so it is the edit
                // a developer most often wants back.
                registerManifestUndo()
                try save()
                invalidatePlan()
                storeSnapshot.save(toRoot: manifestURL?.deletingLastPathComponent())
                locale = manifest.listing?.defaultLocale ?? locale
                updateLinkedAppNameFromManifest()
                await readStores()
                let count = manifest.listing?.locales.count ?? 0
                if let version = actualState.apple?.versionString,
                   actualState.apple?.attachedBuildId != nil {
                    listingImportStatus = .connected(
                        "Imported App Store draft \(version) with its attached build and \(count) \(count == 1 ? "locale" : "locales") into store.yaml")
                } else {
                    listingImportStatus = .connected(
                        "Imported \(count) \(count == 1 ? "locale" : "locales") into store.yaml")
                }
            } catch {
                listingImportStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Packages

    func importPackages(from urls: [URL]) {
        for url in urls { importPackage(from: url) }
    }

    func importPackage(from url: URL) {
        guard let kind = AppPackage.Kind(rawValue: url.pathExtension.lowercased()) else {
            errorMessage = PackageError.unknownType(url.pathExtension).localizedDescription
            return
        }
        readingPackages.insert(kind)
        packageErrors[kind] = nil
        Task {
            do {
                let package = try await Task.detached(priority: .userInitiated) {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    return try PackageReader().read(url)
                }.value
                packages[kind] = package
                readingPackages.remove(kind)
                buildRead = true
                manifest.apply(package: package, path: manifestPath(for: url))
                syncStoreFieldsFromManifest()
                saveManifestReportingErrors()
                // The file says which train this release is for. A .pkg under
                // an app id whose manifest still named iOS sent every listing
                // write to the iOS version while the binary went to the Mac
                // one. See `BuildFlow.adoptAppleTrain` for the other door into
                // the same room.
                switch kind {
                case .pkg where applePlatform != .macOS: applePlatform = .macOS
                case .ipa where applePlatform != .ios: applePlatform = .ios
                default: break
                }
            } catch {
                readingPackages.remove(kind)
                packageErrors[kind] = error.localizedDescription
            }
        }
    }

    func chooseBuildFiles(allowedExtensions: Set<String>) {
        let panel = NSOpenPanel()
        panel.title = "Choose a build"
        panel.explain("Choose \(allowedExtensions.sorted().map { ".\($0)" }.joined(separator: " or ")).")
        panel.allowsMultipleSelection = allowedExtensions.count > 1
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        importPackages(from: panel.urls)
    }

    /// Chooses one file and answers its URL. The build picker imports and
    /// parses; this one only names a path, because the artifacts next to a
    /// build carry no metadata that the app reads.
    func chooseOneFile(allowedExtensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a file"
        panel.explain("Choose \(allowedExtensions.sorted().map { ".\($0)" }.joined(separator: " or ")).")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// A path relative to the manifest, when the file sits under it. The
    /// manifest travels in a repository, so an absolute path from one machine
    /// is useless on the next.
    func relativePath(for url: URL) -> String {
        guard let root = manifestRoot?.standardizedFileURL.path else { return url.path }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    /// The note a path field shows, or nil while the path is good or empty.
    ///
    /// `Planner.resolve` is the rule the Validator already runs for the
    /// Summary tab, so the field and the plan can never disagree. It ran only
    /// there, which put the fault three tabs away from the box that caused it.
    func missingFileNote(for path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard Planner.resolve(trimmed, root: manifestRoot) == nil else { return nil }
        return "No file sits at this path."
    }

    /// The same check for a build the manifest names but no longer has.
    ///
    /// The well shows the file a drop read this session. A build named by an
    /// earlier session and since moved left the well looking empty and healthy.
    func missingBuildNote(_ kind: AppPackage.Kind) -> String? {
        let path: String? = switch kind {
        case .ipa: manifest.release?.build?.ios
        case .pkg: manifest.release?.build?.macos
        case .aab: manifest.release?.build?.android
        }
        guard let path, !path.isEmpty, missingFileNote(for: path) != nil else { return nil }
        return "The manifest names \(path), and no file sits there."
    }

    func useReleaseVersion(_ version: String) {
        manifest.setReleaseVersionName(version)
        saveManifestReportingErrors()
    }

    /// The number this submission carries.
    ///
    /// It arrived from a package and from an import, and from nowhere else:
    /// no tab took one. An update with no build attached yet therefore kept
    /// whatever the import had read, the Summary said "Version 1.2 is not
    /// above 1.4", and its Fix button opened a tab with no version on it.
    /// The shared key first, then the only store's own, because an app with one
    /// store cannot disagree with itself about its own number.
    ///
    /// The fallback is what this field was missing. Every writer that names a
    /// store, and the listing import is the one a developer meets first, writes
    /// `release.apple.versionName` and clears the shared key: that is right for
    /// two stores that number apart. This field is the one an app with a single
    /// store gets, it read the shared key alone, and so the fetch that had just
    /// read 1.6 off App Store Connect left the box empty and showing its own
    /// "1.0" placeholder. The number was in `store.yaml` the whole time, which
    /// is why the build below it went on saying 1.6.
    var releaseVersionBinding: Binding<String> {
        Binding(
            get: {
                if let shared = self.manifest.release?.versionName, !shared.isEmpty {
                    return shared
                }
                guard self.stores.count == 1, let only = self.stores.first else { return "" }
                return self.manifest.versionName(for: only) ?? ""
            },
            set: {
                self.manifest.setReleaseVersionName($0)
                self.saveManifestReportingErrors()
            })
    }

    /// The number one store is being given.
    ///
    /// The two stores do not number together. An app that shipped on the App
    /// Store first is on 1.4.1 there and on 1.0.0 in Play, and one field for
    /// both of them refused the Android upload against a number Apple owns.
    func releaseVersionBinding(for store: Store) -> Binding<String> {
        Binding(
            get: { self.manifest.versionName(for: store) ?? "" },
            set: {
                self.manifest.setReleaseVersionName($0, for: store)
                self.saveManifestReportingErrors()
            })
    }

    /// Whether one number covers both stores. See `Manifest.sharesOneVersion`.
    ///
    /// Setting it is the developer answering "are these the same release?".
    /// Sharing takes the App Store's number where there is one, because that
    /// is the store whose number a customer sees first, and gives it to both.
    /// Splitting hands each store the number it already had.
    var sharesOneVersion: Bool {
        get { manifest.sharesOneVersion }
        set {
            let apple = manifest.versionName(for: .apple) ?? ""
            let google = manifest.versionName(for: .google) ?? ""
            if newValue {
                manifest.setReleaseVersionName(apple.isEmpty ? google : apple)
            } else {
                manifest.setReleaseVersionName(apple, for: .apple)
                manifest.setReleaseVersionName(google, for: .google)
            }
            saveManifestReportingErrors()
        }
    }

    /// Whether the tab has two versions to draw at all. One store is one
    /// number, and a checkbox offering to share it with nobody is a control
    /// that does nothing.
    var showsVersionPerStore: Bool { stores.count > 1 }

    /// What the App Store shows customers, once a read has said so.
    var liveAppleVersion: String? { actualState.apple?.liveVersionString }

    /// The smallest number that clears the one on sale. Apple refuses a
    /// version that does not climb, and the patch component is the one a fix
    /// usually moves. See `Validator.nextVersion(above:)`.
    var nextAppleVersion: String? {
        liveAppleVersion.flatMap(Validator.nextVersion(above:))
    }

    /// Gives the App Store a release version, and leaves Google's alone.
    ///
    /// Through the shared key while one number covers both stores, so an app
    /// that releases to the two together keeps doing so and the checkbox on the
    /// Build tab still reads as ticked. Splitting them here would answer "are
    /// these the same release?" on the developer's behalf.
    func setAppleReleaseVersion(_ version: String) {
        if sharesOneVersion {
            manifest.setReleaseVersionName(version)
        } else {
            manifest.setReleaseVersionName(version, for: .apple)
        }
        saveManifestReportingErrors()
    }

    // MARK: - Listing details

    func listingBinding(_ field: ListingTextField, locale code: String? = nil) -> Binding<String> {
        let localeCode = code ?? locale
        return Binding(
            get: { self.manifest.listingText(locale: localeCode, field: field) },
            set: { value in
                self.manifest.setListingText(value, locale: localeCode, field: field)
                if field == .name, localeCode == self.manifest.listing?.defaultLocale {
                    self.updateLinkedAppNameFromManifest()
                }
                self.saveManifestReportingErrors()
            })
    }

    func googleOverrideBinding(_ field: ListingTextField) -> Binding<Bool> {
        let localeCode = locale
        return Binding(
            get: { self.manifest.hasGoogleOverride(locale: localeCode, field: field) },
            set: { enabled in
                self.manifest.setGoogleOverride(enabled, locale: localeCode, field: field)
                self.saveManifestReportingErrors()
            })
    }

    // MARK: - Media

    func mediaPaths(deviceClass: Manifest.DeviceClass, previews: Bool = false,
                    store: Store? = nil) -> [String] {
        manifest.mediaPaths(locale: locale, deviceClass: deviceClass,
                            previews: previews, store: store)
    }

    /// Whether this size holds one list for both stores or one each.
    func mediaIsSplit(_ deviceClass: Manifest.DeviceClass) -> Bool {
        Store.allCases.contains {
            manifest.hasStoreScreenshots(locale: locale, deviceClass: deviceClass, store: $0)
        }
    }

    func splitMedia(_ deviceClass: Manifest.DeviceClass) {
        manifest.splitMedia(locale: locale, deviceClass: deviceClass)
        saveManifestReportingErrors()
    }

    func mergeMedia(_ deviceClass: Manifest.DeviceClass) {
        manifest.mergeMedia(locale: locale, deviceClass: deviceClass)
        saveManifestReportingErrors()
    }

    /// Gives every size that holds pictures a list per store, when the app
    /// ships on both.
    ///
    /// The Media tab shows a column per store, so the sizes behind it are per
    /// store too. It runs on opening the tab and on changing language.
    ///
    /// Only the sizes that hold something. An override is an answer, and an
    /// empty one says "send this store nothing for this size" — writing those
    /// across seven device classes on a tab visit would fill the manifest with
    /// decisions nobody made, and quietly stop a later shared edit reaching
    /// either store.
    func splitMediaForThisLocale() {
        guard stores.count > 1 else { return }
        var changed = false
        for deviceClass in Manifest.DeviceClass.allCases
        where !mediaPaths(deviceClass: deviceClass).isEmpty && !mediaIsSplit(deviceClass) {
            manifest.splitMedia(locale: locale, deviceClass: deviceClass)
            changed = true
        }
        if changed { saveManifestReportingErrors() }
    }

    /// The two graphics Google asks for and Apple does not.
    ///
    /// The App Store reads its icon out of the build. Google Play refuses a
    /// listing without both of these, the planner has always uploaded them and
    /// the validator has always checked their exact sizes, and until now the
    /// only thing that ever wrote them was an import of a listing that already
    /// had them. A first Play submission had nowhere to name either file.
    enum GoogleGraphic: CaseIterable {
        case icon, featureGraphic

        var label: String {
            switch self {
            case .icon: "App icon"
            case .featureGraphic: "Feature graphic"
            }
        }

        var note: String {
            switch self {
            case .icon: "512 by 512, PNG"
            case .featureGraphic: "1024 by 500"
            }
        }

        var extensions: [String] {
            switch self {
            case .icon: ["png"]
            case .featureGraphic: ["png", "jpg", "jpeg"]
            }
        }
    }

    func googleGraphicBinding(_ graphic: GoogleGraphic) -> Binding<String> {
        Binding(get: {
            switch graphic {
            case .icon: self.manifest.media?.icon ?? ""
            case .featureGraphic: self.manifest.media?.featureGraphic ?? ""
            }
        }, set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored: String? = trimmed.isEmpty ? nil : trimmed
            if self.manifest.media == nil { self.manifest.media = Manifest.Media() }
            switch graphic {
            case .icon: self.manifest.media?.icon = stored
            case .featureGraphic: self.manifest.media?.featureGraphic = stored
            }
            self.saveManifestReportingErrors()
        })
    }

    /// A media path against the manifest's own folder. `Planner.resolve` is
    /// the same rule for the run, and this one answers even when the file is
    /// gone, because a tile still names a screenshot that moved.
    ///
    /// The test reads the path, not the URL. `URL(fileURLWithPath:)` resolves
    /// a relative path against the working directory of the process, so the
    /// URL is absolute either way and asking it "are you absolute" answered
    /// yes for every path. Every relative path, which is what the app itself
    /// writes, then pointed at the working directory and the tile drew an
    /// empty box.
    func mediaURL(for path: String) -> URL {
        guard !path.hasPrefix("/") else { return URL(fileURLWithPath: path) }
        return manifestRoot?.appendingPathComponent(path) ?? URL(fileURLWithPath: path)
    }

    func imageInfo(for path: String) -> ImageAssetInfo? {
        try? AssetInspector.image(at: mediaURL(for: path))
    }

    func imageStores(for path: String, deviceClass: Manifest.DeviceClass) -> Set<Store> {
        guard let info = imageInfo(for: path) else { return [] }
        return (try? AssetInspector.compatibleStores(
            for: info, deviceClass: deviceClass, selectedStores: stores)) ?? []
    }

    func chooseMediaFiles(deviceClass: Manifest.DeviceClass, previews: Bool = false,
                          store: Store? = nil) {
        let panel = NSOpenPanel()
        panel.title = previews ? "Choose app previews" : "Choose screenshots"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let extensions = previews ? ["mov", "m4v", "mp4"] : ["png", "jpg", "jpeg"]
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        addMediaFiles(panel.urls, deviceClass: deviceClass, previews: previews, store: store)
    }

    func addMediaFiles(_ urls: [URL], deviceClass: Manifest.DeviceClass,
                       previews: Bool = false, store: Store? = nil) {
        // A picture dropped on one store's column belongs to that store, so
        // the size splits before it lands rather than reaching both. Which
        // store does not matter here: the split makes a list for each of them,
        // and `addMediaPaths` below is what puts the files in the right one.
        if store != nil, !previews, stores.count > 1, !mediaIsSplit(deviceClass) {
            manifest.splitMedia(locale: locale, deviceClass: deviceClass)
        }
        if previews {
            Task {
                var accepted: [String] = []
                do {
                    let existing = mediaPaths(deviceClass: deviceClass, previews: true)
                    guard existing.count + urls.count <= 3 else {
                        throw MediaInputError.tooMany(limit: 3)
                    }
                    for url in urls {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        _ = try await AssetInspector.validatePreview(at: url)
                        accepted.append(manifestPath(for: url))
                    }
                    manifest.addMediaPaths(accepted, locale: locale,
                                           deviceClass: deviceClass, previews: true)
                    saveManifestReportingErrors()
                    mediaError = nil
                } catch {
                    mediaError = error.localizedDescription
                }
            }
        } else {
            do {
                let existing = mediaPaths(deviceClass: deviceClass)
                let arriving = urls.map(manifestPath(for:))
                try checkMediaLimits(existing: existing, arriving: arriving)
                var paths: [String] = []
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    _ = try AssetInspector.validateImage(at: url, deviceClass: deviceClass,
                                                         stores: stores)
                    paths.append(manifestPath(for: url))
                }
                manifest.addMediaPaths(paths, locale: locale, deviceClass: deviceClass,
                                       store: store)
                saveManifestReportingErrors()
                mediaError = nil
            } catch {
                mediaError = error.localizedDescription
            }
        }
    }

    /// How many pictures one device size may still take, by the rule each store
    /// actually counts by.
    ///
    /// Google takes 8 per device class, and refuses the whole drop rather than
    /// the overflow: a developer moving screenshots between locales adds and
    /// removes in whichever order is convenient, and a size that is briefly over
    /// on the way to being under is not a mistake to block.
    ///
    /// Apple's 10-per-**display type** limit is not checked here on purpose. A
    /// developer replacing a set drops the new pictures before deleting the old
    /// ones, which is over the limit for as long as both sit here, and this used
    /// to refuse that drop outright: the fix was deleting four first, uploading
    /// blind, and hoping the new four were the right four. `Validator.media`
    /// enforces the real limit before anything reaches Apple, which is the door
    /// that actually has to hold: this one only has to let the developer work.
    private func checkMediaLimits(existing: [String], arriving: [String]) throws {
        guard stores.contains(.google), existing.count + arriving.count > 8 else { return }
        throw MediaInputError.tooMany(limit: 8)
    }

    func moveMedia(_ path: String, by offset: Int, deviceClass: Manifest.DeviceClass,
                   previews: Bool = false, store: Store? = nil) {
        manifest.moveMediaPath(path, by: offset, locale: locale, deviceClass: deviceClass,
                               previews: previews, store: store)
        saveManifestReportingErrors()
    }

    /// Drops one screenshot onto the place another one holds.
    ///
    /// The tiles sit in a horizontal row and not a `List`, so there is no
    /// `onMove` to inherit. The two arrow buttons stay: they are the keyboard
    /// route, and Full Keyboard Access cannot drag.
    func moveMedia(_ path: String, before other: String,
                   deviceClass: Manifest.DeviceClass, previews: Bool = false,
                   store: Store? = nil) {
        let paths = mediaPaths(deviceClass: deviceClass, previews: previews, store: store)
        guard path != other, let target = paths.firstIndex(of: other) else { return }
        manifest.moveMediaPath(path, to: target, locale: locale, deviceClass: deviceClass,
                               previews: previews, store: store)
        saveManifestReportingErrors()
    }

    func removeMedia(_ path: String, deviceClass: Manifest.DeviceClass,
                     previews: Bool = false, store: Store? = nil) {
        manifest.removeMediaPath(path, locale: locale, deviceClass: deviceClass,
                                 previews: previews, store: store)
        saveManifestReportingErrors()
    }

    // MARK: - Money

    func setProvider(_ value: Manifest.Provider) {
        provider = value
        var monetization = manifest.monetization ?? Manifest.Monetization()
        monetization.provider = value
        manifest.monetization = monetization
        saveManifestReportingErrors()
    }

    func updateRevenueCatProject() {
        var monetization = manifest.monetization ?? Manifest.Monetization(provider: .revenuecat)
        monetization.provider = .revenuecat
        var revenueCat = monetization.revenuecat
            ?? Manifest.Monetization.RevenueCat(projectId: revenueCatProjectID)
        revenueCat.projectId = revenueCatProjectID
        monetization.revenuecat = revenueCat
        manifest.monetization = monetization
        saveManifestReportingErrors()
    }

    func revenueCatKeyChanged() {
        do {
            try KeychainCredentials.save(RevenueCatCredential(apiKey: revenueCatAPIKey),
                                         kind: .revenueCat,
                                         account: try requireCredentialAccount())
            revenueCatConnection = .notConnected
        } catch { errorMessage = error.localizedDescription }
    }

    func testRevenueCatConnection() {
        revenueCatConnection = .connecting
        Task {
            do {
                revenueCatKeyChanged()
                let message = try await ProviderConnectionClient().testRevenueCat(
                    apiKey: revenueCatAPIKey, projectID: revenueCatProjectID)
                revenueCatConnection = .connected(message)
            } catch { revenueCatConnection = .failed(error.localizedDescription) }
        }
    }

    func checkAdapty() {
        adaptyConnection = .connecting
        Task {
            do {
                let message = try await Task.detached { try AdaptyCLIClient().status() }.value
                adaptyConnection = .connected(message)
            } catch { adaptyConnection = .failed(error.localizedDescription) }
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func updateBasePrice() {
        switch PriceDraft.resolve(amount: priceAmount, currency: priceCurrency,
                                  territory: priceTerritory) {
        case .empty:
            manifest.pricing = nil
            saveManifestReportingErrors()
            moneyError = priceCurrency.isEmpty ? nil : "Enter an amount to save the base price."
        case .invalid(let message):
            moneyError = message
        case .valid(let price):
            // The price, and nothing else about the block.
            //
            // It used to build a new `Pricing` from the price alone, carrying
            // one key across by hand, so every other key in the block was
            // dropped on the keystroke: a developer who picked their countries
            // and then changed the amount lost the country list, silently, on
            // a screen that shows both. The territories and the new-territory
            // answer live in this block too.
            //
            // Nothing is invented for a block that does not exist yet. The
            // defaults were `true`, so saving a price wrote an answer about
            // territory availability that the developer had never given, and
            // the planner then queued "Write the territory availability" on an
            // app whose countries nobody had touched. An absent key means "do
            // not manage this". The toggles still draw `true` when the key is
            // absent, because a checkbox has to draw something; pressing one is
            // what writes the key.
            var pricing = manifest.pricing ?? Manifest.Pricing(base: price)
            pricing.base = price
            manifest.pricing = pricing
            saveManifestReportingErrors()
            moneyError = nil
        }
    }

    /// The products App Store Connect already holds and `store.yaml` has never
    /// named, brought in so they can be read and edited here.
    ///
    /// The read has always fetched every product on the store, and the tab
    /// only ever drew the ones the manifest listed. So an app with approved
    /// purchases showed an empty catalog, and the only way to manage one was to
    /// retype its id exactly and hope the apply matched it rather than creating
    /// a second product.
    ///
    /// It adds and never overwrites. A product the manifest already names is
    /// the developer's own text, and a store value must not land on top of it:
    /// that is the same rule the listing import obeys.
    @discardableResult
    func importAppleCatalog() -> Int {
        guard let catalog = actualState.apple?.catalog else { return 0 }
        var purchases = manifest.purchases ?? []
        var groups = manifest.subscriptions ?? []
        let known = Set(purchases.map(\.id)) .union(groups.flatMap { $0.plans.map(\.id) })
        var added = 0

        for product in catalog.values.sorted(by: { $0.productId < $1.productId })
        where !known.contains(product.productId) && !product.productId.isEmpty {
            // A duration is what makes it a subscription. Apple returns the
            // two kinds from two endpoints into one catalog, and only the
            // subscription carries a billing period.
            if let duration = product.duration {
                // Without a group there is nowhere in the manifest to put it.
                // The group read names them, so a nil here means the link was
                // not returned, and inventing a group would create a second
                // one on the next apply.
                guard let groupName = product.groupName else { continue }
                // No name on a plan. Apple's reference name is not a manifest
                // field: what the customer reads lives in `locales`, and the
                // apply writes those separately.
                let plan = Manifest.SubscriptionGroup.Plan(id: product.productId,
                                                           duration: duration)
                if let index = groups.firstIndex(where: { $0.groupName == groupName }) {
                    groups[index].plans.append(plan)
                } else {
                    groups.append(Manifest.SubscriptionGroup(
                        groupId: groupName, groupName: groupName, plans: [plan]))
                }
            } else {
                purchases.append(Manifest.Purchase(id: product.productId,
                                                   kind: .nonConsumable,
                                                   name: product.name))
            }
            added += 1
        }

        guard added > 0 else { return 0 }
        manifest.purchases = purchases.isEmpty ? nil : purchases
        manifest.subscriptions = groups.isEmpty ? nil : groups
        saveManifestReportingErrors()
        invalidatePlan()
        return added
    }

    /// How many products on the store this app knows nothing about.
    var appleCatalogNotImported: Int {
        guard let catalog = actualState.apple?.catalog else { return 0 }
        let known = Set((manifest.purchases ?? []).map(\.id))
            .union((manifest.subscriptions ?? []).flatMap { $0.plans.map(\.id) })
        return catalog.values.filter { !known.contains($0.productId) && !$0.productId.isEmpty }
            .count
    }

    /// Apple's own review state for one product, or nil when no read has said.
    func appleProductState(_ id: String) -> ActualState.Apple.CatalogProduct? {
        actualState.apple?.catalog[id]
    }

    func addPurchase() {
        var values = manifest.purchases ?? []
        values.append(Manifest.Purchase(id: "", kind: .nonConsumable))
        manifest.purchases = values
        saveManifestReportingErrors()
    }

    func removePurchase(at index: Int) {
        guard manifest.purchases?.indices.contains(index) == true else { return }
        manifest.purchases?.remove(at: index)
        purchasePriceInputs = [:]
        saveManifestReportingErrors()
    }

    func purchaseBinding(index: Int, field: PurchaseTextField) -> Binding<String> {
        Binding(get: {
            guard let item = self.manifest.purchases?[safe: index] else { return "" }
            return switch field {
            case .id: item.id
            case .name: item.name ?? ""
            case .amount: self.purchasePriceInput(index).amount
            case .currency: self.purchasePriceInput(index).currency
            case .entitlement: item.entitlements?.joined(separator: ",") ?? ""
            }
        }, set: { value in
            guard self.manifest.purchases?.indices.contains(index) == true else { return }
            switch field {
            case .id: self.manifest.purchases?[index].id = value
            case .name: self.manifest.purchases?[index].name = value
            case .amount:
                var input = self.purchasePriceInput(index)
                input.amount = value
                self.purchasePriceInputs[index] = input
                self.commitPurchasePrice(index)
                return
            case .currency:
                var input = self.purchasePriceInput(index)
                input.currency = value.uppercased()
                self.purchasePriceInputs[index] = input
                self.commitPurchasePrice(index)
                return
            case .entitlement:
                self.manifest.purchases?[index].entitlements = value.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            self.saveManifestReportingErrors()
        })
    }

    private func purchasePriceInput(_ index: Int) -> CatalogPriceInput {
        if let input = purchasePriceInputs[index] { return input }
        let price = manifest.purchases?[safe: index]?.price
        return CatalogPriceInput(amount: price.map { "\($0.amount)" } ?? "",
                                 currency: price?.currency ?? "")
    }

    private func commitPurchasePrice(_ index: Int) {
        guard manifest.purchases?.indices.contains(index) == true else { return }
        let input = purchasePriceInput(index)
        switch PriceDraft.resolve(amount: input.amount, currency: input.currency) {
        case .empty:
            manifest.purchases?[index].price = nil
            moneyError = nil
        case .invalid(let message):
            moneyError = "Purchase: \(message)"
            return
        case .valid(let price):
            manifest.purchases?[index].price = price
            moneyError = nil
        }
        saveManifestReportingErrors()
    }

    func purchaseKindBinding(index: Int) -> Binding<Manifest.Purchase.Kind> {
        Binding(get: { self.manifest.purchases?[safe: index]?.kind ?? .nonConsumable },
                set: { value in
                    guard self.manifest.purchases?.indices.contains(index) == true else { return }
                    self.manifest.purchases?[index].kind = value
                    self.saveManifestReportingErrors()
                })
    }

    func addSubscriptionGroup() {
        var groups = manifest.subscriptions ?? []
        groups.append(Manifest.SubscriptionGroup(groupId: ""))
        manifest.subscriptions = groups
        saveManifestReportingErrors()
    }

    func removeSubscriptionGroup(at index: Int) {
        guard manifest.subscriptions?.indices.contains(index) == true else { return }
        manifest.subscriptions?.remove(at: index)
        planPriceInputs = [:]
        saveManifestReportingErrors()
    }

    func subscriptionGroupBinding(index: Int, name: Bool) -> Binding<String> {
        Binding(get: {
            guard self.manifest.subscriptions?.indices.contains(index) == true else { return "" }
            return name ? self.manifest.subscriptions?[index].groupName ?? ""
                : self.manifest.subscriptions?[index].groupId ?? ""
        }, set: { value in
            guard self.manifest.subscriptions?.indices.contains(index) == true else { return }
            if name { self.manifest.subscriptions?[index].groupName = value }
            else { self.manifest.subscriptions?[index].groupId = value }
            self.saveManifestReportingErrors()
        })
    }

    func addPlan(to groupIndex: Int) {
        guard manifest.subscriptions?.indices.contains(groupIndex) == true else { return }
        manifest.subscriptions?[groupIndex].plans.append(Manifest.SubscriptionGroup.Plan(id: "", duration: ""))
        saveManifestReportingErrors()
    }

    func removePlan(groupIndex: Int, planIndex: Int) {
        guard manifest.subscriptions?.indices.contains(groupIndex) == true,
              manifest.subscriptions?[groupIndex].plans.indices.contains(planIndex) == true else { return }
        manifest.subscriptions?[groupIndex].plans.remove(at: planIndex)
        planPriceInputs = [:]
        saveManifestReportingErrors()
    }

    func planBinding(groupIndex: Int, planIndex: Int, field: PlanTextField) -> Binding<String> {
        Binding(get: {
            guard self.manifest.subscriptions?.indices.contains(groupIndex) == true,
                  self.manifest.subscriptions?[groupIndex].plans.indices.contains(planIndex) == true,
                  let plan = self.manifest.subscriptions?[groupIndex].plans[planIndex] else { return "" }
            return switch field {
            case .id: plan.id
            case .duration: plan.duration
            case .basePlanID: plan.basePlanId ?? ""
            case .applePlanType: plan.applePlanType?.rawValue ?? ""
            case .amount: self.planPriceInput(groupIndex, planIndex).amount
            case .currency: self.planPriceInput(groupIndex, planIndex).currency
            case .entitlement: plan.entitlements?.joined(separator: ",") ?? ""
            case .packageKey: plan.packageKey ?? ""
            }
        }, set: { value in
            guard self.manifest.subscriptions?.indices.contains(groupIndex) == true,
                  self.manifest.subscriptions?[groupIndex].plans.indices.contains(planIndex) == true else { return }
            switch field {
            case .id: self.manifest.subscriptions?[groupIndex].plans[planIndex].id = value
            case .duration: self.manifest.subscriptions?[groupIndex].plans[planIndex].duration = value
            case .basePlanID: self.manifest.subscriptions?[groupIndex].plans[planIndex].basePlanId = value
            case .applePlanType:
                self.manifest.subscriptions?[groupIndex].plans[planIndex].applePlanType =
                    Manifest.ApplePlanType(rawValue: value)
            case .amount:
                var input = self.planPriceInput(groupIndex, planIndex)
                input.amount = value
                self.planPriceInputs[self.planPriceKey(groupIndex, planIndex)] = input
                self.commitPlanPrice(groupIndex, planIndex)
                return
            case .currency:
                var input = self.planPriceInput(groupIndex, planIndex)
                input.currency = value.uppercased()
                self.planPriceInputs[self.planPriceKey(groupIndex, planIndex)] = input
                self.commitPlanPrice(groupIndex, planIndex)
                return
            case .entitlement:
                self.manifest.subscriptions?[groupIndex].plans[planIndex].entitlements =
                    Self.csv(value)
            case .packageKey: self.manifest.subscriptions?[groupIndex].plans[planIndex].packageKey = value
            }
            self.saveManifestReportingErrors()
        })
    }

    private func planPriceKey(_ groupIndex: Int, _ planIndex: Int) -> String {
        "\(groupIndex):\(planIndex)"
    }

    private func planPriceInput(_ groupIndex: Int, _ planIndex: Int) -> CatalogPriceInput {
        let key = planPriceKey(groupIndex, planIndex)
        if let input = planPriceInputs[key] { return input }
        let price = manifest.subscriptions?[safe: groupIndex]?.plans[safe: planIndex]?.price
        return CatalogPriceInput(amount: price.map { "\($0.amount)" } ?? "",
                                 currency: price?.currency ?? "")
    }

    private func commitPlanPrice(_ groupIndex: Int, _ planIndex: Int) {
        guard manifest.subscriptions?.indices.contains(groupIndex) == true,
              manifest.subscriptions?[groupIndex].plans.indices.contains(planIndex) == true else {
            return
        }
        let input = planPriceInput(groupIndex, planIndex)
        switch PriceDraft.resolve(amount: input.amount, currency: input.currency) {
        case .empty:
            manifest.subscriptions?[groupIndex].plans[planIndex].price = nil
            moneyError = nil
        case .invalid(let message):
            moneyError = "Subscription: \(message)"
            return
        case .valid(let price):
            manifest.subscriptions?[groupIndex].plans[planIndex].price = price
            moneyError = nil
        }
        saveManifestReportingErrors()
    }

    func entitlementBinding(index: Int, name: Bool) -> Binding<String> {
        Binding(get: {
            guard self.manifest.entitlements?.indices.contains(index) == true else { return "" }
            return name ? self.manifest.entitlements?[index].name ?? ""
                : self.manifest.entitlements?[index].key ?? ""
        }, set: { value in
            guard self.manifest.entitlements?.indices.contains(index) == true else { return }
            if name { self.manifest.entitlements?[index].name = value }
            else { self.manifest.entitlements?[index].key = value }
            self.saveManifestReportingErrors()
        })
    }

    func offeringBinding(index: Int, field: String) -> Binding<String> {
        Binding(get: {
            guard self.manifest.offerings?.indices.contains(index) == true else { return "" }
            switch field {
            case "name": return self.manifest.offerings?[index].name ?? ""
            case "products": return self.manifest.offerings?[index].products?.joined(separator: ",") ?? ""
            default: return self.manifest.offerings?[index].key ?? ""
            }
        }, set: { value in
            guard self.manifest.offerings?.indices.contains(index) == true else { return }
            switch field {
            case "name": self.manifest.offerings?[index].name = value
            case "products": self.manifest.offerings?[index].products = Self.csv(value)
            default: self.manifest.offerings?[index].key = value
            }
            self.saveManifestReportingErrors()
        })
    }

    func offeringCurrentBinding(index: Int) -> Binding<Bool> {
        Binding(get: { self.manifest.offerings?[safe: index]?.isCurrent ?? false }, set: { value in
            guard self.manifest.offerings?.indices.contains(index) == true else { return }
            self.manifest.offerings?[index].isCurrent = value
            self.saveManifestReportingErrors()
        })
    }

    func addEntitlement() {
        var values = manifest.entitlements ?? []
        values.append(Manifest.Entitlement(key: ""))
        manifest.entitlements = values
        saveManifestReportingErrors()
    }

    func removeEntitlement(at index: Int) {
        guard manifest.entitlements?.indices.contains(index) == true else { return }
        manifest.entitlements?.remove(at: index)
        saveManifestReportingErrors()
    }

    func addOffering() {
        var values = manifest.offerings ?? []
        values.append(Manifest.Offering(key: "", isCurrent: values.isEmpty, products: []))
        manifest.offerings = values
        saveManifestReportingErrors()
    }

    func removeOffering(at index: Int) {
        guard manifest.offerings?.indices.contains(index) == true else { return }
        manifest.offerings?.remove(at: index)
        saveManifestReportingErrors()
    }

    // MARK: - Review info

    func reviewBinding(_ field: ReviewTextField) -> Binding<String> {
        Binding(get: { self.manifest.reviewText(field) }, set: { value in
            self.manifest.setReviewText(value, field: field)
            self.saveManifestReportingErrors()
        })
    }

    var demoAccountRequiredBinding: Binding<Bool> {
        Binding(get: { self.manifest.review?.demoAccountRequired ?? false }, set: { value in
            var review = self.manifest.review ?? Manifest.Review()
            review.demoAccountRequired = value
            self.manifest.review = review
            self.saveManifestReportingErrors()
        })
    }

    /// True when this app already sells on a store.
    ///
    /// It decides what a tab may assume the developer has to supply. An update
    /// starts from a listing that is already complete, so nothing on the Media
    /// tab is required and the App Store wants release notes; a first
    /// submission starts from nothing, both stores refuse it without
    /// screenshots, and there is no such thing as what is new in a version
    /// nobody has ever seen.
    ///
    /// The safest default is false. Telling a developer with a shipped app
    /// that screenshots are required costs them a shrug; telling a first-time
    /// developer that they are optional costs them a rejection.
    ///
    /// This used to be `isUpdate || !storeSnapshot.isEmpty`, and the second
    /// half answered a different question than the one being asked. The
    /// snapshot fills from `infoLocales` and `versionLocales`, which a **draft**
    /// carries: an app record created in App Store Connect and never submitted
    /// has a name, a subtitle and a description, so anything the store held at
    /// all read as an app that ships. Every unpublished app was then told that
    /// What is new is required, over a version that has no previous version to
    /// be new against.
    var isUpdatingLiveApp: Bool { appleHasShipped || googleHasShipped }

    /// Whether this store has fixed the identifiers of the open app.
    ///
    /// A published app cannot change its bundle id, its App Store app id, or
    /// its Play package name. Each one is the app's identity in that store:
    /// every install, review, purchase and crash report hangs off it, and
    /// neither store publishes a call that changes one. A new value typed into
    /// the box moves no app. It points this workspace at a different app, or at
    /// none, and the apply then writes this app's listing over somebody else's
    /// or fails on an id that names nothing.
    ///
    /// Per store, because an app can be shipped in one and unwritten in the
    /// other. Locking the bundle id of a first iOS submission because the
    /// Android app is out would block the submission the box exists for.
    ///
    /// False before a read answers, which is the only safe way round. A box
    /// held shut against a store nobody has asked about is a developer who
    /// cannot type the id that would let the app ask.
    func storeFixedTheIdentifiers(_ store: Store) -> Bool {
        switch store {
        case .apple: appleHasShipped
        case .google: googleHasShipped
        }
    }

    /// The App Store has taken this app to customers at least once.
    ///
    /// Three readings of one fact, because they arrive at different moments.
    /// The first two need a fresh read of the store; the third is kept on disk
    /// and answers on the launch before any read has finished.
    private var appleHasShipped: Bool {
        if actualState.apple?.isUpdate == true { return true }
        // Any platform, not only the one being published. A Mac app that has
        // shipped is a shipped app while its iOS train is still a draft.
        if actualState.apple?.platforms.contains(where: { $0.live != nil }) == true {
            return true
        }
        // The words the customers are reading. `appleLive` fills from
        // `liveVersionLocales` alone, so a draft never puts anything here.
        return storeSnapshot.hasAppleLiveListing
    }

    /// Google Play has published this app.
    ///
    /// The production track and not the primary one. A build on an internal or
    /// a closed track is not an app the public can install, and the question
    /// here is whether there is a released version to be an update to.
    private var googleHasShipped: Bool {
        // The status is unwrapped and not compared through the optional. A nil
        // status is a read that did not answer, and `nil != "draft"` is true,
        // so comparing it directly would call an unread track published.
        guard let track = actualState.google?.tracks["production"],
              let status = track.status else { return false }
        return !track.versionCodes.isEmpty && status != "draft"
    }

    /// Whether the tabs draw the fields that only a first submission uses.
    ///
    /// A first submission has to reserve a bundle ID, name the app, and supply
    /// everything the store has never been told. An update was told all of it
    /// on the day it shipped, so those controls are noise at best; the write
    /// ones are worse than noise, because reserving a second bundle ID for an
    /// app that already ships under one is a mistake the API cannot undo.
    ///
    /// It is the inverse of `isUpdatingLiveApp` and it has its own name so a
    /// view says what it means: a tab hides a field because the app is new or
    /// is not, and never because of what a store read happened to answer.
    var showsNewAppFields: Bool { !isUpdatingLiveApp }

    /// True when a store holds a screenshot for the language on screen.
    ///
    /// The Media tab asks so that an empty grid on an update can say which of
    /// the two empties it is: an app with no pictures, or a read that did not
    /// reach them.
    var hasLiveScreenshots: Bool {
        Manifest.DeviceClass.allCases.contains {
            !storeSnapshot.screenshots(locale: locale, deviceClass: $0).isEmpty
        }
    }

    /// The territory the base price is set in. Apple's own default when the
    /// developer has not picked one, which is what the reader and the apply
    /// both fall back to.
    var basePriceTerritory: String {
        priceTerritory.isEmpty ? "USA" : priceTerritory
    }

    /// Fetches the ladder for the base territory when the one in hand is for
    /// another country, or for no country at all.
    ///
    /// The Availability tab calls this when it opens and whenever the base
    /// territory moves. Without it the prices arrived only with a whole store
    /// read from the Summary tab, so the field that asks for the first price
    /// was a plain box on the one screen where a developer sets a price, and
    /// moving the territory left the old country's money on offer.
    ///
    /// It costs one paged GET and nothing else. A failure leaves the state
    /// alone: the fields fall back to free text, which is where they started.
    func loadApplePricePoints() async {
        guard stores.contains(.apple), let appID = appleActionAppID,
              credentials.apple != nil else { return }
        let territory = basePriceTerritory
        guard territory != actualState.apple?.pricePointTerritory,
              let points = try? await ApplePricePoints.app(readOnlyAPI(), appID: appID,
                                                           territory: territory)
        else { return }
        // The developer can move the territory again while Apple answers. The
        // answer that comes back for the country they left is not their list.
        guard territory == basePriceTerritory else { return }
        var apple = actualState.apple ?? ActualState.Apple()
        apple.pricePoints = Set(points.map(\.amount)).sorted()
        apple.pricePointTerritory = territory
        // The ladder moved country, so the two product ladders read for the old
        // one are the wrong money now.
        apple.purchasePricePoints = []
        apple.subscriptionPricePoints = []
        actualState.apple = apple
    }

    /// The two ladders a product is priced off.
    ///
    /// A product does not sell at the app's price points. Apple keeps a table
    /// per kind, and the subscription one is the sparsest of the three: the
    /// menu offered R$17.50, R$18.00 and R$18.50 for a Brazilian subscription
    /// whose real rows are R$14.90, R$19.90 and R$24.90.
    ///
    /// One read per kind, not one per product. The ladder belongs to the
    /// territory and the kind, and Apple hangs it off a product only because
    /// that is where the route lives — the ids are per product and this uses
    /// none of them, since the apply resolves the amount against the product it
    /// is writing. An app with nothing of a kind on the store yet gets no
    /// ladder for it, and the picker says the prices are unavailable rather
    /// than offering the app's.
    ///
    /// It needs the catalog, so it runs after the catalog read.
    func loadAppleProductPricePoints() async {
        guard stores.contains(.apple), credentials.apple != nil,
              let apple = actualState.apple, apple.catalogRead else { return }
        let territory = basePriceTerritory
        guard territory == apple.pricePointTerritory else { return }
        let api = readOnlyAPI()

        if apple.purchasePricePoints.isEmpty,
           let id = appleResourceID(of: (manifest.purchases ?? []).map(\.id)),
           let points = try? await ApplePricePoints.purchase(api, id: id,
                                                             territory: territory),
           territory == basePriceTerritory {
            actualState.apple?.purchasePricePoints = Set(points.map(\.amount)).sorted()
        }
        if actualState.apple?.subscriptionPricePoints.isEmpty != false,
           let id = appleResourceID(of: (manifest.subscriptions ?? [])
            .flatMap { $0.plans.map(\.id) }),
           let points = try? await ApplePricePoints.subscription(api, id: id,
                                                                 territory: territory),
           territory == basePriceTerritory {
            actualState.apple?.subscriptionPricePoints = Set(points.map(\.amount)).sorted()
        }
    }

    /// Apple's own id for the first of these products that the store holds. The
    /// manifest's product id names the product; the route wants the resource.
    private func appleResourceID(of productIds: [String]) -> String? {
        productIds.lazy.compactMap { self.actualState.apple?.catalog[$0]?.id }.first
    }

    /// What the App Store already charges for this app and sells inside it,
    /// into the blanks on this tab.
    ///
    /// An app that is on sale opened Monetization on an empty price and an
    /// empty product list. Everything needed to fill them was already in the
    /// app: the catalogue rides along with a listing import, and the price is
    /// two requests that the plan makes on every read. Neither reached this
    /// screen, so the developer of a shipping app was asked to type the price
    /// their customers are already paying.
    ///
    /// It writes into blanks only. See `Manifest.mergeAppleMoney`: a value the
    /// file already holds is the developer's answer, and a screen they walked
    /// past may not overwrite it.
    ///
    /// Once per app and territory. The tab body reruns its task whenever
    /// SwiftUI rebuilds it, and four requests per redraw is a store read nobody
    /// asked for. The territory is part of the key because it is what the price
    /// is read in: moving the base country asks a different question.
    ///
    /// A read that failed is not a read. The mark comes off, so the next visit
    /// tries again rather than holding the tab empty until the app restarts.
    func loadStoreMonetization() async {
        guard stores.contains(.apple), let appID = appleActionAppID,
              credentials.apple != nil else { return }
        let territory = basePriceTerritory
        let key = "\(appID)|\(territory)"
        guard !moneyReadApps.contains(key) else { return }
        moneyReadApps.insert(key)
        let money = try? await StoreImportReader(credentials: credentials)
            .appleMoney(appID: appID, territory: territory)
        guard let money else { moneyReadApps.remove(key); return }
        // The developer can move to another app while Apple answers. What came
        // back is that app's money, not this one's.
        guard appID == appleActionAppID else { return }
        if !money.isEmpty, manifest.mergeAppleMoney(money) {
            registerManifestUndo()
            syncEditingStateFromManifest()
            saveManifestReportingErrors()
        }
        // The manifest merge above fills what `store.yaml` is missing. It does
        // not say what the store holds, and that is the question the tab draws:
        // the price columns, "Approved", "In review" and "Will add" all read
        // `actualState.apple.catalog`, which nothing but the Summary read ever
        // filled. Opening Monetization on a published app therefore showed
        // every approved purchase as one the apply was about to create.
        //
        // After the merge, so a product imported a moment ago is in the id list
        // and gets its detail read in the same pass.
        await readAppleCatalogForMoney(appID: appID, key: key)
    }

    /// The read-only catalog work the Monetization tab needs to draw itself.
    ///
    /// `AppleCatalogClient` and not a second parser: it is the same client the
    /// Summary read uses, it already reads product state, prices, availability,
    /// subscription groups and group membership, and a parallel reader would be
    /// a second answer to drift from this one.
    ///
    /// It writes nothing to any store. Every call inside is a `GET`.
    private func readAppleCatalogForMoney(appID: String, key: String) async {
        // A Summary read fills the same map from the same client, so an app
        // whose state is already fresh owes nothing here. `actualState` is
        // cleared when the open app changes, so this is per app by
        // construction.
        guard actualState.apple?.catalogRead != true else { return }
        let client = AppleCatalogClient(api: readOnlyAPI())
        let purchaseIds = (manifest.purchases ?? []).map(\.id).filter { !$0.isEmpty }
        let groups = manifest.subscriptions ?? []
        let planIds = groups.flatMap { $0.plans.map(\.id) }.filter { !$0.isEmpty }

        // A failure leaves the flag false, so the tab says the read did not
        // answer rather than claiming Apple holds nothing. It also drops the
        // key, so opening the tab again asks again.
        guard let purchases = try? await client.purchases(appID: appID,
                                                          productIds: purchaseIds),
              let subscriptions = try? await client.subscriptions(
                appID: appID, productIds: planIds,
                groupNames: groups.compactMap(\.groupName)) else {
            moneyReadApps.remove(key)
            return
        }
        guard appID == appleActionAppID else { return }

        var apple = actualState.apple ?? ActualState.Apple()
        apple.purchaseIds = Set(purchases.keys)
        apple.subscriptionIds = Set(subscriptions.products.keys)
        // Merged and not assigned. A Summary read may already have filled this
        // with more than the two list reads carry, and the newer detail wins
        // per product rather than replacing the whole map.
        apple.catalog.merge(purchases) { _, new in new }
        apple.catalog.merge(subscriptions.products) { _, new in new }
        apple.subscriptionGroupNames = subscriptions.groups.names
        apple.subscriptionGroupLocales.merge(subscriptions.groups.locales) { _, new in new }
        apple.catalogRead = true
        actualState.apple = apple

        // And into the file, for the products it already names. The catalog
        // read carries the price, the store text and the billing type of every
        // product on this tab, and until now none of it reached a field: the
        // list merge writes a catalog only when there is none, so an app with
        // one line about a subscription kept every blank under it for ever.
        if manifest.mergeAppleCatalog(apple, territory: basePriceTerritory,
                                      currency: apple.priceCurrency
                                          ?? manifest.pricing?.base.currency) {
            registerManifestUndo()
            syncEditingStateFromManifest()
            saveManifestReportingErrors()
        }
    }

    /// The prices Apple sells at, as the picker's rows.
    ///
    /// Empty whenever the App Store is not chosen, nobody has read it yet, or
    /// the developer moved the base territory after the read. The Amount
    /// picker is unavailable in those states rather than accepting a value the
    /// store may not sell at.
    ///
    /// The territory has to match. A ladder is one country's money, so São
    /// Paulo's prices offered against a United States base price are the wrong
    /// numbers in the wrong currency, which is worse than a plain box.
    var applePricePoints: [StoreValues.Choice] {
        guard stores.contains(.apple),
              actualState.apple?.pricePointTerritory == basePriceTerritory else { return [] }
        // Sorted here and not only in the reader. The picker's order is what a
        // person reads down, and it should not depend on which code path filled
        // the state.
        return (actualState.apple?.pricePoints ?? []).sorted().map {
            // The value is the number the manifest writes. The label is the
            // money App Store Connect shows for it, so the row reads $1.99 and
            // not 1.99 the way the web form does.
            StoreValues.Choice("\($0)", priceLabel($0))
        }
    }

    /// The ladder an in-app purchase is priced off, and the one a subscription
    /// is priced off.
    ///
    /// Apple keeps a table per kind and they are not the app's. This offered
    /// the app's ladder for both, so a Brazilian subscription was offered
    /// R$17.50 and R$18.00 — prices the App Store does not sell a subscription
    /// at — and the apply then resolved the choice to the nearest real point
    /// without saying so. See `loadAppleProductPricePoints`.
    ///
    /// Nothing until that read lands. An empty list makes the picker say the
    /// prices are unavailable, which is the honest state: the app ladder here
    /// was a list of wrong answers offered with confidence.
    var applePurchasePricePoints: [StoreValues.Choice] {
        productLadder(actualState.apple?.purchasePricePoints ?? [])
    }

    var appleSubscriptionPricePoints: [StoreValues.Choice] {
        productLadder(actualState.apple?.subscriptionPricePoints ?? [])
    }

    /// One kind's ladder as the picker's rows, in the territory it was read
    /// for. The App Store sells no product for nothing, so a zero row is
    /// dropped: it belongs to the app alone.
    private func productLadder(_ amounts: [Decimal]) -> [StoreValues.Choice] {
        guard stores.contains(.apple),
              actualState.apple?.pricePointTerritory == basePriceTerritory else { return [] }
        return amounts.filter { $0 > 0 }.sorted().map {
            StoreValues.Choice("\($0)", priceLabel($0))
        }
    }

    /// One price point in the base price's currency.
    ///
    /// The locale is fixed, and not this Mac's. Apple states `customerPrice`
    /// with a dot, the manifest writes it with a dot, and the row a developer
    /// picks has to read as the value it sets: a Brazilian Mac rendered the
    /// same price as `US$ 1,99` against a stored `1.99`. The currency code
    /// still supplies the symbol, so USD reads $1.99 and BRL reads R$6.90, the
    /// way App Store Connect prints them.
    private func priceLabel(_ amount: Decimal) -> String {
        guard !priceCurrency.isEmpty else { return "\(amount)" }
        return amount.formatted(.currency(code: priceCurrency)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    /// The reviewer sign-in App Store Connect holds that this Mac does not.
    ///
    /// Nil when there is nothing to offer: no read, no stored name, or the
    /// fields already hold something. It never overwrites what the developer
    /// typed, because a store value is older than a value being typed now.
    var storedDemoAccount: (name: String, password: String?)? {
        guard let name = actualState.apple?.reviewDemoAccountName,
              reviewerUsername.isEmpty, reviewerPassword.isEmpty else { return nil }
        return (name, actualState.apple?.reviewDemoAccountPassword)
    }

    /// Takes it, and puts it where the app keeps a reviewer sign-in.
    ///
    /// Apple hands back the name and, on most accounts, withholds the
    /// password. Filling the half it gave is still the useful half: the
    /// developer confirms the account rather than remembering which one it was,
    /// and types one field instead of two.
    func fillDemoAccountFromStore() {
        guard let stored = storedDemoAccount else { return }
        reviewerUsername = stored.name
        if let password = stored.password { reviewerPassword = password }
        reviewerCredentialsChanged()
    }

    /// Asks App Store Connect for the reviewer sign-in it already holds.
    ///
    /// The offer above appears only once something has read the store, and the
    /// only thing that read it was the whole pass on the Summary tab. So a
    /// developer standing on this tab with two empty fields, on an app that has
    /// shipped with a demo account several times, had nothing here to press:
    /// the account was in App Store Connect the whole time and the way to it
    /// was another tab and a full read of both stores.
    ///
    /// The press is the decision, so an empty pair fills itself. A field that
    /// already holds something is left alone and the offer above says what the
    /// store has, because a value being typed now is newer than a store's.
    func readDemoAccountFromStore() async {
        guard let appID = manifest.apps.apple?.appId, !appID.isEmpty else {
            demoAccountReadNote = "No App Store app is connected. The Stores tab holds the app id."
            return
        }
        demoAccountReading = true
        demoAccountReadNote = nil
        defer { demoAccountReading = false }
        do {
            let signIn = try await AppleActionsClient(api: readOnlyAPI()).reviewSignIn(appID: appID)
            var apple = actualState.apple ?? ActualState.Apple()
            apple.reviewDemoAccountName = signIn.name ?? apple.reviewDemoAccountName
            apple.reviewDemoAccountPassword = signIn.password ?? apple.reviewDemoAccountPassword
            actualState.apple = apple
            guard signIn.name != nil else {
                demoAccountReadNote = "App Store Connect holds no reviewer account for this app."
                return
            }
            if reviewerUsername.isEmpty, reviewerPassword.isEmpty {
                fillDemoAccountFromStore()
                demoAccountReadNote = signIn.password == nil
                    ? "Filled from \(signIn.versionString ?? "the App Store"). Apple does not return the password, so type it."
                    : "Filled from \(signIn.versionString ?? "the App Store")."
            }
        } catch {
            demoAccountReadNote = "The App Store could not be read. \(error.localizedDescription)"
        }
    }

    /// The reviewer sign-in as text, for the one console field no API reaches.
    ///
    /// Play Console asks for both halves under App access and the Android
    /// Publisher API publishes no endpoint for either, so the only way the
    /// account gets there is a paste. Apple withholds the password on most
    /// accounts, so half a sign-in is still worth copying; nothing at all is
    /// not, and nil keeps the button from clearing the pasteboard over it.
    var demoAccountClipboard: String? {
        let user = reviewerUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty || !reviewerPassword.isEmpty else { return nil }
        guard !reviewerPassword.isEmpty else { return user }
        return "\(user)\n\(reviewerPassword)"
    }

    func copyDemoAccount() {
        guard let text = demoAccountClipboard else { return }
        copyToPasteboard(text)
    }

    func reviewerCredentialsChanged() {
        do {
            try KeychainCredentials.save(
                ReviewerCredential(username: reviewerUsername, password: reviewerPassword),
                kind: .reviewAccount, account: try requireCredentialAccount())
        } catch { errorMessage = error.localizedDescription }
    }

    /// Data safety answers left by an older build, whose question ids the app
    /// invented. Google publishes its own, so these declare nothing.
    var staleDataSafetyAnswers: [String] {
        (manifest.review?.dataSafetyAnswers ?? [:]).keys.sorted()
    }

    func removeDataSafetyAnswers() {
        guard var review = manifest.review else { return }
        review.dataSafetyAnswers = nil
        manifest.review = review
        saveManifestReportingErrors()
    }

    /// One row of Apple's age rating questionnaire.
    ///
    /// `held` is what App Store Connect answered and it decides the control.
    /// The app names no field and no value, so a questionnaire Apple changes
    /// arrives through the read.
    struct AgeRatingField: Sendable, Equatable {
        let key: String
        let held: AgeRatingAnswer
        let wanted: AgeRatingAnswer
        var changed: Bool { wanted != held }
    }

    /// Every age rating field the store read returned, with the value that the
    /// next apply would send. Empty until the stores are read.
    var ageRatingFields: [AgeRatingField] {
        let held = actualState.apple?.ageRating ?? [:]
        let wanted = manifest.review?.ageRatingAnswers ?? [:]
        return held.keys.sorted().map { key in
            AgeRatingField(key: key, held: held[key]!, wanted: wanted[key] ?? held[key]!)
        }
    }

    /// The categories to choose from: the ones App Store Connect reported,
    /// or the built-in snapshot until the stores are read.
    ///
    /// Apple adds and renames categories. The snapshot is a starting point,
    /// never the authority, so a read replaces it whole. A label the snapshot
    /// knows is kept, and one it does not shows the id Apple uses.
    var appleCategoryChoices: [StoreValues.Choice] {
        let known = actualState.apple?.appCategoryIDs ?? []
        guard !known.isEmpty else { return StoreValues.appleCategories }
        let labels = Dictionary(uniqueKeysWithValues:
            StoreValues.appleCategories.map { ($0.value, $0.label) })
        return known.sorted().map { StoreValues.Choice($0, labels[$0] ?? $0) }
    }

    /// Answers whose field App Store Connect does not have. They declare
    /// nothing and no apply sends them.
    var unknownAgeRatingKeys: [String] {
        Planner.appleAgeRatingChanges(manifest.review, actualState.apple).unknown
    }

    func removeUnknownAgeRatingKeys() {
        guard var review = manifest.review, var answers = review.ageRatingAnswers else { return }
        for key in unknownAgeRatingKeys { answers[key] = nil }
        review.ageRatingAnswers = answers.isEmpty ? nil : answers
        manifest.review = review
        saveManifestReportingErrors()
    }

    func ageRatingFlagBinding(_ field: AgeRatingField) -> Binding<Bool> {
        Binding(get: {
            if case .flag(let value) = field.wanted { return value }
            return false
        }, set: { self.setAgeRating(field, .flag($0)) })
    }

    func ageRatingTextBinding(_ field: AgeRatingField) -> Binding<String> {
        Binding(get: { field.wanted.display }, set: { self.setAgeRating(field, .text($0)) })
    }

    /// Writes the answer, or drops it when it matches the store again. A
    /// manifest that carries no answer is a manifest that keeps what Apple has.
    private func setAgeRating(_ field: AgeRatingField, _ value: AgeRatingAnswer) {
        var review = manifest.review ?? Manifest.Review()
        var answers = review.ageRatingAnswers ?? [:]
        if value == field.held { answers[field.key] = nil } else { answers[field.key] = value }
        review.ageRatingAnswers = answers.isEmpty ? nil : answers
        manifest.review = review
        saveManifestReportingErrors()
    }

    /// Apple's yes or no question, and the third state a Bool cannot hold.
    ///
    /// The key is optional in the manifest and every reader tests it for
    /// presence: Apple asks the question once per build and refuses the
    /// submission until the build carries an answer, so an absent key is a
    /// question still open. This was a `Binding<Bool>` that read an absent key
    /// as `false`, which drew a settled "no" over every app nobody had asked.
    var encryptionAnswer: Bool? { manifest.review?.usesNonExemptEncryption }

    func setEncryptionAnswer(_ value: Bool?) {
        var review = manifest.review ?? Manifest.Review()
        review.usesNonExemptEncryption = value
        manifest.review = review
        saveManifestReportingErrors()
    }

    /// The answer the Build tab opens with when nobody has given one.
    ///
    /// "Uses no non-exempt encryption" is the answer for almost every app:
    /// HTTPS and the platform's own cryptography are exempt, and the developer
    /// who does ship their own has the other option one click away with the
    /// paperwork behind it.
    ///
    /// It writes the key rather than only drawing it selected. The button that
    /// starts a build waits on this key being present — see
    /// `BuildFlow.blockingReason` — so a radio that showed an answer the file
    /// did not hold would be a selected option beside a blocked button and
    /// nothing to press to unblock it.
    ///
    /// This is a declaration to Apple, and this app now makes it on the
    /// developer's behalf until they say otherwise. The panel says which
    /// answer is selected, on the tab they have to visit to build.
    func defaultEncryptionAnswer() {
        guard manifest.apps.apple != nil, encryptionAnswer == nil else { return }
        setEncryptionAnswer(false)
    }

    // MARK: - The export compliance declaration

    /// The paperwork that the encryption toggle above creates the need for.
    ///
    /// `usesNonExemptEncryption` answers Apple's yes or no question on the
    /// build. An app that answers yes and claims no exemption also owes Apple
    /// this declaration, and sometimes a CCATS or ERN document with it.
    /// `AppleApply.appleEncryptionDeclaration` has always sent the whole block
    /// and no field ever wrote one, so the toggle created an obligation the app
    /// gave you no way to meet.
    var hasEncryptionDeclaration: Bool { manifest.review?.encryption != nil }

    func addEncryptionDeclaration() {
        guard manifest.review?.encryption == nil else { return }
        editEncryption { _ in }
    }

    func removeEncryptionDeclaration() {
        var review = manifest.review ?? Manifest.Review()
        review.encryption = nil
        manifest.review = review
        saveManifestReportingErrors()
    }

    enum EncryptionFlag: CaseIterable {
        case exempt, proprietary, thirdParty, french

        var label: String {
            switch self {
            case .exempt: "The app qualifies for an exemption"
            case .proprietary: "It contains proprietary cryptography"
            case .thirdParty: "It contains third-party cryptography"
            case .french: "It is available on the French App Store"
            }
        }
    }

    func encryptionFlagBinding(_ flag: EncryptionFlag) -> Binding<Bool> {
        Binding(get: {
            let block = self.manifest.review?.encryption
            return switch flag {
            case .exempt: block?.exempt ?? false
            case .proprietary: block?.containsProprietaryCryptography ?? false
            case .thirdParty: block?.containsThirdPartyCryptography ?? false
            case .french: block?.availableOnFrenchStore ?? false
            }
        }, set: { value in
            self.editEncryption { block in
                switch flag {
                case .exempt: block.exempt = value
                case .proprietary: block.containsProprietaryCryptography = value
                case .thirdParty: block.containsThirdPartyCryptography = value
                case .french: block.availableOnFrenchStore = value
                }
            }
        })
    }

    enum EncryptionTextField { case codeValue, documentPath }

    func encryptionTextBinding(_ field: EncryptionTextField) -> Binding<String> {
        Binding(get: {
            let block = self.manifest.review?.encryption
            return switch field {
            case .codeValue: block?.codeValue ?? ""
            case .documentPath: block?.documentPath ?? ""
            }
        }, set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored: String? = trimmed.isEmpty ? nil : trimmed
            self.editEncryption { block in
                switch field {
                case .codeValue: block.codeValue = stored
                case .documentPath: block.documentPath = stored
                }
            }
        })
    }

    /// One writer, so a toggle that fires before the block exists creates it.
    private func editEncryption(_ edit: (inout Manifest.Encryption) -> Void) {
        var review = manifest.review ?? Manifest.Review()
        var block = review.encryption ?? Manifest.Encryption()
        edit(&block)
        review.encryption = block
        manifest.review = review
        saveManifestReportingErrors()
    }

    func reviewMetadataBinding(_ key: String) -> Binding<String> {
        Binding(get: {
            if key == "kidsAgeBand" { return self.manifest.review?.kidsAgeBand ?? "" }
            if key == "dataSafetyCSV" { return self.manifest.review?.dataSafetyCSV ?? "" }
            return (self.manifest.review?.attachments ?? []).joined(separator: ", ")
        }, set: { value in
            var review = self.manifest.review ?? Manifest.Review()
            if key == "kidsAgeBand" {
                review.kidsAgeBand = value.isEmpty ? nil : value
            } else if key == "dataSafetyCSV" {
                review.dataSafetyCSV = value.isEmpty ? nil : value
            } else {
                let paths = value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                review.attachments = paths.isEmpty ? nil : paths
            }
            self.manifest.review = review
            self.saveManifestReportingErrors()
        })
    }

    // MARK: - The badges

    /// The open items per tab, errors and warnings kept apart.
    ///
    /// Red means "this blocks the apply", so it must never appear on a tab
    /// that holds no error. That rule is why the two counts are separate now
    /// rather than summed under the louder colour.
    func badge(for tab: Tab) -> TabBadge? {
        if applied { return nil }
        // Before the first read the only rule the app can run is the text
        // limit, because every other rule needs the store side. It is an
        // error in every case, so this branch has no warning to report.
        guard let plan else {
            let count = listingErrorCount
            guard count > 0 else { return nil }
            return tab == .details || tab == .plan ? TabBadge(errors: count) : nil
        }
        let target: FixTarget?
        switch tab {
        case .stores: target = .stores
        case .build: target = .build
        case .betaTesting: target = .betaTesting
        case .details: target = .details
        case .media: target = .media
        case .availability: target = .availability
        case .money: target = .money
        case .marketing: target = .marketing
        case .reviewInfo: target = .reviewInfo
        case .plan: target = nil
        default: return nil
        }
        // A hold earns no badge. A badge is a count of open items, and a
        // version in review is not an item: nothing on any tab closes it, and
        // a number beside Summary that never falls is a number nobody reads.
        let findings = (tab == .plan
            ? plan.findings
            : plan.findings.filter { $0.fix == target })
            .filter { $0.severity != .held }
        guard !findings.isEmpty else { return nil }
        let errors = findings.filter { $0.severity == .error }.count
        return TabBadge(errors: errors, warnings: findings.count - errors)
    }

    var planIsBlocked: Bool {
        plan.map(\.isBlocked) ?? (listingErrorCount > 0)
    }

    private var listingErrorCount: Int {
        manifest.listingErrorCount(for: stores)
    }

    // MARK: - The manifest file

    func load(from url: URL) throws {
        // Before the document is swapped, or a coalesced write still holding
        // this app's last keystroke would land against the next app's file.
        flushSave()
        manifest = try ManifestFile.load(from: url)
        manifest.removeImportedMedia()
        manifestURL = url
        // The stack holds whole manifests, so it cannot cross an app. See
        // resetUndo.
        resetUndo()
        syncStoreFieldsFromManifest()
        syncEditingStateFromManifest()
    }

    /// Writes now. Every call is also a flush, so a coalesced write waiting
    /// behind this one is answered by it and never lands afterwards. That is
    /// what lets every existing caller stay a plain `try save()`.
    func save() throws {
        guard let manifestURL else { return }
        saveTask?.cancel()
        saveTask = nil
        pendingSave = false
        try ManifestFile.save(manifest, to: manifestURL)
        lastSavedAt = Date()
    }

    /// Asks for a write and returns. The disk is touched once the typing stops.
    ///
    /// Every character used to re-encode the whole manifest through Yams and
    /// write it atomically, on the main actor: about 1.7 ms and one temporary
    /// file per key on a 16 KB listing. That is what made a text field lag
    /// behind the keyboard. It also stamped `lastSavedAt` per key, so the
    /// sidebar tick restarted its fade on every character and read as a blink.
    ///
    /// `flushSave` is what keeps this safe. Nothing may swap the document,
    /// show the file, or leave the process with a write still waiting.
    private func scheduleSave() {
        guard manifestURL != nil else { return }
        pendingSave = true
        saveTask?.cancel()
        // Long enough that a burst of typing is one write, short enough that
        // the pause between two words already committed the first one.
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    /// A listing field holding characters the manifest has not seen yet.
    ///
    /// `ListingEditor` keeps a draft while the developer types, so that a key
    /// redraws one field rather than the whole window. This is how the draft
    /// reaches the manifest before anything that reads or replaces it: every
    /// write boundary drains it first. Set while a commit is waiting and nil
    /// the rest of the time, so the usual path costs one comparison.
    ///
    /// `@ObservationIgnored`, because nothing draws it.
    @ObservationIgnored var pendingListingEdit: (() -> Void)?

    /// Writes whatever is waiting. It costs nothing when nothing is.
    func flushSave() {
        // Before the guard. A draft is exactly the case where nothing is
        // pending yet and something is about to be.
        pendingListingEdit?()
        guard pendingSave else {
            saveTask?.cancel()
            saveTask = nil
            return
        }
        do { try save() }
        catch { errorMessage = "The manifest could not be saved. \(error.localizedDescription)" }
    }

    /// File > Save. Every edit already writes `store.yaml`, so this writes it
    /// once more and stamps the time. A Mac app answers Command-S.
    func saveNow() {
        guard manifestURL != nil else { return }
        pendingListingEdit?()
        do { try save() }
        catch { errorMessage = "The manifest could not be saved. \(error.localizedDescription)" }
    }

    var credentialAccount: String? {
        guard linkedApps.indices.contains(selectedAppIndex) else { return nil }
        return linkedApps[selectedAppIndex].id.uuidString
    }

    private func requireCredentialAccount() throws -> String {
        guard let credentialAccount else {
            throw CocoaError(.fileNoSuchFile,
                             userInfo: [NSLocalizedDescriptionKey:
                                "Link or create an app before saving credentials."])
        }
        return credentialAccount
    }

    /// The folder that holds `store.yaml`. The run log, the console state, and
    /// every relative media path resolve against it.
    var manifestRoot: URL? {
        manifestURL?.deletingLastPathComponent()
    }

    private func activateLinkedApp(at index: Int) {
        guard linkedApps.indices.contains(index) else { return }
        selectedAppIndex = index
        showEntryScreen = false
        defaults.set(linkedApps[index].id.uuidString, forKey: lastOpenAppKey)
        let url = URL(fileURLWithPath: linkedApps[index].manifestPath)
        do {
            try load(from: url)
            locale = manifest.listing?.defaultLocale
                ?? manifest.listing?.locales.keys.sorted().first
                ?? ""
            // One app at a time, and the picture belongs to the app. Without
            // this line the app that opens second showed the first one's live
            // text under its own fields.
            storeSnapshot = StoreSnapshot.load(fromRoot: manifestRoot)
            syncEditingStateFromManifest()
            packages = [:]
            packageErrors = [:]
            buildRead = false
            loadCredentials()
            resetRunState()
            loadConsoleMarks()
            // After `resetRunState`, which clears the read the app before this
            // one left behind. The snapshot on disk holds the listing customers
            // are reading, so an app read in an earlier session proves itself
            // live here without waiting for the sweep.
            rememberOpenAppLiveState()
            applyDryRunDefault()
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent). \(error.localizedDescription)"
        }
    }

    /// Spec 16.5 and 17: the Settings preference decides it, for every app.
    ///
    /// One rule and no exception. A published app used to open with the dry run
    /// off, which made the live-write default belong to the one app state where
    /// a wrong write is read by customers. The preference is the developer's
    /// standing answer, it defaults to `true`, and a live app is a reason to
    /// keep that answer rather than to overrule it.
    ///
    /// Only the default. The toggle is the developer's for the rest of the
    /// session, and turning the dry run off asks a question first. See
    /// `RootView` and `isAppLive(appKey:)`, which other features still read.
    private func applyDryRunDefault() {
        dryRun = defaults.object(forKey: "dryRunByDefault") as? Bool ?? true
    }

    /// Settings ▸ Nuclear. Everything the app holds, gone, back to first run.
    ///
    /// The boundary is the point of this feature, so it is drawn explicitly.
    ///
    /// What goes is what Super Submitter made and what was typed into it: its
    /// defaults, its Keychain vault, the account, the list of linked apps, and
    /// the archives, artifacts, run logs and scratch it wrote.
    ///
    /// What stays is every file that holds the user's own work. No `store.yaml`
    /// is deleted, in a repository or in `Managed/`. Neither are their source
    /// projects, their accounts at Apple and Google, or anything published.
    /// Forgetting a single app has always worked this way. This is that, for
    /// all of them at once, and it must not become more than that.
    ///
    /// Two gates in front of it, and neither is this function's job. It is
    /// only ever called from the second one.
    /// `storage` is a parameter so a test can point the deletion at a
    /// temporary folder. Called without one, it is the real app folder, which
    /// is what the button in Settings wants and what a test must never touch.
    func eraseEverything(storage: BuildStorage = BuildStorage()) {
        nuclearFirstConfirm = false
        nuclearSecondConfirm = false

        // Stop anything in flight first. A run that is mid-upload holds the
        // storage folder this is about to remove.
        resetRunState()
        resetUndo()

        // The account keeps its entitlement in the same vault, so it is
        // cleared first and the vault goes second, both in one task so the
        // order holds. The other way round, `forget()` writes an empty vault
        // back and the nuclear option leaves a Keychain item behind.
        //
        // One delete for the credentials, never a per-store loop: a store the
        // user connected and then deselected still has a key in there, and a
        // loop over the selected stores would walk straight past it.
        let controller = accessController
        Task.detached {
            await controller?.forget()
            do { try KeychainCredentials.deleteEverything() }
            catch {
                let reason = error.localizedDescription
                await MainActor.run {
                    self.errorMessage = "The Keychain refused to clear: \(reason)"
                }
            }
        }

        // Named one by one, and never the folder above them.
        //
        // `Managed/` is in there too, and that is where a managed app keeps
        // its `store.yaml`. The workspace is this app's, but the listing text,
        // the catalog and the review answers inside it are the user's work and
        // there is no second copy anywhere. Removing the root took all of it.
        //
        // These five are byproducts: a list of paths to projects that live
        // elsewhere, archives this app built, artifacts it exported, logs it
        // wrote, and scratch it should already have cleaned up. Nuclear takes
        // what Super Submitter made. It does not take what the user wrote.
        for folder in [storage.projects, storage.archives, storage.artifacts,
                       storage.runs, storage.scratch] {
            try? FileManager.default.removeItem(at: folder)
        }

        // Every default this app writes, including the ones the views own
        // through @AppStorage. It walks the suite in use rather than removing
        // a domain by bundle identifier: a screenshot or demo run points at a
        // suite of its own, and clearing the domain would clear the real one
        // and leave the throwaway suite full. `removeObject` only reaches this
        // app's own values, so a global key read through here is left alone.
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }

        // Now the memory, so nothing writes a cleared key back on the way out.
        linkedApps = []
        manifest = Manifest()
        manifestURL = nil

        // Back to the first-run screen, which is where a new install starts.
        //
        // The tab first, and the order is the whole of it. Settings is where
        // the button was pressed and it stands on an empty window, so the
        // selection has to move or the erase finishes on the screen it was
        // ordered from. Moving it *after* the flag undoes the flag:
        // `selectedTab` clears the entry screen whenever it lands on a tab that
        // stands alone, which is exactly what Stores is.
        selectedTab = .stores
        showEntryScreen = true
        showOnboarding = true
    }

    func resetRunState() {
        stateGeneration &+= 1
        runTask?.cancel()
        runTask = nil
        runContinuation?.finish()
        runContinuation = nil
        eventTask?.cancel()
        eventTask = nil
        runner = nil
        pollTask?.cancel()
        pollTask = nil
        plan = nil
        storePlans = [:]
        actualState = ActualState()
        moneyReadApps.removeAll()
        fetchingStoreTab = nil
        consoleRows = []
        consoleMarks = []
        planReadFailures = []
        planReading = false
        acknowledged = []
        stepStates = []
        stepMeta = []
        runIndex = -1
        runDone = false
        runProgress = 0
        runDetail = ""
        clearRunLog()
        applied = false
        runFailure = nil
        providerFailure = nil
        statuses = [:]
        releaseError = nil
        appleSubmissionID = nil
        // Switching apps clears the run, so the Dock has to stop describing
        // the one that was open. Both signals go: a bar from an interrupted
        // upload and a badge counting another app's console steps.
        DockTile.clear()
        DockTile.badge(0)
    }

    /// Fills the credential fields of the Stores tab from the Keychain.
    /// Anything that writes a credential outside these fields calls it again,
    /// so the panels never ask for a file the app already holds.
    ///
    /// A store credential belongs to the account and not to the app. An App
    /// Store Connect key covers the team and a Play service account covers the
    /// developer account, so opening a second app loads the same key. This used
    /// to set both connections back to "Not connected" every time, and a
    /// developer who saw that on the app they had just added read it as "enter
    /// your key again". The status now falls only when the credential itself
    /// changes, which is the one thing that can invalidate it.
    /// The two store keys load whether an app is open or not.
    ///
    /// This used to return at the door when no app was linked, and the whole
    /// bug lived in that one line. Removing the last app left the fields empty,
    /// so "Update existing apps" asked for the `.p8` again on the next screen,
    /// and a developer who had entered it once was asked for it a second time
    /// by an app that still held it in the Keychain the whole time. The keys
    /// were never deleted. They were simply never read back.
    ///
    /// Only the two per-app credentials need an app. They describe one app, so
    /// with none open they are cleared rather than left showing the last one's.
    func loadCredentials() {
        do {
            let appleWas = [appleKeyID, appleIssuerID, applePrivateKeyPEM]
            let googleWas = googleCredentialIdentity

            let apple = try storeCredential(AppleCredential.self, kind: .apple)
            appleKeyID = apple?.keyID ?? ""
            appleIssuerID = apple?.issuerID ?? ""
            applePrivateKeyPEM = apple?.privateKeyPEM ?? ""
            appleCredentialFileName = apple?.fileName ?? ""

            let google = try storeCredential(GoogleServiceAccount.self, kind: .google)
            googleCredential = google
            googleCredentialFileName = google?.fileName ?? ""
            googleAccountEmail = google?.clientEmail ?? ""
            googleOAuthCredential = try storeCredential(
                GoogleOAuthCredential.self, kind: .googleOAuth)
            if defaults.object(forKey: googleCredentialChoiceKey) == nil,
               google == nil, googleOAuthCredential != nil {
                googleCredentialChoice = .oauth
            }

            let revenueCat = try credentialAccount.flatMap {
                try KeychainCredentials.load(RevenueCatCredential.self,
                                             kind: .revenueCat, account: $0)
            }
            revenueCatAPIKey = revenueCat?.apiKey ?? ""
            let reviewer = try credentialAccount.flatMap {
                try KeychainCredentials.load(ReviewerCredential.self,
                                             kind: .reviewAccount, account: $0)
            }
            reviewerUsername = reviewer?.username ?? ""
            reviewerPassword = reviewer?.password ?? ""

            if appleWas != [appleKeyID, appleIssuerID, applePrivateKeyPEM] {
                appleConnection = .notConnected
                // The visible apps came from the key that just went away.
                remoteAppleApps = []
            }
            if googleWas != googleCredentialIdentity {
                googleConnection = .notConnected
                // The visible apps came from the credential that just went away.
                remoteGoogleApps = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Forgets a store credential, from every app at once.
    ///
    /// One key covers the account, so removing it removes it everywhere. The
    /// panel confirms it first. Apple offers a `.p8` exactly once and never
    /// again, so this is the one credential action the app cannot undo, and
    /// the confirmation says so.
    func forgetCredential(for store: Store) {
        do {
            switch store {
            case .apple:
                try KeychainCredentials.delete(kind: .apple, account: storeAccount)
                if let credentialAccount {
                    try KeychainCredentials.delete(kind: .apple, account: credentialAccount)
                }
                appleKeyID = ""
                appleIssuerID = ""
                applePrivateKeyPEM = ""
                appleCredentialFileName = ""
                appleConnection = .notConnected
                remoteAppleApps = []
            case .google:
                try KeychainCredentials.delete(kind: .google, account: storeAccount)
                try KeychainCredentials.delete(kind: .googleOAuth, account: storeAccount)
                if let credentialAccount {
                    try KeychainCredentials.delete(kind: .google, account: credentialAccount)
                    try KeychainCredentials.delete(kind: .googleOAuth,
                                                   account: credentialAccount)
                }
                googleCredential = nil
                googleOAuthCredential = nil
                googleCredentialFileName = ""
                googleAccountEmail = ""
                googleConnection = .notConnected
                remoteGoogleApps = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Whether a store has a credential worth asking about before it goes.
    func hasCredential(for store: Store) -> Bool {
        switch store {
        case .apple: !applePrivateKeyPEM.isEmpty
        case .google:
            googleCredentialChoice == .oauth
                ? googleOAuthCredential != nil
                : googleCredential != nil
        }
    }

    private var googleCredentialIdentity: String {
        switch googleCredentialChoice {
        case .oauth: googleOAuthCredential?.refreshToken ?? ""
        case .serviceAccount: googleCredential?.clientEmail ?? ""
        }
    }

    /// Whether the credential card shows its fields.
    ///
    /// A connected store closes itself. The key is entered once, it covers
    /// every app on the account, and after that the card is four controls
    /// nobody touches again sitting above the store the developer came here to
    /// pick. A store that is not connected stays open, because entering the key
    /// is the whole job of the tab and it may not be behind a click.
    ///
    /// The dictionary is the override and not the state: a developer who opened
    /// a connected card keeps it open, and one who closed a card that later
    /// fails still meets the fields when the failure needs them.
    func credentialDetailsOpen(_ store: Store) -> Bool {
        if let chosen = credentialOpen[store] { return chosen }
        return !connection(for: store).isConnected
    }

    func toggleCredentialDetails(_ store: Store) {
        credentialOpen[store] = !credentialDetailsOpen(store)
    }

    /// Opens the card that holds a field, so the search can reach one that a
    /// connected store has folded away. `FieldIndex` names two of them.
    func revealCredentialDetails(forAnchor anchor: String) {
        guard anchor.hasPrefix("stores.") else { return }
        credentialOpen[anchor.contains("google") ? .google : .apple] = true
    }

    func connection(for store: Store) -> ConnectionStatus {
        switch store {
        case .apple: appleConnection
        case .google: googleConnection
        }
    }

    /// Reads a store credential, and adopts the copy an earlier version of the
    /// app saved under one app. The old item stays where it is, because a
    /// deleted `.p8` is gone: App Store Connect offers the file once.
    /// One of the two store keys, from the account copy that outlives every
    /// app, or from the copy an older build filed under the app that entered
    /// it.
    ///
    /// A key found under an app is promoted to the account, so it is found
    /// once and then belongs to the machine. That promotion is also what saves
    /// it from a removal: an app record is deleted with its id, and a key filed
    /// under that id would be orphaned in the Keychain with nothing left able
    /// to name it.
    private func storeCredential<T: Codable>(_ type: T.Type,
                                             kind: CredentialKind) throws -> T? {
        if let shared = try KeychainCredentials.load(type, kind: kind,
                                                    account: storeAccount) {
            return shared
        }
        guard let app = credentialAccount,
              let own = try KeychainCredentials.load(type, kind: kind,
                                                     account: app) else { return nil }
        try KeychainCredentials.save(own, kind: kind, account: storeAccount)
        return own
    }

    private func persistAppleCredential() throws {
        let credential = AppleCredential(
            keyID: appleKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
            issuerID: appleIssuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: applePrivateKeyPEM,
            fileName: appleCredentialFileName)
        try KeychainCredentials.save(credential, kind: .apple, account: storeAccount)
    }

    func syncStoreFieldsFromManifest() {
        appleAppID = manifest.apps.apple?.appId ?? ""
        appleBundleID = manifest.apps.apple?.bundleId ?? ""
        googlePackageName = manifest.apps.google?.packageName ?? ""
    }

    func syncEditingStateFromManifest() {
        provider = manifest.monetization?.provider ?? .none
        revenueCatProjectID = manifest.monetization?.revenuecat?.projectId ?? ""
        priceAmount = manifest.pricing.map { "\($0.base.amount)" } ?? ""
        priceCurrency = manifest.pricing?.base.currency ?? ""
        priceTerritory = manifest.pricing?.base.territory ?? ""
        purchasePriceInputs = [:]
        planPriceInputs = [:]
        offerPriceInputs = [:]
    }

    /// The one funnel every manifest edit ends at.
    ///
    /// The undo is registered here and nowhere else, so a tab that edits a
    /// field does not know undo exists and a tab written later inherits it.
    /// One edit. The undo step and the stale plan are immediate, because both
    /// are in memory; only the file waits for the typing to stop.
    func saveManifestReportingErrors() {
        registerManifestUndo()
        invalidatePlan()
        scheduleSave()
    }

    func invalidatePlan() {
        stateGeneration &+= 1
        planReading = false
        plan = nil
        storePlans = [:]
        acknowledged = []
        clearStoppedRun()
        refreshConsoleRows()
    }

    /// Rebuilds the release checklist from what the app now holds.
    ///
    /// The checklist is a function of the manifest, the last store read and the
    /// chosen stores, which is exactly what the plan is a function of, so it is
    /// rebuilt wherever the plan is thrown away.
    ///
    /// It used to be built in two places only: a store read, and opening an
    /// app. Every other way of satisfying a row left the banner saying the row
    /// was still open. Picking a build under Ship this build writes the number
    /// into `store.yaml` and the plan draws the attach row from it, and the
    /// banner on every screen went on reading "Every submission needs a build"
    /// until a read or an apply happened to rebuild the rows.
    ///
    /// Empty with no app open. The rows are about one app's submission, and an
    /// empty manifest would answer for a submission nobody is preparing.
    func refreshConsoleRows() {
        guard manifestURL != nil else {
            consoleRows = []
            refreshDockBadge()
            return
        }
        consoleRows = ConsoleChecklist.rows(manifest: manifest, actual: actualState,
                                            stores: stores)
        refreshDockBadge()
    }

    func persistLinkedApps() {
        do {
            let data = try JSONEncoder().encode(linkedApps)
            defaults.set(data, forKey: linkedAppsDefaultsKey)
        } catch {
            errorMessage = "The app list could not be saved. \(error.localizedDescription)"
        }
    }

    private func updateLinkedAppNameFromManifest() {
        guard linkedApps.indices.contains(selectedAppIndex),
              let listing = manifest.listing,
              let name = listing.locales[listing.defaultLocale]?.name,
              !name.isEmpty else { return }
        linkedApps[selectedAppIndex].name = name
        persistLinkedApps()
    }

    private func manifestPath(for file: URL) -> String {
        guard let root = manifestURL?.deletingLastPathComponent().standardizedFileURL else {
            return file.path
        }
        let target = file.standardizedFileURL
        let rootParts = root.pathComponents
        let targetParts = target.pathComponents
        guard targetParts.starts(with: rootParts) else { return target.path }
        return targetParts.dropFirst(rootParts.count).joined(separator: "/")
    }

    private static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    private static func csv(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func displayName(from folderName: String) -> String {
        folderName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func normalizedLocale(_ raw: String) -> String {
        let pieces = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard let language = pieces.first else { return "" }
        return ([language.lowercased()] + pieces.dropFirst().map { piece in
            if piece.count == 4 { return piece.prefix(1).uppercased() + piece.dropFirst().lowercased() }
            if piece.count == 2 { return piece.uppercased() }
            return piece
        }).joined(separator: "-")
    }

    private static func isValidLocale(_ code: String) -> Bool {
        code.range(of: #"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$"#,
                   options: .regularExpression) != nil
    }
}

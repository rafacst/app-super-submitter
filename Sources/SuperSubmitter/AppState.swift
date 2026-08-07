import AppKit
import Foundation
import Observation
import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

struct LinkedAppRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var manifestPath: String
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

enum PurchaseTextField { case id, name, amount, currency, entitlement }
enum PlanTextField { case id, duration, basePlanID, amount, currency, entitlement, packageKey }

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
struct TabBadge {
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
    @ObservationIgnored var applePrivateKeyPEM = ""
    @ObservationIgnored var googleCredential: GoogleServiceAccount?
    @ObservationIgnored private let linkedAppsDefaultsKey = "linkedApps.v1"
    @ObservationIgnored private let lastOpenAppKey = "lastOpenApp.v1"
    @ObservationIgnored private let modeDefaultsKey = "mode.v1"

    // The manifest and the file behind it.
    var manifest = Manifest()
    var manifestURL: URL?
    var linkedApps: [LinkedAppRecord] = []
    var errorMessage: String?

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
        }
    }
    var selectedTab: Tab = .stores {
        didSet {
            guard selectedTab != oldValue else { return }
            // Picking a tab answers the entry screen: you asked for the two
            // doors and then chose a third thing instead. Without this,
            // pressing "Add app" and changing your mind left the flag set, and
            // the entry screen covered every footer tab you went to next.
            if selectedTab.standsAlone { showEntryScreen = false }
            // A tab names its own mode. Anything that jumps to one, such as
            // the import landing on Build, switches the shell rather than
            // showing a tab the sidebar hides.
            guard !selectedTab.modes.contains(mode),
                  let owner = selectedTab.modes.first else { return }
            mode = owner
        }
    }
    var selectedAppIndex = 0

    /// Settings opens as a panel over the window, not as a second window.
    var showSettings = false
    /// What the app is, who makes it, and how to reach a person. It sits at
    /// the foot of the sidebar and under the app menu, the two places a Mac
    /// user looks for it.
    var showAbout = false
    var showOnboarding = false
    var showExistingAppImport = false
    /// Shows the entry screen over an app that is already open.
    ///
    /// "Add app" used to open a folder picker, which answers one of the three
    /// doors before the developer has chosen a door. Any app that opens clears
    /// this, so nothing has to remember to put it back.
    var showEntryScreen = false
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

    // Paid access. Every gate reads `entitlement`; nothing keeps its own
    // `isPaid` boolean. See AppStateAccess.swift.
    /// The gate every mutation boundary in SubmitKit receives. It refuses
    /// until `configureAccess` replaces it.
    @ObservationIgnored var access: any AccessGate = UnconfiguredAccess()
    @ObservationIgnored var accessController: AccessController?
    @ObservationIgnored var authController: SupabaseAuth?
    var entitlement = Entitlement.free(at: .distantPast)
    /// What sent the developer to the Account tab, or nil if they walked
    /// there themselves. It is the line at the top of that tab and nothing
    /// else: the plans, the code, and the checkout live on the tab whether a
    /// gate opened it or not.
    var paywallReason: PaywallTrigger?
    var billingPlans: BillingPlans?
    var billingOperation: BillingOperation = .idle
    var billingMessage: String?
    var selectedPlan = "annual"
    var promotionCode = ""
    var promotionPreview: PromotionPreview?
    /// The address the Supabase account is signed in with.
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

    // Tab 1.
    var appleGuideOpen = false
    var googleGuideOpen = false
    var appleKeyID = ""
    var appleIssuerID = ""
    var appleCredentialFileName = ""
    var appleAppID = ""
    var appleBundleID = ""
    var googlePackageName = ""
    var googleCredentialFileName = ""
    var googleAccountEmail = ""
    var appleConnection: ConnectionStatus = .notConnected
    var googleConnection: ConnectionStatus = .notConnected
    var remoteAppleApps: [RemoteStoreApp] = []
    var listingImportStatus: ConnectionStatus = .notConnected

    // Tab 2.
    /// Build from Project. upload-spec section 10.
    @ObservationIgnored lazy var buildFlow = BuildFlow(app: self)
    var showBuildFromProject = false
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
    /// The plan the button counts its rows from. `stateGeneration` covers the
    /// store read and the manifest covers the edits, so the pair is the whole
    /// input of a plan. See `directPlan()`.
    @ObservationIgnored
    var directPlanCache: (generation: Int, manifest: Manifest, plan: PlanResult)?

    // Tab 3.
    var locale = ""

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
    private var purchasePriceInputs: [Int: CatalogPriceInput] = [:]
    private var planPriceInputs: [String: CatalogPriceInput] = [:]
    var offerPriceInputs: [String: CatalogPriceInput] = [:]

    // Tab 6.
    var reviewerUsername = ""
    var reviewerPassword = ""
    var showAgeRating = false
    var showDataSafety = false

    // Tab 7. The plan.
    var plan: PlanResult?
    var planReading = false
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
    var logLines: [String] = []
    var logOpen = false
    var applied = false
    var runFailure: RunFailure?
    var providerFailure: String?

    // Tab 9. The checklist, the status, and the two buttons.
    var actualState = ActualState()
    /// What the stores hold right now. The import fills it, and so does every
    /// read, and the editing tabs show it beside the value being written.
    var storeSnapshot = StoreSnapshot()
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

    init(defaults: UserDefaults = .standard, storeAccount: String = "store-credentials") {
        self.defaults = defaults
        self.storeAccount = storeAccount
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
        appleVendorNumber = defaults.string(forKey: "appleVendorNumber") ?? ""
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
            let version = loaded?.release?.versionName ?? "No version"
            let selected = index == selectedAppIndex
            return AppSummary(
                id: record.id,
                name: record.name,
                initials: Self.initials(for: record.name),
                // The same rule as the run and as the Media tab: relative to
                // the manifest, absolute when it says so, and nil when the
                // file is gone. The row then draws the initials.
                icon: loaded?.media?.icon.flatMap {
                    Planner.resolve($0, root: url.deletingLastPathComponent())
                },
                summary: "\(version) · \(summary(for: loaded, selected: selected))",
                apple: health(.apple, manifest: loaded, selected: selected),
                google: health(.google, manifest: loaded, selected: selected))
        }
    }

    private func summary(for loaded: Manifest?, selected: Bool) -> String {
        if selected, let plan {
            let count = plan.steps.count
            if plan.isBlocked {
                let errors = plan.errors.count
                return "\(errors) \(errors == 1 ? "error blocks" : "errors block") the plan"
            }
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
        // An error blocks the whole apply, so it marks every store.
        guard !plan.isBlocked else { return .blocked }
        let system: PlanSystem = store == .apple ? .apple : .google
        return plan.steps(for: system).isEmpty ? .matched : .changed
    }

    // MARK: - The YAML toggle

    /// The raw block behind the open tab, or nil for a tab that edits nothing.
    var yamlBlock: ManifestBlock? {
        switch selectedTab {
        case .stores: .stores
        case .build: .build
        case .details: .details
        case .media: .media
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
        panel.message = "Choose the folder of your app. Super Submitter keeps one small file inside it."
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
        panel.message = "Choose the store.yaml file of the app you want to continue."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        link(manifestAt: url)
    }

    /// Both doors end here: read the file, add it once, and select it.
    func link(manifestAt url: URL) {
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
                manifestPath: url.path)
            linkedApps.append(record)
            persistLinkedApps()
            activateLinkedApp(at: linkedApps.count - 1)
            selectedTab = .stores
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
                let suffix = apps.count == 1 ? "app" : "apps"
                appleConnection = .connected("Connected · \(apps.count) \(suffix) visible")
            } catch {
                guard generation == stateGeneration else { return }
                appleConnection = .failed(error.localizedDescription)
            }
        }
    }

    /// Saves the service account, then calls Google with it.
    ///
    /// The save was only on the import before, which was true but not obvious
    /// from a button that now says Connect. Saving here as well costs one
    /// Keychain write and makes the label mean exactly what it says.
    func connectGoogleStore() {
        guard let credential = googleCredential else {
            googleConnection = .failed("Choose the service-account JSON first.")
            return
        }
        googleConnection = .connecting
        Task {
            do {
                try KeychainCredentials.save(credential, kind: .google,
                                             account: storeAccount)
                let message = try await StoreConnectionClient().testGoogle(
                    credential: credential, packageName: googlePackageName)
                googleConnection = .connected(message)
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

    func importExistingListing() {
        if stores.contains(.apple),
           (applePrivateKeyPEM.isEmpty || appleKeyID.isEmpty || appleIssuerID.isEmpty || appleAppID.isEmpty) {
            listingImportStatus = .failed("Connect App Store and choose an app on Stores first.")
            return
        }
        if stores.contains(.google), (googleCredential == nil || googlePackageName.isEmpty) {
            listingImportStatus = .failed("Connect Google Play and enter its package name on Stores first.")
            return
        }

        let appleCredential = AppleCredential(
            keyID: appleKeyID, issuerID: appleIssuerID,
            privateKeyPEM: applePrivateKeyPEM, fileName: appleCredentialFileName)
        let googleCredential = googleCredential
        listingImportStatus = .connecting
        Task {
            do {
                let client = StoreConnectionClient()
                if stores.contains(.apple) {
                    let imported = try await client.importApple(
                        appID: appleAppID, credential: appleCredential)
                    manifest.mergeAppleImport(imported)
                    await adopt(imported, store: .apple)
                }
                if stores.contains(.google), let googleCredential {
                    let imported = try await client.importGoogle(
                        credential: googleCredential, packageName: googlePackageName)
                    manifest.mergeGoogleImport(imported)
                    await adopt(imported, store: .google)
                }
                // An import rewrites the listing wholesale, so it is the edit
                // a developer most often wants back.
                registerManifestUndo()
                try save()
                storeSnapshot.save(toRoot: manifestURL?.deletingLastPathComponent())
                locale = manifest.listing?.defaultLocale ?? locale
                updateLinkedAppNameFromManifest()
                listingImportStatus = .connected("Imported \(manifest.listing?.locales.count ?? 0) locales into store.yaml")
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
            } catch {
                readingPackages.remove(kind)
                packageErrors[kind] = error.localizedDescription
            }
        }
    }

    func chooseBuildFiles(allowedExtensions: Set<String>) {
        let panel = NSOpenPanel()
        panel.title = "Choose a build"
        panel.message = "Choose \(allowedExtensions.sorted().map { ".\($0)" }.joined(separator: " or "))."
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
        panel.message = "Choose \(allowedExtensions.sorted().map { ".\($0)" }.joined(separator: " or "))."
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
    var releaseVersionBinding: Binding<String> {
        Binding(
            get: { self.manifest.release?.versionName ?? "" },
            set: {
                self.manifest.setReleaseVersionName($0)
                self.saveManifestReportingErrors()
            })
    }

    /// What the App Store shows customers, once a read has said so.
    var liveAppleVersion: String? { actualState.apple?.liveVersionString }

    /// The smallest number that clears the one on sale. Apple refuses a
    /// version that does not climb, and the last component is the one a fix
    /// usually moves.
    var nextAppleVersion: String? {
        guard let live = liveAppleVersion else { return nil }
        var parts = live.split(separator: ".").map { Int($0) ?? 0 }
        guard !parts.isEmpty else { return nil }
        parts[parts.count - 1] += 1
        return parts.map(String.init).joined(separator: ".")
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

    func mediaPaths(deviceClass: Manifest.DeviceClass, previews: Bool = false) -> [String] {
        manifest.mediaPaths(locale: locale, deviceClass: deviceClass, previews: previews)
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

    func chooseMediaFiles(deviceClass: Manifest.DeviceClass, previews: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = previews ? "Choose app previews" : "Choose screenshots"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let extensions = previews ? ["mov", "m4v", "mp4"] : ["png", "jpg", "jpeg"]
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        addMediaFiles(panel.urls, deviceClass: deviceClass, previews: previews)
    }

    func addMediaFiles(_ urls: [URL], deviceClass: Manifest.DeviceClass,
                       previews: Bool = false) {
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
                let limit = stores.contains(.google) ? 8 : 10
                let existing = mediaPaths(deviceClass: deviceClass)
                guard existing.count + urls.count <= limit else {
                    throw MediaInputError.tooMany(limit: limit)
                }
                var paths: [String] = []
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    _ = try AssetInspector.validateImage(at: url, deviceClass: deviceClass,
                                                         stores: stores)
                    paths.append(manifestPath(for: url))
                }
                manifest.addMediaPaths(paths, locale: locale, deviceClass: deviceClass)
                saveManifestReportingErrors()
                mediaError = nil
            } catch {
                mediaError = error.localizedDescription
            }
        }
    }

    func moveMedia(_ path: String, by offset: Int, deviceClass: Manifest.DeviceClass,
                   previews: Bool = false) {
        manifest.moveMediaPath(path, by: offset, locale: locale, deviceClass: deviceClass,
                               previews: previews)
        saveManifestReportingErrors()
    }

    /// Drops one screenshot onto the place another one holds.
    ///
    /// The tiles sit in a horizontal row and not a `List`, so there is no
    /// `onMove` to inherit. The two arrow buttons stay: they are the keyboard
    /// route, and Full Keyboard Access cannot drag.
    func moveMedia(_ path: String, before other: String,
                   deviceClass: Manifest.DeviceClass, previews: Bool = false) {
        let paths = mediaPaths(deviceClass: deviceClass, previews: previews)
        guard path != other, let target = paths.firstIndex(of: other) else { return }
        manifest.moveMediaPath(path, to: target, locale: locale, deviceClass: deviceClass,
                               previews: previews)
        saveManifestReportingErrors()
    }

    func removeMedia(_ path: String, deviceClass: Manifest.DeviceClass,
                     previews: Bool = false) {
        manifest.removeMediaPath(path, locale: locale, deviceClass: deviceClass,
                                 previews: previews)
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
            manifest.pricing = Manifest.Pricing(
                base: price,
                autoConvertOtherTerritories: manifest.pricing?.autoConvertOtherTerritories ?? true)
            saveManifestReportingErrors()
            moneyError = nil
        }
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

    func reviewerCredentialsChanged() {
        do {
            try KeychainCredentials.save(
                ReviewerCredential(username: reviewerUsername, password: reviewerPassword),
                kind: .reviewAccount, account: try requireCredentialAccount())
        } catch { errorMessage = error.localizedDescription }
    }

    func reviewAnswerBinding(group: String, key: String) -> Binding<Bool> {
        Binding(get: {
            if group == "age" { return self.manifest.review?.ageRatingAnswers?[key] ?? false }
            return self.manifest.review?.dataSafetyAnswers?[key] ?? false
        }, set: { value in
            var review = self.manifest.review ?? Manifest.Review()
            if group == "age" {
                var answers = review.ageRatingAnswers ?? [:]
                answers[key] = value
                review.ageRatingAnswers = answers
            } else {
                var answers = review.dataSafetyAnswers ?? [:]
                answers[key] = value
                review.dataSafetyAnswers = answers
            }
            self.manifest.review = review
            self.saveManifestReportingErrors()
        })
    }

    var encryptionBinding: Binding<Bool> {
        Binding(get: { self.manifest.review?.usesNonExemptEncryption ?? false }, set: { value in
            var review = self.manifest.review ?? Manifest.Review()
            review.usesNonExemptEncryption = value
            self.manifest.review = review
            self.saveManifestReportingErrors()
        })
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
        case .details: target = .details
        case .media: target = .media
        case .money: target = .money
        case .marketing: target = .marketing
        case .reviewInfo: target = .reviewInfo
        case .plan: target = nil
        default: return nil
        }
        let findings = tab == .plan
            ? plan.findings
            : plan.findings.filter { $0.fix == target }
        guard !findings.isEmpty else { return nil }
        let errors = findings.filter { $0.severity == .error }.count
        return TabBadge(errors: errors, warnings: findings.count - errors)
    }

    var planIsBlocked: Bool {
        plan.map(\.isBlocked) ?? (listingErrorCount > 0)
    }

    var hasProvider: Bool { provider != .none }

    private var listingErrorCount: Int {
        manifest.listingErrorCount(for: stores)
    }

    // MARK: - The manifest file

    func load(from url: URL) throws {
        // Before the document is swapped, or a coalesced write still holding
        // this app's last keystroke would land against the next app's file.
        flushSave()
        manifest = try ManifestFile.load(from: url)
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

    /// Writes whatever is waiting. It costs nothing when nothing is.
    func flushSave() {
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
            applyDryRunDefault()
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent). \(error.localizedDescription)"
        }
    }

    /// Spec 16.5 and 17: the dry run is on by default **for a new app**. An
    /// app with a run log is not new, so its own toggle stays where it was.
    private func applyDryRunDefault() {
        guard let root = manifestRoot else { return }
        let runs = root.appendingPathComponent(".super-submitter/runs")
        let hasRun = (try? FileManager.default.contentsOfDirectory(atPath: runs.path))?
            .isEmpty == false
        dryRun = hasRun ? false : (defaults.object(forKey: "dryRunByDefault")
            as? Bool ?? true)
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
        actualState = ActualState()
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
        logLines = []
        applied = false
        runFailure = nil
        providerFailure = nil
        statuses = [:]
        releaseError = nil
        appleSubmissionID = nil
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
            let googleWas = googleCredential?.clientEmail ?? ""

            let apple = try storeCredential(AppleCredential.self, kind: .apple)
            appleKeyID = apple?.keyID ?? ""
            appleIssuerID = apple?.issuerID ?? ""
            applePrivateKeyPEM = apple?.privateKeyPEM ?? ""
            appleCredentialFileName = apple?.fileName ?? ""

            let google = try storeCredential(GoogleServiceAccount.self, kind: .google)
            googleCredential = google
            googleCredentialFileName = google?.fileName ?? ""
            googleAccountEmail = google?.clientEmail ?? ""

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
            if googleWas != (googleCredential?.clientEmail ?? "") {
                googleConnection = .notConnected
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
                if let credentialAccount {
                    try KeychainCredentials.delete(kind: .google, account: credentialAccount)
                }
                googleCredential = nil
                googleCredentialFileName = ""
                googleAccountEmail = ""
                googleConnection = .notConnected
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Whether a store has a credential worth asking about before it goes.
    func hasCredential(for store: Store) -> Bool {
        switch store {
        case .apple: !applePrivateKeyPEM.isEmpty
        case .google: googleCredential != nil
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
        acknowledged = []
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

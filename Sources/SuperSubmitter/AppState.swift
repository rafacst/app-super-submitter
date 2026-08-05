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
    case notTested
    case testing
    case connected(String)
    case failed(String)

    var label: String {
        switch self {
        case .notTested: "Not tested"
        case .testing: "Testing…"
        case .connected(let message): message
        case .failed(let message): message
        }
    }

    var isConnected: Bool {
        if case .connected = self { true } else { false }
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

@Observable
@MainActor
final class AppState {
    @ObservationIgnored var runTask: Task<Void, Never>?
    @ObservationIgnored var runner: Runner?
    @ObservationIgnored var eventTask: Task<Void, Never>?
    @ObservationIgnored var runContinuation: AsyncStream<RunEvent>.Continuation?
    @ObservationIgnored var pollTask: Task<Void, Never>?
    @ObservationIgnored var stateGeneration = 0
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
    var showOnboarding = false
    var showExistingAppImport = false
    /// The index of the app the user asked to remove. It holds the choice
    /// while the confirmation is open.
    var appPendingRemoval: Int?
    var releaseSheet: Store?
    var showAddLocale = false

    // Paid access. Every gate reads `entitlement`; nothing keeps its own
    // `isPaid` boolean. See AppStateAccess.swift.
    /// The gate every mutation boundary in SubmitKit receives. It refuses
    /// until `configureAccess` replaces it.
    @ObservationIgnored var access: any AccessGate = UnconfiguredAccess()
    @ObservationIgnored var accessController: AccessController?
    @ObservationIgnored var authController: SupabaseAuth?
    var entitlement = Entitlement.free(at: .distantPast)
    var paywall: PaywallTrigger?
    /// A paywall that waits for the Settings sheet to close. See openPaywall.
    var pendingPaywall: PaywallTrigger?
    var billingPlans: BillingPlans?
    var billingOperation: BillingOperation = .idle
    var billingMessage: String?
    var selectedPlan = "annual"
    var promotionCode = ""
    var promotionPreview: PromotionPreview?
    /// The address the Supabase account is signed in with.
    var accountEmail: String?
    var showAccount = false
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
    var appleConnection: ConnectionStatus = .notTested
    var googleConnection: ConnectionStatus = .notTested
    var remoteAppleApps: [RemoteStoreApp] = []
    var listingImportStatus: ConnectionStatus = .notTested

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
    var revenueCatConnection: ConnectionStatus = .notTested
    var adaptyConnection: ConnectionStatus = .notTested
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
    var planError: String?
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
        if let data = defaults.data(forKey: linkedAppsDefaultsKey),
           let decoded = try? JSONDecoder().decode([LinkedAppRecord].self, from: data) {
            linkedApps = decoded.filter { FileManager.default.fileExists(atPath: $0.manifestPath) }
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
        if !linkedApps.isEmpty { activateLinkedApp(at: index) }
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
    private func health(_ store: Store, manifest loaded: Manifest?,
                        selected: Bool) -> StoreHealth {
        let configured = store == .apple ? loaded?.apps.apple != nil : loaded?.apps.google != nil
        guard configured else { return .blocked }
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
            manifest = Manifest()
            manifestURL = nil
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
            appleConnection = .notTested
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
            googleConnection = .notTested
        } catch {
            errorMessage = "That service-account file could not be imported. \(error.localizedDescription)"
        }
    }

    func appleCredentialFieldsChanged() {
        guard !applePrivateKeyPEM.isEmpty else { return }
        do { try persistAppleCredential() }
        catch { errorMessage = error.localizedDescription }
        appleConnection = .notTested
    }

    func testAppleConnection() {
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
        appleConnection = .testing
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

    func testGoogleConnection() {
        guard let credential = googleCredential else {
            googleConnection = .failed("Choose the service-account JSON first.")
            return
        }
        googleConnection = .testing
        Task {
            do {
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
        listingImportStatus = .testing
        Task {
            do {
                let client = StoreConnectionClient()
                if stores.contains(.apple) {
                    let imported = try await client.importApple(
                        appID: appleAppID, credential: appleCredential)
                    manifest.mergeAppleImport(imported)
                }
                if stores.contains(.google), let googleCredential {
                    let imported = try await client.importGoogle(
                        credential: googleCredential, packageName: googlePackageName)
                    manifest.mergeGoogleImport(imported)
                }
                try save()
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

    func useReleaseVersion(_ version: String) {
        manifest.setReleaseVersionName(version)
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

    func mediaPaths(deviceClass: Manifest.DeviceClass, previews: Bool = false) -> [String] {
        manifest.mediaPaths(locale: locale, deviceClass: deviceClass, previews: previews)
    }

    func mediaURL(for path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        if url.path.hasPrefix("/") { return url }
        return manifestURL?.deletingLastPathComponent().appendingPathComponent(path) ?? url
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
            revenueCatConnection = .notTested
        } catch { errorMessage = error.localizedDescription }
    }

    func testRevenueCatConnection() {
        revenueCatConnection = .testing
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
        adaptyConnection = .testing
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
        values.append(ManifestDrafts.purchase())
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
        groups.append(ManifestDrafts.subscriptionGroup())
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
        manifest.subscriptions?[groupIndex].plans.append(ManifestDrafts.subscriptionPlan())
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
        values.append(ManifestDrafts.entitlement())
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
        values.append(ManifestDrafts.offering(isFirst: values.isEmpty))
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

    /// The count of open items per tab, and how loud each one is.
    ///
    /// A badge is red when the tab holds an error and yellow when it holds
    /// only warnings. Red means "this blocks the apply", so it must never
    /// appear on a tab that holds no error.
    func badge(for tab: Tab) -> (count: Int, severity: Severity)? {
        if applied { return nil }
        // Before the first read the only rule the app can run is the text
        // limit, because every other rule needs the store side.
        guard let plan else {
            let count = listingErrorCount
            guard count > 0 else { return nil }
            return tab == .details || tab == .plan ? (count, .error) : nil
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
        let severity: Severity = findings.contains { $0.severity == .error } ? .error : .warning
        return (findings.count, severity)
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
        manifest = try ManifestFile.load(from: url)
        manifestURL = url
        syncStoreFieldsFromManifest()
        syncEditingStateFromManifest()
    }

    func save() throws {
        guard let manifestURL else { return }
        try ManifestFile.save(manifest, to: manifestURL)
        lastSavedAt = Date()
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
        planError = nil
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

    /// Fills the credential fields of tab 1 from the Keychain of the open app.
    /// Anything that writes a credential outside these fields calls it again,
    /// so the panels never ask for a file the app already holds.
    func loadCredentials() {
        guard let credentialAccount else { return }
        do {
            let apple = try storeCredential(AppleCredential.self, kind: .apple,
                                            savedUnder: credentialAccount)
            appleKeyID = apple?.keyID ?? ""
            appleIssuerID = apple?.issuerID ?? ""
            applePrivateKeyPEM = apple?.privateKeyPEM ?? ""
            appleCredentialFileName = apple?.fileName ?? ""

            let google = try storeCredential(GoogleServiceAccount.self, kind: .google,
                                             savedUnder: credentialAccount)
            googleCredential = google
            googleCredentialFileName = google?.fileName ?? ""
            googleAccountEmail = google?.clientEmail ?? ""
            let revenueCat = try KeychainCredentials.load(
                RevenueCatCredential.self, kind: .revenueCat, account: credentialAccount)
            revenueCatAPIKey = revenueCat?.apiKey ?? ""
            let reviewer = try KeychainCredentials.load(
                ReviewerCredential.self, kind: .reviewAccount, account: credentialAccount)
            reviewerUsername = reviewer?.username ?? ""
            reviewerPassword = reviewer?.password ?? ""
            appleConnection = .notTested
            googleConnection = .notTested
            remoteAppleApps = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reads a store credential, and adopts the copy an earlier version of the
    /// app saved under one app. The old item stays where it is, because a
    /// deleted `.p8` is gone: App Store Connect offers the file once.
    private func storeCredential<T: Codable>(_ type: T.Type, kind: CredentialKind,
                                             savedUnder app: String) throws -> T? {
        if let shared = try KeychainCredentials.load(type, kind: kind,
                                                    account: storeAccount) {
            return shared
        }
        guard let own = try KeychainCredentials.load(type, kind: kind,
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

    private func syncStoreFieldsFromManifest() {
        appleAppID = manifest.apps.apple?.appId ?? ""
        appleBundleID = manifest.apps.apple?.bundleId ?? ""
        googlePackageName = manifest.apps.google?.packageName ?? ""
    }

    private func syncEditingStateFromManifest() {
        provider = manifest.monetization?.provider ?? .none
        revenueCatProjectID = manifest.monetization?.revenuecat?.projectId ?? ""
        priceAmount = manifest.pricing.map { "\($0.base.amount)" } ?? ""
        priceCurrency = manifest.pricing?.base.currency ?? ""
        priceTerritory = manifest.pricing?.base.territory ?? ""
        purchasePriceInputs = [:]
        planPriceInputs = [:]
        offerPriceInputs = [:]
    }

    func saveManifestReportingErrors() {
        do {
            try save()
            invalidatePlan()
        }
        catch { errorMessage = "The manifest could not be saved. \(error.localizedDescription)" }
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

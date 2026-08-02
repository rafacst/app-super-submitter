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

/// Where the tabs live. Spec section 16.1.
enum NavigationPosition: String, CaseIterable, Identifiable {
    case sidebar, topBar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sidebar: "Sidebar"
        case .topBar: "Top bar"
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
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var applePrivateKeyPEM = ""
    @ObservationIgnored private var googleCredential: GoogleServiceAccount?
    @ObservationIgnored private let linkedAppsDefaultsKey = "linkedApps.v1"

    // The manifest and the file behind it.
    var manifest = Manifest()
    var manifestURL: URL?
    var linkedApps: [LinkedAppRecord] = []
    var errorMessage: String?

    // Navigation.
    var selectedTab: Tab = .stores
    var selectedAppIndex = 0
    var switcherOpen = false

    /// Settings opens as a panel over the window, not as a second window.
    var showSettings = false
    var showOnboarding = false
    var onboardingStep = 0
    var menuBarOpen = false
    var releaseSheet: Store?
    var showAddLocale = false

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
    var buildRead = false
    var packages: [AppPackage.Kind: AppPackage] = [:]
    var packageErrors: [AppPackage.Kind: String] = [:]
    var readingPackages: Set<AppPackage.Kind> = []

    // Tab 3.
    var locale = "en-US"
    var keywordsFixed = false

    // Tab 5.
    var provider: Manifest.Provider = .revenuecat

    // Tab 7.
    var dryRun = false
    var acknowledged: Set<String> = []

    // Tab 8.
    var runIndex = -1
    var runDone = false
    var runProgress = 0.0
    var logOpen = false
    var applied = false

    // Tab 9.
    var checked: Set<String> = []
    var rechecked = false
    var appleReleased = false
    var googleReleased = false

    init() {
        if let data = UserDefaults.standard.data(forKey: linkedAppsDefaultsKey),
           let decoded = try? JSONDecoder().decode([LinkedAppRecord].self, from: data) {
            linkedApps = decoded.filter { FileManager.default.fileExists(atPath: $0.manifestPath) }
        }
        if !linkedApps.isEmpty { activateLinkedApp(at: 0) }
    }

    var appRows: [DemoApp] {
        guard !linkedApps.isEmpty else { return DemoData.apps }
        return linkedApps.map { record in
            let url = URL(fileURLWithPath: record.manifestPath)
            let loaded = try? ManifestFile.load(from: url)
            let version = loaded?.release?.versionName ?? "No version"
            let storeCount = [loaded?.apps.apple != nil, loaded?.apps.google != nil].filter { $0 }.count
            return DemoApp(
                name: record.name,
                initials: Self.initials(for: record.name),
                summary: "\(version) · \(storeCount) \(storeCount == 1 ? "store" : "stores")",
                apple: loaded?.apps.apple == nil ? .blocked : .changed,
                google: loaded?.apps.google == nil ? .blocked : .changed)
        }
    }

    var currentApp: DemoApp {
        let rows = appRows
        return rows[min(selectedAppIndex, max(0, rows.count - 1))]
    }

    var stores: Set<Store> {
        if linkedApps.isEmpty, manifestURL == nil { return [.apple, .google] }
        var result: Set<Store> = []
        if manifest.apps.apple != nil { result.insert(.apple) }
        if manifest.apps.google != nil { result.insert(.google) }
        return result
    }

    var locales: [String] {
        let values = manifest.listing?.locales.keys.sorted() ?? []
        return values.isEmpty && linkedApps.isEmpty ? ["en-US", "pt-BR"] : values
    }

    // MARK: - Linked apps and manifest editing

    func selectApp(at index: Int) {
        selectedAppIndex = index
        guard !linkedApps.isEmpty else { return }
        activateLinkedApp(at: index)
    }

    func chooseNewAppLocation() {
        let panel = NSSavePanel()
        panel.title = "Create a Super Submitter app"
        panel.message = "Choose the repository folder and save its manifest as store.yaml."
        panel.nameFieldStringValue = ManifestFile.defaultName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            var newManifest = Manifest()
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let appName = Self.displayName(from: folderName)
            newManifest.addLocale("en-US", name: appName)
            try ManifestFile.save(newManifest, to: url)
            let record = LinkedAppRecord(id: UUID(), name: appName, manifestPath: url.path)
            linkedApps.append(record)
            persistLinkedApps()
            selectedAppIndex = linkedApps.count - 1
            activateLinkedApp(at: selectedAppIndex)
            selectedTab = .stores
        } catch {
            errorMessage = error.localizedDescription
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
            try KeychainCredentials.save(credential, kind: .google, account: credentialAccount)
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
        appleConnection = .testing
        Task {
            do {
                try KeychainCredentials.save(credential, kind: .apple, account: credentialAccount)
                let apps = try await StoreConnectionClient().appleApps(credential: credential)
                remoteAppleApps = apps
                let suffix = apps.count == 1 ? "app" : "apps"
                appleConnection = .connected("Connected · \(apps.count) \(suffix) visible")
            } catch {
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

    func useReleaseVersion(_ version: String) {
        manifest.setReleaseVersionName(version)
        saveManifestReportingErrors()
    }

    // MARK: - The badges

    /// The count of open items per tab, and how loud each one is.
    ///
    /// A badge is red when the tab holds an error and yellow when it holds
    /// only warnings. Red means "this blocks the apply", so it must never
    /// appear on a tab that holds no error.
    func badge(for tab: Tab) -> (count: Int, severity: Severity)? {
        if applied { return nil }
        switch tab {
        case .details:
            return keywordsFixed ? nil : (1, .error)
        case .reviewInfo:
            return (2, .warning)
        case .plan:
            return keywordsFixed ? (2, .warning) : (3, .error)
        default:
            return nil
        }
    }

    var planIsBlocked: Bool { !keywordsFixed }
    var hasProvider: Bool { provider != .none }

    // MARK: - The run

    func startRun() {
        guard !planIsBlocked, !applied else { return }
        runTask?.cancel()
        runIndex = 0
        runDone = false
        runProgress = 0

        runTask = Task { [weak self] in
            guard let self else { return }

            for (index, item) in DemoData.runItems.enumerated() {
                guard !Task.isCancelled else { return }
                runIndex = index
                runProgress = 0

                let tickCount = item.isGroup ? 1 : (item.long ? 22 : 3)
                for tick in 1...tickCount {
                    do {
                        try await Task.sleep(for: .milliseconds(110))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    runProgress = Double(tick) / Double(tickCount)
                }
            }

            finishRun()

            do {
                try await Task.sleep(for: .milliseconds(1_600))
            } catch {
                return
            }
            guard runDone else { return }
            selectedTab = .release
        }
    }

    func finishRun() {
        runIndex = DemoData.runItems.count
        runDone = true
        runProgress = 1
        applied = true
    }

    func resetDemo() {
        runTask?.cancel()
        runTask = nil
        selectedTab = .stores
        buildRead = false
        keywordsFixed = false
        applied = false
        runIndex = -1
        runDone = false
        runProgress = 0
        checked = []
        rechecked = false
        appleReleased = false
        googleReleased = false
        acknowledged = []
        packages = [:]
        packageErrors = [:]
        readingPackages = []
    }

    // MARK: - The manifest file

    func load(from url: URL) throws {
        manifest = try ManifestFile.load(from: url)
        manifestURL = url
        syncStoreFieldsFromManifest()
    }

    func save() throws {
        guard let manifestURL else { return }
        try ManifestFile.save(manifest, to: manifestURL)
    }

    private var credentialAccount: String {
        guard !linkedApps.isEmpty,
              linkedApps.indices.contains(selectedAppIndex) else { return "demo" }
        return linkedApps[selectedAppIndex].id.uuidString
    }

    private func activateLinkedApp(at index: Int) {
        guard linkedApps.indices.contains(index) else { return }
        selectedAppIndex = index
        let url = URL(fileURLWithPath: linkedApps[index].manifestPath)
        do {
            try load(from: url)
            locale = manifest.listing?.defaultLocale
                ?? manifest.listing?.locales.keys.sorted().first
                ?? "en-US"
            packages = [:]
            packageErrors = [:]
            buildRead = false
            loadCredentials()
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent). \(error.localizedDescription)"
        }
    }

    private func loadCredentials() {
        do {
            let apple = try KeychainCredentials.load(
                AppleCredential.self, kind: .apple, account: credentialAccount)
            appleKeyID = apple?.keyID ?? ""
            appleIssuerID = apple?.issuerID ?? ""
            applePrivateKeyPEM = apple?.privateKeyPEM ?? ""
            appleCredentialFileName = apple?.fileName ?? ""

            let google = try KeychainCredentials.load(
                GoogleServiceAccount.self, kind: .google, account: credentialAccount)
            googleCredential = google
            googleCredentialFileName = google?.fileName ?? ""
            googleAccountEmail = google?.clientEmail ?? ""
            appleConnection = .notTested
            googleConnection = .notTested
            remoteAppleApps = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistAppleCredential() throws {
        let credential = AppleCredential(
            keyID: appleKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
            issuerID: appleIssuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: applePrivateKeyPEM,
            fileName: appleCredentialFileName)
        try KeychainCredentials.save(credential, kind: .apple, account: credentialAccount)
    }

    private func syncStoreFieldsFromManifest() {
        appleAppID = manifest.apps.apple?.appId ?? ""
        appleBundleID = manifest.apps.apple?.bundleId ?? ""
        googlePackageName = manifest.apps.google?.packageName ?? ""
    }

    private func saveManifestReportingErrors() {
        do { try save() }
        catch { errorMessage = "The manifest could not be saved. \(error.localizedDescription)" }
    }

    private func persistLinkedApps() {
        do {
            let data = try JSONEncoder().encode(linkedApps)
            UserDefaults.standard.set(data, forKey: linkedAppsDefaultsKey)
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

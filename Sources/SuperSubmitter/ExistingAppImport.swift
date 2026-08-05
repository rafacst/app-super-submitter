import Foundation
import Observation
import SubmitKit

struct ExistingAppCandidate: Identifiable, Hashable, Sendable {
    let store: Store
    let remoteID: String
    let name: String
    let identifier: String

    var id: String { "\(store.rawValue):\(remoteID)" }
}

struct ExistingAppSelection: Sendable {
    private(set) var ids: Set<String> = []

    var count: Int { ids.count }
    func contains(_ candidate: ExistingAppCandidate) -> Bool { ids.contains(candidate.id) }
    mutating func toggle(_ candidate: ExistingAppCandidate) {
        if !ids.insert(candidate.id).inserted { ids.remove(candidate.id) }
    }
    mutating func selectAll(_ candidates: [ExistingAppCandidate]) {
        ids.formUnion(candidates.map(\.id))
    }
    mutating func clear() { ids.removeAll() }
}

enum ExistingAppImportPlan {
    struct Group: Identifiable, Sendable {
        let identifier: String
        let folderName: String
        let candidates: [ExistingAppCandidate]
        var id: String { identifier }
    }

    static func group(_ candidates: [ExistingAppCandidate]) -> [Group] {
        let unique = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(grouping: unique.values, by: \.identifier)
            .map { identifier, values in
                let preferredName = values.first(where: { $0.store == .apple })?.name
                    ?? values.first?.name ?? identifier
                return Group(identifier: identifier,
                             folderName: safeFolderName(preferredName, fallback: identifier),
                             candidates: values.sorted { $0.store.rawValue < $1.store.rawValue })
            }
            .sorted { $0.folderName.localizedCaseInsensitiveCompare($1.folderName) == .orderedAscending }
    }

    private static func safeFolderName(_ name: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }
}

@Observable
@MainActor
final class ExistingAppImportModel {
    enum Step: Int { case credentials, apps, destination, complete }

    var step: Step = .credentials
    /// Empty, so the developer says where the app lives. Both stores
    /// preselected asked for two sets of credentials before anyone chose
    /// anything. `canDiscover` already refuses an empty set, so Continue
    /// stays shut until one is picked.
    var stores: Set<Store> = []
    var appleKeyID = ""
    var appleIssuerID = ""
    var applePrivateKey = ""
    var appleFileName = ""
    var googleCredential: GoogleServiceAccount?
    var googleFileName = ""
    var googlePackages = ""
    var candidates: [ExistingAppCandidate] = []
    /// The app icon of a candidate, keyed by its id. A candidate with no icon
    /// shows its store mark, so a missing icon costs nothing.
    var icons: [String: URL] = [:]
    /// Why the grid shows store marks instead of icons, when it does.
    var iconNote: String?
    var selection = ExistingAppSelection()
    var loading = false
    var error: String?
    var imported: [URL] = []

    var selectedCandidates: [ExistingAppCandidate] {
        candidates.filter(selection.contains)
    }

    /// The App Store first, then Google Play. The grid draws one block per
    /// store, in this order.
    func candidates(for store: Store) -> [ExistingAppCandidate] {
        candidates.filter { $0.store == store }
    }

    /// One selected app takes the folder the user picks. Several apps each
    /// take a folder inside it.
    var selectedGroupCount: Int {
        ExistingAppImportPlan.group(selectedCandidates).count
    }

    var selectedGroupName: String? {
        let groups = ExistingAppImportPlan.group(selectedCandidates)
        return groups.count == 1 ? groups[0].folderName : nil
    }

    var canDiscover: Bool {
        let appleReady = !stores.contains(.apple)
            || (!appleKeyID.isEmpty && !appleIssuerID.isEmpty && !applePrivateKey.isEmpty)
        return !stores.isEmpty && appleReady && (!stores.contains(.google) || googleCredential != nil)
    }

    var appleCredential: AppleCredential? {
        guard stores.contains(.apple), canDiscover else { return nil }
        return AppleCredential(keyID: appleKeyID, issuerID: appleIssuerID,
                               privateKeyPEM: applePrivateKey, fileName: appleFileName)
    }

    func toggleStore(_ store: Store) {
        if !stores.insert(store).inserted { stores.remove(store) }
    }

    func importAppleKey(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        applePrivateKey = try String(contentsOf: url, encoding: .utf8)
        appleFileName = url.lastPathComponent
        // Apple names the file after the key. One the user already typed wins.
        if appleKeyID.trimmingCharacters(in: .whitespaces).isEmpty,
           let keyID = AppleCredential.keyID(fromFileName: url.lastPathComponent) {
            appleKeyID = keyID
        }
    }

    func importGoogleKey(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        googleCredential = try GoogleServiceAccount(
            data: Data(contentsOf: url), fileName: url.lastPathComponent)
        googleFileName = url.lastPathComponent
    }

    func discover() async {
        guard canDiscover else { return }
        loading = true
        error = nil
        defer { loading = false }
        let client = StoreConnectionClient()
        var found: [ExistingAppCandidate] = []
        var failures: [String] = []
        if let credential = appleCredential {
            do {
                found += try await client.appleApps(credential: credential).map {
                    ExistingAppCandidate(store: .apple, remoteID: $0.id,
                                         name: $0.name, identifier: $0.identifier)
                }
            } catch { failures.append("App Store: \(error.localizedDescription)") }
        }
        if stores.contains(.google), let credential = googleCredential {
            do {
                found += try await client.googleApps(credential: credential).map {
                    ExistingAppCandidate(store: .google, remoteID: $0.id,
                                         name: $0.name, identifier: $0.identifier)
                }
            } catch {
                failures.append("Google app listing is unavailable. Enable the Play Developer Reporting API or enter package names below. \(error.localizedDescription)")
            }
        }
        candidates = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selection.clear()
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        step = .apps

        // The icons are decoration, so they arrive after the list and they
        // never block it. A silent failure looked exactly like an account with
        // no icons, so the reason reaches the panel now.
        if let credential = appleCredential {
            let ids = found.filter { $0.store == .apple }.map(\.remoteID)
            if let icons = try? await client.appleIcons(appIDs: ids, credential: credential) {
                for (appID, url) in icons.urls {
                    self.icons["\(Store.apple.rawValue):\(appID)"] = url
                }
                iconNote = icons.urls.isEmpty ? icons.explanation : nil
            } else {
                iconNote = "The app icons could not be read. The apps below are still correct."
            }
        }
    }

    func addGooglePackages() {
        let packages = googlePackages
            .split { $0 == "," || $0 == ";" || $0.isNewline || $0.isWhitespace }
            .map(String.init).filter { !$0.isEmpty }
        let additions = packages.map {
            ExistingAppCandidate(store: .google, remoteID: $0, name: $0, identifier: $0)
        }
        let all = candidates + additions
        candidates = Array(Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for item in additions { if !selection.contains(item) { selection.toggle(item) } }
    }
}

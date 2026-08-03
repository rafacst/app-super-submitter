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
    var stores: Set<Store> = [.apple, .google]
    var appleKeyID = ""
    var appleIssuerID = ""
    var applePrivateKey = ""
    var appleFileName = ""
    var googleCredential: GoogleServiceAccount?
    var googleFileName = ""
    var googlePackages = ""
    var candidates: [ExistingAppCandidate] = []
    var selection = ExistingAppSelection()
    var loading = false
    var error: String?
    var imported: [URL] = []

    var selectedCandidates: [ExistingAppCandidate] {
        candidates.filter(selection.contains)
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

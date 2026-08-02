import Foundation
import SubmitKit

@MainActor
extension AppState {
    func importExistingApps(_ candidates: [ExistingAppCandidate], destination: URL,
                            appleCredential: AppleCredential?,
                            googleCredential: GoogleServiceAccount?) async throws -> [URL] {
        let groups = ExistingAppImportPlan.group(candidates)
        guard !groups.isEmpty else { return [] }
        let client = StoreConnectionClient()
        var importedURLs: [URL] = []

        for group in groups {
            let folder = availableImportFolder(named: group.folderName, under: destination,
                                               identifier: group.identifier)
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
            let manifestURL = folder.appendingPathComponent(ManifestFile.defaultName)
            var importedManifest = (try? ManifestFile.load(from: manifestURL)) ?? Manifest()

            for candidate in group.candidates {
                switch candidate.store {
                case .apple:
                    guard let appleCredential else { continue }
                    importedManifest.setAppleApp(appID: candidate.remoteID,
                                                 bundleID: candidate.identifier)
                    let listing = try await client.importApple(
                        appID: candidate.remoteID, credential: appleCredential)
                    importedManifest.mergeAppleImport(listing)
                case .google:
                    guard let googleCredential else { continue }
                    _ = try await client.testGoogle(credential: googleCredential,
                                                    packageName: candidate.identifier)
                    importedManifest.setGoogleApp(packageName: candidate.identifier)
                    let listing = try await client.importGoogle(
                        credential: googleCredential, packageName: candidate.identifier)
                    importedManifest.mergeGoogleImport(listing)
                }
            }

            try ManifestFile.save(importedManifest, to: manifestURL)
            link(manifestAt: manifestURL)
            if let account = credentialAccount {
                if group.candidates.contains(where: { $0.store == .apple }), let appleCredential {
                    try KeychainCredentials.save(appleCredential, kind: .apple, account: account)
                }
                if group.candidates.contains(where: { $0.store == .google }), let googleCredential {
                    try KeychainCredentials.save(googleCredential, kind: .google, account: account)
                }
            }
            importedURLs.append(manifestURL)
        }
        selectedTab = .build
        return importedURLs
    }

    private func availableImportFolder(named name: String, under root: URL,
                                       identifier: String) -> URL {
        let proposed = root.appendingPathComponent(name, isDirectory: true)
        let manifest = proposed.appendingPathComponent(ManifestFile.defaultName)
        if !FileManager.default.fileExists(atPath: proposed.path)
            || FileManager.default.fileExists(atPath: manifest.path) { return proposed }
        let suffix = identifier.split(separator: ".").last.map(String.init) ?? "app"
        return root.appendingPathComponent("\(name) - \(suffix)", isDirectory: true)
    }
}

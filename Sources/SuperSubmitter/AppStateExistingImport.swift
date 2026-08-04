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
        var skipped: [String] = []

        for group in groups {
            // Super Submitter keeps `store.yaml` beside the app, so one app
            // takes the folder the user picked. Several apps cannot share one
            // folder, so each takes its own inside it.
            let folder = groups.count == 1
                ? destination
                : availableImportFolder(named: group.folderName, under: destination,
                                        identifier: group.identifier)
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
            let manifestURL = folder.appendingPathComponent(ManifestFile.defaultName)
            var importedManifest = (try? ManifestFile.load(from: manifestURL)) ?? Manifest()
            // What each store holds today. The editing tabs show it beside the
            // value the developer is about to write, before any store read.
            var snapshot = StoreSnapshot()

            for candidate in group.candidates {
                switch candidate.store {
                case .apple:
                    guard let appleCredential else { continue }
                    importedManifest.setAppleApp(appID: candidate.remoteID,
                                                 bundleID: candidate.identifier)
                    let listing = try await client.importApple(
                        appID: candidate.remoteID, credential: appleCredential)
                    importedManifest.setAppleApp(
                        appID: candidate.remoteID,
                        bundleID: listing.bundleID ?? candidate.identifier)
                    importedManifest.mergeAppleImport(listing)
                    snapshot.merge(listing, store: .apple)
                    skipped += listing.failures
                    try await materializeImportedAssets(
                        listing.assets, store: .apple, root: folder,
                        manifest: &importedManifest)
                case .google:
                    guard let googleCredential else { continue }
                    _ = try await client.testGoogle(credential: googleCredential,
                                                    packageName: candidate.identifier)
                    importedManifest.setGoogleApp(packageName: candidate.identifier)
                    let listing = try await client.importGoogle(
                        credential: googleCredential, packageName: candidate.identifier)
                    importedManifest.mergeGoogleImport(listing)
                    snapshot.merge(listing, store: .google)
                    skipped += listing.failures
                    try await materializeImportedAssets(
                        listing.assets, store: .google, root: folder,
                        manifest: &importedManifest)
                }
            }

            try ManifestFile.save(importedManifest, to: manifestURL)
            // `link` activates the app, which clears the read state, so the
            // snapshot of the app that stays open is set after it.
            link(manifestAt: manifestURL)
            storeSnapshot = snapshot
            if let appleCredential {
                try KeychainCredentials.save(appleCredential, kind: .apple,
                                             account: storeAccount)
            }
            if let googleCredential {
                try KeychainCredentials.save(googleCredential, kind: .google,
                                             account: storeAccount)
            }
            // `link` read the Keychain before these lines wrote it, so tab 1
            // held empty fields and asked for the .p8 and the JSON a second
            // time. Read it again now it is there.
            loadCredentials()
            importedURLs.append(manifestURL)
        }
        // A publisher lands on the build they are about to send. A manager has
        // nothing to build, so they land on the reviews of the live app.
        selectedTab = mode == .managing ? .reviews : .build
        if !skipped.isEmpty {
            errorMessage = "The apps were imported. These parts stayed empty:\n"
                + skipped.map { "· \($0)" }.joined(separator: "\n")
        }
        return importedURLs
    }

    /// The managing import. It asks the user for no folder.
    ///
    /// A publishing import writes `store.yaml` beside the source, because the
    /// developer keeps it in their repository. A manager has no repository in
    /// play: the app is built and it is out there. Super Submitter keeps the
    /// workspace in its own Application Support directory instead, one folder
    /// per app, and the rest of the import is the same.
    func importManagedApps(_ candidates: [ExistingAppCandidate],
                           appleCredential: AppleCredential?,
                           googleCredential: GoogleServiceAccount?) async throws -> [URL] {
        let groups = ExistingAppImportPlan.group(candidates)
        guard !groups.isEmpty else { return [] }
        let storage = BuildStorage()
        var imported: [URL] = []

        // One app at a time, so one folder is one app and the shared import
        // never has to split a parent folder.
        for group in groups {
            let folder = try storage.managedFolder(name: group.folderName,
                                                   identifier: group.identifier)
            imported += try await importExistingApps(
                group.candidates, destination: folder,
                appleCredential: appleCredential, googleCredential: googleCredential)
        }
        return imported
    }

    private func availableImportFolder(named name: String, under root: URL,
                                       identifier: String) -> URL {
        let proposed = root.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: proposed.path) else { return proposed }
        let manifest = proposed.appendingPathComponent(ManifestFile.defaultName)
        if let existing = try? ManifestFile.load(from: manifest),
           existing.apps.apple?.bundleId == identifier
            || existing.apps.google?.packageName == identifier { return proposed }
        let suffix = identifier.split(separator: ".").last.map(String.init) ?? "app"
        var index = 1
        while true {
            let counter = index == 1 ? "" : " \(index)"
            let candidate = root.appendingPathComponent(
                "\(name) - \(suffix)\(counter)", isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func materializeImportedAssets(_ assets: [ImportedStoreAsset], store: Store,
                                           root: URL, manifest: inout Manifest) async throws {
        for asset in assets {
            let safeName = asset.fileName
                .components(separatedBy: CharacterSet(charactersIn: "/:"))
                .joined(separator: "-")
            let relative = "Store Import/\(store.rawValue)/\(asset.locale)/\(asset.kind)/\(safeName)"
            let destination = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) {
                let (data, response) = try await URLSession.shared.data(from: asset.url)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw ConnectionError.http(http.statusCode,
                        "Could not download \(asset.fileName) from \(store.storeName).")
                }
                try data.write(to: destination, options: .atomic)
            }
            if let deviceClass = asset.deviceClass {
                manifest.addMediaPaths([relative], locale: asset.locale,
                                       deviceClass: deviceClass)
            } else if asset.kind == "icon" {
                var media = manifest.media ?? Manifest.Media()
                media.icon = relative
                manifest.media = media
            } else if asset.kind == "featureGraphic" {
                var media = manifest.media ?? Manifest.Media()
                media.featureGraphic = relative
                manifest.media = media
            }
        }
    }
}

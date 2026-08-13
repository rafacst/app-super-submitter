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
        // The stores this import actually called, so the Stores tab can stop
        // asking for a connection it has already watched succeed. Collected
        // rather than read off the two credentials: the sheet seeds itself from
        // the Keychain, so it can hold an Apple key on an import of Google apps
        // alone, and a key nothing called proves nothing.
        var reached: Set<Store> = []

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
            importedManifest.removeImportedMedia()
            // What each store holds today. The editing tabs show it beside the
            // value the developer is about to write, before any store read.
            var snapshot = StoreSnapshot()

            for candidate in group.candidates {
                switch candidate.store {
                case .apple:
                    guard let appleCredential else { continue }
                    // The platforms the picker read off the store, not the
                    // `[.ios]` default. Every Mac app imported so far was
                    // written into `store.yaml` as an iPhone app.
                    let platforms = candidate.platforms.isEmpty
                        ? [Manifest.Platform.ios] : candidate.platforms
                    importedManifest.setAppleApp(appID: candidate.remoteID,
                                                 bundleID: candidate.identifier,
                                                 platforms: platforms)
                    // One platform's listing, not a mix of two. See
                    // `StoreImportReader.apple(appID:platform:)`.
                    let listing = try await client.importApple(
                        appID: candidate.remoteID, credential: appleCredential,
                        platform: platforms.first?.rawValue)
                    importedManifest.setAppleApp(
                        appID: candidate.remoteID,
                        bundleID: listing.bundleID ?? candidate.identifier,
                        platforms: platforms)
                    importedManifest.mergeAppleImport(listing)
                    skipped += listing.failures
                    // The files first, then the snapshot that names them. See
                    // `adopt`: a snapshot pointing at the store's own URLs made
                    // the Media tab download every picture a second time.
                    let landed = await materializeImportedAssets(
                        listing.assets, store: .apple, root: folder)
                    skipped += landed.failures
                    snapshot.rememberLocalCopies(
                        zip(listing.assets, landed.local).map { ($0.url, $1.url) })
                    snapshot.merge(listing, store: .apple)
                    reached.insert(.apple)
                case .google:
                    guard let googleCredential else { continue }
                    _ = try await client.testGoogle(credential: googleCredential,
                                                    packageName: candidate.identifier)
                    importedManifest.setGoogleApp(packageName: candidate.identifier)
                    let listing = try await client.importGoogle(
                        credential: googleCredential, packageName: candidate.identifier)
                    importedManifest.mergeGoogleImport(listing)
                    skipped += listing.failures
                    let landed = await materializeImportedAssets(
                        listing.assets, store: .google, root: folder)
                    skipped += landed.failures
                    snapshot.rememberLocalCopies(
                        zip(listing.assets, landed.local).map { ($0.url, $1.url) })
                    snapshot.merge(listing, store: .google)
                    reached.insert(.google)
                }
            }

            try ManifestFile.save(importedManifest, to: manifestURL)
            // Every app keeps its own picture of its own stores. Only one app
            // is open at the end, so an import of five that held the picture
            // in memory alone left four of them grey-less.
            snapshot.save(toRoot: folder)
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
        // The import is the connection. It signed a token with this key, listed
        // the apps, and read a whole listing back, which is strictly more than
        // the Connect button on the Stores tab ever does.
        //
        // Without these lines that tab said "Not connected" under a Connect
        // button, so a developer who had just imported an app through the key
        // was asked to prove the same key a second time, by hand, on the next
        // screen they opened. `loadCredentials` above is what cleared it: the
        // fields went from empty to the imported key, and a key that changes is
        // exactly what invalidates a connection everywhere else in the app.
        //
        // After the loop, so the last `loadCredentials` of the run cannot
        // undo it.
        for store in reached {
            switch store {
            case .apple:
                appleConnection = .connected("Connected · the import used this key")
            case .google:
                googleConnection = .connected("Connected · the import used this service account")
            }
        }
        // A publisher lands on the build they are about to send. A manager has
        // nothing to build, so they land on the reviews of the live app.
        selectedTab = mode == .managing ? .liveApp : .build
        // Which of the apps just imported the App Store has shipped. The Manage
        // side lists those and no others, and an import is the usual way a live
        // app arrives: without this the developer imported five published apps
        // and the Manage column listed none of them until the next launch.
        await refreshReviewStates()
        // And which of them Google Play has, which the sweep above cannot ask.
        // `link` asks this as each app is added, and an import is the one door
        // where that is too early: the keys the read has to sign with are put
        // in the Keychain by the lines after it. Nothing already answered for
        // is asked again.
        for record in linkedApps
        where importedURLs.contains(where: { $0.path == record.manifestPath }) {
            await readAppLiveness(for: record)
        }
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

    /// Keeps downloaded store media as a local view of what is live.
    ///
    /// The download runs first and the snapshot takes the files it wrote, so the
    /// Media tab shows what the store holds from disk. The merge used to run
    /// first, against the store's own URLs, and the pictures this folder already
    /// held were never looked at again.
    func adopt(_ imported: ImportedStoreListing, store: Store) async {
        guard let root = manifestURL?.deletingLastPathComponent() else { return }
        manifest.removeImportedMedia()
        let (failures, local) = await materializeImportedAssets(
            imported.assets, store: store, root: root)
        storeSnapshot.rememberLocalCopies(
            zip(imported.assets, local).map { ($0.url, $1.url) })
        storeSnapshot.merge(imported, store: store)
        let skipped = imported.failures + failures
        guard !skipped.isEmpty else { return }
        errorMessage = "The listing was read. These parts stayed empty:\n"
            + skipped.map { "· \($0)" }.joined(separator: "\n")
    }

    /// Downloads what the store shows without making it desired upload input.
    ///
    /// One file that will not download costs that one file. It used to cost
    /// the whole app: a single failed image threw out of the loop before the
    /// save, so every description the import had already read was thrown away
    /// with it and the folder was left without a `store.yaml`. The names of
    /// the files that stayed behind are returned instead, and they reach the
    /// developer in the same list as the reads the store refused.
    /// It answers the same assets pointing at the copies on disk, because a
    /// file that landed here and is then shown from the store's own URL is a
    /// download nobody used. The Media tab drew every live picture straight off
    /// Apple's servers while the bytes sat in this folder, so the strip filled
    /// in slowly, one blank tile at a time, and a press on a tile downloaded the
    /// whole image again before Quick Look could open it.
    ///
    /// A file that will not download keeps the store's URL, so it is still on
    /// the screen and still slow, rather than gone.
    func materializeImportedAssets(_ assets: [ImportedStoreAsset], store: Store,
                                   root: URL) async -> (failures: [String],
                                                        local: [ImportedStoreAsset]) {
        var failures: [String] = []
        var local: [ImportedStoreAsset] = []
        for asset in assets {
            guard let destination = Self.importDestination(asset, store: store, root: root)
            else {
                failures.append("\(store.storeName) \(asset.kind): the store named a path outside the import folder.")
                local.append(asset)
                continue
            }
            do {
                try await download(asset, to: destination, root: root)
                local.append(ImportedStoreAsset(
                    locale: asset.locale, kind: asset.kind, url: destination,
                    fileName: asset.fileName))
            } catch {
                failures.append("\(store.storeName) \(asset.kind) \(asset.fileName): "
                    + error.localizedDescription)
                local.append(asset)
                continue
            }
        }
        return (failures, local)
    }

    /// Downloads what a store read says is live, so the Media tab draws it from
    /// disk rather than from the store on every appearance.
    ///
    /// It covers the version's own page and every custom product page and test
    /// treatment beside it. An app the developer never imported reached the
    /// Media tab with nothing on disk at all, and the product pages are read
    /// after any import, so neither had a copy without this.
    func cacheLiveMedia(_ actual: ActualState) async {
        guard let root = manifestURL?.deletingLastPathComponent(),
              let apple = actual.apple else { return }
        // The page name goes in the file name, because the folder is keyed by
        // locale and screen size and every page answers for the same two. Two
        // pages whose first 6.5 inch picture is called `shot.png` would land on
        // one path, and the download skips a file that is already there, so one
        // page would have shown the other page's pictures.
        let pageAssets = apple.productPages.flatMap { page in
            page.assets.map {
                ImportedStoreAsset(locale: $0.locale, kind: $0.kind, url: $0.url,
                                   fileName: "\(Self.safeComponent(page.name))-\($0.fileName)")
            }
        }
        let assets = apple.liveAssets + pageAssets
        guard !assets.isEmpty else { return }
        let landed = await materializeImportedAssets(assets, store: .apple, root: root)
        storeSnapshot.rememberLocalCopies(
            zip(assets, landed.local).map { ($0.url, $1.url) })
    }

    /// Where one store asset belongs under `Store Import/`, or nil when the
    /// name the store sent would put it somewhere else entirely.
    static func importDestination(_ asset: ImportedStoreAsset, store: Store,
                                  root: URL) -> URL? {
        let folder = root.appendingPathComponent(importFolder).standardizedFileURL
        let destination = [store.rawValue, safeComponent(asset.locale),
                           safeComponent(asset.kind), safeComponent(asset.fileName)]
            .reduce(folder) { $0.appendingPathComponent($1) }.standardizedFileURL
        return isSafeImportDestination(destination, root: root) ? destination : nil
    }

    private func download(_ asset: ImportedStoreAsset, to destination: URL,
                          root: URL) async throws {
        guard asset.url.scheme?.lowercased() == "https" else {
            throw ConnectionError.invalidResponse
        }
        guard Self.isSafeImportDestination(destination, root: root) else {
            throw ConnectionError.invalidResponse
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard Self.isSafeImportDestination(destination, root: root) else {
            throw ConnectionError.invalidResponse
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let (data, response) = try await URLSession.shared.data(from: asset.url)
        guard let http = response as? HTTPURLResponse,
              response.url?.scheme?.lowercased() == "https" else {
            throw ConnectionError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            throw ConnectionError.http(http.statusCode, "The store refused the file.")
        }
        guard Self.isSafeImportDestination(destination, root: root) else {
            throw ConnectionError.invalidResponse
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func isSafeImportDestination(_ destination: URL, root: URL) -> Bool {
        let root = root.standardizedFileURL
        let folder = root.appendingPathComponent(importFolder).standardizedFileURL
        let destination = destination.standardizedFileURL
        guard destination.path.hasPrefix(folder.path + "/") else { return false }

        var current = root
        for component in destination.pathComponents.dropFirst(root.pathComponents.count) {
            current.appendPathComponent(component)
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                return false
            }
        }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolved = destination.resolvingSymlinksInPath().standardizedFileURL
        return resolved.path.hasPrefix(
            resolvedRoot.appendingPathComponent(importFolder).path + "/")
    }

    static func safeComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_."))
        let cleaned = raw.components(separatedBy: allowed.inverted).joined(separator: "-")
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "unnamed" : cleaned
    }

    /// Where the import puts what it downloads, relative to `store.yaml`.
    /// The Media tab reads it to tell a file that came from the store from a
    /// file the developer chose.
    static let importFolder = "Store Import"

    static func isImported(_ path: String) -> Bool {
        path.hasPrefix("\(importFolder)/")
    }
}

extension Manifest {
    /// Old imports put observed store assets in the desired manifest. Drop
    /// those paths while keeping user-selected media untouched.
    @MainActor mutating func removeImportedMedia() {
        guard var media else { return }
        func cleaned(_ locales: [String: [String: [String]]]?)
            -> [String: [String: [String]]]? {
            locales?.mapValues { groups in
                groups.mapValues { $0.filter { !AppState.isImported($0) } }
            }
        }
        media.screenshots = cleaned(media.screenshots)
        media.appleScreenshots = cleaned(media.appleScreenshots)
        media.googleScreenshots = cleaned(media.googleScreenshots)
        media.previews = cleaned(media.previews)
        if media.icon.map(AppState.isImported) == true { media.icon = nil }
        if media.featureGraphic.map(AppState.isImported) == true { media.featureGraphic = nil }
        self.media = media
    }
}

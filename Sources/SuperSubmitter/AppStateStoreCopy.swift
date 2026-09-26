import Foundation
import SubmitKit

/// The copy between the two stores, and the Google Play side of a catalog
/// that came from the App Store.
///
/// An app that ships on one store first gets its second store later, and that
/// store starts empty. `Manifest.copyStore` decides what the second store can
/// take; this hands it what the app knows about the first one, which lives
/// beside `store.yaml` and not in it.
@MainActor
extension AppState {

    /// Whether there are two stores to copy between.
    var canCopyBetweenStores: Bool {
        manifestURL != nil && Store.allCases.allSatisfy(stores.contains)
    }

    /// Gives the other store what `source` already has, and answers what the
    /// copy did.
    ///
    /// One undo step, whatever it wrote. The App Store's own products and
    /// prices are read into the blanks first, the read the Monetization tab
    /// makes when it opens, so a copy made before anyone opened that tab still
    /// carries them.
    func copyStore(from source: Store) async -> StoreCopyReport? {
        let target: Store = source == .apple ? .google : .apple
        guard canCopyBetweenStores else { return nil }
        // A word still in a listing box is the developer's newest answer, and
        // the copy reads the file.
        flushSave()
        let app = manifestURL
        if source == .apple { await loadStoreMonetization() }
        // The developer can open another app while Apple answers. The copy
        // belongs to the app it was asked for.
        guard manifestURL == app else { return nil }

        // A copy of the manifest and not the manifest itself: the picture
        // sizes are read from disk through `self` while the edit runs.
        var edited = manifest
        var report = edited.copyStore(from: source, to: target,
                                      live: storeCopySource(for: source),
                                      imageSize: { self.imageInfo(for: $0) })
        report.skipped += keepCopiedMedia(&edited, target: target)
        guard edited != manifest else { return report }
        manifest = edited
        // Its own step, never folded into the keystroke before it.
        lastUndoRegistration = nil
        saveManifestReportingErrors()
        return report
    }

    /// Where the copy keeps the pictures it takes from `Store Import/`,
    /// relative to `store.yaml`.
    static let copyFolder = "Store Copy"

    /// The copy's pictures, moved out of `Store Import/`.
    ///
    /// That folder holds what a store showed when it was read, and `load`
    /// drops every path under it from `store.yaml`, because a picture of the
    /// store is not an upload. A picture the copy gives the other store is an
    /// upload, so it takes a file of its own under `Store Copy/`, in the same
    /// layout, and keeps its place in `store.yaml` across a relaunch. Only the
    /// pictures the copy chose are copied, never the whole folder.
    ///
    /// Answers one line per file that could not be copied.
    private func keepCopiedMedia(_ edited: inout Manifest, target: Store) -> [String] {
        guard let root = manifestRoot else { return [] }
        var failures: [String] = []
        func kept(_ path: String) -> String {
            guard AppState.isImported(path) else { return path }
            let relative = "\(AppState.copyFolder)/"
                + path.dropFirst(AppState.importFolder.count + 1)
            let from = root.appendingPathComponent(path)
            let to = root.appendingPathComponent(relative)
            do {
                if !FileManager.default.fileExists(atPath: to.path) {
                    try FileManager.default.createDirectory(
                        at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: from, to: to)
                }
                return relative
            } catch {
                failures.append("\(from.lastPathComponent) could not be copied beside store.yaml, so it stays out of the copy. \(error.localizedDescription)")
                return path
            }
        }
        for (locale, groups) in edited.storeScreenshots(target) ?? [:] {
            for (key, paths) in groups {
                guard let deviceClass = Manifest.DeviceClass(rawValue: key) else { continue }
                let moved = paths.map(kept).filter { !Self.isImported($0) }
                guard moved != paths else { continue }
                guard moved.isEmpty else {
                    edited.setStoreScreenshots(moved, locale: locale, deviceClass: deviceClass,
                                               store: target)
                    continue
                }
                // Nothing landed. An empty list here would say "send this
                // store nothing for this size", which nobody chose.
                switch target {
                case .apple: edited.media?.appleScreenshots?[locale]?[key] = nil
                case .google: edited.media?.googleScreenshots?[locale]?[key] = nil
                }
            }
        }
        if target == .google, let icon = edited.media?.icon, Self.isImported(icon) {
            let moved = kept(icon)
            edited.media?.icon = Self.isImported(moved) ? nil : moved
        }
        return failures
    }

    /// What `source` shows today, from the snapshot the import and every store
    /// read keep beside `store.yaml`, and the Google Play products the last
    /// read found.
    func storeCopySource(for source: Store) -> StoreCopySource {
        let snapshot = storeSnapshot
        var copy = StoreCopySource()
        switch source {
        case .apple:
            // The live version under the draft. The draft is what the next
            // version carries, and an app between versions has none.
            for (locale, fields) in snapshot.appleLive {
                copy.text[locale, default: [:]].merge(fields) { _, new in new }
            }
            for (locale, fields) in snapshot.text[.apple] ?? [:] {
                copy.text[locale, default: [:]].merge(fields) { _, new in new }
            }
            if let icon = snapshot.appleIcon.map({ snapshot.resolve($0) }), icon.isFileURL,
               FileManager.default.fileExists(atPath: icon.path) {
                copy.icon = relativePath(for: icon)
            }
        case .google:
            for (locale, fields) in snapshot.text[.google] ?? [:] {
                copy.text[locale, default: [:]].merge(fields) { _, new in new }
            }
            // Play keeps one contact website for the app, and the file keeps
            // the support URL per language. The default language is the one
            // the send reads it from.
            if let website = actualState.google?.contactWebsite, !website.isEmpty,
               let locale = manifest.listing?.defaultLocale {
                copy.text[locale, default: [:]][.supportURL] = website
            }
        }
        // The pictures on disk and nothing else. A store URL is not a file the
        // other store can be sent, and a video is not a screenshot.
        for (locale, devices) in snapshot.screenshots[source] ?? [:] {
            for (deviceClass, urls) in devices {
                let files = urls.map { snapshot.resolve($0) }.filter {
                    $0.isFileURL && !StoreSnapshot.isVideo($0)
                        && FileManager.default.fileExists(atPath: $0.path)
                }
                guard !files.isEmpty else { continue }
                copy.screenshots[locale, default: [:]][deviceClass] =
                    files.map { relativePath(for: $0) }
            }
        }
        if let google = actualState.google {
            copy.googleProducts = googlePlayProductIds(google)
            copy.googleBasePlans = google.catalog.compactMapValues(\.basePlanId)
        }
        return copy
    }

    // MARK: - The Google Play side of the catalog

    /// Every product id Google Play holds, one-time and subscription alike.
    private func googlePlayProductIds(_ google: ActualState.Google) -> Set<String> {
        google.oneTimeProductIds.union(google.subscriptionIds)
    }

    /// What Google Play still lacks before the next send can create the
    /// catalog there. Nil while Google Play is not chosen, or has not been
    /// read: before a read the app cannot tell a product Google holds from one
    /// it does not.
    var googlePlayCatalogGaps: Manifest.GooglePlayCatalogGaps? {
        guard stores.contains(.google), let google = actualState.google else { return nil }
        return manifest.googlePlayCatalogGaps(onGooglePlay: googlePlayProductIds(google))
    }

    /// Whether the catalog is waiting for a Google Play read before the tab
    /// can say what Google still needs.
    var googlePlayCatalogUnread: Bool {
        stores.contains(.google) && actualState.google == nil
            && !((manifest.purchases ?? []).isEmpty && (manifest.subscriptions ?? []).isEmpty)
    }

    /// Gives every product Google Play does not hold its base plan and its
    /// sale switch. See `Manifest.prepareGooglePlayCatalog`.
    @discardableResult
    func setUpGooglePlayCatalog() -> [String] {
        guard let google = actualState.google else { return [] }
        let ready = manifest.prepareGooglePlayCatalog(
            onGooglePlay: googlePlayProductIds(google),
            basePlans: google.catalog.compactMapValues(\.basePlanId))
        guard !ready.isEmpty else { return [] }
        lastUndoRegistration = nil
        saveManifestReportingErrors()
        return ready
    }
}

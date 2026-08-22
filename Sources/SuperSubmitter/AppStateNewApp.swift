import Foundation
import SubmitKit

/// What one scan of a chosen folder could tell about the app in it.
///
/// Every field is optional, because every one of them is a value the project
/// may compute at build time rather than state. Nothing here is a guess: a
/// field the project does not state plainly stays nil and the developer fills
/// it, exactly as they did before this existed.
struct ScannedProject: Equatable {
    var store: Store?
    var platforms: [Manifest.Platform] = []
    var identifier: String?
    var version: String?
    var name: String?
    /// The language the listing is written in first, and every language the
    /// project ships. Without the first one the manifest carries no listing at
    /// all, and Details, Media and Preview store open on "Add the first
    /// locale" for an app whose project states the answer.
    var locales = ProjectLocales()
    /// Google's 512-square listing icon, when Android Studio has written one.
    /// Google Play refuses anything else, so the launcher icons beside it are
    /// never offered here. See `playStoreIcon`.
    var playIcon: URL?
    /// Apple's export compliance answer, where the project states it.
    ///
    /// Apple reads `ITSAppUsesNonExemptEncryption` out of the binary and
    /// changes it for nobody, so a project that carries the key has already
    /// answered and the app has no business asking again. Apple only: Google
    /// asks no such question.
    var usesNonExemptEncryption: Bool?

    var isEmpty: Bool {
        identifier == nil && version == nil && name == nil && locales.isEmpty
    }
}

@MainActor
extension AppState {

    /// The new-app door: a folder becomes a linked app, with whatever the
    /// project in it already says filled in.
    ///
    /// The old door asked for the folder first and wrote an empty manifest
    /// into it, so the developer met a credential form for an app the app knew
    /// nothing about, and then typed a bundle identifier that was sitting in
    /// their own project file the whole time. The keys come first now, and the
    /// folder answers for itself.
    func createApp(in folder: URL, stores: Set<Store>) async {
        let url = folder.appendingPathComponent(ManifestFile.defaultName)
        // A folder that already carries the file keeps every word of it. This
        // door writes an app that is not there yet; it does not reset one.
        var draft = (try? ManifestFile.load(from: url)) ?? Manifest()
        for store in Store.allCases {
            // Only ever adds. A store already in the file stays, so opening a
            // folder that holds an App Store app through the Google door
            // cannot drop the App Store half of it.
            if stores.contains(store) { draft.setStore(store, enabled: true) }
        }
        // No language is invented here. A project that states its development
        // region, or lists its languages, is read and answers for itself; a
        // project that states neither keeps no language at all, because a
        // default baked into the app is exactly the placeholder this codebase
        // refuses everywhere else. See `ProjectLocales`.
        let found = await Self.scanProject(at: folder)
        if let found { apply(found, to: &draft, stores: stores, root: folder) }
        do {
            try ManifestFile.save(draft, to: url)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // After the file is written, so the record takes the name the manifest
        // carries rather than the folder's own.
        link(manifestAt: url)
        // And the project's name where the manifest has no language to keep
        // one. `link` falls back to the folder name, which is a repository
        // name as often as it is an app name.
        if let name = found?.name, !name.isEmpty,
           linkedApps.indices.contains(selectedAppIndex),
           linkedApps[selectedAppIndex].manifestPath == url.path {
            linkedApps[selectedAppIndex].name = name
            persistLinkedApps()
        }
        if let found, found.isEmpty {
            errorMessage = "The project in this folder states no bundle identifier or version "
                + "that can be read without building it. Fill them in on the Details tab."
        }
    }

    /// Puts the keys the sheet collected into the Keychain, then asks the two
    /// stores about them.
    ///
    /// The import saves its own keys inside its loop, where the order matters.
    /// This is the door that imports nothing: a new app has no listing to read
    /// and no app id to read it with, so the keys are saved on their own and
    /// `verifyStoredConnections` makes the claim that they work — by calling,
    /// the same as the Stores tab, rather than by asserting it here.
    func adoptCredentials(apple: AppleCredential?, google: GoogleServiceAccount?) {
        do {
            if let apple {
                try KeychainCredentials.save(apple, kind: .apple, account: storeAccount)
            }
            if let google {
                try KeychainCredentials.save(google, kind: .google, account: storeAccount)
            }
        } catch {
            errorMessage = "The keys could not be saved to the Keychain. "
                + error.localizedDescription
        }
        loadCredentials()
        verifyStoredConnections()
    }

    /// Reads the project in a folder. It runs no build and no Gradle daemon.
    ///
    /// `ProjectDiscovery` already walks a folder for the Build tab, and both
    /// build services already read what a project states. The scan is those
    /// three, called at the moment the folder is chosen instead of minutes
    /// later, on the tab the developer has not reached yet.
    static func scanProject(at root: URL) async -> ScannedProject? {
        let result = await Task.detached { ProjectDiscovery.scan(root: root) }.value
        // The recommended container and no other. Two projects in one folder
        // is a question with an answer the developer owns, and the Build tab
        // asks it properly; filling a bundle identifier out of whichever one
        // sorted first would answer it behind their back.
        guard let container = ProjectDiscovery.recommended(result.containers) else { return nil }
        var found = ScannedProject()
        if container.kind == .gradle {
            // The root script rarely names the application. `app` is the module
            // the Android template creates and the one nearly every project
            // keeps.
            let root = AndroidBuildService.identity(root: container.url, module: nil)
            let usesAppModule = root.applicationID == nil
            let module = usesAppModule
                ? AndroidBuildService.identity(root: container.url, module: "app")
                : root
            let moduleURL = usesAppModule
                ? container.url.appendingPathComponent("app") : container.url
            found.store = .google
            found.identifier = module.applicationID
            found.version = module.versionName
            found.name = module.appName
            found.locales = ProjectLocales.android(module: moduleURL)
            found.playIcon = playStoreIcon(in: moduleURL)
        } else {
            let identity = AppleProjectIdentity.read(container: container.url)
            found.store = .apple
            found.platforms = container.platform == .macos ? [.macOS] : [.ios]
            found.identifier = identity.bundleIdentifier
            found.version = identity.marketingVersion
            found.name = identity.displayName
            found.usesNonExemptEncryption = identity.usesNonExemptEncryption
            found.locales = ProjectLocales.apple(container: container.url)
        }
        return found
    }

    /// The one Android icon Google Play accepts.
    ///
    /// Play takes a 512-square PNG and refuses the launcher icons: the largest
    /// of those is 192 points, so pointing the manifest at `res/mipmap-*` would
    /// write a path that fails on upload. Android Studio's own Image Asset tool
    /// writes `ic_launcher-playstore.png` beside `res` at exactly the size Play
    /// asks for, and that file and no other is what this offers.
    ///
    /// The App Store has no equivalent: Apple reads the icon out of the binary,
    /// and the manifest holds no field for one.
    static func playStoreIcon(in module: URL) -> URL? {
        let icon = module.appendingPathComponent("src/main/ic_launcher-playstore.png")
        return FileManager.default.fileExists(atPath: icon.path) ? icon : nil
    }

    /// Fills what the manifest does not already say, and overrules nothing.
    ///
    /// The Build tab's rule, kept: the manifest is a constraint on the project
    /// and never the other way round. A field the developer has already
    /// answered stays as they answered it, and the preflight still blocks a
    /// build whose identifier disagrees with the one in the file.
    ///
    /// A store the developer did not pick is not filled either. An Xcode
    /// project in a folder linked for Google Play alone says nothing about the
    /// Play listing.
    /// `root` is the folder the new `store.yaml` goes in, and it is passed
    /// rather than read. `manifestRoot` still names the app that was open
    /// before this door was opened, so a path resolved against it would be
    /// written relative to somebody else's project.
    func apply(_ found: ScannedProject, to draft: inout Manifest, stores: Set<Store>,
               root: URL? = nil) {
        guard let store = found.store, stores.contains(store) else { return }
        switch store {
        case .apple:
            let existing = draft.apps.apple
            let bundleID = existing?.bundleId.isEmpty == false
                ? existing?.bundleId ?? "" : (found.identifier ?? "")
            if !bundleID.isEmpty || existing != nil {
                draft.setAppleApp(
                    appID: existing?.appId ?? "", bundleID: bundleID,
                    platforms: existing?.platforms.isEmpty == false
                        ? existing?.platforms ?? [.ios]
                        : (found.platforms.isEmpty ? [.ios] : found.platforms))
            }
        case .google:
            let existing = draft.apps.google?.packageName ?? ""
            if existing.isEmpty, let identifier = found.identifier {
                draft.setGoogleApp(packageName: identifier)
            }
        }
        if let version = found.version, draft.versionName(for: store) == nil {
            draft.setReleaseVersionName(version, for: store)
        }
        // Apple's export compliance answer, where the project states it. It
        // runs before the Build tab opens, so `defaultEncryptionAnswer` finds
        // an answer already there and leaves it alone: the app guesses "uses
        // no non-exempt encryption" only for a project that stated nothing.
        if store == .apple, let answer = found.usesNonExemptEncryption,
           draft.review?.usesNonExemptEncryption == nil {
            var review = draft.review ?? Manifest.Review()
            review.usesNonExemptEncryption = answer
            draft.review = review
        }
        applyLocales(found, to: &draft)
        // Play's listing icon, where the project holds the file Play accepts.
        // Google only: see `playStoreIcon`.
        if store == .google, draft.media?.icon == nil, let icon = found.playIcon {
            var media = draft.media ?? Manifest.Media()
            media.icon = Self.path(of: icon, under: root)
            draft.media = media
        }
        // The listing name, in the language the listing is written in first.
        // A folder whose project names no language at all still has none, and
        // the name goes on the app's record instead, which is what the tab
        // strip reads. See `createApp`.
        if let name = found.name, !name.isEmpty,
           let code = draft.listing?.defaultLocale,
           draft.listing?.locales[code]?.name?.isEmpty != false {
            draft.setListingText(name, locale: code, field: .name)
        }
    }

    /// A file as `store.yaml` will name it: relative to the folder holding the
    /// file, and absolute when it sits outside that folder.
    ///
    /// The same rule as `relativePath(for:)`, against a root that is handed in
    /// rather than read off the open app. See `apply`.
    static func path(of url: URL, under root: URL?) -> String {
        guard let root = root?.standardizedFileURL.path else { return url.path }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    /// The languages the project ships, written into the listing.
    ///
    /// The default first, because `Manifest.addLocale` names the default only
    /// when it creates the listing. Every other language becomes an empty
    /// entry, which is exactly what the Add locale button makes: the developer
    /// still writes the words, and the app no longer asks them to remember
    /// which languages their own project ships.
    ///
    /// A manifest that already carries a listing keeps its default. The scan
    /// adds languages to it and never renames the one the developer chose.
    func applyLocales(_ found: ScannedProject, to draft: inout Manifest) {
        if draft.listing == nil, let code = found.locales.defaultLocale {
            draft.addLocale(code)
        }
        // Only beside a default. A project with `values-de` and `values-fr`
        // and nothing that says which of them is first would otherwise pick
        // one by sort order and call it the language of the listing.
        guard draft.listing != nil else { return }
        for code in found.locales.locales { draft.addLocale(code) }
    }
}

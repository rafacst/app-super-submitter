import Foundation

/// Small, tested mutations used by the SwiftUI form. Keeping these in
/// SubmitKit means the views never need to know how to construct a missing
/// manifest block.
public extension Manifest {
    mutating func setStore(_ store: Store, enabled: Bool) {
        switch store {
        case .apple:
            if enabled, apps.apple == nil {
                apps.apple = Apps.Apple(appId: "", platforms: [.ios], bundleId: "")
            } else if !enabled {
                apps.apple = nil
            }
        case .google:
            if enabled, apps.google == nil {
                apps.google = Apps.Google(packageName: "")
            } else if !enabled {
                apps.google = nil
            }
        }
    }

    mutating func setAppleApp(appID: String, bundleID: String,
                              platforms: [Platform] = [.ios]) {
        apps.apple = Apps.Apple(appId: appID, platforms: platforms, bundleId: bundleID)
    }

    mutating func setGoogleApp(packageName: String) {
        apps.google = Apps.Google(packageName: packageName)
    }

    mutating func addLocale(_ code: String, name: String? = nil) {
        if listing == nil {
            listing = Listing(defaultLocale: code, locales: [:])
        }
        guard var listing else { return }
        if listing.locales[code] == nil {
            var locale = Listing.Locale()
            locale.name = name
            listing.locales[code] = locale
        }
        self.listing = listing
    }

    mutating func apply(package: AppPackage, path: String) {
        var release = self.release ?? Release()
        var build = release.build ?? Release.Build()
        switch package.kind {
        case .ipa: build.ios = path
        case .pkg: build.macos = path
        case .aab: build.android = path
        }
        release.build = build
        if release.versionName?.isEmpty != false {
            release.versionName = package.versionName
        }
        self.release = release

        switch package.kind {
        case .ipa, .pkg:
            if apps.apple != nil, let identifier = package.identifier,
               apps.apple?.bundleId.isEmpty != false {
                apps.apple?.bundleId = identifier
            }
        case .aab:
            if apps.google != nil, let identifier = package.identifier,
               apps.google?.packageName.isEmpty != false {
                apps.google?.packageName = identifier
            }
        }

        let packageLocales = package.locales.isEmpty ? [] : package.locales
        if listing == nil, let first = packageLocales.first {
            listing = Listing(defaultLocale: first, locales: [:])
        }
        if listing == nil, package.appName != nil {
            listing = Listing(defaultLocale: "en-US", locales: [:])
        }
        for code in packageLocales { addLocale(code) }
        if var listing, let appName = package.appName {
            let code = listing.defaultLocale
            if listing.locales[code] == nil { addLocale(code) }
            listing = self.listing ?? listing
            if listing.locales[code]?.name?.isEmpty != false {
                listing.locales[code]?.name = appName
            }
            self.listing = listing
        }
    }

    mutating func setReleaseVersionName(_ value: String) {
        var release = self.release ?? Release()
        release.versionName = value
        self.release = release
    }

    mutating func mergeAppleImport(_ imported: ImportedStoreListing) {
        if let versionName = imported.versionName { setReleaseVersionName(versionName) }
        ensureListing(for: imported.locales.keys)
        guard var listing else { return }
        for (code, source) in imported.locales {
            var target = listing.locales[code] ?? Listing.Locale()
            target.name = source.name ?? target.name
            target.subtitle = managed(source.subtitle, keeping: target.subtitle)
            target.description = managed(source.description, keeping: target.description)
            target.whatsNew = managed(source.whatsNew, keeping: target.whatsNew)
            target.keywords = managed(source.keywords, keeping: target.keywords)
            target.promotionalText = managed(source.promotionalText, keeping: target.promotionalText)
            target.supportUrl = managed(source.supportURL, keeping: target.supportUrl)
            target.marketingUrl = managed(source.marketingURL, keeping: target.marketingUrl)
            target.privacyPolicyUrl = managed(source.privacyPolicyURL, keeping: target.privacyPolicyUrl)
            listing.locales[code] = target
        }
        self.listing = listing
    }

    mutating func mergeGoogleImport(_ imported: ImportedStoreListing) {
        if release?.versionName == nil, let versionName = imported.versionName {
            setReleaseVersionName(versionName)
        }
        ensureListing(for: imported.locales.keys)
        guard var listing else { return }
        for (code, source) in imported.locales {
            var target = listing.locales[code] ?? Listing.Locale()
            if target.name == nil { target.name = source.name }
            if !target.description.isManaged {
                target.description = managed(source.description, keeping: target.description)
            }

            var google = target.google ?? Listing.Locale.GoogleOverride()
            google.shortDescription = managed(source.subtitle, keeping: google.shortDescription)
            google.whatsNew = managed(source.whatsNew, keeping: google.whatsNew)
            google.video = managed(source.video, keeping: google.video)
            target.google = google
            listing.locales[code] = target
        }
        self.listing = listing
    }

    private mutating func ensureListing<S: Sequence>(for codes: S) where S.Element == String {
        let sorted = Array(codes).sorted()
        if listing == nil {
            let defaultLocale = sorted.first(where: { $0 == "en-US" }) ?? sorted.first ?? "en-US"
            listing = Listing(defaultLocale: defaultLocale, locales: [:])
        }
        for code in sorted { addLocale(code) }
    }

    private func managed(_ value: String?, keeping current: Managed<String>) -> Managed<String> {
        value.map(Managed.value) ?? current
    }
}

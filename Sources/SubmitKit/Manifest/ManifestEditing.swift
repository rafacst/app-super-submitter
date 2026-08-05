import Foundation

public enum ListingTextField: String, Codable, Sendable, CaseIterable {
    case name, subtitle, description, whatsNew, keywords, promotionalText
    case supportURL, marketingURL, privacyPolicyURL, privacyPolicyText, privacyChoicesURL
    case googleShortDescription, googleWhatsNew, googleVideo
}

public enum ReviewTextField: String, Sendable, CaseIterable {
    case firstName, lastName, email, phone, notes
    case applePrimaryCategory, appleSecondaryCategory
}

/// Small, tested mutations used by the SwiftUI form. Keeping these in
/// SubmitKit means the views never need to know how to construct a missing
/// manifest block.
public extension Manifest {
    func listingErrorCount(for stores: Set<Store>) -> Int {
        guard let localeCodes = listing?.locales.keys else { return 0 }
        var count = 0
        for code in localeCodes {
            let googleSubtitleOverride = hasGoogleOverride(
                locale: code, field: .googleShortDescription)
            let googleWhatsNewOverride = hasGoogleOverride(
                locale: code, field: .googleWhatsNew)
            let checks: [(ListingTextField, ListingField, Set<Store>)] = [
                (.name, .name, []),
                (.subtitle, .subtitle, googleSubtitleOverride ? [.google] : []),
                (.description, .description, []),
                (.whatsNew, .whatsNew, googleWhatsNewOverride ? [.google] : []),
                (.keywords, .keywords, []),
                (.promotionalText, .promotionalText, []),
            ]
            for (textField, listingField, overrides) in checks {
                if BindingLimits.overflow(
                    listingText(locale: code, field: textField), for: listingField,
                    stores: stores, overriddenIn: overrides) > 0 { count += 1 }
            }
            if googleSubtitleOverride,
               BindingLimits.overflow(
                listingText(locale: code, field: .googleShortDescription),
                for: .shortDescription, stores: [.google]) > 0 { count += 1 }
            if googleWhatsNewOverride,
               BindingLimits.overflow(
                listingText(locale: code, field: .googleWhatsNew),
                for: .whatsNew, stores: [.google]) > 0 { count += 1 }
        }
        return count
    }

    func listingText(locale code: String, field: ListingTextField) -> String {
        guard let locale = listing?.locales[code] else { return "" }
        return switch field {
        case .name: locale.name ?? ""
        case .subtitle: locale.subtitle.value ?? ""
        case .description: locale.description.value ?? ""
        case .whatsNew: locale.whatsNew.value ?? ""
        case .keywords: locale.keywords.value ?? ""
        case .promotionalText: locale.promotionalText.value ?? ""
        case .supportURL: locale.supportUrl.value ?? ""
        case .marketingURL: locale.marketingUrl.value ?? ""
        case .privacyPolicyURL: locale.privacyPolicyUrl.value ?? ""
        case .privacyPolicyText: locale.privacyPolicyText.value ?? ""
        case .privacyChoicesURL: locale.privacyChoicesUrl.value ?? ""
        case .googleShortDescription: locale.google?.shortDescription.value ?? ""
        case .googleWhatsNew: locale.google?.whatsNew.value ?? ""
        case .googleVideo: locale.google?.video.value ?? ""
        }
    }

    mutating func setListingText(_ value: String, locale code: String,
                                 field: ListingTextField) {
        addLocale(code)
        guard var listing else { return }
        var locale = listing.locales[code] ?? Listing.Locale()
        let managed = Managed<String>.value(value)
        switch field {
        case .name: locale.name = value
        case .subtitle: locale.subtitle = managed
        case .description: locale.description = managed
        case .whatsNew: locale.whatsNew = managed
        case .keywords: locale.keywords = managed
        case .promotionalText: locale.promotionalText = managed
        case .supportURL: locale.supportUrl = managed
        case .marketingURL: locale.marketingUrl = managed
        case .privacyPolicyURL: locale.privacyPolicyUrl = managed
        case .privacyPolicyText: locale.privacyPolicyText = managed
        case .privacyChoicesURL: locale.privacyChoicesUrl = managed
        case .googleShortDescription:
            var google = locale.google ?? Listing.Locale.GoogleOverride()
            google.shortDescription = managed
            locale.google = google
        case .googleWhatsNew:
            var google = locale.google ?? Listing.Locale.GoogleOverride()
            google.whatsNew = managed
            locale.google = google
        case .googleVideo:
            var google = locale.google ?? Listing.Locale.GoogleOverride()
            google.video = managed
            locale.google = google
        }
        listing.locales[code] = locale
        self.listing = listing
    }

    mutating func setGoogleOverride(_ enabled: Bool, locale code: String,
                                    field: ListingTextField) {
        addLocale(code)
        guard var listing else { return }
        var locale = listing.locales[code] ?? Listing.Locale()
        if enabled {
            var google = locale.google ?? Listing.Locale.GoogleOverride()
            if field == .googleShortDescription, !google.shortDescription.isManaged {
                google.shortDescription = .value(locale.subtitle.value ?? "")
            }
            if field == .googleWhatsNew, !google.whatsNew.isManaged {
                google.whatsNew = .value(locale.whatsNew.value ?? "")
            }
            locale.google = google
        } else if var google = locale.google {
            if field == .googleShortDescription { google.shortDescription = .unmanaged }
            if field == .googleWhatsNew { google.whatsNew = .unmanaged }
            locale.google = google
        }
        listing.locales[code] = locale
        self.listing = listing
    }

    func hasGoogleOverride(locale code: String, field: ListingTextField) -> Bool {
        guard let google = listing?.locales[code]?.google else { return false }
        return switch field {
        case .googleShortDescription: google.shortDescription.isManaged
        case .googleWhatsNew: google.whatsNew.isManaged
        case .googleVideo: google.video.isManaged
        default: false
        }
    }

    func mediaPaths(locale: String, deviceClass: DeviceClass, previews: Bool = false) -> [String] {
        let source = previews ? media?.previews : media?.screenshots
        return source?[locale]?[deviceClass.rawValue] ?? []
    }

    mutating func addMediaPaths(_ paths: [String], locale: String,
                                deviceClass: DeviceClass, previews: Bool = false) {
        var media = self.media ?? Media()
        if previews {
            var locales = media.previews ?? [:]
            var groups = locales[locale] ?? [:]
            var values = groups[deviceClass.rawValue] ?? []
            for path in paths where !values.contains(path) { values.append(path) }
            groups[deviceClass.rawValue] = values
            locales[locale] = groups
            media.previews = locales
        } else {
            var locales = media.screenshots ?? [:]
            var groups = locales[locale] ?? [:]
            var values = groups[deviceClass.rawValue] ?? []
            for path in paths where !values.contains(path) { values.append(path) }
            groups[deviceClass.rawValue] = values
            locales[locale] = groups
            media.screenshots = locales
        }
        self.media = media
    }

    /// Moves one file inside its bucket. The list order is the order the
    /// stores show, so the developer needs it and no other model does.
    mutating func moveMediaPath(_ path: String, by offset: Int, locale: String,
                                deviceClass: DeviceClass, previews: Bool = false) {
        var values = mediaPaths(locale: locale, deviceClass: deviceClass, previews: previews)
        guard let index = values.firstIndex(of: path) else { return }
        let target = index + offset
        guard values.indices.contains(target) else { return }
        values.swapAt(index, target)

        var media = self.media ?? Media()
        if previews {
            var locales = media.previews ?? [:]
            var groups = locales[locale] ?? [:]
            groups[deviceClass.rawValue] = values
            locales[locale] = groups
            media.previews = locales
        } else {
            var locales = media.screenshots ?? [:]
            var groups = locales[locale] ?? [:]
            groups[deviceClass.rawValue] = values
            locales[locale] = groups
            media.screenshots = locales
        }
        self.media = media
    }

    mutating func removeMediaPath(_ path: String, locale: String,
                                  deviceClass: DeviceClass, previews: Bool = false) {
        var media = self.media ?? Media()
        if previews {
            var locales = media.previews ?? [:]
            var groups = locales[locale] ?? [:]
            groups[deviceClass.rawValue]?.removeAll { $0 == path }
            locales[locale] = groups
            media.previews = locales
        } else {
            var locales = media.screenshots ?? [:]
            var groups = locales[locale] ?? [:]
            groups[deviceClass.rawValue]?.removeAll { $0 == path }
            locales[locale] = groups
            media.screenshots = locales
        }
        self.media = media
    }

    func reviewText(_ field: ReviewTextField) -> String {
        guard let review else { return "" }
        return switch field {
        case .firstName: review.contactFirstName ?? ""
        case .lastName: review.contactLastName ?? ""
        case .email: review.contactEmail ?? ""
        case .phone: review.contactPhone ?? ""
        case .notes: review.notes ?? ""
        case .applePrimaryCategory: review.applePrimaryCategory ?? ""
        case .appleSecondaryCategory: review.appleSecondaryCategory ?? ""
        }
    }

    mutating func setReviewText(_ value: String, field: ReviewTextField) {
        var review = self.review ?? Review()
        switch field {
        case .firstName: review.contactFirstName = value
        case .lastName: review.contactLastName = value
        case .email: review.contactEmail = value
        case .phone: review.contactPhone = value
        case .notes: review.notes = value
        case .applePrimaryCategory: review.applePrimaryCategory = value
        case .appleSecondaryCategory: review.appleSecondaryCategory = value
        }
        self.review = review
    }
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
        mergeImportedReview(imported.review)
        mergeImportedCatalog(imported)
        if release?.apple == nil,
           imported.appleReleaseType != nil || imported.applePhasedRelease != nil {
            var release = self.release ?? Release()
            release.apple = Release.AppleRelease(
                releaseType: imported.appleReleaseType.flatMap(Release.ReleaseType.init(rawValue:)),
                phasedRelease: imported.applePhasedRelease)
            self.release = release
        }
        ensureListing(for: imported.locales.keys, defaultLocale: imported.defaultLocale)
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
            target.privacyPolicyText = managed(source.privacyPolicyText,
                                               keeping: target.privacyPolicyText)
            target.privacyChoicesUrl = managed(source.privacyChoicesURL,
                                               keeping: target.privacyChoicesUrl)
            listing.locales[code] = target
        }
        self.listing = listing
    }

    mutating func mergeGoogleImport(_ imported: ImportedStoreListing) {
        if release?.versionName == nil, let versionName = imported.versionName {
            setReleaseVersionName(versionName)
        }
        mergeImportedReview(imported.review)
        mergeImportedCatalog(imported)
        if release?.google == nil, !imported.googleTracks.isEmpty {
            var release = self.release ?? Release()
            var google = release.google ?? Release.GoogleRelease()
            google.tracks = imported.googleTracks
            google.track = imported.googleTracks.contains("production")
                ? "production" : imported.googleTracks.first
            release.google = google
            self.release = release
        }
        ensureListing(for: imported.locales.keys, defaultLocale: imported.defaultLocale)
        guard var listing else { return }
        for (code, source) in imported.locales {
            var target = listing.locales[code] ?? Listing.Locale()
            if target.name == nil { target.name = source.name }
            if !target.description.isManaged {
                target.description = managed(source.description, keeping: target.description)
            }
            if !target.whatsNew.isManaged {
                target.whatsNew = managed(imported.googleReleaseNotes[code],
                                          keeping: target.whatsNew)
            }
            if !target.supportUrl.isManaged {
                target.supportUrl = managed(imported.googleContactWebsite,
                                            keeping: target.supportUrl)
            }

            var google = target.google ?? Listing.Locale.GoogleOverride()
            google.shortDescription = managed(source.subtitle, keeping: google.shortDescription)
            google.whatsNew = managed(imported.googleReleaseNotes[code] ?? source.whatsNew,
                                      keeping: google.whatsNew)
            google.video = managed(source.video, keeping: google.video)
            target.google = google
            listing.locales[code] = target
        }
        self.listing = listing
    }

    /// An import fills an empty catalog and never rewrites one the developer
    /// already holds. A workspace may be imported twice.
    private mutating func mergeImportedCatalog(_ imported: ImportedStoreListing) {
        if purchases?.isEmpty != false, !imported.purchases.isEmpty {
            purchases = imported.purchases
        }
        if subscriptions?.isEmpty != false, !imported.subscriptions.isEmpty {
            subscriptions = imported.subscriptions
        }
    }

    /// A store answer never clears an answer that another store already gave.
    private mutating func mergeImportedReview(_ imported: ImportedReview) {
        var review = self.review ?? Review()
        review.contactFirstName = review.contactFirstName ?? imported.contactFirstName
        review.contactLastName = review.contactLastName ?? imported.contactLastName
        review.contactEmail = review.contactEmail ?? imported.contactEmail
        review.contactPhone = review.contactPhone ?? imported.contactPhone
        review.demoAccountRequired = review.demoAccountRequired ?? imported.demoAccountRequired
        review.notes = review.notes ?? imported.notes
        review.applePrimaryCategory = review.applePrimaryCategory ?? imported.applePrimaryCategory
        review.appleSecondaryCategory = review.appleSecondaryCategory
            ?? imported.appleSecondaryCategory
        review.usesNonExemptEncryption = review.usesNonExemptEncryption
            ?? imported.usesNonExemptEncryption
        guard review != Review() else { return }
        self.review = review
    }

    private mutating func ensureListing<S: Sequence>(
        for codes: S, defaultLocale wanted: String? = nil) where S.Element == String {
        let sorted = Array(codes).sorted()
        if listing == nil {
            let fallback = sorted.first(where: { $0 == "en-US" }) ?? sorted.first ?? "en-US"
            listing = Listing(defaultLocale: wanted ?? fallback, locales: [:])
        }
        for code in sorted { addLocale(code) }
    }

    private func managed(_ value: String?, keeping current: Managed<String>) -> Managed<String> {
        value.map(Managed.value) ?? current
    }
}

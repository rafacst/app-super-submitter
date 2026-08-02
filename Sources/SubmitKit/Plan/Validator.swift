import Foundation

/// Every rule from spec section 10, in the order that the section states them.
///
/// A rule has a severity of error or warning. An error blocks the apply. A
/// warning needs one acknowledgement. Nothing here writes, and nothing here
/// shortens a value: an over-limit field is an error the developer fixes.
public enum Validator {

    public static func findings(_ input: Planner.Input) -> [Finding] {
        var result: [Finding] = []
        result += text(input)
        result += review(input)
        result += media(input)
        result += build(input)
        result += money(input)
        result += offers(input)
        result += marketing(input)
        result += monetization(input)
        result += state(input)
        // The errors first: tab 7 shows them at the top.
        return result.sorted { lhs, rhs in
            lhs.severity == rhs.severity ? lhs.id < rhs.id : lhs.severity == .error
        }
    }

    static func review(_ input: Planner.Input) -> [Finding] {
        guard input.stores.contains(.google) else { return [] }
        if let path = input.manifest.review?.dataSafetyCSV, !path.isEmpty,
           Planner.resolve(path, root: input.root) == nil {
            return [Finding(
                id: "review.dataSafetyCSV.missing", severity: .error,
                message: "The Google Data safety CSV \(path) does not exist.",
                location: "Review Info · Google data safety", fix: .reviewInfo)]
        }
        if input.manifest.review?.dataSafetyCSV?.isEmpty != false,
           input.manifest.review?.dataSafetyAnswers?.isEmpty == false {
            return [Finding(
                id: "review.dataSafetyCSV.recommended", severity: .warning,
                message: "Use a current CSV exported from Play Console for a complete Data safety declaration. Google's question template changes over time.",
                location: "Review Info · Google data safety", fix: .reviewInfo)]
        }
        return []
    }

    // MARK: - 10.1 Text

    static func text(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        let stores = input.stores
        var result: [Finding] = []

        guard let listing = manifest.listing else {
            return [Finding(id: "text.noDefault", severity: .error,
                            message: "The manifest holds no listing.",
                            location: "Details", fix: .details)]
        }
        if listing.locales[listing.defaultLocale] == nil {
            result.append(Finding(
                id: "text.noDefault", severity: .error,
                message: "The default locale has no entry in the manifest.",
                location: "Details · \(listing.defaultLocale)", fix: .details))
        }

        for code in listing.locales.keys.sorted() {
            let googleSubtitle = manifest.hasGoogleOverride(locale: code,
                                                            field: .googleShortDescription)
            let googleWhatsNew = manifest.hasGoogleOverride(locale: code, field: .googleWhatsNew)
            let checks: [(ListingTextField, ListingField, Set<Store>, String)] = [
                (.name, .name, [], "Name"),
                (.subtitle, .subtitle, googleSubtitle ? [.google] : [], "Subtitle"),
                (.description, .description, [], "Description"),
                (.whatsNew, .whatsNew, googleWhatsNew ? [.google] : [], "What's new"),
                (.keywords, .keywords, [], "Keywords"),
                (.promotionalText, .promotionalText, [], "Promotional text"),
            ]
            for (textField, field, overrides, label) in checks {
                let value = manifest.listingText(locale: code, field: textField)
                let overflow = BindingLimits.overflow(value, for: field, stores: stores,
                                                      overriddenIn: overrides)
                guard overflow > 0 else { continue }
                let limit = BindingLimits.binding(for: field, stores: stores,
                                                  overriddenIn: overrides) ?? 0
                result.append(Finding(
                    id: "text.\(code).\(textField.rawValue)", severity: .error,
                    message: "\(label) is \(value.count) characters. The limit is \(limit).",
                    location: "Details · \(code) · \(label)", fix: .details))
            }

            // The Google release note has its own limit, and its own override.
            let note = googleWhatsNew
                ? manifest.listingText(locale: code, field: .googleWhatsNew)
                : manifest.listingText(locale: code, field: .whatsNew)
            if stores.contains(.google), note.count > 500 {
                result.append(Finding(
                    id: "text.\(code).googleWhatsNew", severity: .error,
                    message: "The Google release note is \(note.count) characters. The limit is 500.",
                    location: "Details · \(code) · What's new", fix: .details))
            }
            if googleSubtitle {
                let short = manifest.listingText(locale: code, field: .googleShortDescription)
                if BindingLimits.overflow(short, for: .shortDescription, stores: [.google]) > 0 {
                    result.append(Finding(
                        id: "text.\(code).googleShort", severity: .error,
                        message: "The Google short description is \(short.count) characters. The limit is 80.",
                        location: "Details · \(code) · Short description", fix: .details))
                }
            }

            // A locale that the store does not support. The read supplies the
            // list; with no read the app claims nothing.
            if let supported = input.actual.apple?.infoLocales.keys, !supported.isEmpty,
               stores.contains(.apple), input.actual.apple?.versionId != nil,
               !supported.contains(code), listing.locales.count > 1,
               input.actual.apple?.infoLocales.isEmpty == false,
               !Self.appleLocales.contains(code) {
                result.append(Finding(
                    id: "text.\(code).unsupported", severity: .warning,
                    message: "The App Store does not list \(code) as a supported locale.",
                    location: "Details · \(code)", fix: .details))
            }
        }
        return result
    }

    // MARK: - 10.2 Media

    static func media(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        var result: [Finding] = []
        let locales = Array(manifest.media?.screenshots?.keys ?? [:].keys).sorted()

        for code in locales {
            for deviceClass in Manifest.DeviceClass.allCases {
                let paths = manifest.mediaPaths(locale: code, deviceClass: deviceClass)
                guard !paths.isEmpty else { continue }

                for path in paths {
                    guard let url = Planner.resolve(path, root: input.root) else {
                        result.append(Finding(
                            id: "media.missing.\(path)", severity: .error,
                            message: "The file \(path) does not exist.",
                            location: "Media · \(code) · \(deviceClass.rawValue)", fix: .media))
                        continue
                    }
                    do {
                        let info = try AssetInspector.image(at: url)
                        _ = try AssetInspector.compatibleStores(
                            for: info, deviceClass: deviceClass, selectedStores: input.stores)
                    } catch {
                        result.append(Finding(
                            id: "media.size.\(path)", severity: .error,
                            message: error.localizedDescription,
                            location: "Media · \(code) · \(deviceClass.rawValue)", fix: .media))
                    }
                }

                // Apple takes 10 per display type, Google takes 8 per locale.
                if input.stores.contains(.apple), paths.count > 10 {
                    result.append(Finding(
                        id: "media.count.apple.\(code).\(deviceClass.rawValue)", severity: .error,
                        message: "\(paths.count) screenshots exceed the App Store limit of 10.",
                        location: "Media · \(code) · \(deviceClass.rawValue)", fix: .media))
                }
                if input.stores.contains(.google), paths.count > 8,
                   AssetInspector.googleImageType(for: deviceClass) != nil {
                    result.append(Finding(
                        id: "media.count.google.\(code).\(deviceClass.rawValue)", severity: .error,
                        message: "\(paths.count) screenshots exceed the Google Play limit of 8.",
                        location: "Media · \(code) · \(deviceClass.rawValue)", fix: .media))
                }

                // One store has screenshots and the other has none.
                if input.stores.count == 2 {
                    let apple = Planner.mediaUploads(paths, deviceClass: deviceClass,
                                                     store: .apple, root: input.root)
                    let google = Planner.mediaUploads(paths, deviceClass: deviceClass,
                                                      store: .google, root: input.root)
                    if apple.isEmpty != google.isEmpty {
                        let empty = apple.isEmpty ? "the App Store" : "Google Play"
                        result.append(Finding(
                            id: "media.oneStore.\(code).\(deviceClass.rawValue)",
                            severity: .warning,
                            message: "\(code) has \(deviceClass.rawValue) screenshots for one store and none for \(empty).",
                            location: "Media · \(code) · \(deviceClass.rawValue)", fix: .media))
                    }
                }
            }

            // The app previews.
            for deviceClass in Manifest.DeviceClass.allCases {
                let previews = manifest.mediaPaths(locale: code, deviceClass: deviceClass,
                                                   previews: true)
                guard !previews.isEmpty else { continue }
                if previews.count > 3 {
                    result.append(Finding(
                        id: "media.previewCount.\(code).\(deviceClass.rawValue)", severity: .error,
                        message: "\(previews.count) app previews exceed the limit of 3 per display type.",
                        location: "Media · \(code) · \(deviceClass.rawValue)", fix: .media))
                }
                if input.stores.contains(.google),
                   manifest.listingText(locale: code, field: .googleVideo).isEmpty {
                    result.append(Finding(
                        id: "media.noYouTube.\(code)", severity: .warning,
                        message: "\(code) holds an app preview and no Google YouTube URL. Google shows no video without it.",
                        location: "Media · \(code) · Google video", fix: .media))
                }
            }
        }

        // The two Google graphics have exact sizes.
        if input.stores.contains(.google) {
            if let icon = manifest.media?.icon {
                result += graphic(icon, name: "icon", width: 512, height: 512,
                                  requirePNG: true, root: input.root)
            }
            if let feature = manifest.media?.featureGraphic {
                result += graphic(feature, name: "featureGraphic", width: 1_024, height: 500,
                                  requirePNG: false, root: input.root)
            }
        }
        return result
    }

    private static func graphic(_ path: String, name: String, width: Int, height: Int,
                                requirePNG: Bool, root: URL?) -> [Finding] {
        guard let url = Planner.resolve(path, root: root) else {
            return [Finding(id: "media.\(name).missing", severity: .error,
                            message: "The Google \(name) file \(path) does not exist.",
                            location: "Media · \(name)", fix: .media)]
        }
        guard let info = try? AssetInspector.image(at: url) else {
            return [Finding(id: "media.\(name).unreadable", severity: .error,
                            message: "The Google \(name) could not be read.",
                            location: "Media · \(name)", fix: .media)]
        }
        var problems: [String] = []
        if info.width != width || info.height != height {
            problems.append("\(info.width) × \(info.height) is not \(width) by \(height)")
        }
        if requirePNG, url.pathExtension.lowercased() != "png" {
            problems.append("the file is not a PNG")
        }
        guard !problems.isEmpty else { return [] }
        return [Finding(id: "media.\(name).size", severity: .error,
                        message: "The Google \(name): \(problems.joined(separator: ", ")).",
                        location: "Media · \(name)", fix: .media)]
    }

    // MARK: - 10.3 Build

    static func build(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        var result: [Finding] = []

        for (path, store) in [(Planner.applePath(manifest), Store.apple),
                              (manifest.release?.build?.android, Store.google)] {
            guard input.stores.contains(store), let path, !path.isEmpty else { continue }
            if Planner.resolve(path, root: input.root) == nil {
                result.append(Finding(
                    id: "build.missing.\(store.rawValue)", severity: .error,
                    message: "The manifest names the build \(path) and the file does not exist.",
                    location: "Build · \(store == .apple ? "iOS" : "Android")", fix: .build))
            }
        }
        result += googleArtifacts(input)
        result += googleTracks(input)

        if let package = input.packages[.ipa] ?? input.packages[.pkg] {
            if let bundleID = manifest.apps.apple?.bundleId, !bundleID.isEmpty,
               let identifier = package.identifier, identifier != bundleID {
                result.append(Finding(
                    id: "build.bundleId", severity: .error,
                    message: "The build bundle id \(identifier) does not match \(bundleID).",
                    location: "Build · iOS", fix: .build))
            }
            if let highest = input.actual.apple?.highestBuildNumber,
               let current = package.buildNumber.flatMap(Int.init), current <= highest {
                result.append(Finding(
                    id: "build.number", severity: .error,
                    message: "The build number \(current) is not greater than \(highest) in App Store Connect.",
                    location: "Build · iOS", fix: .build))
            }
            if let versionName = manifest.release?.versionName, !versionName.isEmpty,
               let packageVersion = package.versionName, packageVersion != versionName {
                result.append(Finding(
                    id: "build.versionName.apple", severity: .warning,
                    message: "The version name differs between the manifest and the build.",
                    location: "Build · \(versionName) and \(packageVersion)", fix: .build))
            }
        }

        if let package = input.packages[.aab] {
            if let packageName = manifest.apps.google?.packageName, !packageName.isEmpty,
               let identifier = package.identifier, identifier != packageName {
                result.append(Finding(
                    id: "build.packageName", severity: .error,
                    message: "The bundle package name \(identifier) does not match \(packageName).",
                    location: "Build · Android", fix: .build))
            }
            if let highest = input.actual.google?.highestVersionCode,
               let current = package.buildNumber.flatMap(Int.init), current <= highest {
                result.append(Finding(
                    id: "build.versionCode", severity: .error,
                    message: "The version code \(current) is not greater than \(highest) in the target track.",
                    location: "Build · Android", fix: .build))
            }
            if let versionName = manifest.release?.versionName, !versionName.isEmpty,
               let packageVersion = package.versionName, packageVersion != versionName {
                result.append(Finding(
                    id: "build.versionName.google", severity: .warning,
                    message: "The version name differs between the manifest and the bundle.",
                    location: "Build · \(versionName) and \(packageVersion)", fix: .build))
            }
        }
        return result
    }

    // MARK: - 10.3 The Google artifacts

    /// The APK, the deobfuscation files, the expansion files, and the
    /// externally hosted APK. Every rule here fails before a byte moves.
    static func googleArtifacts(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        guard input.stores.contains(.google) else { return [] }
        let google = manifest.release?.google
        var result: [Finding] = []

        let files: [(String, String?, String)] = [
            ("apk", manifest.release?.build?.androidApk, "the APK"),
            ("mapping", google?.mappingFile, "the mapping file"),
            ("symbols", google?.nativeDebugSymbols, "the native symbols"),
            ("expansionMain", google?.expansionFileMain, "the main expansion file"),
            ("expansionPatch", google?.expansionFilePatch, "the patch expansion file"),
        ]
        for (key, path, label) in files {
            guard let path, !path.isEmpty else { continue }
            if Planner.resolve(path, root: input.root) == nil {
                result.append(Finding(
                    id: "build.google.\(key)", severity: .error,
                    message: "The manifest names \(label) \(path) and the file does not exist.",
                    location: "Build · Android", fix: .build))
            }
        }

        // Google attaches an expansion file to an APK. A bundle carries its
        // assets inside, so the pair is a manifest mistake, not a store error.
        let hasExpansion = [google?.expansionFileMain, google?.expansionFilePatch]
            .contains { $0?.isEmpty == false }
        if hasExpansion, manifest.release?.build?.androidApk?.isEmpty != false {
            result.append(Finding(
                id: "build.expansionNeedsApk", severity: .error,
                message: "An expansion file needs an APK. The manifest names no androidApk build.",
                location: "Build · Android", fix: .build))
        }

        if let external = google?.externalApk {
            if !external.url.lowercased().hasPrefix("https://") {
                result.append(Finding(
                    id: "build.externalApk.url", severity: .error,
                    message: "The externally hosted APK URL must use https.",
                    location: "Build · Android", fix: .build))
            }
            if external.certificateBase64s.filter({ !$0.isEmpty }).isEmpty {
                result.append(Finding(
                    id: "build.externalApk.certificate", severity: .error,
                    message: "The externally hosted APK names no signing certificate.",
                    location: "Build · Android", fix: .build))
            }
            if external.versionCode <= 0 {
                result.append(Finding(
                    id: "build.externalApk.versionCode", severity: .error,
                    message: "The externally hosted APK version code must be greater than zero.",
                    location: "Build · Android", fix: .build))
            }
            result.append(Finding(
                id: "build.externalApk.private", severity: .warning,
                message: "Google accepts an externally hosted APK from a Google Play organization only. A normal account answers 403.",
                location: "Build · Android", fix: .build))
        }
        return result
    }

    /// The track list and the country targeting.
    static func googleTracks(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        guard input.stores.contains(.google) else { return [] }
        var result: [Finding] = []

        let listed = (manifest.release?.google?.tracks ?? []).filter { !$0.isEmpty }
        if !listed.isEmpty, let primary = manifest.release?.google?.track, !primary.isEmpty,
           !listed.contains(primary) {
            result.append(Finding(
                id: "build.trackNotListed", severity: .error,
                message: "The release track \(primary) is not in the tracks list. The release button would write a track that no apply prepared.",
                location: "Build · Android", fix: .build))
        }
        if Set(listed).count != listed.count {
            result.append(Finding(
                id: "build.trackDuplicate", severity: .error,
                message: "The tracks list names the same track twice.",
                location: "Build · Android", fix: .build))
        }

        for code in (manifest.release?.google?.countries ?? []) {
            guard code.count != 2 || code != code.uppercased() else { continue }
            result.append(Finding(
                id: "build.country.\(code)", severity: .error,
                message: "\(code) is not a two-letter uppercase country code.",
                location: "Build · Android", fix: .build))
        }
        // Google assigns the id and keeps every configuration, so a second
        // apply makes a second configuration. No diff row can show that.
        if let path = manifest.release?.google?.deviceTierConfig, !path.isEmpty {
            if Planner.resolve(path, root: input.root) == nil {
                result.append(Finding(
                    id: "build.deviceTierMissing", severity: .error,
                    message: "The manifest names the device tier configuration \(path) and the file does not exist.",
                    location: "Build · Android", fix: .build))
            } else {
                result.append(Finding(
                    id: "build.deviceTierRepeats", severity: .warning,
                    message: "Every apply creates a new device tier configuration, because Google assigns the id and keeps the old one. Remove the key once the configuration is live.",
                    location: "Build · Android", fix: .build))
            }
        }

        if (manifest.release?.google?.countries ?? []).isEmpty,
           manifest.release?.google?.includeRestOfWorld != nil {
            result.append(Finding(
                id: "build.restOfWorldAlone", severity: .warning,
                message: "includeRestOfWorld does nothing while the countries list is empty. The release reaches every country.",
                location: "Build · Android", fix: .build))
        }
        return result
    }

    // MARK: - 10.4 Money

    static func money(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        var result: [Finding] = []

        // The resolved Apple price point, against the request.
        if let requested = manifest.pricing?.base,
           let resolved = input.actual.apple?.priceAmount,
           requested.currency == (input.actual.apple?.priceCurrency ?? requested.currency),
           resolved > 0 {
            let difference = abs((requested.amount as NSDecimalNumber).doubleValue
                                 - (resolved as NSDecimalNumber).doubleValue)
            let base = (requested.amount as NSDecimalNumber).doubleValue
            if base > 0, difference / base > 0.05 {
                result.append(Finding(
                    id: "money.pricePoint", severity: .warning,
                    message: "The App Store resolved \(resolved) \(requested.currency) for a request of \(requested.amount) \(requested.currency).",
                    location: "Money · Base price", fix: .money))
            }
        }

        for group in manifest.subscriptions ?? [] {
            for plan in group.plans where AppleDurations.name(for: plan.duration) == nil {
                result.append(Finding(
                    id: "money.duration.\(plan.id)", severity: .error,
                    message: "The App Store offers no \(plan.duration) subscription duration.",
                    location: "Money · \(group.groupId) · \(plan.id)", fix: .money))
            }
        }

        if input.stores.count == 2 {
            let apple = Set(input.actual.apple?.purchaseIds ?? [])
                .union(input.actual.apple?.subscriptionIds ?? [])
            let google = Set(input.actual.google?.oneTimeProductIds ?? [])
                .union(input.actual.google?.subscriptionIds ?? [])
            if !apple.isEmpty, !google.isEmpty {
                for id in apple.symmetricDifference(google).sorted() {
                    result.append(Finding(
                        id: "money.oneStore.\(id)", severity: .warning,
                        message: "The product \(id) exists in one store and not in the other.",
                        location: "Money · Purchases", fix: .money))
                }
            }
        }
        return result
    }

    // MARK: - 10.4 The offers and the catalog states

    /// The discounts, the grace period, and the one call in the app that
    /// reaches a paying customer.
    static func offers(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        var result: [Finding] = []

        var everyOffer: [(String, Manifest.Offer)] = []
        for purchase in manifest.purchases ?? [] {
            everyOffer += (purchase.offers ?? []).map { (purchase.id, $0) }
        }
        for group in manifest.subscriptions ?? [] {
            for plan in group.plans {
                everyOffer += (plan.offers ?? []).map { (plan.id, $0) }
            }
        }

        var seen: Set<String> = []
        for (productID, offer) in everyOffer {
            let location = "Money · \(productID) · \(offer.id)"
            if !seen.insert("\(productID)/\(offer.id)").inserted {
                result.append(Finding(
                    id: "offer.duplicate.\(productID).\(offer.id)", severity: .error,
                    message: "The product \(productID) names the offer \(offer.id) twice.",
                    location: location, fix: .money))
            }
            if offer.kind == .freeTrial, offer.duration?.isEmpty != false {
                result.append(Finding(
                    id: "offer.trialDuration.\(offer.id)", severity: .error,
                    message: "The free trial \(offer.id) names no duration.",
                    location: location, fix: .money))
            }
            if offer.kind == .introPrice, offer.price == nil {
                result.append(Finding(
                    id: "offer.introPrice.\(offer.id)", severity: .error,
                    message: "The introductory offer \(offer.id) names no price.",
                    location: location, fix: .money))
            }
            if input.stores.contains(.apple), let duration = offer.duration,
               AppleDurations.offerDuration(for: duration) == nil {
                result.append(Finding(
                    id: "offer.appleDuration.\(offer.id)", severity: .error,
                    message: "The App Store offers no \(duration) offer duration. It accepts \(AppleDurations.offerDurations.keys.sorted().joined(separator: ", ")).",
                    location: location, fix: .money))
            }
            // Google accepts a lowercase id with digits and dashes only.
            if input.stores.contains(.google),
               offer.id != offer.id.lowercased()
                || offer.id.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "-" }) {
                result.append(Finding(
                    id: "offer.googleId.\(offer.id)", severity: .error,
                    message: "Google accepts a lowercase offer id with digits and dashes only. \(offer.id) does not match.",
                    location: location, fix: .money))
            }
            if (offer.periods ?? 1) < 1 {
                result.append(Finding(
                    id: "offer.periods.\(offer.id)", severity: .error,
                    message: "The offer \(offer.id) runs for fewer than one period.",
                    location: location, fix: .money))
            }
        }

        // Apple keeps one grace period for the whole app. Two different
        // values in one manifest means the second one never reaches Apple.
        let periods = Set((manifest.subscriptions ?? []).compactMap(\.gracePeriodDays))
        if periods.count > 1, input.stores.contains(.apple) {
            result.append(Finding(
                id: "offer.gracePeriodDisagreement", severity: .warning,
                message: "The manifest names \(periods.count) different grace periods. The App Store keeps one for the whole app, and the first group wins.",
                location: "Money · Grace period", fix: .money))
        }

        for group in manifest.subscriptions ?? [] {
            for plan in group.plans where plan.migrateExistingSubscribers == true {
                result.append(Finding(
                    id: "offer.migrate.\(plan.id)", severity: .warning,
                    message: "The plan \(plan.id) migrates the existing subscribers. This changes what a paying customer is charged at the next renewal, and no call undoes it.",
                    location: "Money · \(group.groupId) · \(plan.id)", fix: .money))
            }
        }
        return result
    }

    // MARK: - 10.4 The App Store marketing resources

    static func marketing(_ input: Planner.Input) -> [Finding] {
        guard let marketing = input.manifest.marketing else { return [] }
        var result: [Finding] = []

        // Apple allows 35 custom product pages per app.
        if let pages = marketing.customProductPages, pages.count > 35 {
            result.append(Finding(
                id: "marketing.pageCount", severity: .error,
                message: "\(pages.count) custom product pages exceed the App Store limit of 35.",
                location: "Marketing · Custom product pages", fix: .marketing))
        }
        for page in marketing.customProductPages ?? [] {
            for (code, locale) in (page.locales ?? [:]).sorted(by: { $0.key < $1.key }) {
                guard let text = locale.promotionalText, text.count > 170 else { continue }
                result.append(Finding(
                    id: "marketing.page.\(page.key).\(code)", severity: .error,
                    message: "The promotional text of \(page.key) is \(text.count) characters. The limit is 170.",
                    location: "Marketing · \(page.key) · \(code)", fix: .marketing))
            }
        }

        for experiment in marketing.experiments ?? [] {
            let proportion = experiment.trafficProportion ?? 50
            if !(1...100).contains(proportion) {
                result.append(Finding(
                    id: "marketing.traffic.\(experiment.key)", severity: .error,
                    message: "The experiment \(experiment.key) sends \(proportion) percent of the traffic. The range is 1 to 100.",
                    location: "Marketing · \(experiment.key)", fix: .marketing))
            }
            if experiment.treatments.isEmpty {
                result.append(Finding(
                    id: "marketing.treatments.\(experiment.key)", severity: .error,
                    message: "The experiment \(experiment.key) holds no treatment, so it compares nothing.",
                    location: "Marketing · \(experiment.key)", fix: .marketing))
            }
            if experiment.treatments.count > 3 {
                result.append(Finding(
                    id: "marketing.treatmentCount.\(experiment.key)", severity: .error,
                    message: "\(experiment.treatments.count) treatments exceed the App Store limit of 3.",
                    location: "Marketing · \(experiment.key)", fix: .marketing))
            }
        }

        for event in marketing.events ?? [] {
            for (code, locale) in (event.locales ?? [:]).sorted(by: { $0.key < $1.key }) {
                let checks = [("name", locale.name, 30),
                              ("shortDescription", locale.shortDescription, 50),
                              ("longDescription", locale.longDescription, 120)]
                for (field, value, limit) in checks {
                    guard let value, value.count > limit else { continue }
                    result.append(Finding(
                        id: "marketing.event.\(event.key).\(code).\(field)", severity: .error,
                        message: "The event \(field) is \(value.count) characters. The limit is \(limit).",
                        location: "Marketing · \(event.key) · \(code)", fix: .marketing))
                }
            }
        }

        if let eula = marketing.eula, eula.text.count > 10_000 {
            result.append(Finding(
                id: "marketing.eulaLength", severity: .error,
                message: "The licence agreement is \(eula.text.count) characters. The limit is 10000.",
                location: "Marketing · Licence agreement", fix: .marketing))
        }

        if let path = marketing.routingCoverage {
            if Planner.resolve(path, root: input.root) == nil {
                result.append(Finding(
                    id: "marketing.routingMissing", severity: .error,
                    message: "The manifest names the routing coverage \(path) and the file does not exist.",
                    location: "Marketing · Routing coverage", fix: .marketing))
            } else if !path.lowercased().hasSuffix(".geojson") {
                result.append(Finding(
                    id: "marketing.routingType", severity: .error,
                    message: "The routing app coverage must be a .geojson file.",
                    location: "Marketing · Routing coverage", fix: .marketing))
            }
        }

        if input.stores.contains(.google), input.manifest.marketing != nil {
            result.append(Finding(
                id: "marketing.appleOnly", severity: .warning,
                message: "The marketing block reaches the App Store only. Google Play offers no equivalent for any of it.",
                location: "Marketing · Marketing", fix: .marketing))
        }
        return result
    }

    // MARK: - 10.5 The monetization platform

    static func monetization(_ input: Planner.Input) -> [Finding] {
        let manifest = input.manifest
        let provider = manifest.monetization?.provider ?? .none
        guard provider != .none else { return [] }
        var result: [Finding] = []
        let actual = input.actual.provider
        let declared = Set((manifest.entitlements ?? []).map(\.key))
        let productIds = Set(manifest.productIds)

        for (id, keys) in manifest.entitlementsByProduct {
            for key in keys where !declared.contains(key) {
                result.append(Finding(
                    id: "provider.entitlement.\(id).\(key)", severity: .error,
                    message: "The product \(id) names the entitlement \(key), which the manifest does not declare.",
                    location: "Money · Entitlements", fix: .money))
            }
        }

        for offering in manifest.offerings ?? [] {
            for product in offering.products ?? [] where !productIds.contains(product) {
                result.append(Finding(
                    id: "provider.offering.\(offering.key).\(product)", severity: .error,
                    message: "The offering \(offering.key) names \(product), which no purchase and no plan declares.",
                    location: "Money · Offerings", fix: .money))
            }
        }

        if (manifest.offerings ?? []).isEmpty {
            result.append(Finding(
                id: "provider.noOffering", severity: .warning,
                message: "The manifest holds no offering. The app code then has nothing to request.",
                location: "Money · Offerings", fix: .money))
        }

        for orphan in (actual?.offeringKeys ?? [])
            .subtracting(Set((manifest.offerings ?? []).map(\.key))).sorted() {
            result.append(Finding(
                id: "provider.orphan.\(orphan)", severity: .warning,
                message: "The offering \(orphan) exists in the provider and not in the manifest. The plan archives it.",
                location: "Money · Offerings", fix: .money))
        }

        switch provider {
        case .revenuecat:
            let appIds = manifest.monetization?.revenuecat?.appIds
            if let appleAppId = appIds?.appStore, !appleAppId.isEmpty {
                if let identifiers = actual?.appIdentifiers, !identifiers.isEmpty {
                    if identifiers[appleAppId] == nil {
                        result.append(Finding(
                            id: "rc.appMissing.apple", severity: .error,
                            message: "The RevenueCat app id \(appleAppId) does not exist in the project.",
                            location: "Money · RevenueCat", fix: .money))
                    } else if let bundleID = manifest.apps.apple?.bundleId,
                              !bundleID.isEmpty, identifiers[appleAppId] != bundleID {
                        result.append(Finding(
                            id: "rc.bundleId", severity: .error,
                            message: "The RevenueCat App Store bundle id \(identifiers[appleAppId] ?? "") does not match \(bundleID). A wrong app id writes to another app.",
                            location: "Money · RevenueCat", fix: .money))
                    }
                }
            }
            if let playAppId = appIds?.playStore, !playAppId.isEmpty,
               let identifiers = actual?.appIdentifiers, !identifiers.isEmpty,
               let packageName = manifest.apps.google?.packageName, !packageName.isEmpty,
               identifiers[playAppId] != nil, identifiers[playAppId] != packageName {
                result.append(Finding(
                    id: "rc.packageName", severity: .error,
                    message: "The RevenueCat Play Store package name \(identifiers[playAppId] ?? "") does not match \(packageName).",
                    location: "Money · RevenueCat", fix: .money))
            }
            if !(manifest.offerings ?? []).isEmpty,
               (manifest.offerings ?? []).allSatisfy({ $0.isCurrent != true }) {
                result.append(Finding(
                    id: "rc.noCurrent", severity: .warning,
                    message: "No offering is marked current. The app code then reads no default offering.",
                    location: "Money · Offerings", fix: .money))
            }
            for scope in actual?.missingScopes ?? [] {
                result.append(Finding(
                    id: "rc.scope.\(scope)", severity: .error,
                    message: "The RevenueCat API key lacks the scope \(scope).",
                    location: "Money · RevenueCat", fix: .money))
            }
        case .adapty:
            if actual?.loggedInAs == nil {
                result.append(Finding(
                    id: "adapty.auth", severity: .error,
                    message: "The adapty CLI is not logged in. Run adapty auth login.",
                    location: "Money · Adapty", fix: .money))
            }
            for group in manifest.subscriptions ?? [] {
                for plan in group.plans {
                    if AdaptyPeriods.period(for: plan.duration) == nil {
                        result.append(Finding(
                            id: "adapty.period.\(plan.id)", severity: .error,
                            message: "Adapty has no period for \(plan.duration) on \(plan.id). The supported periods are \(AdaptyPeriods.supported.joined(separator: ", ")).",
                            location: "Money · \(group.groupId)", fix: .money))
                    }
                    if input.stores.contains(.google), plan.basePlanId?.isEmpty != false {
                        result.append(Finding(
                            id: "adapty.basePlan.\(plan.id)", severity: .error,
                            message: "The Android subscription plan \(plan.id) has no basePlanId.",
                            location: "Money · \(group.groupId)", fix: .money))
                    }
                    if (plan.entitlements?.count ?? 0) > 1 {
                        result.append(Finding(
                            id: "adapty.manyEntitlements.\(plan.id)", severity: .warning,
                            message: "Adapty takes one access level. \(plan.id) names \(plan.entitlements?.count ?? 0); the app uses \(plan.entitlements?.first ?? "").",
                            location: "Money · \(group.groupId)", fix: .money))
                    }
                }
            }
        case .none:
            break
        }
        return result
    }

    // MARK: - 10.6 State

    static func state(_ input: Planner.Input) -> [Finding] {
        var result: [Finding] = []
        guard let apple = input.actual.apple else { return result }

        let writesMetadata = input.stores.contains(.apple)
        if writesMetadata, let versionState = apple.versionState,
           versionState != "PREPARE_FOR_SUBMISSION" {
            result.append(Finding(
                id: "state.appleVersion", severity: .error,
                message: "The App Store version is \(versionState). Metadata writes need PREPARE_FOR_SUBMISSION.",
                location: "Plan · App Store", fix: .plan))
        }
        if apple.hasOpenReviewSubmission {
            result.append(Finding(
                id: "state.openSubmission", severity: .error,
                message: "An App Store review submission is already open. Cancel it before you apply.",
                location: "Plan · App Store", fix: .plan))
        }

        let track = input.manifest.googlePrimaryTrack
        if let google = input.actual.google,
           let draft = google.tracks[track], draft.status == "draft",
           let existing = draft.versionCodes.first,
           let package = input.packages[.aab]?.buildNumber.flatMap(Int.init),
           existing != package {
            result.append(Finding(
                id: "state.googleDraft", severity: .warning,
                message: "A draft release already exists in \(track) with version code \(existing). This apply replaces it with \(package).",
                location: "Plan · Google Play", fix: .plan))
        }
        return result
    }

    /// The locales that the App Store lists. Used only to warn, never to block.
    private static let appleLocales: Set<String> = [
        "ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US",
        "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id",
        "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro",
        "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
    ]
}

/// The subscription durations that Apple offers. Spec section 10.4.
public enum AppleDurations {
    public static let map: [String: String] = [
        "P1W": "1 week", "P1M": "1 month", "P2M": "2 months", "P3M": "3 months",
        "P6M": "6 months", "P1Y": "1 year",
    ]

    public static func name(for duration: String) -> String? {
        map[duration.uppercased()]
    }

    /// The `subscriptionPeriod` value that App Store Connect accepts.
    public static let apiPeriods: [String: String] = [
        "P1W": "ONE_WEEK", "P1M": "ONE_MONTH", "P2M": "TWO_MONTHS",
        "P3M": "THREE_MONTHS", "P6M": "SIX_MONTHS", "P1Y": "ONE_YEAR",
    ]

    public static func apiPeriod(for duration: String) -> String? {
        apiPeriods[duration.uppercased()]
    }

    /// The offer duration. Apple accepts three short values that a
    /// subscription period does not use, so this map is wider.
    public static let offerDurations: [String: String] = [
        "P3D": "THREE_DAYS", "P1W": "ONE_WEEK", "P2W": "TWO_WEEKS",
        "P1M": "ONE_MONTH", "P2M": "TWO_MONTHS", "P3M": "THREE_MONTHS",
        "P6M": "SIX_MONTHS", "P1Y": "ONE_YEAR",
    ]

    public static func offerDuration(for duration: String) -> String? {
        offerDurations[duration.uppercased()]
    }

    /// Apple accepts three grace periods and no other value. The nearest one
    /// wins, so a manifest never fails on a number that means the same thing.
    public static func gracePeriod(days: Int) -> String {
        let choices = [(3, "THREE_DAYS"), (16, "SIXTEEN_DAYS"), (28, "TWENTY_EIGHT_DAYS")]
        return choices.min { abs($0.0 - days) < abs($1.0 - days) }?.1 ?? "SIXTEEN_DAYS"
    }
}

/// Spec section 6.6.2. The app never rounds a duration.
public enum AdaptyPeriods {
    public static let map: [String: String] = [
        "P1W": "weekly", "P1M": "monthly", "P2M": "two_months", "P3M": "three_months",
        "P6M": "six_months", "P1Y": "annual",
    ]

    public static var supported: [String] { map.keys.sorted() }

    public static func period(for duration: String) -> String? {
        map[duration.uppercased()]
    }
}

public extension Manifest {
    /// The entitlement keys that each product names.
    var entitlementsByProduct: [String: [String]] {
        var result: [String: [String]] = [:]
        for purchase in purchases ?? [] where purchase.entitlements?.isEmpty == false {
            result[purchase.id] = purchase.entitlements
        }
        for group in subscriptions ?? [] {
            for plan in group.plans where plan.entitlements?.isEmpty == false {
                result[plan.id] = plan.entitlements
            }
        }
        return result
    }
}

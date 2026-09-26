import Foundation

/// What the stores show today that `store.yaml` may not say.
///
/// A field that `store.yaml` leaves alone keeps what the store holds, so that
/// is the value a copy between the stores has to take. The app keeps it beside
/// the file and not in it: the import and every store read put the text in the
/// store snapshot, and the import downloads the pictures under `Store Import/`.
public struct StoreCopySource: Sendable, Equatable {
    /// locale -> field -> the text the source store holds.
    public var text: [String: [ListingTextField: String]]
    /// locale -> device class -> the pictures the source store shows, as paths
    /// that `store.yaml` can name.
    public var screenshots: [String: [Manifest.DeviceClass: [String]]]
    /// The app icon the source store shows, as a path that `store.yaml` can
    /// name.
    public var icon: String?
    /// The product ids Google Play already holds, or nil while nobody has
    /// read Google Play. A copy to Google Play sets up only the products it
    /// does not hold, so a sale switched off in the Play Console stays off,
    /// and it sets up none before a read has said which ones those are.
    public var googleProducts: Set<String>?
    /// The base plan Google Play holds for each subscription, by product id.
    public var googleBasePlans: [String: String]

    public init(text: [String: [ListingTextField: String]] = [:],
                screenshots: [String: [Manifest.DeviceClass: [String]]] = [:],
                icon: String? = nil, googleProducts: Set<String>? = nil,
                googleBasePlans: [String: String] = [:]) {
        self.text = text
        self.screenshots = screenshots
        self.icon = icon
        self.googleProducts = googleProducts
        self.googleBasePlans = googleBasePlans
    }
}

/// What one copy wrote into `store.yaml`, and what it left alone and why.
public struct StoreCopyReport: Sendable, Equatable {
    public let source: Store
    public let target: Store
    /// One line per language or picture set that changed.
    public var copied: [String] = []
    /// One line per value the other store cannot take, with the reason.
    public var skipped: [String] = []
    /// What `store.yaml` holds once for both stores, so there is nothing to
    /// copy.
    public var shared: [String] = []
    /// What one store has and the other has no field for.
    public var noEquivalent: [String] = []

    public init(source: Store, target: Store) {
        self.source = source
        self.target = target
    }
}

public extension Manifest {
    /// Gives one store what the other already has, wherever the two stores
    /// take the same kind of value.
    ///
    /// An app that ships on one store first gets its second store later, and
    /// the second one starts empty: no screenshots, no icon, and its own words
    /// in the few fields where Google Play takes different text from the App
    /// Store. Most of the listing needs no copy at all, because `store.yaml`
    /// holds one name, one description and one catalog for both stores, and a
    /// value it holds already reaches both. So this fills what is missing:
    ///
    /// - A shared field that `store.yaml` leaves alone takes the source store's
    ///   own text, so the next send gives it to the other store as well.
    /// - The subtitle and the Google short description, and what is new and
    ///   the Google release notes, are one value each once the copy has run.
    ///   Text the other store cannot take whole is left alone and reported.
    ///   Nothing is ever shortened.
    /// - Each screenshot size takes the source store's pictures that the other
    ///   store accepts, checked by their pixels.
    /// - Google Play takes the App Store icon when it is a 512 by 512 PNG.
    /// - A product Google Play does not hold yet gets the two details only
    ///   Google asks for: a base plan id and the sale switch. See
    ///   `prepareGooglePlayCatalog`.
    ///
    /// It never clears a value because the source store has none.
    ///
    /// - Parameter imageSize: the pixel size of a picture, by the path that
    ///   `store.yaml` names it with. Nil for a file that cannot be read.
    @discardableResult
    mutating func copyStore(from source: Store, to target: Store,
                            live: StoreCopySource,
                            imageSize: (String) -> ImageAssetInfo?) -> StoreCopyReport {
        var report = StoreCopyReport(source: source, target: target)
        guard source != target else { return report }
        copyListingText(from: source, to: target, live: live.text, report: &report)
        copyScreenshots(from: source, to: target, live: live.screenshots,
                        imageSize: imageSize, report: &report)
        if source == .apple {
            copyIcon(live.icon, imageSize: imageSize, report: &report)
        }
        if target == .google, let held = live.googleProducts {
            let ready = prepareGooglePlayCatalog(onGooglePlay: held,
                                                 basePlans: live.googleBasePlans)
            if !ready.isEmpty {
                report.copied.append("Products · Google Play details for \(ready.joined(separator: ", "))")
            }
        }
        describeCatalog(from: source, to: target, onGooglePlay: live.googleProducts,
                        report: &report)
        report.noEquivalent = Self.noEquivalent(from: source)
        return report
    }

    /// What `store.yaml` says for one field of one language.
    ///
    /// Three answers, the same three the send reads: the text, an empty string
    /// for a field cleared on purpose, and nil where the file says nothing and
    /// the store keeps its own. A box emptied by typing holds an empty value,
    /// and the send treats that as nothing at all, so this does too.
    func copyText(locale code: String, field: ListingTextField) -> String? {
        guard let entry = listing?.locales[code] else { return nil }
        let managed: Managed<String>
        switch field {
        case .name:
            guard let name = entry.name, !name.isEmpty else { return nil }
            return name
        case .subtitle: managed = entry.subtitle
        case .description: managed = entry.description
        case .whatsNew: managed = entry.whatsNew
        case .keywords: managed = entry.keywords
        case .promotionalText: managed = entry.promotionalText
        case .supportURL: managed = entry.supportUrl
        case .marketingURL: managed = entry.marketingUrl
        case .privacyPolicyURL: managed = entry.privacyPolicyUrl
        case .privacyPolicyText: managed = entry.privacyPolicyText
        case .privacyChoicesURL: managed = entry.privacyChoicesUrl
        case .googleShortDescription: managed = entry.google?.shortDescription ?? .unmanaged
        case .googleWhatsNew: managed = entry.google?.whatsNew ?? .unmanaged
        case .googleVideo: managed = entry.google?.video ?? .unmanaged
        }
        switch managed {
        case .value(let text): return text.isEmpty ? nil : text
        case .clear: return ""
        case .unmanaged: return nil
        }
    }
}

// MARK: - The text

extension Manifest {
    private mutating func copyListingText(from source: Store, to target: Store,
                                          live: [String: [ListingTextField: String]],
                                          report: inout StoreCopyReport) {
        var codes = Set(live.keys)
        if let held = listing?.locales.keys { codes.formUnion(held) }
        var ordered = codes.sorted()
        // A file with no listing yet takes the first language written as its
        // default, so the one a store most likely leads with goes first.
        if listing == nil, let index = ordered.firstIndex(of: "en-US") {
            ordered.insert(ordered.remove(at: index), at: 0)
        }

        // One key that both stores read. A value in the file already reaches
        // both, so only its silence is filled.
        let sharedFields: [ListingTextField] = [.name, .description, .supportURL]
        // One text under two names. The App Store reads the shared key, and
        // Google Play reads its own box while that box is switched on.
        let pairs: [(apple: ListingTextField, google: ListingTextField)] = [
            (.subtitle, .googleShortDescription),
            (.whatsNew, .googleWhatsNew),
        ]

        for code in ordered {
            let held = live[code] ?? [:]
            var written: [String] = []

            for field in sharedFields {
                guard copyText(locale: code, field: field) == nil,
                      let text = held[field], !text.isEmpty else { continue }
                if let reason = Self.copyRefusal(text, field: field, target: target) {
                    report.skipped.append("\(code) · \(field.label): \(reason)")
                    continue
                }
                setListingText(text, locale: code, field: field)
                written.append(field.label)
            }

            for pair in pairs {
                let shared = copyText(locale: code, field: pair.apple)
                var own = copyText(locale: code, field: pair.google)
                // Google's release notes fall back to what is new whenever
                // their own box is empty, cleared or not. The short
                // description takes a cleared box as a clear.
                if pair.google == .googleWhatsNew, own?.isEmpty == true { own = nil }
                let switchedOn = hasGoogleOverride(locale: code, field: pair.google)

                if source == .apple {
                    // What the App Store shows once the next send has run.
                    let text = shared ?? held[pair.apple] ?? ""
                    guard !text.isEmpty else { continue }
                    if let reason = Self.copyRefusal(text, field: pair.google, target: target) {
                        report.skipped.append("\(code) · \(pair.google.label): \(reason)")
                        continue
                    }
                    let filling = shared == nil
                    let replacing = own != nil && own != text
                    if filling { setListingText(text, locale: code, field: pair.apple) }
                    if switchedOn { setGoogleOverride(false, locale: code, field: pair.google) }
                    if filling || replacing { written.append(pair.google.label) }
                } else {
                    // What Google Play shows once the next send has run.
                    let text = own ?? shared ?? held[pair.google] ?? ""
                    guard !text.isEmpty else { continue }
                    if let reason = Self.copyRefusal(text, field: pair.apple, target: target) {
                        report.skipped.append("\(code) · \(pair.apple.label): \(reason)")
                        continue
                    }
                    // Google Play goes on reading the same words, now from
                    // the shared key.
                    let filling = shared != text
                    if filling { setListingText(text, locale: code, field: pair.apple) }
                    if switchedOn { setGoogleOverride(false, locale: code, field: pair.google) }
                    if filling { written.append(pair.apple.label) }
                }
            }

            if !written.isEmpty {
                report.copied.append("\(code) · \(written.joined(separator: ", "))")
            }
        }
    }

    /// Why the other store cannot take this text whole, or nil when it can.
    ///
    /// The copy never shortens a text. A sentence cut at a character count is
    /// a sentence nobody wrote.
    private static func copyRefusal(_ text: String, field: ListingTextField,
                                    target: Store) -> String? {
        let limited: ListingField? = switch field {
        case .name: .name
        case .subtitle: .subtitle
        case .description: .description
        case .whatsNew, .googleWhatsNew: .whatsNew
        case .googleShortDescription: .shortDescription
        default: nil
        }
        guard let limited, let limit = BindingLimits.limit(for: limited, in: target),
              text.count > limit else { return nil }
        return "the text is \(text.count) characters, and \(copyName(target)) takes \(limit)."
    }
}

// MARK: - The pictures

extension Manifest {
    private mutating func copyScreenshots(from source: Store, to target: Store,
                                          live: [String: [DeviceClass: [String]]],
                                          imageSize: (String) -> ImageAssetInfo?,
                                          report: inout StoreCopyReport) {
        var codes = Set(live.keys)
        for groups in [media?.screenshots, storeScreenshots(source)] {
            if let held = groups?.keys { codes.formUnion(held) }
        }
        for code in codes.sorted() {
            for deviceClass in DeviceClass.allCases {
                // The pictures `store.yaml` sends the source store, or what that
                // store shows when the file sends it nothing for this size.
                let held = mediaPaths(locale: code, deviceClass: deviceClass, store: source)
                let pictures = held.isEmpty ? (live[code]?[deviceClass] ?? []) : held
                guard !pictures.isEmpty else { continue }
                let place = "\(code) · \(deviceClass.label)"

                let fitting = pictures.filter { path in
                    guard let info = imageSize(path) else { return false }
                    let stores = try? AssetInspector.compatibleStores(
                        for: info, deviceClass: deviceClass, selectedStores: [target])
                    return stores?.contains(target) == true
                }
                guard !fitting.isEmpty else {
                    report.skipped.append("\(place): " + Self.screenshotRefusal(
                        deviceClass, count: pictures.count, target: target))
                    continue
                }
                let chosen = target == .google
                    ? Self.oneGooglePlaySet(fitting, imageSize: imageSize) : fitting
                guard chosen != mediaPaths(locale: code, deviceClass: deviceClass,
                                           store: target) else { continue }
                setStoreScreenshots(chosen, locale: code, deviceClass: deviceClass,
                                    store: target)
                report.copied.append(
                    "\(place) · \(chosen.count) screenshot\(chosen.count == 1 ? "" : "s")")
            }
        }
    }

    /// The one screen size Google Play gets for one device.
    ///
    /// The App Store keeps a set per screen size, so its phone pictures are
    /// often the same screens twice, at 6.9 inches and at 5.5. Google Play keeps
    /// one set per device and shows 8 at most, so the copy takes the size with
    /// the most pictures Google accepts, in the order the source shows them.
    private static func oneGooglePlaySet(_ paths: [String],
                                         imageSize: (String) -> ImageAssetInfo?) -> [String] {
        var sizes: [String: [String]] = [:]
        var areas: [String: Int] = [:]
        var order: [String] = []
        for path in paths {
            guard let info = imageSize(path) else { continue }
            let key = "\(min(info.width, info.height))x\(max(info.width, info.height))"
            if sizes[key] == nil { order.append(key) }
            sizes[key, default: []].append(path)
            areas[key] = info.width * info.height
        }
        let best = order.max { left, right in
            ((sizes[left]?.count ?? 0), (areas[left] ?? 0))
                < ((sizes[right]?.count ?? 0), (areas[right] ?? 0))
        }
        return Array((best.flatMap { sizes[$0] } ?? []).prefix(8))
    }

    /// Why none of one size's pictures fits the other store.
    private static func screenshotRefusal(_ deviceClass: DeviceClass, count: Int,
                                          target: Store) -> String {
        let pictures = count == 1 ? "the picture" : "the \(count) pictures"
        switch (target, deviceClass) {
        case (.google, .desktop), (.google, .vision):
            return "Google Play has no screenshots of this size."
        case (.google, .watch):
            return "Google Play takes a square watch picture of 384 pixels or more, and none of \(pictures) is one."
        case (.google, _):
            return "Google Play takes 320 to 3840 pixels, at most twice as long as wide, and none of \(pictures) fits."
        case (.apple, .tablet7):
            return "The App Store has no small tablet size."
        case (.apple, _):
            return "The App Store takes its own screen sizes only, and none of \(pictures) is one of them."
        }
    }

    /// The App Store icon, as the Google Play icon.
    ///
    /// Apple keeps one icon for the whole app and the import downloads it at
    /// 512 by 512, which is the size Google asks for. Google Play has no way
    /// back: the App Store reads its icon out of the build.
    private mutating func copyIcon(_ path: String?, imageSize: (String) -> ImageAssetInfo?,
                                   report: inout StoreCopyReport) {
        guard let path, !path.isEmpty else { return }
        guard let info = imageSize(path) else {
            report.skipped.append("App icon: the App Store icon could not be read.")
            return
        }
        guard path.lowercased().hasSuffix(".png"), info.width == 512, info.height == 512 else {
            report.skipped.append("App icon: the App Store icon is \(info.width) × \(info.height), and Google Play takes a 512 × 512 PNG.")
            return
        }
        guard media?.icon != path else { return }
        var media = self.media ?? Media()
        media.icon = path
        self.media = media
        report.copied.append("App icon")
    }
}

// MARK: - The catalog, and what has no equivalent

extension Manifest {
    /// The products need no copy: `store.yaml` holds one catalog, and the next
    /// send creates in each store what that store does not have. The report
    /// says so, and says what the other store will still ask for.
    private func describeCatalog(from source: Store, to target: Store,
                                 onGooglePlay held: Set<String>?,
                                 report: inout StoreCopyReport) {
        let purchases = self.purchases ?? []
        let plans = (subscriptions ?? []).flatMap(\.plans)
        let count = purchases.count + plans.count
        guard count > 0 else { return }
        report.shared.append("Products: store.yaml holds one catalog of \(count) product\(count == 1 ? "" : "s"), so \(Self.copyName(target)) gets the same ones and the same prices.")
        if target == .google, let held {
            report.skipped += googlePlayCatalogGaps(onGooglePlay: held).warnings
        } else if target == .google {
            report.skipped.append("Products: Google Play has not been read yet, so the copy left its product details alone. Read the stores, then copy again.")
        }
        if source == .google, target == .apple, !purchases.isEmpty {
            report.skipped.append("Products: Google Play does not say which purchases are consumable, and Apple cannot change the type of a purchase later. Check each type on Monetization before you send.")
        }
    }

    /// What one store has that the other has no field for. The same list
    /// every time, so the developer does not look for them after a copy.
    private static func noEquivalent(from source: Store) -> [String] {
        switch source {
        case .apple:
            [
                "Keywords, promotional text, the marketing URL, the privacy policy text and the privacy choices URL: Google Play has no field for them.",
                "App previews: Google Play takes a YouTube link and not a video file.",
                "The version number: each store keeps its own.",
            ]
        case .google:
            [
                "The YouTube video: the App Store takes a preview video file and not a link.",
                "The feature graphic: the App Store has no such image.",
                "The app icon: the App Store reads it from the build.",
                "The version number: each store keeps its own.",
            ]
        }
    }

    /// The store's name in a sentence. The app's own `storeName` lives beside
    /// the views, and this file sits below them.
    private static func copyName(_ store: Store) -> String {
        switch store {
        case .apple: "the App Store"
        case .google: "Google Play"
        }
    }
}

// MARK: - The Google Play side of an App Store catalog

public extension Manifest {
    /// What Google Play still lacks before the next send can create this
    /// catalog there.
    struct GooglePlayCatalogGaps: Sendable, Equatable {
        /// The products and plans whose Google Play details are not set yet.
        public var unset: [String] = []
        /// The products with no price. Google Play sells nothing without one.
        public var unpriced: [String] = []
        /// The product ids Google Play refuses.
        public var refusedIds: [String] = []

        public init() {}

        public var isEmpty: Bool { unset.isEmpty && unpriced.isEmpty && refusedIds.isEmpty }

        /// The two faults a button cannot fix, as the lines a screen shows.
        public var warnings: [String] {
            var lines: [String] = []
            if !unpriced.isEmpty {
                lines.append("Products with no price: \(unpriced.joined(separator: ", ")). Google Play needs a price to sell a product. Set it on Monetization.")
            }
            if !refusedIds.isEmpty {
                lines.append("Product ids Google Play refuses: \(refusedIds.joined(separator: ", ")). Google takes lowercase letters, digits, periods and underscores, and a letter or digit first.")
            }
            return lines
        }
    }

    /// What Google Play still lacks, for the products it does not hold.
    ///
    /// A catalog that came from the App Store is one list in `store.yaml`, and
    /// Google Play reads the same list, so the products need no copy. Two
    /// details are Google's alone and the App Store never had them: the base
    /// plan every Google subscription sells through, and the sale switch.
    /// Google makes a new product and a new base plan as a draft, and a draft
    /// sells to nobody.
    ///
    /// - Parameter held: the product ids Google Play already holds. Their
    ///   Google details are Google's answer already, and this leaves them out.
    func googlePlayCatalogGaps(onGooglePlay held: Set<String> = []) -> GooglePlayCatalogGaps {
        var gaps = GooglePlayCatalogGaps()
        for purchase in purchases ?? [] where !purchase.id.isEmpty && !held.contains(purchase.id) {
            if purchase.active == nil { gaps.unset.append(purchase.id) }
            if purchase.price == nil { gaps.unpriced.append(purchase.id) }
            if !Self.googleAcceptsProductId(purchase.id) { gaps.refusedIds.append(purchase.id) }
        }
        for plan in (subscriptions ?? []).flatMap(\.plans)
        where !plan.id.isEmpty && !held.contains(plan.id) {
            if plan.active == nil || plan.basePlanId?.isEmpty != false {
                gaps.unset.append(plan.id)
            }
            if plan.price == nil { gaps.unpriced.append(plan.id) }
            if !Self.googleAcceptsProductId(plan.id) { gaps.refusedIds.append(plan.id) }
        }
        return gaps
    }

    /// Gives every product Google Play does not hold yet the two details only
    /// Google asks for, and answers the ids it set up.
    ///
    /// A plan with no base plan id takes one named after its period, which is
    /// what the Play Console suggests: `monthly`, `yearly`. A subscription
    /// Google already holds takes the base plan Google has, so the next send
    /// does not open a second one beside it. The sale switch goes on for the
    /// products Google does not hold, and only where the file says nothing: a
    /// product Google holds keeps whatever the Play Console says.
    ///
    /// The id, the name, the price and the store text are shared with the App
    /// Store already, and this touches none of them.
    @discardableResult
    mutating func prepareGooglePlayCatalog(onGooglePlay held: Set<String> = [],
                                           basePlans: [String: String] = [:]) -> [String] {
        var ready: [String] = []
        for index in (purchases ?? []).indices {
            let id = purchases![index].id
            guard !id.isEmpty, !held.contains(id), purchases![index].active == nil else {
                continue
            }
            purchases![index].active = true
            ready.append(id)
        }
        for group in (subscriptions ?? []).indices {
            for index in subscriptions![group].plans.indices {
                var plan = subscriptions![group].plans[index]
                guard !plan.id.isEmpty else { continue }
                var changed = false
                if plan.basePlanId?.isEmpty != false {
                    if let live = basePlans[plan.id], !live.isEmpty {
                        plan.basePlanId = live
                        changed = true
                    } else if !held.contains(plan.id) {
                        plan.basePlanId = Self.googleBasePlanId(for: plan.duration)
                        changed = true
                    }
                }
                if !held.contains(plan.id), plan.active == nil {
                    plan.active = true
                    changed = true
                }
                guard changed else { continue }
                subscriptions![group].plans[index] = plan
                ready.append(plan.id)
            }
        }
        return ready
    }

    /// Whether Google Play takes this product id: a lowercase letter or a
    /// digit first, then lowercase letters, digits, periods and underscores.
    /// The App Store takes capitals and Google does not, so an id both stores
    /// share has to fit the stricter rule.
    static func googleAcceptsProductId(_ id: String) -> Bool {
        let leading = "abcdefghijklmnopqrstuvwxyz0123456789"
        guard let first = id.first, leading.contains(first) else { return false }
        return id.allSatisfy { (leading + "._").contains($0) }
    }

    /// The base plan id the Play Console suggests for a period. Google takes
    /// lowercase letters, digits and hyphens here, and every name below fits.
    static func googleBasePlanId(for duration: String) -> String {
        switch duration {
        case "P1W": "weekly"
        case "P1M": "monthly"
        case "P2M": "every-two-months"
        case "P3M": "quarterly"
        case "P6M": "every-six-months"
        case "P1Y": "yearly"
        default: "default"
        }
    }
}

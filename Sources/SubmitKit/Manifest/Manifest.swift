import Foundation

/// The Swift shape of `store.yaml`. Spec section 5.2 holds the example, and
/// this file follows it key for key.
///
/// Every tab from 1 to 6 edits one block of this struct.
public struct Manifest: Codable, Sendable, Equatable {
    public var version: Int = 1
    public var apps: Apps = Apps()
    public var monetization: Monetization?
    public var release: Release?
    public var listing: Listing?
    public var media: Media?
    public var pricing: Pricing?
    public var purchases: [Purchase]?
    public var subscriptions: [SubscriptionGroup]?
    public var entitlements: [Entitlement]?
    public var offerings: [Offering]?
    public var review: Review?
    /// The App Store resources that sell the app rather than ship it: the
    /// custom product pages, the experiments, the in-app events, and the
    /// small single-value resources next to them.
    public var marketing: Marketing?

    public init() {}
}

// MARK: - apps (tab 1)

extension Manifest {
    public struct Apps: Codable, Sendable, Equatable {
        public var apple: Apple?
        public var google: Google?

        public init(apple: Apple? = nil, google: Google? = nil) {
            self.apple = apple
            self.google = google
        }

        public struct Apple: Codable, Sendable, Equatable {
            public var appId: String
            public var platforms: [Platform]
            public var bundleId: String
        }

        public struct Google: Codable, Sendable, Equatable {
            public var packageName: String
        }
    }

    public enum Platform: String, Codable, Sendable, CaseIterable {
        case ios = "IOS"
        case macOS = "MAC_OS"
        case tvOS = "TV_OS"
        case visionOS = "VISION_OS"
    }
}

// MARK: - monetization (tab 5)

extension Manifest {
    public struct Monetization: Codable, Sendable, Equatable {
        public var provider: Provider = .none
        public var revenuecat: RevenueCat?
        public var adapty: Adapty?

        public init(provider: Provider = .none, revenuecat: RevenueCat? = nil,
                    adapty: Adapty? = nil) {
            self.provider = provider
            self.revenuecat = revenuecat
            self.adapty = adapty
        }

        public struct RevenueCat: Codable, Sendable, Equatable {
            public var projectId: String
            public var appIds: AppIds

            public init(projectId: String, appIds: AppIds = AppIds()) {
                self.projectId = projectId
                self.appIds = appIds
            }

            public struct AppIds: Codable, Sendable, Equatable {
                public var appStore: String?
                public var macAppStore: String?
                public var playStore: String?

                public init(appStore: String? = nil, macAppStore: String? = nil,
                            playStore: String? = nil) {
                    self.appStore = appStore
                    self.macAppStore = macAppStore
                    self.playStore = playStore
                }

                enum CodingKeys: String, CodingKey {
                    case appStore = "app_store"
                    case macAppStore = "mac_app_store"
                    case playStore = "play_store"
                }
            }
        }

        public struct Adapty: Codable, Sendable, Equatable {
            public var appId: String
            public init(appId: String) { self.appId = appId }
        }
    }

    /// Spec section 8, rule 2. One provider per manifest, never two.
    public enum Provider: String, Codable, Sendable, CaseIterable {
        case none
        case revenuecat
        case adapty
    }
}

// MARK: - release (tab 2)

extension Manifest {
    public struct Release: Codable, Sendable, Equatable {
        public var versionName: String?
        public var build: Build?
        public var apple: AppleRelease?
        public var google: GoogleRelease?

        public init(versionName: String? = nil, build: Build? = nil,
                    apple: AppleRelease? = nil, google: GoogleRelease? = nil) {
            self.versionName = versionName
            self.build = build
            self.apple = apple
            self.google = google
        }

        public struct Build: Codable, Sendable, Equatable {
            public var ios: String?
            public var macos: String?
            /// The App Bundle. Google prefers it, and the Play Console needs it
            /// for a new app.
            public var android: String?
            /// A plain APK. Google still accepts one for an existing app, and
            /// an expansion file needs one. The manifest may name both, and
            /// then the run uploads both into the same edit.
            public var androidApk: String?

            public init(ios: String? = nil, macos: String? = nil, android: String? = nil,
                        androidApk: String? = nil) {
                self.ios = ios
                self.macos = macos
                self.android = android
                self.androidApk = androidApk
            }
        }

        public struct AppleRelease: Codable, Sendable, Equatable {
            public var releaseType: ReleaseType?
            public var phasedRelease: Bool?
        }

        public struct GoogleRelease: Codable, Sendable, Equatable {
            /// The track that the release button releases. It is one track,
            /// because a release is one irreversible call. Spec section 7.9.
            public var track: String?
            /// Every track that an apply writes. One edit carries them all, so
            /// a build reaches `internal` and `production` in one commit. The
            /// primary `track` must appear here when both keys exist.
            public var tracks: [String]?
            /// Read at release time, never at apply time. An apply always
            /// writes `draft`. Spec section 7.4.
            public var status: String?
            public var userFraction: Double?
            public var inAppUpdatePriority: Int?
            /// The staged rollout by country. An empty list means every
            /// country, and then Google receives no `countryTargeting`.
            public var countries: [String]?
            /// True keeps the release available outside `countries`.
            public var includeRestOfWorld: Bool?
            /// The ProGuard or R8 mapping file. Google needs it to read a
            /// stack trace.
            public var mappingFile: String?
            /// The native debug symbols archive, for the NDK crash reports.
            public var nativeDebugSymbols: String?
            /// The APK expansion files. Google accepts them for an APK only,
            /// never for an App Bundle.
            public var expansionFileMain: String?
            public var expansionFilePatch: String?
            /// A privately hosted APK. Google Play organizations only.
            public var externalApk: ExternalApk?
            /// A device tier configuration file, as JSON. Google assigns the
            /// id, so the app creates a new configuration when the file
            /// content changes and never before.
            public var deviceTierConfig: String?

            public init(track: String? = nil, tracks: [String]? = nil, status: String? = nil,
                        userFraction: Double? = nil, inAppUpdatePriority: Int? = nil,
                        countries: [String]? = nil, includeRestOfWorld: Bool? = nil,
                        mappingFile: String? = nil, nativeDebugSymbols: String? = nil,
                        expansionFileMain: String? = nil, expansionFilePatch: String? = nil,
                        externalApk: ExternalApk? = nil, deviceTierConfig: String? = nil) {
                self.track = track
                self.tracks = tracks
                self.status = status
                self.userFraction = userFraction
                self.inAppUpdatePriority = inAppUpdatePriority
                self.countries = countries
                self.includeRestOfWorld = includeRestOfWorld
                self.mappingFile = mappingFile
                self.nativeDebugSymbols = nativeDebugSymbols
                self.expansionFileMain = expansionFileMain
                self.expansionFilePatch = expansionFilePatch
                self.externalApk = externalApk
                self.deviceTierConfig = deviceTierConfig
            }
        }

        /// The metadata of an APK that the developer hosts, not Google.
        ///
        /// The app computes the size and the two digests from the file. Every
        /// other value comes from here, because the reader parses an App
        /// Bundle and not the binary manifest of an APK.
        ///
        /// `// ponytail: the developer names six fields instead of the app
        /// // shipping an AXML parser and a certificate reader. Add the parser
        /// // when a user actually publishes a private app this way.`
        public struct ExternalApk: Codable, Sendable, Equatable {
            public var url: String
            public var applicationLabel: String
            public var versionCode: Int
            public var versionName: String
            public var minimumSdk: Int
            public var certificateBase64s: [String]
            public var maximumSdk: Int?
            public var nativeCodes: [String]?
            public var usesFeatures: [String]?
            public var usesPermissions: [String]?
            public var iconBase64: String?

            public init(url: String, applicationLabel: String, versionCode: Int,
                        versionName: String, minimumSdk: Int, certificateBase64s: [String],
                        maximumSdk: Int? = nil, nativeCodes: [String]? = nil,
                        usesFeatures: [String]? = nil, usesPermissions: [String]? = nil,
                        iconBase64: String? = nil) {
                self.url = url
                self.applicationLabel = applicationLabel
                self.versionCode = versionCode
                self.versionName = versionName
                self.minimumSdk = minimumSdk
                self.certificateBase64s = certificateBase64s
                self.maximumSdk = maximumSdk
                self.nativeCodes = nativeCodes
                self.usesFeatures = usesFeatures
                self.usesPermissions = usesPermissions
                self.iconBase64 = iconBase64
            }
        }

        public enum ReleaseType: String, Codable, Sendable, CaseIterable {
            case manual = "MANUAL"
            case afterApproval = "AFTER_APPROVAL"
            case scheduled = "SCHEDULED"
        }
    }
}

// MARK: - the Google tracks

public extension Manifest {
    /// Every track that an apply writes. It is never empty.
    ///
    /// `// ponytail: one definition. Nine call sites held their own
    /// // `?? "production"`, and the tenth would have drifted.`
    var googleTracks: [String] {
        let list = (release?.google?.tracks ?? []).filter { !$0.isEmpty }
        guard list.isEmpty else { return list }
        return [googlePrimaryTrack]
    }

    /// The track that the release button releases, and the track that the
    /// status row reads.
    var googlePrimaryTrack: String {
        if let track = release?.google?.track, !track.isEmpty { return track }
        return (release?.google?.tracks ?? []).first { !$0.isEmpty } ?? "production"
    }

    /// The `countryTargeting` body of a release, or nil for every country.
    var googleCountryTargeting: [String: Any]? {
        let countries = (release?.google?.countries ?? []).filter { !$0.isEmpty }
        guard !countries.isEmpty else { return nil }
        return ["countries": countries,
                "includeRestOfWorld": release?.google?.includeRestOfWorld ?? false]
    }
}

// MARK: - listing (tab 3)

extension Manifest {
    public struct Listing: Codable, Sendable, Equatable {
        public var defaultLocale: String
        public var locales: [String: Locale]

        public init(defaultLocale: String, locales: [String: Locale]) {
            self.defaultLocale = defaultLocale
            self.locales = locales
        }

        /// One language of the store listing.
        ///
        /// The clearable fields use `Managed`. A name is not clearable,
        /// because no store accepts an app with no name.
        public struct Locale: Codable, Sendable, Equatable {
            public var name: String?
            public var subtitle: Managed<String> = .unmanaged
            public var description: Managed<String> = .unmanaged
            public var whatsNew: Managed<String> = .unmanaged
            public var keywords: Managed<String> = .unmanaged          // Apple only
            public var promotionalText: Managed<String> = .unmanaged   // Apple only
            public var supportUrl: Managed<String> = .unmanaged
            public var marketingUrl: Managed<String> = .unmanaged      // Apple only
            public var privacyPolicyUrl: Managed<String> = .unmanaged
            public var google: GoogleOverride?

            public init(name: String? = nil) { self.name = name }

            public struct GoogleOverride: Codable, Sendable, Equatable {
                public var shortDescription: Managed<String> = .unmanaged
                public var video: Managed<String> = .unmanaged
                public var whatsNew: Managed<String> = .unmanaged

                public init() {}
            }
        }
    }
}

// MARK: - media (tab 4)

extension Manifest {
    public struct Media: Codable, Sendable, Equatable {
        /// locale -> device class -> file globs
        public var screenshots: [String: [String: [String]]]?
        /// Apple only. Google takes a YouTube URL on the listing. Spec 6.3.
        public var previews: [String: [String: [String]]]?
        public var icon: String?            // Google only
        public var featureGraphic: String?  // Google only

        public init(screenshots: [String: [String: [String]]]? = nil,
                    previews: [String: [String: [String]]]? = nil,
                    icon: String? = nil, featureGraphic: String? = nil) {
            self.screenshots = screenshots
            self.previews = previews
            self.icon = icon
            self.featureGraphic = featureGraphic
        }
    }

    /// Spec 6.3. The pixel dimensions pick the bucket, never the folder name.
    public enum DeviceClass: String, Codable, Sendable, CaseIterable {
        case phone, tablet7, tablet10, desktop, watch, tv, vision
    }
}

// MARK: - pricing and purchases (tab 5)

extension Manifest {
    public struct Pricing: Codable, Sendable, Equatable {
        public var base: Price
        public var autoConvertOtherTerritories: Bool?

        public init(base: Price, autoConvertOtherTerritories: Bool? = nil) {
            self.base = base
            self.autoConvertOtherTerritories = autoConvertOtherTerritories
        }
    }

    public struct Purchase: Codable, Sendable, Equatable {
        public var id: String
        public var kind: Kind
        public var name: String?
        public var price: Price?
        public var reviewNote: String?
        public var entitlements: [String]?
        public var locales: [String: ProductLocale]?
        /// False deactivates the Google purchase option. Google keeps the
        /// product and stops the sale. Apple has no equivalent switch.
        public var active: Bool?
        /// The tax treatment. Google writes it on the product; Apple reads
        /// its own category from App Store Connect.
        public var tax: Tax?
        /// The discounts on this product.
        public var offers: [Offer]?

        public init(id: String, kind: Kind, name: String? = nil, price: Price? = nil,
                    reviewNote: String? = nil, entitlements: [String]? = nil,
                    locales: [String: ProductLocale]? = nil, active: Bool? = nil,
                    tax: Tax? = nil, offers: [Offer]? = nil) {
            self.id = id
            self.kind = kind
            self.name = name
            self.price = price
            self.reviewNote = reviewNote
            self.entitlements = entitlements
            self.locales = locales
            self.active = active
            self.tax = tax
            self.offers = offers
        }

        public enum Kind: String, Codable, Sendable, CaseIterable {
            case consumable
            case nonConsumable = "non_consumable"
            case nonRenewing = "non_renewing"
        }
    }

    public struct SubscriptionGroup: Codable, Sendable, Equatable {
        public var groupId: String
        public var groupName: String?
        public var plans: [Plan]
        /// The billing grace period, in days. Apple accepts 3, 16, or 28 at
        /// the app level. Google sets it on the base plan.
        public var gracePeriodDays: Int?
        /// The group name that the customer reads, per locale. Apple only.
        public var locales: [String: ProductLocale]?

        public init(groupId: String, groupName: String? = nil, plans: [Plan] = [],
                    gracePeriodDays: Int? = nil,
                    locales: [String: ProductLocale]? = nil) {
            self.groupId = groupId
            self.groupName = groupName
            self.plans = plans
            self.gracePeriodDays = gracePeriodDays
            self.locales = locales
        }

        public struct Plan: Codable, Sendable, Equatable {
            public var id: String
            /// ISO 8601, for example `P1M`. Spec 6.6.2 holds the Adapty map.
            public var duration: String
            public var basePlanId: String?   // Google needs it. Apple ignores it.
            public var price: Price?
            public var entitlements: [String]?
            public var packageKey: String?   // RevenueCat only
            public var locales: [String: ProductLocale]?
            /// False deactivates the Google base plan and stops new sales.
            /// An existing subscriber keeps the plan.
            public var active: Bool?
            public var tax: Tax?
            /// The free trial and the introductory price.
            public var offers: [Offer]?
            /// True moves the existing subscribers to the new price. It
            /// changes what a real customer pays, so the validator warns and
            /// the default is false.
            public var migrateExistingSubscribers: Bool?

            public init(id: String, duration: String, basePlanId: String? = nil,
                        price: Price? = nil, entitlements: [String]? = nil,
                        packageKey: String? = nil,
                        locales: [String: ProductLocale]? = nil, active: Bool? = nil,
                        tax: Tax? = nil, offers: [Offer]? = nil,
                        migrateExistingSubscribers: Bool? = nil) {
                self.id = id
                self.duration = duration
                self.basePlanId = basePlanId
                self.price = price
                self.entitlements = entitlements
                self.packageKey = packageKey
                self.locales = locales
                self.active = active
                self.tax = tax
                self.offers = offers
                self.migrateExistingSubscribers = migrateExistingSubscribers
            }
        }
    }

    /// One discount on a product or on a subscription plan.
    ///
    /// Both stores sell the same three shapes, and each store names them
    /// differently. Spec section 6.5 holds the map.
    public struct Offer: Codable, Sendable, Equatable {
        public var id: String
        public var kind: Kind
        /// The offer duration, ISO 8601. A free trial needs it.
        public var duration: String?
        /// The price of an introductory offer. A free trial has none.
        public var price: Price?
        /// How many billing periods the offer runs. Apple calls it the
        /// number of periods; Google calls it the recurrence count.
        public var periods: Int?
        /// The regions or territories. An empty list means every region.
        public var regions: [String]?
        public var eligibility: Eligibility?

        public init(id: String, kind: Kind, duration: String? = nil, price: Price? = nil,
                    periods: Int? = nil, regions: [String]? = nil,
                    eligibility: Eligibility? = nil) {
            self.id = id
            self.kind = kind
            self.duration = duration
            self.price = price
            self.periods = periods
            self.regions = regions
            self.eligibility = eligibility
        }

        public enum Kind: String, Codable, Sendable, CaseIterable {
            case freeTrial = "free_trial"
            case introPrice = "intro_price"
            /// A code that the developer hands out. Apple calls it an offer
            /// code; Google calls it a promotion.
            case offerCode = "offer_code"
        }

        public enum Eligibility: String, Codable, Sendable, CaseIterable {
            case new
            case existing
            case winBack = "win_back"
        }
    }

    /// The tax treatment of one product.
    public struct Tax: Codable, Sendable, Equatable {
        /// The Google tax category, for example `TAX_CATEGORY_UNSPECIFIED`
        /// or `TAX_CATEGORY_EBOOK`.
        public var category: String?
        /// The EU withdrawal right, for example
        /// `WITHDRAWAL_RIGHT_DIGITAL_CONTENT`.
        public var withdrawalRight: String?
        /// True marks the product as sold by the developer in the EEA.
        public var eeaWithdrawalRight: Bool?

        public init(category: String? = nil, withdrawalRight: String? = nil,
                    eeaWithdrawalRight: Bool? = nil) {
            self.category = category
            self.withdrawalRight = withdrawalRight
            self.eeaWithdrawalRight = eeaWithdrawalRight
        }
    }

    public struct ProductLocale: Codable, Sendable, Equatable {
        public var name: String?
        public var description: String?

        public init(name: String? = nil, description: String? = nil) {
            self.name = name
            self.description = description
        }
    }

    public struct Entitlement: Codable, Sendable, Equatable {
        public var key: String
        public var name: String?

        public init(key: String, name: String? = nil) {
            self.key = key
            self.name = name
        }
    }

    public struct Offering: Codable, Sendable, Equatable {
        public var key: String
        public var name: String?
        public var isCurrent: Bool?
        public var products: [String]?

        public init(key: String, name: String? = nil, isCurrent: Bool? = nil,
                    products: [String]? = nil) {
            self.key = key
            self.name = name
            self.isCurrent = isCurrent
            self.products = products
        }
    }
}

// MARK: - marketing (App Store only)

extension Manifest {
    /// The App Store resources that shape how the store sells the app.
    ///
    /// Google offers no equivalent for any of these, so every block here
    /// reaches one store. A missing block writes nothing.
    public struct Marketing: Codable, Sendable, Equatable {
        public var customProductPages: [CustomProductPage]?
        public var experiments: [Experiment]?
        public var events: [AppEvent]?
        public var eula: EULA?
        /// A GeoJSON file for a routing app. Apple reserves and uploads it
        /// the same way as a screenshot.
        public var routingCoverage: String?
        public var nomination: Nomination?
        public var accessibility: Accessibility?
        public var appClip: AppClip?

        public init() {}

        /// One alternative product page. Apple allows up to 35.
        public struct CustomProductPage: Codable, Sendable, Equatable {
            public var key: String
            public var name: String
            public var visible: Bool?
            /// The promotional text and the screenshots differ per page. The
            /// screenshots reuse the media block by locale and device class.
            public var locales: [String: PageLocale]?

            public init(key: String, name: String, visible: Bool? = nil,
                        locales: [String: PageLocale]? = nil) {
                self.key = key
                self.name = name
                self.visible = visible
                self.locales = locales
            }

            public struct PageLocale: Codable, Sendable, Equatable {
                public var promotionalText: String?
                public init(promotionalText: String? = nil) {
                    self.promotionalText = promotionalText
                }
            }
        }

        /// One product page experiment. Apple runs it against the live page.
        public struct Experiment: Codable, Sendable, Equatable {
            public var key: String
            public var name: String
            /// The share of the traffic that the treatments take, 0 to 100.
            public var trafficProportion: Int?
            public var platform: Platform?
            public var treatments: [Treatment]

            public init(key: String, name: String, trafficProportion: Int? = nil,
                        platform: Platform? = nil, treatments: [Treatment] = []) {
                self.key = key
                self.name = name
                self.trafficProportion = trafficProportion
                self.platform = platform
                self.treatments = treatments
            }

            public struct Treatment: Codable, Sendable, Equatable {
                public var key: String
                public var name: String
                public init(key: String, name: String) {
                    self.key = key
                    self.name = name
                }
            }
        }

        /// One in-app event.
        public struct AppEvent: Codable, Sendable, Equatable {
            public var key: String
            /// `BADGE_LIVE_EVENT`, `BADGE_PREMIERE`, and the rest.
            public var badge: String?
            public var priority: String?
            public var purpose: String?
            public var locales: [String: EventLocale]?

            public init(key: String, badge: String? = nil, priority: String? = nil,
                        purpose: String? = nil, locales: [String: EventLocale]? = nil) {
                self.key = key
                self.badge = badge
                self.priority = priority
                self.purpose = purpose
                self.locales = locales
            }

            public struct EventLocale: Codable, Sendable, Equatable {
                public var name: String?
                public var shortDescription: String?
                public var longDescription: String?
                public init(name: String? = nil, shortDescription: String? = nil,
                            longDescription: String? = nil) {
                    self.name = name
                    self.shortDescription = shortDescription
                    self.longDescription = longDescription
                }
            }
        }

        /// A custom licence agreement. Apple uses its own when this is absent.
        public struct EULA: Codable, Sendable, Equatable {
            public var text: String
            /// The territories that receive it. Empty means every territory.
            public var territories: [String]?

            public init(text: String, territories: [String]? = nil) {
                self.text = text
                self.territories = territories
            }
        }

        /// A request to the App Store editorial team.
        public struct Nomination: Codable, Sendable, Equatable {
            public var name: String
            /// `APP_LAUNCH`, `APP_ENHANCEMENTS`, `IN_APP_EVENT`, and the rest.
            public var type: String
            public var description: String?
            public var publishStartDate: String?
            public var publishEndDate: String?

            public init(name: String, type: String, description: String? = nil,
                        publishStartDate: String? = nil, publishEndDate: String? = nil) {
                self.name = name
                self.type = type
                self.description = description
                self.publishStartDate = publishStartDate
                self.publishEndDate = publishEndDate
            }
        }

        /// The accessibility nutrition label.
        public struct Accessibility: Codable, Sendable, Equatable {
            /// The supported features, for example `VOICE_OVER`,
            /// `LARGER_TEXT`, `SUFFICIENT_CONTRAST`.
            public var supports: [String]
            public init(supports: [String] = []) { self.supports = supports }
        }

        /// The default App Clip experience.
        public struct AppClip: Codable, Sendable, Equatable {
            /// `OPEN`, `VIEW`, `PLAY`.
            public var action: String?
            public var locales: [String: ClipLocale]?

            public init(action: String? = nil, locales: [String: ClipLocale]? = nil) {
                self.action = action
                self.locales = locales
            }

            public struct ClipLocale: Codable, Sendable, Equatable {
                public var subtitle: String?
                public var title: String?
                public init(subtitle: String? = nil, title: String? = nil) {
                    self.subtitle = subtitle
                    self.title = title
                }
            }
        }
    }
}

// MARK: - review (tab 6)

extension Manifest {
    /// The demo account user name and password are **not** here. They live in
    /// the Keychain. A manifest sits in a repository. Spec section 9.5.
    public struct Review: Codable, Sendable, Equatable {
        public var contactFirstName: String?
        public var contactLastName: String?
        public var contactEmail: String?
        public var contactPhone: String?
        public var demoAccountRequired: Bool?
        public var notes: String?
        public var applePrimaryCategory: String?
        public var appleSecondaryCategory: String?
        public var googleCategory: String?
        public var ageRatingAnswers: [String: Bool]?
        public var dataSafetyAnswers: [String: Bool]?
        public var usesNonExemptEncryption: Bool?

        public init(contactFirstName: String? = nil, contactLastName: String? = nil,
                    contactEmail: String? = nil, contactPhone: String? = nil,
                    demoAccountRequired: Bool? = nil, notes: String? = nil,
                    applePrimaryCategory: String? = nil,
                    appleSecondaryCategory: String? = nil,
                    googleCategory: String? = nil,
                    ageRatingAnswers: [String: Bool]? = nil,
                    dataSafetyAnswers: [String: Bool]? = nil,
                    usesNonExemptEncryption: Bool? = nil) {
            self.contactFirstName = contactFirstName
            self.contactLastName = contactLastName
            self.contactEmail = contactEmail
            self.contactPhone = contactPhone
            self.demoAccountRequired = demoAccountRequired
            self.notes = notes
            self.applePrimaryCategory = applePrimaryCategory
            self.appleSecondaryCategory = appleSecondaryCategory
            self.googleCategory = googleCategory
            self.ageRatingAnswers = ageRatingAnswers
            self.dataSafetyAnswers = dataSafetyAnswers
            self.usesNonExemptEncryption = usesNonExemptEncryption
        }
    }
}

// MARK: - money

/// One price. `territory` is set on the base price only.
///
/// The amount decodes through the shortest round-trip text of the YAML
/// scalar, never through `Decimal(Double)`. `Decimal(4.99)` is not 4.99, and
/// this app writes prices to a real store.
public struct Price: Codable, Sendable, Equatable {
    public var amount: Decimal
    public var currency: String
    public var territory: String?

    public init(amount: Decimal, currency: String, territory: String? = nil) {
        self.amount = amount
        self.currency = currency
        self.territory = territory
    }

    enum CodingKeys: String, CodingKey {
        case amount, currency, territory
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.currency = try c.decode(String.self, forKey: .currency)
        self.territory = try c.decodeIfPresent(String.self, forKey: .territory)

        if let text = try? c.decode(String.self, forKey: .amount) {
            guard let decimal = Decimal(string: text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount, in: c, debugDescription: "The amount is not a number: \(text)")
            }
            self.amount = decimal
        } else {
            let double = try c.decode(Double.self, forKey: .amount)
            self.amount = Decimal(string: "\(double)") ?? Decimal(double)
        }
    }
}

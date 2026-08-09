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
            /// Controls an existing phased release as well as creating one.
            public var phasedReleaseState: PhasedReleaseState?
            /// The TestFlight distribution. It is the App Store twin of the
            /// Google tester groups, and it reaches real testers, so nothing
            /// here runs before the plan shows it.
            public var testFlight: TestFlight?
            public init(releaseType: ReleaseType? = nil, phasedRelease: Bool? = nil,
                        phasedReleaseState: PhasedReleaseState? = nil,
                        testFlight: TestFlight? = nil) {
                self.releaseType = releaseType
                self.phasedRelease = phasedRelease
                self.phasedReleaseState = phasedReleaseState
                self.testFlight = testFlight
            }
        }

        /// TestFlight. The groups, who is in them, and what to test.
        ///
        /// Apple keeps the internal testers on the team, so the manifest names
        /// external groups and the addresses that belong to them. An address
        /// here receives an invitation, which is why the apply asks for the
        /// plan first.
        public struct TestFlight: Codable, Sendable, Equatable {
            public var groups: [Group]?
            /// The release notes that every tester reads, by locale. Apple
            /// calls this "What to Test" and keys it to the build.
            public var whatToTest: [String: String]?
            /// Apple emails the testers when a build arrives.
            public var autoNotify: Bool?
            /// Sends the build to the beta review that an external group
            /// needs. It is a queue, so this is the one irreversible switch.
            public var submitForBetaReview: Bool?
            /// The TestFlight page of the app, by locale. `whatToTest` above
            /// belongs to one build; this belongs to the app and it survives
            /// every build.
            public var localizations: [String: Localization]?
            /// The licence that every external tester accepts before the first
            /// install. Apple fills it with its own standard text, and a
            /// missing key here leaves whatever Apple holds alone.
            public var licenseAgreement: String?

            public init(groups: [Group]? = nil, whatToTest: [String: String]? = nil,
                        autoNotify: Bool? = nil, submitForBetaReview: Bool? = nil,
                        localizations: [String: Localization]? = nil,
                        licenseAgreement: String? = nil) {
                self.groups = groups
                self.whatToTest = whatToTest
                self.autoNotify = autoNotify
                self.submitForBetaReview = submitForBetaReview
                self.localizations = localizations
                self.licenseAgreement = licenseAgreement
            }

            /// One locale of the TestFlight page. Apple calls the resource
            /// `betaAppLocalizations`.
            public struct Localization: Codable, Sendable, Equatable {
                public var description: String?
                public var feedbackEmail: String?
                public var marketingUrl: String?
                public var privacyPolicyUrl: String?

                public init(description: String? = nil, feedbackEmail: String? = nil,
                            marketingUrl: String? = nil, privacyPolicyUrl: String? = nil) {
                    self.description = description
                    self.feedbackEmail = feedbackEmail
                    self.marketingUrl = marketingUrl
                    self.privacyPolicyUrl = privacyPolicyUrl
                }
            }

            public struct Group: Codable, Sendable, Equatable {
                public var name: String
                /// The email addresses in the group. Apple invites each one.
                public var testers: [String]?
                /// Opens the public TestFlight link, and caps it when the
                /// number is set.
                public var publicLink: Bool?
                public var publicLinkLimit: Int?
                /// Adds every new build to this group without a second call.
                public var automaticBuilds: Bool?

                public init(name: String, testers: [String]? = nil,
                            publicLink: Bool? = nil, publicLinkLimit: Int? = nil,
                            automaticBuilds: Bool? = nil) {
                    self.name = name
                    self.testers = testers
                    self.publicLink = publicLink
                    self.publicLinkLimit = publicLinkLimit
                    self.automaticBuilds = automaticBuilds
                }
            }
        }

        public enum PhasedReleaseState: String, Codable, Sendable, CaseIterable {
            case active = "ACTIVE"
            case paused = "PAUSED"
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
            /// The Google Groups that may install a closed track, keyed by the
            /// track name. A closed track without a group reaches nobody.
            ///
            /// Google accepts group email addresses here and nothing else. It
            /// keeps the single tester list in the Play Console, so the
            /// manifest names no individual address.
            public var testers: [String: [String]]?

            public init(track: String? = nil, tracks: [String]? = nil, status: String? = nil,
                        userFraction: Double? = nil, inAppUpdatePriority: Int? = nil,
                        countries: [String]? = nil, includeRestOfWorld: Bool? = nil,
                        mappingFile: String? = nil, nativeDebugSymbols: String? = nil,
                        expansionFileMain: String? = nil, expansionFilePatch: String? = nil,
                        externalApk: ExternalApk? = nil, deviceTierConfig: String? = nil,
                        testers: [String: [String]]? = nil) {
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
                self.testers = testers
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
            public var privacyPolicyText: Managed<String> = .unmanaged
            public var privacyChoicesUrl: Managed<String> = .unmanaged
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
        ///
        /// What both stores read when neither override below holds this size.
        public var screenshots: [String: [String: [String]]]?
        /// The App Store's own pictures, where they differ from the shared set.
        ///
        /// An override and not a second model, so every manifest written before
        /// per-store screenshots keeps working untouched: an absent entry means
        /// this store reads `screenshots`, which is what it always did. A
        /// *present* entry answers for this store even when it is empty, which
        /// is how "send Play nothing for this size" is said.
        public var appleScreenshots: [String: [String: [String]]]?
        /// Google Play's own pictures. See `appleScreenshots`.
        public var googleScreenshots: [String: [String: [String]]]?
        /// Apple only. Google takes a YouTube URL on the listing. Spec 6.3.
        public var previews: [String: [String: [String]]]?
        public var icon: String?            // Google only
        public var featureGraphic: String?  // Google only

        public init(screenshots: [String: [String: [String]]]? = nil,
                    appleScreenshots: [String: [String: [String]]]? = nil,
                    googleScreenshots: [String: [String: [String]]]? = nil,
                    previews: [String: [String: [String]]]? = nil,
                    icon: String? = nil, featureGraphic: String? = nil) {
            self.screenshots = screenshots
            self.appleScreenshots = appleScreenshots
            self.googleScreenshots = googleScreenshots
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
        /// App Store availability by ISO 3166-1 alpha-3 territory id.
        public var territories: [TerritoryAvailability]?

        public init(base: Price, autoConvertOtherTerritories: Bool? = nil,
                    territories: [TerritoryAvailability]? = nil) {
            self.base = base
            self.autoConvertOtherTerritories = autoConvertOtherTerritories
            self.territories = territories
        }
    }

    public struct TerritoryAvailability: Codable, Sendable, Equatable {
        public var territory: String
        public var available: Bool
        public var preOrderEnabled: Bool?
        /// Ends the preorder and puts the app on sale. Everybody who
        /// pre-ordered is charged, and no call takes that back.
        public var endPreOrder: Bool?
        public var releaseDate: String?

        public init(territory: String, available: Bool = true,
                    preOrderEnabled: Bool? = nil, endPreOrder: Bool? = nil,
                    releaseDate: String? = nil) {
            self.territory = territory
            self.available = available
            self.preOrderEnabled = preOrderEnabled
            self.endPreOrder = endPreOrder
            self.releaseDate = releaseDate
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
        /// Apple review asset and catalog controls.
        public var reviewScreenshot: String?
        public var availableTerritories: [String]?
        public var contentHosting: Bool?
        public var content: String?
        public var promotedPurchase: Bool?
        /// The promotional image the App Store shows for this purchase.
        /// Apple asks for 1024 by 1024 pixels. Google offers no equivalent.
        public var promotionalImage: String?

        public init(id: String, kind: Kind, name: String? = nil, price: Price? = nil,
                    reviewNote: String? = nil, entitlements: [String]? = nil,
                    locales: [String: ProductLocale]? = nil, active: Bool? = nil,
                    tax: Tax? = nil, offers: [Offer]? = nil,
                    reviewScreenshot: String? = nil,
                    availableTerritories: [String]? = nil,
                    contentHosting: Bool? = nil, content: String? = nil,
                    promotedPurchase: Bool? = nil,
                    promotionalImage: String? = nil) {
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
            self.reviewScreenshot = reviewScreenshot
            self.availableTerritories = availableTerritories
            self.contentHosting = contentHosting
            self.content = content
            self.promotedPurchase = promotedPurchase
            self.promotionalImage = promotionalImage
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
            /// The two Apple review controls that a one-time purchase already
            /// had. Apple asks for the same screenshot and the same territory
            /// list on a subscription, on its own pair of resources.
            public var reviewScreenshot: String?
            public var availableTerritories: [String]?
            /// Apple's billing commitment for this territory set. It cannot
            /// be inferred from duration or price.
            public var applePlanType: ApplePlanType?
            /// The promotional image the App Store shows for this
            /// subscription. Apple asks for 1024 by 1024 pixels. Google
            /// offers no equivalent.
            public var promotionalImage: String?

            public init(id: String, duration: String, basePlanId: String? = nil,
                        price: Price? = nil, entitlements: [String]? = nil,
                        packageKey: String? = nil,
                        locales: [String: ProductLocale]? = nil, active: Bool? = nil,
                        tax: Tax? = nil, offers: [Offer]? = nil,
                        migrateExistingSubscribers: Bool? = nil,
                        reviewScreenshot: String? = nil,
                        availableTerritories: [String]? = nil,
                        applePlanType: ApplePlanType? = nil,
                        promotionalImage: String? = nil) {
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
                self.reviewScreenshot = reviewScreenshot
                self.availableTerritories = availableTerritories
                self.applePlanType = applePlanType
                self.promotionalImage = promotionalImage
            }
        }
    }

    /// The two billing commitments Apple documents for subscription plan
    /// availability. Raw values are sent unchanged to App Store Connect.
    public enum ApplePlanType: String, Codable, Sendable, Equatable, CaseIterable {
        case monthly = "MONTHLY"
        case upfront = "UPFRONT"
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
        /// Google sells an offer only while it is active. A created offer
        /// starts in the draft state, so an offer without this key reaches no
        /// customer. Nil leaves the Play Console state untouched.
        ///
        /// The App Store reads it too, and on one shape only: an offer code.
        /// Apple has no switch for an introductory, a promotional, or a
        /// win-back offer, and sells each as soon as the product is live.
        /// `false` on an offer code deactivates it, which stops a redemption
        /// and keeps every subscription that already used one.
        public var active: Bool?
        /// The redeemable codes of an offer code. Apple creates the offer and
        /// no code, so an offer code without this key reaches nobody.
        ///
        /// Google generates its promotion codes in the Play Console, so this
        /// block reaches the App Store only.
        public var codes: Codes?

        public init(id: String, kind: Kind, duration: String? = nil, price: Price? = nil,
                    periods: Int? = nil, regions: [String]? = nil,
                    eligibility: Eligibility? = nil, active: Bool? = nil,
                    codes: Codes? = nil) {
            self.id = id
            self.kind = kind
            self.duration = duration
            self.price = price
            self.periods = periods
            self.regions = regions
            self.eligibility = eligibility
            self.active = active
            self.codes = codes
        }

        /// The two kinds of redeemable code Apple issues for one offer.
        ///
        /// A custom code is a string the developer picks and hands to
        /// everybody, with a redemption limit. A one-time use code is one of a
        /// batch Apple generates, and each one works once.
        public struct Codes: Codable, Sendable, Equatable {
            /// The key is the code the customer types. The value is how many
            /// redemptions Apple allows for it.
            public var custom: [String: Int]?
            /// How many single-use codes Apple generates. Apple caps a batch
            /// at 25,000 and needs an expiry date for it.
            public var oneTimeUse: Int?
            /// `YYYY-MM-DD`. Apple requires it for a one-time use batch and
            /// takes it as optional on a custom code.
            public var expiresOn: String?

            public init(custom: [String: Int]? = nil, oneTimeUse: Int? = nil,
                        expiresOn: String? = nil) {
                self.custom = custom
                self.oneTimeUse = oneTimeUse
                self.expiresOn = expiresOn
            }
        }

        public enum Kind: String, Codable, Sendable, CaseIterable {
            case freeTrial = "free_trial"
            case introPrice = "intro_price"
            /// A code that the developer hands out. Apple calls it an offer
            /// code; Google calls it a promotion.
            case offerCode = "offer_code"
            case promotional
            case winBack = "win_back"
        }

        public enum Eligibility: String, Codable, Sendable, CaseIterable {
            case new
            case existing
            case winBack = "win_back"
        }
    }

    /// The tax treatment of one product.
    /// The App Store export compliance declaration.
    ///
    /// `usesNonExemptEncryption` on the build answers the yes or no question.
    /// An app that answers yes and does not qualify for an exemption also owes
    /// Apple this declaration, and sometimes a CCATS or ERN document.
    public struct Encryption: Codable, Sendable, Equatable {
        /// `available` publishes the app; Apple also accepts `documentation`
        /// while the paperwork is in progress.
        public var availableOnFrenchStore: Bool?
        public var exempt: Bool?
        public var containsProprietaryCryptography: Bool?
        public var containsThirdPartyCryptography: Bool?
        /// The CCATS or ERN file, beside `store.yaml`.
        public var documentPath: String?
        /// The regulator code, when Apple has already issued one.
        public var codeValue: String?

        public init(availableOnFrenchStore: Bool? = nil, exempt: Bool? = nil,
                    containsProprietaryCryptography: Bool? = nil,
                    containsThirdPartyCryptography: Bool? = nil,
                    documentPath: String? = nil, codeValue: String? = nil) {
            self.availableOnFrenchStore = availableOnFrenchStore
            self.exempt = exempt
            self.containsProprietaryCryptography = containsProprietaryCryptography
            self.containsThirdPartyCryptography = containsThirdPartyCryptography
            self.documentPath = documentPath
            self.codeValue = codeValue
        }
    }

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
                public var screenshots: [String: [String]]?
                public init(promotionalText: String? = nil,
                            screenshots: [String: [String]]? = nil) {
                    self.promotionalText = promotionalText
                    self.screenshots = screenshots
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
                public var screenshots: [String: [String: [String]]]?
                public init(key: String, name: String,
                            screenshots: [String: [String: [String]]]? = nil) {
                    self.key = key
                    self.name = name
                    self.screenshots = screenshots
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
                /// `card` and `details` map to Apple's two event asset types.
                public var screenshots: [String: [String]]?
                /// One video clip per asset type, keyed the same way as the
                /// screenshots. Apple takes one clip for the card and one for
                /// the details page, so the value is a path and not a list.
                public var videoClips: [String: String]?
                public init(name: String? = nil, shortDescription: String? = nil,
                            longDescription: String? = nil,
                            screenshots: [String: [String]]? = nil,
                            videoClips: [String: String]? = nil) {
                    self.name = name
                    self.shortDescription = shortDescription
                    self.longDescription = longDescription
                    self.screenshots = screenshots
                    self.videoClips = videoClips
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
            public var advancedExperiences: [AdvancedExperience]?

            public init(action: String? = nil, locales: [String: ClipLocale]? = nil,
                        advancedExperiences: [AdvancedExperience]? = nil) {
                self.action = action
                self.locales = locales
                self.advancedExperiences = advancedExperiences
            }

            public struct AdvancedExperience: Codable, Sendable, Equatable {
                public var action: String
                public var businessCategory: String?
                public var defaultLanguage: String?
                public var link: String?
                public init(action: String, businessCategory: String? = nil,
                            defaultLanguage: String? = nil, link: String? = nil) {
                    self.action = action
                    self.businessCategory = businessCategory
                    self.defaultLanguage = defaultLanguage
                    self.link = link
                }
            }

            public struct ClipLocale: Codable, Sendable, Equatable {
                public var subtitle: String?
                public var title: String?
                /// The picture on the App Clip card. Apple keeps one per
                /// locale, beside the subtitle a reader sees under it, and it
                /// is reserved and uploaded the same way as a screenshot.
                public var headerImage: String?
                public init(subtitle: String? = nil, title: String? = nil,
                            headerImage: String? = nil) {
                    self.subtitle = subtitle
                    self.title = title
                    self.headerImage = headerImage
                }
            }
        }
    }
}

// MARK: - review (tab 6)

/// One answer on Apple's age rating questionnaire.
///
/// Apple owns the field list and the shape of each value. Most fields take an
/// enum string, a few take a flag, and Apple has changed both. Nothing here
/// names a field or a value, so the app carries no copy of a questionnaire
/// that is not its own to define. The names come from the store read, and an
/// answer the read does not know is never sent.
///
/// This replaced a `[String: Bool]` map filled from five invented keys.
/// `user_generated_content` is not an App Store Connect attribute, and every
/// apply died on it with a 409.
public enum AgeRatingAnswer: Codable, Sendable, Equatable, Hashable {
    case text(String)
    case flag(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .flag(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .flag(let value): try container.encode(value)
        }
    }

    /// The value as a request body carries it.
    public var body: Any {
        switch self {
        case .text(let value): value
        case .flag(let value): value
        }
    }

    /// The value as a person reads it.
    public var display: String {
        switch self {
        case .text(let value): value
        case .flag(let value): value ? "Yes" : "No"
        }
    }

    /// What the store answered, whatever shape it used.
    public init?(_ json: JSON) {
        if let value = json.bool { self = .flag(value) }
        else if let value = json.string { self = .text(value) }
        else { return nil }
    }
}

extension Manifest {
    /// The manifest without the five age rating keys the older build invented.
    ///
    /// That build offered them as the whole questionnaire, and the apply sent
    /// them as App Store Connect attribute names. Apple has none of them, so
    /// every manifest it touched still carries lines that declare nothing.
    /// They are dropped on the way in, because a warning about a line no store
    /// ever sees must not stand between a developer and a release.
    ///
    /// It names these five and nothing else. Apple's attributes are camelCase,
    /// so none of these can ever become one, and a key a developer typed by
    /// hand still earns the warning that explains it.
    func withoutInventedAgeRatingAnswers() -> Manifest {
        let invented: Set<String> = ["gambling", "profanity", "sexual_content",
                                     "user_generated_content", "violence"]
        guard let answers = review?.ageRatingAnswers else { return self }
        let kept = answers.filter { !invented.contains($0.key) }
        var result = self
        result.review?.ageRatingAnswers = kept.isEmpty ? nil : kept
        return result
    }
}

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
        /// Whether this block names anything the beta review contact wants.
        /// An empty review block used to blank Apple's copy on every apply.
        public var hasBetaReviewContact: Bool {
            [contactFirstName, contactLastName, contactEmail, contactPhone, notes]
                .contains { $0?.isEmpty == false } || demoAccountRequired != nil
        }

        /// Only the answers you changed. Everything absent here keeps whatever
        /// App Store Connect already holds.
        public var ageRatingAnswers: [String: AgeRatingAnswer]?
        public var dataSafetyAnswers: [String: Bool]?
        /// A current Data safety CSV exported from Play Console. Google owns
        /// this evolving format, so this exact file takes precedence over the
        /// compact answer map when it is present.
        public var dataSafetyCSV: String?
        public var usesNonExemptEncryption: Bool?
        /// The export compliance declaration that an app using non-exempt
        /// encryption needs, on top of the build flag. Apple asks for it once
        /// per app, and it carries a document for the regulated cases.
        public var encryption: Encryption?
        public var kidsAgeBand: String?
        public var attachments: [String]?

        public init(contactFirstName: String? = nil, contactLastName: String? = nil,
                    contactEmail: String? = nil, contactPhone: String? = nil,
                    demoAccountRequired: Bool? = nil, notes: String? = nil,
                    applePrimaryCategory: String? = nil,
                    appleSecondaryCategory: String? = nil,
                    ageRatingAnswers: [String: AgeRatingAnswer]? = nil,
                    dataSafetyAnswers: [String: Bool]? = nil,
                    dataSafetyCSV: String? = nil,
                    usesNonExemptEncryption: Bool? = nil,
                    kidsAgeBand: String? = nil, attachments: [String]? = nil) {
            self.contactFirstName = contactFirstName
            self.contactLastName = contactLastName
            self.contactEmail = contactEmail
            self.contactPhone = contactPhone
            self.demoAccountRequired = demoAccountRequired
            self.notes = notes
            self.applePrimaryCategory = applePrimaryCategory
            self.appleSecondaryCategory = appleSecondaryCategory
            self.ageRatingAnswers = ageRatingAnswers
            self.dataSafetyAnswers = dataSafetyAnswers
            self.dataSafetyCSV = dataSafetyCSV
            self.usesNonExemptEncryption = usesNonExemptEncryption
            self.kidsAgeBand = kidsAgeBand
            self.attachments = attachments
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

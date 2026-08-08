import Foundation

/// What the stores hold right now.
///
/// The plan reads this, compares it to the manifest, and writes nothing.
/// Spec section 7.2, step 1.
public struct ActualState: Sendable, Equatable {
    public var apple: Apple?
    public var google: Google?
    public var provider: Provider?
    public var readAt: Date?
    /// A store that could not be read. The plan says so instead of pretending
    /// that everything matches.
    public var failures: [String] = []

    public init() {}

    public struct Apple: Sendable, Equatable {
        public var appInfoId: String?
        /// The version the app may write to. It is nil when the app is live
        /// and nobody has started the next one, and the plan then creates it.
        public var versionId: String?
        public var versionString: String?
        /// `PREPARE_FOR_SUBMISSION`, `WAITING_FOR_REVIEW`, and the rest.
        /// Spec section 10.6 blocks a metadata write outside the first one.
        public var versionState: String?
        /// How the version goes on sale once Apple approves it. The plan
        /// compares against this, so a manifest that names the type the store
        /// already carries writes nothing.
        public var releaseType: String?
        /// The version the customers see. It never equals `versionString`,
        /// because a live version is not a version the app may write to. The
        /// validator needs it to demand a higher number in the manifest.
        public var liveVersionString: String?
        /// Every category id App Store Connect accepts, parents and children.
        /// Apple owns this list and changes it, so the app checks a manifest
        /// category against this read and never against a list of its own.
        /// Empty means the read never reached it, and nothing is checked.
        public var appCategoryIDs: Set<String> = []
        public var primaryCategory: String?
        public var secondaryCategory: String?
        public var infoLocales: [String: InfoLocale] = [:]
        public var versionLocales: [String: VersionLocale] = [:]
        /// The text the customers read today, from the live version.
        ///
        /// `versionLocales` holds the editable draft, and the draft is often an
        /// empty shell: App Store Connect creates one with no words, and so
        /// does this app's own apply. The plan and the run must diff against
        /// that shell, so this is kept apart from it and never feeds either.
        /// It exists so the editing tabs can say what the store is serving.
        public var liveVersionLocales: [String: VersionLocale] = [:]
        /// "locale/displayType" to the set of `sourceFileChecksum` values that
        /// Apple already holds. An upload that matches is skipped. Spec 7.5.
        public var screenshotChecksums: [String: Set<String>] = [:]
        public var screenshotChecksumOrder: [String: [String]] = [:]
        public var previewChecksums: [String: Set<String>] = [:]
        /// "locale/displayType" to the images Apple serves right now, in the
        /// order it shows them. It comes out of the same payload as the
        /// checksums, so the editing tabs can show the live media for free.
        public var screenshotURLs: [String: [URL]] = [:]
        public var previewURLs: [String: [URL]] = [:]
        /// The highest build number inside **this version's train**, never
        /// across the whole app. Apple counts a build number against the
        /// marketing version it belongs to, and a new train may start at one.
        public var highestBuildNumber: Int?
        /// The processed build that App Store Connect already holds for this
        /// version, and that no version holds yet.
        ///
        /// Build from Project uploads with `xcodebuild -exportArchive`, so a
        /// binary reaches Apple without this app's own upload step. The plan
        /// still has to attach it, and this is what it attaches.
        public var buildIdForVersion: String?
        public var attachedBuildId: String?
        public var buildUsesNonExemptEncryption: Bool?
        public var reviewDetailId: String?
        public var reviewContactEmail: String?
        public var reviewContactFirstName: String?
        public var reviewContactLastName: String?
        public var reviewContactPhone: String?
        public var reviewDemoAccountRequired: Bool?
        public var reviewNotes: String?
        public var ageRatingDeclarationId: String?
        /// Every age rating field App Store Connect holds, with its current
        /// value. Apple owns this questionnaire, so this read is the only
        /// place the app learns the field names. A manifest answer whose key
        /// is missing here is a key Apple does not have, and no apply sends
        /// one. Empty means the read never reached the declaration.
        public var ageRating: [String: AgeRatingAnswer] = [:]
        public var purchaseIds: Set<String> = []
        public var subscriptionIds: Set<String> = []
        /// Every paid product that Apple holds, keyed by the product id. The
        /// purchases and the subscription plans share the map, because a
        /// product id is unique across both. It mirrors the Google catalog.
        public var catalog: [String: CatalogProduct] = [:]
        /// The subscription groups that Apple holds, by the reference name
        /// that the manifest group id maps to, and their localizations. The
        /// subscription write covers the group as well as its plans, so the
        /// diff has to compare both.
        public var subscriptionGroupNames: Set<String> = []
        public var subscriptionGroupLocales:
            [String: [String: CatalogProduct.ProductLocale]] = [:]
        /// The TestFlight groups that Apple holds, by name, with the testers
        /// and the builds each one carries.
        public var betaGroups: [String: AppleTestFlightClient.BetaGroup] = [:]
        /// The "What to Test" note of the attached build, by locale.
        public var whatToTest: [String: String] = [:]
        public var betaReviewSubmitted: Bool?
        public var betaAutoNotify: Bool?
        /// The TestFlight page of the app, by locale. Empty means the read
        /// failed or the app has no page yet, and the planner tells the two
        /// apart with `betaAppLocalizationsRead`.
        public var betaAppLocalizations: [String: Manifest.Release.TestFlight.Localization] = [:]
        public var betaAppLocalizationsRead = false
        /// The subscription grace period, in days, and its switch.
        public var gracePeriodDays: Int?
        public var gracePeriodOptIn: Bool?
        /// The marketing resources, by the key that the manifest gives them.
        public var customProductPageNames: [String: String] = [:]
        public var experimentNames: [String: String] = [:]
        public var appEventNames: [String: String] = [:]
        public var eulaText: String?
        public var eulaTerritories: Set<String> = []
        public var nominationNames: Set<String> = []
        public var accessibilitySupports: Set<String> = []
        public var appClipExperienceActions: Set<String> = []
        public var hasAppClipExperience: Bool?
        /// Spec 10.6. A second submission cannot open while one is open.
        public var hasOpenReviewSubmission = false
        public var priceAmount: Decimal?
        public var currentPriceAmount: Decimal?
        public var priceCurrency: String?
        public var territoryCount: Int?
        public var appAvailabilityId: String?
        public var territoryAvailability: [String: Bool] = [:]
        public var availableInNewTerritories: Bool?
        public var phasedReleaseId: String?
        public var phasedReleaseState: String?

        public init() {}

        public struct InfoLocale: Sendable, Equatable {
            public var id: String?
            public var name: String?
            public var subtitle: String?
            public var privacyPolicyUrl: String?
            public var privacyPolicyText: String?
            public var privacyChoicesUrl: String?
            public init() {}
        }

        public struct VersionLocale: Sendable, Equatable {
            public var id: String?
            public var description: String?
            public var whatsNew: String?
            public var keywords: String?
            public var promotionalText: String?
            public var supportUrl: String?
            public var marketingUrl: String?
            public init() {}
        }

        /// One paid product that Apple holds, in the shape that the plan
        /// compares.
        ///
        /// `// ponytail: the fields the manifest writes, and no others. The
        /// // App Store product carries a dozen more, and the plan shows none
        /// // of them.`
        public struct CatalogProduct: Sendable, Equatable {
            public var productId: String = ""
            /// The Apple resource id, so a later write patches instead of
            /// creating a duplicate.
            public var id: String?
            public var name: String?
            public var reviewNote: String?
            /// The locale to the store name and description.
            public var locales: [String: ProductLocale] = [:]
            /// The territory to the customer price, as `"USD 4.99"`.
            public var prices: [String: String] = [:]
            public var availableTerritories: Set<String> = []
            public var promoted: Bool?
            /// The offer ids that Apple holds on this product. An introductory
            /// offer carries no id of its own, so it never lands here.
            public var offerIds: Set<String> = []
            /// How many offers Apple holds, across the three offer
            /// collections. Nil means that the offer read failed, and the plan
            /// then says that nobody verified the offers.
            public var offerCount: Int?
            /// The subscription duration, as an ISO 8601 period.
            public var duration: String?
            public init() {}

            public struct ProductLocale: Sendable, Equatable {
                public var name: String?
                public var description: String?
                public init() {}
            }
        }
    }

    public struct Google: Sendable, Equatable {
        public var listings: [String: Listing] = [:]
        public var contactEmail: String?
        public var contactWebsite: String?
        public var contactPhone: String?
        public var tracks: [String: Track] = [:]
        public var highestVersionCode: Int?
        /// "locale/imageType" to the `sha256` values that Google already holds.
        public var imageHashes: [String: Set<String>] = [:]
        /// "locale/imageType" to the images Google serves right now, from the
        /// same payload as the hashes.
        public var imageURLs: [String: [URL]] = [:]
        public var oneTimeProductIds: Set<String> = []
        public var subscriptionIds: Set<String> = []
        /// Every catalog product that Google holds, keyed by the product id.
        /// The one-time products and the subscription plans share this map,
        /// because a product id is unique across both.
        public var catalog: [String: CatalogProduct] = [:]

        public init() {}

        public struct Listing: Sendable, Equatable {
            public var title: String?
            public var shortDescription: String?
            public var fullDescription: String?
            public var video: String?
            public init() {}
        }

        public struct Track: Sendable, Equatable {
            public var versionCodes: [Int] = []
            public var status: String?
            public var userFraction: Double?
            public var releaseNotes: [String: String] = [:]
            /// The Google Group addresses that may install this track.
            public var testers: [String] = []
            /// The countries that Google sells this track in. Nil means that
            /// the read failed or that the track is not a country-targeted
            /// one, and then the plan says so instead of showing a false diff.
            public var countries: [String]?
            public var restOfWorld: Bool?
            public init() {}
        }

        /// One catalog product, in the shape that the plan compares.
        ///
        /// `// ponytail: the fields that the manifest writes, and no others. A
        /// // full mirror of the Google product would need a normalizer for
        /// // every nested region config, and the plan shows none of that.`
        public struct CatalogProduct: Sendable, Equatable {
            public var productId: String = ""
            /// The language code to the title and the description.
            public var listings: [String: ProductListing] = [:]
            /// The region code to the price, as `"USD 4.99"`.
            public var prices: [String: String] = [:]
            /// The first base plan of a subscription. Nil for a one-time
            /// product.
            public var basePlanId: String?
            public var basePlanDuration: String?
            public var basePlanState: String?
            /// The offer id to its Google state, for example `ACTIVE`.
            public var offerStates: [String: String] = [:]
            public init() {}

            public struct ProductListing: Sendable, Equatable {
                public var title: String?
                public var description: String?
                public init() {}
            }
        }
    }

    public struct Provider: Sendable, Equatable {
        public var kind: Manifest.Provider = .none
        /// The provider product id, keyed by the store product id.
        public var productIds: [String: String] = [:]
        public var entitlementKeys: Set<String> = []
        public var offeringKeys: Set<String> = []
        /// The store product ids that each entitlement key already holds. A
        /// key with no entry means that the attachment read failed.
        public var entitlementProducts: [String: Set<String>] = [:]
        /// The store product ids that each offering already carries, in the
        /// order the provider serves them.
        public var offeringProducts: [String: [String]] = [:]
        /// The offering key that the provider marks current.
        public var currentOfferingKey: String?
        /// The RevenueCat app id to its store identifier, for the mismatch
        /// rules in spec section 10.5.
        public var appIdentifiers: [String: String] = [:]
        public var missingScopes: [String] = []
        public var loggedInAs: String?

        public init() {}
    }
}

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
        public var versionId: String?
        public var versionString: String?
        /// `PREPARE_FOR_SUBMISSION`, `WAITING_FOR_REVIEW`, and the rest.
        /// Spec section 10.6 blocks a metadata write outside the first one.
        public var versionState: String?
        public var primaryCategory: String?
        public var secondaryCategory: String?
        public var infoLocales: [String: InfoLocale] = [:]
        public var versionLocales: [String: VersionLocale] = [:]
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
        public var highestBuildNumber: Int?
        public var attachedBuildId: String?
        public var buildUsesNonExemptEncryption: Bool?
        public var reviewDetailId: String?
        public var reviewContactEmail: String?
        public var ageRatingDeclarationId: String?
        public var purchaseIds: Set<String> = []
        public var subscriptionIds: Set<String> = []
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
        /// The RevenueCat app id to its store identifier, for the mismatch
        /// rules in spec section 10.5.
        public var appIdentifiers: [String: String] = [:]
        public var missingScopes: [String] = []
        public var loggedInAs: String?

        public init() {}
    }
}

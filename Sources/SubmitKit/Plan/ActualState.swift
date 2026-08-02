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
        public var previewChecksums: [String: Set<String>] = [:]
        public var highestBuildNumber: Int?
        public var attachedBuildId: String?
        public var reviewDetailId: String?
        public var reviewContactEmail: String?
        public var ageRatingDeclarationId: String?
        public var purchaseIds: Set<String> = []
        public var subscriptionIds: Set<String> = []
        /// Spec 10.6. A second submission cannot open while one is open.
        public var hasOpenReviewSubmission = false
        public var priceAmount: Decimal?
        public var priceCurrency: String?
        public var territoryCount: Int?

        public init() {}

        public struct InfoLocale: Sendable, Equatable {
            public var id: String?
            public var name: String?
            public var subtitle: String?
            public var privacyPolicyUrl: String?
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
        public var oneTimeProductIds: Set<String> = []
        public var subscriptionIds: Set<String> = []

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
            public init() {}
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

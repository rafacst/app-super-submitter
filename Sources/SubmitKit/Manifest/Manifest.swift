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

        public struct RevenueCat: Codable, Sendable, Equatable {
            public var projectId: String
            public var appIds: AppIds

            public struct AppIds: Codable, Sendable, Equatable {
                public var appStore: String?
                public var macAppStore: String?
                public var playStore: String?

                enum CodingKeys: String, CodingKey {
                    case appStore = "app_store"
                    case macAppStore = "mac_app_store"
                    case playStore = "play_store"
                }
            }
        }

        public struct Adapty: Codable, Sendable, Equatable {
            public var appId: String
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

        public struct Build: Codable, Sendable, Equatable {
            public var ios: String?
            public var macos: String?
            public var android: String?
        }

        public struct AppleRelease: Codable, Sendable, Equatable {
            public var releaseType: ReleaseType?
            public var phasedRelease: Bool?
        }

        public struct GoogleRelease: Codable, Sendable, Equatable {
            public var track: String?
            /// Read at release time, never at apply time. An apply always
            /// writes `draft`. Spec section 7.4.
            public var status: String?
            public var userFraction: Double?
            public var inAppUpdatePriority: Int?
        }

        public enum ReleaseType: String, Codable, Sendable, CaseIterable {
            case manual = "MANUAL"
            case afterApproval = "AFTER_APPROVAL"
            case scheduled = "SCHEDULED"
        }
    }
}

// MARK: - listing (tab 3)

extension Manifest {
    public struct Listing: Codable, Sendable, Equatable {
        public var defaultLocale: String
        public var locales: [String: Locale]

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

            public struct GoogleOverride: Codable, Sendable, Equatable {
                public var shortDescription: Managed<String> = .unmanaged
                public var video: Managed<String> = .unmanaged
                public var whatsNew: Managed<String> = .unmanaged
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
    }

    public struct Purchase: Codable, Sendable, Equatable {
        public var id: String
        public var kind: Kind
        public var name: String?
        public var price: Price?
        public var reviewNote: String?
        public var entitlements: [String]?
        public var locales: [String: ProductLocale]?

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

        public struct Plan: Codable, Sendable, Equatable {
            public var id: String
            /// ISO 8601, for example `P1M`. Spec 6.6.2 holds the Adapty map.
            public var duration: String
            public var basePlanId: String?   // Google needs it. Apple ignores it.
            public var price: Price?
            public var entitlements: [String]?
            public var packageKey: String?   // RevenueCat only
            public var locales: [String: ProductLocale]?
        }
    }

    public struct ProductLocale: Codable, Sendable, Equatable {
        public var name: String?
        public var description: String?
    }

    public struct Entitlement: Codable, Sendable, Equatable {
        public var key: String
        public var name: String?
    }

    public struct Offering: Codable, Sendable, Equatable {
        public var key: String
        public var name: String?
        public var isCurrent: Bool?
        public var products: [String]?
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

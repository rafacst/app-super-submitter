import Foundation

/// Which `AppVersionState` values still take a write.
///
/// One list, because three places had their own and one of them disagreed.
/// The two readers picked a withdrawn or rejected version as the version to
/// write to, which is right: App Store Connect hands the version back to the
/// developer, and it takes new metadata and a new build under the same
/// number. The validator asked for `PREPARE_FOR_SUBMISSION` and nothing else,
/// so it blocked the apply against the version the readers had just chosen,
/// and a developer who cancelled a submission could not send the rebuilt
/// binary at all.
///
/// `READY_FOR_REVIEW` is still a draft: it has been added to a draft review
/// submission, but Apple has not received that submission yet.
///
/// `INVALID_BINARY` belongs here for the same reason and is the plainest case
/// of it: Apple refused the binary and is waiting for another one.
///
/// Only these. A version in review, approved, or on sale takes no write, and
/// the error that says so is the one that stops a developer editing a listing
/// customers are already reading.
public enum AppleVersionState {
    public static let editable: Set<String> = [
        "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "INVALID_BINARY",
    ]

    /// Apple has it and has not answered. Nothing may be written and nothing
    /// may be sent: a second submission on top of an open one is the state
    /// App Store Connect refuses outright.
    public static let withApple: Set<String> = [
        "WAITING_FOR_REVIEW", "IN_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE",
    ]

    /// The states of a version customers have had.
    ///
    /// It answers "has this app ever shipped?" off a bare version state, which
    /// is all a sweep over every linked app has in hand. A version pulled from
    /// sale still shipped, and one replaced by a newer one shipped too.
    ///
    /// `PENDING_DEVELOPER_RELEASE` is not here. Apple said yes and nobody can
    /// buy it yet, so an app whose only version sits there has never been on
    /// the store. `AppleStanding` draws the same line and calls it "Approved".
    public static let shipped: Set<String> = [
        "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION",
        "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE",
    ]

    /// What Apple said, once it has said anything.
    ///
    /// Three answers and not two. `waiting` is the state this app spent its
    /// whole life refusing to write in and never named, and it is the one a
    /// developer opens the app to ask about.
    public enum Outcome: Sendable, Equatable {
        case waiting
        case approved
        case refused
    }

    /// Apple's answer for a version state, or nil where Apple has not been
    /// asked yet.
    ///
    /// `DEVELOPER_REJECTED` answers nil on purpose. The developer withdrew it,
    /// Apple never refused it, and reporting a refusal sends somebody looking
    /// for a reason nobody ever wrote.
    public static func outcome(of state: String?) -> Outcome? {
        guard let state else { return nil }
        if withApple.contains(state) { return .waiting }
        if ["ACCEPTED", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE",
            "PROCESSING_FOR_DISTRIBUTION", "READY_FOR_DISTRIBUTION"].contains(state) {
            return .approved
        }
        if ["REJECTED", "METADATA_REJECTED", "INVALID_BINARY"].contains(state) {
            return .refused
        }
        return nil
    }

    /// What Apple refused, in the words its own state uses.
    ///
    /// This is as far as any endpoint goes. The App Store Connect API
    /// publishes no Resolution Center resource: there is no `rejectionReason`,
    /// no message, and no attachment of Apple's reply anywhere in the
    /// reference. The kind is knowable and the sentence is not, so the app
    /// says the kind and sends the developer to the thread for the rest.
    public static func refusalKind(_ state: String?) -> String? {
        switch state {
        case "METADATA_REJECTED": "the metadata"
        case "INVALID_BINARY": "the binary"
        case "REJECTED": "the submission"
        default: nil
        }
    }

    /// Whether Apple locks this field while it holds the version.
    ///
    /// Store policy and not the schema. Every one of these is a plain string
    /// on `appStoreVersionLocalizations` and the endpoint would take any of
    /// them; App Store Connect refuses the write once the version is with
    /// review. The promotional text is the exception Apple documents in its
    /// own interface: it is not part of what review reads, so it can be
    /// changed at any time, on a version already in review and on a live one.
    public static func isLocked(_ field: ListingTextField) -> Bool {
        field != .promotionalText
    }
}

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
        /// Where every platform of this app id stands, and not only the one
        /// this run is submitting.
        ///
        /// One app id carries a separate train per platform, and they are not
        /// in step: a Mac app can be on sale for a year while its iOS twin has
        /// never left the draft. Every other field here is narrowed to one
        /// platform, which is right for planning a run and wrong for the one
        /// question a developer asks before starting one, "which of these is
        /// actually out?".
        ///
        /// It costs no extra request. `/v1/apps/{id}/appStoreVersions` answers
        /// for every platform at once and the reader was already dropping the
        /// rest on the floor.
        public var platforms: [PlatformStanding] = []
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
        /// The twin of `screenshotChecksumOrder`, for the live version.
        ///
        /// App Store Connect fills a new version from the last released one,
        /// pictures included, so this is what the version this run creates
        /// starts out holding. `startingScreenshotOrder` is the only reader.
        public var liveScreenshotChecksumOrder: [String: [String]] = [:]
        public var previewChecksums: [String: Set<String>] = [:]
        /// "locale/displayType" to the images Apple serves right now, in the
        /// order it shows them. It comes out of the same payload as the
        /// checksums, so the editing tabs can show the live media for free.
        public var screenshotURLs: [String: [URL]] = [:]
        public var previewURLs: [String: [URL]] = [:]
        /// The same live screenshots with the store's own file names on them.
        /// The app downloads them into `Store Import/` so the Media tab draws
        /// from disk, and a bare URL carries no name to save one under.
        public var liveAssets: [ImportedStoreAsset] = []
        /// The custom product pages and the experiment treatments, and what
        /// each of them shows. Read only: nothing plans or writes these.
        public var productPages: [StoreProductPage] = []
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
        /// The reviewer sign-in App Store Connect already holds.
        ///
        /// An update inherits the review detail from the released version, so
        /// a developer who sent a demo account last time has already sent this
        /// one. The app keeps its own copy in the Keychain and never in the
        /// manifest, and a Keychain is per machine: a new Mac, a re-install, or
        /// a colleague meant the fields opened empty on an app that had shipped
        /// with them three times. The store is the one place that remembers.
        ///
        /// Apple may answer the name and withhold the password. The two are
        /// read apart for that reason, and the screen says which of them came
        /// back.
        public var reviewDemoAccountName: String?
        public var reviewDemoAccountPassword: String?
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
        /// Whether the two catalog list reads answered.
        ///
        /// An empty `catalog` is two different facts and the screen has to tell
        /// them apart: Apple was asked and holds nothing, or nobody has asked.
        /// Without this the Monetization tab read every unread product as one
        /// the apply would create, so an app whose purchases have been approved
        /// for years opened with "Will add" against each of them. The same line
        /// `betaAppLocalizationsRead` draws, for the same reason.
        public var catalogRead = false
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
        /// The licence text that every external tester accepts. Nil means the
        /// read failed; an empty string means Apple holds an empty agreement.
        public var betaLicenseAgreement: String?
        /// What App Store Connect holds for Game Center, or nil for an app the
        /// read never reached.
        public var gameCenter: GameCenter?
        /// The subscription grace period, in days, and its switch.
        public var gracePeriodDays: Int?
        public var gracePeriodOptIn: Bool?
        /// The marketing resources, by the key that the manifest gives them.
        public var customProductPageNames: [String: String] = [:]
        /// Everything App Store Connect holds for one game.
        ///
        /// Every map is keyed the way the manifest names the thing: by vendor
        /// identifier for the five families, and by reference name for the
        /// groups, which carry no vendor identifier at all.
        ///
        /// `read` is what tells "this app has no Game Center" apart from "the
        /// read failed". The first is the ordinary state of every app that is
        /// not a game and costs one request; the second must never produce a
        /// create step, because a create against an existing detail answers
        /// 409.
        public struct GameCenter: Sendable, Equatable {
            public var detail: AppleGameCenterClient.Detail?
            public var groups: [String: String] = [:]
            public var appVersions: [String: AppleGameCenterClient.AppVersion] = [:]
            public var achievements: [String: AppleGameCenterCatalogClient.Object] = [:]
            public var leaderboards: [String: AppleGameCenterCatalogClient.Object] = [:]
            public var leaderboardSets: [String: AppleGameCenterCatalogClient.Object] = [:]
            public var activities: [String: AppleGameCenterCatalogClient.Object] = [:]
            public var challenges: [String: AppleGameCenterCatalogClient.Object] = [:]
            /// The names Apple already holds for the boards inside a set, by
            /// set vendor identifier. Read only: Apple deprecated the write and
            /// left the read and the delete live.
            public var memberLocalizations:
                [String: [AppleGameCenterCatalogClient.MemberName]] = [:]
            /// Matchmaking, keyed by reference name. Apple gives these no
            /// vendor identifier, and they belong to the account rather than
            /// to one app, exactly like the groups above.
            public var ruleSets: [String: AppleGameCenterMatchmakingClient.RuleSet] = [:]
            public var queues: [String: AppleGameCenterMatchmakingClient.Queue] = [:]
            /// False when the detail read failed rather than answering nothing.
            public var read = false
            /// The families whose own read failed, so the tab can say the
            /// count it shows is short rather than showing a wrong zero.
            /// `matchmaking` joins the five family names here when the rule
            /// set read fails, for the same reason: a wrong zero would read as
            /// "create every rule set" on the next plan.
            public var unreadFamilies: Set<String> = []

            public init() {}

            /// The objects of one family, so a panel names the family once.
            public func objects(_ family: AppleGameCenterCatalogClient.Family)
                -> [String: AppleGameCenterCatalogClient.Object] {
                switch family {
                case .achievement: achievements
                case .leaderboard: leaderboards
                case .leaderboardSet: leaderboardSets
                case .activity: activities
                case .challenge: challenges
                }
            }

            /// Whether the app has a configuration at all. A read that failed
            /// answers false here and `read` false beside it.
            public var exists: Bool { detail != nil }
        }

        /// One product page experiment, as Apple describes it.
        ///
        /// This was the state string alone. The same response carries the
        /// dates and the traffic share, and the Marketing tab needs them to say
        /// how far into its run an experiment is, so the read stops throwing
        /// them away. The plan only ever asks whether the key is present, so a
        /// richer value costs it nothing.
        public struct Experiment: Sendable, Equatable, Codable {
            public var state: String
            public var startDate: String?
            public var endDate: String?
            public var trafficProportion: Int?

            public init(state: String = "", startDate: String? = nil,
                        endDate: String? = nil, trafficProportion: Int? = nil) {
                self.state = state
                self.startDate = startDate
                self.endDate = endDate
                self.trafficProportion = trafficProportion
            }
        }
        public var experiments: [String: Experiment] = [:]
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
        /// Every customer price Apple sells at in the base territory, sorted.
        ///
        /// Apple does not sell at the number the developer typed. It sells at a
        /// price point, and the apply already resolves the typed amount to the
        /// nearest one, so a manifest that said 4.95 shipped as 4.99 and the
        /// only warning was a gap of under five percent that nobody read.
        ///
        /// The read has always fetched this whole list and kept one value out
        /// of it. Keeping the list lets the field offer the prices that exist
        /// instead of accepting a number that does not.
        ///
        /// Empty means nobody has read the store, or the app does not go to the
        /// App Store. The field stays a plain text field then: a developer with
        /// no credentials still has to be able to name a price.
        public var pricePoints: [Decimal] = []
        /// The territory `pricePoints` was read for. A ladder read for one
        /// territory names prices that do not exist in another, so the field
        /// only offers the list while the base territory still matches.
        public var pricePointTerritory: String?
        public var currentPriceAmount: Decimal?
        public var priceCurrency: String?
        public var territoryCount: Int?
        public var territoryAvailability: [String: Bool] = [:]
        public var availableInNewTerritories: Bool?
        public var phasedReleaseId: String?
        public var phasedReleaseState: String?

        public init() {}

        // MARK: - The update

        /// True when the app is already on the App Store.
        ///
        /// An update is not a first publish. App Store Connect carries the
        /// released version into the next one, so a field the developer never
        /// touched is already there, and sending it again writes the same
        /// bytes over the same bytes. Every rule that only holds for a shipped
        /// app asks this one question.
        public var isUpdate: Bool { liveVersionString != nil }

        /// The version Apple is holding for one platform, when it holds one.
        ///
        /// `versionId`, `versionString` and `versionState` name the version the
        /// app may **write** to, and a version in review is not one, so the
        /// reader leaves all three nil for as long as the review lasts. That is
        /// right for planning a write and wrong for every question about what
        /// the store is doing, and those questions were asking the same three
        /// fields and hearing "no version at all". A first submission sitting in
        /// review read **No version is prepared**, the blockers panel counted
        /// that row, and Re-check re-ran a read that answers nil again every
        /// time, so the row could not be cleared by the button offered to clear
        /// it.
        ///
        /// The answer was already in hand: `platforms` carries the pending
        /// number and its state for every platform of this app id, off the same
        /// request, and nothing here consulted it.
        ///
        /// An editable state answers nil. A plain draft is not "with the
        /// store", and a rejection hands the version back and makes the
        /// checklist matter again.
        public func submittedVersion(platform: String)
            -> (version: String?, state: String)? {
            guard let standing = platforms.first(where: { $0.platform == platform }),
                  let state = standing.pendingState,
                  !AppleVersionState.editable.contains(state) else { return nil }
            return (standing.pending, state)
        }

        /// The listing text the version this run writes to starts out holding.
        ///
        /// A draft that exists answers for itself: it is the resource the run
        /// patches, and whatever it holds is what a write would replace.
        ///
        /// Before it exists there is nothing to read, and comparing against
        /// nothing made every field of an update look changed. The run creates
        /// that version, and Apple fills a new version from the released one,
        /// so the words the customers read today are what it will start with.
        public func startingVersionLocale(_ code: String) -> VersionLocale? {
            if let draft = versionLocales[code] { return draft }
            guard isUpdate, versionId == nil else { return nil }
            return liveVersionLocales[code]
        }

        /// The screenshots that version starts out holding, by
        /// "locale/displayType", in the order the store shows them.
        ///
        /// The same rule as the text, and the one that costs real bytes: an
        /// update re-uploaded every picture Apple had already carried over.
        public func startingScreenshotOrder(_ key: String) -> [String]? {
            if let draft = screenshotChecksumOrder[key] { return draft }
            guard isUpdate, versionId == nil else { return nil }
            return liveScreenshotChecksumOrder[key]
        }

        /// One platform of one app id, and how far along it is.
        ///
        /// `live` is the number a customer can buy today and `pending` is the
        /// number that is on its way, so an app that is on sale at 1.5 with 1.6
        /// in review carries both. Either may be nil: a platform in draft has
        /// no live version, and a shipped platform with nothing started has no
        /// pending one.
        public struct PlatformStanding: Sendable, Equatable {
            /// `IOS`, `MAC_OS`, `TV_OS` or `VISION_OS`, as Apple spells them.
            public var platform: String
            /// The number a customer can buy today, and its `AppVersionState`.
            /// Nil on a platform that has never shipped.
            public var live: String?
            public var liveState: String?
            /// The number on its way, and its `AppVersionState`. Nil when
            /// nothing has been started since the last release.
            public var pending: String?
            public var pendingState: String?

            /// Two states and not one, because the answer depends on which
            /// question is being asked. "Is this platform out?" is the live
            /// one; "what is happening to it?" is the pending one. A chip that
            /// merged them read "In review over live", which is both answers in
            /// one breath and too long for a chip.
            public init(platform: String,
                        live: String? = nil, liveState: String? = nil,
                        pending: String? = nil, pendingState: String? = nil) {
                self.platform = platform
                self.live = live
                self.liveState = liveState
                self.pending = pending
                self.pendingState = pendingState
            }
        }

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
            /// Apple's own review state for the product, `APPROVED`,
            /// `WAITING_FOR_REVIEW`, `READY_TO_SUBMIT` and the rest.
            ///
            /// A product is reviewed separately from the app, and an approved
            /// one goes back into review when its name, its review note or its
            /// localizations change. The developer has to be told that before
            /// they type, not after the apply.
            public var state: String?
            /// The subscription group that holds this product, for a
            /// subscription. Nil for a one-time purchase.
            public var groupName: String?

            /// Apple has already approved this product, so a change to its
            /// name, its review note or its localizations sends it back into
            /// review on its own, separately from the app.
            ///
            /// A product taken off sale counts as approved: it went through
            /// review once and putting it back is not a fresh submission.
            public var isApproved: Bool {
                ["APPROVED", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"]
                    .contains(state ?? "")
            }

            /// Apple has this product and has not answered yet.
            public var isWithReview: Bool {
                ["WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_BINARY_APPROVAL"]
                    .contains(state ?? "")
            }
            /// The locale to the store name and description.
            public var locales: [String: ProductLocale] = [:]
            /// True on a desired-state value when absence from `locales`
            /// means delete it. Store reads leave this false.
            public var managesLocales = false
            /// False means no usable metadata version was available or its
            /// localization read failed. An empty successful read is true.
            public var localesRead = false
            /// The territory to the customer price, as `"USD 4.99"`.
            public var prices: [String: String] = [:]
            public var availableTerritories: Set<String> = []
            /// Subscription territories stay separated by Apple's billing
            /// plan type. Combining these sets would compare unlike plans.
            public var subscriptionPlanTerritories: [Manifest.ApplePlanType: Set<String>] = [:]
            public var subscriptionPlanAvailabilityRead = false
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

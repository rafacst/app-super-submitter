import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

private final class CorrectionCallLog: @unchecked Sendable {
    struct Call {
        var method: String
        var path: String
        var body: [String: Any]
    }

    private let lock = NSLock()
    private var entries: [Call] = []

    func record(_ request: URLRequest) {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                collected.append(contentsOf: bytes[..<count])
            }
            data = collected
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            as? [String: Any] ?? [:]
        lock.withLock {
            entries.append(Call(method: request.httpMethod ?? "",
                                path: request.url?.path ?? "", body: body))
        }
    }

    var all: [Call] { lock.withLock { entries } }
}

private final class CorrectionStubProtocol: URLProtocol, @unchecked Sendable {
    enum Scenario {
        case reviews, purchase, release, releaseExistingDraft, encryption
        case subscriptionLocales, groupLocales
        case availabilityExisting, availabilityMissing, subscriptionCatalog
        case subscriptionDraftExisting, subscriptionDraftMissing, subscriptionDraftInReview
    }

    nonisolated(unsafe) static var scenario = Scenario.reviews
    nonisolated(unsafe) static var log = CorrectionCallLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request)
        let method = request.httpMethod ?? ""
        let path = request.url?.path ?? ""
        let body: String

        switch Self.scenario {
        case .reviews:
            body = #"{"data":{"type":"customerReviewResponses","id":"response-1"}}"#

        case .purchase:
            switch (method, path) {
            case ("GET", "/v1/apps/app-1/inAppPurchasesV2"):
                body = #"{"data":[{"type":"inAppPurchases","id":"purchase-1","attributes":{"productId":"pro","name":"Pro"}}]}"#
            case ("GET", "/v2/inAppPurchases/purchase-1/versions"):
                body = #"{"data":[{"type":"inAppPurchaseVersions","id":"purchase-version-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"}}]}"#
            case ("GET", "/v1/inAppPurchaseVersions/purchase-version-1/localizations"):
                body = #"{"data":[{"type":"inAppPurchaseLocalizations","id":"purchase-locale-1","attributes":{"locale":"en-US","name":"Pro","description":"Full access"}}]}"#
            default:
                body = #"{"data":[]}"#
            }

        case .release:
            switch (method, path) {
            case ("POST", "/v1/reviewSubmissions"):
                body = #"{"data":{"type":"reviewSubmissions","id":"submission-1"}}"#
            case ("GET", "/v1/apps/app-1/inAppPurchasesV2"):
                body = #"{"data":[{"type":"inAppPurchases","id":"purchase-1","attributes":{"productId":"pro"}}]}"#
            case ("GET", "/v2/inAppPurchases/purchase-1/versions"):
                body = #"{"data":[{"type":"inAppPurchaseVersions","id":"purchase-version-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"}}]}"#
            case ("GET", "/v1/apps/app-1/subscriptionGroups"):
                body = """
                {"data":[{"type":"subscriptionGroups","id":"group-1",
                            "attributes":{"referenceName":"Pro"}}],
                 "included":[{"type":"subscriptions","id":"subscription-1",
                              "attributes":{"productId":"pro.monthly"}}]}
                """
            case ("GET", "/v1/subscriptionGroups/group-1/versions"):
                body = #"{"data":[{"type":"subscriptionGroupVersions","id":"group-version-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"}}]}"#
            case ("GET", "/v1/subscriptions/subscription-1/versions"):
                body = #"{"data":[{"type":"subscriptionVersions","id":"subscription-version-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"}}]}"#
            default:
                body = #"{"data":[]}"#
            }

        case .releaseExistingDraft:
            body = method == "GET" && path == "/v1/reviewSubmissions"
                ? #"{"data":[{"type":"reviewSubmissions","id":"submission-draft","attributes":{"state":"READY_FOR_REVIEW","platform":"IOS"}}]}"#
                : #"{"data":{}}"#

        case .encryption:
            body = method == "POST" && path == "/v1/appEncryptionDeclarations"
                ? #"{"data":{"type":"appEncryptionDeclarations","id":"declaration-1"}}"#
                : #"{"data":{}}"#

        case .subscriptionLocales:
            body = method == "GET"
                ? """
                  {"data":[
                    {"type":"subscriptionLocalizations","id":"locale-en","attributes":{"locale":"en-US"}},
                    {"type":"subscriptionLocalizations","id":"locale-fr","attributes":{"locale":"fr-FR"}}
                  ]}
                """
                : #"{"data":{}}"#

        case .groupLocales:
            body = method == "GET"
                ? """
                  {"data":[
                    {"type":"subscriptionGroupLocalizations","id":"group-locale-en","attributes":{"locale":"en-US"}},
                    {"type":"subscriptionGroupLocalizations","id":"group-locale-fr","attributes":{"locale":"fr-FR"}}
                  ]}
                  """
                : #"{"data":{}}"#

        case .availabilityExisting, .availabilityMissing:
            switch (method, path) {
            case ("GET", "/v1/apps/app-1/subscriptionGroups"):
                body = #"{"data":[{"type":"subscriptionGroups","id":"group-1","attributes":{"referenceName":"Pro"}}]}"#
            case ("GET", "/v1/subscriptionGroups/group-1/subscriptions"):
                body = #"{"data":[{"type":"subscriptions","id":"subscription-1","attributes":{"productId":"pro.monthly"}}]}"#
            case ("GET", "/v1/subscriptions/subscription-1/planAvailabilities"):
                body = Self.scenario == .availabilityExisting
                    ? #"{"data":[{"type":"subscriptionPlanAvailabilities","id":"availability-1","attributes":{"planType":"MONTHLY"}}]}"#
                    : #"{"data":[]}"#
            default:
                body = #"{"data":{}}"#
            }

        case .subscriptionCatalog:
            switch (method, path) {
            case ("GET", "/v1/apps/app-1/subscriptionGroups"):
                body = """
                {"data":[{"type":"subscriptionGroups","id":"group-1","attributes":{"referenceName":"Pro"}}],
                 "included":[{"type":"subscriptions","id":"subscription-1",
                              "attributes":{"productId":"pro.monthly","subscriptionPeriod":"ONE_MONTH"}}]}
                """
            case ("GET", "/v1/subscriptions/subscription-1/versions"):
                body = #"{"data":[{"type":"subscriptionVersions","id":"subscription-version-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"}}]}"#
            case ("GET", "/v1/subscriptionVersions/subscription-version-1/localizations"):
                body = #"{"data":[]}"#
            case ("GET", "/v1/subscriptions/subscription-1/planAvailabilities"):
                body = """
                {"data":[
                  {"type":"subscriptionPlanAvailabilities","id":"monthly","attributes":{"planType":"MONTHLY"},
                   "relationships":{"availableTerritories":{"data":[{"type":"territories","id":"USA"}]}}},
                  {"type":"subscriptionPlanAvailabilities","id":"upfront","attributes":{"planType":"UPFRONT"},
                   "relationships":{"availableTerritories":{"data":[{"type":"territories","id":"DEU"}]}}}
                ]}
                """
            default:
                body = #"{"data":[]}"#
            }

        case .subscriptionDraftExisting, .subscriptionDraftMissing,
             .subscriptionDraftInReview:
            switch (method, path) {
            case ("GET", "/v1/apps/app-1/subscriptionGroups"):
                body = #"{"data":[{"type":"subscriptionGroups","id":"group-1","attributes":{"referenceName":"Pro"}}]}"#
            case ("GET", "/v1/subscriptionGroups/group-1/subscriptions"):
                body = #"{"data":[{"type":"subscriptions","id":"subscription-1","attributes":{"productId":"pro.monthly"}}]}"#
            case ("GET", "/v1/subscriptions/subscription-1/versions"):
                switch Self.scenario {
                case .subscriptionDraftExisting:
                    body = #"{"data":[{"type":"subscriptionVersions","id":"subscription-version-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"}}]}"#
                case .subscriptionDraftInReview:
                    body = #"{"data":[{"type":"subscriptionVersions","id":"subscription-version-1","attributes":{"version":1,"state":"IN_REVIEW"}}]}"#
                default:
                    body = #"{"data":[]}"#
                }
            case ("POST", "/v1/subscriptionVersions"):
                body = #"{"data":{"type":"subscriptionVersions","id":"subscription-version-new","attributes":{"version":2,"state":"PREPARE_FOR_SUBMISSION"}}}"#
            case ("GET", "/v1/subscriptionVersions/subscription-version-1/localizations"),
                 ("GET", "/v1/subscriptionVersions/subscription-version-new/localizations"):
                body = #"{"data":[{"type":"subscriptionLocalizations","id":"locale-fr","attributes":{"locale":"fr-FR","name":"Ancien"}}]}"#
            default:
                body = #"{"data":{}}"#
            }
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func correctionAPI(_ scenario: CorrectionStubProtocol.Scenario) -> StoreAPI {
    CorrectionStubProtocol.scenario = scenario
    CorrectionStubProtocol.log = CorrectionCallLog()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CorrectionStubProtocol.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                    session: URLSession(configuration: configuration))
}

private func correctionRunner(_ scenario: CorrectionStubProtocol.Scenario,
                              manifest: Manifest, actual: ActualState = ActualState()) -> Runner {
    CorrectionStubProtocol.scenario = scenario
    CorrectionStubProtocol.log = CorrectionCallLog()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CorrectionStubProtocol.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    var manifest = manifest
    manifest.apps.apple?.appId = "app-1"
    return Runner(plan: PlanResult(), manifest: manifest, actual: actual, root: nil,
                  credentials: StoreCredentials(apple: credential), dryRun: false,
                  access: GrantAll(), session: URLSession(configuration: configuration),
                  emit: { _ in })
}

private func relationship(_ name: String, in call: CorrectionCallLog.Call,
                          type: String, id: String) -> Bool {
    guard let data = call.body["data"] as? [String: Any],
          let relationships = data["relationships"] as? [String: Any],
          let relationship = relationships[name] as? [String: Any],
          let target = relationship["data"] as? [String: Any],
          let actualType = target["type"] as? String,
          let actualID = target["id"] as? String else { return false }
    return actualType == type && actualID == id
}

@Suite(.serialized)
struct AppleAPICorrectionTests {
    @Test func creatingAndReplacingAReviewReplyUseTheSamePostWithAReviewRelationship()
        async throws {
        let client = AppleActionsClient(api: correctionAPI(.reviews))

        _ = try await client.replyToReview(reviewId: "review-1", text: "  Thank you.  ")
        _ = try await client.replyToReview(reviewId: "review-1", text: "Updated reply")

        let calls = CorrectionStubProtocol.log.all
        #expect(calls.count == 2)
        #expect(calls.allSatisfy {
            $0.method == "POST" && $0.path == "/v1/customerReviewResponses"
        })
        #expect(calls.allSatisfy {
            relationship("review", in: $0, type: "customerReviews", id: "review-1")
        })
        #expect(!calls.contains { $0.method == "DELETE" })
    }

    @Test func purchaseCatalogReadsTheSelectedVersionLocalizations() async throws {
        let catalog = AppleCatalogClient(api: correctionAPI(.purchase))

        let products = try await catalog.purchases(appID: "app-1", productIds: ["pro"])

        #expect(products["pro"]?.locales["en-US"]?.name == "Pro")
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "GET"
                && $0.path == "/v1/inAppPurchaseVersions/purchase-version-1/localizations"
        })
        #expect(!CorrectionStubProtocol.log.all.contains {
            $0.path.hasSuffix("/inAppPurchaseLocalizations")
        })
    }

    @Test func reviewSubmissionItemsUseVersionRelationshipsAndIds() async throws {
        let client = ReleaseClient(api: correctionAPI(.release), access: GrantAll())

        _ = try await client.releaseApple(appID: "app-1", platform: "IOS",
                                          versionID: "app-version-1")

        let items = CorrectionStubProtocol.log.all.filter {
            $0.method == "POST" && $0.path == "/v1/reviewSubmissionItems"
        }
        #expect(items.contains {
            relationship("inAppPurchaseVersion", in: $0,
                         type: "inAppPurchaseVersions", id: "purchase-version-1")
        })
        #expect(items.contains {
            relationship("subscriptionGroupVersion", in: $0,
                         type: "subscriptionGroupVersions", id: "group-version-1")
        })
        #expect(items.contains {
            relationship("subscriptionVersion", in: $0,
                         type: "subscriptionVersions", id: "subscription-version-1")
        })
        #expect(!CorrectionStubProtocol.log.all.contains {
            $0.path == "/v1/subscriptionSubmissions"
                || $0.path == "/v1/subscriptionGroupSubmissions"
        })
    }

    @Test func releaseResumesTheDraftSubmissionThatAlreadyHoldsTheBuild() async throws {
        let client = ReleaseClient(api: correctionAPI(.releaseExistingDraft), access: GrantAll())

        let id = try await client.releaseApple(appID: "app-1", platform: "IOS",
                                               versionID: "app-version-1")

        #expect(id == "submission-draft")
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "PATCH" && $0.path == "/v1/reviewSubmissions/submission-draft"
        })
        #expect(!CorrectionStubProtocol.log.all.contains {
            $0.method == "POST" && $0.path == "/v1/reviewSubmissions"
        })
    }

    @Test func encryptionDeclarationAttachesByPatchingTheBuild() async throws {
        var manifest = appleManifest()
        manifest.review = Manifest.Review(usesNonExemptEncryption: true)
        manifest.review?.encryption = Manifest.Encryption(exempt: false)
        var actual = ActualState()
        actual.apple = ActualState.Apple()
        actual.apple?.attachedBuildId = "build-1"
        let runner = correctionRunner(.encryption, manifest: manifest, actual: actual)

        try await runner.appleEncryptionDeclaration()

        let attachment = try #require(CorrectionStubProtocol.log.all.first {
            $0.method == "PATCH" && $0.path == "/v1/builds/build-1"
        })
        #expect(relationship("appEncryptionDeclaration", in: attachment,
                             type: "appEncryptionDeclarations", id: "declaration-1"))
        #expect(!CorrectionStubProtocol.log.all.contains { $0.path.contains("relationships/builds") })
    }

    @Test func versionedSubscriptionWritesDeleteDroppedLocales() async throws {
        let client = AppleSubscriptionVersionsClient(api: correctionAPI(.subscriptionLocales))

        try await client.writeLocalizations(
            kind: .subscription, draftID: "subscription-version-1",
            locales: ["en-US": (name: "Pro", description: "Full access"),
                      "de-DE": (name: "Pro", description: "Vollzugriff")],
            deleteMissing: true)

        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "PATCH" && $0.path == "/v2/subscriptionLocalizations/locale-en"
        })
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "DELETE" && $0.path == "/v2/subscriptionLocalizations/locale-fr"
        })
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "POST" && $0.path == "/v2/subscriptionLocalizations"
        })
    }

    @Test func versionedGroupWritesUseV2CreatePatchAndDelete() async throws {
        let client = AppleSubscriptionVersionsClient(api: correctionAPI(.groupLocales))

        try await client.writeLocalizations(
            kind: .group, draftID: "group-version-1",
            locales: ["en-US": (name: "Pro", description: nil),
                      "de-DE": (name: "Pro", description: nil)],
            deleteMissing: true)

        let calls = CorrectionStubProtocol.log.all
        #expect(calls.contains {
            $0.method == "PATCH"
                && $0.path == "/v2/subscriptionGroupLocalizations/group-locale-en"
        })
        #expect(calls.contains {
            $0.method == "POST" && $0.path == "/v2/subscriptionGroupLocalizations"
        })
        #expect(calls.contains {
            $0.method == "DELETE"
                && $0.path == "/v2/subscriptionGroupLocalizations/group-locale-fr"
        })
    }

    @Test func planAvailabilityPatchesTheMatchingTypeAndDoesNotDuplicateOnASecondApply()
        async throws {
        var manifest = appleManifest()
        manifest.subscriptions = [Manifest.SubscriptionGroup(
            groupId: "Pro", groupName: "Pro",
            plans: [Manifest.SubscriptionGroup.Plan(
                id: "pro.monthly", duration: "P1M",
                availableTerritories: ["USA", "DEU"], applePlanType: .monthly)])]
        let runner = correctionRunner(.availabilityExisting, manifest: manifest)

        try await runner.appleSubscriptions()
        try await runner.appleSubscriptions()

        let calls = CorrectionStubProtocol.log.all
        #expect(calls.filter {
            $0.method == "PATCH"
                && $0.path == "/v1/subscriptionPlanAvailabilities/availability-1"
        }.count == 2)
        #expect(!calls.contains {
            $0.method == "POST" && $0.path == "/v1/subscriptionPlanAvailabilities"
        })
    }

    @Test func planAvailabilityPostsWhenTheRequestedTypeDoesNotExist() async throws {
        var manifest = appleManifest()
        manifest.subscriptions = [Manifest.SubscriptionGroup(
            groupId: "Pro", groupName: "Pro",
            plans: [Manifest.SubscriptionGroup.Plan(
                id: "pro.monthly", duration: "P1M",
                availableTerritories: ["USA"], applePlanType: .monthly)])]
        let runner = correctionRunner(.availabilityMissing, manifest: manifest)

        try await runner.appleSubscriptions()

        let call = try #require(CorrectionStubProtocol.log.all.first {
            $0.method == "POST" && $0.path == "/v1/subscriptionPlanAvailabilities"
        })
        let data = try #require(call.body["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes["planType"] as? String == "MONTHLY")
        #expect(relationship("subscription", in: call,
                             type: "subscriptions", id: "subscription-1"))
    }

    @Test func catalogKeepsTerritoriesSeparatedByPlanType() async throws {
        let catalog = AppleCatalogClient(api: correctionAPI(.subscriptionCatalog))

        let result = try await catalog.subscriptions(
            appID: "app-1", productIds: ["pro.monthly"])
        let product = try #require(result.products["pro.monthly"])

        #expect(product.subscriptionPlanTerritories[.monthly] == ["USA"])
        #expect(product.subscriptionPlanTerritories[.upfront] == ["DEU"])
        #expect(product.subscriptionPlanAvailabilityRead)
    }

    @Test func applePlanTypesDecodeAndMissingTypeValidationIsAppleOnly() throws {
        let monthly = try ManifestFile.decode("""
        version: 1
        apps:
          apple:
            appId: app-1
            platforms: [IOS]
            bundleId: com.example.app
        subscriptions:
          - groupId: pro
            plans:
              - id: pro.monthly
                duration: P1M
                applePlanType: MONTHLY
        """)
        let upfront = try ManifestFile.decode("""
        version: 1
        apps:
          apple:
            appId: app-1
            platforms: [IOS]
            bundleId: com.example.app
        subscriptions:
          - groupId: pro
            plans:
              - id: pro.upfront
                duration: P1Y
                applePlanType: UPFRONT
        """)
        #expect(monthly.subscriptions?.first?.plans.first?.applePlanType == .monthly)
        #expect(upfront.subscriptions?.first?.plans.first?.applePlanType == .upfront)

        var missing = googleManifest()
        missing.subscriptions = [Manifest.SubscriptionGroup(
            groupId: "pro", plans: [Manifest.SubscriptionGroup.Plan(
                id: "pro.monthly", duration: "P1M", basePlanId: "monthly",
                availableTerritories: ["USA"])])]
        let appleFindings = Validator.findings(Planner.Input(
            manifest: missing, actual: ActualState(), stores: [.apple]))
        let googleFindings = Validator.findings(Planner.Input(
            manifest: missing, actual: ActualState(), stores: [.google]))
        #expect(appleFindings.contains { $0.id == "money.applePlanType.pro.monthly" })
        #expect(!googleFindings.contains { $0.id == "money.applePlanType.pro.monthly" })
    }

    @Test func automaticSubscriptionApplyReusesCreatesAndRefusesVersions() async throws {
        func manifest() -> Manifest {
            var value = appleManifest()
            value.subscriptions = [Manifest.SubscriptionGroup(
                groupId: "Pro", groupName: "Pro",
                plans: [Manifest.SubscriptionGroup.Plan(
                    id: "pro.monthly", duration: "P1M",
                    locales: ["en-US": Manifest.ProductLocale(
                        name: "Pro", description: "Full access")])])]
            return value
        }

        let existing = correctionRunner(.subscriptionDraftExisting, manifest: manifest())
        try await existing.appleSubscriptions()
        #expect(!CorrectionStubProtocol.log.all.contains {
            $0.method == "POST" && $0.path == "/v1/subscriptionVersions"
        })
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "DELETE" && $0.path == "/v2/subscriptionLocalizations/locale-fr"
        })

        let missing = correctionRunner(.subscriptionDraftMissing, manifest: manifest())
        try await missing.appleSubscriptions()
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "POST" && $0.path == "/v1/subscriptionVersions"
        })

        let inReview = correctionRunner(.subscriptionDraftInReview, manifest: manifest())
        do {
            try await inReview.appleSubscriptions()
            Issue.record("Metadata already in review should not be mutated.")
        } catch ConnectionError.http(let status, _) {
            #expect(status == 409)
        }
        #expect(!CorrectionStubProtocol.log.all.contains {
            ($0.method == "POST" || $0.method == "PATCH" || $0.method == "DELETE")
                && $0.path.hasPrefix("/v2/subscriptionLocalizations")
        })
    }

    @Test func deprecatedApplePathsAreAbsentAndPlanAvailabilityIsExplicit() throws {
        let apply = try source("Sources/SubmitKit/Run/AppleApply.swift")
        let subscriptions = try source("Sources/SubmitKit/Run/AppleSubscriptions.swift")
        let catalog = try source("Sources/SubmitKit/Clients/AppleCatalogClient.swift")
        let release = try source("Sources/SubmitKit/Release/ReleaseClient.swift")
        let manifest = try source("Sources/SubmitKit/Manifest/Manifest.swift")
        let schema = try source("Sources/SubmitKit/Resources/store.schema.json")

        #expect(apply.contains("/localizations?limit=200"))
        #expect(!apply.contains("/inAppPurchaseLocalizations?limit=200"))
        #expect(!catalog.contains("/inAppPurchaseLocalizations?limit=200"))
        #expect(!subscriptions.contains("/v1/subscriptionAvailabilities"))
        #expect(!subscriptions.contains("/v1/subscriptionLocalizations"))
        #expect(!subscriptions.contains("/v1/subscriptionGroupLocalizations"))
        #expect(!release.contains("/v1/subscriptionSubmissions"))
        #expect(!release.contains("/v1/subscriptionGroupSubmissions"))
        #expect(manifest.contains("applePlanType"))
        #expect(schema.contains("applePlanType"))
        #expect(schema.contains("MONTHLY"))
        #expect(schema.contains("UPFRONT"))
        #expect(subscriptions.contains("/planAvailabilities"))
        #expect(subscriptions.contains("/v1/subscriptionPlanAvailabilities"))
    }

    /// `appAvailabilities` takes CREATE and GET_INSTANCE and nothing else, so
    /// the apply that patched an app which already held an availability got a
    /// 403 back. The app read that 403 as a role its key was denied and told
    /// the developer to check the key, which sent them after a permission that
    /// was never missing.
    @Test func availabilityAlwaysCreatesBecauseTheResourceTakesNoUpdate() async throws {
        var manifest = appleManifest()
        manifest.pricing = Manifest.Pricing(
            base: Price(amount: 0, currency: "USD"),
            territories: [Manifest.TerritoryAvailability(territory: "USA")])
        var actual = ActualState()
        actual.apple = ActualState.Apple()
        let runner = correctionRunner(.availabilityExisting, manifest: manifest,
                                      actual: actual)

        try await runner.appleAvailability()

        let calls = CorrectionStubProtocol.log.all.filter {
            $0.path.hasPrefix("/v2/appAvailabilities")
        }
        #expect(calls.allSatisfy { $0.method == "POST" })
        #expect(calls.contains { $0.path == "/v2/appAvailabilities" })
    }

    /// The drop deletes every localization the manifest does not name, and an
    /// absent `locales` key named none of them. So an apply that touched a
    /// purchase for any other reason stripped the names off products the
    /// developer never asked it to manage.
    @Test func aPurchaseThatNamesNoLocaleKeepsTheOnesAppleHolds() async throws {
        var manifest = appleManifest()
        manifest.purchases = [Manifest.Purchase(id: "pro", kind: .nonConsumable)]
        let runner = correctionRunner(.purchase, manifest: manifest)

        try await runner.applePurchases()

        let calls = CorrectionStubProtocol.log.all
        #expect(!calls.contains { $0.method == "DELETE" })
        #expect(!calls.contains {
            $0.path == "/v1/inAppPurchaseVersions/purchase-version-1/localizations"
        })
    }

    /// And the drop still runs for a purchase that does name its locales,
    /// because the guard above is about an absent key and not about the drop.
    @Test func aPurchaseThatNamesItsLocalesStillLosesTheOnesItDropped() async throws {
        var manifest = appleManifest()
        manifest.purchases = [Manifest.Purchase(
            id: "pro", kind: .nonConsumable,
            locales: ["de-DE": Manifest.ProductLocale(name: "Pro")])]
        let runner = correctionRunner(.purchase, manifest: manifest)

        try await runner.applePurchases()

        // The store holds en-US and the manifest names de-DE only.
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "DELETE"
                && $0.path == "/v2/inAppPurchaseLocalizations/purchase-locale-1"
        })
    }

    /// The plan and the apply have to agree about which purchases changed. The
    /// plan claimed a purchase managed its localizations whatever the manifest
    /// said, so an empty wanted set met the names Apple holds, every purchase
    /// read as changed, and the row never went away.
    @Test func aPurchaseThatNamesNoLocaleIsNotAChange() {
        var manifest = appleManifest()
        manifest.purchases = [Manifest.Purchase(id: "pro", kind: .nonConsumable)]
        var apple = ActualState.Apple()
        apple.purchaseIds = ["pro"]
        var held = ActualState.Apple.CatalogProduct()
        held.productId = "pro"
        held.localesRead = true
        var name = ActualState.Apple.CatalogProduct.ProductLocale()
        name.name = "Pro"
        name.description = "Full access"
        held.locales = ["en-US": name]
        apple.catalog = ["pro": held]

        let diff = Planner.appleCatalogDiff(manifest, apple, kind: .purchases)
        #expect(diff.changes.isEmpty)
    }
}

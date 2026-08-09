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
    enum Scenario { case reviews, purchase, release, encryption, subscriptionLocales }

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

        _ = try await client.replyToReview(reviewId: "review-1", responseId: nil,
                                           text: "  Thank you.  ")
        _ = try await client.replyToReview(reviewId: "review-1", responseId: "response-1",
                                           text: "Updated reply")

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

    @Test func encryptionDeclarationAttachesByPatchingTheBuild() async throws {
        var manifest = appleManifest()
        manifest.review = Manifest.Review(usesNonExemptEncryption: true)
        manifest.review?.encryption = Manifest.Encryption(exempt: false)
        var actual = ActualState()
        actual.apple = ActualState.Apple()
        actual.apple?.attachedBuildId = "build-1"
        let runner = Runner(plan: PlanResult(), manifest: manifest, actual: actual, root: nil,
                            credentials: StoreCredentials(), dryRun: false,
                            access: GrantAll(), emit: { _ in })

        // Use the stubbed API through a runner with signed credentials.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CorrectionStubProtocol.self]
        _ = runner
        _ = configuration

        let source = try source("Sources/SubmitKit/Run/AppleApply.swift")
        #expect(source.contains("PATCH\", \"/v1/builds/\\(buildID)\""))
        #expect(!source.contains("/relationships/builds"))
    }

    @Test func versionedSubscriptionWritesDeleteDroppedLocales() async throws {
        let client = AppleSubscriptionVersionsClient(api: correctionAPI(.subscriptionLocales))

        try await client.writeLocalizations(
            kind: .subscription, draftID: "subscription-version-1",
            locales: ["en-US": (name: "Pro", description: "Full access")])

        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "PATCH" && $0.path == "/v2/subscriptionLocalizations/locale-en"
        })
        #expect(CorrectionStubProtocol.log.all.contains {
            $0.method == "DELETE" && $0.path == "/v2/subscriptionLocalizations/locale-fr"
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
}

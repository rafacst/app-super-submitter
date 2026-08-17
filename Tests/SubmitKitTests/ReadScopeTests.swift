import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// Records every path the reader asks for and answers each one with an empty
/// document, so the test is about the requests and nothing else.
private final class ScopeProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var seen: [String] = []
    private static let lock = NSLock()

    static func start() { lock.withLock { seen = [] } }
    static var paths: [String] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url.path + (url.query.map { "?\($0)" } ?? "")) }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A save of one tab reads one tab's area of the store.
///
/// Saving the Details of an app asked App Store Connect about every in-app
/// purchase, every subscription and its group, the price ladder, the marketing
/// resources, TestFlight and the Game Center configuration: forty requests to
/// build a comparison that only the listing rows were ever read from. The
/// developer watching the log saw the app asking about a tab they had not
/// opened.
///
/// The plan still reads all of it, because the plan compares all of it. These
/// hold the line between the two.
@Suite(.serialized)
struct ReadScopeTests {
    private func api() -> StoreAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScopeProtocol.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                        session: URLSession(configuration: configuration))
    }

    private func paths(_ areas: StateReader.Areas) async throws -> [String] {
        ScopeProtocol.start()
        _ = try await StateReader(api: api()).readApple(
            appID: "1", purchaseIds: ["tip.small"], subscriptionIds: ["pro.monthly"],
            groupNames: ["Pro"], areas: areas)
        return ScopeProtocol.paths
    }

    /// The catalog, in the words Apple's own routes use.
    private static let catalog = ["inAppPurchase", "subscription"]
    private static let marketing = ["appCustomProductPages", "appStoreVersionExperiments",
                                    "appEvents", "appClips"]

    @Test func aListingSaveAsksAboutNoPurchaseAndNoSubscription() async throws {
        let asked = try await paths([])

        let money = asked.filter { path in
            Self.catalog.contains { path.localizedCaseInsensitiveContains($0) }
        }
        #expect(money.isEmpty,
                "a save of the listing asked about the catalog: \(money.joined(separator: ", "))")
    }

    @Test func aListingSaveAsksAboutNoMarketingResourceOrGameCenter() async throws {
        let asked = try await paths([])

        let extras = asked.filter { path in
            (Self.marketing + ["gameCenter", "betaGroups", "betaAppReviewDetail"])
                .contains { path.localizedCaseInsensitiveContains($0) }
        }
        #expect(extras.isEmpty,
                "a save of the listing asked outside its tab: \(extras.joined(separator: ", "))")
    }

    /// The listing rows still need what every diff needs, or the save would
    /// write a description into a version it never found.
    @Test func aListingSaveStillReadsTheAppAndItsVersion() async throws {
        let asked = try await paths([])

        #expect(asked.contains { $0.contains("/appInfos?") })
        #expect(asked.contains { $0.contains("/appStoreVersions?") })
        #expect(asked.contains { $0.contains("/v1/appCategories?") })
    }

    /// The plan's own read is unchanged, and it is the one that fills the
    /// column every tab draws.
    @Test func thePlanReadStillAsksAboutEverything() async throws {
        let asked = try await paths(.all)

        for word in Self.catalog + Self.marketing + ["gameCenter"] {
            #expect(asked.contains { $0.localizedCaseInsensitiveContains(word) },
                    "the full read stopped asking about \(word)")
        }
    }

    /// Money reads the catalog and Availability does not, so the two tabs are
    /// the proof that the scope is per tab and not one switch.
    @Test func onlyTheTabsThatOwnTheCatalogRead() async throws {
        let money = try await paths([.catalog, .pricing])
        let availability = try await paths(.pricing)

        #expect(money.contains { $0.localizedCaseInsensitiveContains("inAppPurchase") })
        #expect(!availability.contains { $0.localizedCaseInsensitiveContains("inAppPurchase") })
        // Both price, so both read the ladder.
        for asked in [money, availability] {
            #expect(asked.contains { $0.contains("PricePoint") || $0.contains("pricePoint") })
        }
    }
}

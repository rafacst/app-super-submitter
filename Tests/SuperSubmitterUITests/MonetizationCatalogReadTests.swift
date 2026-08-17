import CryptoKit
import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// Answers the App Store Connect reads the Monetization tab makes.
///
/// `URLSession.shared` is what `readOnlyAPI` uses, so the stub registers
/// globally and unregisters at the end of each test.
private final class MoneyStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static let lock = NSLock()
    nonisolated(unsafe) static var routes: [String: String] = [:]
    nonisolated(unsafe) static var asked: [String] = []
    /// Paths whose read fails, to prove a partial answer stays partial.
    nonisolated(unsafe) static var refuse: Set<String> = []

    static func configure(_ routes: [String: String], refuse: Set<String> = []) {
        lock.withLock {
            self.routes = routes
            self.refuse = refuse
            asked = []
        }
    }

    static func wasAsked(_ fragment: String) -> Bool {
        lock.withLock { asked.contains { $0.contains(fragment) } }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.appstoreconnect.apple.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = (request.url?.path ?? "") + (request.url?.query.map { "?\($0)" } ?? "")
        let body: String?
        let refused: Bool
        (body, refused) = Self.lock.withLock {
            Self.asked.append(path)
            let refused = Self.refuse.contains { path.contains($0) }
            let match = Self.routes.filter { path.contains($0.key) }
                .max { $0.key.count < $1.key.count }?.value
            return (match, refused)
        }
        // 403 and not 500: a server error is retried with backoff, which
        // makes a test about one failed read take half a minute.
        let status = refused ? 403 : (body == nil ? 404 : 200)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Opening Monetization must be enough on its own.
///
/// The tab draws prices, "Approved" and "Will add" off
/// `actualState.apple.catalog`, and `loadStoreMonetization` filled the manifest
/// and never that map. Only the Summary read filled it, so a developer who
/// opened Monetization first was shown an empty catalog and every approved
/// product read as one the apply was about to create.
@MainActor
@Suite(.serialized) struct MonetizationCatalogReadTests {

    private func state(appID: String = "6001") throws -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.setStore(.apple, enabled: true)
        state.manifest.setAppleApp(appID: appID, bundleID: "com.example.app", platforms: [.ios])
        // `credentials` is derived from these, so the key is set the way the
        // Stores tab sets it.
        state.appleKeyID = "ABC123DEFG"
        state.appleIssuerID = "issuer"
        state.applePrivateKeyPEM = P256.Signing.PrivateKey().pemRepresentation
        return state
    }

    /// Everything the two list reads answer, in the shape Apple sends.
    private var liveCatalog: [String: String] {
        [
            "/inAppPurchasesV2": #"""
            {"data":[{"type":"inAppPurchases","id":"p1",
              "attributes":{"productId":"com.example.tip","name":"Tip Jar",
                            "inAppPurchaseType":"CONSUMABLE","state":"APPROVED"}}]}
            """#,
            "/subscriptionGroups": #"""
            {"data":[{"type":"subscriptionGroups","id":"g1",
               "attributes":{"referenceName":"Premium"},
               "relationships":{"subscriptions":{"data":[
                 {"type":"subscriptions","id":"s1"}]}}}],
             "included":[{"type":"subscriptions","id":"s1",
               "attributes":{"productId":"com.example.monthly","name":"Monthly",
                             "subscriptionPeriod":"ONE_MONTH","state":"APPROVED"}}]}
            """#,
            "/v2/inAppPurchases/p1/iapPriceSchedule": #"""
            {"data":{"id":"sched"},
             "included":[
              {"type":"inAppPurchasePrices","id":"pr1",
               "attributes":{"startDate":null,"endDate":null},
               "relationships":{"inAppPurchasePricePoint":{"data":{"id":"pt1"}}}},
              {"type":"inAppPurchasePricePoints","id":"pt1",
               "attributes":{"customerPrice":"4.99"},
               "relationships":{"territory":{"data":{"id":"USA"}}}},
              {"type":"territories","id":"USA","attributes":{"currency":"USD"}}]}
            """#,
            "/v1/subscriptions/s1/prices": #"""
            {"data":[{"type":"subscriptionPrices","id":"sp1",
               "attributes":{"startDate":null},
               "relationships":{"subscriptionPricePoint":{"data":{"id":"spt1"}},
                                "territory":{"data":{"id":"USA"}}}}],
             "included":[
              {"type":"subscriptionPricePoints","id":"spt1",
               "attributes":{"customerPrice":"9.99"}},
              {"type":"territories","id":"USA","attributes":{"currency":"USD"}}]}
            """#,
        ]
    }

    /// The whole report, end to end: open Monetization on a published app and
    /// every existing product is present, priced, and not called new.
    @Test func openingMonetizationAloneShowsWhatTheStoreHolds() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog)
        let state = try state()

        await state.loadStoreMonetization()

        // The catalog is filled, and it is marked as read.
        let apple = try #require(state.actualState.apple)
        #expect(apple.catalogRead)
        #expect(apple.catalog["com.example.tip"]?.state == "APPROVED")
        #expect(apple.catalog["com.example.monthly"]?.state == "APPROVED")
        #expect(apple.purchaseIds.contains("com.example.tip"))
        #expect(apple.subscriptionIds.contains("com.example.monthly"))
        #expect(apple.subscriptionGroupNames.contains("Premium"))

        // And the tab therefore says the true thing about each of them.
        #expect(MoneyTab.productStatus("com.example.tip", stores: [.apple],
                                       actual: state.actualState).text == "Approved")
        #expect(MoneyTab.productStatus("com.example.monthly", stores: [.apple],
                                       actual: state.actualState).text == "Approved")
    }

    /// The subscription arrives under its group, with its duration and the
    /// price of the base territory.
    @Test func anApprovedMonthlyArrivesInsideItsGroupWithADurationAndAPrice() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog)
        let state = try state()

        await state.loadStoreMonetization()

        // In `store.yaml`, under the group Apple holds it in.
        let group = try #require(state.manifest.subscriptions?.first)
        #expect(group.groupName == "Premium")
        #expect(group.plans.map(\.id) == ["com.example.monthly"])
        #expect(group.plans.first?.duration == "P1M")

        // And on the row, as a duration and a price.
        #expect(MoneyTab.storeSummary("com.example.monthly", store: .apple,
                                      actual: state.actualState,
                                      territory: "USA") == "1 month · 9.99")
    }

    /// The one-time purchase carries its price too.
    @Test func anExistingPurchaseCarriesItsCurrentPrice() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog)
        let state = try state()

        await state.loadStoreMonetization()

        #expect(state.actualState.apple?.catalog["com.example.tip"]?.prices["USA"]
                == "4.99")
    }

    /// A failed list read leaves the flag false, so the tab says nobody
    /// answered instead of claiming the store holds nothing.
    @Test func aFailedCatalogReadIsNotAnEmptyCatalog() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog, refuse: ["/inAppPurchasesV2"])
        let state = try state()

        await state.loadStoreMonetization()

        #expect(state.actualState.apple?.catalogRead != true)
        #expect(MoneyTab.productStatus("com.example.tip", stores: [.apple],
                                       actual: state.actualState).text == "Not read yet")
    }

    /// One product's detail failing costs that detail and not the rest of the
    /// catalog. The list read is what proves existence, and it answered.
    @Test func oneFailedProductDetailDoesNotEraseTheRest() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog, refuse: ["iapPriceSchedule"])
        let state = try state()

        await state.loadStoreMonetization()

        let apple = try #require(state.actualState.apple)
        #expect(apple.catalogRead)
        // The purchase is still known to exist, with no price against it.
        #expect(apple.catalog["com.example.tip"]?.state == "APPROVED")
        #expect(apple.catalog["com.example.tip"]?.prices.isEmpty == true)
        #expect(MoneyTab.productStatus("com.example.tip", stores: [.apple],
                                       actual: state.actualState).text != "Will add")
        // And the subscription beside it is untouched.
        #expect(apple.catalog["com.example.monthly"]?.prices["USA"] == "9.99")
    }

    /// State that is already fresh is not read again. The Summary read fills
    /// the same map from the same client.
    @Test func aFreshCatalogIsNotReadTwice() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog)
        let state = try state()

        var apple = ActualState.Apple()
        apple.catalogRead = true
        apple.catalog["com.example.tip"] = {
            var product = ActualState.Apple.CatalogProduct()
            product.productId = "com.example.tip"
            product.state = "APPROVED"
            return product
        }()
        state.actualState.apple = apple

        await state.loadStoreMonetization()

        #expect(!MoneyStubProtocol.wasAsked("iapPriceSchedule"))
        #expect(state.actualState.apple?.catalog["com.example.tip"]?.state == "APPROVED")
    }

    /// An app switch clears the catalog, so it must also clear the mark that
    /// stopped the tab from asking for that catalog again.
    @Test func switchingAppsLetsMonetizationReadAgain() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog)
        let state = try state()

        await state.loadStoreMonetization()
        #expect(state.actualState.apple?.catalogRead == true)

        state.resetRunState()
        #expect(state.actualState.apple == nil)
        await state.loadStoreMonetization()

        #expect(state.actualState.apple?.catalogRead == true)
        #expect(state.actualState.apple?.catalog["com.example.tip"]?.state == "APPROVED")
    }

    /// The read fills what `store.yaml` leaves blank and never lands on top of
    /// what the developer wrote.
    @Test func theReadNeverOverwritesTheDevelopersOwnText() async throws {
        URLProtocol.registerClass(MoneyStubProtocol.self)
        defer { URLProtocol.unregisterClass(MoneyStubProtocol.self) }
        MoneyStubProtocol.configure(liveCatalog)
        let state = try state()
        state.manifest.purchases = [Manifest.Purchase(id: "com.example.tip",
                                                      kind: .nonRenewing,
                                                      name: "My own name")]

        await state.loadStoreMonetization()

        #expect(state.manifest.purchases?.first?.name == "My own name")
        #expect(state.manifest.purchases?.first?.kind == .nonRenewing)
        // And the store's own answer is still available beside it.
        #expect(state.actualState.apple?.catalog["com.example.tip"]?.name == "Tip Jar")
    }
}

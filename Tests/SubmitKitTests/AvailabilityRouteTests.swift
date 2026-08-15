import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// App Store Connect splits the territory availability three ways and answers
/// an error for every route but the right one.
///
/// A `PATCH /v2/appAvailabilities/{id}` answers 403 and "Allowed operations
/// are: CREATE, GET_INSTANCE". A second `POST /v2/appAvailabilities` answers
/// 409 "already exists". An app that has ever been on sale holds one, so both
/// of those are the ordinary case and neither one writes a territory.

private final class AvailabilityStub: URLProtocol, @unchecked Sendable {
    struct Call { var method: String; var path: String; var query: String; var body: [String: Any] }

    nonisolated(unsafe) private static var calls: [Call] = []
    private static let lock = NSLock()
    /// False makes the app hold no availability yet, the create route.
    nonisolated(unsafe) static var holdsAvailability = true

    static func start(holding: Bool = true) {
        lock.withLock { calls = [] }
        holdsAvailability = holding
    }

    static var seen: [Call] { lock.withLock { calls } }

    static func patched(_ path: String) -> [String: Any]? {
        seen.first { $0.method == "PATCH" && $0.path == path }
            .flatMap { $0.body["data"] as? [String: Any] }
            .flatMap { $0["attributes"] as? [String: Any] }
    }

    /// One row, the way App Store Connect answers it.
    ///
    /// The country code is on the `territory` relationship, and Apple puts it
    /// there only for a request that asks for `include=territory`. Without the
    /// include the relationship is a pair of links and the row names no
    /// country at all, which is the answer the run has to survive reading.
    private static func row(_ id: String, _ code: String, available: Bool,
                            includesTerritory: Bool) -> String {
        let territory = includesTerritory
            ? #"{"data":{"id":"\#(code)","type":"territories"}}"#
            : #"{"links":{"self":"https://api.appstoreconnect.apple.com/v2/territoryAvailabilities/\#(id)/relationships/territory"}}"#
        return """
        {"id":"\(id)","type":"territoryAvailabilities",
         "attributes":{"available":\(available)},
         "relationships":{"territory":\(territory)}}
        """
    }

    /// BRA is off and USA is on, which is the state the manifest below changes.
    /// DEU sits on a second page, so a run that reads one page reports it as a
    /// country the App Store does not have.
    private static func territories(page: Int, includesTerritory: Bool) -> String {
        let next = #""links":{"next":"https://api.appstoreconnect.apple.com/v2/appAvailabilities/avail-1/territoryAvailabilities?limit=200&include=territory&cursor=page2"},"#
        return page == 1
            ? """
            {\(next)"data":[
              \(row("ta-bra", "BRA", available: false, includesTerritory: includesTerritory)),
              \(row("ta-usa", "USA", available: true, includesTerritory: includesTerritory))
            ]}
            """
            : """
            {"data":[
              \(row("ta-deu", "DEU", available: false, includesTerritory: includesTerritory))
            ]}
            """
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
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
        let query = url.query ?? ""
        Self.lock.withLock {
            Self.calls.append(Call(method: request.httpMethod ?? "",
                                   path: url.path, query: query, body: body))
        }

        let answer: String
        switch url.path {
        case "/v1/apps/app-1/appAvailabilityV2":
            answer = Self.holdsAvailability
                ? #"{"data":{"id":"avail-1","type":"appAvailabilities"}}"#
                : #"{"data":{}}"#
        case "/v2/appAvailabilities/avail-1/territoryAvailabilities":
            answer = Self.territories(page: query.contains("cursor=page2") ? 2 : 1,
                                      includesTerritory: query.contains("include=territory"))
        default:
            answer = #"{"data":{}}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func availabilityRunner(_ territories: [Manifest.TerritoryAvailability],
                                newTerritories: Bool? = nil,
                                heldAutoConvert: Bool? = nil) -> Runner {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AvailabilityStub.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    var manifest = appleManifest()
    manifest.apps.apple?.appId = "app-1"
    manifest.pricing = Manifest.Pricing(
        base: Price(amount: 0, currency: "USD"),
        appleNewTerritories: newTerritories, territories: territories)
    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.availableInNewTerritories = heldAutoConvert
    actual.apple = apple
    return Runner(plan: PlanResult(), manifest: manifest, actual: actual, root: nil,
                  credentials: StoreCredentials(apple: credential), dryRun: false,
                  access: GrantAll(),
                  session: URLSession(configuration: configuration), emit: { _ in })
}

@Suite(.serialized)
struct AvailabilityRouteTests {
    /// The one the developer hit. An app that already holds an availability
    /// takes no create at all.
    @Test func anAppThatHoldsAnAvailabilityIsNeverCreatedAgain() async throws {
        AvailabilityStub.start()
        let runner = availabilityRunner([
            Manifest.TerritoryAvailability(territory: "BRA", available: true),
        ])

        try await runner.appleAvailability()

        #expect(!AvailabilityStub.seen.contains {
            $0.method == "POST" && $0.path == "/v2/appAvailabilities"
        })
        #expect(!AvailabilityStub.seen.contains {
            $0.method == "PATCH" && $0.path.hasPrefix("/v2/appAvailabilities")
        })
        let written = try #require(
            AvailabilityStub.patched("/v1/territoryAvailabilities/ta-bra"))
        #expect(written["available"] as? Bool == true)
    }

    /// A territory that already answers what the manifest asks is not written.
    /// An app on sale everywhere holds 175 of these.
    @Test func aTerritoryThatAlreadyAgreesIsNotWritten() async throws {
        AvailabilityStub.start()
        let runner = availabilityRunner([
            Manifest.TerritoryAvailability(territory: "USA", available: true),
        ])

        try await runner.appleAvailability()

        #expect(!AvailabilityStub.seen.contains { $0.method == "PATCH" })
    }

    /// The preorder date rides on the same PATCH as the switch.
    @Test func thePreorderAnswerIsWrittenWithTheTerritory() async throws {
        AvailabilityStub.start()
        let runner = availabilityRunner([
            Manifest.TerritoryAvailability(territory: "USA", available: true,
                                           preOrderEnabled: true,
                                           releaseDate: "2026-09-01"),
        ])

        try await runner.appleAvailability()

        let written = try #require(
            AvailabilityStub.patched("/v1/territoryAvailabilities/ta-usa"))
        #expect(written["preOrderEnabled"] as? Bool == true)
        #expect(written["releaseDate"] as? String == "2026-09-01")
        // Already true in the store, so the switch itself is left out.
        #expect(written["available"] == nil)
    }

    /// `availableInNewTerritories` is an attribute of the create and of nothing
    /// else. Once an app holds an availability record, no route changes it.
    ///
    /// This used to send `PATCH /v1/apps/{id}`, which Apple's own reference
    /// still documents and the store refuses: 409, "'availableInNewTerritories'
    /// is not an attribute on the resource 'apps'". The other two routes were
    /// already known closed: `PATCH /v2/appAvailabilities/{id}` answers 403 and
    /// "Allowed operations are: CREATE, GET_INSTANCE", and a second create
    /// answers 409.
    ///
    /// So the run says so instead of stopping on a request that cannot work.
    @Test func changingNewTerritoriesOnAnExistingRecordSendsNothing() async throws {
        AvailabilityStub.start()
        let runner = availabilityRunner([], newTerritories: false, heldAutoConvert: true)

        try await runner.appleAvailability()

        // Nothing was sent, and nothing failed. A request Apple refuses is not
        // worth the round trip, and stopping the whole apply over a setting the
        // store will never take is worse than not offering it.
        // `Validator.availability` is what tells the developer.
        #expect(AvailabilityStub.patched("/v1/apps/app-1") == nil)
        #expect(!AvailabilityStub.seen.contains { $0.method == "PATCH" })
    }

    @Test func anAnswerTheStoreAlreadyHoldsIsNotWritten() async throws {
        AvailabilityStub.start()
        let runner = availabilityRunner([], newTerritories: true, heldAutoConvert: true)

        try await runner.appleAvailability()

        #expect(!AvailabilityStub.seen.contains { $0.path == "/v1/apps/app-1" })
    }

    /// Named, never skipped. A run that reports success and left a country out
    /// is the outcome nothing tells the developer to look for.
    @Test func aTerritoryTheStoreDoesNotListIsNamed() async throws {
        AvailabilityStub.start()
        let runner = availabilityRunner([
            Manifest.TerritoryAvailability(territory: "BRA", available: true),
            Manifest.TerritoryAvailability(territory: "ZZZ", available: true),
        ])

        await #expect(throws: RunError.self) { try await runner.appleAvailability() }
        // And the territory it could write still landed.
        #expect(AvailabilityStub.patched("/v1/territoryAvailabilities/ta-bra") != nil)
    }

    /// The one the developer hit next. The run paged the relationship itself
    /// and asked for no `include=territory`, so App Store Connect answered
    /// every row with a link where its country code belongs. Nothing matched,
    /// the run reported about 200 valid codes as countries the App Store does
    /// not have, and it stopped there.
    ///
    /// A page beyond the first is in the answer too: the whole record is read,
    /// so a country on page two is written and never reported as unknown.
    @Test func everyPageIsReadAndEveryRowNamesItsCountry() async throws {
        AvailabilityStub.start()
        let runner = availabilityRunner([
            Manifest.TerritoryAvailability(territory: "BRA", available: true),
            Manifest.TerritoryAvailability(territory: "USA", available: true),
            Manifest.TerritoryAvailability(territory: "DEU", available: true),
        ])

        try await runner.appleAvailability()

        #expect(AvailabilityStub.seen.contains {
            $0.path == "/v2/appAvailabilities/avail-1/territoryAvailabilities"
                && $0.query.contains("include=territory")
        })
        // The two that disagree with the store are written.
        #expect(AvailabilityStub.patched("/v1/territoryAvailabilities/ta-bra")?["available"]
            as? Bool == true)
        #expect(AvailabilityStub.patched("/v1/territoryAvailabilities/ta-deu")?["available"]
            as? Bool == true)
        // The one that already agrees is not.
        #expect(AvailabilityStub.patched("/v1/territoryAvailabilities/ta-usa") == nil)
    }

    /// An app that holds no availability yet still takes the create, which is
    /// the only route that sets the whole set at once.
    @Test func anAppWithNoAvailabilityYetIsCreated() async throws {
        AvailabilityStub.start(holding: false)
        let runner = availabilityRunner([
            Manifest.TerritoryAvailability(territory: "BRA", available: true),
        ], newTerritories: true)

        try await runner.appleAvailability()

        #expect(AvailabilityStub.seen.contains {
            $0.method == "POST" && $0.path == "/v2/appAvailabilities"
        })
        #expect(!AvailabilityStub.seen.contains { $0.method == "PATCH" })
    }
}

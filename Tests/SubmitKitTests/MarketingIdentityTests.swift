import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// A store that remembers what the apply did to it.
///
/// The bug this covers only appears on the third apply, so a stub that answers
/// a fixed document cannot show it. This one keeps the pages and the
/// experiments it was told to create and reflects them back on the next GET,
/// exactly as App Store Connect would.
private final class MarketingStore: URLProtocol, @unchecked Sendable {
    struct Resource { var id: String; var name: String }

    nonisolated(unsafe) private static var pages: [Resource] = []
    nonisolated(unsafe) private static var experiments: [Resource] = []
    nonisolated(unsafe) private static var creates = 0
    private static let lock = NSLock()

    static func reset(pages seeded: [Resource] = []) {
        lock.withLock {
            pages = seeded
            experiments = []
            creates = 0
        }
    }

    static var pageCount: Int { lock.withLock { pages.count } }
    static var experimentCount: Int { lock.withLock { experiments.count } }
    static var createCalls: Int { lock.withLock { creates } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private func body() -> [String: Any] {
        guard let stream = request.httpBodyStream else {
            return (request.httpBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0)
            } as? [String: Any]) ?? [:]
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    override func startLoading() {
        let url = request.url!
        let path = url.path
        let method = request.httpMethod ?? "GET"
        var payload: [String: Any] = ["data": []]

        Self.lock.withLock {
            func list(_ items: [Resource], type: String, key: String) -> [String: Any] {
                ["data": items.map {
                    ["type": type, "id": $0.id, "attributes": [key: $0.name]]
                }]
            }
            let attributes = ((body()["data"] as? [String: Any])?["attributes"]
                              as? [String: Any]) ?? [:]
            let name = attributes["name"] as? String ?? ""

            switch (method, path) {
            case ("GET", let p) where p.hasSuffix("/appCustomProductPages"):
                payload = list(Self.pages, type: "appCustomProductPages", key: "name")
            case ("POST", "/v1/appCustomProductPages"):
                Self.creates += 1
                let made = Resource(id: "page-\(Self.pages.count + 1)", name: name)
                Self.pages.append(made)
                payload = ["data": ["type": "appCustomProductPages", "id": made.id]]
            case ("PATCH", let p) where p.hasPrefix("/v1/appCustomProductPages/"):
                let id = String(p.dropFirst("/v1/appCustomProductPages/".count))
                if let index = Self.pages.firstIndex(where: { $0.id == id }) {
                    Self.pages[index].name = name
                }
            case ("GET", let p) where p.hasSuffix("/appStoreVersionExperimentsV2"):
                payload = list(Self.experiments, type: "appStoreVersionExperiments", key: "name")
            case ("POST", "/v2/appStoreVersionExperiments"):
                Self.creates += 1
                let made = Resource(id: "exp-\(Self.experiments.count + 1)", name: name)
                Self.experiments.append(made)
                payload = ["data": ["type": "appStoreVersionExperiments", "id": made.id]]
            case ("PATCH", let p) where p.hasPrefix("/v2/appStoreVersionExperiments/"):
                let id = String(p.dropFirst("/v2/appStoreVersionExperiments/".count))
                if let index = Self.experiments.firstIndex(where: { $0.id == id }) {
                    Self.experiments[index].name = name
                }
            default:
                break
            }
        }

        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: payload))
                            ?? Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The manifest names a marketing resource twice and Apple stores one string.
///
/// The apply created a page named after the **key** and then renamed it to the
/// **name**, and every lookup after that asked for the key again. So the third
/// apply found nothing, created a second page, and every apply after it leaked
/// another one. The planner asked the same question by name, so the plan and
/// the apply could disagree about whether a resource existed at all.
@Suite(.serialized)
struct MarketingIdentityTests {

    private func runner(_ manifest: Manifest) -> Runner {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketingStore.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        var manifest = manifest
        manifest.setAppleApp(appID: "app-1", bundleID: "com.example.app")
        return Runner(plan: PlanResult(), manifest: manifest, actual: ActualState(), root: nil,
                      credentials: StoreCredentials(apple: credential), dryRun: false,
                      access: GrantAll(), session: URLSession(configuration: configuration),
                      emit: { _ in })
    }

    private func pageManifest() -> Manifest {
        var manifest = Manifest()
        var marketing = Manifest.Marketing()
        marketing.customProductPages = [
            .init(key: "students", name: "Students"),
        ]
        manifest.marketing = marketing
        return manifest
    }

    // MARK: - The duplicate

    /// Three applies of one unchanged manifest. The store must end with one
    /// page, and the third apply must create nothing.
    @Test func aRepeatedApplyNeverCreatesASecondPage() async throws {
        MarketingStore.reset()
        let runner = runner(pageManifest())

        for _ in 0..<3 { try await runner.appleCustomProductPages() }

        #expect(MarketingStore.pageCount == 1)
        #expect(MarketingStore.createCalls == 1)
    }

    /// The same rule for the experiments, which carried the identical pattern.
    @Test func aRepeatedApplyNeverCreatesASecondExperiment() async throws {
        MarketingStore.reset()
        var manifest = Manifest()
        var marketing = Manifest.Marketing()
        marketing.experiments = [.init(key: "icon-2026", name: "Rounded icon")]
        manifest.marketing = marketing

        let runner = runner(manifest)
        for _ in 0..<3 { try await runner.appleExperiments() }

        #expect(MarketingStore.experimentCount == 1)
        #expect(MarketingStore.createCalls == 1)
    }

    /// A page the older build already created under its key. The fix may not
    /// orphan it: it is the page that is live.
    @Test func aPageLeftUnderItsKeyIsAdoptedAndNotDuplicated() async throws {
        MarketingStore.reset(pages: [.init(id: "page-legacy", name: "students")])
        let runner = runner(pageManifest())

        for _ in 0..<3 { try await runner.appleCustomProductPages() }

        #expect(MarketingStore.pageCount == 1)
        #expect(MarketingStore.createCalls == 0)
    }

    // MARK: - The one rule

    @Test func theStoreIsAskedUnderEitherSpelling() {
        let held = ["students": "1"]
        #expect(StoreIdentity.value(key: "students", name: "Students", in: held) == "1")
        #expect(StoreIdentity.value(key: "students", name: "Students",
                                    in: ["Students": "1"]) == "1")
        #expect(StoreIdentity.value(key: "travel", name: "Travel", in: held) == nil)
    }

    /// A resource is created under the name a human reads, so no later apply
    /// has to rename it. An entry with no name keeps its key.
    @Test func aResourceIsCreatedUnderTheNameItWillKeep() {
        #expect(StoreIdentity.displayName(key: "students", name: "Students") == "Students")
        #expect(StoreIdentity.displayName(key: "students", name: "") == "students")
    }

    /// The plan asked by name while the apply asked by key, so the two could
    /// disagree about whether a page existed.
    @Test func thePlanAsksTheSameQuestionTheApplyAsks() {
        var manifest = pageManifest()
        manifest.setAppleApp(appID: "app-1", bundleID: "com.example.app")
        var actual = ActualState()
        var apple = ActualState.Apple()
        apple.customProductPageNames = ["students": "1"]
        actual.apple = apple

        let plan = Planner.plan(Planner.Input(manifest: manifest, actual: actual,
                                              stores: [.apple]))
        let step = plan.steps.first { $0.id == "apple.customProductPages" }
        #expect(step?.summary.contains("Students") != true,
                "The store holds this page under its key, so nothing is missing.")
    }
}

import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// The TestFlight group, as Apple splits it and as the plan compares it.
///
/// Apple puts the attributes of a beta group in three lists: the ones a create
/// and a change both take, `isInternalGroup` on the create alone, and the two
/// platform switches on the change alone. A request that ignores the split is
/// a request Apple answers with a fault or silently drops half of, and neither
/// one is visible from the app.

// MARK: - What the write sends

private final class GroupLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(method: String, path: String, attributes: [String: Any])] = []

    func record(_ request: URLRequest) {
        // `URLSession` hands a `URLProtocol` the body as a stream, so
        // `httpBody` is nil by the time it arrives here.
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                collected.append(contentsOf: buffer[..<read])
            }
            stream.close()
            data = collected
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let payload = body?["data"] as? [String: Any] ?? [:]
        lock.withLock {
            entries.append((request.httpMethod ?? "", request.url?.path ?? "",
                            payload["attributes"] as? [String: Any] ?? [:]))
        }
    }

    func attributes(_ method: String) -> [String: Any] {
        lock.withLock { entries.first { $0.method == method }?.attributes ?? [:] }
    }

    var calls: [String] { lock.withLock { entries.map { "\($0.method) \($0.path)" } } }
}

private final class GroupStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var log = GroupLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request)
        let body = #"{"data":{"id":"group-new","type":"betaGroups"}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func testFlightClient() -> AppleTestFlightClient {
    GroupStub.log = GroupLog()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GroupStub.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return AppleTestFlightClient(api: StoreAPI(
        credentials: StoreCredentials(apple: credential), record: { _ in },
        session: URLSession(configuration: configuration)))
}

@Suite(.serialized)
struct TestFlightGroupWriteTests {

    /// A new group carries its kind, and takes the two platform switches in the
    /// change that follows. Sending them on the create loses them without a word.
    @Test func aNewGroupTakesItsKindOnTheCreateAndItsPlatformsOnTheChange() async throws {
        let client = testFlightClient()
        let group = Manifest.Release.TestFlight.Group(
            name: "QA", internalGroup: true, feedback: false,
            iosBuildsOnMac: false, iosBuildsOnVision: true)

        _ = try await client.ensureGroup(appID: "1", group, existing: nil)

        let created = GroupStub.log.attributes("POST")
        #expect(created["isInternalGroup"] as? Bool == true)
        #expect(created["feedbackEnabled"] as? Bool == false)
        #expect(created["iosBuildsAvailableForAppleSiliconMac"] == nil)
        #expect(created["iosBuildsAvailableForAppleVision"] == nil)

        let changed = GroupStub.log.attributes("PATCH")
        #expect(changed["iosBuildsAvailableForAppleSiliconMac"] as? Bool == false)
        #expect(changed["iosBuildsAvailableForAppleVision"] as? Bool == true)
        #expect(GroupStub.log.calls == ["POST /v1/betaGroups", "PATCH /v1/betaGroups/group-new"])
    }

    /// Apple fixes the kind when it makes the group, so a change never carries
    /// it. It would be dropped, and the app would keep asking for it.
    @Test func aChangeNeverSendsTheKind() async throws {
        let client = testFlightClient()
        let group = Manifest.Release.TestFlight.Group(name: "QA", internalGroup: false)

        _ = try await client.ensureGroup(appID: "1", group,
                                         existing: AppleTestFlightClient.BetaGroup(
                                            id: "g1", name: "QA"))

        #expect(GroupStub.log.attributes("PATCH")["isInternalGroup"] == nil)
        #expect(GroupStub.log.calls == ["PATCH /v1/betaGroups/g1"])
    }

    /// A cap the developer cleared has to be turned off by name. Leaving the
    /// key out left Apple capping the public link at the number it still held.
    @Test func clearingTheCapTurnsTheLimitOffRatherThanSayingNothing() async throws {
        let client = testFlightClient()
        let group = Manifest.Release.TestFlight.Group(name: "QA", publicLink: true)

        _ = try await client.ensureGroup(appID: "1", group,
                                         existing: AppleTestFlightClient.BetaGroup(
                                            id: "g1", name: "QA"))

        let sent = GroupStub.log.attributes("PATCH")
        #expect(sent["publicLinkEnabled"] as? Bool == true)
        #expect(sent["publicLinkLimitEnabled"] as? Bool == false)
        #expect(sent["publicLinkLimit"] == nil)
    }

    /// Apple takes a public link on an external group only, and faults the
    /// whole request when one reaches an internal group.
    @Test func anInternalGroupCarriesNoPublicLink() async throws {
        let client = testFlightClient()
        let group = Manifest.Release.TestFlight.Group(
            name: "The office", publicLink: true, publicLinkLimit: 50, internalGroup: true)

        _ = try await client.ensureGroup(appID: "1", group, existing: nil)

        let created = GroupStub.log.attributes("POST")
        #expect(created["publicLinkEnabled"] == nil)
        #expect(created["publicLinkLimit"] == nil)
        #expect(created["publicLinkLimitEnabled"] == nil)
    }
}

// MARK: - What the read keeps

@Test func aBetaGroupPayloadCarriesItsKindItsFeedbackAndItsLink() throws {
    let group = try #require(AppleTestFlightClient.parseGroup(json("""
    {"id":"g1","attributes":{"name":"QA","isInternalGroup":false,"feedbackEnabled":true,
     "publicLinkEnabled":true,"publicLink":"https://testflight.apple.com/join/abcd1234",
     "iosBuildsAvailableForAppleSiliconMac":false,
     "iosBuildsAvailableForAppleVision":true}}
    """)))

    #expect(group.internalGroup == false)
    #expect(group.feedback == true)
    #expect(group.iosBuildsOnMac == false)
    #expect(group.iosBuildsOnVision == true)
    // The address the developer hands to a tester. The read used to drop it.
    #expect(group.publicLinkURL == "https://testflight.apple.com/join/abcd1234")
}

// MARK: - What the plan compares

private func groupManifest(_ group: Manifest.Release.TestFlight.Group) -> Manifest {
    var manifest = appleManifest()
    manifest.release?.apple = Manifest.Release.AppleRelease(
        testFlight: Manifest.Release.TestFlight(groups: [group]))
    return manifest
}

private func liveGroup(_ build: (inout AppleTestFlightClient.BetaGroup) -> Void)
    -> ActualState {
    var group = AppleTestFlightClient.BetaGroup(id: "g1", name: "QA")
    build(&group)
    return appleState { $0.betaGroups = ["QA": group] }
}

@Test func aChangedCapRaisesTheGroupStepAndAMatchingOneDoesNot() {
    let manifest = groupManifest(.init(name: "QA", publicLink: true, publicLinkLimit: 500))
    let held = liveGroup { group in
        group.publicLink = true
        group.publicLinkLimit = 250
    }
    #expect(steps(manifest, held).contains { $0.id == "apple.betaGroup.QA" })

    let matching = liveGroup { group in
        group.publicLink = true
        group.publicLinkLimit = 500
    }
    #expect(!steps(manifest, matching).contains { $0.id == "apple.betaGroup.QA" })
}

@Test func theFeedbackAndPlatformSwitchesAreCompared() {
    let manifest = groupManifest(.init(name: "QA", feedback: false, iosBuildsOnVision: false))
    let held = liveGroup { group in
        group.feedback = true
        group.iosBuildsOnVision = true
    }
    #expect(steps(manifest, held).contains { $0.id == "apple.betaGroup.QA" })
}

/// Apple takes the kind on the create alone, so a group it already holds can
/// never change kind. A step for it would be sent on every apply and change
/// nothing.
@Test func theKindAloneRaisesNoStepOnAGroupAppleAlreadyHolds() {
    let manifest = groupManifest(.init(name: "QA", internalGroup: true))
    let held = liveGroup { $0.internalGroup = false }
    #expect(!steps(manifest, held).contains { $0.id == "apple.betaGroup.QA" })
}

/// The build a run uploads is the build its groups receive. The step used to
/// wait for a build the App Store version already held, so the first beta of a
/// version created the group, invited the testers, and gave them nothing.
@Test func aGroupGetsTheBuildThisRunUploads() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("testflight-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let artifact = folder.appendingPathComponent("App.ipa")
    try Data("binary".utf8).write(to: artifact)

    var manifest = groupManifest(.init(name: "QA", testers: ["a@example.com"]))
    manifest.release?.build = Manifest.Release.Build(ios: "App.ipa")

    let plan = Planner.plan(Planner.Input(manifest: manifest, actual: ActualState(),
                                          stores: [.apple], root: folder))
    #expect(plan.steps.contains { $0.id == "apple.betaBuild.QA" })

    // Without a build there is nothing to give, so the row stays away.
    var withoutBuild = manifest
    withoutBuild.release?.build = nil
    let bare = Planner.plan(Planner.Input(manifest: withoutBuild, actual: ActualState(),
                                          stores: [.apple], root: folder))
    #expect(!bare.steps.contains { $0.id == "apple.betaBuild.QA" })
}

/// A group that already holds the build takes no second row.
@Test func aGroupThatHoldsTheBuildIsLeftAlone() {
    let manifest = groupManifest(.init(name: "QA"))
    let held = liveGroup { group in
        group.buildIds = ["build-9"]
    }
    var state = held
    state.apple?.buildIdForVersion = "build-9"
    #expect(!steps(manifest, state).contains { $0.id == "apple.betaBuild.QA" })

    // A build Apple holds that the group does not is the row's whole reason.
    state.apple?.buildIdForVersion = "build-10"
    #expect(steps(manifest, state).contains { $0.id == "apple.betaBuild.QA" })
}

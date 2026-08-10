import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

private func findings(_ manifest: Manifest, _ actual: ActualState) -> [Finding] {
    Validator.findings(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
}

/// Updating an app that is already on the App Store.
///
/// The live version is not writable. The app used to read it anyway, hand its
/// id to the runner, and then block the apply on a state error. These tests
/// hold the three rules that replaced that: the read reports no writable
/// version, the plan creates one, and the create never leaves a stale
/// localization id pointing at the listing the customers are reading.

private func liveApp(manifestVersion: String = "3.2.0") -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName(manifestVersion)
    return manifest
}

/// What the read produces for a live app with no version in preparation.
private func liveState(_ live: String = "3.1.0") -> ActualState {
    var apple = ActualState.Apple()
    apple.liveVersionString = live
    apple.appInfoId = "info-1"
    var state = ActualState()
    state.apple = apple
    return state
}

// MARK: - The plan

@Test func aLiveAppWithNoDraftPlansACreateAndNotAPatch() {
    let step = steps(liveApp(), liveState()).first { $0.id == "apple.version" }
    let version = try! #require(step)

    #expect(version.kind == .add)
    #expect(version.requests.first?.method == "POST")
    #expect(version.operation == .appleEnsureVersion("3.2.0"))
}

@Test func aVersionAlreadyInPreparationIsPatchedAndNotRecreated() {
    var actual = liveState()
    actual.apple?.versionId = "version-9"
    actual.apple?.versionString = "3.1.5"
    actual.apple?.versionState = "PREPARE_FOR_SUBMISSION"

    let version = try! #require(steps(liveApp(), actual).first { $0.id == "apple.version" })
    #expect(version.kind == .change)
    #expect(version.requests.first?.method == "PATCH")
}

@Test func aLiveAppWithNoDraftNoLongerBlocksTheApply() {
    // The state rule reads `versionState`, and a live app now leaves it nil.
    #expect(!findings(liveApp(), liveState()).contains { $0.id == "state.appleVersion" })
}

/// It blocks, and it is not an error.
///
/// Apple takes no write while it holds the version, so the apply still has to
/// stop. Nothing about that is the developer's mistake, so the row that says so
/// is `.held` and the plan is blocked by the hold rather than by an error.
@Test func aVersionStuckOutsidePreparationStillBlocksTheApply() {
    var actual = liveState()
    actual.apple?.versionId = "version-9"
    actual.apple?.versionState = "WAITING_FOR_REVIEW"

    let finding = try! #require(findings(liveApp(), actual)
        .first { $0.id == "state.appleVersion" })
    #expect(finding.severity == .held)

    // The hold alone is enough to stop the apply. This fixture carries an
    // unrelated error too, so the block is asserted on the hold by itself.
    var plan = PlanResult()
    plan.findings = [finding]
    #expect(plan.isBlocked)
    #expect(plan.errors.isEmpty)
}

// MARK: - The version has to climb

@Test func aManifestVersionBelowTheLiveOneBlocksTheApply() {
    let finding = try! #require(findings(liveApp(manifestVersion: "3.0.0"), liveState("3.1.0"))
        .first { $0.id == "state.appleVersionBump" })

    #expect(finding.severity == .error)
    #expect(finding.fix == .build)
    #expect(finding.message.contains("3.1.0"))
}

@Test func aManifestVersionEqualToTheLiveOneBlocksTheApply() {
    #expect(findings(liveApp(manifestVersion: "3.1.0"), liveState("3.1.0"))
        .contains { $0.id == "state.appleVersionBump" })
}

@Test func aManifestVersionAboveTheLiveOnePasses() {
    #expect(!findings(liveApp(manifestVersion: "3.2.0"), liveState("3.1.0"))
        .contains { $0.id == "state.appleVersionBump" })
}

@Test func anAppWithNoLiveVersionSkipsTheBumpRule() {
    #expect(!findings(liveApp(), ActualState())
        .contains { $0.id == "state.appleVersionBump" })
}

@Test(arguments: [
    ("3.10.0", "3.9.0", true),   // the text compare gets this one wrong
    ("3.9.0", "3.10.0", false),
    ("3.2", "3.1.9", true),
    ("3.1", "3.1.0", false),     // equal, and equal is not above
    ("4.0.0", "3.99.99", true),
    ("1.0.0", "1.0.1", false),
])
func versionsCompareByNumberAndNotByText(candidate: String, other: String, above: Bool) {
    #expect(Validator.isVersion(candidate, above: other) == above)
}

// MARK: - The create must not leave a stale localization id

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(method: String, path: String)] = []

    func record(_ request: URLRequest) {
        lock.withLock {
            entries.append((request.httpMethod ?? "", request.url?.path ?? ""))
        }
    }

    var all: [(method: String, path: String)] { lock.withLock { entries } }
}

private final class VersionStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var log = CallLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request)
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? ""
        let body: String

        if method == "POST", path == "/v1/appStoreVersions" {
            body = #"{"data":{"id":"version-new","type":"appStoreVersions"}}"#
        } else if path.hasSuffix("/appStoreReviewDetail"), method == "GET" {
            // Apple copies the previous version's review detail onto the new
            // one, so the created version already carries this id.
            body = #"{"data":{"id":"review-new","type":"appStoreReviewDetails"}}"#
        } else if path.hasSuffix("/appStoreVersionLocalizations"), method == "GET" {
            // Apple pre-fills the new version, so the copied localization
            // carries a different id from the live one the read saw.
            body = """
            {"data":[{"id":"loc-new","type":"appStoreVersionLocalizations",
                      "attributes":{"locale":"en-US"}}]}
            """
        } else {
            body = #"{"data":{}}"#
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// An app with one version, and that version is on sale. This is exactly the
/// shape that used to dead-end the update.
private final class LiveOnlyStubProtocol: URLProtocol, @unchecked Sendable {
    static let defaultVersions = """
    {"id":"version-live","type":"appStoreVersions",
     "attributes":{"versionString":"3.1.0","appVersionState":"READY_FOR_SALE"}}
    """

    /// The versions the stub reports, as raw JSON objects.
    nonisolated(unsafe) static var versions = defaultVersions

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let body: String

        if path.hasSuffix("/appStoreVersions") {
            body = #"{"data":[\#(Self.versions)]}"#
        } else {
            body = #"{"data":[]}"#
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// One read against `LiveOnlyStubProtocol`, with a throwaway signing key.
private func readAppleState() async throws -> ActualState.Apple {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LiveOnlyStubProtocol.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    let api = StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                       session: URLSession(configuration: configuration))
    return try await StateReader(api: api).readApple(appID: "1234567890", versionName: "3.2.0")
}

private func stubbedRunner(plan: PlanResult, actual: ActualState,
                           manifest: Manifest = liveApp()) -> Runner {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [VersionStubProtocol.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return Runner(plan: plan, manifest: manifest, actual: actual, root: nil,
                  credentials: StoreCredentials(apple: credential), dryRun: false,
                  access: GrantAll(),
                  session: URLSession(configuration: configuration), emit: { _ in })
}

@Suite(.serialized)
struct AppleVersionCreationRunTests {

    /// The regression this whole change exists to prevent.
    ///
    /// The runner seeds `appleVersionLocalizationIDs` from the read. A live
    /// app used to seed it with the live version's ids. If the run then
    /// created a version and kept them, `appleVersionLocale` would patch the
    /// live listing and `appleScreenshots` would delete inside it.
    @Test func creatingAVersionReplacesTheLocalizationIdsTheReadSupplied() async throws {
        VersionStubProtocol.log = CallLog()
        var actual = liveState()
        // What the old fallback produced: the live version's localization.
        actual.apple?.versionLocales["en-US"] = {
            var locale = ActualState.Apple.VersionLocale()
            locale.id = "loc-live"
            return locale
        }()

        var plan = PlanResult()
        plan.steps = [PlanStep(
            id: "apple.version", system: .apple, kind: .add, summary: "",
            title: "Create the version 3.2.0",
            requests: [RequestSketch("POST", "/v1/appStoreVersions")],
            operation: .appleEnsureVersion("3.2.0"))]

        let runner = stubbedRunner(plan: plan, actual: actual)
        await runner.run()

        let ids = await runner.appleVersionLocalizationIDs
        #expect(ids["en-US"] == "loc-new")
        #expect(ids["en-US"] != "loc-live")

        // It read the new version, not the old one.
        #expect(VersionStubProtocol.log.all.contains {
            $0.method == "GET"
                && $0.path == "/v1/appStoreVersions/version-new/appStoreVersionLocalizations"
        })
    }

    /// The 409 that stopped a real update one step short of the submit.
    ///
    /// Apple copies a review detail onto a version this run creates, and the
    /// read that seeded the id saw no version at all, so it carried none. The
    /// apply POSTed a second detail and App Store Connect refused it: "The
    /// given app version already has an existing review." A retry keeps the
    /// runner and starts at the failed step, so it re-read nothing and failed
    /// in exactly the same place, forever.
    @Test func theReviewDetailIsPatchedOnAVersionTheReadNeverSaw() async throws {
        VersionStubProtocol.log = CallLog()
        var manifest = liveApp()
        var review = Manifest.Review()
        review.contactEmail = "someone@example.com"
        review.notes = "Nothing special."
        manifest.review = review

        // The read found no writable version, so it carries no detail id.
        let actual = liveState()
        #expect(actual.apple?.reviewDetailId == nil)

        var plan = PlanResult()
        plan.steps = [
            PlanStep(id: "apple.version", system: .apple, kind: .add, summary: "",
                     title: "Create the version 3.2.0",
                     requests: [RequestSketch("POST", "/v1/appStoreVersions")],
                     operation: .appleEnsureVersion("3.2.0")),
            PlanStep(id: "apple.review", system: .apple, kind: .add, summary: "",
                     title: "Write the review details",
                     requests: [RequestSketch("POST", "/v1/appStoreReviewDetails")],
                     operation: .appleReviewDetails),
        ]

        let runner = stubbedRunner(plan: plan, actual: actual, manifest: manifest)
        await runner.run()

        // It asks the version it is writing, and patches what it finds.
        #expect(VersionStubProtocol.log.all.contains {
            $0.method == "GET"
                && $0.path == "/v1/appStoreVersions/version-new/appStoreReviewDetail"
        })
        #expect(VersionStubProtocol.log.all.contains {
            $0.method == "PATCH" && $0.path == "/v1/appStoreReviewDetails/review-new"
        })
        // The POST is what App Store Connect answered with a 409.
        #expect(!VersionStubProtocol.log.all.contains {
            $0.method == "POST" && $0.path == "/v1/appStoreReviewDetails"
        })
    }

    /// Edit one, and the reason the flow used to dead-end.
    ///
    /// The read used to fall back to `versions.first`, which for a live app is
    /// the released version. That handed the runner an id it could not write
    /// to, and the state rule then blocked the apply with no way forward.
    @Test func theReadReportsNoWritableVersionForALiveApp() async throws {
        let state = try await readAppleState()

        #expect(state.versionId == nil)
        #expect(state.versionString == nil)
        #expect(state.versionState == nil)
        #expect(state.liveVersionString == "3.1.0")
    }

    /// An app the developer pulled from sale was still on the store, so the
    /// next version is an update and it still has to climb past the last one.
    @Test func aVersionRemovedFromSaleStillCountsAsShipped() async throws {
        LiveOnlyStubProtocol.versions = """
        {"id":"version-pulled","type":"appStoreVersions",
         "attributes":{"versionString":"3.1.0","appVersionState":"REMOVED_FROM_SALE"}}
        """
        defer { LiveOnlyStubProtocol.versions = LiveOnlyStubProtocol.defaultVersions }

        #expect(try await readAppleState().liveVersionString == "3.1.0")
    }

    /// App Store Connect fixes no order for this list. Taking the first entry
    /// would compare the manifest against whichever release came back first.
    ///
    /// The lower version leads the list, so `.first` would answer 3.9.0 and
    /// let a 3.9.5 update through against a 3.10.0 that already shipped.
    @Test func theBaselineIsTheHighestReleasedVersionAndNotTheFirstOne() async throws {
        LiveOnlyStubProtocol.versions = """
        {"id":"older","type":"appStoreVersions",
         "attributes":{"versionString":"3.9.0","appVersionState":"REMOVED_FROM_SALE"}},
        {"id":"newer","type":"appStoreVersions",
         "attributes":{"versionString":"3.10.0","appVersionState":"REMOVED_FROM_SALE"}}
        """
        defer { LiveOnlyStubProtocol.versions = LiveOnlyStubProtocol.defaultVersions }

        // 3.10 beats 3.9 by number. A text compare would pick 3.9.
        #expect(try await readAppleState().liveVersionString == "3.10.0")
    }

    /// A version nobody ever submitted leaves the app a first submission, and
    /// every update rule stays quiet.
    @Test func anAppThatNeverShippedReportsNoBaseline() async throws {
        LiveOnlyStubProtocol.versions = """
        {"id":"draft","type":"appStoreVersions",
         "attributes":{"versionString":"1.0.0","appVersionState":"PREPARE_FOR_SUBMISSION"}}
        """
        defer { LiveOnlyStubProtocol.versions = LiveOnlyStubProtocol.defaultVersions }

        let state = try await readAppleState()
        #expect(state.liveVersionString == nil)
        #expect(state.versionId == "draft")
    }

    @Test func creatingAVersionDropsALocalizationTheNewVersionDoesNotHave() async throws {
        VersionStubProtocol.log = CallLog()
        var actual = liveState()
        actual.apple?.versionLocales["pt-BR"] = {
            var locale = ActualState.Apple.VersionLocale()
            locale.id = "loc-live-pt"
            return locale
        }()

        var plan = PlanResult()
        plan.steps = [PlanStep(
            id: "apple.version", system: .apple, kind: .add, summary: "",
            title: "Create the version 3.2.0",
            requests: [RequestSketch("POST", "/v1/appStoreVersions")],
            operation: .appleEnsureVersion("3.2.0"))]

        let runner = stubbedRunner(plan: plan, actual: actual)
        await runner.run()

        // The stub returns en-US only. A pt-BR id from the live version must
        // not survive, or the pt-BR step would write to the live listing.
        let ids = await runner.appleVersionLocalizationIDs
        #expect(ids["pt-BR"] == nil)
    }
}

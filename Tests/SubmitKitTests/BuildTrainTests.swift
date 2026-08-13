import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// A build number belongs to a version train, and a build reaches Apple by two
/// routes.
///
/// Both facts cost this app the same flow. The reader compared a build number
/// against every train at once, so a new marketing version that restarted at
/// one was blocked while App Store Connect would have taken it. And the plan
/// gated the attach on a named file, so a build that Build from Project had
/// already uploaded with `xcodebuild -exportArchive` was never attached, and
/// the release refused a version that held no build.

// MARK: - The reader

/// Answers `/v1/builds` with two trains and an empty document for everything
/// else, so the test is about the train filter and nothing else.
private final class BuildsStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var seen: [String] = []
    private static let lock = NSLock()

    static func start() { lock.withLock { seen = [] } }
    static var paths: [String] { lock.withLock { seen } }

    /// Train `old` holds build 412. Train `new` holds 1 and 2, both processed,
    /// and 3, which Apple is still processing.
    static let payload = """
    {"data":[
      {"id":"b-412","type":"builds",
       "attributes":{"version":"412","processingState":"VALID"},
       "relationships":{"preReleaseVersion":{"data":{"id":"train-old"}}}},
      {"id":"b-1","type":"builds",
       "attributes":{"version":"1","processingState":"VALID",
                     "uploadedDate":"2026-08-01T10:00:00.000Z"},
       "relationships":{"preReleaseVersion":{"data":{"id":"train-new"}}}},
      {"id":"b-2","type":"builds",
       "attributes":{"version":"2","processingState":"VALID",
                     "usesNonExemptEncryption":false},
       "relationships":{"preReleaseVersion":{"data":{"id":"train-new"}}}},
      {"id":"b-3","type":"builds",
       "attributes":{"version":"3","processingState":"PROCESSING"},
       "relationships":{"preReleaseVersion":{"data":{"id":"train-new"}}}}
     ],
     "included":[
      {"id":"train-old","type":"preReleaseVersions",
       "attributes":{"version":"3.1.0","platform":"IOS"}},
      {"id":"train-new","type":"preReleaseVersions",
       "attributes":{"version":"3.2.0","platform":"IOS"}},
      {"id":"train-mac","type":"preReleaseVersions",
       "attributes":{"version":"3.2.0","platform":"MAC_OS"}}
     ]}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url.path + (url.query.map { "?\($0)" } ?? "")) }
        let body = url.path == "/v1/builds" ? Self.payload : #"{"data":[]}"#
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func buildsAPI() -> StoreAPI {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BuildsStubProtocol.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                    session: URLSession(configuration: configuration))
}

private func readBuilds(versionName: String?, platform: String?,
                        buildNumber: String? = nil) async throws -> ActualState.Apple {
    try await StateReader(api: buildsAPI())
        .readApple(appID: "1", versionName: versionName, platform: platform,
                   buildNumber: buildNumber)
}

@Suite(.serialized)
struct BuildTrainReadTests {
    @Test func theHighestBuildNumberCountsOnlyItsOwnTrain() async throws {
        let apple = try await readBuilds(versionName: "3.2.0", platform: "IOS")

        // 412 lives in the 3.1.0 train, and 3 is still processing but is still
        // a number Apple holds. Counting 412 blocked every build below it.
        #expect(apple.highestBuildNumber == 3)
    }

    @Test func theReadAsksForTheTrainItThenFiltersOn() async throws {
        _ = try await readBuilds(versionName: "3.2.0", platform: "IOS")

        let builds = BuildsStubProtocol.paths.filter { $0.hasPrefix("/v1/builds?") }
        #expect(!builds.isEmpty, "The read never asked for the builds.")
        #expect(builds.allSatisfy { $0.contains("include=preReleaseVersion") },
                "Without the include, no build names its train.")
    }

    @Test func onlyAProcessedBuildIsOfferedForTheAttach() async throws {
        let apple = try await readBuilds(versionName: "3.2.0", platform: "IOS")

        // Build 3 is higher and Apple is still processing it. A version cannot
        // hold that one, so the processed build 2 is the answer.
        #expect(apple.buildIdForVersion == "b-2")
    }

    @Test func aVersionWithNoBuildYetOffersNothing() async throws {
        let apple = try await readBuilds(versionName: "4.0.0", platform: "IOS")

        #expect(apple.buildIdForVersion == nil)
        #expect(apple.highestBuildNumber == nil)
    }

    @Test func theOtherPlatformsTrainIsNotThisRunsTrain() async throws {
        let apple = try await readBuilds(versionName: "3.2.0", platform: "MAC_OS")

        // `train-mac` carries the same version string and holds no build, so a
        // Mac run sees none of the iOS numbers.
        #expect(apple.highestBuildNumber == nil)
        #expect(apple.buildIdForVersion == nil)
    }
}

// MARK: - Choosing a build the store already holds

/// The version takes one of the builds App Store Connect holds, and the app
/// took the highest processed one with no way to say otherwise.
@Suite(.serialized)
struct ChosenBuildTests {
    @Test func aNamedNumberBeatsTheHighestBuild() async throws {
        let apple = try await readBuilds(versionName: "3.2.0", platform: "IOS",
                                         buildNumber: "1")

        // Build 2 is processed and higher. The manifest asked for 1.
        #expect(apple.buildIdForVersion == "b-1")
    }

    @Test func noNamedNumberStillTakesTheHighestProcessedBuild() async throws {
        let apple = try await readBuilds(versionName: "3.2.0", platform: "IOS")

        #expect(apple.buildIdForVersion == "b-2")
    }

    /// Never the highest one instead. Attaching a build the developer did not
    /// ask for is the one outcome worse than attaching none.
    @Test func aNumberOfNoProcessedBuildAnswersNothing() async throws {
        let apple = try await readBuilds(versionName: "3.2.0", platform: "IOS",
                                         buildNumber: "3")

        #expect(apple.buildIdForVersion == nil)
    }

    @Test func aChosenBuildTheStoreDoesNotHoldBlocksTheApply() {
        var manifest = updatable()
        manifest.release?.apple = Manifest.Release.AppleRelease(buildNumber: "9")
        var actual = ActualState()
        actual.apple = ActualState.Apple()

        let findings = Validator.findings(Planner.Input(
            manifest: manifest, actual: actual, stores: [.apple]))
        let finding = try! #require(findings.first { $0.id == "build.chosenMissing" })
        #expect(finding.severity == .error)
        #expect(finding.message.contains("9"))
    }

    @Test func theBuildTheManifestFoundRaisesNoFinding() {
        var manifest = updatable()
        manifest.release?.apple = Manifest.Release.AppleRelease(buildNumber: "1")
        var actual = ActualState()
        actual.apple = ActualState.Apple()
        actual.apple?.buildIdForVersion = "b-1"

        #expect(!Validator.findings(Planner.Input(
            manifest: manifest, actual: actual, stores: [.apple]))
            .contains { $0.id == "build.chosenMissing" })
    }

    /// The picker on the Build tab draws this list, so every build of the
    /// platform belongs in it, processed or not.
    @Test func theListNamesEveryBuildOfThisPlatform() async throws {
        let builds = try await UploadService(api: buildsAPI())
            .appleBuildChoices(appID: "1", platform: .ios)

        #expect(builds.map(\.id) == ["b-412", "b-1", "b-2", "b-3"])
        #expect(builds.first { $0.id == "b-2" }?.version == "3.2.0")
        #expect(builds.first { $0.id == "b-3" }?.processed == false)
        #expect(builds.first { $0.id == "b-1" }?.uploaded != nil)
    }

    @Test func theListDropsTheOtherPlatform() async throws {
        let builds = try await UploadService(api: buildsAPI())
            .appleBuildChoices(appID: "1", platform: .macos)

        // `train-mac` holds no build, and none of the iOS builds belong to it.
        #expect(builds.isEmpty)
    }
}

// MARK: - The export compliance answer

/// Apple takes it from `ITSAppUsesNonExemptEncryption` while it processes the
/// build and refuses to change it afterwards. The read used to ask only the
/// attached build, so between releases it answered nil, the plan queued the
/// write against a build that already carried the answer, and the run stopped
/// on Apple's 409.
@Suite(.serialized)
struct BuildComplianceTests {
    @Test func theAnswerComesFromTheBuildTheApplyWritesTo() async throws {
        let apple = try await readBuilds(versionName: "3.2.0", platform: "IOS")

        #expect(apple.attachedBuildId == nil)
        #expect(apple.buildUsesNonExemptEncryption == false)
    }

    @Test func aBuildThatAlreadyAnswersNeedsNoWrite() {
        var manifest = updatable()
        manifest.review = Manifest.Review(usesNonExemptEncryption: false)
        var apple = ActualState.Apple()
        apple.buildIdForVersion = "b-2"
        apple.buildUsesNonExemptEncryption = false

        #expect(!plan(apple, manifest: manifest).contains { $0 == "apple.buildCompliance" })
    }

    @Test func aBuildWithNoAnswerYetGetsTheWrite() {
        var manifest = updatable()
        manifest.review = Manifest.Review(usesNonExemptEncryption: false)
        var apple = ActualState.Apple()
        apple.buildIdForVersion = "b-2"

        #expect(plan(apple, manifest: manifest).contains { $0 == "apple.buildCompliance" })
    }
}

// MARK: - The plan

private func updatable() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.setReleaseVersionName("3.2.0")
    return manifest
}

private func plan(_ apple: ActualState.Apple, manifest: Manifest = updatable()) -> [String] {
    var actual = ActualState()
    actual.apple = apple
    return Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
        .steps(for: .apple).map(\.id)
}

@Test func anUploadedBuildIsAttachedWithoutANamedFile() {
    var apple = ActualState.Apple()
    apple.buildIdForVersion = "b-2"

    let ids = plan(apple)
    #expect(ids.contains("apple.attachBuild"))
    // Nothing to upload: `xcodebuild -exportArchive` already sent it, and a
    // second upload of the same build is what Apple refuses.
    #expect(!ids.contains("apple.build"))
}

@Test func aBuildTheVersionAlreadyHoldsNeedsNoAttach() {
    var apple = ActualState.Apple()
    apple.buildIdForVersion = "b-2"
    apple.attachedBuildId = "b-2"

    #expect(!plan(apple).contains("apple.attachBuild"))
}

@Test func noBuildAnywhereMeansNoBuildStep() {
    let ids = plan(ActualState.Apple())
    #expect(!ids.contains("apple.attachBuild"))
    #expect(!ids.contains("apple.build"))
}

/// The version names the train, so a build with no version leaves the number
/// rule with nothing to compare against. The apply used to meet the same wall
/// and answer only "no version".
@Test func aNamedBuildWithNoVersionIsAnError() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    var package = AppPackage(kind: .ipa, url: URL(fileURLWithPath: "/tmp/a.ipa"))
    package.identifier = "com.example.app"
    package.buildNumber = "7"

    let findings = Validator.findings(Planner.Input(
        manifest: manifest, actual: ActualState(), stores: [.apple],
        packages: [.ipa: package]))

    #expect(findings.contains { $0.id == "build.noVersionName" && $0.severity == .error })
}

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SubmitKit

/// Updating an app that is already on the App Store.
///
/// An update is not a first publish, and the app used to treat it as one. App
/// Store Connect fills a new version from the released one: the description,
/// the keywords, the URLs and every screenshot are already there before the
/// run starts. The read saw no draft, compared the manifest against nothing,
/// and every field came out changed. So an apply that altered one line of
/// What's New re-wrote six fields and re-uploaded a whole screenshot set, over
/// bytes that were already identical.
///
/// These tests pin the rule in the three places it has to hold: the plan says
/// what will be sent, the run sends what the plan said, and the checklist does
/// not hold the release button over a declaration Apple asked for once, a year
/// ago, to let the app on the store in the first place.

// MARK: - The fixtures

/// The words on the store today. The manifest starts out agreeing with every
/// one of them, so each test changes exactly what it means to test.
private let liveText = (
    description: "A long description.",
    whatsNew: "The 3.1.0 notes.",
    keywords: "one,two,three",
    promotionalText: "Now with more.",
    supportUrl: "https://example.com/support",
    marketingUrl: "https://example.com"
)

private func updateManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText(liveText.description, locale: "en-US", field: .description)
    manifest.setListingText(liveText.whatsNew, locale: "en-US", field: .whatsNew)
    manifest.setListingText(liveText.keywords, locale: "en-US", field: .keywords)
    manifest.setListingText(liveText.promotionalText, locale: "en-US", field: .promotionalText)
    manifest.setListingText(liveText.supportUrl, locale: "en-US", field: .supportURL)
    manifest.setListingText(liveText.marketingUrl, locale: "en-US", field: .marketingURL)
    manifest.setReleaseVersionName("3.2.0")
    return manifest
}

private func liveLocale(id: String? = "loc-live") -> ActualState.Apple.VersionLocale {
    var locale = ActualState.Apple.VersionLocale()
    locale.id = id
    locale.description = liveText.description
    locale.whatsNew = liveText.whatsNew
    locale.keywords = liveText.keywords
    locale.promotionalText = liveText.promotionalText
    locale.supportUrl = liveText.supportUrl
    locale.marketingUrl = liveText.marketingUrl
    return locale
}

/// A live app with no version in preparation. This is the shape of an update
/// between releases, and the shape the plan used to read as a blank app.
private func liveState(_ build: (inout ActualState.Apple) -> Void = { _ in }) -> ActualState {
    var apple = ActualState.Apple()
    apple.liveVersionString = "3.1.0"
    apple.appInfoId = "info-1"
    apple.liveVersionLocales["en-US"] = liveLocale()
    build(&apple)
    var state = ActualState()
    state.apple = apple
    return state
}

private func appleSteps(_ manifest: Manifest, _ actual: ActualState,
                        root: URL? = nil) -> [PlanStep] {
    Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple], root: root))
        .steps(for: .apple)
}

private func localeStep(_ manifest: Manifest, _ actual: ActualState) -> PlanStep? {
    appleSteps(manifest, actual).first { $0.id == "apple.locale.en-US" }
}

// MARK: - The listing text

@Test func anUpdateThatChangedNothingWritesNoListing() {
    // The manifest and the released version say the same thing, so there is
    // nothing to send. The draft does not exist yet, and that used to be read
    // as "the store holds nothing", which made all six fields a change.
    #expect(localeStep(updateManifest(), liveState()) == nil)
}

@Test func anUpdatePlansOnlyTheFieldTheDeveloperChanged() {
    var manifest = updateManifest()
    manifest.setListingText("The 3.2.0 notes.", locale: "en-US", field: .whatsNew)

    let step = try! #require(localeStep(manifest, liveState()))
    #expect(step.summary.contains("What is new"))
    // The five that did not move stay out of the summary, because they stay
    // out of the request.
    #expect(!step.summary.contains("Description"))
    #expect(!step.summary.contains("Keywords"))
    #expect(!step.summary.contains("Promotional"))
    #expect(!step.summary.contains("Support"))
    #expect(!step.summary.contains("Marketing"))
}

@Test func aDraftThatAlreadyExistsAnswersForItself() {
    // The version in preparation is the resource the run patches, so it wins
    // over the released one even when the two disagree.
    let actual = liveState { apple in
        apple.versionId = "version-9"
        apple.versionLocales["en-US"] = {
            var locale = liveLocale(id: "loc-9")
            locale.keywords = "already,edited,in,app,store,connect"
            return locale
        }()
    }
    var manifest = updateManifest()
    manifest.setListingText("already,edited,in,app,store,connect",
                            locale: "en-US", field: .keywords)

    #expect(localeStep(manifest, actual) == nil)
}

@Test func aFirstPublishStillWritesEveryField() {
    // Nothing is live, so nothing is inherited and every managed field is new.
    // The update rule may never reach a first submission.
    let step = try! #require(localeStep(updateManifest(), ActualState()))
    #expect(step.kind == .add)
    for field in ["Description", "What is new", "Keywords", "Promotional text",
                  "Support URL", "Marketing URL"] {
        #expect(step.summary.contains(field), "\(field) is missing from a first publish")
    }
}

/// The name and the subtitle are app-level and not version-level, so they were
/// never part of the same bug. They are pinned here because the requirement
/// names them, and because an app-level read that regressed would be invisible
/// otherwise.
@Test func anUpdateWritesNoAppInformationWhenTheNameAndSubtitleMatch() {
    var manifest = updateManifest()
    manifest.setListingText("Scan anything", locale: "en-US", field: .subtitle)

    let actual = liveState { apple in
        apple.infoLocales["en-US"] = {
            var info = ActualState.Apple.InfoLocale()
            info.id = "info-loc-1"
            info.name = "Example"
            info.subtitle = "Scan anything"
            return info
        }()
    }

    #expect(!appleSteps(manifest, actual).contains { $0.id == "apple.info.en-US" })
}

// MARK: - The screenshots

/// A real PNG, because `AssetInspector` reads the pixel size off the file and
/// the display type comes from that size. 1320 x 2868 is `APP_IPHONE_69`.
private func writeScreenshot(_ url: URL, gray: CGFloat) throws {
    let width = 1_320, height = 2_868
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.setFillColor(gray: gray, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

/// Two screenshots on disk, their md5s, and a manifest that names them in
/// order. The temporary directory goes with the test.
private struct ScreenshotSet {
    let root: URL
    let manifest: Manifest
    let checksums: [String]

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apple-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var manifest = updateManifest()
        var checksums: [String] = []
        for (index, gray) in [CGFloat(0.2), 0.8].enumerated() {
            let file = root.appendingPathComponent("shot-\(index).png")
            try writeScreenshot(file, gray: gray)
            manifest.addMediaPaths([file.path], locale: "en-US", deviceClass: .phone)
            checksums.append(Checksums.md5(try Data(contentsOf: file)))
        }
        self.manifest = manifest
        self.checksums = checksums
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func mediaStep(_ actual: ActualState) -> PlanStep? {
        appleSteps(manifest, actual).first { $0.id == "apple.media.en-US.phone" }
    }
}

@Test func anUpdateWithTheSameScreenshotsUploadsNothing() throws {
    let set = try ScreenshotSet()
    defer { set.cleanUp() }

    // What Apple carries into the new version: the released version's set,
    // in the released version's order.
    let actual = liveState { apple in
        apple.liveScreenshotChecksumOrder["en-US/APP_IPHONE_69"] = set.checksums
    }

    let step = set.mediaStep(actual)
    #expect(step == nil, "an unchanged set planned \(step?.uploadCount ?? 0) uploads")
}

@Test func aScreenshotThatChangedStillUploadsTheSet() throws {
    let set = try ScreenshotSet()
    defer { set.cleanUp() }

    let actual = liveState { apple in
        apple.liveScreenshotChecksumOrder["en-US/APP_IPHONE_69"] =
            [set.checksums[0], "a-checksum-from-the-old-picture"]
    }

    let step = try! #require(set.mediaStep(actual))
    #expect(step.uploadCount == 2)
}

@Test func reorderingTheSameScreenshotsIsAChange() throws {
    let set = try ScreenshotSet()
    defer { set.cleanUp() }

    // The same two files, the other way round. The store shows them in order,
    // so this is a real edit and a set compare would have missed it.
    let actual = liveState { apple in
        apple.liveScreenshotChecksumOrder["en-US/APP_IPHONE_69"] = set.checksums.reversed()
    }

    #expect(set.mediaStep(actual) != nil)
}

@Test func aDraftSetWinsOverTheLiveOne() throws {
    let set = try ScreenshotSet()
    defer { set.cleanUp() }

    // The draft exists and holds something else. It is the version being
    // written, so the live set says nothing about what an upload would replace.
    let actual = liveState { apple in
        apple.versionId = "version-9"
        apple.screenshotChecksumOrder["en-US/APP_IPHONE_69"] = ["stale", "stale-two"]
        apple.liveScreenshotChecksumOrder["en-US/APP_IPHONE_69"] = set.checksums
    }

    #expect(set.mediaStep(actual) != nil)
}

/// A read that never happened is not a store that matches.
///
/// The upload still goes, because an unknown set is not a matching one. But the
/// plan may not print it in the same green as a set it actually compared: an
/// update whose credentials had lapsed read "replace with 5 screenshots" with
/// no hint that nobody had checked.
@Test func screenshotsAreMarkedUnverifiedWhenTheStoreWasNeverRead() throws {
    let set = try ScreenshotSet()
    defer { set.cleanUp() }

    let unread = try! #require(set.mediaStep(ActualState()))
    #expect(unread.comparison == .unverified)

    // A read that happened and simply holds other pictures is verified.
    let compared = try! #require(set.mediaStep(liveState { apple in
        apple.liveScreenshotChecksumOrder["en-US/APP_IPHONE_69"] = ["old", "older"]
    }))
    #expect(compared.comparison == .verified)
}

@Test func aFirstPublishAlwaysUploadsItsScreenshots() throws {
    let set = try ScreenshotSet()
    defer { set.cleanUp() }

    // Nothing is live, so nothing is inherited. A checksum that matched here
    // would mean the pictures were already sent, which is a different app.
    #expect(set.mediaStep(ActualState()) != nil)
}

// MARK: - What the apply actually sends

private final class BodyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(method: String, path: String, body: [String: Any])] = []

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
        lock.withLock {
            entries.append((request.httpMethod ?? "", request.url?.path ?? "", body ?? [:]))
        }
    }

    /// The attribute names of the first call that matches, which is the whole
    /// question: a field named here is a field sent to Apple.
    func attributes(method: String, pathPrefix: String) -> Set<String>? {
        lock.withLock {
            guard let entry = entries.first(where: {
                $0.method == method && $0.path.hasPrefix(pathPrefix)
            }) else { return nil }
            let data = entry.body["data"] as? [String: Any] ?? [:]
            let attributes = data["attributes"] as? [String: Any] ?? [:]
            return Set(attributes.keys)
        }
    }

    var calls: [(method: String, path: String)] {
        lock.withLock { entries.map { ($0.method, $0.path) } }
    }
}

private final class LocaleStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var log = BodyLog()
    /// Whether Apple pre-filled the version this run created. It nearly always
    /// does for an update, and the run must not assume it.
    nonisolated(unsafe) static var prefills = true

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request)
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? ""
        let body: String

        if method == "POST", path == "/v1/appStoreVersions" {
            body = #"{"data":{"id":"version-new","type":"appStoreVersions"}}"#
        } else if method == "POST", path == "/v1/appStoreVersionLocalizations" {
            body = #"{"data":{"id":"loc-created","type":"appStoreVersionLocalizations"}}"#
        } else if method == "GET", path.hasSuffix("/appStoreVersionLocalizations") {
            body = Self.prefills
                ? """
                  {"data":[{"id":"loc-new","type":"appStoreVersionLocalizations",
                            "attributes":{"locale":"en-US"}}]}
                  """
                : #"{"data":[]}"#
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

private func stubbedRunner(steps: [PlanStep], manifest: Manifest,
                           actual: ActualState) -> Runner {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LocaleStubProtocol.self]
    var plan = PlanResult()
    plan.steps = steps
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return Runner(plan: plan, manifest: manifest, actual: actual, root: nil,
                  credentials: StoreCredentials(apple: credential), dryRun: false,
                  access: GrantAll(),
                  session: URLSession(configuration: configuration), emit: { _ in })
}

private func localeStep() -> PlanStep {
    PlanStep(id: "apple.locale.en-US", system: .apple, kind: .change, summary: "",
             title: "Write the en-US listing",
             requests: [RequestSketch("PATCH", "/v1/appStoreVersionLocalizations")],
             operation: .appleVersionLocale("en-US"))
}

private func createVersionStep() -> PlanStep {
    PlanStep(id: "apple.version", system: .apple, kind: .add, summary: "",
             title: "Create the version 3.2.0",
             requests: [RequestSketch("POST", "/v1/appStoreVersions")],
             operation: .appleEnsureVersion("3.2.0"))
}

@Suite(.serialized)
struct AppleUpdateApplyTests {

    /// The requirement, at the only place it can be observed: the request.
    ///
    /// A plan that names one field and a run that sends six is a run that
    /// re-sends five values the developer never touched.
    @Test func theApplyPatchesOnlyTheFieldThatChanged() async throws {
        LocaleStubProtocol.log = BodyLog()
        LocaleStubProtocol.prefills = true

        var manifest = updateManifest()
        manifest.setListingText("The 3.2.0 notes.", locale: "en-US", field: .whatsNew)
        let actual = liveState { apple in
            apple.versionId = "version-9"
            apple.versionLocales["en-US"] = liveLocale(id: "loc-9")
        }

        let runner = stubbedRunner(steps: [localeStep()], manifest: manifest, actual: actual)
        await runner.run()

        let sent = try #require(LocaleStubProtocol.log.attributes(
            method: "PATCH", pathPrefix: "/v1/appStoreVersionLocalizations/"))
        #expect(sent == ["whatsNew"])
    }

    /// The same rule through the path an update actually takes: no draft, so
    /// the run creates the version, Apple hands back the copy it pre-filled,
    /// and the baseline is the released version's text.
    @Test func aVersionThisRunCreatesInheritsTheReleasedTextAndPatchesTheRest() async throws {
        LocaleStubProtocol.log = BodyLog()
        LocaleStubProtocol.prefills = true

        var manifest = updateManifest()
        manifest.setListingText("The 3.2.0 notes.", locale: "en-US", field: .whatsNew)

        let runner = stubbedRunner(steps: [createVersionStep(), localeStep()],
                                   manifest: manifest, actual: liveState())
        await runner.run()

        let sent = try #require(LocaleStubProtocol.log.attributes(
            method: "PATCH", pathPrefix: "/v1/appStoreVersionLocalizations/"))
        #expect(sent == ["whatsNew"])
    }

    /// The other half, and the reason the skip is keyed on the id rather than
    /// on "this is an update". Apple usually pre-fills a new version and is not
    /// obliged to. When it hands back nothing, the localization is created from
    /// scratch and every managed field has to go, or the update ships a listing
    /// with no description.
    @Test func aLocalizationTheRunCreatesCarriesEveryManagedField() async throws {
        LocaleStubProtocol.log = BodyLog()
        LocaleStubProtocol.prefills = false

        var manifest = updateManifest()
        manifest.setListingText("The 3.2.0 notes.", locale: "en-US", field: .whatsNew)

        let runner = stubbedRunner(steps: [createVersionStep(), localeStep()],
                                   manifest: manifest, actual: liveState())
        await runner.run()

        let sent = try #require(LocaleStubProtocol.log.attributes(
            method: "POST", pathPrefix: "/v1/appStoreVersionLocalizations"))
        #expect(sent == ["locale", "description", "whatsNew", "keywords",
                         "promotionalText", "supportUrl", "marketingUrl"])
    }

    @Test func anUpdateWithNothingToSayMakesNoCallAtAll() async throws {
        LocaleStubProtocol.log = BodyLog()
        LocaleStubProtocol.prefills = true

        // A stale plan, or a retry after the write already landed. The step
        // exists and there is still nothing to send.
        let actual = liveState { apple in
            apple.versionId = "version-9"
            apple.versionLocales["en-US"] = liveLocale(id: "loc-9")
        }

        let runner = stubbedRunner(steps: [localeStep()], manifest: updateManifest(),
                                   actual: actual)
        await runner.run()

        #expect(!LocaleStubProtocol.log.calls.contains {
            $0.path.hasPrefix("/v1/appStoreVersionLocalizations")
                && ($0.method == "PATCH" || $0.method == "POST")
        })
    }
}

// MARK: - The once-per-app declarations

private func rows(_ manifest: Manifest, _ actual: ActualState) -> [ConsoleRow] {
    ConsoleChecklist.rows(manifest: manifest, actual: actual, stores: [.apple])
}

private func row(_ id: String, _ manifest: Manifest, _ actual: ActualState) -> ConsoleRow? {
    rows(manifest, actual).first { $0.id == id }
}

/// The rows that Apple asks once per app, and that no read can always confirm.
private let oncePerApp = ["apple.privacy", "apple.info", "apple.ageRating",
                          "apple.pricing", "apple.business"]

@Test func aPublishedAppDoesNotBlockOnTheOncePerAppDeclarations() {
    // No categories read, no price in the manifest: the two reads that used to
    // produce a needed row. The app is on the App Store, so both were answered
    // before it got there.
    let rows = rows(updateManifest(), liveState())

    for id in oncePerApp {
        let found = try! #require(rows.first { $0.id == id }, "\(id) is missing")
        #expect(found.state == .done, "\(id) is \(found.state.label) on a published app")
    }
    // The gate reads `.needed` and nothing else, so this is the assertion that
    // the release button actually opens.
    #expect(!rows.filter { oncePerApp.contains($0.id) }.contains { $0.state == .needed })
}

@Test func anAssumedRowSaysThatItWasAssumed() {
    // A row that reads Done with no reason is a row that lies. Each one that
    // nobody confirmed says who assumed it and why.
    let assumed = rows(updateManifest(), liveState())
        .filter { oncePerApp.contains($0.id) && $0.reason.contains(ConsoleChecklist.assumed) }
    #expect(assumed.count == oncePerApp.count)
}

@Test func aReadThatDoesSurfaceTheAnswerIsConfirmedAndNotAssumed() {
    // An assumption is the fallback, never the first answer. Where the API
    // does report the value, the row says so and names it.
    let actual = liveState { $0.primaryCategory = "PRODUCTIVITY" }
    let info = try! #require(row("apple.info", updateManifest(), actual))

    #expect(info.state == .done)
    #expect(info.reason.contains("PRODUCTIVITY"))
    #expect(!info.reason.contains(ConsoleChecklist.assumed))
}

/// The declaration Apple does answer, so the app asks rather than assumes.
///
/// The read is already on the state, filled from Apple's own questionnaire, so
/// "detect it" costs one lookup. The assumption is the fallback for a read that
/// never arrived, and it does not apply to an app that has never shipped.
@Test func theAgeRatingIsReadWhereApplePublishesItAndAssumedOnlyWhereItDoesNot() {
    let read: (inout ActualState.Apple) -> Void = {
        $0.ageRating["violenceCartoonOrFantasy"] = .text("NONE")
    }

    let confirmed = try! #require(row("apple.ageRating", updateManifest(), liveState(read)))
    #expect(confirmed.state == .done)
    #expect(!confirmed.reason.contains(ConsoleChecklist.assumed))

    // The same read on an app that has never shipped. It is the API's answer
    // either way, and the app never had to guess.
    var first = ActualState()
    first.apple = ActualState.Apple()
    read(&first.apple!)
    #expect(row("apple.ageRating", updateManifest(), first)?.state == .done)

    // No read, and the app is on the store, so it was answered to get there.
    let assumed = try! #require(row("apple.ageRating", updateManifest(), liveState()))
    #expect(assumed.state == .done)
    #expect(assumed.reason.contains(ConsoleChecklist.assumed))
}

@Test func aFirstPublishStillAsksForTheDeclarations() {
    // Nothing is live, so nothing was ever answered, and these are exactly the
    // rows a first submission has to work through.
    let first = rows(updateManifest(), ActualState())

    #expect(first.first { $0.id == "apple.info" }?.state == .needed)
    #expect(first.first { $0.id == "apple.pricing" }?.state == .needed)
    // No API answer in hand, so a first publish leaves these for the developer
    // to tick by hand. A failed read may not hold the button on a guess.
    #expect(first.first { $0.id == "apple.privacy" }?.state == .unknown)
    #expect(first.first { $0.id == "apple.business" }?.state == .unknown)
    #expect(first.first { $0.id == "apple.ageRating" }?.state == .unknown)
    #expect(!first.contains { oncePerApp.contains($0.id) && $0.reason.contains(ConsoleChecklist.assumed) })
}

@Test func theVersionRowStillHoldsTheButtonOnAnUpdate() {
    // Not a declaration. An update genuinely has no version to release until
    // the apply creates one, and assuming that away would open the button on
    // nothing.
    #expect(row("apple.version", updateManifest(), liveState())?.state == .needed)
}

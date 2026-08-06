import Foundation
import Testing
@testable import SubmitKit

/// The features that neither store side reached before.
///
/// TestFlight is the App Store twin of the Google track testers, and the
/// customer reviews are the twin of the Play reviews. Both used to exist on
/// one side only.

private func testFlightManifest(
    _ testFlight: Manifest.Release.TestFlight) -> Manifest {
    var manifest = appleManifest()
    manifest.release?.apple = Manifest.Release.AppleRelease(testFlight: testFlight)
    return manifest
}

// MARK: - TestFlight

@Test func aTestFlightGroupAppleAlreadyHoldsIsNotCreatedTwice() {
    let manifest = testFlightManifest(Manifest.Release.TestFlight(
        groups: [Manifest.Release.TestFlight.Group(name: "QA")]))
    let actual = appleState { apple in
        apple.betaGroups["QA"] = AppleTestFlightClient.BetaGroup(id: "1", name: "QA")
    }

    #expect(!steps(manifest, actual).contains { $0.id == "apple.betaGroup.QA" })
    #expect(steps(manifest, appleState { _ in })
        .contains { $0.id == "apple.betaGroup.QA" })
}

/// Apple emails every address it does not already hold, so the step carries
/// the difference and never the whole list.
@Test func onlyTheTestersAppleDoesNotHoldAreInvited() throws {
    let manifest = testFlightManifest(Manifest.Release.TestFlight(
        groups: [Manifest.Release.TestFlight.Group(
            name: "QA", testers: ["old@example.com", "new@example.com"])]))
    let actual = appleState { apple in
        var group = AppleTestFlightClient.BetaGroup(id: "1", name: "QA")
        group.testers = ["old@example.com"]
        apple.betaGroups["QA"] = group
    }

    let step = try #require(steps(manifest, actual)
        .first { $0.id == "apple.betaTesters.QA" })

    #expect(step.summary.contains("1 of 2"))
    #expect(step.operation == .appleBetaTesters(group: "QA", emails: ["new@example.com"]))
}

@Test func aGroupThatHoldsEveryTesterNeedsNoInvitation() {
    let manifest = testFlightManifest(Manifest.Release.TestFlight(
        groups: [Manifest.Release.TestFlight.Group(name: "QA",
                                                   testers: ["Old@Example.com"])]))
    let actual = appleState { apple in
        var group = AppleTestFlightClient.BetaGroup(id: "1", name: "QA")
        // Apple lower-cases the address it stores.
        group.testers = ["old@example.com"]
        apple.betaGroups["QA"] = group
    }

    #expect(!steps(manifest, actual).contains { $0.id == "apple.betaTesters.QA" })
}

@Test func aBuildReachesAGroupOnceAndTheNotesCompare() {
    let manifest = testFlightManifest(Manifest.Release.TestFlight(
        groups: [Manifest.Release.TestFlight.Group(name: "QA")],
        whatToTest: ["en-US": "Try the new tab."]))
    let held = appleState { apple in
        apple.attachedBuildId = "900"
        var group = AppleTestFlightClient.BetaGroup(id: "1", name: "QA")
        group.buildIds = ["900"]
        apple.betaGroups["QA"] = group
        apple.whatToTest = ["en-US": "Try the new tab."]
    }
    let missing = appleState { apple in
        apple.attachedBuildId = "900"
        apple.betaGroups["QA"] = AppleTestFlightClient.BetaGroup(id: "1", name: "QA")
        apple.whatToTest = ["en-US": "An older note."]
    }

    let quiet = steps(manifest, held)
    #expect(!quiet.contains { $0.id == "apple.betaBuild.QA" })
    #expect(!quiet.contains { $0.id == "apple.whatToTest" })

    let busy = steps(manifest, missing)
    #expect(busy.contains { $0.id == "apple.betaBuild.QA" })
    #expect(busy.contains { $0.id == "apple.whatToTest" })
}

/// The beta review takes a place in a queue and no call takes it back, so it
/// never repeats once Apple holds a submission.
@Test func theBetaReviewRunsOnceAndNeverAgain() {
    let manifest = testFlightManifest(
        Manifest.Release.TestFlight(submitForBetaReview: true))
    let submitted = appleState { apple in apple.betaReviewSubmitted = true }
    let notYet = appleState { apple in apple.betaReviewSubmitted = false }

    #expect(!steps(manifest, submitted).contains { $0.id == "apple.betaReview" })
    #expect(steps(manifest, notYet).contains { $0.id == "apple.betaReview" })
}

@Test func aManifestWithoutTestFlightWritesNothing() {
    #expect(!steps(appleManifest(), appleState { _ in })
        .contains { $0.id.hasPrefix("apple.beta") })
}

@Test func aBetaGroupPayloadParsesItsPublicLink() throws {
    let group = try #require(AppleTestFlightClient.parseGroup(json("""
    {"id":"g1","attributes":{"name":"QA","publicLinkEnabled":true,
     "publicLinkLimit":500,"hasAccessToAllBuilds":false}}
    """)))

    #expect(group.name == "QA")
    #expect(group.publicLink == true)
    #expect(group.publicLinkLimit == 500)
    #expect(group.automaticBuilds == false)
    #expect(AppleTestFlightClient.parseGroup(json("{}")) == nil)
}

// MARK: - The App Store customer reviews

@Test func anAppleReviewPayloadCarriesItsPublishedReply() throws {
    let reviews = [json("""
    {"id":"r1","attributes":{"reviewerNickname":"A Reader","title":"Good",
      "body":"It works.","rating":4,"territory":"USA",
      "createdDate":"2026-07-01T10:00:00-07:00"},
     "relationships":{"response":{"data":{"id":"resp1"}}}}
    """)]
    let responses = ["resp1": (id: "resp1", body: Optional("Thank you."))]

    let review = try #require(AppleActionsClient.parseReview(reviews[0],
                                                             responses: responses))

    #expect(review.authorName == "A Reader")
    #expect(review.title == "Good")
    #expect(review.starRating == 4)
    #expect(review.territory == "USA")
    #expect(review.responseId == "resp1")
    #expect(review.developerReply == "Thank you.")
    #expect(review.lastModified != nil)
}

@Test func aReviewWithoutAnIdIsSkippedInsteadOfCrashing() {
    #expect(AppleActionsClient.parseReview(json("{}"), responses: [:]) == nil)
}

/// The same guard the Google reply carries, at the limit Apple sets.
@Test func anEmptyOrOversizedAppleReplyNeverReachesTheStore() async {
    let client = AppleActionsClient(api: StoreAPI(credentials: StoreCredentials(),
                                                  record: { _ in }))
    let tooLong = String(repeating: "x", count: AppleActionsClient.replyLimit + 1)

    for text in ["", "   ", tooLong] {
        do {
            _ = try await client.replyToReview(reviewId: "r1", responseId: nil, text: text)
            Issue.record("The reply \(text.count) characters long should be refused.")
        } catch ConnectionError.http(let status, _) {
            #expect(status == 400)
        } catch {
            Issue.record("The reply failed with the wrong error: \(error)")
        }
    }
}

// MARK: - The export compliance declaration and the offer codes

@Test func anEncryptionDeclarationTakesItsOwnStepBesideTheBuildFlag() throws {
    var manifest = appleManifest()
    manifest.review = Manifest.Review(usesNonExemptEncryption: true)
    manifest.review?.encryption = Manifest.Encryption(exempt: false,
                                                      documentPath: "legal/ccats.pdf")

    let step = try #require(steps(manifest, appleState { _ in })
        .first { $0.id == "apple.encryption" })

    #expect(step.summary.contains("with a document"))
    #expect(step.operation == .appleEncryptionDeclaration)
    // A manifest that answers the question and owes no declaration keeps only
    // the build flag.
    var plain = appleManifest()
    plain.review = Manifest.Review(usesNonExemptEncryption: false)
    #expect(!steps(plain, appleState { _ in }).contains { $0.id == "apple.encryption" })
}

@Test func aPurchaseOfferCodeTakesItsOwnStepAndNamesItsProduct() throws {
    var manifest = appleManifest()
    manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable,
        offers: [Manifest.Offer(id: "LAUNCH25", kind: .offerCode, duration: "P1M"),
                 Manifest.Offer(id: "trial", kind: .freeTrial, duration: "P1W")])]

    let step = try #require(steps(manifest, appleState { _ in })
        .first { $0.id == "apple.purchaseOfferCodes.com.example.pro" })

    // One of the two offers is a code. The other belongs to the Google side.
    #expect(step.summary.contains("1 offer codes"))
    #expect(step.summary.contains("draft"))
    #expect(AppleApplyEligibility.check())
}

/// The eligibility words that App Store Connect accepts.
enum AppleApplyEligibility {
    static func check() -> Bool {
        Runner.appleEligibility(.new) == "NEW"
            && Runner.appleEligibility(.existing) == "EXISTING"
            && Runner.appleEligibility(.winBack) == "EXPIRED"
    }
}

// MARK: - The preorder that charges every customer

@Test func endingAPreOrderTakesTheLastAppleRow() throws {
    var manifest = appleManifest()
    manifest.pricing = Manifest.Pricing(
        base: Price(amount: 4.99, currency: "USD", territory: "USA"),
        territories: [Manifest.TerritoryAvailability(territory: "USA", available: true,
                                                     endPreOrder: true)])

    let apple = steps(manifest, appleState { _ in })
    let step = try #require(apple.first { $0.id == "apple.endPreOrder" })

    #expect(step.summary.contains("every pre-order is charged"))
    #expect(apple.last?.id == "apple.endPreOrder")
    // A manifest that names no end keeps the row away.
    manifest.pricing?.territories = [Manifest.TerritoryAvailability(territory: "USA")]
    #expect(!steps(manifest, appleState { _ in }).contains { $0.id == "apple.endPreOrder" })
}

// MARK: - The APKs Google signs

@Test func theGeneratedAPKListNamesEverySplitAndTheUniversalOne() {
    let apks = GoogleActionsClient.parseGeneratedAPKs(json("""
    {"generatedApks":[{
      "generatedSplitApks":[
        {"downloadId":"d1","moduleName":"base","splitId":"config.arm64_v8a"},
        {"downloadId":"d2","moduleName":"base"}],
      "generatedUniversalApk":{"downloadId":"d3"}}]}
    """), packageName: "com.example.app", versionCode: 42)

    #expect(apks.map(\.kind) == ["base.config.arm64_v8a", "base", "universal"])
    #expect(apks.allSatisfy { $0.versionCode == 42 })
    #expect(apks[0].downloadPath.contains("generatedApks/42/downloads/d1"))
}

// MARK: - The vitals, and the refunds the app only reads

@Test func theGoogleVitalsAverageTheDaysGoogleReturns() {
    let rows = json("""
    {"rows":[
      {"metrics":[{"metric":"userPerceivedCrashRate",
                   "decimalValue":{"value":"0.01"}}]},
      {"metrics":[{"metric":"userPerceivedCrashRate",
                   "decimalValue":{"value":"0.03"}}]}]}
    """)["rows"].array

    let average = StoreVitalsClient.average(rows, metric: "userPerceivedCrashRate")

    #expect(average != nil)
    #expect(StoreVitalsClient.percent(average!) == "2.00 %")
    // A metric nobody reported averages nothing rather than zero.
    #expect(StoreVitalsClient.average(rows, metric: "userPerceivedAnrRate") == nil)
}

@Test func anApplePerformancePayloadReadsIntoNamedRows() {
    let metrics = StoreVitalsClient.parseAppleMetrics(json("""
    {"productData":[{"metricCategories":[
      {"identifier":"LAUNCH","metrics":[
        {"identifier":"LAUNCH_TIME","unit":"ms",
         "datasets":[{"points":[{"value":842}]}]}]}]}]}
    """))

    #expect(metrics.count == 1)
    #expect(metrics[0].name == "Launch  Launch time")
    #expect(metrics[0].value == "842 ms")
    #expect(StoreVitalsClient.title("USER_PERCEIVED") == "User perceived")
}

@Test func aVoidedPurchaseNamesItsReasonAndItsSource() throws {
    let voided = try #require(StoreVitalsClient.parseVoided(json("""
    {"purchaseToken":"tok1","orderId":"GPA.1","voidedTimeMillis":"1700000000000",
     "voidedReason":1,"voidedSource":0}
    """)))

    #expect(voided.orderId == "GPA.1")
    #expect(voided.reason == "Remorse")
    #expect(voided.source == "User")
    #expect(voided.voidedAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(StoreVitalsClient.parseVoided(json("{}")) == nil)
}

/// The app reads the refunds and issues none. A refund moves real money, so
/// no code path here sends one.
@Test func noCodePathIssuesARefund() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let sources = try FileManager.default
        .subpathsOfDirectory(atPath: root.appendingPathComponent("Sources").path)
        .filter { $0.hasSuffix(".swift") }

    for path in sources {
        let text = try String(
            contentsOf: root.appendingPathComponent("Sources").appendingPathComponent(path),
            encoding: .utf8)
        #expect(!text.contains(":refund"), "\(path) reaches the refund endpoint.")
        #expect(!text.contains("orders/") || !text.contains("refund"),
                "\(path) reaches the order refund endpoint.")
    }
}

// MARK: - Xcode Cloud

@Test func anXcodeCloudWorkflowAndRunParseIntoTheirRows() throws {
    let workflow = try #require(XcodeCloudClient.parseWorkflow(json("""
    {"id":"w1","attributes":{"name":"Release","isEnabled":true}}
    """), productName: "Example"))

    #expect(workflow.name == "Release")
    #expect(workflow.productName == "Example")
    #expect(workflow.enabled)

    let run = try #require(XcodeCloudClient.parseRun(json("""
    {"id":"r1","attributes":{"number":42,"executionProgress":"COMPLETE",
     "completionStatus":"SUCCEEDED","startedDate":"2026-07-01T10:00:00Z"}}
    """)))

    #expect(run.number == 42)
    #expect(run.state == "SUCCEEDED")
    #expect(run.startedAt != nil)

    // A run that is still going names its progress rather than nothing.
    let running = try #require(XcodeCloudClient.parseRun(json("""
    {"id":"r2","attributes":{"number":43,"executionProgress":"RUNNING"}}
    """)))
    #expect(running.state == "RUNNING")

    #expect(XcodeCloudClient.parseWorkflow(json("{}"), productName: "x") == nil)
    #expect(XcodeCloudClient.parseRun(json("{}")) == nil)
}

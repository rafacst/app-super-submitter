import Foundation
import Testing
@testable import SubmitKit

// MARK: - The diagnostic signatures and their logs

@Test func aDiagnosticSignatureParsesAndCarriesItsShare() throws {
    let signature = try #require(AppleDiagnosticsClient.parseSignature(json("""
    {"id":"s1","attributes":{"diagnosticType":"DISK_WRITES",
     "signature":"ExampleApp: -[Database executeSQL:]","weight":0.85}}
    """)))

    #expect(signature.diagnosticType == "DISK_WRITES")
    #expect(signature.share == "85 %")
    // A signature Apple sends without a weight shows no share rather than 0 %.
    let unweighted = try #require(AppleDiagnosticsClient.parseSignature(json("""
    {"id":"s2","attributes":{"signature":"x"}}
    """)))
    #expect(unweighted.share == nil)
    #expect(AppleDiagnosticsClient.parseSignature(json("{}")) == nil)
}

/// The whole point of the log rows: 40 frames come back and 35 of them are
/// system libraries, so only the frames Apple blames on the app are kept, and
/// they stay in the order they were called.
@Test func onlyTheFramesAppleBlamesOnTheAppSurvive() throws {
    let logs = AppleDiagnosticsClient.parseLogs(json("""
    {"productData":[{"signatureId":"s1","diagnosticLogs":[{
      "diagnosticMetaData":{"event":"disk writes","osVersion":"iPhone OS 18.0",
        "appVersion":"6.10.1","deviceType":"iPhone13_3",
        "eventDetail":"Total of 1073.76 MB of disk writes"},
      "callStackTree":[{"callStacks":[{"callStackRootFrames":[
        {"rawFrame":"libdispatch","isBlameFrame":false,"subFrames":[
          {"rawFrame":"MyApp updateNames","isBlameFrame":true,"subFrames":[
            {"rawFrame":"MyApp readRows","isBlameFrame":true,"subFrames":[]}]}]}
      ]}]}]
    }]}]}
    """))

    let log = try #require(logs.first)
    #expect(log.deviceType == "iPhone13_3")
    #expect(log.appVersion == "6.10.1")
    #expect(log.detail == "Total of 1073.76 MB of disk writes")
    #expect(log.frames == ["MyApp updateNames", "MyApp readRows"])
}

@Test func betaFeedbackReadsTheTesterThroughTheIncludedRow() throws {
    let testers = AppleDiagnosticsClient.testerEmails(json("""
    [{"type":"betaTesters","id":"t1","attributes":{"email":"anna@example.org"}}]
    """))
    let feedback = try #require(AppleDiagnosticsClient.parseFeedback(json("""
    {"id":"f1","attributes":{"comment":"It froze on the paywall",
      "deviceModel":"iPhone15,2","osVersion":"18.1",
      "screenshots":[{"url":"https://example.org/a.png"}]},
     "relationships":{"tester":{"data":{"id":"t1"}}}}
    """), kind: .screenshot, testers: testers))

    #expect(feedback.testerEmail == "anna@example.org")
    #expect(feedback.comment == "It froze on the paywall")
    #expect(feedback.screenshots.count == 1)
    #expect(AppleDiagnosticsClient.parseFeedback(json("{}"), kind: .crash,
                                                  testers: [:]) == nil)
}

// MARK: - The two provisioning writes

/// Apple refuses a malformed identifier with a 409 that names nothing, so the
/// refusal happens here where it can name the field.
@Test func onlyARealDeviceIdentifierPassesTheCheck() {
    #expect(AppleProvisioningClient.looksLikeAUDID(
        "00008030001C2D6A3E80802E00008030001C2D6A"))
    #expect(AppleProvisioningClient.looksLikeAUDID("00008030-001C2D6A3E80802E"))
    // A Mac gives a 36-character UUID.
    #expect(AppleProvisioningClient.looksLikeAUDID(
        "5F3A1B2C-4D5E-6F70-8192-A3B4C5D6E7F8"))

    #expect(!AppleProvisioningClient.looksLikeAUDID(""))
    #expect(!AppleProvisioningClient.looksLikeAUDID("not a udid"))
    #expect(!AppleProvisioningClient.looksLikeAUDID("00008030 001C2D6A"))
    #expect(!AppleProvisioningClient.looksLikeAUDID("zzzz8030001C2D6A3E80802E"))
    #expect(!AppleProvisioningClient.looksLikeAUDID("abc123"))
}

@Test func aBundleIDIsReverseDNSOrItIsRefused() {
    #expect(AppleProvisioningClient.looksLikeABundleID("org.super.submitter"))
    #expect(AppleProvisioningClient.looksLikeABundleID("org.super-submitter.app2"))
    // A wildcard is legal in a bundle ID, and Apple takes it.
    #expect(AppleProvisioningClient.looksLikeABundleID("org.super.*"))

    #expect(!AppleProvisioningClient.looksLikeABundleID("submitter"))
    #expect(!AppleProvisioningClient.looksLikeABundleID("org..submitter"))
    #expect(!AppleProvisioningClient.looksLikeABundleID("org.super submitter"))
    #expect(!AppleProvisioningClient.looksLikeABundleID(""))
}

// MARK: - The finance report

/// Apple closes a month several weeks after it ends, so the default has to be
/// a month that can already exist.
@Test func theDefaultFinanceMonthIsTwoMonthsBack() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let march = try #require(calendar.date(from: DateComponents(
        timeZone: calendar.timeZone, year: 2026, month: 3, day: 14)))
    #expect(AppleReportsClient.defaultFinanceMonth(from: march) == "2026-01")

    // The year has to roll back with the month.
    let january = try #require(calendar.date(from: DateComponents(
        timeZone: calendar.timeZone, year: 2026, month: 1, day: 5)))
    #expect(AppleReportsClient.defaultFinanceMonth(from: january) == "2025-11")
}

// MARK: - The team

@Test func aUserAndAnInvitationReadIntoTheSameRow() throws {
    let user = try #require(AppleTeamClient.parse(json("""
    {"id":"u1","attributes":{"username":"anna@example.org","firstName":"Anna",
      "lastName":"Lee","roles":["APP_MANAGER"],"allAppsVisible":false,
      "provisioningAllowed":true},
     "relationships":{"visibleApps":{"data":[{"id":"a1"},{"id":"a2"}]}}}
    """), pending: false))

    #expect(user.email == "anna@example.org")
    #expect(user.name == "Anna Lee")
    #expect(user.visibleApps == ["a1", "a2"])
    #expect(!user.isAccountOwner)

    // An invitation names the address `email` and carries no username at all.
    let invited = try #require(AppleTeamClient.parse(json("""
    {"id":"i1","attributes":{"email":"bo@example.org","roles":["DEVELOPER"],
      "allAppsVisible":true}}
    """), pending: true))
    #expect(invited.email == "bo@example.org")
    #expect(invited.pending)
    #expect(invited.allAppsVisible)

    let owner = try #require(AppleTeamClient.parse(json("""
    {"id":"u2","attributes":{"username":"chris@example.org",
      "roles":["ACCOUNT_HOLDER"]}}
    """), pending: false))
    #expect(owner.isAccountOwner)

    #expect(AppleTeamClient.parse(json("{\"id\":\"u3\"}"), pending: false) == nil)
}

// MARK: - The webhooks

@Test func aWebhookAndItsDeliveryParseIntoTheirRows() throws {
    let hook = try #require(AppleWebhooksClient.parseHook(json("""
    {"id":"h1","attributes":{"name":"Release states",
      "url":"https://hooks.invalid/appstore","enabled":true,
      "eventTypes":["BUILD_UPLOAD_STATE_UPDATED"]}}
    """)))
    #expect(hook.eventTypes == ["BUILD_UPLOAD_STATE_UPDATED"])

    let delivery = try #require(AppleWebhooksClient.parseDelivery(json("""
    {"id":"d1","attributes":{"deliveryState":"FAILED",
      "createdDate":"2026-07-01T10:00:00Z","errorMessage":"connection refused",
      "response":{"httpStatusCode":502},"redelivery":true}}
    """)))
    #expect(delivery.state == "FAILED")
    #expect(delivery.responseStatus == 502)
    #expect(delivery.redelivery)
    #expect(delivery.createdDate != nil)
}

/// Apple never gives the secret back, so the panel that sends one has to know
/// the refusals before it spends a round trip on them.
@Test func aWebhookNeedsHTTPSAnEventAndASecret() async throws {
    let client = AppleWebhooksClient(api: StoreAPI(credentials: StoreCredentials(),
                                                    record: { _ in }))
    await #expect(throws: ConnectionError.self) {
        try await client.create(appID: "a1", name: "x", url: "http://hooks.invalid",
                                secret: "s", eventTypes: ["BUILD_UPLOAD_STATE_UPDATED"])
    }
    await #expect(throws: ConnectionError.self) {
        try await client.create(appID: "a1", name: "x", url: "https://hooks.invalid",
                                secret: "s", eventTypes: [])
    }
    await #expect(throws: ConnectionError.self) {
        try await client.create(appID: "a1", name: "x", url: "https://hooks.invalid",
                                secret: "", eventTypes: ["BUILD_UPLOAD_STATE_UPDATED"])
    }
}

// MARK: - The sandbox

@Test func aSandboxTesterReadsItsAccountAndItsRenewalRate() throws {
    let tester = try #require(AppleSandboxClient.parse(json("""
    {"id":"t1","attributes":{"firstName":"Anne","lastName":"Johnson",
      "acAccountName":"anne@icloud.invalid","territory":"USA",
      "applePayCompatible":true,"interruptPurchases":false,
      "subscriptionRenewalRate":"MONTHLY_RENEWAL_EVERY_FIVE_MINUTES"}}
    """)))

    #expect(tester.appleAccount == "anne@icloud.invalid")
    #expect(tester.name == "Anne Johnson")
    #expect(!tester.interruptPurchases)
    #expect(AppleSandboxClient.renewalRates.contains {
        $0.value == tester.renewalRate
    })
    #expect(AppleSandboxClient.parse(json("{}")) == nil)
}

// MARK: - The versioned subscription drafts

@Test func aSubscriptionDraftIsEditableOnlyBeforeItIsSubmitted() throws {
    let open = try #require(AppleSubscriptionVersionsClient.parseDraft(json("""
    {"id":"v1","attributes":{"version":3,"state":"PREPARE_FOR_SUBMISSION"}}
    """)))
    #expect(open.version == 3)
    #expect(open.isEditable)

    let waiting = try #require(AppleSubscriptionVersionsClient.parseDraft(json("""
    {"id":"v2","attributes":{"version":4,"state":"WAITING_FOR_REVIEW"}}
    """)))
    #expect(!waiting.isEditable)

    #expect(AppleSubscriptionVersionsClient.parseDraft(json("{}")) == nil)
}

// MARK: - Why an Xcode Cloud run failed

@Test func aBuildActionCountsItsIssuesAndAnArtifactNamesItsFile() throws {
    let action = try #require(XcodeCloudClient.parseAction(json("""
    {"id":"a1","attributes":{"name":"Test iOS","actionType":"TEST",
      "completionStatus":"FAILED","executionProgress":"COMPLETE",
      "issueCounts":{"errors":2,"warnings":7,"testFailures":3}}}
    """)))
    #expect(action.state == "FAILED")
    #expect(action.issues == "2 errors  ·  3 test failures  ·  7 warnings")

    // A clean step says nothing rather than "0 errors".
    let clean = try #require(XcodeCloudClient.parseAction(json("""
    {"id":"a2","attributes":{"name":"Archive","completionStatus":"SUCCEEDED",
      "issueCounts":{"errors":0,"warnings":0,"testFailures":0}}}
    """)))
    #expect(clean.issues == nil)

    let artifact = try #require(XcodeCloudClient.parseArtifact(json("""
    {"id":"f1","attributes":{"fileName":"logs.zip","fileType":"LOG_BUNDLE",
      "fileSize":4096,"downloadUrl":"https://artifacts.invalid/logs.zip"}}
    """)))
    #expect(artifact.fileName == "logs.zip")
    #expect(artifact.downloadURL != nil)

    let failure = try #require(XcodeCloudClient.parseTestResult(json("""
    {"id":"r1","attributes":{"name":"testPaywall","className":"PaywallTests",
      "status":"FAILURE","message":"expected 1, got 0"}}
    """)))
    #expect(failure.className == "PaywallTests")
    #expect(failure.status == "FAILURE")
}

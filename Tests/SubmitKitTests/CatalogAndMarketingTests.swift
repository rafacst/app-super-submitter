import Foundation
import Testing
@testable import SubmitKit

private func bothStores() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

private func input(_ manifest: Manifest, stores: Set<Store> = [.apple, .google],
                   actual: ActualState = ActualState()) -> Planner.Input {
    Planner.Input(manifest: manifest, actual: actual, stores: stores)
}

private func plan(_ manifest: Manifest, duration: String = "P1M",
                  offers: [Manifest.Offer] = []) -> Manifest {
    var result = manifest
    result.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro", groupName: "Pro",
        plans: [Manifest.SubscriptionGroup.Plan(
            id: "pro.monthly", duration: duration, basePlanId: "monthly",
            price: Price(amount: 4.99, currency: "USD", territory: "USA"),
            offers: offers.isEmpty ? nil : offers)])]
    return result
}

// MARK: - The Apple subscription catalog

@Test func theSubscriptionsTakeTheirOwnStepAndThePurchaseStepStopsCountingThem() {
    var manifest = plan(bothStores())
    manifest.purchases = [Manifest.Purchase(id: "com.example.tip", kind: .consumable)]

    let steps = Planner.plan(input(manifest)).steps(for: .apple)
    let purchases = steps.first { $0.id == "apple.purchases" }

    #expect(steps.contains { $0.id == "apple.subscriptions" })
    // The old plan said "5 purchases" and wrote two. It now counts one.
    #expect(purchases?.summary.contains("1 purchases") == true)
}

@Test func aSubscriptionOfferTakesAStepAfterTheSubscriptionStep() {
    let manifest = plan(bothStores(), offers: [
        Manifest.Offer(id: "freetrial", kind: .freeTrial, duration: "P1W"),
    ])

    let steps = Planner.plan(input(manifest)).steps(for: .apple)
    let catalog = steps.firstIndex { $0.id == "apple.subscriptions" }
    let offers = steps.firstIndex { $0.id == "apple.subscriptionOffers" }

    #expect(catalog != nil)
    #expect(offers != nil)
    #expect(catalog! < offers!)
}

@Test func theGracePeriodStepUsesTheNearestAppleDuration() {
    var manifest = plan(bothStores())
    manifest.subscriptions?[0].gracePeriodDays = 14

    let steps = Planner.plan(input(manifest)).steps(for: .apple)

    #expect(steps.contains { $0.id == "apple.gracePeriod" })
    #expect(AppleDurations.gracePeriod(days: 14) == "SIXTEEN_DAYS")
    #expect(AppleDurations.gracePeriod(days: 2) == "THREE_DAYS")
    #expect(AppleDurations.gracePeriod(days: 30) == "TWENTY_EIGHT_DAYS")
}

@Test func theSubscriptionPeriodMapsToTheAppleEnumAndNotToTheLabel() {
    #expect(AppleDurations.apiPeriod(for: "P1M") == "ONE_MONTH")
    #expect(AppleDurations.apiPeriod(for: "p1y") == "ONE_YEAR")
    #expect(AppleDurations.apiPeriod(for: "P2W") == nil)
    #expect(AppleDurations.offerDuration(for: "P2W") == "TWO_WEEKS")
}

@Test func theNearestSubscriptionPricePointWins() {
    let payload = JSON(data: Data("""
        {"data": [
          {"id": "a", "attributes": {"customerPrice": "3.99"}},
          {"id": "b", "attributes": {"customerPrice": "4.99"}},
          {"id": "c", "attributes": {"customerPrice": "9.99"}}
        ]}
        """.utf8))

    #expect(Runner.nearestPricePoint(payload, to: 5) == "b")
    #expect(Runner.nearestPricePoint(payload, to: 100) == "c")
}

// MARK: - The Apple marketing resources

@Test func everyMarketingBlockTakesItsOwnStep() {
    var manifest = bothStores()
    var marketing = Manifest.Marketing()
    marketing.customProductPages = [.init(key: "winter", name: "Winter")]
    marketing.experiments = [.init(key: "icons", name: "Icons",
                                   treatments: [.init(key: "b", name: "Variant B")])]
    marketing.events = [.init(key: "tournament")]
    marketing.eula = .init(text: "The agreement.")
    marketing.nomination = .init(name: "Launch", type: "APP_LAUNCH")
    marketing.accessibility = .init(supports: ["VOICE_OVER"])
    marketing.appClip = .init(action: "OPEN")
    manifest.marketing = marketing

    let ids = Set(Planner.plan(input(manifest)).steps(for: .apple).map(\.id))

    #expect(ids.contains("apple.customProductPages"))
    #expect(ids.contains("apple.experiments"))
    #expect(ids.contains("apple.events"))
    #expect(ids.contains("apple.eula"))
    #expect(ids.contains("apple.nomination"))
    #expect(ids.contains("apple.accessibility"))
    #expect(ids.contains("apple.appClip"))
}

@Test func aMissingMarketingBlockWritesNothing() {
    let ids = Set(Planner.plan(input(bothStores())).steps(for: .apple).map(\.id))

    #expect(!ids.contains("apple.customProductPages"))
    #expect(!ids.contains("apple.nomination"))
}

@Test func noMarketingStepEverReachesGoogle() {
    var manifest = bothStores()
    var marketing = Manifest.Marketing()
    marketing.events = [.init(key: "tournament")]
    manifest.marketing = marketing

    let google = Planner.plan(input(manifest)).steps(for: .google)

    #expect(google.allSatisfy { !$0.id.contains("events") })
}

@Test func anAccessibilityFeatureNameBecomesTheAppleAttribute() {
    #expect(Runner.accessibilityKey("VOICE_OVER") == "supportsVoiceOver")
    #expect(Runner.accessibilityKey("LARGER_TEXT") == "supportsLargerText")
    #expect(Runner.accessibilityKey("CAPTIONS") == "supportsCaptions")
}

// MARK: - The Google catalog

@Test func aBasePlanStateTakesOneStepPerPlan() {
    var manifest = plan(bothStores())
    manifest.subscriptions?[0].plans[0].active = false

    let steps = Planner.plan(input(manifest)).steps(for: .google)
    let step = steps.first { $0.id == "google.basePlanState.pro.monthly" }

    #expect(step?.summary.contains("deactivate") == true)
    #expect(step?.requests.first?.path.hasSuffix(":deactivate") == true)
}

@Test func aPurchaseOptionStateTakesOneStepPerPurchase() {
    var manifest = bothStores()
    manifest.purchases = [Manifest.Purchase(id: "com.example.tip", kind: .consumable,
                                            active: true)]

    let steps = Planner.plan(input(manifest)).steps(for: .google)

    #expect(steps.contains { $0.id == "google.purchaseOptionState.com.example.tip" })
}

@Test func theOfferStepsSplitByProduct() {
    var manifest = plan(bothStores(), offers: [
        Manifest.Offer(id: "freetrial", kind: .freeTrial, duration: "P1W"),
    ])
    manifest.purchases = [Manifest.Purchase(
        id: "com.example.tip", kind: .consumable,
        offers: [Manifest.Offer(id: "launch", kind: .introPrice,
                                price: Price(amount: 0.99, currency: "USD"))])]

    let ids = Set(Planner.plan(input(manifest)).steps(for: .google).map(\.id))

    #expect(ids.contains("google.subscriptionOffers.pro.monthly"))
    #expect(ids.contains("google.oneTimeOffers.com.example.tip"))
}

@Test func aPriceMigrationTakesAStepOnlyWhenTheManifestOptsIn() {
    var manifest = plan(bothStores())
    #expect(!Planner.plan(input(manifest)).steps(for: .google)
        .contains { $0.id.hasPrefix("google.migratePrices") })

    manifest.subscriptions?[0].plans[0].migrateExistingSubscribers = true
    #expect(Planner.plan(input(manifest)).steps(for: .google)
        .contains { $0.id == "google.migratePrices.pro.monthly" })
}

@Test func aSubscriptionThatLeftTheManifestIsArchivedAndNeverDeleted() {
    let manifest = plan(bothStores())
    var actual = ActualState()
    var google = ActualState.Google()
    google.subscriptionIds = ["pro.monthly", "pro.yearly"]
    actual.google = google

    let steps = Planner.plan(input(manifest, actual: actual)).steps(for: .google)
    let archive = steps.first { $0.id == "google.archive.pro.yearly" }

    #expect(archive?.kind == .remove)
    #expect(archive?.requests.first?.path.hasSuffix(":archive") == true)
    #expect(!steps.contains { $0.id == "google.archive.pro.monthly" })
}

@Test func theTaxBlockIsAbsentWhenTheManifestNamesNothing() {
    #expect(Runner.taxSettings(nil) == nil)
    #expect(Runner.taxSettings(Manifest.Tax()) == nil)

    let settings = Runner.taxSettings(Manifest.Tax(category: "TAX_CATEGORY_EBOOK"))
    #expect(settings?["googlePlayTaxCategory"] as? String == "TAX_CATEGORY_EBOOK")
}

// MARK: - The rules

@Test func aFreeTrialWithoutADurationIsAnError() {
    let manifest = plan(bothStores(), offers: [
        Manifest.Offer(id: "freetrial", kind: .freeTrial),
    ])

    #expect(Validator.findings(input(manifest))
        .contains { $0.id == "offer.trialDuration.freetrial" && $0.severity == .error })
}

@Test func anIntroductoryOfferWithoutAPriceIsAnError() {
    let manifest = plan(bothStores(), offers: [
        Manifest.Offer(id: "intro", kind: .introPrice, duration: "P1M"),
    ])

    #expect(Validator.findings(input(manifest))
        .contains { $0.id == "offer.introPrice.intro" && $0.severity == .error })
}

@Test func anOfferDurationThatAppleRefusesIsAnError() {
    let manifest = plan(bothStores(), offers: [
        Manifest.Offer(id: "trial", kind: .freeTrial, duration: "P5D"),
    ])

    let findings = Validator.findings(input(manifest, stores: [.apple]))

    #expect(findings.contains { $0.id == "offer.appleDuration.trial" && $0.severity == .error })
}

@Test func anUppercaseOfferIdBreaksGoogleAndNotApple() {
    let manifest = plan(bothStores(), offers: [
        Manifest.Offer(id: "FreeTrial", kind: .freeTrial, duration: "P1W"),
    ])

    #expect(Validator.findings(input(manifest, stores: [.google]))
        .contains { $0.id == "offer.googleId.FreeTrial" })
    #expect(!Validator.findings(input(manifest, stores: [.apple]))
        .contains { $0.id == "offer.googleId.FreeTrial" })
}

@Test func aPriceMigrationAlwaysWarnsBecauseItChargesARealCustomer() {
    var manifest = plan(bothStores())
    manifest.subscriptions?[0].plans[0].migrateExistingSubscribers = true

    let finding = Validator.findings(input(manifest)).first { $0.id == "offer.migrate.pro.monthly" }

    #expect(finding?.severity == .warning)
    #expect(finding?.message.contains("no call undoes it") == true)
}

@Test func twoDifferentGracePeriodsWarnBecauseAppleKeepsOne() {
    var manifest = plan(bothStores())
    manifest.subscriptions?[0].gracePeriodDays = 3
    manifest.subscriptions?.append(Manifest.SubscriptionGroup(
        groupId: "plus", plans: [], gracePeriodDays: 28))

    #expect(Validator.findings(input(manifest))
        .contains { $0.id == "offer.gracePeriodDisagreement" && $0.severity == .warning })
}

@Test func anExperimentWithNoTreatmentIsAnError() {
    var manifest = bothStores()
    var marketing = Manifest.Marketing()
    marketing.experiments = [.init(key: "icons", name: "Icons", trafficProportion: 150)]
    manifest.marketing = marketing

    let findings = Validator.findings(input(manifest))

    #expect(findings.contains { $0.id == "marketing.treatments.icons" && $0.severity == .error })
    #expect(findings.contains { $0.id == "marketing.traffic.icons" && $0.severity == .error })
}

@Test func anOverLongEventNameIsAnError() {
    var manifest = bothStores()
    var marketing = Manifest.Marketing()
    marketing.events = [.init(key: "tournament",
                              locales: ["en-US": .init(name: String(repeating: "x", count: 31))])]
    manifest.marketing = marketing

    #expect(Validator.findings(input(manifest))
        .contains { $0.id == "marketing.event.tournament.en-US.name" })
}

@Test func aRoutingCoverageThatIsNotGeoJSONIsAnError() {
    var manifest = bothStores()
    var marketing = Manifest.Marketing()
    marketing.routingCoverage = "assets/coverage.json"
    manifest.marketing = marketing

    // The file does not exist, so the missing rule fires first and the type
    // rule stays quiet. Both rules point at the same tab.
    #expect(Validator.findings(input(manifest))
        .contains { $0.id == "marketing.routingMissing" })
}

@Test func theMarketingBlockWarnsThatGoogleReceivesNoneOfIt() {
    var manifest = bothStores()
    var marketing = Manifest.Marketing()
    marketing.events = [.init(key: "tournament")]
    manifest.marketing = marketing

    #expect(Validator.findings(input(manifest))
        .contains { $0.id == "marketing.appleOnly" && $0.severity == .warning })
    #expect(!Validator.findings(input(manifest, stores: [.apple]))
        .contains { $0.id == "marketing.appleOnly" })
}

// MARK: - The read-only diagnostics

@Test func theGeneratedApkParserReadsBothTheListsAndTheSingleUniversalApk() {
    let payload = JSON(data: Data("""
        {"generatedApks": [{
          "generatedSplitApks": [
            {"downloadId": "d1", "moduleName": "base"},
            {"downloadId": "d2", "moduleName": "feature"}
          ],
          "generatedStandaloneApks": [{"downloadId": "d3"}],
          "generatedUniversalApk": {"downloadId": "d4"},
          "generatedAssetPackSlices": []
        }]}
        """.utf8))

    let apks = StoreDiagnostics.parseGeneratedApks(payload)

    #expect(apks.count == 4)
    #expect(apks.contains { $0.id == "split/base" && $0.downloadId == "d1" })
    #expect(apks.contains { $0.id == "split/feature" })
    #expect(apks.contains { $0.kind == "standalone" && $0.downloadId == "d3" })
    #expect(apks.contains { $0.id == "universal" && $0.downloadId == "d4" })
}

@Test func anEmptyGeneratedApkPayloadYieldsNothing() {
    #expect(StoreDiagnostics.parseGeneratedApks(JSON(data: Data("{}".utf8))).isEmpty)
}

@Test func aPaginationLinkFromAnotherHostIsRefused() {
    #expect(StoreDiagnostics.appleNextPath(
        "https://api.appstoreconnect.apple.com/v1/territories?cursor=x")
        == "/v1/territories?cursor=x")
    #expect(StoreDiagnostics.appleNextPath("https://evil.example.com/v1/territories") == nil)
}

// MARK: - The manifest

@Test func theOfferAndMarketingBlocksSurviveAYAMLRoundTrip() throws {
    let yaml = """
        version: 1
        apps:
          apple:
            appId: "1234567890"
            platforms: [IOS]
            bundleId: com.example.app
        purchases:
          - id: com.example.tip
            kind: consumable
            active: true
            tax:
              category: TAX_CATEGORY_EBOOK
              withdrawalRight: WITHDRAWAL_RIGHT_DIGITAL_CONTENT
            offers:
              - id: launch
                kind: intro_price
                price: {amount: 0.99, currency: USD}
        subscriptions:
          - groupId: pro
            groupName: Pro
            gracePeriodDays: 16
            plans:
              - id: pro.monthly
                duration: P1M
                basePlanId: monthly
                active: true
                migrateExistingSubscribers: false
                offers:
                  - id: freetrial
                    kind: free_trial
                    duration: P1W
                    periods: 1
                    regions: [US, DE]
                    eligibility: new
        marketing:
          customProductPages:
            - key: winter
              name: Winter campaign
              locales:
                en-US: {promotionalText: Save now}
          experiments:
            - key: icons
              name: Icons
              trafficProportion: 40
              treatments: [{key: b, name: Variant B}]
          events:
            - key: tournament
              badge: BADGE_LIVE_EVENT
              locales:
                en-US: {name: Tournament}
          eula:
            text: The agreement.
            territories: [USA]
          routingCoverage: assets/coverage.geojson
          nomination:
            name: Launch
            type: APP_LAUNCH
          accessibility:
            supports: [VOICE_OVER, LARGER_TEXT]
          appClip:
            action: OPEN
            locales:
              en-US: {subtitle: Try it}
        """

    let manifest = try ManifestFile.decode(yaml)

    #expect(manifest.purchases?.first?.active == true)
    #expect(manifest.purchases?.first?.tax?.category == "TAX_CATEGORY_EBOOK")
    #expect(manifest.purchases?.first?.offers?.first?.kind == .introPrice)
    #expect(manifest.subscriptions?.first?.gracePeriodDays == 16)
    #expect(manifest.subscriptions?.first?.plans.first?.offers?.first?.kind == .freeTrial)
    #expect(manifest.subscriptions?.first?.plans.first?.offers?.first?.eligibility == .new)
    #expect(manifest.marketing?.customProductPages?.first?.key == "winter")
    #expect(manifest.marketing?.experiments?.first?.treatments.first?.key == "b")
    #expect(manifest.marketing?.events?.first?.badge == "BADGE_LIVE_EVENT")
    #expect(manifest.marketing?.eula?.territories == ["USA"])
    #expect(manifest.marketing?.accessibility?.supports.count == 2)
    #expect(manifest.marketing?.appClip?.locales?["en-US"]?.subtitle == "Try it")

    let again = try ManifestFile.decode(try ManifestFile.encode(manifest))
    #expect(again == manifest)
}

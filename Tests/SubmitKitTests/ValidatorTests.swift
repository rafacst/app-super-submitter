import Foundation
import Testing
@testable import SubmitKit

private func base() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setReleaseVersionName("1.0.0")
    return manifest
}

private func findings(_ manifest: Manifest, _ actual: ActualState = ActualState(),
                      stores: Set<Store> = [.apple, .google],
                      packages: [AppPackage.Kind: AppPackage] = [:]) -> [Finding] {
    Validator.findings(Planner.Input(manifest: manifest, actual: actual, stores: stores,
                                     root: nil, packages: packages))
}

private func has(_ list: [Finding], _ id: String) -> Bool {
    list.contains { $0.id == id }
}

// MARK: - 10.1 Text

@Test func aFieldOverTheBindingLimitIsAnError() throws {
    var manifest = base()
    manifest.setListingText(String(repeating: "a", count: 31), locale: "en-US", field: .subtitle)

    let list = findings(manifest)
    let subtitle = try #require(list.first { $0.id == "text.en-US.subtitle" })
    #expect(subtitle.severity == .error)
    #expect(subtitle.fix == .details)
}

@Test func aGoogleOverrideRaisesTheSubtitleLimitToEighty() {
    var manifest = base()
    manifest.setListingText(String(repeating: "a", count: 31), locale: "en-US", field: .subtitle)
    manifest.setGoogleOverride(true, locale: "en-US", field: .googleShortDescription)

    // The shared value now reaches Apple only, so 31 characters still break
    // the 30 character Apple limit.
    #expect(has(findings(manifest), "text.en-US.subtitle"))

    manifest.setListingText(String(repeating: "a", count: 30), locale: "en-US", field: .subtitle)
    manifest.setListingText(String(repeating: "b", count: 70), locale: "en-US",
                            field: .googleShortDescription)
    #expect(!has(findings(manifest), "text.en-US.subtitle"))
    #expect(!has(findings(manifest), "text.en-US.googleShort"))
}

@Test func keywordsOverOneHundredCharactersIsAnError() {
    var manifest = base()
    manifest.setListingText(String(repeating: "k", count: 101), locale: "en-US", field: .keywords)

    #expect(has(findings(manifest), "text.en-US.keywords"))
}

@Test func aGoogleReleaseNoteOverFiveHundredCharactersIsAnError() {
    var manifest = base()
    manifest.setListingText(String(repeating: "n", count: 501), locale: "en-US", field: .whatsNew)

    let list = findings(manifest)
    #expect(has(list, "text.en-US.googleWhatsNew"))
    // Apple allows 4000, so the Apple side stays quiet.
    #expect(!has(findings(manifest, stores: [.apple]), "text.en-US.googleWhatsNew"))
}

@Test func aMissingDefaultLocaleIsAnError() {
    var manifest = base()
    manifest.listing = Manifest.Listing(defaultLocale: "fr-FR", locales: ["en-US": .init()])

    #expect(has(findings(manifest), "text.noDefault"))
}

// MARK: - 10.3 Build

@Test func aBuildNumberThatIsNotHigherThanTheStoreIsAnError() {
    var manifest = base()
    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.highestBuildNumber = 412
    actual.apple = apple

    var package = AppPackage(kind: .ipa, url: URL(fileURLWithPath: "/tmp/a.ipa"))
    package.identifier = "com.example.app"
    package.buildNumber = "412"
    package.versionName = "1.0.0"
    manifest.release?.build = Manifest.Release.Build(ios: "build/a.ipa")

    let list = findings(manifest, actual, packages: [.ipa: package])
    #expect(has(list, "build.number"))
}

/// The gap: the rule asked `Planner.applePath`, which answers `ios ?? macos`.
/// A manifest that named both hid a broken `.pkg` behind a good `.ipa`, so the
/// plan passed and the run met the missing file instead.
@Test func aMissingMacBuildIsReportedEvenWhenTheiOSBuildIsThere() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("both-builds-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("ipa".utf8).write(to: folder.appendingPathComponent("a.ipa"))

    var manifest = base()
    manifest.release?.build = Manifest.Release.Build(ios: "a.ipa", macos: "gone.pkg")

    let list = Validator.findings(Planner.Input(
        manifest: manifest, actual: ActualState(), stores: [.apple, .google], root: folder))
    #expect(!has(list, "build.missing.ios"))
    let mac = try #require(list.first { $0.id == "build.missing.macos" })
    #expect(mac.severity == .error)
    #expect(mac.location == "Build · Mac")
}

@Test func aBundleIdentifierMismatchIsAnError() {
    let manifest = base()
    var package = AppPackage(kind: .ipa, url: URL(fileURLWithPath: "/tmp/a.ipa"))
    package.identifier = "com.other.app"

    #expect(has(findings(manifest, packages: [.ipa: package]), "build.bundleId"))
}

@Test func aVersionNameMismatchIsOnlyAWarning() throws {
    let manifest = base()
    var package = AppPackage(kind: .aab, url: URL(fileURLWithPath: "/tmp/a.aab"))
    package.identifier = "com.example.app"
    package.versionName = "1.0.0-rc4"

    let list = findings(manifest, packages: [.aab: package])
    let finding = try #require(list.first { $0.id == "build.versionName.google" })
    #expect(finding.severity == .warning)
}

// MARK: - 10.4 Money

@Test func aDurationThatAppleDoesNotOfferIsAnError() {
    var manifest = base()
    manifest.subscriptions = [
        Manifest.SubscriptionGroup(groupId: "main", plans: [
            .init(id: "com.example.p5m", duration: "P5M"),
        ]),
    ]

    #expect(has(findings(manifest), "money.duration.com.example.p5m"))
}

/// The prices Apple sells at, in the base territory.
private func ladder(_ values: [String], territory: String = "USA") -> ActualState {
    appleState {
        $0.pricePoints = values.compactMap { Decimal(string: $0) }
        $0.pricePointTerritory = territory
    }
}

private func priced(_ amount: String, territory: String? = nil) -> Price {
    Price(amount: Decimal(string: amount)!, currency: "USD", territory: territory)
}

@Test func aPriceThatIsNotOnApplesLadderIsCaughtBeforeTheApplyResolvesIt() throws {
    var manifest = base()
    manifest.pricing = Manifest.Pricing(base: priced("4.95"))
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                            price: priced("2.50"))]
    manifest.subscriptions = [
        Manifest.SubscriptionGroup(groupId: "main", plans: [
            .init(id: "com.example.month", duration: "P1M", price: priced("9.50")),
        ]),
    ]

    let list = findings(manifest, ladder(["0", "0.99", "4.99", "9.99"]))
    let base = try #require(list.first { $0.id == "money.offLadder.base" })
    #expect(base.severity == .warning)
    // The message names the price that would actually ship.
    #expect(base.message.contains("4.99"))
    #expect(has(list, "money.offLadder.com.example.pro"))
    #expect(has(list, "money.offLadder.com.example.month"))
}

@Test func aPriceOnTheLadderPassesAndTheFreeRowIsTheAppsAlone() {
    var manifest = base()
    manifest.pricing = Manifest.Pricing(base: priced("0"))
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                            price: priced("4.99"))]

    let list = findings(manifest, ladder(["0", "0.99", "4.99"]))
    // A free app is a price point. A purchase that costs nothing is not, so
    // the shorter ladder catches it while the app's own price passes.
    #expect(!has(list, "money.offLadder.base"))
    #expect(!has(list, "money.offLadder.com.example.pro"))
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                            price: priced("0"))]
    #expect(has(findings(manifest, ladder(["0", "0.99", "4.99"])),
                "money.offLadder.com.example.pro"))
}

@Test func aPriceSetInAnotherTerritoryIsUncheckedAndNotWrong() {
    var manifest = base()
    manifest.pricing = Manifest.Pricing(base: priced("6.90", territory: "BRA"))

    // The ladder in hand is one country's money. Brazil's price judged against
    // the United States ladder would be a warning about nothing.
    #expect(!has(findings(manifest, ladder(["0.99", "4.99"])), "money.offLadder.base"))
    #expect(has(findings(manifest, ladder(["2.90", "4.90"], territory: "BRA")),
                "money.offLadder.base"))
}

@Test func nobodyIsHeldToALadderThatWasNeverRead() {
    var manifest = base()
    manifest.pricing = Manifest.Pricing(base: priced("4.95"))

    #expect(!has(findings(manifest), "money.offLadder.base"))
    #expect(!has(findings(manifest, ladder([])), "money.offLadder.base"))
}

// MARK: - 10.5 The provider

@Test func aProductThatNamesAnUndeclaredEntitlementIsAnError() {
    var manifest = base()
    manifest.monetization = Manifest.Monetization(provider: .revenuecat)
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                            entitlements: ["ghost"])]

    #expect(has(findings(manifest), "provider.entitlement.com.example.pro.ghost"))
}

@Test func anOfferingThatNamesAnUnknownProductIsAnError() {
    var manifest = base()
    manifest.monetization = Manifest.Monetization(provider: .revenuecat)
    manifest.offerings = [Manifest.Offering(key: "default", products: ["com.example.ghost"])]

    #expect(has(findings(manifest), "provider.offering.default.com.example.ghost"))
}

@Test func noOfferingIsOnlyAWarning() throws {
    var manifest = base()
    manifest.monetization = Manifest.Monetization(provider: .revenuecat)

    let finding = try #require(findings(manifest).first { $0.id == "provider.noOffering" })
    #expect(finding.severity == .warning)
}

@Test func aRevenueCatBundleIdentifierMismatchIsAnError() {
    var manifest = base()
    manifest.monetization = Manifest.Monetization(
        provider: .revenuecat,
        revenuecat: .init(projectId: "p",
                          appIds: .init(appStore: "rc_apple", playStore: "rc_play")))
    var actual = ActualState()
    var provider = ActualState.Provider()
    provider.kind = .revenuecat
    provider.appIdentifiers = ["rc_apple": "com.wrong.app", "rc_play": "com.example.app"]
    actual.provider = provider

    #expect(has(findings(manifest, actual), "rc.bundleId"))
    #expect(!has(findings(manifest, actual), "rc.packageName"))
}

@Test func adaptyRejectsADurationThatItHasNoPeriodFor() {
    var manifest = base()
    manifest.monetization = Manifest.Monetization(
        provider: .adapty, adapty: .init(appId: "app"))
    manifest.subscriptions = [
        Manifest.SubscriptionGroup(groupId: "main", plans: [
            .init(id: "com.example.p5m", duration: "P5M", basePlanId: "five"),
        ]),
    ]
    var actual = ActualState()
    var provider = ActualState.Provider()
    provider.kind = .adapty
    provider.loggedInAs = "Logged in as someone"
    actual.provider = provider

    #expect(has(findings(manifest, actual), "adapty.period.com.example.p5m"))
}

@Test func adaptyNeedsABasePlanIdForAnAndroidSubscription() {
    var manifest = base()
    manifest.monetization = Manifest.Monetization(
        provider: .adapty, adapty: .init(appId: "app"))
    manifest.subscriptions = [
        Manifest.SubscriptionGroup(groupId: "main", plans: [
            .init(id: "com.example.monthly", duration: "P1M"),
        ]),
    ]
    var actual = ActualState()
    var provider = ActualState.Provider()
    provider.kind = .adapty
    provider.loggedInAs = "Logged in"
    actual.provider = provider

    #expect(has(findings(manifest, actual), "adapty.basePlan.com.example.monthly"))
    #expect(!has(findings(manifest, actual, stores: [.apple]), "adapty.basePlan.com.example.monthly"))
}

// MARK: - 10.6 State

@Test func metadataWritesNeedTheAppleVersionToBeInPrepareForSubmission() throws {
    let manifest = base()
    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.versionState = "WAITING_FOR_REVIEW"
    actual.apple = apple

    let finding = try #require(findings(manifest, actual).first { $0.id == "state.appleVersion" })
    #expect(finding.severity == .error)
    #expect(finding.fix == .plan)
}

@Test func anOpenReviewSubmissionBlocksTheApply() {
    let manifest = base()
    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.versionState = "PREPARE_FOR_SUBMISSION"
    apple.hasOpenReviewSubmission = true
    actual.apple = apple

    #expect(has(findings(manifest, actual), "state.openSubmission"))
}

// MARK: - The plan verdict

@Test func onlyAnErrorBlocksTheApply() {
    var plan = PlanResult()
    plan.findings = [Finding(id: "w", severity: .warning, message: "", location: "", fix: .media)]
    #expect(!plan.isBlocked)

    plan.findings.append(Finding(id: "e", severity: .error, message: "", location: "",
                                 fix: .details))
    #expect(plan.isBlocked)
}

@Test func theErrorsSortAboveTheWarnings() {
    var manifest = base()
    manifest.setListingText(String(repeating: "a", count: 31), locale: "en-US", field: .subtitle)
    manifest.monetization = Manifest.Monetization(provider: .revenuecat)

    let list = findings(manifest)
    let firstWarning = list.firstIndex { $0.severity == .warning } ?? list.count
    let lastError = list.lastIndex { $0.severity == .error } ?? -1
    #expect(lastError < firstWarning)
}

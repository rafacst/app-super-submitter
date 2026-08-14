import Foundation
import Testing
@testable import SubmitKit

/// The shapes and the values that the two stores refused.
///
/// Every case here stands for one write that the app sent and a store either
/// rejected or, worse, took and misread.

// MARK: - The money a price field reads

/// `Decimal(string:)` keeps the part it managed to read and reports nothing
/// about the rest, so `"4,99"` came out as 4. A price that rounds itself down
/// to the whole currency unit reaches a customer.
@Test func aPriceWrittenWithACommaIsNotFourEuros() throws {
    #expect(Price.amount(from: "4,99") == Decimal(string: "4.99"))
    #expect(Price.amount(from: "0,99") == Decimal(string: "0.99"))
    #expect(Price.amount(from: "4,9") == Decimal(string: "4.9"))
    // The shape that never needed fixing still works.
    #expect(Price.amount(from: "4.99") == Decimal(string: "4.99"))
    #expect(Price.amount(from: " 12 ") == 12)
    #expect(Price.amount(from: "-3.50") == Decimal(string: "-3.50"))
    #expect(Price.amount(from: ".5") == Decimal(string: "0.5"))
}

/// A comma that could be a thousands separator is refused rather than read
/// two ways. `1,299` is one thousand two hundred and ninety-nine in one
/// country and 1.299 in the next, and neither store asks which.
@Test func anAmbiguousSeparatorIsRefusedAndNotGuessedAt() throws {
    #expect(Price.amount(from: "1,299") == nil)
    #expect(Price.amount(from: "1.299,00") == nil)
    #expect(Price.amount(from: "1,299.00") == nil)
    #expect(Price.amount(from: "4,,99") == nil)
    #expect(Price.amount(from: "") == nil)
    #expect(Price.amount(from: "abc") == nil)
    #expect(Price.amount(from: "4.99USD") == nil)
    #expect(Price.amount(from: "4.") == nil)
}

/// The YAML door is the one a hand-written price comes through.
@Test func aCommaPriceInStoreYamlDoesNotDecodeToAWholeUnit() throws {
    let yaml = Data(#"{"amount": "4,99", "currency": "BRL"}"#.utf8)
    let price = try JSONDecoder().decode(Price.self, from: yaml)
    #expect(price.amount == Decimal(string: "4.99"))

    let ambiguous = Data(#"{"amount": "1,299", "currency": "BRL"}"#.utf8)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(Price.self, from: ambiguous)
    }
}

/// The price field on the Monetization tab shares the door.
@Test func thePriceFieldTakesACommaAndRefusesTheAmbiguousOne() throws {
    #expect(PriceDraft.resolve(amount: "4,99", currency: "BRL")
        == .valid(Price(amount: Decimal(string: "4.99")!, currency: "BRL")))
    guard case .invalid = PriceDraft.resolve(amount: "1,299", currency: "BRL") else {
        Issue.record("A thousands separator has to stop at the field.")
        return
    }
}

// MARK: - The Google offer shape

private func offer(_ kind: Manifest.Offer.Kind, price: Price? = nil,
                   regions: [String]? = nil) -> Manifest.Offer {
    Manifest.Offer(id: "launch", kind: kind, duration: "P1M", price: price,
                   periods: 2, regions: regions)
}

private func payload(_ offer: Manifest.Offer) throws -> [String: Any] {
    try Runner.googleOfferPayload(offer, packageName: "com.example.app",
                                  productId: "pro", basePlanId: "monthly")
}

/// The price of a phase lives in the phase's own `regionalConfigs`, and a free
/// trial is `free`. The app used to write `freePriceOverride` on the phase,
/// which is a name no current schema holds, and Google refuses the request.
@Test func aFreeTrialPricesEveryRegionOfItsPhase() throws {
    let body = try payload(offer(.freeTrial, regions: ["US", "BRA"]))
    let phases = try #require(body["phases"] as? [[String: Any]])
    #expect(phases.count == 1)
    #expect(phases[0]["duration"] as? String == "P1M")
    #expect(phases[0]["recurrenceCount"] as? Int == 2)
    #expect(phases[0]["freePriceOverride"] == nil)

    let configs = try #require(phases[0]["regionalConfigs"] as? [[String: Any]])
    #expect(configs.map { $0["regionCode"] as? String } == ["US", "BR"])
    #expect(configs.allSatisfy { $0["free"] != nil })
}

/// An introductory offer names the amount the customer pays, so it is `price`
/// and not `absoluteDiscount`. A discount of 4.99 off a 9.99 plan is 5.00, and
/// that is not the price anybody wrote down.
@Test func anIntroductoryOfferSendsThePriceAndNotADiscount() throws {
    let body = try payload(offer(.introPrice,
                                 price: Price(amount: Decimal(string: "4.99")!,
                                              currency: "USD")))
    let phases = try #require(body["phases"] as? [[String: Any]])
    let configs = try #require(phases[0]["regionalConfigs"] as? [[String: Any]])
    #expect(configs[0]["absoluteDiscount"] == nil)
    let money = try #require(configs[0]["price"] as? [String: Any])
    #expect(money["currencyCode"] as? String == "USD")
    #expect(money["units"] as? String == "4")
    #expect(money["nanos"] as? Int == 990_000_000)
}

/// Google wants one phase config for each region the offer itself lists, so
/// the two lists name the same places.
@Test func thePhaseAndTheOfferNameTheSameRegions() throws {
    let body = try payload(offer(.freeTrial, regions: ["DEU", "FR"]))
    let phases = try #require(body["phases"] as? [[String: Any]])
    let phaseRegions = (phases[0]["regionalConfigs"] as? [[String: Any]] ?? [])
        .compactMap { $0["regionCode"] as? String }
    let offerRegions = (body["regionalConfigs"] as? [[String: Any]] ?? [])
        .compactMap { $0["regionCode"] as? String }
    #expect(phaseRegions == ["DE", "FR"])
    #expect(phaseRegions == offerRegions)
}

/// There is no price override that means "no price". A paid offer without one
/// stops here, because the alternative is a product that sells for nothing.
@Test func aPaidOfferWithNoPriceNeverReachesTheStore() throws {
    #expect(throws: (any Error).self) { try payload(offer(.promotional)) }
}

// MARK: - The territory both stores read

/// The manifest holds one territory field. Apple spells a territory in
/// alpha-3 and Google in alpha-2, so `USA` has to leave as `US`.
@Test func anAppleTerritoryBecomesAGoogleRegion() throws {
    #expect(Runner.googleRegion("USA") == "US")
    #expect(Runner.googleRegion("BRA") == "BR")
    #expect(Runner.googleRegion("DEU") == "DE")
    // An alpha-2 is already what Google wants.
    #expect(Runner.googleRegion("US") == "US")
    #expect(Runner.googleRegion("br") == "BR")
    // A code ICU cannot place goes out as it came in, and the store names it.
    #expect(Runner.googleRegion("XKS") == "XKS")
    #expect(Runner.googleRegions([]) == ["US"])
    #expect(Runner.googleRegions(["", "BRA"]) == ["BR"])
}

// MARK: - The dates the App Store types

/// Apple types a nomination date `date-time`. Every other Apple date in the
/// manifest is a plain day, which is what gets typed here by mistake.
@Test func anAppleDateTimeIsNotAPlainDay() throws {
    #expect(Validator.isDateTime("2026-09-01T00:00:00Z"))
    #expect(Validator.isDateTime("2026-08-14T09:00:00-07:00"))
    #expect(Validator.isDateTime("2026-09-01T00:00:00.500Z"))
    #expect(!Validator.isDateTime("2026-09-01"))
    #expect(!Validator.isDateTime("2026-09-01 00:00:00"))
    #expect(!Validator.isDateTime(""))
}

private func base() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setReleaseVersionName("1.0.0")
    return manifest
}

private func findings(_ manifest: Manifest,
                      stores: Set<Store> = [.apple]) -> [Finding] {
    Validator.findings(Planner.Input(manifest: manifest, actual: ActualState(),
                                     stores: stores, root: nil, packages: [:]))
}

@Test func aNominationDateWithoutATimeIsAnError() throws {
    var manifest = base()
    var marketing = Manifest.Marketing()
    marketing.nomination = Manifest.Marketing.Nomination(
        name: "Launch", type: "APP_LAUNCH", publishStartDate: "2026-09-01")
    manifest.marketing = marketing
    #expect(findings(manifest).contains { $0.id == "marketing.nominationDate.publishStartDate" })

    marketing.nomination?.publishStartDate = "2026-09-01T00:00:00Z"
    manifest.marketing = marketing
    #expect(!findings(manifest).contains { $0.id.hasPrefix("marketing.nominationDate") })
}

/// Apple requires the start on the create and offers no call to add it later.
@Test func aNominationWithNoStartIsAnError() throws {
    var manifest = base()
    var marketing = Manifest.Marketing()
    marketing.nomination = Manifest.Marketing.Nomination(name: "Launch", type: "APP_LAUNCH")
    manifest.marketing = marketing
    #expect(findings(manifest).contains { $0.id == "marketing.nominationStart" })
}

/// `releaseDate` is a plain day. The strict check already existed for offer
/// codes and this field reached the store without it, one call per country.
@Test func aReleaseDateThatIsNotADayIsAnError() throws {
    var manifest = base()
    manifest.pricing = Manifest.Pricing(
        base: Price(amount: 9, currency: "USD"),
        territories: [Manifest.TerritoryAvailability(territory: "USA",
                                                     releaseDate: "2026-09-01T00:00:00Z")])
    #expect(findings(manifest).contains { $0.id == "availability.releaseDate.USA" })

    manifest.pricing?.territories = [
        Manifest.TerritoryAvailability(territory: "USA", releaseDate: "2026-09-01"),
    ]
    #expect(!findings(manifest).contains { $0.id.hasPrefix("availability.releaseDate") })

    manifest.pricing?.territories = [
        Manifest.TerritoryAvailability(territory: "USA", releaseDate: "2026-02-30"),
    ]
    #expect(findings(manifest).contains { $0.id == "availability.releaseDate.USA" })
}

/// The same field type, on a leaderboard. The Gaming tab takes it as free
/// text and nothing checked the shape before the apply.
@Test func aLeaderboardRecurrenceThatStartsOnADayIsAnError() throws {
    var manifest = base()
    var block = Manifest.GameCenter()
    block.leaderboards = [.init(id: "high", name: "High score",
                                recurrence: .init(start: "2026-09-01",
                                                  duration: "P1W", rule: "FREQ=WEEKLY"))]
    manifest.gameCenter = block
    #expect(findings(manifest)
        .contains { $0.id == "gameCenter.leaderboard.recurrenceStart.high" })

    manifest.gameCenter?.leaderboards?[0].recurrence?.start = "2026-09-01T00:00:00Z"
    #expect(!findings(manifest)
        .contains { $0.id.hasSuffix("recurrenceStart.high") })
}

// MARK: - The duration the two stores do not share

/// The manifest keeps one duration list and Apple sells a period Google does
/// not. The plan used to approve `P2M` and the Google apply then failed on it.
@Test func aTwoMonthPlanIsAnErrorOnGoogleAndNotOnApple() throws {
    var manifest = base()
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro",
        plans: [Manifest.SubscriptionGroup.Plan(id: "pro.two", duration: "P2M")])]

    #expect(findings(manifest, stores: [.google])
        .contains { $0.id == "money.googleDuration.pro.two" })
    #expect(!findings(manifest, stores: [.apple])
        .contains { $0.id.hasPrefix("money.googleDuration") })
    #expect(GoogleDurations.name(for: "P1M") != nil)
    #expect(GoogleDurations.name(for: "P2M") == nil)
    #expect(GoogleDurations.name(for: "p1y") != nil)
}

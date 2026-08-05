import Foundation
import Testing
@testable import SubmitKit

/// The redeemable codes of an App Store offer code.
///
/// The bug behind these: `subscriptionOfferCodes` and `inAppPurchaseOfferCodes`
/// are the offer and not the code. The app created the offer, created no code,
/// and reported success, so every offer code it wrote reached nobody.
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

private func offer(_ codes: Manifest.Offer.Codes,
                   kind: Manifest.Offer.Kind = .offerCode) -> Manifest {
    var manifest = base()
    manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable,
        offers: [Manifest.Offer(id: "LAUNCH25", kind: kind, duration: "P1M",
                                codes: codes)])]
    return manifest
}

// MARK: - The validator

/// The writer skips a batch with no expiry, because Apple answers a 400 that
/// reads like a server fault. Without this finding that skip is silent, and a
/// silent skip looks exactly like a successful mint.
@Test func aOneTimeUseBatchWithNoExpiryIsAnError() throws {
    let list = findings(offer(Manifest.Offer.Codes(oneTimeUse: 500)))
    let found = try #require(list.first {
        $0.id == "offer.oneTimeUseExpiry.com.example.pro.LAUNCH25"
    })
    #expect(found.severity == .error)
    #expect(found.fix == .money)
}

@Test func anExpiryOnTheBatchClearsTheFinding() {
    let codes = Manifest.Offer.Codes(oneTimeUse: 500, expiresOn: "2026-12-31")
    #expect(!findings(offer(codes)).contains {
        $0.id.hasPrefix("offer.oneTimeUse") || $0.id.hasPrefix("offer.codes")
    })
}

@Test func aBatchOverTheAppleCapIsAnError() {
    let codes = Manifest.Offer.Codes(oneTimeUse: 25_001, expiresOn: "2026-12-31")
    #expect(findings(offer(codes)).contains {
        $0.id == "offer.oneTimeUseCount.com.example.pro.LAUNCH25"
    })
}

@Test func aBatchOfNoneIsAnError() {
    let codes = Manifest.Offer.Codes(oneTimeUse: 0, expiresOn: "2026-12-31")
    #expect(findings(offer(codes)).contains {
        $0.id == "offer.oneTimeUseEmpty.com.example.pro.LAUNCH25"
    })
}

/// A day that does not exist reaches Apple as a rejection, so it stops here.
@Test func aDateThatIsNotACalendarDayIsAnError() {
    for text in ["31-12-2026", "2026-13-01", "2026-02-30", "next Friday", "2026-12"] {
        let codes = Manifest.Offer.Codes(custom: ["LAUNCH": 10], expiresOn: text)
        #expect(findings(offer(codes)).contains {
            $0.id == "offer.codesExpiry.com.example.pro.LAUNCH25"
        }, "\(text) passed as a date")
    }
    #expect(Validator.isCalendarDay("2026-02-28"))
    #expect(Validator.isCalendarDay("2028-02-29"))
    #expect(!Validator.isCalendarDay("2026-02-29"))
}

/// Apple takes redeemable codes on an offer code and on no other shape.
@Test func codesOnAFreeTrialWarnBecauseNothingWritesThem() {
    let codes = Manifest.Offer.Codes(custom: ["LAUNCH": 10])
    let manifest = offer(codes, kind: .freeTrial)
    let found = findings(manifest).first {
        $0.id == "offer.codesKind.com.example.pro.LAUNCH25"
    }
    #expect(found?.severity == .warning)
}

/// Google mints its promotion codes in the Play Console.
@Test func codesWithTheAppStoreOffWarn() {
    let codes = Manifest.Offer.Codes(custom: ["LAUNCH": 10])
    #expect(findings(offer(codes), stores: [.google]).contains {
        $0.id == "offer.codesStore.com.example.pro.LAUNCH25"
    })
}

// MARK: - The promotional image

@Test func aPromotionalImageThatIsNotOnDiskIsAnError() throws {
    var manifest = base()
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                            promotionalImage: "art/promo.png")]

    let found = try #require(findings(manifest).first {
        $0.id == "offer.promotionalImage.missing.com.example.pro"
    })
    #expect(found.severity == .error)
    #expect(found.message.contains("art/promo.png"))
}

/// The subscription half reads from a plan inside a group, so it takes its own
/// walk and its own test.
@Test func aPlanPromotionalImageIsCheckedToo() {
    var manifest = base()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "main",
        plans: [Manifest.SubscriptionGroup.Plan(id: "com.example.monthly", duration: "P1M",
                                                promotionalImage: "art/plan.png")])]

    #expect(findings(manifest).contains {
        $0.id == "offer.promotionalImage.missing.com.example.monthly"
    })
}

/// A missing key means "do not manage", so it says nothing at all.
@Test func noPromotionalImageKeySaysNothing() {
    var manifest = base()
    manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable)]

    #expect(!findings(manifest).contains { $0.id.hasPrefix("offer.promotionalImage") })
}

// MARK: - The two families

/// The offer code writer serves the subscription and the purchase through one
/// pair of names. A swap here would write a subscription code onto a purchase.
@Test func theTwoOfferCodeFamiliesNameTheirOwnResources() {
    #expect(Runner.OfferCodeFamily.subscription.offerType == "subscriptionOfferCodes")
    #expect(Runner.OfferCodeFamily.subscription.customType
        == "subscriptionOfferCodeCustomCodes")
    #expect(Runner.OfferCodeFamily.subscription.oneTimeType
        == "subscriptionOfferCodeOneTimeUseCodes")
    #expect(Runner.OfferCodeFamily.purchase.offerType == "inAppPurchaseOfferCodes")
    #expect(Runner.OfferCodeFamily.purchase.customType
        == "inAppPurchaseOfferCodeCustomCodes")
    #expect(Runner.OfferCodeFamily.purchase.oneTimeType
        == "inAppPurchaseOfferCodeOneTimeUseCodes")
}

@Test func theTwoImageFamiliesNameTheirOwnParents() {
    #expect(Runner.ProductImageFamily.subscription.imageType == "subscriptionImages")
    #expect(Runner.ProductImageFamily.subscription.parent.name == "subscription")
    #expect(Runner.ProductImageFamily.subscription.listPath(productID: "7")
        == "/v1/subscriptions/7/images")
    #expect(Runner.ProductImageFamily.purchase.imageType == "inAppPurchaseImages")
    // Apple names the relationship after v2 and keeps the plural type.
    #expect(Runner.ProductImageFamily.purchase.parent.name == "inAppPurchaseV2")
    #expect(Runner.ProductImageFamily.purchase.parent.type == "inAppPurchases")
    #expect(Runner.ProductImageFamily.purchase.listPath(productID: "7")
        == "/v2/inAppPurchases/7/images")
}

/// `card` and `details` are the two words the manifest writes.
@Test func theEventAssetTypeMapsBothWays() {
    #expect(Runner.appleEventAssetType("card") == "EVENT_CARD")
    #expect(Runner.appleEventAssetType("Card") == "EVENT_CARD")
    #expect(Runner.appleEventAssetType("details") == "EVENT_DETAILS_PAGE")
}

// MARK: - The search keyword targets

/// A keyword links to a custom product page, and that is where the feature
/// lives. Apple opened those pages to organic search in July 2025: a search for
/// a linked word reaches that page instead of the default product page.
///
/// The version localization carries the same relationship and does none of
/// that, so a panel wired to it would confirm a change that changes nothing.
@Test func aKeywordLinksToACustomProductPageAndNotToAVersion() {
    #expect(AppleKeywordsClient.Parent.customProductPageLocalization.rawValue
        == "appCustomProductPageLocalizations")
    #expect(AppleKeywordsClient.Parent.versionLocalization.rawValue
        == "appStoreVersionLocalizations")
}

/// An invisible page is reachable from a campaign and never from search, so
/// the panel has to say so rather than confirm a keyword that meets nobody.
@Test func aTargetCarriesThePageNameTheLocaleAndTheVisibleSwitch() {
    let target = AppleKeywordsClient.Target(id: "loc-1", pageName: "Students",
                                            locale: "en-US", visible: false)
    #expect(target.id == "loc-1")
    #expect(!target.visible)
}

// MARK: - The round trip

/// A key the encoder drops is worse than a key that was never added: the
/// developer writes it, saves, and it disappears from their own file.
@Test func theNewKeysSurviveASaveAndAReopen() throws {
    var manifest = base()
    manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable,
        offers: [Manifest.Offer(id: "LAUNCH25", kind: .offerCode, active: true,
                                codes: Manifest.Offer.Codes(custom: ["LAUNCH": 25],
                                                            oneTimeUse: 500,
                                                            expiresOn: "2026-12-31"))],
        promotionalImage: "art/pro.png")]
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "main",
        plans: [Manifest.SubscriptionGroup.Plan(id: "com.example.monthly", duration: "P1M",
                                                promotionalImage: "art/monthly.png")])]
    var marketing = Manifest.Marketing()
    marketing.events = [Manifest.Marketing.AppEvent(
        key: "launch",
        locales: ["en-US": Manifest.Marketing.AppEvent.EventLocale(
            name: "Launch", videoClips: ["card": "art/card.mov"])])]
    manifest.marketing = marketing

    let reopened = try ManifestFile.decode(ManifestFile.encode(manifest))

    let purchase = try #require(reopened.purchases?.first)
    #expect(purchase.promotionalImage == "art/pro.png")
    let codes = try #require(purchase.offers?.first?.codes)
    #expect(codes.custom == ["LAUNCH": 25])
    #expect(codes.oneTimeUse == 500)
    #expect(codes.expiresOn == "2026-12-31")
    #expect(purchase.offers?.first?.active == true)
    #expect(reopened.subscriptions?.first?.plans.first?.promotionalImage == "art/monthly.png")
    #expect(reopened.marketing?.events?.first?.locales?["en-US"]?.videoClips
        == ["card": "art/card.mov"])
}

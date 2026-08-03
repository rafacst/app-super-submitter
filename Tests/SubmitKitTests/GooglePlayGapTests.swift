import Foundation
import Testing
@testable import SubmitKit

private func googleManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

private func input(_ manifest: Manifest,
                   actual: ActualState = ActualState()) -> Planner.Input {
    Planner.Input(manifest: manifest, actual: actual, stores: [.google])
}

private func googleState(_ build: (inout ActualState.Google) -> Void) -> ActualState {
    var google = ActualState.Google()
    build(&google)
    var state = ActualState()
    state.google = google
    return state
}

private func json(_ text: String) -> JSON { JSON(data: Data(text.utf8)) }

// MARK: - The track testers

@Test func aClosedTrackWithoutATesterGroupCannotReachAnybody() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(tracks: ["qa-team"])

    let findings = Validator.googleTesterFindings(input(manifest))
    let warning = findings.first { $0.id == "build.closedTrackNoTesters.qa-team" }

    #expect(warning?.severity == .warning)
    #expect(warning?.message.contains("nobody can install") == true)
}

@Test func theFourStandardTracksNeedNoTesterGroup() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        tracks: ["internal", "alpha", "beta", "production"])

    #expect(Validator.googleTesterFindings(input(manifest)).isEmpty)
}

@Test func aTesterEntryThatIsNotAGroupAddressIsAnError() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        tracks: ["qa-team"], testers: ["qa-team": ["not-an-address"]])

    let findings = Validator.googleTesterFindings(input(manifest))

    #expect(findings.contains { $0.id.hasPrefix("build.testerGroup.qa-team") })
    #expect(findings.first { $0.id.hasPrefix("build.testerGroup") }?.severity == .error)
}

@Test func testerGroupsForATrackThatNoApplyWritesAreAnError() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        tracks: ["beta"], testers: ["qa-team": ["qa@example.com"]])

    let findings = Validator.googleTesterFindings(input(manifest))

    #expect(findings.contains { $0.id == "build.testerTrackMissing.qa-team" })
}

@Test func theTesterStepWritesTheGroupsIntoTheEdit() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        tracks: ["qa-team"], testers: ["qa-team": ["qa@example.com"]])

    let steps = Planner.plan(input(manifest)).steps(for: .google)
    let testers = steps.first { $0.id == "google.testers.qa-team" }

    #expect(testers?.operation == .googleTesters(track: "qa-team"))
    #expect(testers?.requests.first?.method == "PUT")
    #expect(testers?.requests.first?.path == "/edits/{editId}/testers/qa-team")
    // The edit wraps it, so it lands between the open and the commit.
    let ids = steps.map(\.id)
    #expect(ids.firstIndex(of: "google.openEdit")! < ids.firstIndex(of: "google.testers.qa-team")!)
    #expect(ids.firstIndex(of: "google.testers.qa-team")! < ids.firstIndex(of: "google.commit")!)
}

@Test func theTesterStepDisappearsWhenGoogleAlreadyHoldsTheSameGroups() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        tracks: ["qa-team"], testers: ["qa-team": ["qa@example.com"]])
    let actual = googleState { google in
        var track = ActualState.Google.Track()
        track.testers = ["qa@example.com"]
        google.tracks["qa-team"] = track
    }

    let steps = Planner.plan(input(manifest, actual: actual)).steps(for: .google)

    #expect(!steps.contains { $0.id == "google.testers.qa-team" })
}

// MARK: - The country availability read

@Test func theTrackStepShowsWhatGoogleSellsTodayBesideTheWantedCountries() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        tracks: ["production"], countries: ["DE", "FR", "GB"])
    let actual = googleState { google in
        var track = ActualState.Google.Track()
        track.countries = ["DE"]
        google.tracks["production"] = track
    }

    let step = Planner.plan(input(manifest, actual: actual)).steps(for: .google)
        .first { $0.id == "google.track.production" }

    #expect(step?.summary.contains("3 countries") == true)
    #expect(step?.summary.contains("(now 1)") == true)
}

@Test func theTrackStepStaysQuietWhenTheCountriesAlreadyMatch() {
    var manifest = googleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        tracks: ["production"], countries: ["DE", "FR"])
    let actual = googleState { google in
        var track = ActualState.Google.Track()
        track.countries = ["FR", "DE"]
        google.tracks["production"] = track
    }

    let step = Planner.plan(input(manifest, actual: actual)).steps(for: .google)
        .first { $0.id == "google.track.production" }

    #expect(step?.summary.contains("now") == false)
}

// MARK: - The offer switches

private func offerManifest(active: Bool?) -> Manifest {
    var manifest = googleManifest()
    manifest.subscriptions = [Manifest.SubscriptionGroup(
        groupId: "pro", groupName: "Pro",
        plans: [Manifest.SubscriptionGroup.Plan(
            id: "pro.monthly", duration: "P1M", basePlanId: "monthly",
            price: Price(amount: 4.99, currency: "USD", territory: "US"),
            offers: [Manifest.Offer(id: "trial", kind: .freeTrial, duration: "P1W",
                                    active: active)])])]
    return manifest
}

@Test func anOfferThatNamesNoStateNeverGetsASwitchStep() {
    let steps = Planner.plan(input(offerManifest(active: nil))).steps(for: .google)
    #expect(!steps.contains { $0.id == "google.subscriptionOfferStates.pro.monthly" })
}

@Test func aDraftOfferThatTheManifestActivatesGetsASwitchStep() {
    let actual = googleState { google in
        google.subscriptionIds = ["pro.monthly"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "pro.monthly"
        product.basePlanId = "monthly"
        product.offerStates = ["trial": "DRAFT"]
        google.catalog["pro.monthly"] = product
    }

    let step = Planner.plan(input(offerManifest(active: true), actual: actual))
        .steps(for: .google).first { $0.id == "google.subscriptionOfferStates.pro.monthly" }

    #expect(step?.summary.contains("activate 1") == true)
    #expect(step?.comparison == .verified)
    #expect(step?.operation == .googleSubscriptionOfferStates(productId: "pro.monthly",
                                                              basePlanId: "monthly"))
}

@Test func anOfferThatIsAlreadyActiveNeedsNoSwitch() {
    let actual = googleState { google in
        google.subscriptionIds = ["pro.monthly"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "pro.monthly"
        product.basePlanId = "monthly"
        product.offerStates = ["trial": "ACTIVE"]
        google.catalog["pro.monthly"] = product
    }

    let steps = Planner.plan(input(offerManifest(active: true), actual: actual))
        .steps(for: .google)

    #expect(!steps.contains { $0.id == "google.subscriptionOfferStates.pro.monthly" })
}

@Test func anOfferSwitchWithoutAReadSaysThatNobodyVerifiedIt() {
    let step = Planner.plan(input(offerManifest(active: true)))
        .steps(for: .google).first { $0.id == "google.subscriptionOfferStates.pro.monthly" }

    #expect(step?.comparison == .unverified)
}

@Test func aOneTimeOfferTakesItsOwnSwitchStep() {
    var manifest = googleManifest()
    manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable,
        offers: [Manifest.Offer(id: "launch", kind: .introPrice,
                                price: Price(amount: 1.99, currency: "USD"),
                                active: false)])]

    let step = Planner.plan(input(manifest)).steps(for: .google)
        .first { $0.id == "google.oneTimeOfferStates.com.example.pro" }

    #expect(step?.operation == .googleOneTimeOfferStates(productId: "com.example.pro"))
    #expect(step?.requests.first?.path.hasSuffix("offers:batchUpdateStates") == true)
}

// MARK: - The per-product catalog diff

private func catalogManifest() -> Manifest {
    var manifest = googleManifest()
    manifest.purchases = [Manifest.Purchase(
        id: "com.example.pro", kind: .nonConsumable, name: "Pro",
        price: Price(amount: 4.99, currency: "USD", territory: "US"))]
    return manifest
}

@Test func theCatalogStepDisappearsWhenGoogleAlreadyHoldsEveryField() {
    let actual = googleState { google in
        google.oneTimeProductIds = ["com.example.pro"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "com.example.pro"
        var listing = ActualState.Google.CatalogProduct.ProductListing()
        listing.title = "Pro"
        product.listings = ["en-US": listing]
        product.prices = ["US": "USD 4.99"]
        google.catalog["com.example.pro"] = product
    }

    let steps = Planner.plan(input(catalogManifest(), actual: actual)).steps(for: .google)

    #expect(!steps.contains { $0.id == "google.products" })
}

@Test func theCatalogStepNamesTheFieldThatDiffers() {
    let actual = googleState { google in
        google.oneTimeProductIds = ["com.example.pro"]
        var product = ActualState.Google.CatalogProduct()
        product.productId = "com.example.pro"
        var listing = ActualState.Google.CatalogProduct.ProductListing()
        listing.title = "Pro"
        product.listings = ["en-US": listing]
        product.prices = ["US": "USD 2.99"]
        google.catalog["com.example.pro"] = product
    }

    let step = Planner.plan(input(catalogManifest(), actual: actual)).steps(for: .google)
        .first { $0.id == "google.products" }

    #expect(step?.summary.contains("com.example.pro") == true)
    #expect(step?.summary.contains("price") == true)
    #expect(step?.summary.contains("title") == false)
    #expect(step?.comparison == .verified)
}

@Test func aProductThatGoogleHoldsAndNobodyCouldReadIsUnverified() {
    let actual = googleState { google in
        google.oneTimeProductIds = ["com.example.pro"]
        // The store lists the product and the detail read failed.
    }

    let step = Planner.plan(input(catalogManifest(), actual: actual)).steps(for: .google)
        .first { $0.id == "google.products" }

    #expect(step?.comparison == .unverified)
    #expect(step?.summary.contains("unread") == true)
}

@Test func aProductThatGoogleDoesNotHoldReadsAsACreate() {
    let actual = googleState { _ in }

    let step = Planner.plan(input(catalogManifest(), actual: actual)).steps(for: .google)
        .first { $0.id == "google.products" }

    #expect(step?.summary.contains("create") == true)
}

@Test func theTwoSidesOfThePriceDiffUseTheSameText() {
    let wanted = Planner.googlePriceText(Price(amount: 4.99, currency: "USD"))
    let live = GoogleCatalogClient.money(
        json(#"{"currencyCode":"USD","units":"4","nanos":990000000}"#))

    #expect(wanted == "USD 4.99")
    #expect(live == wanted)
}

// MARK: - The catalog reader

@Test func aGoogleSubscriptionPayloadParsesIntoTheComparableShape() {
    let product = GoogleCatalogClient.parseSubscription(json("""
    {"productId":"pro.monthly",
     "listings":[{"languageCode":"en-US","title":"Pro","description":"Everything."}],
     "basePlans":[{"basePlanId":"monthly","state":"ACTIVE",
       "autoRenewingBasePlanType":{"billingPeriodDuration":"P1M"},
       "regionalConfigs":[{"regionCode":"US",
         "price":{"currencyCode":"USD","units":"4","nanos":990000000}}]}]}
    """))

    #expect(product?.productId == "pro.monthly")
    #expect(product?.listings["en-US"]?.title == "Pro")
    #expect(product?.listings["en-US"]?.description == "Everything.")
    #expect(product?.basePlanId == "monthly")
    #expect(product?.basePlanDuration == "P1M")
    #expect(product?.prices["US"] == "USD 4.99")
}

@Test func aGoogleOneTimeProductPayloadCarriesThePurchaseOptionPrice() {
    let product = GoogleCatalogClient.parseOneTimeProduct(json("""
    {"productId":"com.example.pro",
     "listings":[{"languageCode":"en-US","title":"Pro"}],
     "purchaseOptions":[{"purchaseOptionId":"com.example.pro","state":"ACTIVE",
       "regionalPricingAndAvailabilityConfigs":[{"regionCode":"US",
         "price":{"currencyCode":"USD","units":"9","nanos":0}}]}]}
    """))

    #expect(product?.prices["US"] == "USD 9")
    #expect(product?.basePlanState == "ACTIVE")
}

@Test func aPayloadWithoutAProductIdIsSkippedInsteadOfCrashing() {
    #expect(GoogleCatalogClient.parseSubscription(json("{}")) == nil)
    #expect(GoogleCatalogClient.parseOneTimeProduct(json("{}")) == nil)
    #expect(GoogleCatalogClient.parseOffer(json("{}")) == nil)
}

@Test func theBatchReadSplitsAtTheGoogleLimit() {
    let ids = (0..<250).map { "product.\($0)" }
    let chunks = GoogleCatalogClient.chunks(ids)

    #expect(chunks.count == 3)
    #expect(chunks.map(\.count) == [100, 100, 50])
    #expect(chunks.flatMap { $0 } == ids)
    #expect(GoogleCatalogClient.chunks([]).isEmpty)
}

// MARK: - The reviews, the sharing, and the recovery

@Test func aReviewPayloadParsesIntoOneRow() {
    let review = GoogleActionsClient.parseReview(json("""
    {"reviewId":"abc","authorName":"A Reader",
     "comments":[{"userComment":{"text":"It crashes.","starRating":2,
                                 "lastModified":{"seconds":1700000000}}},
                 {"developerComment":{"text":"We fixed it."}}]}
    """))

    #expect(review?.id == "abc")
    #expect(review?.text == "It crashes.")
    #expect(review?.starRating == 2)
    #expect(review?.developerReply == "We fixed it.")
    #expect(review?.lastModified == Date(timeIntervalSince1970: 1_700_000_000))
}

@Test func aRecoveryPayloadParsesIntoOneAction() {
    let action = GoogleActionsClient.parseRecovery(json("""
    {"appRecoveryId":"42","status":"RECOVERY_STATUS_DRAFT","createTime":"2026-08-01T00:00:00Z",
     "targeting":{"versionList":{"versionCodes":[41,42]}}}
    """))

    #expect(action?.id == "42")
    #expect(action?.status == "RECOVERY_STATUS_DRAFT")
    #expect(action?.targetedVersionCodes == [41, 42])
}

@Test func anEmptyOrOversizedReviewReplyNeverReachesGoogle() async {
    let client = GoogleActionsClient(api: StoreAPI(credentials: StoreCredentials(),
                                                   record: { _ in }))

    for text in ["", "   ", String(repeating: "x", count: 351)] {
        do {
            _ = try await client.replyToReview(packageName: "com.example.app",
                                               reviewId: "abc", text: text)
            Issue.record("The reply \(text.count) characters long should be refused.")
        } catch ConnectionError.http(let status, _) {
            #expect(status == 400)
        } catch {
            Issue.record("The reply failed with the wrong error: \(error)")
        }
    }
}

@Test func aRecoveryDraftNeedsAtLeastOneVersionCode() async {
    let client = GoogleActionsClient(api: StoreAPI(credentials: StoreCredentials(),
                                                   record: { _ in }))
    do {
        _ = try await client.createRecoveryDraft(packageName: "com.example.app",
                                                 versionCodes: [])
        Issue.record("An empty version list should be refused.")
    } catch ConnectionError.http(let status, _) {
        #expect(status == 400)
    } catch {
        Issue.record("The draft failed with the wrong error: \(error)")
    }
}

@Test func theDeployAndTheReplyCarryTheirWarningInTheSource() throws {
    let actions = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SubmitKit/Clients/GoogleActionsClient.swift"),
        encoding: .utf8)

    // Both calls reach real people, and no call takes either one back.
    #expect(actions.contains("This publishes public text"))
    #expect(actions.contains("This reaches every targeted device"))
}

import Foundation
import Testing
@testable import SubmitKit

/// The Google support lookup: an order id or a purchase token in, the picture
/// of what one customer holds out.
///
/// Every check here reads a payload shaped like Google's own. None of them
/// reaches the network, and none of them can move money: no call in this file
/// has a write twin in the app.

// MARK: - Which endpoint answers the string

@Test func anOrderIdAnnouncesItselfAndAPurchaseTokenDoesNot() {
    #expect(StoreVitalsClient.looksLikeAnOrderId("GPA.3364-8005-8149-11334"))
    // A subscription renewal suffixes the same id.
    #expect(StoreVitalsClient.looksLikeAnOrderId("GPA.3364-8005-8149-11334..2"))
    #expect(StoreVitalsClient.looksLikeAnOrderId("gpa.3364-8005-8149-11334"))
    #expect(!StoreVitalsClient.looksLikeAnOrderId(
        "hakfcimlcdfnpjbldjbelmoe.AO-J1OyzD9k4Xj7Rr2wQ"))
}

@Test func aPastedTicketSplitsOnCommasAndNewlines() {
    let terms = StoreVitalsClient.terms("GPA.1111-2222, GPA.3333-4444\n GPA.5555-6666 ")

    #expect(terms == ["GPA.1111-2222", "GPA.3333-4444", "GPA.5555-6666"])
}

// MARK: - The order

@Test func anOrderReadsItsStateItsMoneyAndItsToken() {
    let blocks = StoreVitalsClient.orderBlocks(JSON([
        "orderId": "GPA.3364-8005-8149-11334",
        "purchaseToken": "opaque-token",
        "state": "PARTIALLY_REFUNDED",
        "createTime": "2026-01-04T09:30:00Z",
        "total": ["currencyCode": "USD", "units": "9", "nanos": 990_000_000],
        "tax": ["currencyCode": "USD", "units": "0", "nanos": 800_000_000],
        "developerRevenue": ["currencyCode": "USD", "units": "6", "nanos": 990_000_000],
    ]))

    let order = try! #require(blocks.first)
    #expect(order.title == "Order GPA.3364-8005-8149-11334")
    #expect(order.rows.first { $0.name == "State" }?.value == "Partially refunded")
    #expect(order.rows.first { $0.name == "Total" }?.value == "USD 9.99")
    #expect(order.rows.first { $0.name == "Total" }?.detail == "USD 0.8 tax")
    #expect(order.rows.first { $0.name == "Your share" }?.value == "USD 6.99")
    #expect(order.rows.first { $0.name == "Purchase token" }?.value == "opaque-token")
}

@Test func eachLineItemBecomesItsOwnBlockAndNamesWhatItIs() {
    let blocks = StoreVitalsClient.orderBlocks(JSON([
        "orderId": "GPA.1111",
        "lineItems": [
            ["productId": "com.example.pro",
             "productTitle": "Pro, yearly",
             "total": ["currencyCode": "EUR", "units": "49", "nanos": 0],
             "subscriptionDetails": ["basePlanId": "yearly", "offerId": "intro-50"]],
            ["productId": "com.example.coins",
             "oneTimePurchaseDetails": ["quantity": 1]],
        ],
    ]))

    #expect(blocks.count == 3)
    let subscription = blocks[1]
    #expect(subscription.title == "Line item com.example.pro")
    #expect(subscription.rows.first { $0.name == "Kind" }?.value == "Subscription")
    #expect(subscription.rows.first { $0.name == "Base plan" }?.value == "yearly")
    #expect(subscription.rows.first { $0.name == "Base plan" }?.detail == "intro-50")
    #expect(subscription.rows.first { $0.name == "Paid" }?.value == "EUR 49")
    #expect(blocks[2].rows.first { $0.name == "Kind" }?.value == "One-time purchase")
}

// MARK: - The subscription

@Test func aSubscriptionReadsItsStateItsPlanAndWhenItRenews() {
    let block = StoreVitalsClient.subscriptionBlock(JSON([
        "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
        "startTime": "2026-01-04T09:30:00Z",
        "regionCode": "BR",
        "latestOrderId": "GPA.9999",
        "acknowledgementState": "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        "lineItems": [[
            "productId": "com.example.pro",
            "expiryTime": "2027-01-04T09:30:00Z",
            "offerDetails": ["basePlanId": "yearly", "offerId": "intro-50"],
            "autoRenewingPlan": [
                "autoRenewEnabled": true,
                "recurringPrice": ["currencyCode": "BRL", "units": "99", "nanos": 900_000_000],
            ],
        ]],
    ]))

    #expect(block.rows.first { $0.name == "State" }?.value == "Active")
    #expect(block.rows.first { $0.name == "Product" }?.value == "com.example.pro")
    #expect(block.rows.first { $0.name == "Product" }?.detail == "yearly")
    #expect(block.rows.first { $0.name == "Offer" }?.value == "intro-50")
    #expect(block.rows.contains { $0.name == "Renews" })
    #expect(block.rows.first { $0.name == "Renewal price" }?.value == "BRL 99.9")
    #expect(block.rows.first { $0.name == "Acknowledged" }?.value == "Yes")
    #expect(block.rows.first { $0.name == "Bought in" }?.value == "BR")
}

@Test func aSubscriptionWithAutoRenewOffEndsRatherThanRenews() {
    let block = StoreVitalsClient.subscriptionBlock(JSON([
        "subscriptionState": "SUBSCRIPTION_STATE_CANCELED",
        "lineItems": [[
            "productId": "com.example.pro",
            "expiryTime": "2027-01-04T09:30:00Z",
            "autoRenewingPlan": ["autoRenewEnabled": false],
        ]],
    ]))

    #expect(block.rows.first { $0.name == "State" }?.value == "Canceled")
    #expect(block.rows.contains { $0.name == "Ends" })
    #expect(!block.rows.contains { $0.name == "Renews" })
    #expect(block.rows.first { $0.name == "Ends" }?.detail == "Auto-renew is off.")
}

@Test func anUnacknowledgedPurchaseSaysGoogleWillRefundIt() {
    let block = StoreVitalsClient.subscriptionBlock(JSON([
        "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
        "acknowledgementState": "ACKNOWLEDGEMENT_STATE_PENDING",
    ]))
    let row = block.rows.first { $0.name == "Acknowledged" }

    #expect(row?.value == "Not yet")
    #expect(row?.detail?.contains("three days") == true)
}

@Test func aTestPurchaseSaysSoBeforeAnybodyChasesTheMoney() {
    let block = StoreVitalsClient.subscriptionBlock(JSON([
        "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
        "testPurchase": [:],
    ]))

    #expect(block.rows.first { $0.name == "Test purchase" }?.value == "Yes")
}

// MARK: - Who ended it

@Test func eachCancellationCauseReadsAsASentence() {
    #expect(StoreVitalsClient.cancelReason(
        JSON(["developerInitiatedCancellation": [:]])) == "you")
    #expect(StoreVitalsClient.cancelReason(
        JSON(["systemInitiatedCancellation": [:]])) == "Google, after the payment failed")
    #expect(StoreVitalsClient.cancelReason(
        JSON(["replacementCancellation": [:]])) == "a plan change, which replaced it")
    #expect(StoreVitalsClient.cancelReason(JSON(nil)) == nil)
}

@Test func theCancelSurveyAnswerReachesTheReader() {
    let reason = StoreVitalsClient.cancelReason(JSON([
        "userInitiatedCancellation": [
            "cancelSurveyResult": ["reason": "CANCEL_SURVEY_REASON_TOO_EXPENSIVE"],
        ],
    ]))

    #expect(reason?.contains("the customer") == true)
    #expect(reason?.contains("expensive") == true)
}

// MARK: - The one-time purchase

@Test func aOneTimePurchaseReadsItsStateAndWhetherTheAppAcknowledgedIt() {
    let block = StoreVitalsClient.productPurchaseBlock(JSON([
        "purchaseState": 0,
        "consumptionState": 0,
        "acknowledgementState": 1,
        "orderId": "GPA.4444",
        "regionCode": "DE",
        "quantity": 3,
        "refundableQuantity": 2,
    ]), productId: "com.example.coins")

    #expect(block.title == "One-time purchase com.example.coins")
    #expect(block.rows.first { $0.name == "State" }?.value == "Bought")
    #expect(block.rows.first { $0.name == "Consumed" }?.value == "Not yet")
    #expect(block.rows.first { $0.name == "Acknowledged" }?.value == "Yes")
    #expect(block.rows.first { $0.name == "Quantity" }?.value == "3")
    #expect(block.rows.first { $0.name == "Quantity" }?.detail == "2 still refundable")
    #expect(block.rows.first { $0.name == "Order" }?.value == "GPA.4444")
}

@Test func aPromoPurchaseSaysItPaidNothing() {
    let block = StoreVitalsClient.productPurchaseBlock(
        JSON(["purchaseState": 0, "purchaseType": 1]), productId: "com.example.coins")

    #expect(block.rows.first { $0.name == "Kind" }?.value == "Promo code")
    #expect(block.rows.first { $0.name == "Kind" }?.detail == "It paid nothing.")
}

// MARK: - The device tier configuration, create or skip

/// The apply used to create a configuration on every run. It now reads the
/// newest one back and compares, so these checks are what stands between a
/// developer and a Play Console full of duplicates.

private func fingerprint(_ json: String) -> String {
    StoreDiagnostics.deviceTierFingerprint(
        try! JSONSerialization.jsonObject(with: Data(json.utf8)))
}

@Test func theIdGoogleAssignedIsNotADifference() {
    let mine = fingerprint(#"{"deviceGroups":[{"name":"high"}]}"#)
    let live = fingerprint(#"{"deviceTierConfigId":"7","deviceGroups":[{"name":"high"}]}"#)

    #expect(mine == live)
}

@Test func theOrderGoogleReturnsTheGroupsInIsNotADifference() {
    let mine = fingerprint(#"{"deviceGroups":[{"name":"high"},{"name":"low"}]}"#)
    let live = fingerprint(#"{"deviceGroups":[{"name":"low"},{"name":"high"}]}"#)

    #expect(mine == live)
}

/// Google encodes every 64-bit number as a JSON string. A developer writes a
/// number. Reading those as different would create a configuration on every
/// single apply, which is the wart this whole comparison exists to remove.
@Test func aByteCountWrittenAsANumberMatchesTheStringGoogleSendsBack() {
    let mine = fingerprint(#"{"deviceGroups":[{"deviceRam":{"minBytes":2000000000}}]}"#)
    let live = fingerprint(#"{"deviceGroups":[{"deviceRam":{"minBytes":"2000000000"}}]}"#)

    #expect(mine == live)
}

@Test func aTrueIsNotTheNumberOne() {
    #expect(fingerprint(#"{"a":true}"#) != fingerprint(#"{"a":1}"#))
    #expect(fingerprint(#"{"a":true}"#) == fingerprint(#"{"a":true}"#))
    #expect(fingerprint(#"{"a":false}"#) != fingerprint(#"{"a":0}"#))
}

@Test func arealDifferenceStillReadsAsADifference() {
    let mine = fingerprint("""
        {"deviceGroups":[{"name":"high","deviceSelectors":[
            {"deviceRam":{"minBytes":"4000000000"}}]}]}
        """)
    let live = fingerprint("""
        {"deviceTierConfigId":"7","deviceGroups":[{"name":"high","deviceSelectors":[
            {"deviceRam":{"minBytes":"2000000000"}}]}]}
        """)

    #expect(mine != live)
}

@Test func anExtraGroupIsADifference() {
    let mine = fingerprint(#"{"deviceGroups":[{"name":"high"},{"name":"low"}]}"#)
    let live = fingerprint(#"{"deviceGroups":[{"name":"high"}]}"#)

    #expect(mine != live)
}

@Test func aMissingKeyIsNotTheSameAsAnEmptyOne() {
    #expect(fingerprint(#"{"deviceGroups":[]}"#) != fingerprint("{}"))
}

// MARK: - The listing write, and the three states behind it

/// The apply used to send a partial body over a PUT, which replaces. A promo
/// video the developer set in the Play Console, and never named in the
/// manifest, was deleted by an apply that only meant to write a description.
/// These checks are what keeps the three manifest states apart.

@Test func anUnmanagedFieldSendsNothingAtAll() {
    #expect(Runner.listingField(.unmanaged) == nil)
    #expect(Runner.listingField(nil) == nil)
}

@Test func aNullInTheManifestSendsTheEmptyStringThatClearsTheField() {
    #expect(Runner.listingField(.clear) == "")
}

@Test func aValueSendsItself() {
    #expect(Runner.listingField(.value("Watch it on YouTube")) == "Watch it on YouTube")
    // An empty value is the old shape of "not set", and it still hands over
    // to the fallback rather than clearing anything.
    #expect(Runner.listingField(.value("")) == nil)
}

@Test func aClearedFieldGetsItsOwnPlanRow() {
    var changes: [String] = []
    Planner.appendClear(&changes, .googleVideo, .clear, fallback: nil,
                        "https://youtu.be/live")

    #expect(changes == ["YouTube video (cleared)"])
}

@Test func clearingAFieldGoogleDoesNotHoldIsNoChange() {
    var changes: [String] = []
    Planner.appendClear(&changes, .googleVideo, .clear, fallback: nil, nil)
    Planner.appendClear(&changes, .googleVideo, .clear, fallback: nil, "")

    #expect(changes.isEmpty)
}

@Test func anUnmanagedFieldNeverGetsAClearRow() {
    var changes: [String] = []
    Planner.appendClear(&changes, .googleVideo, .unmanaged, fallback: nil,
                        "https://youtu.be/live")
    Planner.appendClear(&changes, .googleVideo, .value("keep me"), fallback: nil,
                        "https://youtu.be/live")

    #expect(changes.isEmpty)
}

/// The short description reads the Apple subtitle when the manifest names no
/// Google override, so the subtitle is what clears it.
@Test func theSubtitleClearsTheShortDescriptionItStandsInFor() {
    var changes: [String] = []
    Planner.appendClear(&changes, .googleShortDescription, .unmanaged,
                        fallback: .clear, "Shop faster")

    #expect(changes == ["Short description (cleared)"])
}

@Test func aGoogleOverrideBeatsTheSubtitleForClearing() {
    var changes: [String] = []
    Planner.appendClear(&changes, .googleShortDescription, .value("Shop faster"),
                        fallback: .clear, "Shop faster")

    #expect(changes.isEmpty)
}

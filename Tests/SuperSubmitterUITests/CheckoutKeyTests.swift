import Foundation
import Testing
@testable import SuperSubmitter

/// The promotion code has to reach Stripe.
///
/// The bug this guards cost the customer money. The client sends one
/// idempotency key per checkout, and the server answers a repeated key with
/// the session it already made. The key held the plan and not the code, so
/// this happened:
///
/// 1. Press Subscribe with no code. A session opens at the full price.
/// 2. Close the browser without paying.
/// 3. Type a code, press Apply, watch the discount appear, press Subscribe.
/// 4. The same key comes back, so the server returns the session from step 1.
///
/// The discount was on the screen and never on the invoice.
@MainActor
struct CheckoutKeyTests {
    private func state() -> AppState {
        let fresh = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        fresh.selectedPlan = "annual"
        return fresh
    }

    @Test func aCodeChangesTheKey() {
        let app = state()
        let withoutCode = app.checkoutIdempotencyKey()

        app.promotionCode = "LAUNCH100"

        #expect(app.checkoutIdempotencyKey() != withoutCode)
    }

    /// The key still does its own job. Pressing Subscribe twice on one plan
    /// and one code must reach the session that is already open, not a second.
    @Test func theSameCodeKeepsTheSameKey() {
        let app = state()
        app.promotionCode = "LAUNCH100"
        let first = app.checkoutIdempotencyKey()

        #expect(app.checkoutIdempotencyKey() == first)
    }

    /// Stripe matches a code either way, so two keys would mint two sessions
    /// for one discount. The spacing is what a paste brings in.
    @Test func theCaseAndTheSpacingDoNotSplitTheKey() {
        let app = state()
        app.promotionCode = "LAUNCH100"
        let first = app.checkoutIdempotencyKey()

        app.promotionCode = "  launch100 "

        #expect(app.checkoutIdempotencyKey() == first)
    }

    @Test func aPlanChangeStillChangesTheKey() {
        let app = state()
        app.promotionCode = "LAUNCH100"
        let annual = app.checkoutIdempotencyKey()

        app.selectPlan("lifetime")

        #expect(app.checkoutIdempotencyKey() != annual)
    }

    /// A field of spaces is an empty field. It used to pass the `isEmpty` test
    /// and send an empty code to the server.
    @Test func aFieldOfSpacesSendsNoCode() {
        let app = state()
        app.promotionCode = "   "

        #expect(app.trimmedPromotionCode == nil)
    }
}

import Foundation
import SubmitKit
import SwiftUI
import Testing
@testable import SuperSubmitter

/// The Account tab has to stand in one window with no scroll bar.
///
/// It is the one screen in the app that argues rather than edits, and an offer
/// the reader has to scroll to finish is an offer with a fold in it. Every
/// other tab is a form and scrolls by right.
///
/// Measured and not photographed. `ImageRenderer` lays the real view out at the
/// real width and reports the height it asked for, so this fails the moment a
/// line of copy or a row of padding pushes the screen past the window, which a
/// screenshot only shows to whoever remembers to look at it.
@MainActor
@Suite struct AccountFitsTests {

    /// The content column at the window the app opens at: 1280 wide, less the
    /// sidebar and its divider, less the 20 point pad the shell puts round
    /// every tab.
    static let width: CGFloat = 1280 - 250 - 40

    /// What is left under the title bar and the question band, less the pad at
    /// the foot.
    ///
    /// The window is 820 high where the display allows it and shorter where it
    /// does not: `ScreenshotMode.placeWindow` and the user's own resize both
    /// land at `min(820, screen - 80)`. The budget is taken at 790, which is
    /// what a 1080 point display leaves, so the screen fits the smaller of the
    /// two and not only the one this Mac happens to have.
    static let height: CGFloat = 790 - 118 - 20

    /// Never touches the Keychain. The panel is measured and never signed in.
    private struct NoStore: SupabaseSessionStoring {
        func load() throws -> SupabaseSession? { nil }
        func save(_ session: SupabaseSession) throws {}
        func clear() throws {}
    }

    private func state(plans: Int = 3) -> AppState {
        let app = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                           storeAccount: "test-\(UUID().uuidString)")
        // A build that can reach an account service, which is every shipped
        // one. Without this the identity card carries the four-line warning
        // about a missing Supabase address, and the budget below would then be
        // set by a state no customer ever opens.
        app.authController = SupabaseAuth(
            configuration: .init(baseURL: URL(string: "https://project.supabase.co")!,
                                 publishableKey: "public-key"),
            store: NoStore())
        app.billingPlans = BillingPlans(currency: "USD", plans: [
            BillingPlan(id: "monthly", amount: 499, interval: "month", available: true),
            BillingPlan(id: "annual", amount: 4990, interval: "year", available: true),
            BillingPlan(id: "lifetime", amount: 44990, interval: nil, available: true),
        ].prefix(plans).map { $0 })
        app.selectedPlan = "annual"
        return app
    }

    private func measure(_ app: AppState) -> CGSize {
        let renderer = ImageRenderer(
            content: AccountTab()
                .environment(app)
                .frame(width: Self.width)
                .fixedSize(horizontal: false, vertical: true))
        return renderer.nsImage?.size ?? .zero
    }

    /// The state the screen is written for: nobody signed in, three plans on
    /// sale, everything the offer has to say on one page.
    @Test func theWholeOfferStandsInOneWindow() {
        let size = measure(state())

        #expect(size.height > 0, "the tab rendered nothing, so this measured nothing")
        #expect(size.height <= Self.height,
                "the account tab is \(Int(size.height)) points tall and the window leaves \(Int(Self.height))")
    }

    /// A price list of one plan still has to fit, and so does the free card
    /// beside it. Fewer cards is a wider card, not a taller page.
    @Test func aShorterPriceListStillFits() {
        let size = measure(state(plans: 1))

        #expect(size.height > 0)
        #expect(size.height <= Self.height,
                "one plan makes the tab \(Int(size.height)) points tall")
    }

    /// A paying account sees no offer at all, so it can never be the tall case.
    @Test func aPaidAccountIsShorterThanTheOffer() {
        let free = measure(state())
        let app = state()
        app.entitlement = Entitlement(
            subject: "u", status: .active, plan: .annual, capabilities: [.storeWrite],
            issuedAt: Date(timeIntervalSince1970: 1_800_000_000),
            refreshAfter: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_802_592_000))

        #expect(measure(app).height <= free.height)
    }
}

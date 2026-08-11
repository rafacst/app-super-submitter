import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The Account tab as an offer: a headline price, a card per plan, and the
/// saving on the yearly one.
///
/// Every number on that screen comes from the licensing service. The saving and
/// the best-value badge are the two the app works out for itself, and both of
/// them are arithmetic over amounts the server sent, so both are asserted here
/// rather than photographed. A hard coded "Save 27%" would go on lying the day
/// the price list changes.
@MainActor
@Suite struct AccountOfferTests {

    private func plans(monthly: Int? = 900, annual: Int? = 7900,
                       lifetime: Int? = 19900,
                       available: Bool = true) -> BillingPlans {
        var list: [BillingPlan] = []
        if let monthly {
            list.append(BillingPlan(id: "monthly", amount: monthly,
                                    interval: "month", available: available))
        }
        if let annual {
            list.append(BillingPlan(id: "annual", amount: annual,
                                    interval: "year", available: available))
        }
        if let lifetime {
            list.append(BillingPlan(id: "lifetime", amount: lifetime,
                                    interval: nil, available: available))
        }
        return BillingPlans(currency: "USD", plans: list)
    }

    // MARK: - The saving

    /// Twelve months of the monthly plan against the price of the yearly one.
    @Test func theSavingIsTheYearlyPlanAgainstTwelveMonthlyOnes() throws {
        let list = plans().plans
        let annual = try #require(list.first { $0.id == "annual" })

        #expect(AccountTab.saving(for: annual, in: list) == 27)
    }

    /// Only the yearly plan has anything to compare against. A monthly plan
    /// measured against itself saves nothing, and a one-time purchase is not a
    /// year of anything.
    @Test func onlyTheYearlyPlanCarriesASaving() throws {
        let list = plans().plans

        for id in ["monthly", "lifetime"] {
            let plan = try #require(list.first { $0.id == id })
            #expect(AccountTab.saving(for: plan, in: list) == nil,
                    "\(id) claimed a saving")
        }
    }

    /// No monthly price means nothing to take the saving off, so the card says
    /// nothing rather than inventing a baseline.
    @Test func withNoMonthlyPlanThereIsNoSavingToClaim() throws {
        let list = plans(monthly: nil).plans
        let annual = try #require(list.first { $0.id == "annual" })

        #expect(AccountTab.saving(for: annual, in: list) == nil)
    }

    /// A yearly plan that costs more than twelve months is not a saving, and
    /// the badge may never print a negative one.
    @Test func aYearlyPlanThatCostsMoreClaimsNothing() throws {
        let list = plans(monthly: 900, annual: 12000).plans
        let annual = try #require(list.first { $0.id == "annual" })

        #expect(AccountTab.saving(for: annual, in: list) == nil)
    }

    // MARK: - The badge

    @Test func theBestValueBadgeGoesOnThePlanThatSavesTheMost() {
        #expect(AccountTab.bestValue(in: plans().plans) == "annual")
    }

    /// A price list with nothing to compare wears no badge at all. The badge is
    /// a claim, and a claim with no arithmetic behind it is decoration.
    @Test func aPriceListWithNoSavingWearsNoBadge() {
        #expect(AccountTab.bestValue(in: plans(annual: nil).plans) == nil)
        #expect(AccountTab.bestValue(in: plans(monthly: nil).plans) == nil)
    }

    // MARK: - The headline price

    /// The badge over the headline reads the cheapest plan that is on sale,
    /// split into the amount and the unit under it.
    @Test func theHeadlinePriceIsTheCheapestPlanOnSale() throws {
        let price = try #require(AccountTab.headlinePrice(plans()))

        #expect(price.amount.contains("9"))
        #expect(price.unit == "/ month")
    }

    /// A plan the server has not opened yet is not a price anybody can pay, so
    /// it may not be the number in the headline.
    @Test func aPlanThatIsNotOnSaleIsNotTheHeadlinePrice() {
        #expect(AccountTab.headlinePrice(plans(available: false)) == nil)
    }

    @Test func theUnitFollowsTheInterval() {
        #expect(AccountTab.unit(BillingPlan(id: "monthly", amount: 900,
                                            interval: "month", available: true)) == "per month")
        #expect(AccountTab.unit(BillingPlan(id: "annual", amount: 7900,
                                            interval: "year", available: true)) == "per year")
        #expect(AccountTab.unit(BillingPlan(id: "lifetime", amount: 19900,
                                            interval: nil, available: true)) == "once")
    }

    // MARK: - The way to ask

    /// The indie card tells the reader to ask for a code, so the card is the
    /// asking. A card that names an action and carries nothing to press is a
    /// dead end.
    @Test func theIndieCardOpensAMailToSupport() {
        #expect(AccountTab.askForACodeURL.scheme == "mailto")
        #expect(AccountTab.askForACodeURL.path == AboutPanel.supportEmail)
    }

    // MARK: - The copy

    /// The offer copy, as the design sets it. It is asserted as literal source
    /// text because these strings are the screen: a headline that drifts is the
    /// one regression a layout test cannot see.
    @Test func theTabCarriesTheOfferCopy() throws {
        let source = try tabSource()

        for line in ["Ship both stores from one workflow.",
                     "Prepare App Store and Google Play drafts in one place.",
                     "Review every change, then release on your terms.",
                     "Describe once", "One source of truth for both stores.",
                     "Preview every change", "See exactly what will be sent.",
                     "Drafts first", "Nothing goes live without you.",
                     "Developer-first", "Built for real shipping workflows.",
                     "Sign in to sync your plan across Macs and unlock applies, uploads, and releases.",
                     "Keys stay in Keychain", "Drafts never go live on their own",
                     "Indie developer?", "Ask for a code.",
                     "Discount code", "Enter code", "Apply",
                     "Continue to secure checkout",
                     "Checkout by Stripe. Card details are never seen by us.",
                     "Secure checkout by Stripe",
                     "Your card details are never seen by us.",
                     "We never store or access your keys.",
                     "You review and release on your terms."] {
            #expect(source.contains(line), "the tab lost: \(line)")
        }
    }

    /// No price, no plan name, and no percentage is ever written into the
    /// source. Every one of them arrives from the licensing service.
    @Test func noAmountIsWrittenIntoTheScreen() throws {
        let source = try tabSource()

        for invented in ["US$ 9", "$9", "79,00", "199,00", "Save 27"] {
            #expect(!source.contains(invented),
                    "an amount was hard coded into the tab: \(invented)")
        }
    }

    private func tabSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appending(path: "Sources/SuperSubmitter/Tabs/AccountTab.swift"),
            encoding: .utf8)
    }
}

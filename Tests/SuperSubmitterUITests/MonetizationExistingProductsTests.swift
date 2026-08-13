import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// What the Monetization tab says about products the store already holds.
///
/// The report: an already published app opened this tab and every approved
/// in-app purchase said "Will add", subscription groups showed no plan rows,
/// and no current price appeared anywhere. The tab reads
/// `actualState.apple.catalog`, and nothing but the Summary read ever filled
/// it, so opening Monetization first meant reading an empty map and calling
/// every product missing.
@MainActor
@Suite struct MonetizationExistingProductsTests {

    /// An Apple side that has answered, holding the named products.
    private func appleCatalog(
        _ products: [(id: String, state: String, price: String?, duration: String?)],
        read: Bool = true, territory: String = "USA") -> ActualState {
        var state = ActualState()
        var apple = ActualState.Apple()
        apple.catalogRead = read
        for entry in products {
            var product = ActualState.Apple.CatalogProduct()
            product.productId = entry.id
            product.state = entry.state
            product.duration = entry.duration
            if let price = entry.price { product.prices = [territory: price] }
            apple.catalog[entry.id] = product
            if entry.duration == nil { apple.purchaseIds.insert(entry.id) }
            else { apple.subscriptionIds.insert(entry.id) }
        }
        state.apple = apple
        return state
    }

    // MARK: - An existing product is never one the apply will create

    /// The headline of the report.
    @Test func anApprovedPurchaseIsNotLabelledWillAdd() {
        let actual = appleCatalog([("com.example.pro", "APPROVED", "USD 4.99", nil)])

        let status = MoneyTab.productStatus("com.example.pro", stores: [.apple], actual: actual)

        #expect(status.text != "Will add")
        #expect(status.text == "Approved")
    }

    /// And a product in review says which review it is in, rather than hiding
    /// behind a word about the apply.
    @Test func aPurchaseInReviewSaysSo() {
        let actual = appleCatalog([("com.example.pro", "WAITING_FOR_REVIEW", "USD 4.99", nil)])

        #expect(MoneyTab.productStatus("com.example.pro", stores: [.apple],
                                       actual: actual).text == "In review")
    }

    /// A product the store holds is never "Will add", whatever its state.
    @Test func aProductTheStoreHoldsIsNeverAClaimToCreateIt() {
        for state in ["APPROVED", "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_TO_SUBMIT",
                      "DEVELOPER_ACTION_NEEDED", "REMOVED_FROM_SALE"] {
            let actual = appleCatalog([("com.example.pro", state, "USD 4.99", nil)])
            for stores in [Set<Store>([.apple]), Set<Store>([.apple, .google])] {
                #expect(MoneyTab.productStatus("com.example.pro", stores: stores,
                                               actual: actual).text != "Will add",
                        "state \(state) with \(stores.count) store(s)")
            }
        }
    }

    // MARK: - Unread is not absent

    /// The root cause. An unread catalog was treated exactly like a read one
    /// that proved the product absent.
    @Test func anUnreadCatalogIsNotAnEmptyCatalog() {
        var unread = ActualState()
        unread.apple = ActualState.Apple()   // present, but nobody asked
        #expect(MoneyTab.productStatus("com.example.pro", stores: [.apple],
                                       actual: unread).text == "Not read yet")

        // Nothing read at all is the same answer.
        #expect(MoneyTab.productStatus("com.example.pro", stores: [.apple],
                                       actual: ActualState()).text == "Not read yet")
    }

    /// A read that answered and holds nothing is the one state that may claim
    /// the apply will create the product.
    @Test func areadThatProvesAbsenceStillSaysWillAdd() {
        let read = appleCatalog([])

        #expect(MoneyTab.productStatus("com.example.pro", stores: [.apple],
                                       actual: read).text == "Will add")
    }

    /// A failed read leaves the flag false, so the tab says it could not
    /// verify rather than inventing a creation.
    @Test func aFailedReadNeverBecomesAClaimAboutTheStore() {
        let failed = appleCatalog([("com.example.pro", "APPROVED", nil, nil)], read: false)

        // Apple answered for this product before the failure, so it is held.
        #expect(MoneyTab.productStatus("com.example.pro", stores: [.apple],
                                       actual: failed).text != "Will add")
        // And one nobody heard about is not absent.
        #expect(MoneyTab.productStatus("com.example.other", stores: [.apple],
                                       actual: failed).text == "Not read yet")
    }

    /// One store read and one not is not a claim that the product is missing
    /// from the store nobody asked.
    @Test func oneStoreReadAndOneNotIsNotAOneStoreProduct() {
        let actual = appleCatalog([("com.example.pro", "APPROVED", "USD 4.99", nil)])

        #expect(MoneyTab.productStatus("com.example.pro", stores: [.apple, .google],
                                       actual: actual).text == "Could not verify")
    }

    // MARK: - The price, for one store as well as two

    /// An Apple-only app could not see its own current price anywhere on this
    /// tab: the store columns were drawn only when two stores were selected.
    @Test func anAppleOnlyAppStillSeesItsApplePrice() {
        let actual = appleCatalog([("com.example.pro", "APPROVED", "USD 4.99", nil)])

        #expect(MoneyTab.storeSummary("com.example.pro", store: .apple, actual: actual,
                                      territory: "USA") == "USD 4.99")

        // And the column itself is no longer behind a two-store condition.
        let tab = try! String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/SuperSubmitter/Tabs/MoneyTab.swift"),
            encoding: .utf8)
        #expect(!tab.contains("if state.stores.count > 1 { productTableHeader }"))
    }

    /// A subscription says what it is and what it costs, on the row itself.
    @Test func anApprovedMonthlySubscriptionShowsItsDurationAndPrice() {
        let actual = appleCatalog(
            [("com.example.monthly", "APPROVED", "USD 9.99", "P1M")])

        let summary = MoneyTab.storeSummary("com.example.monthly", store: .apple,
                                            actual: actual, territory: "USA")

        #expect(summary == "1 month · USD 9.99")
        #expect(MoneyTab.productStatus("com.example.monthly", stores: [.apple],
                                       actual: actual).text == "Approved")
    }

    /// Apple returns no row for a territory a product is not sold in. Showing
    /// nothing hides a price the developer is charging, so another country's
    /// is shown and named as the other country's.
    @Test func aTerritoryWithNoPriceFallsBackAndSaysWhichCountryItIs() {
        var actual = ActualState()
        var apple = ActualState.Apple()
        apple.catalogRead = true
        var product = ActualState.Apple.CatalogProduct()
        product.productId = "com.example.pro"
        product.state = "APPROVED"
        product.prices = ["JPN": "JPY 1200", "BRA": "BRL 24.90"]
        apple.catalog["com.example.pro"] = product
        actual.apple = apple

        let summary = MoneyTab.storeSummary("com.example.pro", store: .apple,
                                            actual: actual, territory: "USA")

        // The lowest territory code, so the same product shows the same money
        // on every draw. A dictionary's own order is not stable.
        #expect(summary == "BRL 24.90 (BRA)")
    }

    /// A product with no price returned at all still names itself.
    @Test func aSubscriptionWithNoPriceStillShowsItsDuration() {
        let actual = appleCatalog([("com.example.monthly", "APPROVED", nil, "P1M")])

        #expect(MoneyTab.storeSummary("com.example.monthly", store: .apple,
                                      actual: actual, territory: "USA") == "1 month")
    }

    // MARK: - The state on the collapsed row

    /// Finding out whether a purchase was approved used to mean opening each
    /// one. With two stores the cross-store answer holds the columns, so
    /// Apple's own word rides beside it.
    @Test func approvalShowsWithoutOpeningTheRow() {
        let actual = appleCatalog([("com.example.pro", "APPROVED", "USD 4.99", nil)])

        #expect(MoneyTab.appleProductPill("com.example.pro", stores: [.apple, .google],
                                          actual: actual)?.text == "Approved")

        let reviewing = appleCatalog([("com.example.pro", "IN_REVIEW", "USD 4.99", nil)])
        #expect(MoneyTab.appleProductPill("com.example.pro", stores: [.apple, .google],
                                          actual: reviewing)?.text == "In review")
    }

    /// With one store the status column already carries the word, so the pill
    /// would say it twice.
    @Test func theStateIsNotPrintedTwiceOnAOneStoreRow() {
        let actual = appleCatalog([("com.example.pro", "APPROVED", "USD 4.99", nil)])

        #expect(MoneyTab.appleProductPill("com.example.pro", stores: [.apple],
                                          actual: actual) == nil)
    }

    /// A product nobody has read about wears no state at all. An empty pill is
    /// better than a wrong one.
    @Test func anUnreadProductWearsNoStatePill() {
        var unread = ActualState()
        unread.apple = ActualState.Apple()

        #expect(MoneyTab.appleProductPill("com.example.pro", stores: [.apple, .google],
                                          actual: unread) == nil)
    }

    // MARK: - The import still only fills blanks

    /// The tab reads the store when it opens, so it may only fill what
    /// `store.yaml` leaves empty. A price typed this morning must survive a
    /// screen the developer walked past.
    @Test func theStoreReadNeverOverwritesWhatTheDeveloperWrote() {
        var manifest = Manifest()
        manifest.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .consumable,
                                                name: "My own name")]
        manifest.pricing = Manifest.Pricing(
            base: Price(amount: Decimal(string: "4.99")!, currency: "EUR", territory: "DEU"))

        var money = AppleMoney()
        money.purchases = [Manifest.Purchase(id: "com.example.pro", kind: .nonConsumable,
                                             name: "Apple's reference name")]
        money.price = Price(amount: Decimal(string: "9.99")!, currency: "USD",
                            territory: "USA")
        _ = manifest.mergeAppleMoney(money)

        #expect(manifest.purchases?.first?.name == "My own name")
        #expect(manifest.purchases?.first?.kind == .consumable)
        #expect(manifest.pricing?.base.currency == "EUR")
        #expect(manifest.pricing?.base.amount == Decimal(string: "4.99"))
    }
}

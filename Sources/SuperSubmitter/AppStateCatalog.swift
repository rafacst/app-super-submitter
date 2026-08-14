import SubmitKit
import SwiftUI

/// One offer belongs either to a purchase or to a subscription plan. The
/// editor is the same in both places, so the target names which one and the
/// view stays single.
enum OfferTarget: Hashable {
    case purchase(Int)
    case plan(group: Int, plan: Int)
}

enum OfferTextField { case id, duration, amount, currency, periods, regions }

/// The catalog states, the tax settings, and the offers of tab 5.
extension AppState {

    var autoConvertPricesBinding: Binding<Bool> {
        Binding(get: { self.manifest.pricing?.autoConvertOtherTerritories ?? true }, set: { value in
            guard var pricing = self.manifest.pricing else { return }
            pricing.autoConvertOtherTerritories = value
            self.manifest.pricing = pricing
            self.saveManifestReportingErrors()
        })
    }

    /// Whether the App Store offers this app in territories Apple adds later.
    ///
    /// Its own control and its own key. It was the Google price-conversion
    /// checkbox: one value meant two unrelated things, the label named the
    /// Google one, and an App Store app with no Play listing was shown that
    /// checkbox greyed out. So the only way to answer Apple's question was to
    /// not know you were answering it.
    var appleNewTerritoriesBinding: Binding<Bool> {
        Binding(get: { self.manifest.pricing?.appleNewTerritories ?? true }, set: { value in
            guard var pricing = self.manifest.pricing else { return }
            pricing.appleNewTerritories = value
            self.manifest.pricing = pricing
            self.saveManifestReportingErrors()
        })
    }

    // The comma-separated territory field is gone. `TerritoryPicker` writes
    // the countries now, and it writes both halves of the answer: the old
    // binding kept only the ticked ones, so unticking a country removed its
    // row and the plan then left that country exactly as the store had it.

    /// False while there is no price to hang them on.
    var canEditTerritories: Bool { manifest.pricing != nil }

    /// The countries the picker draws a tick against.
    ///
    /// Two sources, and the manifest wins where it speaks. `store.yaml` names
    /// the countries the developer has an opinion about; the store's own
    /// record answers for the rest. An app on sale in 175 countries whose
    /// manifest names one therefore opens with 175 ticked and not with one:
    /// what the screen shows is what the app sells, and a tick the developer
    /// never made is never written until they change something.
    var territoryTicks: Set<String> {
        var ticks = Set(liveAppleTerritories)
        for row in manifest.pricing?.territories ?? [] {
            if row.available { ticks.insert(row.territory) } else { ticks.remove(row.territory) }
        }
        return ticks
    }

    /// Whether `store.yaml` has an opinion about the countries at all.
    var territoriesFollowTheStore: Bool { (manifest.pricing?.territories ?? []).isEmpty }

    /// The rows of the picker, in continents.
    ///
    /// Apple's own list of territories when the record answered with one, and
    /// ICU's regions only until then. The two are not the same list: ICU knows
    /// 262 regions, the App Store sells in 175, and the difference is places
    /// with no store and codes that name one country twice.
    var territoryGroups: [StoreValues.TerritoryGroup] {
        StoreValues.territoryGroups(
            store: storeTerritories,
            including: Set((manifest.pricing?.territories ?? []).map(\.territory)))
    }

    /// Every territory the App Store availability record names, on sale or
    /// not. Empty until a read lands, and empty again when the read came back
    /// short: a partial record would hide countries the app sells in, and half
    /// a list is worse than the general one.
    var storeTerritories: Set<String> {
        guard let apple = actualState.apple else { return [] }
        let codes = Set(apple.territoryAvailability.keys)
        guard !codes.isEmpty, codes.count >= (apple.territoryCount ?? 0) else { return [] }
        return codes
    }

    /// Ticks or clears one country, a whole continent, or the whole planet.
    ///
    /// The write is the whole answer and not the change: every country that is
    /// ticked is written `available: true`, and every country the store sells
    /// in today that is not ticked is written `available: false`. Anything
    /// else and unticking a country would do nothing at all — the old field
    /// wrote the ticked ones and dropped the rest, and a territory the
    /// manifest does not name is a territory the plan leaves alone.
    ///
    /// Rows the manifest already holds are edited in place, so a preorder date
    /// or a release date on a country survives a tick.
    func setTerritories(_ codes: [String], selling: Bool) {
        guard var pricing = manifest.pricing else { return }
        var ticks = territoryTicks
        if selling { ticks.formUnion(codes) } else { ticks.subtract(codes) }

        var rows: [String: Manifest.TerritoryAvailability] = [:]
        for row in pricing.territories ?? [] { rows[row.territory] = row }
        for code in ticks {
            rows[code, default: Manifest.TerritoryAvailability(territory: code)]
                .available = true
        }
        // The countries with an answer to keep: the ones already named, and the
        // ones the store sells in. A country nobody has ever mentioned and that
        // is not on sale needs no row saying it is off.
        for code in Set(rows.keys).union(liveAppleTerritories) where !ticks.contains(code) {
            rows[code, default: Manifest.TerritoryAvailability(territory: code)]
                .available = false
        }
        pricing.territories = rows.values.sorted { $0.territory < $1.territory }
        manifest.pricing = pricing
        saveManifestReportingErrors()
    }

    /// The territories the App Store says this app is on sale in, as the last
    /// read found them.
    ///
    /// The read has always fetched this and no screen has ever shown it. A
    /// developer whose app sells in Brazil alone had no way to see that here,
    /// and the field above offers to change a set the app would not show.
    ///
    /// Sorted, because a dictionary hands its keys over in no order and a list
    /// of countries that reshuffles between reads reads as a change.
    var liveAppleTerritories: [String] {
        (actualState.apple?.territoryAvailability ?? [:])
            .filter(\.value).keys.sorted()
    }

    /// How many territories the App Store record holds, listed or not.
    ///
    /// The list above is paged; this number is Apple's own count. They differ
    /// only when a page failed, and a screen that says "3 countries" over a
    /// record of 175 is worse than one that says nothing.
    var liveAppleTerritoryCount: Int? { actualState.apple?.territoryCount }

    /// Reads where the App Store sells this app, for the tab that asks.
    ///
    /// The whole store read on the Summary tab fills this, and nothing else
    /// did. So the answer to "which countries is my app in" needed a read of
    /// every resource the app owns, and the developer of an app on sale in one
    /// country had no screen that said which one.
    ///
    /// Once. `hasAvailabilityRecord` is false until a read lands, and it is
    /// what stops the tab from asking again on every redraw. An app that has
    /// no record at all answers 404, which leaves the flag false and asks
    /// again on the next visit: that is one request for an app with nothing to
    /// report, and it is how a first submission notices the record appearing.
    func loadAppleAvailability() async {
        guard stores.contains(.apple), let appID = appleActionAppID,
              credentials.apple != nil,
              actualState.apple?.hasAvailabilityRecord != true,
              let availability = try? await diagnostics().appAvailability(appID: appID)
        else { return }
        // The developer can move to another app while Apple answers. What came
        // back is that app's availability, not this one's.
        guard appID == appleActionAppID else { return }
        var apple = actualState.apple ?? ActualState.Apple()
        apple.territoryAvailability = availability.territories
        apple.availableInNewTerritories = availability.newTerritories
        apple.territoryCount = availability.total
        actualState.apple = apple
    }

    func purchaseMetadataBinding(index: Int, key: String) -> Binding<String> {
        Binding(get: {
            guard let purchase = self.manifest.purchases?[safe: index] else { return "" }
            switch key {
            case "screenshot": return purchase.reviewScreenshot ?? ""
            case "content": return purchase.content ?? ""
            case "territories": return (purchase.availableTerritories ?? []).joined(separator: ", ")
            case "localeName":
                let locale = self.manifest.listing?.defaultLocale ?? ""
                return purchase.locales?[locale]?.name ?? ""
            default:
                let locale = self.manifest.listing?.defaultLocale ?? ""
                return purchase.locales?[locale]?.description ?? ""
            }
        }, set: { value in
            guard self.manifest.purchases?.indices.contains(index) == true else { return }
            switch key {
            case "screenshot":
                self.manifest.purchases?[index].reviewScreenshot = value.isEmpty ? nil : value
            case "content":
                self.manifest.purchases?[index].content = value.isEmpty ? nil : value
            case "territories":
                let codes = Self.splitList(value).map { $0.uppercased() }
                self.manifest.purchases?[index].availableTerritories = codes.isEmpty ? nil : codes
            case "localeName", "localeDescription":
                let locale = self.manifest.listing?.defaultLocale ?? ""
                var locales = self.manifest.purchases?[index].locales ?? [:]
                var text = locales[locale] ?? Manifest.ProductLocale()
                if key == "localeName" { text.name = value.isEmpty ? nil : value }
                else { text.description = value.isEmpty ? nil : value }
                locales[locale] = text
                self.manifest.purchases?[index].locales = locales
            default: break
            }
            self.saveManifestReportingErrors()
        })
    }

    func purchaseFlagBinding(index: Int, key: String) -> Binding<Bool> {
        Binding(get: {
            guard let purchase = self.manifest.purchases?[safe: index] else { return false }
            return key == "content" ? purchase.contentHosting ?? false
                : purchase.promotedPurchase ?? false
        }, set: { value in
            guard self.manifest.purchases?.indices.contains(index) == true else { return }
            if key == "content" { self.manifest.purchases?[index].contentHosting = value }
            else { self.manifest.purchases?[index].promotedPurchase = value }
            self.saveManifestReportingErrors()
        })
    }

    // MARK: - The states

    func purchaseActiveBinding(index: Int) -> Binding<Bool> {
        Binding(get: { self.manifest.purchases?[safe: index]?.active ?? true },
                set: { value in
                    guard self.manifest.purchases?.indices.contains(index) == true else { return }
                    self.manifest.purchases?[index].active = value
                    self.saveManifestReportingErrors()
                })
    }

    func planActiveBinding(groupIndex: Int, planIndex: Int) -> Binding<Bool> {
        Binding(get: {
            self.manifest.subscriptions?[safe: groupIndex]?
                .plans[safe: planIndex]?.active ?? true
        }, set: { value in
            guard self.hasPlan(groupIndex, planIndex) else { return }
            self.manifest.subscriptions?[groupIndex].plans[planIndex].active = value
            self.saveManifestReportingErrors()
        })
    }

    /// The one switch in the app that charges a real customer. The tab draws
    /// it in the warning colour and the validator warns again in the plan.
    func planMigrateBinding(groupIndex: Int, planIndex: Int) -> Binding<Bool> {
        Binding(get: {
            self.manifest.subscriptions?[safe: groupIndex]?
                .plans[safe: planIndex]?.migrateExistingSubscribers ?? false
        }, set: { value in
            guard self.hasPlan(groupIndex, planIndex) else { return }
            self.manifest.subscriptions?[groupIndex].plans[planIndex]
                .migrateExistingSubscribers = value ? true : nil
            self.saveManifestReportingErrors()
        })
    }

    /// Apple keeps one grace period for the whole app. Zero means none.
    func gracePeriodBinding(groupIndex: Int) -> Binding<Int> {
        Binding(get: {
            self.manifest.subscriptions?[safe: groupIndex]?.gracePeriodDays ?? 0
        }, set: { value in
            guard self.manifest.subscriptions?.indices.contains(groupIndex) == true else { return }
            self.manifest.subscriptions?[groupIndex].gracePeriodDays = value == 0 ? nil : value
            self.saveManifestReportingErrors()
        })
    }

    // MARK: - The tax settings

    func taxBinding(_ target: OfferTarget, withdrawal: Bool) -> Binding<String> {
        Binding(get: {
            let tax = self.tax(for: target)
            return (withdrawal ? tax?.withdrawalRight : tax?.category) ?? ""
        }, set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            var tax = self.tax(for: target) ?? Manifest.Tax()
            if withdrawal { tax.withdrawalRight = trimmed.isEmpty ? nil : trimmed }
            else { tax.category = trimmed.isEmpty ? nil : trimmed }
            let cleared = tax.category == nil && tax.withdrawalRight == nil
                && tax.eeaWithdrawalRight == nil
            self.setTax(cleared ? nil : tax, for: target)
            self.saveManifestReportingErrors()
        })
    }

    private func tax(for target: OfferTarget) -> Manifest.Tax? {
        switch target {
        case .purchase(let index): manifest.purchases?[safe: index]?.tax
        case .plan(let group, let plan):
            manifest.subscriptions?[safe: group]?.plans[safe: plan]?.tax
        }
    }

    private func setTax(_ tax: Manifest.Tax?, for target: OfferTarget) {
        switch target {
        case .purchase(let index):
            guard manifest.purchases?.indices.contains(index) == true else { return }
            manifest.purchases?[index].tax = tax
        case .plan(let group, let plan):
            guard hasPlan(group, plan) else { return }
            manifest.subscriptions?[group].plans[plan].tax = tax
        }
    }

    // MARK: - The offers

    func offers(for target: OfferTarget) -> [Manifest.Offer] {
        switch target {
        case .purchase(let index): manifest.purchases?[safe: index]?.offers ?? []
        case .plan(let group, let plan):
            manifest.subscriptions?[safe: group]?.plans[safe: plan]?.offers ?? []
        }
    }

    func addOffer(to target: OfferTarget) {
        var list = offers(for: target)
        // Google refuses anything but a lowercase id with digits and dashes,
        // so the draft is already legal in both stores.
        list.append(Manifest.Offer(id: "offer-\(list.count + 1)", kind: .freeTrial,
                                   duration: "P1W", periods: 1))
        setOffers(list, for: target)
        offerPriceInputs = [:]
        saveManifestReportingErrors()
    }

    func removeOffer(at index: Int, from target: OfferTarget) {
        var list = offers(for: target)
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        setOffers(list, for: target)
        offerPriceInputs = [:]
        saveManifestReportingErrors()
    }

    private func setOffers(_ list: [Manifest.Offer], for target: OfferTarget) {
        let stored = list.isEmpty ? nil : list
        switch target {
        case .purchase(let index):
            guard manifest.purchases?.indices.contains(index) == true else { return }
            manifest.purchases?[index].offers = stored
        case .plan(let group, let plan):
            guard hasPlan(group, plan) else { return }
            manifest.subscriptions?[group].plans[plan].offers = stored
        }
    }

    func offerBinding(_ target: OfferTarget, index: Int,
                      field: OfferTextField) -> Binding<String> {
        Binding(get: {
            guard let offer = self.offers(for: target)[safe: index] else { return "" }
            return switch field {
            case .id: offer.id
            case .duration: offer.duration ?? ""
            case .amount: self.offerPriceInput(target, index).amount
            case .currency: self.offerPriceInput(target, index).currency
            case .periods: offer.periods.map(String.init) ?? ""
            case .regions: (offer.regions ?? []).joined(separator: ", ")
            }
        }, set: { value in
            var list = self.offers(for: target)
            guard list.indices.contains(index) else { return }
            switch field {
            case .id:
                list[index].id = value.trimmingCharacters(in: .whitespacesAndNewlines)
            case .duration:
                let trimmed = value.trimmingCharacters(in: .whitespaces).uppercased()
                list[index].duration = trimmed.isEmpty ? nil : trimmed
            case .amount, .currency:
                let key = self.offerPriceKey(target, index)
                var input = self.offerPriceInput(target, index)
                if field == .amount { input.amount = value }
                else { input.currency = value.uppercased() }
                self.offerPriceInputs[key] = input
                switch PriceDraft.resolve(amount: input.amount, currency: input.currency) {
                case .empty:
                    list[index].price = nil
                    self.moneyError = nil
                case .invalid(let message):
                    // Keep the typed text visible and say what is wrong. A
                    // half-typed price is not an error yet.
                    self.moneyError = "Offer \(list[index].id): \(message)"
                    self.setOffers(list, for: target)
                    return
                case .valid(let price):
                    list[index].price = price
                    self.moneyError = nil
                }
            case .periods:
                list[index].periods = Int(value)
            case .regions:
                let regions = Self.splitList(value).map { $0.uppercased() }
                list[index].regions = regions.isEmpty ? nil : regions
            }
            self.setOffers(list, for: target)
            self.saveManifestReportingErrors()
        })
    }

    private func offerPriceKey(_ target: OfferTarget, _ index: Int) -> String {
        switch target {
        case .purchase(let purchase): "purchase:\(purchase):\(index)"
        case .plan(let group, let plan): "plan:\(group):\(plan):\(index)"
        }
    }

    private func offerPriceInput(_ target: OfferTarget, _ index: Int) -> CatalogPriceInput {
        let key = offerPriceKey(target, index)
        if let input = offerPriceInputs[key] { return input }
        let price = offers(for: target)[safe: index]?.price
        return CatalogPriceInput(amount: price.map { "\($0.amount)" } ?? "",
                                 currency: price?.currency ?? "")
    }

    func offerKindBinding(_ target: OfferTarget, index: Int) -> Binding<Manifest.Offer.Kind> {
        Binding(get: { self.offers(for: target)[safe: index]?.kind ?? .freeTrial },
                set: { value in
                    var list = self.offers(for: target)
                    guard list.indices.contains(index) else { return }
                    list[index].kind = value
                    self.setOffers(list, for: target)
                    self.saveManifestReportingErrors()
                })
    }

    func offerEligibilityBinding(_ target: OfferTarget,
                                 index: Int) -> Binding<Manifest.Offer.Eligibility> {
        Binding(get: { self.offers(for: target)[safe: index]?.eligibility ?? .new },
                set: { value in
                    var list = self.offers(for: target)
                    guard list.indices.contains(index) else { return }
                    list[index].eligibility = value
                    self.setOffers(list, for: target)
                    self.saveManifestReportingErrors()
                })
    }

    /// Whether the offer is on sale.
    ///
    /// Google creates every offer in the draft state, so an offer without this
    /// reaches no customer at all. The App Store reads it on an offer code
    /// alone, where false stops new redemptions and keeps every subscription
    /// that already used one.
    func offerActiveBinding(_ target: OfferTarget, index: Int) -> Binding<Bool> {
        Binding(get: { self.offers(for: target)[safe: index]?.active ?? false },
                set: { value in
                    var list = self.offers(for: target)
                    guard list.indices.contains(index) else { return }
                    list[index].active = value
                    self.setOffers(list, for: target)
                    self.saveManifestReportingErrors()
                })
    }

    /// The redeemable codes of an offer code.
    ///
    /// Apple creates the offer and no code, so an offer code without this block
    /// reaches nobody. `AppleOfferCodes` has always written it and the editor
    /// never asked for it, which made "Offer code" a kind you could pick and
    /// could not finish.
    ///
    /// Google generates its promotion codes in the Play Console, so nothing
    /// here reaches Google.
    enum OfferCodeField { case custom, oneTimeUse, expiresOn }

    func offerCodesBinding(_ target: OfferTarget, index: Int,
                           field: OfferCodeField) -> Binding<String> {
        Binding(get: {
            let codes = self.offers(for: target)[safe: index]?.codes
            return switch field {
            case .custom:
                (codes?.custom ?? [:]).sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            case .oneTimeUse: codes?.oneTimeUse.map(String.init) ?? ""
            case .expiresOn: codes?.expiresOn ?? ""
            }
        }, set: { value in
            var list = self.offers(for: target)
            guard list.indices.contains(index) else { return }
            var codes = list[index].codes ?? Manifest.Offer.Codes()
            switch field {
            case .custom:
                // `LAUNCH=500, PRESS=25`. The number is how many redemptions
                // Apple allows for that one code, and a code with no number
                // works once.
                var custom: [String: Int] = [:]
                for entry in Self.splitList(value) {
                    let parts = entry.split(separator: "=", maxSplits: 1)
                    let code = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
                    guard !code.isEmpty else { continue }
                    custom[code] = parts.count == 2
                        ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
                }
                codes.custom = custom.isEmpty ? nil : custom
            case .oneTimeUse:
                codes.oneTimeUse = Int(value.trimmingCharacters(in: .whitespaces))
            case .expiresOn:
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                codes.expiresOn = trimmed.isEmpty ? nil : trimmed
            }
            let empty = codes.custom == nil && codes.oneTimeUse == nil
                && codes.expiresOn == nil
            list[index].codes = empty ? nil : codes
            self.setOffers(list, for: target)
            self.saveManifestReportingErrors()
        })
    }

    private func hasPlan(_ groupIndex: Int, _ planIndex: Int) -> Bool {
        manifest.subscriptions?[safe: groupIndex]?.plans.indices.contains(planIndex) == true
    }
}

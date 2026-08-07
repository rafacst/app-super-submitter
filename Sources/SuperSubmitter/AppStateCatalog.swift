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

    var appTerritoriesBinding: Binding<String> {
        Binding(get: {
            (self.manifest.pricing?.territories ?? []).filter(\.available)
                .map(\.territory).joined(separator: ", ")
        }, set: { value in
            guard var pricing = self.manifest.pricing else { return }
            let codes = Self.splitList(value).map { $0.uppercased() }
            pricing.territories = codes.isEmpty ? nil : codes.map {
                Manifest.TerritoryAvailability(territory: $0)
            }
            self.manifest.pricing = pricing
            self.saveManifestReportingErrors()
        })
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

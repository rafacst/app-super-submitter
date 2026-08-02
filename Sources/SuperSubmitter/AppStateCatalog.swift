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
        saveManifestReportingErrors()
    }

    func removeOffer(at index: Int, from target: OfferTarget) {
        var list = offers(for: target)
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        setOffers(list, for: target)
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
            case .amount: offer.price.map { "\($0.amount)" } ?? ""
            case .currency: offer.price?.currency ?? ""
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
                let amount = field == .amount ? value : (list[index].price.map { "\($0.amount)" } ?? "")
                let currency = field == .currency
                    ? value.uppercased() : (list[index].price?.currency ?? "")
                switch PriceDraft.resolve(amount: amount, currency: currency) {
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

    private func hasPlan(_ groupIndex: Int, _ planIndex: Int) -> Bool {
        manifest.subscriptions?[safe: groupIndex]?.plans.indices.contains(planIndex) == true
    }
}

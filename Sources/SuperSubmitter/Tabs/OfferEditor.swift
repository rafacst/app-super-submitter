import SubmitKit
import SwiftUI

/// The discounts on one product. A purchase and a subscription plan hold the
/// same three shapes, so one editor serves both and the target says which
/// product it writes.
struct OfferEditor: View {
    @Environment(AppState.self) private var state
    let target: OfferTarget

    var body: some View {
        let offers = state.offers(for: target)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(offers.enumerated()), id: \.offset) { index, offer in
                VStack(alignment: .leading, spacing: 6) {
                    FieldRow {
                        LabeledField("Offer id", width: 200) {
                            TextField("", text: state.offerBinding(target, index: index,
                                                                   field: .id))
                        }
                        LabeledField("Kind", width: 175) {
                            Picker("", selection: state.offerKindBinding(target, index: index)) {
                                Text("Free trial").tag(Manifest.Offer.Kind.freeTrial)
                                Text("Introductory price").tag(Manifest.Offer.Kind.introPrice)
                                Text("Offer code").tag(Manifest.Offer.Kind.offerCode)
                            }.labelsHidden()
                        }
                        LabeledField("Who gets it", width: 130) {
                            Picker("", selection: state.offerEligibilityBinding(target,
                                                                                index: index)) {
                                Text("New").tag(Manifest.Offer.Eligibility.new)
                                Text("Existing").tag(Manifest.Offer.Eligibility.existing)
                                Text("Win back").tag(Manifest.Offer.Eligibility.winBack)
                            }.labelsHidden()
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            state.removeOffer(at: index, from: target)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                    FieldRow {
                        LabeledField("Duration", width: 130) {
                            ChoiceField(value: state.offerBinding(target, index: index,
                                                                  field: .duration),
                                        choices: StoreValues.offerDurations, emptyLabel: "No trial period")
                        }
                        if offer.kind != .freeTrial {
                            LabeledField("Amount", width: 90) {
                                TextField("0.00", text: state.offerBinding(target, index: index,
                                                                           field: .amount))
                            }
                            LabeledField("Currency", width: 175) {
                                ChoiceField(value: state.offerBinding(target, index: index,
                                                                      field: .currency),
                                            choices: StoreValues.currencies, emptyLabel: "Pick a currency", allowsNone: false)
                            }
                        }
                        LabeledField("Periods", width: 80) {
                            TextField("1", text: state.offerBinding(target, index: index,
                                                                    field: .periods))
                        }
                        // Only Google reads them. `GoogleCatalog` turns them
                        // into `regionalConfigs`, so they are Play countries
                        // and not App Store territories.
                        LabeledField("Regions", note: "Google") {
                            MultiChoiceField(text: state.offerBinding(target, index: index,
                                                                      field: .regions),
                                             choices: StoreValues.googleCountries,
                                             emptyLabel: "Every region")
                        }
                    }
                    if let hint = hint(for: offer) {
                        Text(hint).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                }
                .padding(9)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
            }
            Button("Add offer") { state.addOffer(to: target) }.controlSize(.small)
        }
    }

    /// Each kind lands on a different resource in each store. The line says
    /// where, so the developer is not surprised by the plan.
    private func hint(for offer: Manifest.Offer) -> String? {
        switch offer.kind {
        case .freeTrial:
            "App Store: an introductory offer with FREE_TRIAL. Google: an offer phase with a free price."
        case .introPrice:
            "App Store: an introductory offer with PAY_UP_FRONT. Google: an offer phase with an absolute discount."
        case .offerCode:
            "App Store: a subscription offer code. Google: an offer with a promotion targeting."
        case .promotional:
            "App Store: a promotional offer for existing subscribers. Google: a targeted offer phase."
        case .winBack:
            "App Store: a win-back offer for lapsed subscribers. Google: a returning-subscriber offer."
        }
    }
}

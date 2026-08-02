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
                    HStack {
                        TextField("Offer ID",
                                  text: state.offerBinding(target, index: index, field: .id))
                            .frame(width: 130)
                        Picker("Kind", selection: state.offerKindBinding(target, index: index)) {
                            Text("Free trial").tag(Manifest.Offer.Kind.freeTrial)
                            Text("Introductory price").tag(Manifest.Offer.Kind.introPrice)
                            Text("Offer code").tag(Manifest.Offer.Kind.offerCode)
                        }
                        .labelsHidden().frame(width: 155)
                        Picker("Eligibility",
                               selection: state.offerEligibilityBinding(target, index: index)) {
                            Text("New").tag(Manifest.Offer.Eligibility.new)
                            Text("Existing").tag(Manifest.Offer.Eligibility.existing)
                            Text("Win back").tag(Manifest.Offer.Eligibility.winBack)
                        }
                        .labelsHidden().frame(width: 110)
                        Button(role: .destructive) {
                            state.removeOffer(at: index, from: target)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                    HStack {
                        TextField("Duration",
                                  text: state.offerBinding(target, index: index, field: .duration))
                            .frame(width: 80)
                        if offer.kind != .freeTrial {
                            TextField("Amount",
                                      text: state.offerBinding(target, index: index, field: .amount))
                                .frame(width: 80)
                            TextField("Currency",
                                      text: state.offerBinding(target, index: index,
                                                               field: .currency))
                                .frame(width: 75)
                        }
                        TextField("Periods",
                                  text: state.offerBinding(target, index: index, field: .periods))
                            .frame(width: 70)
                        TextField("Regions, comma-separated",
                                  text: state.offerBinding(target, index: index, field: .regions))
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
        }
    }
}

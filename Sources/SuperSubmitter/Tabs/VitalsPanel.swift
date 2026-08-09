import SubmitKit
import SwiftUI

/// How the shipped app is doing, from both stores at once.
///
/// Everything on this panel is a read. The rest of tab 9 answers "did it go
/// out"; this answers "is it healthy now", which is the only question the app
/// could not answer before.
struct VitalsPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var apple: [StoreVitalsClient.Metric] = []
    @State private var google: [StoreVitalsClient.Metric] = []
    @State private var failures: [String] = []
    @State private var voided: [StoreVitalsClient.Voided] = []
    @State private var voidedError: String?
    @State private var lookupQuery = ""
    @State private var lookupProduct = ""
    @State private var lookup: StoreVitalsClient.PurchaseLookup?
    @State private var lookupBusy = false
    @State private var lookupError: String?

    var body: some View {
        Section_("How the shipped app is doing", icon: "waveform.path.ecg",
                 tint: Theme.teal) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apple reports the power and performance of the attached build. Google reports the crash rate and the ANR rate of the last 28 days. Both are reads.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch the vitals") { load() }
                        .disabled(busy)
                }

                ForEach(failures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loaded, apple.isEmpty, google.isEmpty, failures.isEmpty {
                    Text("Neither store reports a measurement yet. Both need a release that enough devices have run.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !apple.isEmpty { metricBlock(.apple, apple) }
                if !google.isEmpty { metricBlock(.google, google) }

                if state.stores.contains(.google) {
                    refundBlock
                    lookupBlock
                }
            }
            .storePanel(padding: 14)
        }
    }

    private func metricBlock(_ store: Store,
                             _ metrics: [StoreVitalsClient.Metric]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StoreLabel(store: store, size: 12.5)
            ForEach(metrics) { metric in
                HStack(spacing: 9) {
                    Text(metric.name).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    Spacer(minLength: 8)
                    if let detail = metric.detail {
                        Text(detail).font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                    Text(metric.value).font(Theme.mono(11))
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The refunds Google already issued. The app reads them and sends none:
    /// a refund moves real money to a customer, and that belongs to a person
    /// in the Play Console.
    @ViewBuilder private var refundBlock: some View {
        Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Refunds and chargebacks")
                    .font(Theme.font(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                QuietButton(title: "Fetch the voided purchases") { loadVoided() }
                    .disabled(busy || state.googleActionPackage == nil)
            }
            Text("Super Submitter reads these and issues none. A refund moves money to a customer, so you do that in the Play Console.")
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let voidedError {
                Label(voidedError, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.orange)
            }
            ForEach(voided) { entry in
                HStack(spacing: 9) {
                    Text(entry.orderId ?? entry.id).font(Theme.mono(10)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let reason = entry.reason {
                        Text(reason).font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                    }
                    if let date = entry.voidedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// The other half of support. The refunds above say what Google already
    /// took back; this says what one customer holds right now.
    ///
    /// One field takes whatever the ticket carried. An order id announces
    /// itself with `GPA.`, so the panel needs no picker, and the product id
    /// beside it is the one thing Google cannot infer: it puts the product in
    /// the path of the one-time endpoint and in no other.
    @ViewBuilder private var lookupBlock: some View {
        Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
        VStack(alignment: .leading, spacing: 7) {
            Text("Look an order or a purchase up")
                .font(Theme.font(size: 12, weight: .semibold))
            Text("Paste what the customer sent: an order id, several of them, or a purchase token. This reads. It issues no refund and it cancels nothing.")
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("GPA.1234-5678-9012-34567, or a purchase token",
                          text: $lookupQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
                    .frame(maxWidth: 340)
                TextField("Product id", text: $lookupProduct)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
                    .frame(width: 150)
                QuietButton(title: lookupBusy ? "Reading…" : "Look it up") { runLookup() }
                    .disabled(lookupBusy || state.googleActionPackage == nil
                        || lookupQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
            Text("Leave the product id empty to read a token as a subscription. Fill it to read the token as a one-time purchase.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)

            if let lookupError { ErrorLine(text: lookupError) }
            if let lookup {
                ForEach(lookup.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if lookup.blocks.isEmpty, lookup.notes.isEmpty {
                    Text("Google answered nothing for that. Check the id, and check that it belongs to this app.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lookup.blocks) { block in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(block.title).font(Theme.font(size: 11.5, weight: .medium))
                            .textSelection(.enabled)
                        ForEach(block.rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(row.name)
                                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                                Spacer(minLength: 8)
                                if let detail = row.detail {
                                    Text(detail).font(Theme.font(size: 10.5))
                                        .foregroundStyle(Theme.text3)
                                        .multilineTextAlignment(.trailing)
                                }
                                Text(row.value).font(Theme.mono(10.5))
                                    .textSelection(.enabled)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: 260, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.top, 4)
    }

    private func load() {
        busy = true
        Task {
            let result = await state.storeVitals()
            apple = result.apple
            google = result.google
            failures = result.failures
            loaded = true
            busy = false
        }
    }

    private func loadVoided() {
        track($busy, $voidedError) { voided = try await state.googleVoidedPurchases() }
    }

    private func runLookup() {
        track($lookupBusy, $lookupError) {
            lookup = try await state.googlePurchaseLookup(query: lookupQuery,
                                                          productId: lookupProduct)
        }
    }
}

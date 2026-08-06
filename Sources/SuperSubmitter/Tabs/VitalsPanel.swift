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

    var body: some View {
        Section_("How the shipped app is doing", icon: "waveform.path.ecg",
                 tint: Theme.teal) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apple reports the power and performance of the attached build. Google reports the crash rate and the ANR rate of the last 28 days. Both are reads.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Reading…" : "Read the vitals") { load() }
                        .disabled(busy)
                }

                ForEach(failures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loaded, apple.isEmpty, google.isEmpty, failures.isEmpty {
                    Text("Neither store reports a measurement yet. Both need a release that enough devices have run.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !apple.isEmpty { metricBlock(.apple, apple) }
                if !google.isEmpty { metricBlock(.google, google) }

                if state.stores.contains(.google) { refundBlock }
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
                    Text(metric.name).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    Spacer(minLength: 8)
                    if let detail = metric.detail {
                        Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
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
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                QuietButton(title: "Read the voided purchases") { loadVoided() }
                    .disabled(busy || state.googleActionPackage == nil)
            }
            Text("Super Submitter reads these and issues none. A refund moves money to a customer, so you do that in the Play Console.")
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let voidedError {
                Label(voidedError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
            }
            ForEach(voided) { entry in
                HStack(spacing: 9) {
                    Text(entry.orderId ?? entry.id).font(Theme.mono(10)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let reason = entry.reason {
                        Text(reason).font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                    if let date = entry.voidedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }
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
}

import SubmitKit
import SwiftUI

/// When the signing identities lapse.
///
/// Every call behind this is a read. Nothing here revokes a certificate or
/// deletes a profile: a revoked certificate breaks every machine that signs
/// with it, so that stays in the Developer portal where one person owns the
/// consequence.
///
/// The value is the expiry. A certificate and a profile both lapse on a date
/// that nothing else in the app shows, and the first sign of a lapse is usually
/// a failed build.
struct SigningIdentitiesPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var items: [AppleProvisioningClient.Item] = []
    @State private var failures: [String] = []

    var body: some View {
        Section_("Signing identities", icon: "seal", tint: Theme.purple) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The certificates, profiles, devices, and identifiers of the team, with the dates they lapse. Super Submitter reads these and revokes none.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch the identities") { load() }
                        .disabled(busy)
                }

                ForEach(failures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loaded, items.isEmpty, failures.isEmpty {
                    Text("The account holds no signing identity yet.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                }
                if !expiring.isEmpty { expiryNote }

                ForEach(AppleProvisioningClient.Item.Kind.allCases, id: \.self) { kind in
                    let group = items.filter { $0.kind == kind }
                    if !group.isEmpty { block(kind, group) }
                }
            }
            .storePanel(padding: 14)
        }
    }

    /// The whole point of the panel, so it goes above the lists and not inside
    /// one of them.
    private var expiring: [AppleProvisioningClient.Item] {
        items.filter { $0.isExpired || $0.expiresSoon() }
    }

    private var expiryNote: some View {
        WarningNote(expiring.contains(where: \.isExpired)
            ? "\(expiring.count) of these have lapsed or lapse within 30 days. Renew them in the Developer portal before the next build."
            : "\(expiring.count) of these lapse within 30 days. Renew them in the Developer portal before the next build.")
    }

    private func block(_ kind: AppleProvisioningClient.Item.Kind,
                       _ group: [AppleProvisioningClient.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.system(size: 12, weight: .semibold))
            ForEach(group) { item in row(item) }
        }
        .padding(.vertical, 4)
    }

    private func row(_ item: AppleProvisioningClient.Item) -> some View {
        HStack(spacing: 9) {
            Text(item.name).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                .lineLimit(1)
            if let detail = item.detail {
                Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let platform = item.platform {
                Text(platform).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if let state = item.state {
                Text(state).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if let expiry = item.expiresAt {
                Text(expiry.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10.5))
                    .foregroundStyle(item.isExpired ? Theme.orange
                        : item.expiresSoon() ? Theme.orange : Theme.text3)
            }
        }
    }

    private func load() {
        busy = true
        Task {
            let result = await state.appleProvisioning()
            items = result.items
            failures = result.failures
            loaded = true
            busy = false
        }
    }
}

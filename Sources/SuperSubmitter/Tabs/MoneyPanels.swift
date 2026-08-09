import SubmitKit
import SwiftUI

/// The two App Store surfaces that sit beside the catalogue rather than in it.
///
/// The Monetization tab writes what the products are. These answer the two
/// questions that come next: who can test them, and where a metadata change
/// goes now that Apple has a versioned draft for one.
///
/// Neither is a desired state, so neither reaches `store.yaml` or a plan row.
/// Each acts on a button and reports its own result.

// MARK: - The sandbox

/// The Apple Accounts that buy nothing.
///
/// "Clear the purchase history" is the button App Store Connect gets opened
/// for. A tester who bought the subscription once cannot buy it again, so every
/// second run of the paywall tests the restore path instead of the purchase
/// path until somebody clears it.
struct SandboxTestersPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var testers: [AppleSandboxClient.Tester] = []
    @State private var rateDrafts: [String: String] = [:]
    @State private var clearing: AppleSandboxClient.Tester?

    var body: some View {
        Section_("Sandbox testers", icon: "testtube.2", tint: Theme.teal) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("A sandbox account buys the products above without spending money, and a subscription that renews yearly on the App Store renews every few minutes here. Apple creates these in App Store Connect; this reads them and changes how they behave.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch the testers") { load() }
                        .disabled(busy || !state.hasCredential(for: .apple))
                }

                if let error { ErrorLine(text: error) }
                if loaded, testers.isEmpty {
                    Text("The account holds no sandbox tester. You add one in App Store Connect, under Users and Access.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(testers) { tester in row(tester) }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Clear the purchase history?", isPresented: $clearing.isPresent,
                            presenting: clearing) { tester in
            Button("Clear the history", role: .destructive) { clear(tester) }
            Button("Cancel", role: .cancel) {}
        } message: { tester in
            Text("\(tester.appleAccount) forgets every product it ever bought in the sandbox, and nothing gives that back. No money is involved: a sandbox account spends none.")
        }
    }

    private func row(_ tester: AppleSandboxClient.Tester) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Text(tester.appleAccount).font(Theme.font(size: 12, weight: .medium))
                    .textSelection(.enabled)
                if !tester.name.isEmpty {
                    Text(tester.name).font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                }
                if let territory = tester.territory {
                    Text(territory).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 8)
                Button("Clear the purchase history") { clearing = tester }
                    .controlSize(.small).disabled(busy)
            }
            HStack(spacing: 10) {
                ChoiceField(value: rateBinding(tester),
                            choices: AppleSandboxClient.renewalRates,
                            emptyLabel: "Apple's own rate")
                    .frame(width: 240)
                Toggle("Interrupt the purchases",
                       isOn: interruptBinding(tester))
                    .font(Theme.font(size: 11.5))
                if rateDrafts[tester.id] != nil {
                    Button("Save") { save(tester) }
                        .controlSize(.small).disabled(busy)
                    Button("Cancel") { rateDrafts[tester.id] = nil }
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            Text("An interrupted purchase is how the failure paths get tested: an expired card, a parental approval, a Terms sheet.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
        }
        .padding(9)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
    }

    private func rateBinding(_ tester: AppleSandboxClient.Tester) -> Binding<String> {
        Binding(get: { rateDrafts[tester.id] ?? tester.renewalRate ?? "" },
                set: { rateDrafts[tester.id] = $0 })
    }

    /// The toggle writes at once, because a switch that needs a Save beside it
    /// is a switch nobody trusts. The renewal rate keeps its Save, since a
    /// chooser is picked through and a write per keystroke would send four.
    private func interruptBinding(_ tester: AppleSandboxClient.Tester) -> Binding<Bool> {
        Binding(get: { tester.interruptPurchases }, set: { value in
            track($busy, $error) {
                try await state.setAppleSandboxTester(tester.id, renewalRate: nil,
                                                      interruptPurchases: value)
                testers = try await state.appleSandboxTesters()
            }
        })
    }

    private func load() {
        track($busy, $error) {
            testers = try await state.appleSandboxTesters()
            rateDrafts = [:]
            loaded = true
        }
    }

    private func save(_ tester: AppleSandboxClient.Tester) {
        guard let draft = rateDrafts[tester.id] else { return }
        track($busy, $error) {
            try await state.setAppleSandboxTester(tester.id, renewalRate: draft,
                                                  interruptPurchases: nil)
            rateDrafts[tester.id] = nil
            testers = try await state.appleSandboxTesters()
        }
    }

    private func clear(_ tester: AppleSandboxClient.Tester) {
        track($busy, $error) {
            try await state.clearAppleSandboxHistory([tester.id])
        }
    }
}

// MARK: - The versioned metadata drafts

/// Apple's newer way to change subscription metadata.
///
/// The run writes the live localizations and submits the group, which is the
/// older model and is what every existing manifest expects. Apple is moving a
/// metadata change into a versioned draft instead: the name a customer reads
/// today survives while the new one waits for a reviewer, and a rejection costs
/// the live product nothing.
///
/// This panel is that path, on a button. It creates the draft and pushes the
/// manifest's own names and descriptions onto it.
struct SubscriptionDraftsPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var products: [AppleSubscriptionVersionsClient.Product] = []

    var body: some View {
        Section_("Subscription metadata drafts", icon: "doc.badge.clock", tint: Theme.purple) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apple keeps a metadata change in a versioned draft that carries its own state through review. The live product goes on selling under the old text until a reviewer accepts the new one.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch the drafts") { load() }
                        .disabled(busy || state.appleActionAppID == nil)
                }

                if let error { ErrorLine(text: error) }
                if loaded, products.isEmpty {
                    Text("Apple holds no subscription group for this app yet. Run the plan once, and the groups appear here.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(products) { product in row(product) }
                if loaded, !products.isEmpty {
                    Text("Apply reconciles these versioned drafts automatically. These buttons remain for a deliberate manual draft write.")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .storePanel(padding: 14)
        }
    }

    private func row(_ product: AppleSubscriptionVersionsClient.Product) -> some View {
        let locales = state.appleDraftLocales(product)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Text(product.name)
                    .font(Theme.font(size: 12, weight: product.kind == .group ? .semibold : .regular))
                    .padding(.leading, product.kind == .group ? 0 : 14)
                if let draft = product.draft {
                    StatePill(text: AppleWords.title(draft.state ?? "draft").uppercased(),
                              foreground: draft.isEditable ? Theme.text2 : Theme.yellow,
                              background: Theme.sunken)
                    if let version = draft.version {
                        Text("v\(version)").font(Theme.mono(10))
                            .foregroundStyle(Theme.text3)
                    }
                }
                Spacer(minLength: 8)
                if product.draft == nil {
                    Button("Create a draft") { create(product) }
                        .controlSize(.small).disabled(busy)
                } else {
                    Text("\(locales.count) locales in the manifest")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    Button("Write the manifest text") { write(product) }
                        .controlSize(.small)
                        .disabled(busy || locales.isEmpty
                                  || product.draft?.isEditable != true)
                }
            }
            if let draft = product.draft, !draft.localizations.isEmpty {
                Text("The draft carries: \(draft.localizations.keys.sorted().joined(separator: ", "))")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .padding(.leading, product.kind == .group ? 0 : 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if product.draft?.isEditable == false {
                Text("A submitted draft is closed to edits. Apple opens the next one after this one lands.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .padding(.leading, product.kind == .group ? 0 : 14)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() {
        track($busy, $error) {
            products = try await state.appleSubscriptionDrafts()
            loaded = true
        }
    }

    private func create(_ product: AppleSubscriptionVersionsClient.Product) {
        track($busy, $error) {
            try await state.createAppleSubscriptionDraft(product)
            products = try await state.appleSubscriptionDrafts()
        }
    }

    private func write(_ product: AppleSubscriptionVersionsClient.Product) {
        track($busy, $error) {
            try await state.writeAppleSubscriptionDraft(product)
            products = try await state.appleSubscriptionDrafts()
        }
    }
}

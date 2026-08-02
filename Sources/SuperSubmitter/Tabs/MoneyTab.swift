import SubmitKit
import SwiftUI

/// Tab 5. Provider credentials stay in Keychain; catalog and prices live in the manifest.
struct MoneyTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 22) {
            if let error = state.moneyError {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.red)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 7))
            }
            Section_("Subscription provider") {
                Picker("Provider", selection: Binding(
                    get: { state.provider },
                    set: { value in state.setProvider(value) })) {
                    Text("None").tag(Manifest.Provider.none)
                    Text("RevenueCat").tag(Manifest.Provider.revenuecat)
                    Text("Adapty").tag(Manifest.Provider.adapty)
                }
                .pickerStyle(.segmented).frame(maxWidth: 460)
                if state.provider == .revenuecat { revenueCatPanel }
                if state.provider == .adapty { adaptyPanel }
            }
            priceSection
            availabilitySection
            purchasesSection
            subscriptionsSection
            if state.provider != .none { providerCatalog }
        }
        .frame(maxWidth: 940, alignment: .leading)
        .onChange(of: state.revenueCatAPIKey) { _, _ in state.revenueCatKeyChanged() }
        .onChange(of: state.revenueCatProjectID) { _, _ in state.updateRevenueCatProject() }
        .onChange(of: state.priceAmount) { _, _ in state.updateBasePrice() }
        .onChange(of: state.priceCurrency) { _, _ in state.updateBasePrice() }
        .onChange(of: state.priceTerritory) { _, _ in state.updateBasePrice() }
    }

    private var revenueCatPanel: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                LabeledContent("Secret v2 API key") {
                    SecureField("sk_…", text: $state.revenueCatAPIKey).frame(width: 250)
                }
                LabeledContent("Project ID") {
                    TextField("proj…", text: $state.revenueCatProjectID).frame(width: 220)
                }
                Button("Test connection", action: state.testRevenueCatConnection)
                    .disabled(state.revenueCatAPIKey.isEmpty || state.revenueCatProjectID.isEmpty)
            }
            connectionRow(state.revenueCatConnection)
            HStack {
                Link("Create a RevenueCat account ↗", destination: URL(string: "https://app.revenuecat.com/signup")!)
                Text("The API key is stored only in macOS Keychain.")
                    .foregroundStyle(Theme.text2)
            }.font(.system(size: 11.5))
        }.moneyPanel()
    }

    private var adaptyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adapty authentication belongs to its CLI; this app reads its status but never runs login.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
            connectionRow(state.adaptyConnection)
            HStack {
                Button("Check CLI login", action: state.checkAdapty)
                Button("Copy login command") { state.copyToPasteboard("adapty auth login") }
                Link("Create an Adapty account ↗", destination: URL(string: "https://app.adapty.io/registration")!)
            }
        }.moneyPanel()
    }

    private func connectionRow(_ status: ConnectionStatus) -> some View {
        HStack(spacing: 6) {
            Circle().fill(status.isConnected ? Theme.green : Theme.text3).frame(width: 7, height: 7)
            Text(status.label)
        }.font(.system(size: 11.5)).foregroundStyle(status.isConnected ? Theme.green : Theme.text2)
    }

    private var priceSection: some View {
        @Bindable var state = state
        return Section_("Base price") {
            HStack {
                TextField("Amount", text: $state.priceAmount).frame(width: 90)
                TextField("Currency", text: $state.priceCurrency).frame(width: 80)
                TextField("Territory", text: $state.priceTerritory).frame(width: 90)
                Text("Other territories are converted by the stores.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }.moneyPanel()
        }
    }

    private var availabilitySection: some View {
        Section_("Availability") {
            HStack(spacing: 12) {
                if state.stores.contains(.apple) {
                    Link("Edit App Store countries ↗",
                         destination: URL(string: "https://appstoreconnect.apple.com/apps")!)
                }
                if state.stores.contains(.google) {
                    Link("Open Play Console countries ↗",
                         destination: URL(string: "https://play.google.com/console/")!)
                }
            }.font(.system(size: 12)).moneyPanel()
        }
    }

    private var purchasesSection: some View {
        let purchases = state.manifest.purchases ?? []
        return Section_("In-app purchases") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(purchases.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            TextField("Product ID", text: state.purchaseBinding(index: index, field: .id))
                            Picker("Kind", selection: state.purchaseKindBinding(index: index)) {
                                ForEach(Manifest.Purchase.Kind.allCases, id: \.self) {
                                    Text($0.rawValue.replacingOccurrences(of: "_", with: " ")).tag($0)
                                }
                            }.labelsHidden().frame(width: 150)
                            Button(role: .destructive) { state.removePurchase(at: index) } label: {
                                Image(systemName: "trash")
                            }
                        }
                        HStack {
                            TextField("Name", text: state.purchaseBinding(index: index, field: .name))
                            TextField("Amount", text: state.purchaseBinding(index: index, field: .amount)).frame(width: 80)
                            TextField("Currency", text: state.purchaseBinding(index: index, field: .currency)).frame(width: 75)
                            TextField("Entitlements (comma-separated)",
                                      text: state.purchaseBinding(index: index, field: .entitlement))
                        }
                    }.moneyPanel()
                }
                Button("Add in-app purchase", action: state.addPurchase)
            }
        }
    }

    private var subscriptionsSection: some View {
        let groups = state.manifest.subscriptions ?? []
        return Section_("Subscriptions") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            TextField("Group ID", text: state.subscriptionGroupBinding(index: groupIndex, name: false))
                            TextField("Group name", text: state.subscriptionGroupBinding(index: groupIndex, name: true))
                            Button(role: .destructive) { state.removeSubscriptionGroup(at: groupIndex) } label: {
                                Image(systemName: "trash")
                            }
                        }
                        ForEach(Array(group.plans.enumerated()), id: \.offset) { planIndex, _ in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    TextField("Plan ID", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .id))
                                    TextField("Duration", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .duration)).frame(width: 75)
                                    TextField("Base plan ID", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .basePlanID)).frame(width: 120)
                                    Button(role: .destructive) { state.removePlan(groupIndex: groupIndex, planIndex: planIndex) } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                }
                                HStack {
                                    TextField("Amount", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .amount)).frame(width: 80)
                                    TextField("Currency", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .currency)).frame(width: 75)
                                    TextField("Entitlements", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .entitlement))
                                    TextField("Package", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .packageKey)).frame(width: 100)
                                }
                            }.padding(.leading, 14)
                        }
                        Button("Add plan") { state.addPlan(to: groupIndex) }.controlSize(.small)
                    }.moneyPanel()
                }
                Button("Add subscription group", action: state.addSubscriptionGroup)
            }
        }
    }

    private var providerCatalog: some View {
        HStack(alignment: .top, spacing: 14) {
            Section_(state.provider == .adapty ? "Access levels" : "Entitlements") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((state.manifest.entitlements ?? []).enumerated()), id: \.offset) { index, _ in
                        HStack {
                            TextField("Key", text: state.entitlementBinding(index: index, name: false))
                            TextField("Name", text: state.entitlementBinding(index: index, name: true))
                            Button(role: .destructive) { state.removeEntitlement(at: index) } label: { Image(systemName: "trash") }
                        }
                    }
                    Button("Add entitlement", action: state.addEntitlement)
                }.moneyPanel()
            }
            Section_(state.provider == .adapty ? "Paywalls" : "Offerings") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((state.manifest.offerings ?? []).enumerated()), id: \.offset) { index, _ in
                        VStack(alignment: .leading) {
                            HStack {
                                TextField("Key", text: state.offeringBinding(index: index, field: "key"))
                                TextField("Name", text: state.offeringBinding(index: index, field: "name"))
                                Button(role: .destructive) { state.removeOffering(at: index) } label: { Image(systemName: "trash") }
                            }
                            HStack {
                                TextField("Product IDs, comma-separated", text: state.offeringBinding(index: index, field: "products"))
                                Toggle("Current", isOn: state.offeringCurrentBinding(index: index))
                            }
                        }
                    }
                    Button("Add offering", action: state.addOffering)
                }.moneyPanel()
            }
        }
    }
}

struct Section_<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                .foregroundStyle(Theme.text3)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func moneyPanel() -> some View {
        padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

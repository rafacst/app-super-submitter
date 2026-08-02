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
            Section_("Subscription provider", icon: "arrow.triangle.2.circlepath", tint: Theme.orange) {
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
                    SecureField("Secret API key", text: $state.revenueCatAPIKey).frame(width: 250)
                }
                LabeledContent("Project ID") {
                    TextField("RevenueCat project ID", text: $state.revenueCatProjectID).frame(width: 220)
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
        return Section_("Base price", icon: "dollarsign.circle.fill", tint: Theme.green) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    TextField("Amount", text: $state.priceAmount).frame(width: 90)
                    TextField("Currency", text: $state.priceCurrency).frame(width: 80)
                    TextField("Territory", text: $state.priceTerritory).frame(width: 90)
                    Text("Other territories are converted by the stores.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                }
                resolvedPoint
            }.moneyPanel()
        }
    }

    /// Apple sells at a price point, never at the amount you typed. The panel
    /// shows what Apple resolved and warns over a 5 percent gap. Spec 6.7.
    @ViewBuilder
    private var resolvedPoint: some View {
        if state.stores.contains(.apple) {
            if let resolved = state.actualState.apple?.priceAmount,
               let requested = state.manifest.pricing?.base {
                let gap = state.priceGap ?? 0
                HStack(spacing: 8) {
                    Text("App Store price point")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    Text("\(resolved.description) \(requested.currency)")
                        .font(Theme.mono(11.5))
                        .foregroundStyle(gap > 0.05 ? Theme.yellow : Theme.text)
                    if gap > 0.05 {
                        StatePill(text: "\(Int((gap * 100).rounded()))% off the request",
                                  foreground: Theme.yellow, background: Theme.yellowBg)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Read the stores on the Plan tab to see the App Store price point.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
            }
        }
    }

    private var availabilitySection: some View {
        Section_("Availability", icon: "globe", tint: Theme.teal) {
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
        return Section_("In-app purchases", icon: "cart.fill", tint: Theme.accent) {
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
                        catalogRow(target: .purchase(index),
                                   active: state.purchaseActiveBinding(index: index),
                                   activeLabel: "On sale")
                        OfferEditor(target: .purchase(index))
                    }.moneyPanel()
                }
                Button("Add in-app purchase", action: state.addPurchase)
            }
        }
    }

    private var subscriptionsSection: some View {
        let groups = state.manifest.subscriptions ?? []
        return Section_("Subscriptions", icon: "arrow.clockwise.circle.fill", tint: Theme.purple) {
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
                        gracePeriodRow(groupIndex: groupIndex)
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
                                catalogRow(
                                    target: .plan(group: groupIndex, plan: planIndex),
                                    active: state.planActiveBinding(groupIndex: groupIndex,
                                                                    planIndex: planIndex),
                                    activeLabel: "Base plan active")
                                migrationRow(groupIndex: groupIndex, planIndex: planIndex)
                                OfferEditor(target: .plan(group: groupIndex, plan: planIndex))
                            }.padding(.leading, 14)
                        }
                        Button("Add plan") { state.addPlan(to: groupIndex) }.controlSize(.small)
                    }.moneyPanel()
                }
                Button("Add subscription group", action: state.addSubscriptionGroup)
            }
        }
    }

    /// The sale switch and the tax treatment. Both reach Google alone; the
    /// App Store keeps them in App Store Connect.
    private func catalogRow(target: OfferTarget, active: Binding<Bool>,
                            activeLabel: String) -> some View {
        HStack(spacing: 10) {
            Toggle(activeLabel, isOn: active)
                .disabled(!state.stores.contains(.google))
            TextField("Tax category", text: state.taxBinding(target, withdrawal: false))
                .frame(width: 190)
            TextField("Withdrawal right", text: state.taxBinding(target, withdrawal: true))
                .frame(width: 210)
            Text("Google only")
                .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            Spacer(minLength: 0)
        }
    }

    /// The one control in the app that charges an existing customer. It is
    /// drawn in the warning colour, and the plan warns again.
    private func migrationRow(groupIndex: Int, planIndex: Int) -> some View {
        let binding = state.planMigrateBinding(groupIndex: groupIndex, planIndex: planIndex)
        return HStack(spacing: 8) {
            Toggle("Migrate the existing subscribers to this price", isOn: binding)
                .disabled(!state.stores.contains(.google))
            if binding.wrappedValue {
                StatePill(text: "Charges a real customer",
                          foreground: Theme.yellow, background: Theme.yellowBg)
            }
            Spacer(minLength: 0)
        }
    }

    /// Apple keeps one grace period for the whole app. The tab says so, and
    /// the validator warns when two groups disagree.
    private func gracePeriodRow(groupIndex: Int) -> some View {
        let binding = state.gracePeriodBinding(groupIndex: groupIndex)
        return HStack(spacing: 10) {
            Picker("Billing grace period", selection: binding) {
                Text("None").tag(0)
                Text("3 days").tag(3)
                Text("16 days").tag(16)
                Text("28 days").tag(28)
            }
            .frame(width: 260)
            Text("The App Store keeps one for the whole app.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            Spacer(minLength: 0)
        }
    }

    private var providerCatalog: some View {
        HStack(alignment: .top, spacing: 14) {
            Section_(state.provider == .adapty ? "Access levels" : "Entitlements", icon: "lock.open.fill", tint: Theme.pink) {
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
            Section_(state.provider == .adapty ? "Paywalls" : "Offerings", icon: "rectangle.on.rectangle", tint: Theme.yellow) {
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

/// A titled block on a tab. The glyph carries the block faster than the words,
/// so a long tab reads as a column of pictures first.
struct Section_<Content: View>: View {
    let title: String
    var icon: String?
    var tint: Color = Theme.accent
    @ViewBuilder let content: Content

    init(_ title: String, icon: String? = nil, tint: Color = Theme.accent,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon { IconChip(symbol: icon, tint: tint, size: 21) }
                Text(title).font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(icon == nil ? Theme.text3 : Theme.text2)
            }
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

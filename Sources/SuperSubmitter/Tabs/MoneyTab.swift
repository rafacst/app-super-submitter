import SubmitKit
import SwiftUI

/// Tab 5. Provider credentials stay in Keychain; catalog and prices live in the manifest.
struct MoneyTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 22) {
            // Yellow, not red. Red says irreversible in this app, and a value
            // the developer can fix in the next keystroke is not that.
            if let error = state.moneyError { WarningNote(error) }
            // Two short blocks that answer "what does it cost, and where",
            // so they share a row and a height the way Review info does.
            HStack(alignment: .top, spacing: 14) {
                priceSection
                availabilitySection
            }
            .fixedSize(horizontal: false, vertical: true)
            purchasesSection
            subscriptionsSection
            // The two App Store surfaces beside the catalogue: who can test
            // these products, and where a metadata change goes now that Apple
            // has a versioned draft for one.
            if state.stores.contains(.apple) {
                SubscriptionDraftsPanel()
                SandboxTestersPanel()
            }
            if state.provider != .none { providerCatalog }
        }
        .frame(maxWidth: 940, alignment: .leading)
        .onChange(of: state.priceAmount) { _, _ in state.updateBasePrice() }
        .onChange(of: state.priceCurrency) { _, _ in state.updateBasePrice() }
        .onChange(of: state.priceTerritory) { _, _ in state.updateBasePrice() }
    }

    private var priceSection: some View {
        @Bindable var state = state
        return Section_("Base price", icon: "dollarsign.circle.fill", tint: Theme.green,
                        anchor: "money.basePrice") {
            VStack(alignment: .leading, spacing: 9) {
                FieldRow {
                    // Apple's own prices when Apple has told us what they are.
                    //
                    // The App Store sells at a price point and at nothing else,
                    // so the apply resolved whatever was typed to the nearest
                    // one and the developer learned the real price on the
                    // Summary tab, after the fact. A field that offers the
                    // prices that exist cannot be wrong in the first place.
                    //
                    // It stays a text field until the store has been read. See
                    // `applePricePoints`: a picker with no rows is a field that
                    // cannot be filled.
                    LabeledField("Amount", width: 120) {
                        let points = state.applePricePoints
                        if points.isEmpty {
                            TextField("0.00", text: $state.priceAmount)
                        } else {
                            ChoiceField(value: $state.priceAmount, choices: points,
                                        emptyLabel: "Pick a price", allowsNone: false)
                        }
                    }
                    LabeledField("Currency") {
                        ChoiceField(value: $state.priceCurrency,
                                    choices: StoreValues.currencies,
                                    emptyLabel: "Pick a currency", allowsNone: false)
                    }
                }
                LabeledField("Base territory", anchor: "money.baseTerritory") {
                    ChoiceField(value: $state.priceTerritory,
                                choices: StoreValues.appleTerritories,
                                emptyLabel: "Pick a territory")
                }
                Text("Other territories are converted by the stores.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                Toggle("Convert the base price for every Google region",
                       isOn: state.autoConvertPricesBinding)
                    .disabled(!state.stores.contains(.google))
                resolvedPoint
                Spacer(minLength: 0)
            }
            // The stretch happens before the panel is painted, so the two
            // panels on this row draw to one height instead of two.
            .frame(maxHeight: .infinity, alignment: .top)
            .storePanel()
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
                Text("Read the stores on the Summary tab to see the App Store price point.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
            }
        }
    }

    private var availabilitySection: some View {
        Section_("Availability", icon: "globe", tint: Theme.teal,
                 anchor: "money.availability") {
            VStack(alignment: .leading, spacing: 10) {
                // The app's own territories. The identically labelled field on
                // each purchase repeats down a list, so it carries no anchor.
                LabeledField("App Store territories",
                             anchor: "money.appStoreTerritories") {
                    MultiChoiceField(text: state.appTerritoriesBinding,
                                     choices: StoreValues.appleTerritories,
                                     emptyLabel: "Every territory Apple sells in")
                }
                if state.stores.contains(.apple) {
                    Link("Edit App Store countries ↗",
                         destination: URL(string: "https://appstoreconnect.apple.com/apps")!)
                }
                if state.stores.contains(.google) {
                    Link("Open Play Console countries ↗",
                         destination: URL(string: "https://play.google.com/console/")!)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .frame(maxHeight: .infinity, alignment: .top)
            .storePanel()
        }
    }

    private var purchasesSection: some View {
        let purchases = state.manifest.purchases ?? []
        return Section_("In-app purchases", icon: "cart.fill", tint: Theme.accent,
                        anchor: "money.purchases") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(purchases.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        FieldRow {
                            LabeledField("Product id", width: 380) {
                                TextField("", text: state.purchaseBinding(index: index, field: .id))
                            }
                            LabeledField("Kind", width: 150) {
                                Picker("", selection: state.purchaseKindBinding(index: index)) {
                                    Text("Consumable").tag(Manifest.Purchase.Kind.consumable)
                                    Text("Non-consumable").tag(Manifest.Purchase.Kind.nonConsumable)
                                    Text("Non-renewing").tag(Manifest.Purchase.Kind.nonRenewing)
                                }.labelsHidden()
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) { state.removePurchase(at: index) } label: {
                                Image(systemName: "trash")
                            }
                        }
                        FieldRow {
                            LabeledField("Name") {
                                TextField("", text: state.purchaseBinding(index: index, field: .name))
                            }
                            LabeledField("Amount", width: 90) {
                                TextField("0.00", text: state.purchaseBinding(index: index, field: .amount))
                            }
                            LabeledField("Currency", width: 175) {
                                ChoiceField(value: state.purchaseBinding(index: index, field: .currency),
                                            choices: StoreValues.currencies, emptyLabel: "Pick a currency", allowsNone: false)
                            }
                            LabeledField("Entitlements", note: "comma-separated", width: 230) {
                                TextField("", text: state.purchaseBinding(index: index, field: .entitlement))
                            }
                        }
                        catalogRow(target: .purchase(index),
                                   active: state.purchaseActiveBinding(index: index),
                                   activeLabel: "On sale")
                        // The eight store-specific controls, behind one row.
                        //
                        // A purchase needs an id, a kind, a name and a price.
                        // The rest are Apple's: a review screenshot, a hosted
                        // content path, a territory list, two localized
                        // strings and two flags. All twelve were open at all
                        // times, so the four that every purchase needs sat in
                        // a card of twelve, and the label columns of four
                        // different `FieldRow` widths never lined up.
                        //
                        // `DisclosureGroup` is what the Build tab already uses
                        // for the same job on the Android artifacts.
                        DisclosureGroup("Store options") {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldRow {
                                    LabeledField("Review screenshot", width: 300) {
                                        purchasePath(index: index, key: "screenshot",
                                                     extensions: ["png", "jpg", "jpeg"])
                                    }
                                    // "Hosted content path", not "Apple-hosted
                                    // content". The toggle below declares THAT
                                    // the content is hosted; this names the
                                    // file. Two controls under one label made
                                    // the pair unreadable.
                                    LabeledField("Hosted content path", width: 300) {
                                        purchasePath(index: index, key: "content",
                                                     extensions: ["zip"])
                                    }
                                    LabeledField("App Store territories") {
                                        MultiChoiceField(
                                            text: state.purchaseMetadataBinding(index: index,
                                                                                key: "territories"),
                                            choices: StoreValues.appleTerritories,
                                            emptyLabel: "Every territory")
                                    }
                                }
                                FieldRow {
                                    LabeledField("Localized name", width: 260) {
                                        TextField("", text: state.purchaseMetadataBinding(index: index,
                                                                                          key: "localeName"))
                                    }
                                    LabeledField("Localized description") {
                                        TextField("", text: state.purchaseMetadataBinding(index: index,
                                                                                          key: "localeDescription"))
                                    }
                                }
                                HStack {
                                    Toggle("Apple hosts this content",
                                           isOn: state.purchaseFlagBinding(index: index, key: "content"))
                                    Toggle("Promoted purchase",
                                           isOn: state.purchaseFlagBinding(index: index, key: "promoted"))
                                    Spacer()
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.system(size: 11.5))
                        OfferEditor(target: .purchase(index))
                    }.storePanel()
                }
                Button("Add in-app purchase", action: state.addPurchase)
            }
        }
    }

    /// A path on a purchase, with the picker and the missing-file check every
    /// other path box in the app already has.
    ///
    /// Both boxes were a bare `TextField` whose placeholder read `path`, so the
    /// developer had to know the spelling and got no word back when the file
    /// was not there. `AndroidArtifactsSection` set the pattern; this reuses it.
    private func purchasePath(index: Int, key: String,
                              extensions: [String]) -> some View {
        let binding = state.purchaseMetadataBinding(index: index, key: key)
        return PathField(path: binding,
                         problem: state.missingFileNote(for: binding.wrappedValue)) {
            guard let url = state.chooseOneFile(allowedExtensions: extensions) else { return }
            binding.wrappedValue = state.relativePath(for: url)
        }
    }

    private var subscriptionsSection: some View {
        let groups = state.manifest.subscriptions ?? []
        return Section_("Subscriptions", icon: "arrow.clockwise.circle.fill", tint: Theme.purple,
                        anchor: "money.subscriptions") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                    VStack(alignment: .leading, spacing: 9) {
                        FieldRow {
                            LabeledField("Group id", width: 300) {
                                TextField("", text: state.subscriptionGroupBinding(index: groupIndex, name: false))
                            }
                            LabeledField("Group name", width: 300) {
                                TextField("", text: state.subscriptionGroupBinding(index: groupIndex, name: true))
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) { state.removeSubscriptionGroup(at: groupIndex) } label: {
                                Image(systemName: "trash")
                            }
                        }
                        gracePeriodRow(groupIndex: groupIndex)
                        ForEach(Array(group.plans.enumerated()), id: \.offset) { planIndex, _ in
                            VStack(alignment: .leading, spacing: 7) {
                                FieldRow {
                                    LabeledField("Plan id") {
                                        TextField("", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .id))
                                    }
                                    LabeledField("Duration", width: 130) {
                                        ChoiceField(value: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .duration),
                                                    choices: StoreValues.subscriptionDurations,
                                                    emptyLabel: "Pick a period", allowsNone: false)
                                    }
                                    LabeledField("Base plan id", note: "Google", width: 130) {
                                        TextField("", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .basePlanID))
                                    }
                                    Button(role: .destructive) { state.removePlan(groupIndex: groupIndex, planIndex: planIndex) } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                }
                                FieldRow {
                                    LabeledField("Amount", width: 90) {
                                        TextField("0.00", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .amount))
                                    }
                                    LabeledField("Currency", width: 175) {
                                        ChoiceField(value: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .currency),
                                                    choices: StoreValues.currencies, emptyLabel: "Pick a currency", allowsNone: false)
                                    }
                                    LabeledField("Entitlements", note: "comma-separated") {
                                        TextField("", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .entitlement))
                                    }
                                    LabeledField("Package", note: "RevenueCat", width: 130) {
                                        TextField("", text: state.planBinding(groupIndex: groupIndex, planIndex: planIndex, field: .packageKey))
                                    }
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
                    }.storePanel()
                }
                Button("Add subscription group", action: state.addSubscriptionGroup)
            }
        }
    }

    /// The sale switch and the tax treatment. Both reach Google alone; the
    /// App Store keeps them in App Store Connect.
    private func catalogRow(target: OfferTarget, active: Binding<Bool>,
                            activeLabel: String) -> some View {
        FieldRow {
            LabeledField(" ", width: 130) {
                Toggle(activeLabel, isOn: active)
                    .disabled(!state.stores.contains(.google))
            }
            LabeledField("Tax category", note: "Google", width: 240) {
                ChoiceField(value: state.taxBinding(target, withdrawal: false),
                            choices: StoreValues.taxCategories,
                            emptyLabel: "The standard rate")
            }
            LabeledField("Withdrawal right", note: "Google", width: 310) {
                ChoiceField(value: state.taxBinding(target, withdrawal: true),
                            choices: StoreValues.withdrawalRights,
                            emptyLabel: "Not declared")
            }
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
                }.storePanel()
            }
            Section_(state.provider == .adapty ? "Paywalls" : "Offerings", icon: "rectangle.on.rectangle", tint: Theme.yellow) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((state.manifest.offerings ?? []).enumerated()), id: \.offset) { index, _ in
                        VStack(alignment: .leading, spacing: 7) {
                            FieldRow {
                                LabeledField("Key") {
                                    TextField("", text: state.offeringBinding(index: index, field: "key"))
                                }
                                LabeledField("Name") {
                                    TextField("", text: state.offeringBinding(index: index, field: "name"))
                                }
                                Button(role: .destructive) { state.removeOffering(at: index) } label: { Image(systemName: "trash") }
                            }
                            FieldRow {
                                LabeledField("Product ids", note: "comma-separated") {
                                    TextField("", text: state.offeringBinding(index: index, field: "products"))
                                }
                                LabeledField(" ", width: 90) {
                                    Toggle("Current", isOn: state.offeringCurrentBinding(index: index))
                                }
                            }
                        }
                    }
                    Button("Add offering", action: state.addOffering)
                }.storePanel()
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
    /// The `FieldIndex` id. A section is what the search jumps to when the
    /// fields under it repeat, which is every list of purchases, plans,
    /// offers, and pages.
    var anchor: String?
    @ViewBuilder let content: Content

    init(_ title: String, icon: String? = nil, tint: Color = Theme.accent,
         anchor: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.anchor = anchor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon { IconChip(symbol: icon, tint: tint, size: 21) }
                // Sentence case, not ALL CAPS with kerning. Capitals cost
                // scan speed, because a word set in them loses the shape the
                // eye reads it by, and no macOS form heads its groups that
                // way. One struct, so this reaches every tab.
                Text(title).font(Theme.sectionHeader)
                    .foregroundStyle(icon == nil ? Theme.text3 : Theme.text2)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldAnchor(anchor)
    }
}

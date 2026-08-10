import SubmitKit
import SwiftUI

/// Tab 5. Provider credentials stay in Keychain; catalog and prices live in the manifest.
struct MoneyTab: View {
    @Environment(AppState.self) private var state

    /// The products whose editor is open. Shut by default: the table answers
    /// what each store holds, and the twelve fields behind a row are for the
    /// one product being changed.
    @State private var openProducts: Set<Int> = []
    /// The plans whose fields are open, by group and plan.
    @State private var openPlans: Set<PlanKey> = []

    /// One plan's place in the manifest. A pair, because a plan index alone
    /// repeats across groups.
    struct PlanKey: Hashable {
        let group: Int
        let plan: Int
        init(_ group: Int, _ plan: Int) { self.group = group; self.plan = plan }
    }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 22) {
            oneStoreOnlyNote
            // Yellow, not red. Red says irreversible in this app, and a value
            // the developer can fix in the next keystroke is not that.
            if let error = state.moneyError { WarningNote(error) }
            // One column per store. The same money reaches the two of them in
            // two different shapes — Apple sells at a price point off a ladder
            // it publishes, Play takes micros and converts per currency — and
            // one "Base price" panel over one "Availability" panel said neither.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    priceSection
                    if state.stores.contains(.google) { googleMoneySection }
                }
                VStack(alignment: .leading, spacing: 14) {
                    priceSection
                    if state.stores.contains(.google) { googleMoneySection }
                }
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
        .onChange(of: state.priceTerritory) { _, _ in
            state.updateBasePrice()
            // The ladder is one country's money, so the territory names which
            // prices every Amount field on this tab may offer.
            Task { await state.loadApplePricePoints() }
        }
        .task { await state.loadApplePricePoints() }
    }

    /// The price, under the store whose ladder decides it.
    ///
    /// It carries the fields even when Apple is not selected, because the base
    /// price is one value and something has to own it.
    private var priceSection: some View {
        @Bindable var state = state
        let apple = state.stores.contains(.apple)
        return Section_(apple ? "App Store" : "Base price",
                        icon: apple ? nil : "dollarsign.circle.fill",
                        tint: Theme.green, anchor: "money.basePrice",
                        note: apple ? "A price point, not a number." : nil) {
            VStack(alignment: .leading, spacing: 9) {
                FieldRow {
                    LabeledField("Currency", width: 120) {
                        ChoiceField(value: $state.priceCurrency,
                                    choices: StoreValues.currencies,
                                    emptyLabel: "Pick a currency", allowsNone: false)
                    }
                    // The app's own ladder, which carries the free row that a
                    // purchase below must not offer. See `amountField`.
                    LabeledField("Amount") {
                        amountField($state.priceAmount, points: state.applePricePoints)
                    }
                }
                LabeledField("Base territory", anchor: "money.baseTerritory") {
                    ChoiceField(value: $state.priceTerritory,
                                choices: StoreValues.appleTerritories,
                                emptyLabel: "Pick a territory")
                }
                Text("Other territories are converted by the stores.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                // The Google half of this moved to the Play column, where the
                // rest of what Play does with the price already lives.
                if !state.stores.contains(.google) {
                    Toggle("Convert the base price for every Google region",
                           isOn: state.autoConvertPricesBinding)
                        .disabled(true)
                }
                resolvedPoint
                if state.stores.contains(.apple) {
                    LabeledField("Territories", anchor: "money.appStoreTerritories") {
                        MultiChoiceField(text: state.appTerritoriesBinding,
                                         choices: StoreValues.appleTerritories,
                                         emptyLabel: "Every territory Apple sells in")
                    }
                    Link("Edit App Store countries ↗",
                         destination: URL(string: "https://appstoreconnect.apple.com/apps")!)
                        .font(Theme.font(size: 12))
                }
                Spacer(minLength: 0)
            }
            // The stretch happens before the panel is painted, so the two
            // panels on this row draw to one height instead of two.
            .frame(maxHeight: .infinity, alignment: .top)
            .storePanel()
        }
    }

    /// A price, offered the way App Store Connect offers one.
    ///
    /// The web form locks this field to a menu: Apple sells at a price point
    /// and refuses everything else, so a number typed here used to be resolved
    /// to the nearest point behind the developer's back, and the app was the
    /// only place where 4.95 looked like a price you could charge.
    ///
    /// If the ladder is unavailable, the picker stays visible but unavailable.
    /// Arbitrary text would promise a price the store may refuse.
    @ViewBuilder
    private func amountField(_ value: Binding<String>,
                             points: [StoreValues.Choice]? = nil) -> some View {
        let points = points ?? state.appleProductPricePoints
        ChoiceField(value: value, choices: points,
                    emptyLabel: points.isEmpty ? "Prices unavailable" : "Pick a price",
                    allowsNone: false)
            .disabled(points.isEmpty)
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
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
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
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
            }
        }
    }


    /// What Play does with the same money.
    ///
    /// Play takes micros and converts per currency, so it holds no ladder and
    /// no price point. What it does hold is the conversion and the countries,
    /// and both used to sit in an "Availability" panel that named the App Store
    /// in its only field.
    private var googleMoneySection: some View {
        Section_("Google Play", tint: Theme.playGreen, anchor: "money.availability",
                 note: "Micros, per currency.") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Play takes the base price beside this and converts it into every currency it sells in. There is no price point to resolve.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Convert the base price for every Google region",
                       isOn: state.autoConvertPricesBinding)
                LabeledField("Countries") {
                    Text("Every country Play sells in, unless the Play Console says otherwise.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link("Open Play Console countries ↗",
                     destination: URL(string: "https://play.google.com/console/")!)
                Spacer(minLength: 0)
            }
            .font(Theme.font(size: 12))
            .frame(maxHeight: .infinity, alignment: .top)
            .storePanel()
        }
    }

    private var purchasesSection: some View {
        let purchases = state.manifest.purchases ?? []
        return Section_("In-app purchases", icon: "cart.fill", tint: Theme.accent,
                        anchor: "money.purchases") {
            VStack(alignment: .leading, spacing: 10) {
                if state.stores.count > 1 { productTableHeader }
                ForEach(Array(purchases.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        productRow(id: state.purchaseBinding(index: index, field: .id).wrappedValue,
                                   kind: Self.kindLabel(purchases[index].kind),
                                   open: openProducts.contains(index)) {
                            toggleProduct(index)
                        }
                        if openProducts.contains(index) {
                            purchaseEditor(index: index)
                        }
                    }.storePanel()
                }
                Button("Add in-app purchase", action: state.addPurchase)
            }
        }
    }


    // MARK: - The same product, on two stores

    /// What one store holds for one product id, in that store's own terms.
    ///
    /// Apple prices a product; Play prices a base plan inside a subscription,
    /// so the ids differ and the money does not. Nil means the store has never
    /// answered for this id, which is a different thing from a price of zero.
    static func storeSummary(_ id: String, store: Store,
                             actual: ActualState, territory: String) -> String? {
        switch store {
        case .apple:
            guard let product = actual.apple?.catalog[id],
                  let price = product.prices[territory] ?? product.prices.values.first
            else { return nil }
            // The ladder position, which is what a tier is. Apple stopped
            // naming tiers in 2023 and this read stores amounts, so this
            // counts the price up the ladder rather than printing a number
            // the API never sent.
            guard let point = ladderPoint(price, in: actual) else { return price }
            return "\(price) · point \(point)"
        case .google:
            guard let product = actual.google?.catalog[id] else { return nil }
            let price = product.prices[territory] ?? product.prices.values.first
            guard let plan = product.basePlanId else { return price }
            return [price, "base plan \(plan)"].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// Where a price stands on the ladder Apple published for the territory
    /// the ladder was read for. Nil when the ladder is unread or the price is
    /// not on it, which is itself worth knowing and the validator already says.
    static func ladderPoint(_ price: String, in actual: ActualState) -> Int? {
        guard let apple = actual.apple, !apple.pricePoints.isEmpty else { return nil }
        let digits = price.split(separator: " ").last.map(String.init) ?? price
        // Compared as numbers with a half-cent tolerance, not as `Decimal`
        // equality: a ladder built from float literals and a price parsed from
        // a string are the same money and different bit patterns.
        guard let amount = Decimal(string: digits) else { return nil }
        let wanted = NSDecimalNumber(decimal: amount).doubleValue
        guard let index = apple.pricePoints.firstIndex(where: {
            abs(NSDecimalNumber(decimal: $0).doubleValue - wanted) < 0.005
        }) else { return nil }
        return index + 1
    }

    /// Where a product stands across the two stores.
    ///
    /// "Will add" is the honest answer before a read as well as after one: the
    /// app has not been told the store holds it, so the apply will create it.
    static func productStatus(_ id: String, stores: Set<Store>,
                              actual: ActualState) -> (text: String, colour: Color) {
        let holders = stores.filter { store in
            switch store {
            case .apple: actual.apple?.catalog[id] != nil
            case .google: actual.google?.catalog[id] != nil
            }
        }
        if holders.isEmpty { return ("Will add", Theme.accent) }
        if holders.count == stores.count { return ("In sync", Theme.text2) }
        let only = holders.first!
        return ("Only on \(only.storeName)", Theme.yellow)
    }

    /// The products one store holds and the other does not.
    private var oneStoreOnly: [String] {
        guard state.stores.count > 1 else { return [] }
        let ids = (state.manifest.purchases ?? []).map(\.id)
            + (state.manifest.subscriptions ?? []).flatMap { $0.plans.map(\.id) }
        return ids.filter {
            Self.productStatus($0, stores: state.stores,
                               actual: state.actualState).text.hasPrefix("Only on")
        }
    }

    @ViewBuilder
    private var oneStoreOnlyNote: some View {
        let stranded = oneStoreOnly
        if !stranded.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.yellow)
                Text(stranded.count == 1
                     ? "1 product exists on one store only"
                     : "\(stranded.count) products exist on one store only")
                    .font(Theme.font(size: 12, weight: .semibold))
                Text(stranded.joined(separator: ", "))
                    .font(Theme.mono(11)).foregroundStyle(Theme.text2)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var productTableHeader: some View {
        HStack(spacing: 10) {
            Text("Product id").frame(maxWidth: .infinity, alignment: .leading)
            Text("Type").frame(width: 120, alignment: .leading)
            ForEach(Store.allCases.filter(state.stores.contains), id: \.self) { store in
                Text(store.storeName).frame(width: 190, alignment: .leading)
            }
            Text("").frame(width: 110, alignment: .leading)
        }
        .font(Theme.font(size: 10.5, weight: .medium))
        .foregroundStyle(Theme.text3)
        .padding(.horizontal, 13)
    }

    /// One row of the table: the id, the type, what each store holds, and
    /// where the two stand. Pressing it opens the fields behind it.
    private func productRow(id: String, kind: String, open: Bool,
                            press: @escaping () -> Void) -> some View {
        let status = Self.productStatus(id, stores: state.stores, actual: state.actualState)
        let territory = state.manifest.pricing?.base.territory ?? "USA"
        return Button(action: press) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(Theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(id.isEmpty ? "No product id" : id)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(id.isEmpty ? Theme.text3 : Theme.text)
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(kind).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .frame(width: 120, alignment: .leading)
                if state.stores.count > 1 {
                    ForEach(Store.allCases.filter(state.stores.contains), id: \.self) { store in
                        Text(Self.storeSummary(id, store: store, actual: state.actualState,
                                               territory: territory)
                             ?? "— not read yet")
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(width: 190, alignment: .leading)
                    }
                }
                StatePill(text: status.text, foreground: status.colour,
                          background: Theme.sunken)
                    .frame(width: 110, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
    }


    /// The word the tab already uses for a kind, in the picker below.
    static func kindLabel(_ kind: Manifest.Purchase.Kind) -> String {
        switch kind {
        case .consumable: "Consumable"
        case .nonConsumable: "Non-consumable"
        case .nonRenewing: "Non-renewing"
        }
    }

    private func togglePlan(_ group: Int, _ plan: Int) {
        let key = PlanKey(group, plan)
        if openPlans.contains(key) { openPlans.remove(key) } else { openPlans.insert(key) }
    }

    private func toggleProduct(_ index: Int) {
        if openProducts.contains(index) { openProducts.remove(index) }
        else { openProducts.insert(index) }
    }

    /// The twelve fields behind one row of the table.
    ///
    /// Its own function, because the row header, the fold and this body in
    /// one expression is more than the type checker will infer in a ForEach.
    @ViewBuilder
    private func purchaseEditor(index: Int) -> some View {
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
                            LabeledField("Amount", width: 110) {
                                amountField(state.purchaseBinding(index: index, field: .amount))
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
                        .font(Theme.font(size: 11.5))
                        OfferEditor(target: .purchase(index))
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
                        if state.stores.count > 1 { productTableHeader }
                        ForEach(Array(group.plans.enumerated()), id: \.offset) { planIndex, _ in
                            VStack(alignment: .leading, spacing: 7) {
                                productRow(id: group.plans[planIndex].id, kind: "Subscription",
                                           open: openPlans.contains(PlanKey(groupIndex, planIndex))) {
                                    togglePlan(groupIndex, planIndex)
                                }
                                if openPlans.contains(PlanKey(groupIndex, planIndex)) {
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
                                    LabeledField("Plan type", note: "Apple", width: 180) {
                                        ChoiceField(
                                            value: state.planBinding(groupIndex: groupIndex,
                                                                     planIndex: planIndex,
                                                                     field: .applePlanType),
                                            choices: StoreValues.appleSubscriptionPlanTypes)
                                    }
                                    Button(role: .destructive) { state.removePlan(groupIndex: groupIndex, planIndex: planIndex) } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                }
                                FieldRow {
                                    LabeledField("Amount", width: 110) {
                                        amountField(state.planBinding(groupIndex: groupIndex,
                                                                      planIndex: planIndex, field: .amount))
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
                                }
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
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            Spacer(minLength: 0)
        }
    }

    private var providerCatalog: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                providerEntitlements
                providerOfferings
            }
            VStack(alignment: .leading, spacing: 14) {
                providerEntitlements
                providerOfferings
            }
        }
    }

    private var providerEntitlements: some View {
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
    }

    private var providerOfferings: some View {
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

// `Section_` moved to Design/Section.swift when it learned to fold.

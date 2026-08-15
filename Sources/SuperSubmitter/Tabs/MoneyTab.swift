import SubmitKit
import SwiftUI

/// What the app sells inside itself. Provider credentials stay in Keychain;
/// the catalog lives in the manifest.
///
/// The price of the app and the countries it sells in are the Availability
/// tab's. They were the top two panels here, which made one screen answer two
/// questions and left the countries filed under the name of the catalogue.
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
        // The ladder every Amount field on this tab offers. The base territory
        // that decides which country's money it is belongs to Availability;
        // this reads whatever that tab last set.
        .task { await state.loadApplePricePoints() }
        // What the store already charges and sells, for an app that is on it.
        // It reads the catalog, and the two product ladders are read off a
        // product, so they follow it rather than racing it.
        .task {
            await state.loadStoreMonetization()
            await state.loadAppleProductPricePoints()
        }
    }

    /// A price, offered the way App Store Connect offers one.
    ///
    /// The web form locks this field to a menu: Apple sells at a price point
    /// and refuses everything else, so a number typed here used to be resolved
    /// to the nearest point behind the developer's back, and the app was the
    /// only place where 4.95 looked like a price you could charge.
    ///
    /// The ladder is the one for that kind of product: a subscription is not
    /// priced off the purchase table and neither is priced off the app's.
    ///
    /// If the ladder is unavailable, the picker stays visible but unavailable.
    /// Arbitrary text would promise a price the store may refuse.
    @ViewBuilder
    private func amountField(_ value: Binding<String>,
                             points: [StoreValues.Choice]) -> some View {
        ChoiceField(value: value, choices: points,
                    emptyLabel: points.isEmpty ? "Prices unavailable" : "Pick a price",
                    allowsNone: false)
            .disabled(points.isEmpty)
    }

    private var purchasesSection: some View {
        let purchases = state.manifest.purchases ?? []
        return Section_("In-app purchases", icon: "cart.fill", tint: Theme.accent,
                        anchor: "money.purchases") {
            VStack(alignment: .leading, spacing: 10) {
                importCatalogNote
                if !purchases.isEmpty { productTableHeader }
                ForEach(Array(purchases.enumerated()), id: \.offset) { index, _ in
                    let id = state.purchaseBinding(index: index, field: .id).wrappedValue
                    VStack(alignment: .leading, spacing: 8) {
                        productRow(id: id,
                                   kind: Self.kindLabel(purchases[index].kind),
                                   open: openProducts.contains(index)) {
                            toggleProduct(index)
                        }
                        if openProducts.contains(index) {
                            // Above the fields, not below them. It is the
                            // thing to read before typing.
                            appleReviewNote(id)
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
            guard let product = actual.apple?.catalog[id] else { return nil }
            var parts: [String] = []
            // What makes a subscription a subscription. It was in the editor
            // behind the row and nowhere on the row itself, so a list of plans
            // read as a list of identical products.
            if let duration = product.duration {
                parts.append(StoreValues.subscriptionDurations
                    .first { $0.value == duration }?.label ?? duration)
            }
            if let price = applePrice(product, territory: territory) {
                parts.append(price.text)
                // The ladder position, which is what a tier is. Apple stopped
                // naming tiers in 2023 and this read stores amounts, so this
                // counts the price up the ladder rather than printing a number
                // the API never sent. Only for the territory the ladder was
                // read for: another country's money is not on this ladder.
                if price.isBase, let point = ladderPoint(price.text, in: actual) {
                    parts.append("point \(point)")
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .google:
            guard let product = actual.google?.catalog[id] else { return nil }
            let price = product.prices[territory] ?? product.prices.values.first
            guard let plan = product.basePlanId else { return price }
            return [price, "base plan \(plan)"].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// The price to show for one product, and whether it is the territory that
    /// was asked for.
    ///
    /// Apple returns a price per territory and does not always return the base
    /// one: a product sold in a subset of countries has no row for a territory
    /// it is not sold in. Showing nothing there hides a price the developer is
    /// charging, so another country's is shown and named as such.
    ///
    /// The fallback is the lowest territory code and not `values.first`. A
    /// dictionary hands its values back in no particular order, so the same
    /// product used to show a different country's money from one draw to the
    /// next.
    static func applePrice(_ product: ActualState.Apple.CatalogProduct,
                           territory: String) -> (text: String, isBase: Bool)? {
        if let exact = product.prices[territory] { return (exact, true) }
        guard let fallback = product.prices.sorted(by: { $0.key < $1.key }).first else {
            return nil
        }
        return ("\(fallback.value) (\(fallback.key))", false)
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
        guard let amount = Price.amount(from: digits) else { return nil }
        let wanted = NSDecimalNumber(decimal: amount).doubleValue
        guard let index = apple.pricePoints.firstIndex(where: {
            abs(NSDecimalNumber(decimal: $0).doubleValue - wanted) < 0.005
        }) else { return nil }
        return index + 1
    }

    /// Whether a store has been asked about this app's catalog at all.
    ///
    /// An empty catalog is two facts and they are not the same: the store was
    /// asked and holds nothing, or nobody has asked. Only the first one lets
    /// the tab say what the apply will do.
    static func catalogRead(_ store: Store, _ actual: ActualState) -> Bool {
        switch store {
        case .apple: actual.apple?.catalogRead == true
        case .google: actual.google != nil
        }
    }

    /// Where a product stands across the selected stores.
    ///
    /// "Will add" used to be the answer before a read as well as after one, on
    /// the grounds that the app had not been told the store holds it. That is
    /// the bug: an unread catalog is not a store saying no, and the tab was
    /// telling a developer their approved, on-sale purchases were about to be
    /// created. A claim about what the apply will do needs a read behind it.
    ///
    /// So the ladder is: nobody asked, then the store's own answer.
    static func productStatus(_ id: String, stores: Set<Store>,
                              actual: ActualState) -> (text: String, colour: Color) {
        let unread = stores.filter { !catalogRead($0, actual) }
        let holders = stores.filter { store in
            switch store {
            case .apple: actual.apple?.catalog[id] != nil
            case .google: actual.google?.catalog[id] != nil
            }
        }
        // A store that holds it is an answer whatever the others did, and it
        // is the answer that stops a false creation claim.
        if holders.isEmpty, !unread.isEmpty {
            return (unread.count == stores.count ? "Not read yet" : "Could not verify",
                    Theme.text3)
        }
        if holders.isEmpty { return ("Will add", Theme.accent) }
        if holders.count == stores.count {
            // One store, and the store holds it. "In sync" says nothing a
            // developer cannot already see, and Apple's own word for the
            // product is what they came to the tab for.
            if stores.count == 1, stores.first == .apple,
               let product = actual.apple?.catalog[id] {
                if product.isWithReview { return ("In review", Theme.yellow) }
                if product.isApproved { return ("Approved", Theme.green) }
            }
            return ("In sync", Theme.text2)
        }
        // Some stores hold it and some were never asked. Naming one of them as
        // the only holder would be a claim about a store nobody read.
        if !unread.isEmpty { return ("Could not verify", Theme.text3) }
        let only = holders.first!
        return ("Only on \(only.storeName)", Theme.yellow)
    }

    /// Apple's own word for a product, for the row that is not expanded.
    ///
    /// The review state used to live behind the disclosure triangle alone, so
    /// finding out whether a purchase was approved meant opening each one.
    static func appleProductPill(_ id: String, stores: Set<Store>,
                                 actual: ActualState) -> (text: String, colour: Color)? {
        guard stores.contains(.apple), stores.count > 1,
              let product = actual.apple?.catalog[id] else { return nil }
        if product.isWithReview { return ("In review", Theme.yellow) }
        if product.isApproved { return ("Approved", Theme.green) }
        return nil
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

    /// Whether the row keeps a column for Apple's own review state.
    ///
    /// With one store the status column already carries that word, so a second
    /// column would print it twice. The header and the row ask the same
    /// question, or the two drift out of line.
    private var showsAppleStateColumn: Bool {
        state.stores.count > 1 && state.stores.contains(.apple)
    }

    private var productTableHeader: some View {
        HStack(spacing: 10) {
            Text("Product id").frame(maxWidth: .infinity, alignment: .leading)
            Text("Type").frame(width: 120, alignment: .leading)
            ForEach(Store.allCases.filter(state.stores.contains), id: \.self) { store in
                Text(store.storeName).frame(width: 190, alignment: .leading)
            }
            if showsAppleStateColumn {
                Text("App Store review").frame(width: 96, alignment: .leading)
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
                // Every selected store, including when there is only one. The
                // column was drawn for two stores alone, so an Apple-only app
                // could not see the price the App Store is charging today
                // anywhere on this tab, which is most of what it is for.
                ForEach(Store.allCases.filter(state.stores.contains), id: \.self) { store in
                    Text(Self.storeSummary(id, store: store, actual: state.actualState,
                                           territory: territory)
                         ?? (Self.catalogRead(store, state.actualState)
                             ? "— not on this store" : "— not read yet"))
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(width: 190, alignment: .leading)
                }
                // Apple's own word for the product, beside the cross-store
                // answer rather than behind the disclosure triangle. The slot
                // is kept whether or not there is a word for this row, so the
                // column under the header stays a column.
                if showsAppleStateColumn {
                    let pill = Self.appleProductPill(id, stores: state.stores,
                                                     actual: state.actualState)
                    Group {
                        if let pill {
                            StatePill(text: pill.text, foreground: pill.colour,
                                      background: Theme.sunken)
                        }
                    }
                    .frame(width: 96, alignment: .leading)
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

    /// What Apple has already decided about this product.
    ///
    /// A product carries its own review, separately from the app: Apple
    /// approves it once and sends it back through review when its name, its
    /// review note or its localizations change. Nothing on this tab said so,
    /// so an approved purchase looked exactly like a draft one and a developer
    /// editing a live product had no way to know what it would cost.
    @ViewBuilder
    private func appleReviewNote(_ id: String) -> some View {
        if let product = state.appleProductState(id), product.isApproved {
            HStack(alignment: .top, spacing: 8) {
                StatePill(text: "Approved", foreground: Theme.green,
                          background: Theme.greenBg)
                Text("The App Store has approved this product. Changing its name, its review note or its store text sends it back for review on its own. The price is not reviewed and changes at once.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } else if let product = state.appleProductState(id), product.isWithReview {
            HStack(alignment: .top, spacing: 8) {
                StatePill(text: "In review", foreground: Theme.yellow,
                          background: Theme.yellowBg)
                Text("App Store review has this product now. An edit here goes to the version being reviewed.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    /// The way in for the products the store already holds.
    ///
    /// The read has always fetched every product on the App Store, and the
    /// table only ever drew the ones `store.yaml` named. An app with approved
    /// purchases showed an empty catalog, and the only way to manage one was
    /// to retype its id exactly.
    @ViewBuilder
    private var importCatalogNote: some View {
        let waiting = state.appleCatalogNotImported
        if waiting > 0 {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.accent)
                Text(waiting == 1
                     ? "The App Store holds 1 product this app does not list"
                     : "The App Store holds \(waiting) products this app does not list")
                    .font(Theme.font(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                QuietButton(title: "Bring them in") {
                    let added = state.importAppleCatalog()
                    state.errorMessage = added == 1
                        ? "1 product came in from the App Store. Nothing you had typed was written over."
                        : "\(added) products came in from the App Store. Nothing you had typed was written over."
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 8))
        }
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
                                amountField(state.purchaseBinding(index: index, field: .amount),
                                            points: state.applePurchasePricePoints)
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
                        Fold("Store options") {
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
                        if !group.plans.isEmpty { productTableHeader }
                        ForEach(Array(group.plans.enumerated()), id: \.offset) { planIndex, _ in
                            VStack(alignment: .leading, spacing: 7) {
                                productRow(id: group.plans[planIndex].id, kind: "Subscription",
                                           open: openPlans.contains(PlanKey(groupIndex, planIndex))) {
                                    togglePlan(groupIndex, planIndex)
                                }
                                if openPlans.contains(PlanKey(groupIndex, planIndex)) {
                                appleReviewNote(group.plans[planIndex].id)
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
                                                                      planIndex: planIndex,
                                                                      field: .amount),
                                                    points: state.appleSubscriptionPricePoints)
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

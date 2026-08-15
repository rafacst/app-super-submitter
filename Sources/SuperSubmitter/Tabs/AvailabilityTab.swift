import SubmitKit
import SwiftUI

/// Where the app sells, and for how much.
///
/// It was the top half of the Monetization tab. That put two different
/// questions under one heading: what this app costs and where it is on sale is
/// one of them, and what it sells inside itself is the other. The countries
/// lost the argument every time — the App Store territory picker sat under a
/// price field, on a screen named after the catalogue, and the list of
/// countries the store actually holds was never drawn at all. A developer
/// updating an app that sells in Brazil alone had no screen anywhere in this
/// program that said so.
struct AvailabilityTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
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
                    if state.stores.contains(.google) { googleSection }
                }
                VStack(alignment: .leading, spacing: 14) {
                    priceSection
                    if state.stores.contains(.google) { googleSection }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if state.stores.contains(.apple) { countriesSection }
        }
        .frame(maxWidth: 940, alignment: .leading)
        .onChange(of: state.priceAmount) { _, _ in state.updateBasePrice() }
        .onChange(of: state.priceCurrency) { _, _ in state.updateBasePrice() }
        .onChange(of: state.priceTerritory) { _, _ in
            state.updateBasePrice()
            // The ladder is one country's money, so the territory names which
            // prices the Amount field may offer.
            Task { await state.loadApplePricePoints() }
        }
        .task { await state.loadApplePricePoints() }
        // What the store already charges, for an app that is on it.
        .task { await state.loadStoreMonetization() }
        // And where it charges it. This is the read the tab exists for.
        .task { await state.loadAppleAvailability() }
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
                        tint: Theme.green, anchor: "availability.basePrice",
                        note: apple ? "A price point, not a number." : nil) {
            VStack(alignment: .leading, spacing: 9) {
                FieldRow {
                    LabeledField("Currency", width: 120) {
                        ChoiceField(value: $state.priceCurrency,
                                    choices: StoreValues.currencies,
                                    emptyLabel: "Pick a currency", allowsNone: false)
                    }
                    // The app's own ladder, which carries the free row that a
                    // purchase must not offer. See `MoneyTab.amountField`.
                    LabeledField("Amount") {
                        let points = state.applePricePoints
                        ChoiceField(value: $state.priceAmount, choices: points,
                                    emptyLabel: points.isEmpty
                                        ? "Prices unavailable" : "Pick a price",
                                    allowsNone: false)
                            .disabled(points.isEmpty)
                    }
                }
                LabeledField("Base territory", anchor: "availability.baseTerritory") {
                    ChoiceField(value: $state.priceTerritory,
                                choices: StoreValues.appleTerritories,
                                emptyLabel: "Pick a territory")
                }
                Text("Other territories are converted by the stores.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                // The Google half of this is in the Play column, where the rest
                // of what Play does with the price already lives.
                if !state.stores.contains(.google) {
                    Toggle("Convert the base price for every Google region",
                           isOn: state.autoConvertPricesBinding)
                        .disabled(true)
                }
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
    /// no price point. What it does hold is the conversion and the countries.
    private var googleSection: some View {
        Section_("Google Play", tint: Theme.playGreen, anchor: "availability.google",
                 note: "Micros, per currency.") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Google Play converts the base price for each supported currency.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Convert the base price for every Google region",
                       isOn: state.autoConvertPricesBinding)
                LabeledField("Countries") {
                    Text("Manage country exceptions in Play Console.")
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

    /// The countries, on a panel of their own.
    ///
    /// One control: a tick is a country the app sells in. It reads the store's
    /// own record where `store.yaml` says nothing, so the box opens showing
    /// where the app actually sells rather than an empty list beside a
    /// paragraph naming 175 countries.
    private var countriesSection: some View {
        Section_("App Store countries", icon: "globe", tint: Theme.accent,
                 anchor: "availability.territories") {
            VStack(alignment: .leading, spacing: 10) {
                liveTerritories
                LabeledField("Territories") { TerritoryPicker() }
                if !state.canEditTerritories {
                    Text("Set a base price first. The manifest keeps the territories inside the pricing block, so there is nothing to hang them on until then.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Sell in territories the App Store adds later",
                       isOn: state.appleNewTerritoriesBinding)
                    .disabled(!state.canEditTerritories)
                Text("Apple accepts this option only when it creates availability. For a live app, change it in App Store Connect.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Edit App Store countries ↗",
                     destination: URL(string: "https://appstoreconnect.apple.com/apps")!)
                    .font(Theme.font(size: 12))
            }
            .storePanel()
        }
    }

    /// Where the App Store sells this app today.
    ///
    /// One line, and the box under it holds the countries themselves. It used
    /// to print all 175 names into a paragraph, which is the longest way to
    /// say a number and the shortest way to bury a list.
    @ViewBuilder
    private var liveTerritories: some View {
        if state.actualState.apple?.hasAvailabilityRecord == true {
            let selling = state.liveAppleTerritories.count
            HStack(spacing: 8) {
                StatePill(text: "On the App Store", foreground: Theme.green,
                          background: Theme.greenBg)
                Text("The App Store sells this app in \(Self.countLine(selling)) today")
                    .font(Theme.font(size: 12))
                // The other half of Apple's own summary. The record holds a row
                // per territory whether the app sells there or not, and that
                // row count is what this line used to print as the number of
                // countries: an app on sale in Brazil alone read "175".
                if let held = state.liveAppleTerritoryCount, held > selling {
                    Text("\(held - selling) not available")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
        } else if state.appleActionAppID == nil || !state.hasCredential(for: .apple) {
            Text("Connect the App Store account on the Stores tab to see where this app sells today.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("The App Store holds no availability record for this app yet. The first apply creates one from the territories below.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "1 country", and never "1 countries".
    ///
    /// Counted from the territories the record marks available, and from
    /// nothing else. It used to take the larger of that and `territoryCount`,
    /// which is the number of rows the record holds — every territory Apple
    /// sells in, each carrying a yes or a no. An app available in Brazil alone
    /// therefore reported 175 countries, which is the count of the question
    /// rather than of the answer.
    static func countLine(_ count: Int) -> String {
        if count == 0 { return "no country" }
        return count == 1 ? "1 country" : "\(count) countries"
    }
}

import SubmitKit
import SwiftUI

/// Tab 5. The provider choice first, because it changes the rest of the tab.
struct MoneyTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            providerSection
            priceSection
            availabilitySection
            purchasesSection
            subscriptionsSection
            if state.hasProvider { providerCatalog }
        }
        .frame(maxWidth: 940, alignment: .leading)
    }

    // MARK: - The provider

    private var providerSection: some View {
        Section_("Subscription provider") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(DemoData.providers) { provider in
                        Button {
                            state.provider = provider.key
                        } label: {
                            ProviderCard(provider: provider, selected: state.provider == provider.key)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(provider.name)
                        .accessibilityAddTraits(state.provider == provider.key ? .isSelected : [])
                    }
                }
                if state.provider == .revenuecat { revenueCatPanel }
                if state.provider == .adapty { adaptyPanel }
            }
        }
    }

    private var revenueCatPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 14) {
                FieldBox(label: "Secret v2 API key", value: "sk_••••••••••••••••••7Qk2", width: 240)
                DropdownBox(label: "Project", value: "Fast Bill Split", width: 200)
            }
            HStack(spacing: 6) {
                ForEach(DemoData.revenueCatScopes, id: \.self) { scope in
                    Text(scope)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
            }
            HStack(spacing: 12) {
                Text("● Connected. 5 of 5 scopes present.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.green)
                Text("I have no account yet ↗")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                Text("The key goes to the macOS Keychain.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    /// Adapty holds no secret this app can store, so the panel shows the state
    /// of the command line tool instead of a field.
    private var adaptyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adapty holds no key that this app can store. The adapty command line tool owns its own login.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 9) {
                Text("●").foregroundStyle(Theme.green)
                Text("Logged in as")
                Text("rafa@fastbillsplit.app").font(Theme.mono(12))
            }
            .font(.system(size: 12))
            HStack(spacing: 8) {
                Text("adapty auth login").font(Theme.mono(12))
                Spacer(minLength: 0)
                Text("Copy")
                    .font(.system(size: 11))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: 420)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            Text("This app never runs the login command. A login opens a browser and it belongs to you.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - The price

    /// The resolved price sits next to the request. Money is never applied on
    /// a guess, and this row is where that promise becomes visible.
    private var priceSection: some View {
        Section_("Price") {
            HStack(alignment: .bottom, spacing: 26) {
                FieldBox(label: "Amount", value: "4.99", width: 86)
                FieldBox(label: "Currency", value: "USD", width: 74)
                DropdownBox(label: "Base country", value: "United States", width: 150)
                Rectangle().fill(Theme.sep2).frame(width: 1, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple resolved this price point")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                    Text("USD 4.99 · exact match")
                        .font(.system(size: 12)).foregroundStyle(Theme.green)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Google base region price")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                    Text("USD 4.99").font(.system(size: 12)).foregroundStyle(Theme.green)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    /// The asymmetry is real, and the design shows it instead of hiding it.
    private var availabilitySection: some View {
        Section_("Availability") {
            HStack(alignment: .top, spacing: 14) {
                AvailabilityCard(
                    title: "App Store · 175 countries",
                    line: "This app writes the territory list.",
                    button: "Edit countries")
                AvailabilityCard(
                    title: "Google Play · 171 countries",
                    line: "Read-only. The Android Publisher API does not write the country list.",
                    button: "Open Play Console ↗")
            }
        }
    }

    // MARK: - The catalog

    private var purchasesSection: some View {
        Section_("In-app purchases") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Product id").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Kind").frame(width: 120, alignment: .leading)
                    Text("Name, en-US").frame(width: 170, alignment: .leading)
                    Text("Price").frame(width: 70, alignment: .leading)
                }
                .font(.system(size: 10.5))
                .kerning(0.3)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 15)
                .padding(.vertical, 7)

                HStack(spacing: 12) {
                    Text("com.fastbillsplit.app.pro")
                        .font(Theme.mono(11.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Non-consumable").foregroundStyle(Theme.text2)
                        .frame(width: 120, alignment: .leading)
                    Text("Pro Unlock").frame(width: 170, alignment: .leading)
                    Text("9.99").font(Theme.mono(12)).frame(width: 70, alignment: .leading)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    private var subscriptionsSection: some View {
        Section_("Subscriptions") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("Fast Bill Split Premium").font(.system(size: 12.5, weight: .semibold))
                    Text("group: main").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)

                ForEach(DemoData.plans) { plan in
                    HStack(spacing: 12) {
                        Text(plan.id).font(Theme.mono(11.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(plan.duration).foregroundStyle(Theme.text2)
                            .frame(width: 90, alignment: .leading)
                        Text(plan.basePlan).font(Theme.mono(11.5)).foregroundStyle(Theme.text2)
                            .frame(width: 110, alignment: .leading)
                        Text(plan.name).frame(width: 150, alignment: .leading)
                        Text(plan.price).font(Theme.mono(12)).frame(width: 70, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    /// The vocabulary follows the provider. A developer never learns two.
    private var providerCatalog: some View {
        HStack(alignment: .top, spacing: 14) {
            Section_(state.provider == .adapty ? "Access levels" : "Entitlements") {
                VStack(spacing: 0) {
                    catalogRow(key: "pro", name: "Pro")
                    catalogRow(key: "premium", name: "Premium")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }

            Section_(state.provider == .adapty ? "Paywalls and placements" : "Offerings") {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text("default").font(Theme.mono(11.5))
                        Text("Standard offering").foregroundStyle(Theme.text2)
                        Text("current")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.text2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Text("premium.monthly, premium.yearly")
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }
        }
    }

    private func catalogRow(key: String, name: String) -> some View {
        HStack(spacing: 12) {
            Text(key).font(Theme.mono(11.5))
            Text(name).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - The parts

/// An uppercase section label with its content below.
struct Section_<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text3)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProviderCard: View {
    let provider: DemoProvider
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle()
                    .fill(selected ? Theme.accent : Theme.sep)
                    .frame(width: 15, height: 15)
                    .overlay(Text(selected ? "✓" : "")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
            }
            Text(provider.line)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(selected ? Theme.accent : Theme.sep,
                          lineWidth: selected ? 1.5 : Theme.hairline))
        .contentShape(.rect)
    }
}

private struct FieldBox: View {
    let label: String
    let value: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            Text(value)
                .font(Theme.mono(12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(width: width, alignment: .leading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}

private struct DropdownBox: View {
    let label: String
    let value: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            HStack {
                Text(value).font(.system(size: 12))
                Spacer(minLength: 6)
                Text("▾").font(.system(size: 9)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}

private struct AvailabilityCard: View {
    let title: String
    let line: String
    let button: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(line)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton(title: button)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

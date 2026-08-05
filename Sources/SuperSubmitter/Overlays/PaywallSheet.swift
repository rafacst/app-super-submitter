import SubmitKit
import SwiftUI

/// The one pricing screen. Every gate in the app opens this and no other.
///
/// It says what stays free before it says what costs money, because the free
/// half is most of the app and a developer who does not know that reads the
/// lock as a wall.
struct PaywallSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let trigger: PaywallTrigger

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 15) {
            Text("Paid access")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.15)

            Text(trigger.line)
                .font(.system(size: 12))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            freeCard
            if state.accountEmail == nil {
                HStack {
                    Text("Sign in before choosing a paid plan.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                    Spacer()
                    QuietButton(title: "Sign in or create account") { state.openAccount() }
                }
            }
            plans

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Promotion code", text: $state.promotionCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                        .onSubmit { Task { await state.validatePromotionCode() } }
                    QuietButton(title: "Apply") {
                        Task { await state.validatePromotionCode() }
                    }
                    .disabled(state.promotionCode.isEmpty
                              || state.billingOperation == .validatingCode)
                    if state.billingOperation == .validatingCode { Spinner() }
                    Spacer(minLength: 0)
                }
                if let preview = state.promotionPreview, preview.valid {
                    discount(preview)
                }
                if let message = state.billingMessage {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.yellow)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if state.billingOperation == .confirming { confirming }

            HStack(spacing: 9) {
                if state.accountEmail != nil {
                    QuietButton(title: "Restore access") { Task { await state.restoreAccess() } }
                }
                Spacer()
                Button { dismiss() } label: {
                    Text("Not now")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await state.startCheckout() }
                } label: {
                    Text(state.billingOperation == .openingCheckout
                         ? "Opening checkout…" : "Continue to secure checkout")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(state.billingOperation != .idle || state.accountEmail == nil
                          || state.billingPlans?.plans.first(where: {
                              $0.id == state.selectedPlan
                          })?.available != true)
            }
            .padding(.top, 2)

            Text("Checkout happens on Stripe, in your browser. Super Submitter never sees a card number. Access opens after Stripe confirms the payment, not when the browser returns.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(width: 520)
        .background(Theme.content)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
        .task { await state.loadBillingPlans() }
        .sheet(isPresented: $state.showAccount) { AccountSheet() }
    }

    private var freeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Free · $0")
                .font(.system(size: 12.5, weight: .semibold))
            Text("Manage your apps, write every listing field, add credentials, validate assets, build and archive locally, read both stores, generate a plan, and run a dry run.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let plans = state.billingPlans {
                let available = plans.plans.filter(\.available)
                if available.isEmpty {
                    Text("Paid plans are not available yet. Free features still work.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                } else {
                    ForEach(available) { plan in
                        planRow(plan, currency: plans.currency)
                    }
                }
            } else if state.billingOperation == .loadingPlans {
                HStack(spacing: 8) { Spinner(); Text("Reading the plans…").font(.system(size: 12)) }
            } else {
                Text("The plans could not be loaded. Check your connection and open this again.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            }
        }
    }

    private func planRow(_ plan: BillingPlan, currency: String) -> some View {
        let selected = state.selectedPlan == plan.id
        return Button {
            state.selectPlan(plan.id)
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .strokeBorder(selected ? Theme.accent : Theme.sep, lineWidth: selected ? 5 : 1)
                    .frame(width: 14, height: 14)
                Text(Self.name(plan.id)).font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 8)
                Text(Self.price(plan, currency: currency))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.10) : Theme.raised,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Theme.accent : Theme.sep,
                              lineWidth: selected ? 1 : Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func discount(_ preview: PromotionPreview) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Was \(Self.money(preview.subtotal, preview.currency)) · discount \(Self.money(preview.discount, preview.currency)) · total \(Self.money(preview.total, preview.currency))")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.green)
            if preview.total == 0 {
                Text("Complete checkout to activate access.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
            }
        }
    }

    private var confirming: some View {
        HStack(spacing: 9) {
            Spinner()
            Text("Payment received; still confirming. This screen unlocks by itself.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
    }

    static func name(_ id: String) -> String {
        switch id {
        case "monthly": "Monthly"
        case "annual": "Annual"
        case "lifetime": "Lifetime"
        default: id.capitalized
        }
    }

    static func price(_ plan: BillingPlan, currency: String) -> String {
        let amount = money(plan.amount, currency)
        switch plan.interval {
        case "month": return "\(amount) per month"
        case "year": return "\(amount) per year"
        default: return "\(amount) once"
        }
    }

    /// The server sends the smallest currency unit, the way Stripe does.
    static func money(_ minor: Int, _ currency: String) -> String {
        let value = Decimal(minor) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value) \(currency)"
    }
}

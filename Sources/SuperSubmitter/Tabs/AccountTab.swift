import SubmitKit
import SwiftUI

/// The account, the plan, and the checkout, on one screen.
///
/// It was four rows inside the Settings panel and a pricing sheet on top of
/// them, and the sheet was the only place a price ever appeared. So the answer
/// to "what does this cost" lived behind a modal that opens when something is
/// already blocked, and signing in from there stacked a second modal over the
/// first.
///
/// Everything is on the tab now. The gates that used to present the sheet move
/// you here and write the reason at the top; the plans, the promotion code, and
/// the checkout button are the page; and signing in opens beside them rather
/// than over them, so the plan you are buying stays in view while you do it.
struct AccountTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                if let reason = state.paywallReason { reasonCard(reason) }
                identity
                if !state.accountServiceReady {
                    WarningNote(AppState.noAccountService, width: Self.column)
                }
                capabilities
                if !state.isPaid { plans }
                actions
            }
            .frame(maxWidth: Self.column, alignment: .leading)

            if state.showSignIn {
                SignInPanel()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .animation(.smooth(duration: 0.22), value: state.showSignIn)
        .task { await state.loadBillingPlans() }
    }

    /// One width for the whole column, so every card shares two edges.
    static let column: CGFloat = 620

    private var signedIn: Bool { state.accountEmail != nil }

    // MARK: - Why you are here

    /// What sent you, when a gate did. It is the sentence the sheet used to
    /// open with, and it belongs at the top of the screen it sent you to.
    private func reasonCard(_ reason: PaywallTrigger) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Theme.purple)
                .padding(.top, 1)
            Text(reason.line)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { state.paywallReason = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.purple.opacity(0.35), lineWidth: Theme.hairline))
    }

    // MARK: - Who, and on what

    /// The address and the plan, in one card.
    ///
    /// The plan had a box of its own directly under this one, which made two
    /// cards out of one fact: an account is an address and what that address
    /// has paid for. They are read together and now they sit together.
    private var identity: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: signedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(signedIn ? Theme.accent : Theme.text3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.accountEmail ?? state.entitlement.email ?? "Not signed in")
                        .font(.system(size: 16, weight: .semibold))
                        .textSelection(.enabled)
                    Text(signedIn
                         ? "The same account works on every Mac you use."
                         : "Sign in to carry your plan between Macs. Everything free works without one.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !signedIn, !state.showSignIn {
                    QuietButton(title: "Sign in or create account") { state.openAccount() }
                }
            }

            Hairline()

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: state.isPaid ? "sparkles" : "circle.dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(state.isPaid ? Theme.purple : Theme.text3)
                    .frame(width: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.planLabel)
                        .font(.system(size: 13, weight: .semibold))
                    if !state.entitlementLabel.isEmpty {
                        Text(state.entitlementLabel)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let status = state.statusLabel {
                    StatePill(text: status,
                              foreground: state.isPaid ? Theme.green : Theme.text2,
                              background: state.isPaid ? Theme.greenBg : Theme.sep2)
                }
            }
            if let problem = state.entitlementProblem {
                // Above `billingMessage`, and worded as the fault it is. This
                // is the only state in the app where the plan reads Free and
                // the card may already have been charged.
                WarningNote("This Mac could not confirm your access. \(problem) Your payment is not lost. Press Restore access, and report this if it stays.")
            }
            if let message = state.billingMessage {
                WarningNote(message)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - What it covers

    /// The free half and the paid half, side by side and the same height.
    ///
    /// `equalHeight` is what keeps them level. Two cards of different lengths
    /// in an HStack sit on one top edge and two bottom edges, which reads as
    /// one of them being unfinished.
    private var capabilities: some View {
        HStack(alignment: .top, spacing: 12) {
            column(title: "Free, always", tint: Theme.green,
                   symbol: "checkmark.seal.fill", lines: Self.free)
            column(title: "Paid access", tint: Theme.purple,
                   symbol: "sparkles", lines: Self.paid, locked: !state.isPaid)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    static let free = [
        "Manage every app and write every listing field",
        "Store credentials, asset checks, and validation",
        "Build and archive locally, with the logs",
        "Read both stores and generate the plan",
        "Run a dry run against the real diff",
    ]

    static let paid = [
        "Apply the plan for real, not as a dry run",
        "Upload a build to App Store Connect or Google Play",
        "Send a version to review, and release an approved one",
    ]

    private func column(title: String, tint: Color, symbol: String,
                        lines: [String], locked: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint)
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    // A lock beside a paid line the reader does not have, a
                    // tick beside everything they do. The glyph carries the
                    // state, so the row is never told apart by hue alone.
                    Image(systemName: locked ? "lock.fill" : "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(locked ? Theme.text3 : tint)
                        .frame(width: 11)
                        .padding(.top, 3)
                    Text(line)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Holds the shorter card down to the taller one's height instead
            // of letting it stop early.
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .accessibilityElement(children: .combine)
    }

    // MARK: - What it costs, and buying it

    /// Every plan, the promotion code, and the checkout button.
    ///
    /// This was the pricing sheet. Nothing about it needed to be modal: it
    /// reads a list, takes one choice and one code, and opens a browser.
    private var plans: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plans").font(.system(size: 13, weight: .semibold))

            if let available = state.billingPlans, !available.plans.isEmpty {
                ForEach(available.plans) { plan in
                    planRow(plan, currency: available.currency)
                }
                coupon
                if let blocked = checkoutBlocked { WarningNote(blocked) }
                checkout
            } else if state.billingOperation == .loadingPlans {
                HStack(spacing: 8) {
                    Spinner()
                    Text("Fetching the plans…").font(.system(size: 12))
                }
            } else {
                HStack(spacing: 9) {
                    Text("The plans could not be loaded. Every free feature still works.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    QuietButton(title: "Try again") {
                        Task { await state.loadBillingPlans() }
                    }
                }
            }

            Text("Checkout happens on Stripe, in your browser. Super Submitter never sees a card number. Access opens after Stripe confirms the payment, not when the browser returns.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    /// One plan, chosen by clicking it. A plan that is not on sale says so and
    /// takes no click.
    private func planRow(_ plan: BillingPlan, currency: String) -> some View {
        let selected = state.selectedPlan == plan.id
        let tint = Self.tint(plan.id)
        return Button {
            state.selectPlan(plan.id)
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .strokeBorder(selected ? tint : Theme.sep, lineWidth: selected ? 5 : 1)
                    .frame(width: 14, height: 14)
                Image(systemName: Self.symbol(plan.id))
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(Self.name(plan.id))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selected ? tint : Theme.text)
                if !plan.available {
                    StatePill(text: "Not on sale yet", foreground: Theme.yellow,
                              background: Theme.yellowBg)
                }
                Spacer(minLength: 8)
                Text(Self.price(plan, currency: currency))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(selected ? 0.13 : 0.05),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? tint : Theme.sep,
                              lineWidth: selected ? 1 : Theme.hairline))
            .opacity(plan.available ? 1 : 0.62)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!plan.available)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The discount code, and what it takes off once the service has checked
    /// it. The app never decides a discount itself; it shows what the service
    /// answered.
    @ViewBuilder
    private var coupon: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Discount code", text: $state.promotionCode)
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
            } else if let message = state.promotionMessage {
                // Under the field, not in the identity card most of a screen
                // above it. A refused code used to report itself where the
                // person who typed it was not looking, so Apply read as a
                // button that did nothing.
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func discount(_ preview: PromotionPreview) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill").font(.system(size: 10))
                Text("Was \(Self.money(preview.subtotal, preview.currency)) · discount \(Self.money(preview.discount, preview.currency)) · total \(Self.money(preview.total, preview.currency))")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Theme.green)
            if preview.total == 0 {
                Text("Complete checkout to activate access.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.greenBg, in: RoundedRectangle(cornerRadius: 7))
    }

    private var checkout: some View {
        HStack(spacing: 9) {
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
            .disabled(state.billingOperation != .idle || checkoutBlocked != nil)

            if state.billingOperation == .confirming {
                Spinner()
                Text("Payment received; still confirming. This unlocks by itself.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 0)
        }
    }

    /// Why the checkout button is shut, or nil when it is open. A disabled
    /// button with nothing beside it reads as a broken button.
    private var checkoutBlocked: String? {
        if !signedIn { return "Sign in before you continue to checkout." }
        if state.billingPlans?.plans.first(where: { $0.id == state.selectedPlan })?
            .available != true {
            return "This plan is not on sale yet, so checkout cannot open. Every free feature still works."
        }
        return nil
    }

    // MARK: - The doors

    private var actions: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if state.isPaid {
                    QuietButton(title: "Manage billing") {
                        Task { await state.openBillingPortal() }
                    }
                }
                if signedIn {
                    QuietButton(title: "Restore access") {
                        Task { await state.restoreAccess() }
                    }
                    QuietButton(title: "Sign out") { state.signOutOfBilling() }
                }
                Spacer(minLength: 0)
            }
            Text("Signing out returns Super Submitter to free access. It deletes no app, no store.yaml, no build, and no store key.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - How a plan reads

    /// A hue per plan, so three rows read as three choices and not one list.
    /// They carry no meaning of their own, the way the tab tints do not.
    static func tint(_ id: String) -> Color {
        switch id {
        case "monthly": Theme.accent
        case "annual": Theme.purple
        case "lifetime": Theme.teal
        default: Theme.accent
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "monthly": "calendar"
        case "annual": "calendar.badge.clock"
        case "lifetime": "infinity"
        default: "creditcard"
        }
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

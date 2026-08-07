import SubmitKit
import SwiftUI

/// The account, the plan, and what the plan covers.
///
/// This was four rows inside the Settings panel: an email, one line of status,
/// and three buttons. It sat behind a sheet, under a tab strip, so the screen
/// that answers "what does this cost and what do I get" was the hardest screen
/// in the app to reach, and the only place the prices appeared was a paywall
/// that opens when something is already blocked.
///
/// So the plan comes first and the prices are on the page. A developer who has
/// not paid can read the whole offer here without hitting a lock, and one who
/// has can see what renews and when.
struct AccountTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            identity
            if !state.accountServiceReady {
                WarningNote(AppState.noAccountService, width: Self.column)
            }
            if let message = state.billingMessage {
                WarningNote(message, width: Self.column)
            }
            plan
            capabilities
            if !state.isPaid { offer }
            actions
        }
        .frame(maxWidth: Self.column, alignment: .leading)
        .task { await state.loadBillingPlans() }
    }

    /// One width for the whole column, so every card shares two edges.
    static let column: CGFloat = 620

    // MARK: - Who

    private var signedIn: Bool { state.accountEmail != nil }

    private var identity: some View {
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
            if !signedIn {
                QuietButton(title: "Sign in or create account") { state.openAccount() }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - What you are on

    private var plan: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: state.isPaid ? "sparkles" : "circle.dashed")
                    .font(.system(size: 13))
                    .foregroundStyle(state.isPaid ? Theme.purple : Theme.text3)
                Text(state.planLabel)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                StatePill(text: state.isPaid ? "Active" : "Free",
                          foreground: state.isPaid ? Theme.green : Theme.text2,
                          background: state.isPaid ? Theme.greenBg : Theme.sep2)
            }
            Text(state.entitlementLabel)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state.isPaid ? Theme.greenBg : Theme.raised,
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(state.isPaid ? Theme.green.opacity(0.35) : Theme.sep,
                          lineWidth: Theme.hairline))
    }

    // MARK: - What it covers

    /// The free half and the paid half, side by side.
    ///
    /// The paywall said this in two paragraphs, and only once something was
    /// already blocked. Most of the app is free, and a developer who does not
    /// know that reads the first lock as a wall.
    private var capabilities: some View {
        HStack(alignment: .top, spacing: 12) {
            column(title: "Free, always", tint: Theme.green,
                   symbol: "checkmark.seal.fill", lines: Self.free)
            column(title: "Paid access", tint: Theme.purple,
                   symbol: "sparkles", lines: Self.paid,
                   locked: !state.isPaid)
        }
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .accessibilityElement(children: .combine)
    }

    // MARK: - What it costs

    /// Every plan and its price, read on the page rather than in a sheet.
    ///
    /// It shows for a free account only. A paid account already knows what it
    /// pays, and the row that changes it is "Manage billing".
    private var offer: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Plans")
                .font(.system(size: 13, weight: .semibold))

            if let plans = state.billingPlans, !plans.plans.isEmpty {
                ForEach(plans.plans) { plan in
                    priceRow(plan, currency: plans.currency)
                }
                HStack(spacing: 9) {
                    QuietButton(title: "See plans and check out") {
                        state.openPaywall(.settings)
                    }
                    if !signedIn {
                        Text("Sign in first. Checkout attaches the purchase to your account.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
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

            Text("Checkout happens on Stripe, in your browser. Super Submitter never sees a card number.")
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

    /// One plan, priced. It reads and never selects: the checkout button opens
    /// the paywall, which is the one screen that owns the choice.
    private func priceRow(_ plan: BillingPlan, currency: String) -> some View {
        let tint = PaywallSheet.tint(plan.id)
        return HStack(spacing: 11) {
            Image(systemName: PaywallSheet.symbol(plan.id))
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(PaywallSheet.name(plan.id))
                .font(.system(size: 12.5, weight: .medium))
            if !plan.available {
                StatePill(text: "Not on sale yet", foreground: Theme.yellow,
                          background: Theme.yellowBg)
            }
            Spacer(minLength: 8)
            Text(PaywallSheet.price(plan, currency: currency))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .opacity(plan.available ? 1 : 0.62)
        .accessibilityElement(children: .combine)
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
}

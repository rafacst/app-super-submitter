import AppKit
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
/// you here; the plans, the promotion code, and the checkout button are the
/// page; and signing in is the one panel left, because an account is a machine
/// you use once and the offer is what the screen is for.
///
/// The screen reads top to bottom as one argument: what the app is for, who is
/// signed in, what each plan costs, and the one button that buys it. Nothing
/// here writes an amount of its own. Every price, every interval and the saving
/// on the yearly plan come from the licensing service, so a price change on the
/// server changes this screen and no build is needed.
struct AccountTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                // The offer first, while there is one to make. The tab opened
                // with an account row, then a build warning, then a loader that
                // had failed, and the answer to the one question a developer
                // opens this tab with was the fourth thing on it. Who I am
                // signed in as is the mechanism; what the app does is the
                // reason.
                if !state.isPaid { hero.frame(maxWidth: .infinity) }
                identity
                    .frame(width: state.isPaid ? nil : Self.sideColumn, alignment: .leading)
            }

            if !state.isPaid { plans }

            actions
            trust
        }
        .frame(maxWidth: Self.column, alignment: .leading)
        .task { await state.loadBillingPlans() }
    }

    /// One width for the whole page, so every card shares two edges.
    ///
    /// Wide enough for four plan cards abreast at the window the app opens at,
    /// and capped so the headline keeps its measure on a display twice that
    /// size. Below the cap the cards divide whatever there is, and the plan row
    /// folds to two by two before any card gets too narrow to hold a line.
    static let column: CGFloat = 1180

    /// The right-hand column: the account card, over the indie note below the
    /// plans. Narrow enough that the offer beside it keeps the width its
    /// headline was measured for.
    static let sideColumn: CGFloat = 300

    private var signedIn: Bool { state.accountEmail != nil }

    // MARK: - What the app is for

    /// The headline, the promise under it, and the four things that make the
    /// promise true.
    ///
    /// No price and no name over the headline. The plan cards a few rows down
    /// carry every amount the service offers, so a badge here read the cheapest
    /// of them a second time, and a wordmark over the app's own window names
    /// what the title bar already names.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Ship both stores from one workflow.")
                    .font(Theme.font(size: 24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Prepare App Store and Google Play drafts in one place.")
                    Text("Review every change, then release on your terms.")
                }
                .font(Theme.font(size: 12.5))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Four across, always, and deliberately not a `ViewThatFits`.
            // That view measures the ideal width, and the ideal width of a
            // caption is the caption on one unwrapped line, so it would fold
            // the row to two by two at every window this app can open. The
            // captions are written to wrap.
            //
            // No `fixedSize` on the row. The card reaches the bottom of its
            // own row, and the tiles take whatever height is left over, so the
            // air lands inside the tiles instead of under them.
            HStack(alignment: .top, spacing: 9) { tiles(Self.promises) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // `maxHeight`, so the card reaches the bottom of the row rather than
        // stopping where its own text ends. The account column beside it grows
        // with every warning it has to carry, and a short hero left a band of
        // empty page under itself each time one appeared.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.16),
                                    Theme.purple.opacity(0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(Theme.accent.opacity(0.28), lineWidth: Theme.hairline))
    }

    /// The four things the app promises, in the order the eye reads them: what
    /// you write, what you see, what it refuses to do behind your back, and who
    /// it was built for.
    static let promises: [(title: String, note: String, symbol: String, tint: Color)] = [
        ("Describe once", "One source of truth for both stores.",
         "doc.text.fill", Theme.accent),
        ("Preview every change", "See exactly what will be sent.",
         "eye.fill", Theme.purple),
        ("Drafts first", "Nothing goes live without you.",
         "shield.lefthalf.filled", Theme.pink),
        ("Developer-first", "Built for real shipping workflows.",
         "chevron.left.forwardslash.chevron.right", Theme.teal),
    ]

    private func tiles(_ promises: [(title: String, note: String,
                                     symbol: String, tint: Color)]) -> some View {
        ForEach(promises, id: \.title) { promise in
            // The icon sits above the words and not beside them. Four tiles
            // across this card leave about ninety points inside one, and an
            // icon in the same row took a third of that: "Preview every
            // change" wrapped onto three lines, "Developer-first" broke at
            // its own hyphen, and every tile stretched to the tallest of
            // them. Stacked, each title gets the whole width of its tile.
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: promise.symbol)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(promise.tint)
                    .frame(width: 26, height: 26)
                    .background(promise.tint.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(promise.title)
                        .font(Theme.font(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(promise.note)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Who, and on what

    /// The address and the plan, in one card.
    ///
    /// The plan had a box of its own directly under this one, which made two
    /// cards out of one fact: an account is an address and what that address
    /// has paid for. They are read together and now they sit together.
    private var identity: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: signedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(Theme.font(size: 28, weight: .light))
                    .foregroundStyle(signedIn ? Theme.accent : Theme.text3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.accountEmail ?? state.entitlement.email ?? "Not signed in")
                        .font(Theme.font(size: 15, weight: .semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(signedIn
                         ? "The same account works on every Mac you use."
                         : "Sign in to sync your plan across Macs and unlock applies, uploads, and releases.")
                        .font(Theme.font(size: 12))
                        .foregroundStyle(Theme.text2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !signedIn {
                Button { state.openAccount() } label: {
                    Text("Sign in or create account")
                        .font(Theme.font(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Hairline()

            // Two assurance rows stood here too, on the Keychain and on the
            // drafts, and the bar at the foot of this screen makes both
            // promises at full length. The screen has to stand in one window
            // with no scroll bar, and a sentence printed twice was the cheapest
            // fifty points on it.
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: state.isPaid ? "sparkles" : "circle.dashed")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(state.isPaid ? Theme.purple : Theme.text3)
                    .frame(width: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.planLabel)
                        .font(Theme.font(size: 13, weight: .semibold))
                    if !state.entitlementLabel.isEmpty {
                        Text(state.entitlementLabel)
                            .font(Theme.font(size: 11.5))
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
            if !state.accountServiceReady {
                WarningNote(AppState.noAccountService)
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
        .padding(.vertical, 12)
        // The same bottom edge as the hero beside it. Two cards on one top edge
        // and two different bottom ones read as one of them being unfinished.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - What it costs

    /// The free tier and every plan the service offers, one card each, over the
    /// code request and the checkout.
    ///
    /// Free is drawn here and not fetched, because it is not a thing anybody
    /// buys: it is what the app does with no account at all. Everything beside
    /// it is the server's own list, in the server's own order.
    ///
    /// A `Grid` and not two stacks. The row under the plans is one narrow card
    /// and one wide one, and they have to line up with the plan cards over
    /// them: a hand-set width would agree with a four plan list and drift the
    /// moment the service offers three or five. The top padding is the room the
    /// best-value chip straddles into.
    @ViewBuilder
    private var plans: some View {
        if let available = state.billingPlans, !available.plans.isEmpty {
            let best = Self.bestValue(in: available.plans)
            Grid(alignment: .topLeading, horizontalSpacing: 11, verticalSpacing: 11) {
                GridRow {
                    freeCard
                    paidCards(available, best: best)
                }
                GridRow {
                    indieCard
                    purchase.gridCellColumns(max(1, available.plans.count))
                }
            }
            // The plan cards ask for `maxHeight: .infinity` so a row of them
            // shares one bottom edge. A scroll view proposes an unbounded
            // height, and without this the grid takes it: the window came up
            // with a title bar and no content at all.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 9)
        } else if state.billingOperation == .loadingPlans {
            HStack(spacing: 8) {
                Spinner()
                Text("Fetching the plans…").font(Theme.font(size: 12))
            }
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 9) {
                Text("The plans could not be loaded. Every free feature still works.")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                QuietButton(title: "Try again") {
                    Task { await state.loadBillingPlans() }
                }
            }
            .storePanel()
        }
    }

    private func paidCards(_ available: BillingPlans, best: String?) -> some View {
        let list = available.plans
        return ForEach(list) { plan in
            planCard(id: plan.id, name: Self.name(plan.id),
                     price: Self.money(plan.amount, available.currency),
                     unit: Self.unit(plan), lines: Self.features[plan.id] ?? [],
                     tint: Self.tint(plan.id), symbol: Self.symbol(plan.id),
                     saving: Self.saving(for: plan, in: list),
                     best: plan.id == best, available: plan.available)
        }
    }

    private var freeCard: some View {
        planCard(id: nil, name: "Free", price: nil, unit: "Always free",
                 lines: Self.free, tint: Theme.green, symbol: "doc.text.fill")
    }

    /// One plan, chosen by clicking it. A plan that is not on sale says so and
    /// takes no click. The free card takes no click either: it is not for sale.
    @ViewBuilder
    private func planCard(id: String?, name: String, price: String?, unit: String,
                          lines: [String], tint: Color, symbol: String,
                          saving: Int? = nil, best: Bool = false,
                          available: Bool = true) -> some View {
        let selected = id != nil && state.selectedPlan == id
        let card = VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(Theme.font(size: 14))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(Theme.font(size: 14, weight: .semibold))
                    if let price {
                        Text(price)
                            .font(Theme.font(size: 18, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(unit)
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 0)
            }

            if let saving {
                StatePill(text: "Save \(saving)%", foreground: Theme.purple,
                          background: Theme.purple.opacity(0.14))
            }
            if !available {
                StatePill(text: "Not on sale yet", foreground: Theme.yellow,
                          background: Theme.yellowBg)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "checkmark")
                            .font(Theme.font(size: 9, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 11)
                            .padding(.top, 3)
                        Text(line)
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(selected ? tint.opacity(0.10) : Theme.raised,
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(selected ? tint : Theme.sep,
                          lineWidth: selected ? 1.6 : Theme.hairline))
        .opacity(available ? 1 : 0.62)
        // The badge straddles the top edge, which is what the row's own top
        // padding leaves room for.
        .overlay(alignment: .top) { if best { bestValueChip.offset(y: -8) } }

        if let id, available {
            Button { state.selectPlan(id) } label: { card.contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        } else {
            card
        }
    }

    private var bestValueChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").font(Theme.font(size: 8))
            Text("BEST VALUE")
                .font(Theme.font(size: 9, weight: .semibold))
                .kerning(0.6)
        }
        .foregroundStyle(Theme.accentText)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Theme.purpleFill, in: Capsule())
    }

    /// What costs nothing, and what each plan adds on top of the one before it.
    ///
    /// These are the plan cards' own lines and they have to stay true against
    /// `AppState.entitlementLabel`, which makes the same promise in one
    /// sentence. Editing, reading, building and dry runs are free; the three
    /// capabilities in `AccessCapability` are what a plan opens.
    /// The last line was two, and the first of them promised the applies and
    /// the uploads that the card beside it charges for. One row of this screen
    /// gave a write away and sold it at the same time. A free account runs
    /// every write dry and sends none of them, which is one line.
    static let free = [
        "Editing & validation",
        "Builds & reads",
        "Unlimited drafts",
        "Dry runs of every write",
    ]

    static let features: [String: [String]] = [
        // A line about store reads without limit stood here, and reads are
        // free, so it sold what the free card beside it already gives away.
        "monthly": [
            "Everything in Free",
            "Apply, upload and release",
            "Cancel anytime",
        ],
        // A line promising a faster answer from support stood here, and
        // nothing answers for it: there is one address and one queue.
        "annual": [
            "Everything in Monthly",
            "Lower yearly cost",
            "Best for teams shipping often",
        ],
        "lifetime": [
            "Everything in Annual",
            "Own payment, forever",
            "Lifetime updates",
            "Great for long-term tools",
        ],
    ]

    // MARK: - Asking for a code

    /// For the developer the price is actually in the way of.
    ///
    /// The card is the asking. It says to ask and it opens the mail, so the
    /// sentence has somewhere to go rather than naming an action with nothing
    /// to press.
    private var indieCard: some View {
        Button { NSWorkspace.shared.open(Self.askForACodeURL) } label: {
            HStack(spacing: 11) {
                Image(systemName: "gift.fill")
                    .font(Theme.font(size: 17))
                    .foregroundStyle(Theme.pink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Indie developer?")
                        .font(Theme.font(size: 13, weight: .semibold))
                    Text("Ask for a code.")
                        .font(Theme.font(size: 12.5))
                }
                .foregroundStyle(Theme.pink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            // Fills its cell. It is one short card beside a wide one, and the
            // page under it was the only hole left on the screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Theme.pink.opacity(0.32), lineWidth: Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Indie developer? Ask for a code.")
        .accessibilityHint("Opens a mail to support")
    }

    /// A mail to the same address the About panel uses, with the subject
    /// already written.
    static var askForACodeURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AboutPanel.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Super Submitter: asking for a code"),
        ]
        return components.url ?? URL(string: "mailto:\(AboutPanel.supportEmail)")!
    }

    // MARK: - Buying it

    /// The promotion code and the checkout button, on one row.
    ///
    /// This was the pricing sheet. Nothing about it needed to be modal: it
    /// reads a list, takes one choice and one code, and opens a browser.
    private var purchase: some View {
        HStack(alignment: .top, spacing: 16) {
            coupon.frame(maxWidth: .infinity, alignment: .leading)
            // The bar at the foot of the screen carries the Stripe sentence at
            // full length, so the button stands on its own here.
            checkout.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    /// The discount code, and what it takes off once the service has checked
    /// it. The app never decides a discount itself; it shows what the service
    /// answered.
    @ViewBuilder
    private var coupon: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 8) {
            Text("Discount code")
                .font(Theme.font(size: 12.5, weight: .semibold))
            HStack(spacing: 8) {
                TextField("Enter code", text: $state.promotionCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 210)
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
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func discount(_ preview: PromotionPreview) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill").font(Theme.font(size: 10))
                Text("Was \(Self.money(preview.subtotal, preview.currency)) · discount \(Self.money(preview.discount, preview.currency)) · total \(Self.money(preview.total, preview.currency))")
                    .font(Theme.font(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Theme.green)
            if preview.total == 0 {
                Text("Complete checkout to activate access.")
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.text2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.greenBg, in: RoundedRectangle(cornerRadius: 7))
    }

    private var checkout: some View {
        VStack(spacing: 7) {
            Button {
                Task { await state.startCheckout() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(Theme.font(size: 12, weight: .semibold))
                    Text(state.billingOperation == .openingCheckout
                         ? "Opening checkout…" : "Continue to secure checkout")
                        .font(Theme.font(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(Theme.accentText)
                .padding(.vertical, 11)
                // The height comes before the fill, so the gradient and the
                // click land on the same rectangle. Stretching the frame after
                // the background left the pill its own size inside a taller
                // hit area, and the empty page under the button opened a
                // checkout.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(colors: [Theme.accentFill, Theme.purpleFill],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 9))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(state.billingOperation != .idle || checkoutBlocked != nil)
            .opacity(state.billingOperation != .idle || checkoutBlocked != nil ? 0.55 : 1)
            // The reason the button is shut, where it costs no height. It had a
            // line of its own under the button and said what the card beside it
            // already says: sign in, and here is the button that does it.
            .help(checkoutBlocked ?? "")

            if state.billingOperation == .confirming {
                HStack(spacing: 8) {
                    Spinner()
                    Text("Payment received; still confirming. This unlocks by itself.")
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Why the checkout button is shut, or nil when it is open. It reaches the
    /// reader as the button's own tooltip.
    private var checkoutBlocked: String? {
        if !signedIn { return "Sign in before you continue to checkout." }
        if state.billingPlans?.plans.first(where: { $0.id == state.selectedPlan })?
            .available != true {
            return "This plan is not on sale yet, so checkout cannot open. Every free feature still works."
        }
        return nil
    }

    // MARK: - The doors

    /// Manage billing, restore, sign out. The block draws nothing at all for an
    /// account that has none of them, rather than explaining a sign out to
    /// somebody who is not signed in.
    @ViewBuilder
    private var actions: some View {
        if signedIn || state.isPaid {
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
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The three things a developer weighing this app wants settled before they
    /// hand over a card and a set of store keys.
    private var trust: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(Self.assurances.enumerated()), id: \.element.title) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.sep)
                        .frame(width: Theme.hairline)
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, 14)
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(Theme.font(size: 16))
                        .foregroundStyle(item.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(Theme.font(size: 12.5, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.note)
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    static let assurances: [(title: String, note: String,
                             symbol: String, tint: Color)] = [
        ("Secure checkout by Stripe", "Your card details are never seen by us.",
         "lock.shield.fill", Theme.accent),
        ("Keys stay in Keychain", "We never store or access your keys.",
         "key.fill", Theme.purple),
        ("Nothing goes live without you", "You review and release on your terms.",
         "checkmark.shield.fill", Theme.accent),
    ]

    // MARK: - How a plan reads

    /// A hue per plan, so three cards read as three choices and not one list.
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

    /// What is under the amount on a plan card.
    static func unit(_ plan: BillingPlan) -> String {
        switch plan.interval {
        case "month": "per month"
        case "year": "per year"
        default: "once"
        }
    }

    /// What a yearly plan takes off twelve months of the monthly one, as a
    /// whole percentage, or nil where there is nothing to take off.
    ///
    /// Both amounts are the server's. A percentage written into the app would
    /// go on claiming itself the day a price changes, and the claim would be
    /// on the screen that asks for money.
    static func saving(for plan: BillingPlan, in plans: [BillingPlan]) -> Int? {
        guard plan.available, plan.interval == "year",
              let monthly = plans.first(where: { $0.interval == "month" && $0.available })
        else { return nil }
        let year = monthly.amount * 12
        guard year > plan.amount else { return nil }
        return Int((Double(year - plan.amount) / Double(year) * 100).rounded())
    }

    /// The plan that saves the most, or nil where nothing saves anything. A
    /// badge with no arithmetic behind it is decoration.
    static func bestValue(in plans: [BillingPlan]) -> String? {
        plans.compactMap { plan in saving(for: plan, in: plans).map { (plan.id, $0) } }
            .max { $0.1 < $1.1 }?.0
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

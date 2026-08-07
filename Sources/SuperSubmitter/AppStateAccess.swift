import AppKit
import Foundation
import PostHog
import SubmitKit

/// Why the pricing sheet opened. It picks the one line at the top of the
/// sheet, so the developer reads what they were doing and not a price list.
enum PaywallTrigger: String, Identifiable {
    case apply, upload, release, marketing, settings, expired

    var id: String { rawValue }

    var line: String {
        switch self {
        case .apply:
            "Store writes need paid access. Your plan is kept, and reading the stores and running a dry run stay free."
        case .upload:
            "Your build is ready. Subscribe or apply a promotion code to upload it. The archive is kept either way."
        case .release:
            "Releasing to review needs paid access. Your draft stays exactly as it is."
        case .marketing:
            "Writing these marketing resources to App Store Connect needs paid access."
        case .settings:
            "Super Submitter is free to configure, validate, build, read, and plan. Paid access adds every store write."
        case .expired:
            "Your paid access has ended. Every local edit, plan, and dry run still works."
        }
    }
}

enum BillingOperation: Equatable {
    case idle, loadingPlans, validatingCode, openingCheckout, confirming
}

/// The billing screen state and the one place that answers "may this write".
///
/// Nothing else in the app compares a plan name. A view asks `can(_:)` to draw
/// a lock, and the write boundary in SubmitKit asks the controller again.
@MainActor
extension AppState {

    /// Builds the controller and loads the document the last session left.
    ///
    /// Supabase owns the account session. The licensing service receives only
    /// its short-lived access token.
    func configureAccess() {
        guard let auth = LicensingConfig.auth.map({ SupabaseAuth(configuration: $0) }) else { return }
        authController = auth
        // The account works without the licensing half. Only the entitlement
        // does not, and a build with no licensing service stays on free access.
        let controller = LicensingConfig.current.map { config in
            AccessController(
                client: HTTPLicensingClient(base: config.baseURL),
                verifier: config.verifier,
                store: KeychainEntitlementStore(),
                token: { try await auth.accessToken() })
        }
        accessController = controller
        if let controller { access = controller }
        Task {
            accountEmail = await auth.email
            await controller?.loadCachedDocument()
            if let controller { entitlement = await controller.current }
            await refreshEntitlement()
        }
    }

    /// Whether this build can reach an account service at all.
    var accountServiceReady: Bool { authController != nil }

    func openAccount() {
        accountEmailInput = accountEmail ?? ""
        accountPassword = ""
        accountMessage = accountServiceReady ? nil : Self.noAccountService
        showSignIn = true
    }

    static let noAccountService =
        "This build carries no account service address, so it cannot sign in. Build it with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY."

    func submitAccount() async {
        // One call at a time. The Return key and the button both land here,
        // and Supabase answers a second signup for the same address by sending
        // the confirmation email again, so a double fire is two emails.
        guard !accountBusy else { return }
        let email = accountEmailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !accountPassword.isEmpty else { return }
        // A missing controller used to return here in silence, and the button
        // then looked broken. Say why instead.
        guard let auth = authController else {
            accountMessage = Self.noAccountService
            return
        }
        accountBusy = true
        accountMessage = nil
        defer { accountBusy = false }
        do {
            if accountCreating {
                switch try await auth.signUp(email: email, password: accountPassword) {
                case .signedIn(let email):
                    accountEmail = email
                case .confirmationRequired:
                    accountMessage = "Check your email to confirm the account, then sign in."
                    accountCreating = false
                    accountPassword = ""
                    return
                }
            } else {
                accountEmail = try await auth.signIn(email: email, password: accountPassword)
            }
            accessController?.forgetLater()
            entitlement = .free(at: Date())
            await refreshEntitlement()
            accountPassword = ""
            showSignIn = false
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    /// Signs in through an identity provider.
    ///
    /// The password is typed into the provider's own page, so this app never
    /// sees one. Everything after the callback is the same path the email
    /// form takes, so a session from either door behaves alike.
    func signIn(with provider: SupabaseOAuthProvider) async {
        guard let auth = authController else {
            accountMessage = Self.noAccountService
            return
        }
        accountBusy = true
        accountMessage = nil
        defer { accountBusy = false }
        let request = auth.authorization(with: provider, redirectTo: OAuthSession.callback)
        do {
            // A closed window is a choice, not a failure. Say nothing.
            guard let callback = try await OAuthSession().run(request.url) else { return }
            accountEmail = try await auth.completeOAuth(callback: callback,
                                                        verifier: request.verifier)
            accessController?.forgetLater()
            entitlement = .free(at: Date())
            await refreshEntitlement()
            accountPassword = ""
            showSignIn = false
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    /// The link in the confirmation email.
    ///
    /// macOS launches the app with the redirect, because `store.yaml` is not
    /// the only thing the scheme is registered for. Without this the app came
    /// forward and did nothing, and the account stayed unconfirmed.
    ///
    /// A URL that carries no session is the return from Stripe Checkout. It
    /// grants nothing on its own, and `didBecomeActive` already asks the
    /// server, so this leaves it alone.
    func handle(callback url: URL) {
        let parts = SupabaseAuth.parameters(in: url)
        let carriesSession = parts["refresh_token"] != nil
            || parts["error_description"] != nil || parts["error"] != nil
        guard carriesSession, let auth = authController else { return }
        Task {
            accountBusy = true
            defer { accountBusy = false }
            do {
                accountEmail = try await auth.adopt(callback: url)
                accessController?.forgetLater()
                entitlement = .free(at: Date())
                await refreshEntitlement()
                accountMessage = nil
                showSignIn = false
                errorMessage = "Your email address is confirmed. You are signed in as \(accountEmail ?? "")."
            } catch {
                accountMessage = error.localizedDescription
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The read a view uses to draw a lock. It never authorizes a write: the
    /// boundary in SubmitKit asks the controller, which refreshes first.
    func can(_ capability: AccessCapability) -> Bool {
        guard accessController != nil else {
            // No configuration. The Debug build allows and says so on stderr;
            // the Release build refuses at the boundary.
#if DEBUG
            return true
#else
            return false
#endif
        }
        return entitlement.grants(capability)
    }

    var isPaid: Bool { can(.storeWrite) }

    /// The gate a button calls. It returns false and opens the pricing sheet,
    /// so the caller stops without inventing its own message.
    @discardableResult
    func requirePaid(_ capability: AccessCapability, _ trigger: PaywallTrigger) -> Bool {
        guard !can(capability) else { return true }
        PostHogSDK.shared.capture("paywall_gate_hit", properties: [
            "capability": capability.rawValue,
            "trigger": trigger.rawValue
        ])
        openPaywall(trigger)
        return false
    }

    /// Takes the developer to the one screen that sells, and says what sent
    /// them.
    ///
    /// It was a sheet, and a sheet is why this needed a queue: the shell hosts
    /// one at a time, Settings is one, so asking from inside Settings set a
    /// trigger, presented nothing, and "See plans" looked dead. It closed
    /// Settings and waited for the dismissal callback to open the real thing.
    ///
    /// The Account tab is part of the window, so none of that is left. It is
    /// reachable from anywhere, including with no app linked, and it carries
    /// the plans, the promotion code, and the checkout button itself. A gate
    /// now moves you to it and writes the reason at the top.
    func openPaywall(_ trigger: PaywallTrigger) {
        billingMessage = nil
        PostHogSDK.shared.capture("paywall_shown", properties: ["trigger": trigger.rawValue])
        paywallReason = trigger
        showSettings = false
        selectedTab = .account
        Task { await loadBillingPlans() }
    }

    // MARK: - The service

    func refreshEntitlement() async {
        guard let controller = accessController else { return }
        // A failed refresh keeps the unexpired document, so the service being
        // down for an hour does not stop a paying developer mid-release.
        do {
            entitlement = try await controller.refresh()
            entitlementProblem = nil
        } catch {
            entitlement = await controller.current
            note(error)
        }
    }

    /// Records a refresh failure that the developer has to see.
    ///
    /// The whole `catch` used to be `try?`. A document this build cannot verify
    /// then looked exactly like an account that has not paid: the tab said
    /// "Free" and gave no reason, on a Mac whose card had already been charged.
    /// Being offline and being signed out are ordinary and stay quiet; a
    /// signature, a key, a subject, or a clock is this build failing to read a
    /// real answer, and it is said out loud with its code so it is reportable.
    private func note(_ error: any Error) {
        guard let access = error as? AccessError, access.isVerificationFailure else {
            entitlementProblem = nil
            return
        }
        entitlementProblem = "\(access.errorDescription ?? "Your access could not be confirmed.") (\(access.code))"
    }

    func loadBillingPlans() async {
        guard let config = LicensingConfig.current,
              billingOperation != .loadingPlans else { return }
        billingOperation = .loadingPlans
        defer { billingOperation = .idle }
        billingPlans = try? await HTTPLicensingClient(base: config.baseURL).plans()
        if billingPlans == nil {
            billingMessage = "The plans could not be loaded. Check your connection and try again."
        }
        // A selection nobody can buy sends the developer to a shut checkout
        // for no reason. Move to a plan that is on sale, when one is.
        if let plans = billingPlans,
           plans.plans.first(where: { $0.id == selectedPlan })?.available != true,
           let open = plans.plans.first(where: \.available) {
            selectedPlan = open.id
        }
    }

    /// The typed code, trimmed, or nil when the field holds nothing.
    ///
    /// One reading of the field for the validate call, the checkout call, and
    /// the idempotency key. A field of spaces used to pass the `isEmpty` test
    /// and send an empty code to the server.
    var trimmedPromotionCode: String? {
        let code = promotionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }

    /// Asks the server what the code is worth for the selected plan. A local
    /// check would be a guess: Stripe holds every restriction.
    func validatePromotionCode() async {
        promotionMessage = nil
        guard let code = trimmedPromotionCode else { promotionPreview = nil; return }
        guard let config = LicensingConfig.current else {
            promotionMessage = AccessError.licensingNotConfigured.errorDescription
            return
        }
        // Two different failures wrote one sentence. A missing service address
        // is a build fault, and a missing token means signed out, and the field
        // reported "signed out" for both.
        guard let bearer = try? await accountToken(), !bearer.isEmpty else {
            promotionMessage = AccessError.signedOut.errorDescription
            return
        }
        billingOperation = .validatingCode
        billingMessage = nil
        defer { billingOperation = .idle }
        do {
            promotionPreview = try await HTTPLicensingClient(base: config.baseURL)
                .validate(promotionCode: code, plan: selectedPlan, idToken: bearer)
            if promotionPreview?.valid == false {
                promotionMessage = promotionPreview?.message
                    ?? "This code is not valid for the \(Self.name(selectedPlan)) plan."
            }
        } catch {
            promotionPreview = nil
            // The service's own words when it gave any, because it is the only
            // party that knows why. `malformedEntitlement` is the exception: it
            // is this client failing to read the answer, and its sentence talks
            // about signing in again, which is not the fault and not the fix.
            promotionMessage = switch error as? AccessError {
            case .malformedEntitlement:
                "The service answered in a form this build did not understand. Report it as a bug."
            case .some(let known): known.errorDescription
            case nil: error.localizedDescription
            }
        }
    }

    /// The plan name a person reads. `AccountTab` holds the same map for its
    /// rows, and this is the message half.
    static func name(_ plan: String) -> String {
        switch plan {
        case "monthly": "monthly"
        case "annual": "annual"
        case "lifetime": "lifetime"
        default: plan
        }
    }

    /// A plan change invalidates a preview. Showing a discount for the plan
    /// the user just left is the one thing this screen must not do.
    func selectPlan(_ plan: String) {
        guard plan != selectedPlan else { return }
        selectedPlan = plan
        promotionPreview = nil
        promotionMessage = nil
        billingMessage = nil
    }

    /// Opens Stripe-hosted Checkout in the default browser, then waits for the
    /// server. The browser return grants nothing.
    func startCheckout() async {
        guard let config = LicensingConfig.current,
              let bearer = try? await accountToken() else {
            billingMessage = AccessError.signedOut.errorDescription
            return
        }
        billingOperation = .openingCheckout
        billingMessage = nil
        do {
            let session = try await HTTPLicensingClient(base: config.baseURL).checkout(
                plan: selectedPlan,
                promotionCode: trimmedPromotionCode,
                idempotencyKey: checkoutIdempotencyKey(),
                idToken: bearer)
            PostHogSDK.shared.capture("checkout_opened", properties: ["plan": selectedPlan])
            // A browser that refuses the address is the one failure this
            // screen used to swallow: the button worked, nothing opened, and
            // the sheet said nothing. Hand over the address instead.
            guard NSWorkspace.shared.open(session.url) else {
                billingOperation = .idle
                billingMessage = "The browser did not open. Finish the checkout at \(session.url.absoluteString)"
                return
            }
            await waitForEntitlement()
        } catch {
            billingOperation = .idle
            billingMessage = (error as? AccessError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Where the key of one plan and one promotion code is remembered.
    ///
    /// The promotion code belongs in here. The plan alone was the bug: the
    /// server returns the same unexpired session for a repeated key, which is
    /// the whole point of the key, so the first Subscribe pinned the plan. A
    /// customer who pressed Subscribe, closed the browser, came back, typed a
    /// code, and pressed Subscribe again reached the first session and paid
    /// the full price. The code changes the request, so it changes the key.
    ///
    /// Upper case because Stripe matches a code either way, and two keys for
    /// one code would mint a second session for the same discount.
    func checkoutDefaultsKey() -> String {
        let code = trimmedPromotionCode?.uppercased() ?? ""
        return "checkoutKey.\(selectedPlan).\(code)"
    }

    /// One key per user, plan, and promotion code, so pressing the button
    /// twice returns the same unexpired Checkout Session instead of a second
    /// one.
    func checkoutIdempotencyKey() -> String {
        let key = checkoutDefaultsKey()
        if let existing = defaults.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }

    /// Polls the service with a bounded backoff. Access changes only when the
    /// server returns an active entitlement, never on a redirect.
    func waitForEntitlement() async {
        guard let controller = accessController else { return }
        billingOperation = .confirming
        for delay in [2, 3, 5, 8, 12, 15, 15] {
            try? await Task.sleep(for: .seconds(delay))
            do {
                let fresh = try await controller.refresh()
                entitlement = fresh
                entitlementProblem = nil
                if fresh.isPaid {
                    billingOperation = .idle
                    billingMessage = nil
                    paywallReason = nil
                    defaults.removeObject(forKey: checkoutDefaultsKey())
                    PostHogSDK.shared.capture("checkout_confirmed",
                                              properties: ["plan": selectedPlan])
                    return
                }
            } catch {
                note(error)
                // A key or a signature does not come right on the next poll,
                // and sixty seconds of "still confirming" after a real payment
                // is the worst way to say so. Stop and report it.
                if entitlementProblem != nil {
                    billingOperation = .idle
                    billingMessage = nil
                    return
                }
            }
        }
        billingOperation = .idle
        billingMessage = "Stripe took the payment and this account is still not entitled. Press Restore access, and report it if that does not open it."
    }

    /// Reconciles the account against Stripe on the server and returns the
    /// effective entitlement. This is how a second Mac gets access.
    func restoreAccess() async {
        guard let config = LicensingConfig.current, let controller = accessController,
              let bearer = try? await accountToken() else {
            billingMessage = AccessError.signedOut.errorDescription
            return
        }
        billingOperation = .confirming
        defer { billingOperation = .idle }
        do {
            _ = try await HTTPLicensingClient(base: config.baseURL).restore(idToken: bearer)
            entitlement = try await controller.refresh()
            billingMessage = entitlement.isPaid ? nil : "No paid access was found for this account."
            if entitlement.isPaid {
                paywallReason = nil
                PostHogSDK.shared.capture("entitlement_restored")
            }
        } catch {
            billingMessage = (error as? AccessError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The Stripe Customer Portal: payment method, invoices, cancellation.
    func openBillingPortal() async {
        guard let config = LicensingConfig.current,
              let bearer = try? await accountToken() else {
            billingMessage = AccessError.signedOut.errorDescription
            return
        }
        do {
            let session = try await HTTPLicensingClient(base: config.baseURL).portal(idToken: bearer)
            NSWorkspace.shared.open(session.url)
        } catch {
            billingMessage = (error as? AccessError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Signing out removes the tokens and the cached document and returns the
    /// app to free access. It deletes no project, no manifest, no build, and
    /// no store credential.
    func signOutOfBilling() {
        Task {
            await authController?.signOut()
            accessController?.forgetLater()
            entitlement = .free(at: Date())
            accountEmail = nil
            promotionPreview = nil
            promotionCode = ""
            billingMessage = nil
        }
    }

    /// The token of the signed-in account, through the controller's provider.
    ///
    private func accountToken() async throws -> String? {
        guard accessController != nil else { return nil }
        return try await accessController?.currentToken()
    }

    // MARK: - What Settings shows

    var planLabel: String {
        switch entitlement.plan {
        case .free: "Free"
        case .monthly: "Monthly"
        case .annual: "Annual"
        case .lifetime: "Lifetime"
        case .complimentary: "Complimentary"
        }
    }

    var entitlementLabel: String {
        switch entitlement.status {
        case .free:
            return "No paid access. Editing, validation, builds, reads, plans, and dry runs are free."
        case .active:
            if entitlement.cancelAtPeriodEnd == true, let end = entitlement.currentPeriodEnd {
                return "Active until \(end.formatted(date: .abbreviated, time: .omitted)). It does not renew."
            }
            if let end = entitlement.currentPeriodEnd, entitlement.plan != .lifetime {
                return "Active. It renews on \(end.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Active."
        case .grace:
            return "A payment did not go through. Access continues for now. Update the payment method."
        case .expired:
            return "Ended. Every local edit, plan, and dry run still works."
        case .revoked:
            return "Withdrawn after a refund or a dispute."
        }
    }
}

extension AccessController {
    /// A fire-and-forget clear, for a caller on the main actor that has
    /// nothing to wait for.
    nonisolated func forgetLater() {
        Task { await self.forget() }
    }
}

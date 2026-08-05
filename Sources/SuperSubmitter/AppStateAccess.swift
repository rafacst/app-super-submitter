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
        showAccount = true
    }

    static let noAccountService =
        "This build carries no account service address, so it cannot sign in. Build it with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY."

    func submitAccount() async {
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
            showAccount = false
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
            showAccount = false
        } catch {
            accountMessage = error.localizedDescription
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

    func openPaywall(_ trigger: PaywallTrigger) {
        billingMessage = nil
        paywall = trigger
        PostHogSDK.shared.capture("paywall_shown", properties: ["trigger": trigger.rawValue])
        Task { await loadBillingPlans() }
    }

    // MARK: - The service

    func refreshEntitlement() async {
        guard let controller = accessController else { return }
        // A failed refresh keeps the unexpired document, so the service being
        // down for an hour does not stop a paying developer mid-release.
        if let fresh = try? await controller.refresh() {
            entitlement = fresh
        } else {
            entitlement = await controller.current
        }
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
    }

    /// Asks the server what the code is worth for the selected plan. A local
    /// check would be a guess: Stripe holds every restriction.
    func validatePromotionCode() async {
        let code = promotionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { promotionPreview = nil; return }
        guard let config = LicensingConfig.current,
              let bearer = try? await accountToken() else {
            billingMessage = AccessError.signedOut.errorDescription
            return
        }
        billingOperation = .validatingCode
        billingMessage = nil
        defer { billingOperation = .idle }
        do {
            promotionPreview = try await HTTPLicensingClient(base: config.baseURL)
                .validate(promotionCode: code, plan: selectedPlan, idToken: bearer)
            if promotionPreview?.valid == false {
                billingMessage = "This code is invalid, expired, or not available for the selected plan."
            }
        } catch {
            promotionPreview = nil
            billingMessage = (error as? AccessError)?.errorDescription
                ?? "This code is invalid, expired, or not available for the selected plan."
        }
    }

    /// A plan change invalidates a preview. Showing a discount for the plan
    /// the user just left is the one thing this screen must not do.
    func selectPlan(_ plan: String) {
        guard plan != selectedPlan else { return }
        selectedPlan = plan
        promotionPreview = nil
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
                promotionCode: promotionCode.isEmpty ? nil : promotionCode,
                idempotencyKey: checkoutIdempotencyKey(),
                idToken: bearer)
            PostHogSDK.shared.capture("checkout_opened", properties: ["plan": selectedPlan])
            NSWorkspace.shared.open(session.url)
            await waitForEntitlement()
        } catch {
            billingOperation = .idle
            billingMessage = (error as? AccessError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// One key per user and plan, so pressing the button twice returns the
    /// same unexpired Checkout Session instead of a second one.
    private func checkoutIdempotencyKey() -> String {
        let key = "checkoutKey.\(selectedPlan)"
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
            if let fresh = try? await controller.refresh() {
                entitlement = fresh
                if fresh.isPaid {
                    billingOperation = .idle
                    billingMessage = nil
                    paywall = nil
                    defaults.removeObject(forKey: "checkoutKey.\(selectedPlan)")
                    PostHogSDK.shared.capture("checkout_confirmed",
                                              properties: ["plan": selectedPlan])
                    return
                }
            }
        }
        billingOperation = .idle
        billingMessage = "Payment received; still confirming. Press Check again in a moment."
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
                paywall = nil
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

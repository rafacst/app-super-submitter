import SubmitKit
import SwiftUI

/// Sign in, or create an account, beside the Account tab.
///
/// It was a sheet, and the paywall presented one too, so signing in on the way
/// to a purchase put two modal layers between the developer and the plan they
/// were trying to buy. Each layer hid the thing the layer under it was about.
///
/// A panel on the right instead. The plan, the price, and the reason you were
/// sent here all stay on screen while you sign in, which is the whole point of
/// signing in at that moment.
struct SignInPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Text(state.accountCreating ? "Create account" : "Sign in")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Button { state.showSignIn = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close sign in")
            }

            Text("Use the same account on every Mac. Your purchase is attached to it.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Above the fields, not below them. macOS draws its password
            // autofill suggestion right under the password field, and it
            // covered the one line that says why the sign-in failed.
            if let message = state.accountMessage {
                WarningNote(message)
            }
            if !state.accountServiceReady {
                WarningNote(AppState.noAccountService)
            }

            providers

            HStack(spacing: 9) {
                Hairline()
                Text("or").font(.system(size: 11)).foregroundStyle(Theme.text3)
                Hairline()
            }

            TextField("Email", text: $state.accountEmailInput)
                .textContentType(.emailAddress)
            SecureField("Password", text: $state.accountPassword)
                .textContentType(state.accountCreating ? .newPassword : .password)
                .onSubmit { Task { await state.submitAccount() } }

            Button(state.accountCreating ? "Create account" : "Sign in") {
                Task { await state.submitAccount() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(state.accountBusy || !state.accountServiceReady
                      || state.accountEmailInput
                          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || state.accountPassword.isEmpty)

            HStack(spacing: 8) {
                Button(state.accountCreating
                       ? "I already have an account" : "Create an account") {
                    state.accountCreating.toggle()
                    state.accountMessage = nil
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5))
                Spacer(minLength: 0)
                if state.accountBusy { Spinner() }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    /// The identity providers, one to a row.
    ///
    /// They sit above the email form, because a developer who already has one
    /// of these accounts is one click from done and never needs the form.
    private var providers: some View {
        VStack(spacing: 7) {
            ForEach(SupabaseOAuthProvider.allCases) { provider in
                Button {
                    Task { await state.signIn(with: provider) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: provider.symbol)
                            .font(.system(size: 12))
                        Text("Continue with \(provider.title)")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(state.accountBusy || !state.accountServiceReady)
                .accessibilityLabel("Continue with \(provider.title)")
            }
        }
    }
}

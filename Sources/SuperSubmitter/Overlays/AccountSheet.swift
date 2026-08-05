import SubmitKit
import SwiftUI

struct AccountSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 14) {
            Text(state.accountCreating ? "Create account" : "Sign in")
                .font(.system(size: 15, weight: .semibold))
            Text("Use the same account on every Mac. Your Stripe purchase is attached to it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            // Above the fields, not below them. macOS draws its password
            // autofill suggestion right under the password field, and it
            // covered the one line that says why the sign-in failed.
            if let message = state.accountMessage {
                WarningNote(message)
            }
            providers

            HStack(spacing: 9) {
                Hairline()
                Text("or")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                Hairline()
            }

            TextField("Email", text: $state.accountEmailInput)
                .textContentType(.emailAddress)
            SecureField("Password", text: $state.accountPassword)
                .textContentType(state.accountCreating ? .newPassword : .password)
                .onSubmit { Task { await state.submitAccount() } }
            HStack {
                Button(state.accountCreating ? "I already have an account" : "Create an account") {
                    state.accountCreating.toggle()
                    state.accountMessage = nil
                }
                .buttonStyle(.link)
                Spacer()
                if state.accountBusy { Spinner() }
                QuietButton(title: "Cancel") { dismiss() }
                Button(state.accountCreating ? "Create account" : "Sign in") {
                    Task { await state.submitAccount() }
                }
                .disabled(state.accountBusy || !state.accountServiceReady
                          || state.accountEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || state.accountPassword.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
        .background(Theme.content)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }

    /// The identity providers, one to a row.
    ///
    /// They sit above the email form, because a developer who already has a
    /// GitHub account is one click from done and never needs the form.
    private var providers: some View {
        VStack(spacing: 8) {
            ForEach(SupabaseOAuthProvider.allCases) { provider in
                Button {
                    Task { await state.signIn(with: provider) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: provider.symbol)
                            .font(.system(size: 13))
                        Text("Continue with \(provider.title)")
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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

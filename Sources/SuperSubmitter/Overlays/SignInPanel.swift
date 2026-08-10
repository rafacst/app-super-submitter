import SubmitKit
import SwiftUI

/// Sign in, or create an account. A panel over the window, the way Settings is.
///
/// It stood inside the Account tab for a while, because the paywall was a sheet
/// too and signing in on the way to a purchase put two modal layers between the
/// developer and the plan they were buying. The paywall is a tab now, so there
/// is no second layer left to stack under, and this goes back to being the one
/// panel it always read as.
///
/// Standing in the tab also charged the offer for it. The screen has to hold
/// one window with no scroll bar, and a form that appears in the middle of it
/// pushes the plans off the bottom edge at the exact moment they matter.
struct SignInPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            PanelTitleBar(title: state.accountCreating ? "Create account" : "Sign in") {
                dismiss()
            }
            form
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Theme.content)
        }
        .frame(width: 340)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }

    private var form: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 13) {
            Text("Use the same account on every Mac. Your purchase is attached to it.")
                .font(Theme.font(size: 11.5))
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
                Text("or").font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
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
                .font(Theme.font(size: 11.5))
                Spacer(minLength: 0)
                if state.accountBusy { Spinner() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .font(Theme.font(size: 12))
                        Text("Continue with \(provider.title)")
                            .font(Theme.font(size: 12))
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

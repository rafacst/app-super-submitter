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
            TextField("Email", text: $state.accountEmailInput)
                .textContentType(.emailAddress)
            SecureField("Password", text: $state.accountPassword)
                .textContentType(state.accountCreating ? .newPassword : .password)
                .onSubmit { Task { await state.submitAccount() } }
            if let message = state.accountMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(state.accountCreating ? "I already have an account" : "Create an account") {
                    state.accountCreating.toggle()
                    state.accountMessage = nil
                }
                .buttonStyle(.link)
                Spacer()
                QuietButton(title: "Cancel") { dismiss() }
                Button(state.accountCreating ? "Create account" : "Sign in") {
                    Task { await state.submitAccount() }
                }
                .disabled(state.accountBusy
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
}

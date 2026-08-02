import SwiftUI

struct AddLocaleSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a locale")
                .font(.system(size: 15, weight: .semibold))
            Text("Use the manifest locale code. Super Submitter maps it to each store's code when they differ.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            TextField("en-US", text: $code)
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                .focused($codeFocused)
                .onSubmit(add)

            HStack(spacing: 9) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 390)
        .background(Theme.content)
        .onAppear { codeFocused = true }
    }

    private func add() {
        if state.addLocale(code) { dismiss() }
    }
}

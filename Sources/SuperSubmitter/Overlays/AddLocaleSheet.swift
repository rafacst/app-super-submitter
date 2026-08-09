import SubmitKit
import SwiftUI

struct AddLocaleSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a language")
                .font(Theme.font(size: 15, weight: .semibold))
            Text("Pick the language of the listing. Super Submitter writes the code each store wants.")
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            ChoiceField(value: $code, choices: StoreValues.listingLocales,
                        emptyLabel: "Pick a language", allowsNone: false)

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
    }

    private func add() {
        if state.addLocale(code) { dismiss() }
    }
}

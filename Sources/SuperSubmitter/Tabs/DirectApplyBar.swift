import SubmitKit
import SwiftUI

/// The one button a Managing tab uses to write what it edits.
///
/// Publishing sends the same rows through the Summary tab, with the whole
/// diff in front of them. A manager who fixed one typo wants
/// one button, so this is that button. Every row lands in a draft or an
/// unstarted state, and none of them reaches a customer until somebody
/// publishes it in the store console.
struct DirectApplyBar: View {
    @Environment(AppState.self) private var state
    let target: DirectApplyTarget
    @State private var confirming = false

    var body: some View {
        let changes = state.changes(for: target)
        let running = state.directApplyRunning(target)
        let message = state.directApplyMessage(for: target)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(changes.isEmpty
                     ? "\(destination.capitalizedFirst) already holds everything on this tab."
                     : "\(changes.count) \(changes.count == 1 ? "row" : "rows") to write")
                    .font(Theme.font(size: 12.5, weight: .medium))
                Text(message.isEmpty
                     ? (changes.first ?? "Nothing here reaches a customer until you publish it in the store console.")
                     : message)
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(state.directApplyFailed(target) ? Theme.red : Theme.text2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if running { Spinner() }
            Button(running ? "Writing…" : "Write to \(destination)") { confirming = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(changes.isEmpty || running || state.stores.isEmpty)
        }
        .storePanel()
        .confirmationDialog("Write these to \(destination)?", isPresented: $confirming) {
            Button("Write them") { state.applyDirectly(target) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationLine)
        }
    }

    private var destination: String { target.destination(state.stores) }

    private var confirmationLine: String {
        let changes = state.changes(for: target)
        let named = changes.prefix(4).joined(separator: "\n")
        return "Super Submitter writes \(changes.count) rows now:\n\(named)"
            + (changes.count > 4 ? "\n…" : "")
            + "\n\nEach one lands as a draft or stays unstarted. None of them reaches a customer until you publish it in the store console."
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

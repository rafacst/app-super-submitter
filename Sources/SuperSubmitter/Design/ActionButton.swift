import SubmitKit
import SwiftUI

/// The button that ends a step.
///
/// One type, two weights. The action rows used a hand-built primary beside a
/// `QuietButton`, and the two carried their own padding and their own font, so
/// "Upload to the store" and "Keep the artifact and stop" stood on one row at
/// two heights. Both are the answer to the same question, and a row of answers
/// at two sizes reads as one answer and one aside.
///
/// It also owns the padlock. A capability the account does not hold is drawn
/// rather than hidden: hiding the button leaves a free developer looking for a
/// send command that is not on the screen, and disabling it says "not now"
/// without saying why. The press goes through `requirePaid`, which is the same
/// gate the write boundary asks, and which moves to the Account tab and writes
/// the reason at the top of it.
struct ActionButton: View {
    enum Kind { case primary, secondary }

    @Environment(AppState.self) private var state

    let title: String
    var kind: Kind = .primary
    var enabled = true
    /// The capability this action spends, and the line the Account tab shows
    /// when the account does not hold it.
    var paid: (capability: AccessCapability, trigger: PaywallTrigger)?
    let action: () -> Void

    private var locked: Bool {
        guard let paid else { return false }
        return state.showsLock(paid.capability)
    }

    /// A locked button is never disabled. It has somewhere to go.
    private var dimmed: Bool { !enabled && !locked }

    var body: some View {
        Button {
            guard let paid, locked else { return action() }
            guard state.requirePaid(paid.capability, paid.trigger) else { return }
            action()
        } label: {
            HStack(spacing: 6) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(Theme.font(size: 11, weight: .semibold))
                }
                Text(title).font(Theme.font(size: 13, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .frame(height: 32)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(kind == .secondary ? Theme.controlEdge : .clear,
                              lineWidth: Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .help(locked ? "Paid access sends this. Everything before it is free." : "")
    }

    private var foreground: Color {
        if dimmed { return Theme.text3 }
        return kind == .primary ? Theme.accentText : Theme.text
    }

    private var background: Color {
        switch kind {
        case .primary: dimmed ? Theme.sep2 : Theme.accent
        case .secondary: Theme.field
        }
    }
}

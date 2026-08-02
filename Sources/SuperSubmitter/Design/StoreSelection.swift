import SubmitKit
import SwiftUI

/// The one store picker used by setup and the Stores tab. Keeping its size,
/// typography, and selection treatment here prevents the two entry paths from
/// drifting into different controls.
struct StoreSelectionGrid: View {
    let selected: Set<Store>
    let toggle: (Store) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach([Store.apple, .google], id: \.self) { store in
                StoreSelectionCard(store: store, selected: selected.contains(store)) {
                    toggle(store)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stores")
    }
}

private struct StoreSelectionCard: View {
    let store: Store
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                StoreMark(store: store, size: 42)
                    .frame(width: 54, height: 54)
                    .background(store.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.storeName)
                        .font(.system(size: 17, weight: .semibold))
                    Text(store.selectionDescription)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : Theme.text3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: selected
                            ? [store.tint.opacity(0.14), Theme.raised]
                            : [Theme.raised, Theme.raised],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? store.tint.opacity(0.85) : Theme.sep,
                                  lineWidth: selected ? 1.6 : Theme.hairline)
            }
            .shadow(color: selected ? store.tint.opacity(0.10) : .clear,
                    radius: 12, y: 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.storeName)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension Store {
    var selectionDescription: String {
        switch self {
        case .apple: "iPhone, iPad, Mac, Apple TV, and Vision Pro"
        case .google: "Android phones, tablets, TV, Wear OS, and more"
        }
    }
}

import SubmitKit
import SwiftUI

/// The one store picker used by setup and the Stores tab. Keeping its size,
/// typography, and selection treatment here prevents the two entry paths from
/// drifting into different controls.
///
/// `detail` puts a column under each card, so a store's own fields open below
/// its own button instead of in a separate stack further down the screen.
struct StoreSelectionGrid<Detail: View>: View {
    private let selected: Set<Store>
    private let toggle: (Store) -> Void
    private let detail: (Store) -> Detail

    init(selected: Set<Store>, toggle: @escaping (Store) -> Void,
         @ViewBuilder detail: @escaping (Store) -> Detail) {
        self.selected = selected
        self.toggle = toggle
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach([Store.apple, .google], id: \.self) { store in
                VStack(alignment: .leading, spacing: 14) {
                    StoreSelectionCard(store: store, selected: selected.contains(store)) {
                        toggle(store)
                    }
                    detail(store)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stores")
    }
}

extension StoreSelectionGrid where Detail == EmptyView {
    init(selected: Set<Store>, toggle: @escaping (Store) -> Void) {
        self.init(selected: selected, toggle: toggle, detail: { _ in EmptyView() })
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
            // Selection wears the selection colour, not the brand colour.
            //
            // The card used to fill and outline itself with `store.tint`,
            // which is black for Apple and green for Google. Two cards in the
            // same state then looked like two different states, and the green
            // one read as "connected" while the panel under it still said Not
            // connected. Green means a good outcome everywhere else in the app,
            // so it may not also mean "this one is the Android one".
            //
            // The logo keeps the brand. That is identity, and identity is what
            // a logo is for.
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Theme.accent.opacity(0.10) : Theme.raised)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? Theme.accent : Theme.controlEdge,
                                  lineWidth: selected ? 1.6 : Theme.hairline)
            }
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

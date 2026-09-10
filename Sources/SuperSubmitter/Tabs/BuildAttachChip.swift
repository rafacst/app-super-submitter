import SubmitKit
import SwiftUI

/// Which build the tab is attaching its data and changes to, on every tab.
///
/// A store write attaches to a build, and until one is chosen every edit stays
/// on this Mac. The chip says which build each store gets, or that none is
/// attached yet, and pressing it opens the Build tab, the one place a build is
/// chosen. See `AppState.attachedBuild(for:)`.
struct BuildAttachChip: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let stores = Store.allCases.filter(state.stores.contains)
        if !stores.isEmpty {
            Button { state.openBuildTabToAttach() } label: { chip(stores) }
                .buttonStyle(.plain)
                .help(helpText(stores))
                .accessibilityLabel(helpText(stores))
        }
    }

    private func chip(_ stores: [Store]) -> some View {
        let missing = !state.storesMissingBuild.isEmpty
        return HStack(spacing: 7) {
            Image(systemName: missing ? "shippingbox" : "shippingbox.fill")
                .font(Theme.font(size: 10.5))
                .foregroundStyle(missing ? Theme.yellow : Theme.text3)
            ForEach(stores) { store in
                HStack(spacing: 3) {
                    StoreMark(store: store, size: 10)
                    Text(state.attachedBuild(for: store)?.label ?? "no build")
                        .font(Theme.font(size: 10, weight: .medium))
                        .foregroundStyle(state.hasAttachedBuild(for: store)
                                         ? Theme.text2 : Theme.yellow)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(missing ? Theme.yellowBg : Theme.sunken, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .contentShape(Capsule())
    }

    private func helpText(_ stores: [Store]) -> String {
        let missing = state.storesMissingBuild
        guard !missing.isEmpty else {
            let parts = stores.compactMap { store in
                state.attachedBuild(for: store).map { "\(store.storeName): \($0.label)" }
            }
            return "The changes attach to \(parts.joined(separator: ", ")). Choose a build in the Build tab."
        }
        let names = missing.map(\.storeName).joined(separator: " and ")
        return "No build is attached for \(names), so these changes stay on this Mac. "
            + "Choose a build in the Build tab before uploading."
    }
}

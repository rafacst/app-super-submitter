import SubmitKit
import SwiftUI

/// The menu bar item. The state of both stores in one glance, without the
/// window.
struct MenuBarPopover: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(Theme.font(size: 12.5, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ForEach(Store.allCases.filter { state.stores.contains($0) }) { store in
                row(state.statuses[store]
                    ?? StoreStatus(store: store, phase: .noDraft,
                                   detail: state.detail(for: store)))
            }

            Button {
                NSApp.activate()
            } label: {
                Text("Open Super Submitter")
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 270)
        .background(Theme.content)
        .foregroundStyle(Theme.text)
    }

    private var title: String {
        let name = state.currentApp?.name ?? "Super Submitter"
        guard let version = state.manifest.displayVersionName, !version.isEmpty else {
            return name
        }
        return "\(name) \(version)"
    }

    private func row(_ status: StoreStatus) -> some View {
        HStack(spacing: 9) {
            Group {
                if status.phase.isReleased {
                    RoundedRectangle(cornerRadius: 1).fill(Theme.yellow)
                } else {
                    Circle().fill(Theme.text3)
                }
            }
            .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.storeName).font(Theme.font(size: 12))
                Text(checked(status))
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            Text(status.phase.label)
                .font(Theme.font(size: 11.5))
                .foregroundStyle(status.phase.isReleased ? Theme.yellow : Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The app polls a store only after a release, so a draft row honestly
    /// says that nothing has been checked.
    private func checked(_ status: StoreStatus) -> String {
        guard let date = status.checkedAt else { return "not checked yet" }
        guard status.phase.isReleased else { return "no poll needed for a draft" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "checked just now" }
        return "checked \(minutes) \(minutes == 1 ? "minute" : "minutes") ago"
    }
}

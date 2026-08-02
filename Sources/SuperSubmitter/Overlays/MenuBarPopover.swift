import SwiftUI

/// The menu bar item. The state of both stores in one glance, without the
/// window.
struct MenuBarPopover: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Fast Bill Split 3.2.0").font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            row(store: "App Store", released: state.appleReleased)
            row(store: "Google Play", released: state.googleReleased)

            Button {
                NSApp.activate()
            } label: {
                Text("Open Super Submitter")
                    .font(.system(size: 11.5))
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

    private func row(store: String, released: Bool) -> some View {
        HStack(spacing: 9) {
            Group {
                if released {
                    RoundedRectangle(cornerRadius: 1).fill(Theme.yellow)
                } else {
                    Circle().fill(Theme.text3)
                }
            }
            .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(store).font(.system(size: 12))
                Text("checked 2 minutes ago")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            Text(label(released: released))
                .font(.system(size: 11.5))
                .foregroundStyle(released ? Theme.yellow : Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func label(released: Bool) -> String {
        if released { "Waiting for review" }
        else if state.applied { "Draft, ready to release" }
        else { "No draft yet" }
    }
}

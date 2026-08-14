import SubmitKit
import SwiftUI

/// The linked apps, across the top of the window.
///
/// They were a group at the head of the sidebar, under the destinations of the
/// app you were standing in. That put two levels of one hierarchy in one
/// column: which app, and which screen of it. Pressing an app there opened its
/// store page, so switching app also moved you off whatever you were reading,
/// and there was nowhere for an app to say it was busy once it left the screen.
///
/// A tab bar answers "which app" above "which screen", the way a browser does.
/// Switching keeps the screen you are on, so comparing the Details of two apps
/// is two clicks, and a build running on another app has a place to say so.
struct AppTabBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // A scroll, because the number of apps is the developer's business.
        // Twelve linked apps used to squeeze the sidebar groups; here they run
        // off the side and the bar keeps its height.
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(state.appRows.enumerated()), id: \.element.id) { index, app in
                        AppTab(index: index, app: app)
                            .id(app.id)
                    }
                    addButton
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.never)
            // An app opened from anywhere else — the entry screen, an import,
            // the File menu — scrolls itself into view. Without this the tab of
            // the app being worked on can sit off the end of the bar.
            .onChange(of: state.selectedAppIndex) {
                guard state.appRows.indices.contains(state.selectedAppIndex) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(state.appRows[state.selectedAppIndex].id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thickMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var addButton: some View {
        Button { state.showEntryScreen = true } label: {
            Image(systemName: "plus")
                .font(Theme.font(size: 11, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Add an app")
        .accessibilityLabel("Add an app")
    }
}

/// One app's tab.
///
/// The icon and the name say which app, the status chip says where the stores
/// have it, and the dot says this app is building right now. The dot is the
/// whole reason the bar exists: a build that is no longer on the screen is
/// still running, and before this there was no way for the window to say so.
private struct AppTab: View {
    @Environment(AppState.self) private var state
    let index: Int
    let app: AppSummary

    private var selected: Bool { index == state.selectedAppIndex }

    var body: some View {
        Button {
            // The screen stays. Switching app while reading Details lands on
            // the other app's Details, which is what the bar is for; the old
            // list opened the store page and lost your place every time.
            state.selectApp(at: index)
        } label: {
            HStack(spacing: 6) {
                AppIconBadge(icon: app.icon, initials: app.initials, size: 15)
                Text(app.name)
                    .font(Theme.font(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.text2)
                    .lineLimit(1)
                if state.isBuilding(appID: app.id) { BuildingDot() }
                AppStatusChip(mark: state.appMark(appKey: app.key))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.content)
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The name truncates at 180 points. A tab bar of five apps whose names
        // all start "My Company " is five identical tabs otherwise.
        .frame(maxWidth: 180)
        .help(app.name)
        .contextMenu {
            Button("Update from the Stores…") {
                state.selectApp(at: index)
                state.showExistingAppImport = true
            }
            Divider()
            Button("Remove from Super Submitter…") { state.askToRemoveApp(at: index) }
        }
        .accessibilityLabel(app.name)
        .accessibilityValue(app.storeSummary)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// This app is building or sending, and you are looking at another one.
///
/// It pulses, because the state it reports is one that ends on its own. A
/// static dot beside a name says "something about this app"; a moving one says
/// "something is happening in it right now", which is the only reason to draw
/// it on a tab the developer has left.
private struct BuildingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 5, height: 5)
            .opacity(dim ? 0.25 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(),
                       value: dim)
            .onAppear { dim = true }
            .accessibilityElement()
            .accessibilityLabel("Building")
    }
}

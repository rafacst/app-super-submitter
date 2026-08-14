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
                HStack(spacing: 8) {
                    // One box of segments, which is the tab view the Mac uses
                    // for switching what the window is showing. The tabs were
                    // loose buttons on the band: the selected one drew a card
                    // and the others drew nothing at all, so a window with one
                    // app showed a single floating chip and no control.
                    HStack(spacing: 2) {
                        ForEach(Array(state.appRows.enumerated()),
                                id: \.element.id) { index, app in
                            AppTab(index: index, app: app)
                                .id(app.id)
                        }
                        addButton
                    }
                    .padding(2)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
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
        .frame(maxWidth: .infinity, minHeight: Theme.headerHeight,
               maxHeight: Theme.headerHeight, alignment: .leading)
        .background(Theme.content)
    }

    private var addButton: some View {
        Button { state.showEntryScreen = true } label: {
            Label("Add app", systemImage: "plus")
                .font(Theme.font(size: 12, weight: state.showsEntryScreen ? .semibold : .regular))
                .foregroundStyle(state.showsEntryScreen ? Theme.text : Theme.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if state.showsEntryScreen {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.raised)
                            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state.showsEntryScreen ? [.isButton, .isSelected] : .isButton)
    }
}

/// One app's tab.
///
/// The icon and the name say which app, and the dot says this app is building
/// right now. The dot is the whole reason the bar exists: a build that is no
/// longer on the screen is still running, and before this there was no way for
/// the window to say so.
///
/// The store standing is not here. A tab bar answers "which app", and a chip
/// reading "Store draft" beside every name answered a question nobody asked at
/// the moment they were picking one — it doubled the width of each tab, so the
/// names got squeezed into an ellipsis and the one thing the bar is for became
/// the hardest thing on it to read. The standing is still on the screens that
/// are about it, and the tooltip carries it here.
private struct AppTab: View {
    @Environment(AppState.self) private var state
    let index: Int
    let app: AppSummary

    private var selected: Bool {
        index == state.selectedAppIndex && !state.showsEntryScreen
    }

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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                // The raised segment inside the box, the way the system draws
                // the chosen one: one step lighter than the track, with the
                // shadow that lifts it. The others are the track itself.
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.raised)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The name truncates at 180 points. A tab bar of five apps whose names
        // all start "My Company " is five identical tabs otherwise.
        .frame(maxWidth: 180)
        // The standing, in the one place that costs the bar no width. It was a
        // chip on the tab itself.
        .help("\(app.name) · \(state.appMark(appKey: app.key).explained)")
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

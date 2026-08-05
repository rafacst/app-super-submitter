import SubmitKit
import SwiftUI

/// The sidebar. 240 points, the Apps list on top, the nine tabs below, and
/// Settings at the foot.
struct Sidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The traffic lights are drawn over the top of this panel. This
            // row is the space they need, so the Apps header clears them.
            Color.clear.frame(height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text("Apps")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                // No "No apps linked" row. The Add app row below is already
                // the whole story when the list is empty.
                ForEach(Array(state.appRows.enumerated()), id: \.element.id) { index, app in
                    Button {
                        state.selectApp(at: index)
                    } label: {
                        AppRow(app: app, selected: index == state.selectedAppIndex)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Update from the stores…") {
                            state.showExistingAppImport = true
                        }
                        Button("Remove from Super Submitter…", role: .destructive) {
                            state.askToRemoveApp(at: index)
                        }
                    }
                    .accessibilityLabel(app.name)
                    .accessibilityValue(app.storeSummary)
                    .accessibilityAddTraits(index == state.selectedAppIndex ? .isSelected : [])
                }
                Button { state.chooseAppFolder() } label: { NewAppRow() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add app")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)

            Hairline().padding(.horizontal, 12).padding(.bottom, 8)

            ModeSwitch().padding(.horizontal, 8).padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Tab.tabs(in: state.mode)) { tab in
                    // A rule before tab 7 and before tab 9. It marks where
                    // the app stops editing a file and starts touching a
                    // store.
                    if tab.startsZone {
                        Color.clear.frame(height: 6)
                        Hairline().padding(.horizontal, 8)
                        Color.clear.frame(height: 6)
                    }
                    TabRow(tab: tab)
                }
                Color.clear.frame(height: 6)
                SettingsRow()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)

            Spacer(minLength: 0)

            if state.manifestURL != nil {
                Hairline().padding(.horizontal, 12)
                SavedChip()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        // No fill of its own. The sidebar is the window surface, and the
        // content panel is the thing that floats on it.
    }
}

private struct AppRow: View {
    let app: AppSummary
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            InitialsBadge(text: app.initials, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let apple = app.apple { HealthChip(store: .apple, health: apple) }
                    if let google = app.google { HealthChip(store: .google, health: google) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selected ? Theme.sep2 : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(.rect)
    }
}

private struct NewAppRow: View {
    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3))
            Text("Add app").font(.system(size: 12.5))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

private struct TabRow: View {
    @Environment(AppState.self) private var state
    let tab: Tab

    private var selected: Bool { state.selectedTab == tab }

    var body: some View {
        Button {
            state.selectedTab = tab
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol(selected: selected))
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    // Always its own colour, so the column reads as thirteen
                    // places and not one shape repeated.
                    .foregroundStyle(tab.tint)
                    .frame(width: 20)
                Text(tab.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? tab.tint : Theme.text)
                Spacer(minLength: 0)
                if let badge = state.badge(for: tab) {
                    BadgeView(count: badge.count, severity: badge.severity, size: 16)
                }
            }
            // The row wears the colour of its tab, as a wash rather than a
            // solid. Thirteen solid fills would each need their own readable
            // text colour, and the lighter ones cannot carry white at all.
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? tab.tint.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? tab.tint.opacity(0.45) : .clear,
                              lineWidth: Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(state.manifestURL == nil)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsRow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            state.showSettings = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: state.showSettings ? "gearshape.2.fill" : "gearshape.2")
                    .font(.system(size: 15))
                    .frame(width: 20)
                Text("Settings…").font(.system(size: 13.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}

/// The two jobs, as one control.
///
/// It sits above the tabs, because it decides which tabs exist. A publisher
/// sends a version; a manager runs the app that is already out there.
struct ModeSwitch: View {
    @Environment(AppState.self) private var state
    /// The pill is one view that moves between the two halves, so the switch
    /// slides instead of blinking from one fill to another.
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases) { mode in
                let selected = state.mode == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        state.mode = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 10.5))
                        Text(mode.title)
                            .font(.system(size: 12,
                                          weight: selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? Theme.accentText : Theme.text2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(mode.tint)
                                .matchedGeometryEffect(id: "modePill", in: pill)
                                .shadow(color: mode.tint.opacity(0.45), radius: 3, y: 1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityHint(mode.line)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

// MARK: - The shared small parts

/// States that the work is on disk, and opens the file that holds it.
///
/// The app has no unsaved state to warn about: every field writes `store.yaml`
/// when it changes. This says so, because a form with no Save button reads as
/// a form that keeps nothing.
struct SavedChip: View {
    @Environment(AppState.self) private var state

    private var line: String {
        guard let date = state.lastSavedAt else { return "Saved to store.yaml" }
        return "Saved \(date.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        Button { state.revealManifest() } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.green)
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Every change is written as you type. Click to show store.yaml in the Finder.")
        .accessibilityLabel(line)
        .accessibilityHint("Shows store.yaml in the Finder")
    }
}

struct InitialsBadge: View {
    let text: String
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.sunken)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .frame(width: size, height: size)
            .overlay(
                Text(text)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Theme.text2)
            )
    }
}

/// One store, and how that store stands.
///
/// The logo says which store faster than a letter does, and it is the same
/// mark every other tab uses for the same store. The glyph beside it keeps
/// its severity colour, so the chip still reads at a glance.
struct HealthChip: View {
    let store: Store
    let health: StoreHealth

    var body: some View {
        HStack(spacing: 3) {
            StoreMark(store: store, size: 9)
            Text(health.mark)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(health.color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(health.background, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement()
        .accessibilityLabel("\(store.storeName) \(health.label)")
    }
}

/// The count on a tab row. It keeps its severity colour whether the row is
/// selected or not: the row is a wash now, not a solid fill, so there is
/// nothing to invert against.
struct BadgeView: View {
    let count: Int
    let severity: Severity
    var size: CGFloat

    var body: some View {
        Text("\(count)")
            .font(.system(size: size * 0.65, weight: .semibold))
            .foregroundStyle(severity.color)
            .padding(.horizontal, 4)
            .frame(minWidth: size, minHeight: size)
            .background(severity.background, in: Capsule())
    }
}


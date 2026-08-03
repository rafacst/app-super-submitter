import SwiftUI

/// The sidebar. 240 points, the Apps list on top, the nine tabs below, and
/// Settings at the foot.
struct Sidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The traffic lights sit in the title bar. This row reserves the
            // space so the Apps header is not under them.
            Color.clear.frame(height: Theme.headerHeight)

            VStack(alignment: .leading, spacing: 1) {
                Text("Apps")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                if state.appRows.isEmpty {
                    Text("No apps linked")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                }

                ForEach(Array(state.appRows.enumerated()), id: \.element.id) { index, app in
                    Button {
                        state.selectApp(at: index)
                    } label: {
                        AppRow(app: app, selected: index == state.selectedAppIndex)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.name)
                    .accessibilityValue("App Store \(app.apple.mark), Google Play \(app.google.mark)")
                    .accessibilityAddTraits(index == state.selectedAppIndex ? .isSelected : [])
                }
                Button { state.chooseAppFolder() } label: { NewAppRow() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add app")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)

            Hairline().padding(.horizontal, 12).padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Tab.allCases) { tab in
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
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
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
                    HealthChip(letter: "A", health: app.apple)
                    HealthChip(letter: "G", health: app.google)
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
                    .frame(width: 20)
                Text(tab.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
                if let badge = state.badge(for: tab) {
                    BadgeView(count: badge.count, severity: badge.severity, selected: selected, size: 16)
                }
            }
            .foregroundStyle(selected ? Theme.accentText : Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 6))
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

// MARK: - The shared small parts

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

struct HealthChip: View {
    let letter: String
    let health: StoreHealth

    var body: some View {
        Text("\(letter) \(health.mark)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(health.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(health.background, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct BadgeView: View {
    let count: Int
    let severity: Severity
    let selected: Bool
    var size: CGFloat

    var body: some View {
        Text("\(count)")
            .font(.system(size: size * 0.65, weight: .semibold))
            .foregroundStyle(selected ? .white : severity.color)
            .padding(.horizontal, 4)
            .frame(minWidth: size, minHeight: size)
            .background(
                selected ? AnyShapeStyle(Color.white.opacity(0.25))
                         : AnyShapeStyle(severity.background),
                in: Capsule()
            )
    }
}


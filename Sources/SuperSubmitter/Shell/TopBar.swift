import SwiftUI

/// The second navigation position. The same nine tabs, as a segmented control,
/// with the app switcher moved into the bar.
struct TopBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 14) {
            // Room for the traffic lights.
            Color.clear.frame(width: 62, height: 1)

            SwitcherChip()

            VHairline().frame(height: 26)

            HStack(spacing: 1) {
                ForEach(Tab.allCases) { tab in
                    if tab.startsZone {
                        Rectangle().fill(Theme.sep)
                            .frame(width: 1)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                    }
                    TabSegment(tab: tab)
                }
            }
            .padding(2)
            .background(Theme.sunken)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .frame(height: 32)

            Spacer(minLength: 8)

            Button {
                state.showSettings = true
            } label: {
                Image(systemName: state.showSettings ? "gearshape.2.fill" : "gearshape.2")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.topBarHeight)
        .background(Theme.sidebar)
    }
}

private struct TabSegment: View {
    @Environment(AppState.self) private var state
    let tab: Tab

    private var selected: Bool { state.selectedTab == tab }

    var body: some View {
        Button {
            state.selectedTab = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol(selected: selected))
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Text(tab.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                if let badge = state.badge(for: tab) {
                    BadgeView(count: badge.count, severity: badge.severity, selected: selected, size: 14)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .padding(.horizontal, 7)
            .frame(maxHeight: .infinity)
            .background(selected ? Theme.field : .clear, in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: selected ? .black.opacity(0.16) : .clear, radius: 1, y: 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(state.manifestURL == nil)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The app switcher, as a chip. The Apple dot is round and the Google dot is
/// square, so the two read apart with no colour.
struct SwitcherChip: View {
    @Environment(AppState.self) private var state

    @ViewBuilder
    var body: some View {
        if let app = state.currentApp {
            Button {
                state.switcherOpen.toggle()
            } label: {
                HStack(spacing: 10) {
                    InitialsBadge(text: app.initials, size: 24)
                    Text(app.name).font(.system(size: 12.5, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle().fill(app.apple.color).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 2).fill(app.google.color)
                            .frame(width: 8, height: 8)
                    }
                    Text("▾").font(.system(size: 8)).foregroundStyle(Theme.text3)
                }
                .padding(.leading, 4)
                .padding(.trailing, 9)
                .frame(height: 32)
                .background(state.switcherOpen ? Theme.sunken : Theme.field,
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                .shadow(color: .black.opacity(0.09), radius: 0.75, y: 1)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current app, \(app.name)")
            .accessibilityHint("Shows linked apps")
        } else {
            Button("Select app folder") { state.chooseAppFolder() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}

/// The list that drops out of the chip.
struct SwitcherPopover: View {
    @Environment(AppState.self) private var state
    let position: NavigationPosition

    var body: some View {
        if state.switcherOpen, position == .topBar, !state.appRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("LINKED APPS")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.7)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                ForEach(Array(state.appRows.enumerated()), id: \.element.id) { index, app in
                    let selected = index == state.selectedAppIndex
                    Button {
                        state.selectApp(at: index)
                        state.switcherOpen = false
                    } label: {
                        HStack(spacing: 10) {
                            Text(selected ? "✓" : "")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 12)
                            InitialsBadge(text: app.initials, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(app.summary).font(.system(size: 10.5))
                                    .foregroundStyle(Theme.text2).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 4) {
                                HealthChip(letter: "A", health: app.apple)
                                HealthChip(letter: "G", health: app.google)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.sunken : .clear)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.name)
                    .accessibilityValue("App Store \(app.apple.mark), Google Play \(app.google.mark)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }

                Button {
                    state.switcherOpen = false
                    state.chooseAppFolder()
                } label: {
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                            .frame(width: 24, height: 24)
                            .overlay(Image(systemName: "folder.badge.plus")
                                .font(.system(size: 10)).foregroundStyle(Theme.text3))
                        Text("Add app").font(.system(size: 12.5))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 292)
            .background(Theme.content, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .shadow(color: .black.opacity(0.30), radius: 18, y: 14)
            .padding(.leading, 76)
            .padding(.top, 46)
        }
    }
}

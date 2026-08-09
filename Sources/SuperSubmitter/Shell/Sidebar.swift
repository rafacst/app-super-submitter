import SubmitKit
import SwiftUI

/// The sidebar: an app switcher, a `List` of destinations in sections, and an
/// account control at the foot.
///
/// It was a hand-built column — a `VStack` of custom buttons, each drawing its
/// own selected band, inside a floating panel with the window buttons nudged
/// in by hand. Every part of that had a system equivalent that already
/// behaves the way a Mac user expects, so this is a `List` in its sidebar
/// style inside a `NavigationSplitView`, and the system draws the selection,
/// the section headers, the vibrancy, the row metrics, the divider, and the
/// collapse.
///
/// Three controls went with it, each because it was a navigation system
/// competing with this one:
///
/// - The Publishing and Managing switch decided which rows existed, so half
///   the app lived behind a control that named neither half. The rows are all
///   here now, under `SidebarSection`.
/// - Settings and About were rows of the work that changed nothing about an
///   app. They are in the app menu, where every Mac keeps them, at ⌘, and
///   under About Super Submitter.
/// - "Saved to store.yaml" was a status line at the bottom of a navigation
///   column. It is a save confirmation in the content header now, and Show
///   store.yaml in Finder is in the File menu.
struct Sidebar: View {
    @Environment(AppState.self) private var state

    /// The selection, as the two properties that already hold it.
    ///
    /// No new state. `selectedTab` and `mode` are the app's own navigation and
    /// they are what the rest of the shell reads, so the list writes them.
    /// The mode goes first: `selectedTab` moves itself into the mode that owns
    /// it, and setting the mode first means that rule never has to fire.
    private var selection: Binding<Destination?> {
        Binding(get: { [state] in Destination(tab: state.selectedTab, mode: state.mode) },
                set: { [state] destination in
                    guard let destination else { return }
                    state.mode = destination.mode
                    state.selectedTab = destination.tab
                })
    }

    var body: some View {
        // The `List` is the column, and nothing wraps it and nothing insets it.
        //
        // Both of the obvious ways to pin a header and a footer to a sidebar
        // break this one, and each breaks it the same way: the column draws
        // nothing at all — not a row, not a plain `Text` put first as a probe —
        // and the detail pane loses its header off the top of the window. A
        // `VStack` around the list does it. A `safeAreaInset` on the list does
        // it too, with any content and any menu style. Both were tried and
        // photographed. `NavigationSplitView` gives its sidebar column to a
        // list and to nothing else.
        //
        // So the two ends are rows. They scroll with the destinations, which
        // is the one thing lost, and there are eleven rows at most.
        List(selection: selection) {
            // Neither end carries a tag, so neither is selectable: the
            // selection means "the destination you are on", and the app you
            // are working on and the account you are signed in as are two
            // other levels of the same hierarchy.
            AppSwitcher()
                .listRowSeparator(.hidden)

            ForEach(SidebarSection.allCases) { section in
                let rows = Destination.rows(in: section, hasApp: !state.hasNoOpenApp)
                if !rows.isEmpty {
                    Section(section.title) {
                        ForEach(rows) { DestinationRow(destination: $0) }
                    }
                }
            }

            Section {
                if state.showsUpgradeCard {
                    UpgradeCard().listRowSeparator(.hidden)
                }
                AccountControl().listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
    }
}

/// One navigation row: a symbol, a label, and the counts that block an apply.
///
/// No fill, no border, no tint of its own. The band this used to draw was a
/// second selected state next to the system's, and the two never agreed about
/// the accent colour, the focus ring, or what a row looks like when the window
/// is not key. `List` answers all three.
private struct DestinationRow: View {
    @Environment(AppState.self) private var state
    let destination: Destination

    private var selected: Bool {
        destination == Destination(tab: state.selectedTab, mode: state.mode)
    }

    /// Red on Release, and the system's own tint on every other row.
    ///
    /// Red says irreversible everywhere in this app and Release is the row
    /// that is, so the hazard is marked before you arrive rather than after.
    /// It steps aside while the row is selected: `List` draws a selected row
    /// in the accent colour and turns its label white, and a red glyph left on
    /// top of that is a colour fighting a fill.
    private var marksTheHazard: Bool { destination.tab == .release && !selected }

    var body: some View {
        HStack(spacing: 0) {
            Label {
                Text(destination.title)
            } icon: {
                Image(systemName: destination.tab.symbol)
                    .foregroundStyle(marksTheHazard ? AnyShapeStyle(Theme.red)
                                                    : AnyShapeStyle(.tint))
            }
            Spacer(minLength: 8)
            if let badge = state.badge(for: destination.tab) {
                BadgeView(badge: badge, size: 16)
            }
        }
        .tag(destination)
        .accessibilityValue(state.badge(for: destination.tab)?.spoken ?? "")
    }
}

/// The app being worked on, and the way to any other.
///
/// It replaced an "Apps" heading, a two-line card for the open app, and a
/// separate "Add app" row: three rows of chrome, at the top of the column, to
/// say one thing. The card also wore the same selected fill as a navigation
/// row, so the app and the destination competed for the one thing that fill
/// means.
///
/// A pull-down is what the Mac uses for "this one, of these": the current
/// choice on the button, the rest in the menu, a tick beside the one you are
/// on. The list, the tick, and Add App… are the same three actions the three
/// rows carried, and they all call what they always called.
private struct AppSwitcher: View {
    @Environment(AppState.self) private var state

    private var current: AppSummary? { state.currentApp }

    var body: some View {
        Menu {
            // A `Picker`, so the tick beside the current app is AppKit's own
            // and looks like every other "one of these" menu on the Mac.
            Picker("App", selection: Binding(get: { [state] in state.selectedAppIndex },
                                             set: { [state] in state.selectApp(at: $0) })) {
                ForEach(Array(state.appRows.enumerated()), id: \.element.id) { index, app in
                    Text(app.name).tag(index)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if !state.appRows.isEmpty { Divider() }
            // The entry screen, not a folder picker. "Add App" is the question
            // "what do I want to do", and the entry screen is where that
            // question is already answered three ways.
            Button("Add App…") { state.showEntryScreen = true }
            if state.currentApp != nil {
                Button("Update from the Stores…") { state.showExistingAppImport = true }
                Divider()
                Button("Remove from Super Submitter…") {
                    state.askToRemoveApp(at: state.selectedAppIndex)
                }
            }
        } label: {
            HStack(spacing: 7) {
                if let current {
                    AppIconBadge(icon: current.icon, initials: current.initials, size: 18)
                    Text(current.name).lineLimit(1)
                } else {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                    Text("No app").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        // The system's own pull-down. It was `.borderlessButton`, and a
        // borderless menu in a safe area inset of a sidebar list took the
        // whole column down with it: the list drew no rows and the detail pane
        // lost its header off the top of the window.
        .menuIndicator(.visible)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .accessibilityLabel("Current app")
        .accessibilityValue(current?.name ?? "No app")
    }
}


/// Who is signed in, and the actions that belong to them.
///
/// It replaced a "Super Submitter" heading over an Account row, a Settings row
/// and an About row. The heading was the name of this program over three rows
/// that had only that in common, and two of the three were not destinations at
/// all: they opened panels. Settings and About are in the app menu now.
///
/// The button says the account, because that is the level of the hierarchy it
/// sits at. The Account screen is still a screen, and this is the way in.
private struct AccountControl: View {
    @Environment(AppState.self) private var state

    private var label: String { state.accountEmail ?? "Not signed in" }

    var body: some View {
        Menu {
            Button("Account") { state.selectedTab = .account }
            if state.showsUpgradeCard {
                Button("See the Plans…") { state.openPaywall(.settings) }
            }
            if state.accountEmail != nil {
                Divider()
                Button("Sign Out") { state.signOutOfBilling() }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Text(label).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 12.5))
        }
        .controlSize(.small)
        .accessibilityLabel("Account")
        .accessibilityValue(label)
    }
}

/// The offer at the foot of the column, for a free account and for no other.
///
/// Both references end their sidebar this way, and the two cards are not the
/// same card. Veltrix sells: a headline, a sentence, a price. Vocalyn shows a
/// real number first — 40% of 100 minutes — and lets the offer follow it.
/// Vocalyn's is the better card, because it is worth reading on the days
/// nobody buys anything.
///
/// This app meters nothing, so there is no quota to show. It does have a real
/// number: the plan. Once the stores have been read, the card says how many
/// writes are waiting, which is exactly what paid access unlocks and exactly
/// the work the developer has already done.
///
/// It shows for `.free` and never for `.expired`, `.grace` or `.revoked`.
/// Somebody who has paid before is not somebody who never has, and the two may
/// not be sold to in the same words.
///
/// It is present whenever the account is free, and not only while a plan
/// exists. `invalidatePlan` fires on every edit, so a card gated on the plan
/// would appear and vanish as the developer typed, and a sidebar is not a place
/// where things may flicker.
///
/// No countdown, no scarcity, no red badge, and nothing that comes back after
/// it is dismissed. It is a standing offer at the foot of a column.
private struct UpgradeCard: View {
    @Environment(AppState.self) private var state

    /// `AppState.upgradeCardLine`. It lives there so a test can read it.
    private var line: String { state.upgradeCardLine }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                IconChip(symbol: "bolt.fill", tint: Theme.accent, size: 20)
                Text("Super Submitter Pro").font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text(line)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // The route the gates already use. It does not introduce a second
            // purchase path.
            Button { state.openPaywall(.settings) } label: {
                Text("See the plans")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        // The one place a tint is allowed to be decoration, because the tint is
        // what separates an offer from the navigation above it. Accent, not
        // red, which means irreversible, and not green, which is a status.
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.accent.opacity(0.30), lineWidth: Theme.hairline))
        .accessibilityElement(children: .contain)
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

/// The app's own icon, and its initials until an import has fetched one.
///
/// The file is read once per row and cached by `NSImage`, so a sidebar of ten
/// apps costs ten reads on the first draw and none after it.
struct AppIconBadge: View {
    let icon: URL?
    let initials: String
    var size: CGFloat

    private var image: NSImage? {
        guard let icon, FileManager.default.fileExists(atPath: icon.path) else { return nil }
        return NSImage(contentsOf: icon)
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                // The stores serve a square icon and draw the corner
                // themselves, so this draws the same corner Apple does.
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225))
                .overlay(RoundedRectangle(cornerRadius: size * 0.225)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        } else {
            InitialsBadge(text: initials, size: size)
        }
    }
}

/// One store, and how that store stands.
///
/// The logo says which store, and the tinted panel behind it says how the
/// store stands. The glyph that used to sit beside the logo said the same
/// thing a second time, and an exclamation mark under an app name reads as a
/// fault even when the state is "there are edits to send".
struct HealthChip: View {
    let store: Store
    let health: StoreHealth

    var body: some View {
        StoreMark(store: store, size: 9)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(health.background, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityElement()
            .accessibilityLabel("\(store.storeName) \(health.label)")
    }
}

/// The counts on a sidebar row: what blocks the apply, then what does not.
///
/// Two pills and not one number. The errors come first because they are the
/// ones that stop the work, and a tab with only warnings draws the yellow pill
/// alone, so red still never appears where there is no error.
///
/// Each pill keeps its severity colour whether the row is selected or not.
struct BadgeView: View {
    let badge: TabBadge
    var size: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            if badge.errors > 0 { pill(badge.errors, .error) }
            if badge.warnings > 0 { pill(badge.warnings, .warning) }
        }
        .help(badge.spoken)
    }

    private func pill(_ count: Int, _ severity: Severity) -> some View {
        // Verbatim, so a locale that groups thousands cannot turn a count
        // into "1.242". See the Details counter for the same reason.
        Text(verbatim: "\(count)")
            .font(.system(size: size * 0.65, weight: .semibold))
            .foregroundStyle(severity.color)
            .padding(.horizontal, 4)
            .frame(minWidth: size, minHeight: size)
            .background(severity.background, in: Capsule())
    }
}

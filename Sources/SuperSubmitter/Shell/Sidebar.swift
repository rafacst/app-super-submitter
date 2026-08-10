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

    /// Which groups are open. Every one starts open, because a sidebar that
    /// opens closed hides the app from a first-time developer, and the point of
    /// listing both jobs at once was that nothing hides.
    ///
    /// `@AppStorage` and not `@State`: a group a developer closed is a
    /// decision, and re-opening it on every launch would undo that decision
    /// every morning. One key per group, because they close independently.
    @AppStorage("sidebar.apps.open") private var appsOpen = true
    @AppStorage("sidebar.publish.open") private var publishOpen = true
    @AppStorage("sidebar.send.open") private var sendOpen = true
    @AppStorage("sidebar.manage.open") private var manageOpen = true

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
                    // Build and Details may present a saved inspector. Letting
                    // the List's selection transaction animate that column
                    // briefly widens the split view and clips the sidebar.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        state.mode = destination.mode
                        state.selectedTab = destination.tab
                    }
                })
    }

    private func isOpen(_ section: SidebarSection) -> Binding<Bool> {
        switch section {
        case .publish: $publishOpen
        case .send: $sendOpen
        case .manage: $manageOpen
        }
    }

    var body: some View {
        // The account and the offer are pinned, and the destinations scroll.
        //
        // `safeAreaInset` and not a row at the end of the list. As rows they
        // scrolled away with the navigation, so the offer at the "foot of the
        // column" was only at the foot of a short column, and the account moved
        // whenever a group opened. As an inset they are the floor of the
        // sidebar and the list scrolls under them.
        //
        // The offer sits below the account on purpose. The account is a control
        // the developer uses, the offer is something the app is asking for, and
        // the thing being asked for does not get to sit closer to the work.
        ScrollViewReader { proxy in
            List(selection: selection) {
                AppsSection(isOpen: $appsOpen)

                ForEach(SidebarSection.allCases.filter { $0.mode == state.mode }) { section in
                    let rows = Destination.rows(in: section, hasApp: !state.hasNoOpenApp)
                    if !rows.isEmpty {
                        if section.showsHeader(in: state.mode) {
                            Section(isExpanded: isOpen(section)) {
                                ForEach(rows) { DestinationRow(destination: $0) }
                            } header: {
                                GroupHeader(title: section.title, isOpen: isOpen(section))
                            }
                        } else {
                            // No heading, so nothing to press to collapse it,
                            // and nothing to collapse it away from: it is the
                            // only group the job has.
                            Section {
                                ForEach(rows) { DestinationRow(destination: $0) }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            // The scroll ends above the floor, so the last row can be reached
            // and nothing sits under the footer for good.
            .safeAreaPadding(.bottom, footerHeight)
            .safeAreaPadding(.top, switchHeight)
            .overlay(alignment: .bottom) { footer }
            .overlay(alignment: .top) { modeSwitch }
            .task(id: selection.wrappedValue) {
                guard let destination = selection.wrappedValue,
                      destination.mode == .managing else { return }
                await Task.yield()
                proxy.scrollTo(destination, anchor: .center)
            }
        }
    }

    /// The two jobs, pinned to the head of the column.
    ///
    /// An overlay for the same reason the footer is one: `NavigationSplitView`
    /// gives its sidebar column to a list and to nothing else, so wrapping the
    /// list in a `VStack` to seat a control above it draws no column at all.
    private var modeSwitch: some View {
        VStack(spacing: 0) {
            ModeSwitch()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The rows scroll under this, so it cannot be transparent.
        .background(.thickMaterial)
    }

    /// Enough for the switch and the rule under it. Through `Theme.scaled`,
    /// because the switch is text.
    private var switchHeight: CGFloat { Theme.scaled(38) }

    /// Enough for the account row, and for the offer when it shows.
    ///
    /// ponytail: a measured constant, not a `GeometryReader` reading the
    /// overlay back into the margin. The footer is two known controls; when it
    /// grows a third, measure it again.
    ///
    /// Through `Theme.scaled`, because both controls are text and the reserve
    /// has to move with the type. Left fixed, a larger font makes the footer
    /// taller than the room kept for it and the last row hides underneath.
    private var footerHeight: CGFloat {
        Theme.scaled(state.showsUpgradeCard ? 132 : 44)
    }

    /// The account, then the offer, pinned to the floor of the column.
    ///
    /// An overlay and not a `VStack` or a `safeAreaInset`. Both of those wrap
    /// the list, and `NavigationSplitView` gives its sidebar column to a list
    /// and to nothing else: with either one the column drew nothing at all and
    /// the detail pane lost its header off the top of the window. Tried,
    /// photographed, and tried again after the switcher changed. An overlay
    /// leaves the list as the column and draws on top of it.
    ///
    /// The offer sits below the account on purpose. The account is a control
    /// the developer uses; the offer is something the app is asking for, and
    /// the thing being asked for does not get to sit closer to the work.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                AccountControl()
                Spacer(minLength: 0)
                SettingsButton()
            }
            .padding(.horizontal, 10)
            if state.showsUpgradeCard {
                UpgradeCard()
                    .padding(.horizontal, 10)
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The rows scroll under this, so it cannot be transparent.
        .background(.thickMaterial)
    }
}

/// The apps, as a group that opens and closes like the three below it.
///
/// It was a pull-down button. A pull-down says "one of these" in the smallest
/// space, which was right while the apps sat in a `safeAreaInset` that could
/// hold one control. Now that every other group is a list that opens, an app
/// list that hides behind a click is the odd one out, and the developer who
/// wants to see what they have linked has to press something to find out.
///
/// The row is not selectable. `List` selection means "the destination you are
/// on", and the app being worked on is another level of the same hierarchy: a
/// tick marks the current one, the way a pull-down marked it.
private struct AppsSection: View {
    @Environment(AppState.self) private var state
    @Binding var isOpen: Bool

    var body: some View {
        Section(isExpanded: $isOpen) {
            ForEach(Array(state.appRows.enumerated()), id: \.element.id) { index, app in
                Button {
                    state.selectApp(at: index)
                } label: {
                    HStack(spacing: 7) {
                        AppIconBadge(icon: app.icon, initials: app.initials, size: 16)
                        Text(app.name).lineLimit(1)
                        Spacer(minLength: 6)
                        // Where App Store review has this app, before it is
                        // opened. Every rule about a review used to read the
                        // open app alone, so a developer with six linked apps
                        // opened each one to find out which were frozen.
                        if let mark = state.appReviewMark(appKey: app.appleAppID ?? "") {
                            Text(mark.text)
                                .font(Theme.font(size: 9.5, weight: .medium))
                                .foregroundStyle(mark.colour)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(mark.colour.opacity(0.14), in: Capsule())
                                .accessibilityLabel("App Store: \(mark.text)")
                        }
                        if index == state.selectedAppIndex {
                            Image(systemName: "checkmark")
                                .font(Theme.font(size: 10, weight: .semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // The two actions that belong to one app, on that app. They
                // were in the pull-down, where they read as actions on
                // "whichever app is current" and could be pressed while
                // looking at another one.
                .contextMenu {
                    Button("Update from the Stores…") {
                        state.selectApp(at: index)
                        state.showExistingAppImport = true
                    }
                    Divider()
                    Button("Remove from Super Submitter…") { state.askToRemoveApp(at: index) }
                }
                .accessibilityAddTraits(index == state.selectedAppIndex ? [.isSelected] : [])
            }

            // The entry screen, not a folder picker. "Add App" is the question
            // "what do I want to do", and the entry screen is where that
            // question is already answered three ways.
            Button { state.showEntryScreen = true } label: {
                Label("Add App…", systemImage: "plus")
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } header: {
            GroupHeader(title: "Apps", isOpen: $isOpen)
        }
    }
}

/// The heading of a sidebar group, and the whole of it opens and closes the
/// group.
///
/// `Section(_:isExpanded:)` draws the title itself and hands the opening to the
/// disclosure control alone, so the word "Publish" was inert: the obvious
/// target did nothing and the only one that worked was a chevron that is not
/// drawn until the pointer is over the row. A developer who clicked the name
/// got no answer and no reason.
private struct GroupHeader: View {
    let title: String
    @Binding var isOpen: Bool

    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { isOpen.toggle() }
            // The strip the system draws its own disclosure control in stays
            // clear. Covering it would let one click reach both targets and
            // toggle the group twice, which breaks the one way in that worked.
            .padding(.trailing, 28)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOpen ? "Open" : "Closed")
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

    /// The two halves of a run, in the order they happen.
    private var runStatuses: [(job: String, symbol: String, status: BuildSidebarStatus)] {
        guard destination.tab == .build else { return [] }
        let flow = state.buildFlow
        return [("Build", "hammer.fill", flow.artifactStatus),
                ("Upload", "arrow.up.circle.fill", flow.uploadStatus)]
            .compactMap { job, symbol, status in
                status.map { (job, symbol, $0) }
            }
    }

    private var accessibilityValue: String {
        (runStatuses.map { $0.status.spoken($0.job) }
            + [state.badge(for: destination.tab)?.spoken])
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var iconStyle: AnyShapeStyle {
        if marksTheHazard { return AnyShapeStyle(Theme.red) }
        if selected { return AnyShapeStyle(Theme.accentText) }
        return AnyShapeStyle(.tint)
    }

    var body: some View {
        HStack(spacing: 0) {
            Label {
                HStack(spacing: 5) {
                    Text(destination.title)
                    ForEach(runStatuses, id: \.job) { run in
                        BuildSidebarStatusView(symbol: run.symbol, status: run.status)
                            .accessibilityHidden(true)
                    }
                }
            } icon: {
                Image(systemName: destination.tab.symbol)
                    .foregroundStyle(iconStyle)
            }
            Spacer(minLength: 8)
            if let badge = state.badge(for: destination.tab) {
                BadgeView(badge: badge, size: 16)
            }
        }
        .tag(destination)
        .accessibilityValue(accessibilityValue)
    }
}

/// One job of a run: its own glyph, and the colour of how it went.
///
/// The glyph says which job, the colour says the outcome, so the two
/// indicators stay legible beside each other. A tick for both would need the
/// reader to remember which position meant which job.
private struct BuildSidebarStatusView: View {
    let symbol: String
    let status: BuildSidebarStatus

    private var tint: Color {
        switch status {
        case .running: Theme.accent
        case .succeeded: Theme.green
        case .failed: Theme.red
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(Theme.font(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .symbolEffect(.pulse, isActive: status == .running)
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
            .font(Theme.font(size: 13, weight: .semibold))
        }
        // `.button`, and the default style drew the app icon at the size of
        // the whole sidebar. A macOS `Menu` in its default style hands its
        // label to AppKit, which sizes an image itself and ignores the frame
        // SwiftUI put on it, so an 18 point badge came out 200 points wide,
        // clipped at the column edge, with the app name pushed off the end.
        // The button style keeps the label in SwiftUI, where a frame is a
        // frame.
        .menuStyle(.button)
        .buttonStyle(.accessoryBar)
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
                    .font(Theme.font(size: 15))
                    .foregroundStyle(.secondary)
                Text(label).lineLimit(1).truncationMode(.middle)
            }
            .font(Theme.font(size: 12.5))
        }
        .controlSize(.small)
        .accessibilityLabel("Account")
        .accessibilityValue(label)
    }
}

/// The way into Settings that is on the screen.
///
/// It was in the app menu alone, at ⌘,. That is where a Mac keeps Settings and
/// it stays there, but the app menu is not a place a developer looks while they
/// are working, and every other panel in this app has a control that opens it.
/// A window whose only route to its own settings is a menu bar reads as a
/// window with no settings.
///
/// Beside the account and not among the navigation rows. Settings is not a
/// destination: it opens a panel over the window, the same way About does, and
/// a row in a `List` that opens a sheet is a row that lies about where it goes.
/// That was the objection to the old Settings row, and it still stands.
private struct SettingsButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button { state.showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(Theme.font(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        // The shortcut sits in the tooltip, so the button teaches the faster
        // way to what it does. See the field search glyph in the header.
        .help("Settings  ⌘,")
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

    /// A sentence and a button, and nothing else.
    ///
    /// It carried a bolt in a tinted chip and the product name over a
    /// two-sentence paragraph that listed the four things this app gives away.
    /// Three rows of card to make one offer, and the loudest row was a name the
    /// window already wears. A call to action is one line and one button: the
    /// line says what is withheld, the button opens the plans.
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(line)
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                // A `List` row proposes its own width to a `Text` before it
                // proposes the column's, and `fixedSize` then held the line at
                // one line and truncated it. This asks for the row's width
                // first, so the sentence wraps instead of ending in an ellipsis.
                .frame(maxWidth: .infinity, alignment: .leading)
            // The route the gates already use. It does not introduce a second
            // purchase path.
            Button { state.openPaywall(.settings) } label: {
                Text("See the plans")
                    .font(Theme.font(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(line)
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
                    .font(Theme.font(size: size * 0.4, weight: .medium))
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

    /// Sized here, on the `NSImage`, and not by `.resizable()` and a frame.
    ///
    /// A macOS `Menu` hands its label to AppKit, and AppKit draws an image at
    /// the image's own size. The SwiftUI frame around it is not consulted, so
    /// an 18 point badge came back 200 points wide, clipped at the edge of the
    /// sidebar, with the app name pushed off the end of the row. Every screen
    /// opened with a band of app icon where the app switcher should be.
    ///
    /// An `NSImage` carries its own size, every renderer reads it, and the
    /// frame below still holds for the layout. So this is one size stated in
    /// two places that cannot disagree, rather than one that AppKit ignores.
    private var image: NSImage? {
        guard let icon, FileManager.default.fileExists(atPath: icon.path),
              let image = NSImage(contentsOf: icon) else { return nil }
        image.size = NSSize(width: size, height: size)
        return image
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
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
        // One read of the stores changes every badge in the column at once,
        // and they used to appear and vanish between frames. A pill arriving
        // beside a navigation row is the app saying "this tab now blocks your
        // apply", which is the single most consequential thing the sidebar
        // ever says, and it said it without a sound.
        .motion(.snappy(duration: 0.24), value: badge)
    }

    private func pill(_ count: Int, _ severity: Severity) -> some View {
        // Verbatim, so a locale that groups thousands cannot turn a count
        // into "1.242". See the Details counter for the same reason.
        Text(verbatim: "\(count)")
            .font(Theme.font(size: size * 0.65, weight: .semibold))
            .foregroundStyle(severity.color)
            // The count moves as findings are fixed one at a time, and
            // proportional digits shifted the pill's width under the row.
            .monospacedDigit()
            .contentTransition(.numericText())
            .padding(.horizontal, 4)
            .frame(minWidth: size, minHeight: size)
            .background(severity.background, in: Capsule())
            // It grows out of the row rather than being painted onto it. The
            // scale is from the middle, so a pill that leaves collapses into
            // the space it held instead of blinking out of it.
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }
}

/// The two jobs, as one control.
///
/// It sits above the groups, because it decides which groups exist. A publisher
/// sends a version; a manager runs the app that is already out there.
///
/// It was removed when every group went into the column at once, so that no
/// half of the app hid behind a control that named neither. The groups name
/// both halves now, which is what made this safe to bring back: the switch
/// picks which of two named jobs the column shows, and the column is the four
/// or the eight rows of that job rather than all twelve.
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
            .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
    }
}

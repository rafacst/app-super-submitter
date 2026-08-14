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
                // The apps were a group here. They are the tab bar across the
                // top of the window now: see `AppTabBar`. The column is one
                // level of the hierarchy again, which is the screens of the app
                // the bar has selected.

                // Every group wears its heading, including a job that has only
                // one. Manage was the lone group of its job and drew none, so
                // its four rows stood loose under the app list with nothing
                // naming them, and the group could not be collapsed at all:
                // the heading is the control that folds it.
                let sections = SidebarSection.allCases.filter { $0.mode == state.mode }
                ForEach(sections) { section in
                    let rows = Destination.rows(in: section, hasApp: !state.hasNoOpenApp)
                    if !rows.isEmpty {
                        Section(isExpanded: isOpen(section)) {
                            ForEach(rows) { DestinationRow(destination: $0) }
                        } header: {
                            // No rule on the first one: the mode switch draws
                            // its own directly above it. The Apps group used to
                            // be the first and carried this; with the apps in
                            // the tab bar the rule belongs to whichever group
                            // now leads the column.
                            GroupHeader(title: section.title, isOpen: isOpen(section),
                                        rule: section != sections.first)
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
                      destination.tab.isListed,
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

    /// Enough for the three rows about this Mac, and for the offer when it
    /// shows.
    ///
    /// ponytail: a measured constant, not a `GeometryReader` reading the
    /// overlay back into the margin. The footer is a known set of rows; when it
    /// grows another one, measure it again.
    ///
    /// Through `Theme.scaled`, because every row is text and the reserve has to
    /// move with the type. Left fixed, a larger font makes the footer taller
    /// than the room kept for it and the last row hides underneath.
    private var footerHeight: CGFloat {
        Theme.scaled(state.showsUpgradeCard ? 190 : 102)
    }

    /// This Mac, then the offer, pinned to the floor of the column.
    ///
    /// Three rows and not one control. The groups above are the steps of one
    /// app's submission, and these three are answered once for the whole
    /// machine: the store keys, what this program does on it, and who is signed
    /// in. Stores used to head the Publish group and the Manage group both,
    /// which is one screen listed twice in a column whose selection can only
    /// stand on one of them, and Settings was a gear with no word beside it.
    ///
    /// An overlay and not a `VStack` or a `safeAreaInset`. Both of those wrap
    /// the list, and `NavigationSplitView` gives its sidebar column to a list
    /// and to nothing else: with either one the column drew nothing at all and
    /// the detail pane lost its header off the top of the window. Tried,
    /// photographed, and tried again after the switcher changed. An overlay
    /// leaves the list as the column and draws on top of it.
    ///
    /// The offer sits below all of it on purpose. These are controls the
    /// developer uses; the offer is something the app is asking for, and the
    /// thing being asked for does not get to sit closer to the work.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .padding(.bottom, 6)
            FooterRow(tab: .stores)
            FooterRow(tab: .settings)
            AccountControl()
            if state.showsUpgradeCard {
                UpgradeCard()
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The rows scroll under this, so it cannot be transparent.
        .background(.thickMaterial)
    }
}

/// One destination in the box at the foot of the column.
///
/// It draws its own selected band, which every row inside the `List` above is
/// forbidden to do. The reason that rule exists is that a hand-drawn band
/// beside the system's is a second answer to a question already answered; down
/// here there is no system answer, because a `List` selection reaches its own
/// rows and nothing else. Without a band, opening Settings left the whole
/// sidebar looking as though nothing was open.
///
/// The fill is the app's accent at the corner radius the mode switch uses, so
/// the two hand-drawn selections in this column are the same shape.
private struct FooterRow: View {
    @Environment(AppState.self) private var state
    let tab: Tab

    private var selected: Bool { state.selectedTab == tab && !state.showsEntryScreen }

    var body: some View {
        Button {
            // The tab is about the Mac and not about an app, so it opens over
            // the entry screen rather than waiting for a folder to be picked.
            state.showEntryScreen = false
            state.selectedTab = tab
        } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.symbol)
                    .font(Theme.font(size: 12))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.accentText)
                                              : AnyShapeStyle(.tint))
                    .frame(width: 17)
                Text(tab.title)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(selected ? Theme.accentText : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(selected ? Theme.accent : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Where the stores have one app, beside the name it belongs to.
///
/// It follows the name and takes only the width of its own word. The chip
/// answers a question about that app, so it reads as part of that row rather
/// than as a column the eye has to carry across. The name truncates before the
/// chip does: a row that runs out of room loses letters of a name the tooltip
/// still carries, not the state word the list exists to show.
///
/// Every row wears one, and an app nobody has read yet wears "Unknown". A blank
/// says nothing at all, and the row it sat on could be an app with no news or
/// an app this Mac has never asked about. See `appMark`.
struct AppStatusChip: View {
    let mark: AppleStanding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 4) {
            // The one state worth an animation. A reviewer has the app open,
            // it is the state a developer refreshes the sidebar to see, and it
            // is the only one of the fifteen that changes within the hour.
            if mark.active {
                Circle()
                    .fill(mark.tint)
                    .frame(width: 5, height: 5)
                    .opacity(dim ? 0.3 : 1)
                    .animation(reduceMotion ? nil
                               : .easeInOut(duration: 0.9).repeatForever(),
                               value: dim)
                    .onAppear { dim = true }
            }
            Text(mark.label)
                .font(Theme.font(size: 9.5, weight: .medium))
                .foregroundStyle(mark.tint)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(mark.fill, in: Capsule())
        .accessibilityElement(children: .combine)
        // The store is not named. The chip answers for both of them now, and
        // an app that goes to Google alone was told what the App Store thinks
        // of it.
        .accessibilityLabel("On the store: \(mark.label)")
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
    /// The rule above the heading. Every group draws one except the first,
    /// which has the mode switch above it instead.
    var rule = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The groups are the steps of a submission and they read as one
            // list of ten rows: four headings in the quietest tier the app has,
            // separated by nothing, and a group that folds shut left its
            // neighbour's rows sitting directly under its title. The floor of
            // the column already draws this rule above the three rows that
            // belong to the Mac rather than to the app, so the sidebar now
            // divides its groups the way it already divided its footer.
            if rule {
                Divider()
                    .padding(.trailing, 6)
                    .padding(.bottom, 7)
            }
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                // Through `withMotion`, so the rows slide rather than vanish.
                // `Section(isExpanded:)` animates the fold when its own
                // disclosure control drives it, and this binding is set from a
                // tap gesture, which carries no animation of its own.
                .onTapGesture {
                    withMotion(reduceMotion, .easeInOut(duration: 0.22)) { isOpen.toggle() }
                }
                // The strip the system draws its own disclosure control in
                // stays clear. Covering it would let one click reach both
                // targets and toggle the group twice, which breaks the one way
                // in that worked.
                .padding(.trailing, 28)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isOpen ? "Open" : "Closed")
        }
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

/// Who is signed in, and the actions that belong to them.
///
/// A menu and not a row, alone among the three in this box. Stores and Settings
/// are one destination each; this one carries Sign Out as well, and it says the
/// address you are signed in under rather than the word "Account". Both of
/// those are answers a row cannot hold.
///
/// The button says the account, because that is the level of the hierarchy it
/// sits at. The Account screen is still a screen, and this is the way in.
private struct AccountControl: View {
    @Environment(AppState.self) private var state

    private var label: String { state.accountEmail ?? "Not signed in" }

    private var selected: Bool {
        state.selectedTab == .account && !state.showsEntryScreen
    }

    var body: some View {
        Menu {
            Button("Account") {
                state.showEntryScreen = false
                state.selectedTab = .account
            }
            if state.showsUpgradeCard {
                Button("See the Plans…") { state.openPaywall(.settings) }
            }
            if state.accountEmail != nil {
                Divider()
                Button("Sign Out") { state.signOutOfBilling() }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: Tab.account.symbol)
                    .font(Theme.font(size: 12))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.accentText)
                                              : AnyShapeStyle(.tint))
                    .frame(width: 17)
                Text(label)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(selected ? Theme.accentText : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                // The indicator, drawn rather than asked for. `menuIndicator`
                // is honoured by the styles that draw a bezel, and this one has
                // none, so the row would otherwise look exactly like the two
                // destinations above it and open a menu instead.
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.font(size: 8, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accentText : Theme.text3)
            }
        }
        // No bezel. The two rows above it are plain, and a bordered control
        // between them and the offer card read as a third kind of thing in a
        // box of three of one kind.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(selected ? Theme.accent : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 3)
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

    /// A sentence and a button, and nothing else.
    ///
    /// It carried a bolt in a tinted chip and the product name over a
    /// two-sentence paragraph that listed the four things this app gives away.
    /// Three rows of card to make one offer, and the loudest row was a name the
    /// window already wears. A call to action is one line and one button: the
    /// line says what is withheld, the button opens the plans.
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // The headline carries the developer's own work, so it is the
            // loudest thing on the card. The promise under it is quiet and
            // never absent: see `AppState.upgradeCardNote`.
            Text(line)
                .font(Theme.font(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(state.upgradeCardNote)
                .font(Theme.font(size: 10.5))
                .foregroundStyle(Theme.text3)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                // A `List` row proposes its own width to a `Text` before it
                // proposes the column's, and `fixedSize` then held the line at
                // one line and truncated it. This asks for the row's width
                // first, so the sentence wraps instead of ending in an ellipsis.
                .frame(maxWidth: .infinity, alignment: .leading)
            // The route the gates already use. It does not introduce a second
            // purchase path.
            // A verb, and the verb the headline just named. "See the plans"
            // invites browsing, and a developer holding a release does not want
            // a price list, they want the send.
            Button { state.openPaywall(.settings) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "paperplane.fill")
                        .font(Theme.font(size: 10, weight: .semibold))
                    Text("Get Pro")
                        .font(Theme.font(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(state.upgradeCardNote)
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

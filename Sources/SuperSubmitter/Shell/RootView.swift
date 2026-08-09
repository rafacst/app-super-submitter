import SubmitKit
import SwiftUI

/// The shell. Spec section 16.1.
///
/// A `NavigationSplitView`, and it was an `HStack` of a floating panel and a
/// pane. The panel was the reason for three pieces of hand-work that have all
/// gone with it: the window buttons had to be nudged in by a `NSViewRepresentable`
/// because the panel was inset from the corner they pin to, the top safe area
/// had to be ignored so the panel could carry them, and the sidebar had a
/// width in points rather than a range a user may drag.
///
/// The split view gives the divider, the drag, the collapse, the vibrancy, and
/// the window buttons in the place AppKit already puts them.
struct RootView: View {
    @Environment(AppState.self) private var state
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// The sidebar may be hidden, and the shell remembers whether it is.
    @State private var columns = NavigationSplitViewVisibility.automatic

    var body: some View {
        @Bindable var state = state
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                // A range, not a number. The old column was 240 points and no
                // other width was reachable.
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            ContentArea()
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.content)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13))
        // Every sheet carries the message alert. See AppMessage: an alert on
        // this view alone cannot appear while a sheet covers it.
        .sheet(isPresented: $state.showSettings) { SettingsPanel().appMessage() }
        .sheet(isPresented: $state.showAbout) { AboutPanel().appMessage() }
        .sheet(isPresented: $state.showOnboarding, onDismiss: { hasSeenOnboarding = true }) {
            OnboardingPanel().appMessage()
        }
        .sheet(isPresented: $state.showExistingAppImport) {
            ExistingAppImportSheet().appMessage()
        }
        .sheet(item: $state.releaseSheet) { store in ReleaseSheet(store: store).appMessage() }
        .sheet(isPresented: $state.showAddLocale) { AddLocaleSheet().appMessage() }
        .sheet(isPresented: $state.showFieldSearch) { FieldSearchSheet().appMessage() }
        .confirmationDialog("Remove \(state.removalName) from Super Submitter?",
                            isPresented: Binding(
                                get: { state.appPendingRemoval != nil },
                                set: { if !$0 { state.appPendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { state.removePendingApp() }
            Button("Cancel", role: .cancel) { state.appPendingRemoval = nil }
        } message: {
            Text("Super Submitter forgets this app. The store.yaml file, the store keys in your Keychain, and both store listings stay as they are.")
        }
        .appMessage()
        // Coming back from the browser lands here, and so does waking from
        // sleep. The refresh is what unlocks the app after a checkout; the
        // browser return itself proves nothing.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await state.refreshEntitlement() }
        }
    }
}

/// The content column: the header, then the tab.
private struct ContentArea: View {
    @Environment(AppState.self) private var state
    /// True once the tab has content passing under the header.
    ///
    /// The band used to draw a rule at all times, so a tab of two sentences
    /// carried the same divider as a tab of forty fields. The rule now says
    /// what a rule is for: there is more above.
    @State private var scrolled = false
    /// Whether the Details inspector is showing. It outlives a relaunch, the
    /// way every inspector on the Mac does.
    @AppStorage("detailsInspector") private var detailsInspectorOpen = true
    /// The same, for the reference boxes beside the build.
    @AppStorage("buildInspector") private var buildInspectorOpen = true

    var body: some View {
        VStack(spacing: 0) {
            // No band on the entry screen. It carries no title, no question
            // and no controls there, so it drew 64 points of empty glass over
            // a screen whose whole job is one centred choice — and the traffic
            // lights sit on the sidebar panel, not here, so nothing needs the
            // room.
            if !state.showsEntryScreen { ContentHeader(scrolled: scrolled) }
            if state.showsLiveWriteWarning { LiveWriteBar(); Hairline() }
            if state.showsEntryScreen {
                EmptyAppView()
            } else {
                tabScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
        // A new tab starts at the top, so the rule starts off.
        .onChange(of: state.selectedTab) { scrolled = false }
    }

    @ViewBuilder
    private var tabScroll: some View {
        let scroll = ScrollViewReader { proxy in
            ScrollView {
                TabContent(tab: state.selectedTab)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The band above is glass, so it refracts whatever passes under
            // it. Without this the first line of the scroll meets that glass
            // at a hard boundary and reads as a line cut in half.
            .softScrollEdge()
            .onChange(of: state.jumpTarget) { _, target in
                guard let target else { return }
                state.jumpTarget = nil
                // A connected store folds its credential away, and the two key
                // fields are in the fold. Scrolling to an anchor inside a
                // collapsed card lands on nothing, silently, which is the one
                // failure `FieldIndex` exists to prevent.
                state.revealCredentialDetails(forAnchor: target)
                // One turn of the loop, so the new tab has drawn and the
                // anchor exists. Scrolling into a tab that has not rendered
                // does nothing, silently.
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(FieldAnchor(id: target), anchor: .top)
                    }
                }
            }
        }
        .background(Theme.content)
        // Outside the ScrollView on purpose: an inspector inside one scrolls
        // away with the content it is meant to sit beside.
        // One inspector, not one per tab. Two `.inspector` modifiers on the
        // same view give two trailing columns, and the second one wins the
        // width while the first keeps the space.
        .inspector(isPresented: Binding(
            get: {
                switch state.selectedTab {
                case .details: detailsInspectorOpen
                case .build: buildInspectorOpen
                default: false
                }
            },
            set: { open in
                switch state.selectedTab {
                case .details: detailsInspectorOpen = open
                case .build: buildInspectorOpen = open
                default: break
                }
            })) {
            Group {
                switch state.selectedTab {
                case .details: DetailsInspector()
                case .build: BuildInspector()
                default: Color.clear
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }

        // macOS 14 keeps the rule on at all times. There is no way to read the
        // offset there without an NSScrollView of our own, and a permanent
        // hairline is the state the app already shipped.
        if #available(macOS 15.0, *) {
            scroll.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 2
            } action: { _, isScrolled in
                guard scrolled != isScrolled else { return }
                // A bare assignment, and `HeaderSurface` animates the one thing
                // that reads it.
                //
                // This was `withAnimation`, which is a *global* transaction: it
                // animates every view SwiftUI updates in that pass, not the
                // property in the braces. It fires the instant a scroll view
                // first reports its geometry, which on a first run is the same
                // pass that inserts the whole tab — the app has no linked app
                // at launch, links one, and rebuilds the sidebar, the header
                // and the tab together. All of it went into a 0.14 second
                // animation and slid into place from wherever SwiftUI had last
                // measured it, which is why panel contents rose up the screen
                // on first launch and never again.
                scrolled = isScrolled
            }
        } else {
            scroll.onAppear { scrolled = true }
        }
    }
}

/// The strip that says a store write is armed.
///
/// The switch that arms it sits on the Summary tab, and its consequence
/// reaches every tab, so the state has to be readable from every tab. A
/// developer could reach Submit without ever having seen the switch.
///
/// Yellow and not red. The apply writes drafts, and red says irreversible in
/// this app, which the Release tab owns alone.
private struct LiveWriteBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
            Text("The dry run is off. An apply writes to \(state.storeListText).")
                .font(.system(size: 11.5, weight: .medium))
            Spacer(minLength: 8)
            Button("Turn the dry run on") { state.dryRun = true }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .underline()
        }
        .foregroundStyle(Theme.yellow)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.yellowBg)
        .accessibilityElement(children: .contain)
    }
}

private struct EmptyAppView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            // The two Spacers hold the block in the middle of the pane. Without
            // them the cards take every spare point of height and grow into two
            // empty columns.
            Spacer(minLength: 40)

            HStack(spacing: 18) {
                storeTile(.apple)
                Circle().fill(Theme.sep).frame(width: 6, height: 6)
                storeTile(.google)
            }
            .padding(.bottom, 26)

            Text(state.mode == .publishing
                 ? "Point Super Submitter at your app"
                 : "Bring in the app you want to manage")
                .font(.system(size: 25, weight: .semibold))
                .kerning(-0.4)
            Text(state.mode == .publishing
                 ? "Pick the folder your app is built in. We read the build and keep one small file beside it."
                 : "Managing works on a live app. Connect your store accounts and import the one you want to look after.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 520)
                .padding(.top, 9)

            // Both doors import an app; the mode decides what the app then
            // shows. A manager needs the live one, so that door comes first
            // and the new-app door does not appear at all.
            HStack(spacing: 18) {
                if state.mode == .publishing {
                    EntryModeCard(symbol: "paperplane.fill", title: "Submit a new app",
                                  detail: "Choose its project folder and prepare a fresh store submission.",
                                  tint: Theme.accent, action: state.chooseAppFolder)
                }
                EntryModeCard(symbol: "arrow.triangle.2.circlepath",
                              title: state.mode == .publishing
                                  ? "Update existing apps" : "Bring in a live app",
                              detail: state.mode == .publishing
                                  ? "Connect your store accounts, select one or many apps, and import their current data."
                                  : "Connect your store accounts and pick the apps you look after. The reviews, the numbers, and the pages all follow.",
                              tint: Theme.teal) {
                    state.showExistingAppImport = true
                }
            }
            .frame(maxWidth: state.mode == .publishing ? 760 : 380)
            .padding(.top, 32)

            // What the app cannot do, before the developer invests a folder in
            // it and not after. Some store steps have no API at all, and the
            // old flow revealed that on the Release tab, at the end, once
            // every in-app step was already finished.
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle").font(.system(size: 11))
                Text("Some store steps have no API. Super Submitter writes every draft it can, then lists the ones you finish in the store console yourself.")
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.text2)
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 26)
            .accessibilityElement(children: .combine)

            // The entry screen offers the doors that start work. Opening a
            // store.yaml continues work that already exists, so it lives in
            // the File menu with the rest of the file commands.

            // The way back, for a developer who opened this over an app they
            // already had. Without it "Add app" is a one-way door.
            if state.showEntryScreen, let open = state.currentApp {
                QuietButton(title: "Back to \(open.name)") { state.showEntryScreen = false }
                    .padding(.top, 26)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }

    private func storeTile(_ store: Store) -> some View {
        StoreMark(store: store, size: 38)
            .frame(width: 62, height: 62)
            .background(store.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(store.tint.opacity(0.28), lineWidth: 1))
    }
}

private struct EntryModeCard: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let action: () -> Void
    /// The tint belongs to the card while the pointer is on it, and not
    /// before.
    ///
    /// Both cards drew a border in their own hue at rest, so the blue one read
    /// as the chosen card on a screen where nothing is chosen yet — the same
    /// signal the app uses for a selected sidebar row and a ticked store. At
    /// rest they are two equal doors; the hover says which one you are about
    /// to open.
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                IconChip(symbol: symbol, tint: tint, size: 52)
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Label("Continue", systemImage: "arrow.right")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(20)
            // A fixed height, so the pane cannot stretch the card and the two
            // cards stay level whatever their text length.
            .frame(maxWidth: .infinity, minHeight: 236, maxHeight: 236,
                   alignment: .topLeading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hovering ? tint.opacity(0.55) : Theme.sep,
                              lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.18), value: hovering)
        .accessibilityHint(detail)
    }
}

/// The band above every tab. It carries the title, the one-line question, and
/// the controls that belong to the tab on the right. `Theme.headerHeight` sets
/// its height.
private struct ContentHeader: View {
    @Environment(AppState.self) private var state
    @AppStorage("showYAMLToggle") private var yamlToggleVisible = false
    @AppStorage("detailsInspector") private var detailsInspectorOpen = true
    @AppStorage("buildInspector") private var buildInspectorOpen = true
    /// Whether content is passing underneath. See ContentArea.
    let scrolled: Bool
    /// Whether the question that arms a store write is open.
    ///
    /// The switch used to arm on one click. The strip below the header says
    /// the state afterwards, which is the right place for a state, but nothing
    /// stood between the click and the consequence — and the consequence is
    /// that the next apply stops being a rehearsal and starts writing to two
    /// live stores.
    @State private var armingLiveWrites = false

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 10) {
            // The entry screen carries its own headline, in the size a
            // headline wants. The band used to carry a second one over it, so
            // one screen asked the same question twice in two voices.
            if !state.showsEntryScreen {
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.selectedTab.title(in: state.mode))
                        .font(Theme.screenTitle)
                        .kerning(-0.21)
                    Text(state.selectedTab.question)
                        .font(Theme.screenSubtitle)
                        .foregroundStyle(Theme.text2)
                }
            }
            Spacer(minLength: 8)

            // Every editing tab shows its own block of store.yaml. Spec 16.1.
            // Settings hides the toggle, because most work never needs it.
            if yamlToggleVisible, state.manifestURL != nil, state.yamlBlock != nil {
                Button {
                    state.showYAML.toggle()
                } label: {
                    Text("YAML")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(state.showYAML ? Theme.accentText : Theme.text2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(state.showYAML ? Theme.accent : Theme.field,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the raw YAML")
                .accessibilityValue(state.showYAML ? "On" : "Off")
            }

            // The save, where a save belongs: beside the work, for as long as
            // it is news. It used to be a permanent line at the foot of the
            // navigation column, which gave a status the weight of a
            // destination and told you at every moment about a moment that had
            // passed.
            SavedChip()

            let shape = HeaderShape(tab: state.selectedTab, busy: state.rechecking,
                                    readFailed: state.planError != nil,
                                    pendingRelease: state.hasPendingRelease,
                                    locales: state.locales.count)

            // Light and dark, one click away, on every screen. It sits before
            // the search glyph and outside the `manifestURL` guard below:
            // reading a screen is the one thing a person does whether an app is
            // linked or not, so the control that decides how a screen reads
            // cannot depend on one.
            HeaderCluster(morphOn: shape) { AppearanceSwitch() }

            // The palette, with a way in that is not the menu bar.
            //
            // It was reachable at Command-F and from Edit, and nowhere on the
            // screen said so. It is the fastest thing in the app — it finds a
            // field across nine tabs and scrolls to it — and a developer who
            // never opens a menu never learns it exists. The shortcut sits in
            // the tooltip, so the button teaches its own replacement.
            if state.manifestURL != nil {
                HeaderCluster(morphOn: shape) {
                    Button { state.showFieldSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 24, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Find a field")
                    .help("Find a field  ⌘F")
                }
            }

            if state.manifestURL != nil { switch state.selectedTab {
            case .build:
                HeaderCluster(morphOn: shape) {
                    Button { buildInspectorOpen.toggle() } label: {
                        Image(systemName: "sidebar.trailing")
                            .font(.system(size: 13))
                            .foregroundStyle(buildInspectorOpen ? Theme.accent : Theme.text2)
                            .frame(width: 24, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("The stores, the workflows, and the identities")
                    .accessibilityValue(buildInspectorOpen ? "Showing" : "Hidden")
                    .help("Show or hide the diagnostics, Xcode Cloud, and signing")
                }
            case .details:
                HeaderCluster(morphOn: shape) { LocalePicker() }
                HeaderCluster(morphOn: shape) {
                    Button { detailsInspectorOpen.toggle() } label: {
                        Image(systemName: "sidebar.trailing")
                            .font(.system(size: 13))
                            .foregroundStyle(detailsInspectorOpen ? Theme.accent : Theme.text2)
                            .frame(width: 24, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What each store receives")
                    .accessibilityValue(detailsInspectorOpen ? "Showing" : "Hidden")
                    .help("Show or hide what each store receives")
                }
            case .media:
                LocalePicker()
            case .plan:
                // Two clusters, not one row of five things. Reading the stores
                // and arming a write are different jobs, and the gap between
                // the groups says so faster than the labels do.
                // Gone while the read has failed. The failure card carries its
                // own "Read again" next to the message that explains it, and
                // two buttons for one action, one of them 900 points from the
                // problem, is a choice the developer should not have to make.
                if state.planError == nil {
                    HeaderCluster(morphOn: shape) {
                        // No spinner here. The tab body already says "Reading
                        // both stores" beside one, and two spinners for one
                        // read read as two reads.
                        QuietButton(title: "Read the stores again", glass: true) {
                            Task { await state.readStores() }
                        }
                    }
                }
                HeaderCluster(morphOn: shape) {
                    Text("Dry run").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    // Turning the dry run off is the moment an apply becomes a
                    // store write, so that is where the paywall belongs, and
                    // where the question belongs. Turning it back on needs no
                    // question: that direction only ever makes the app safer.
                    SmallToggle(isOn: Binding(
                        get: { state.dryRun },
                        set: { value in
                            guard value || state.requirePaid(.storeWrite, .apply) else { return }
                            if value { state.dryRun = true } else { armingLiveWrites = true }
                        }))
                }
            case .release:
                HeaderCluster(morphOn: shape) {
                    if state.rechecking { Spinner() }
                    QuietButton(title: "Copy as checklist", glass: true) { state.copyChecklist() }
                    QuietButton(title: "Re-check", glass: true) { Task { await state.recheck() } }
                }
                // The tab asks "shall I send it?" in its own subtitle, and the
                // buttons that answer it sit below the fold. This says they
                // exist and takes you to them; it sends nothing itself, because
                // one button cannot stand for two stores and a send is the one
                // action in this app that may never happen by surprise.
                if state.hasPendingRelease {
                    HeaderCluster(morphOn: shape) {
                        QuietButton(title: "Send to review", glass: true, prominent: true) {
                            state.jumpTarget = ReleaseTab.sendAnchor
                        }
                    }
                }
            default:
                EmptyView()
            } }
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .frame(height: Theme.headerHeight)
        .confirmationDialog("Turn the dry run off?", isPresented: $armingLiveWrites,
                            titleVisibility: .visible) {
            Button("Turn it off", role: .destructive) { state.dryRun = false }
            Button("Keep the dry run on", role: .cancel) {}
        } message: {
            Text("The next apply writes drafts to \(state.storeListText) instead of logging them. It writes drafts only: nothing reaches review until you send it on the Release tab.")
        }
        // Below macOS 26 the band is the page at rest, and separates itself
        // only while there is something above the fold. On 26 the material
        // does that job. See HeaderSurface.
        .headerSurface(scrolled: scrolled)
    }
}

/// One group of related controls in the header.
///
/// It is the spacing that groups them, the way a macOS toolbar groups items.
/// A single run of five controls at one spacing reads as five equals.
///
/// On macOS 26 the group is also a `GlassEffectContainer`, so neighbours merge
/// into one lozenge instead of three. That is the same statement the spacing
/// was already making, said in the material.
///
/// `morphOn` carries the state that decides which controls are in the group.
/// The header changes its contents constantly — a spinner while a re-check
/// runs, the send action once a release is pending, the read button whenever a
/// read has not failed — and a lozenge that jumps to a new width on the frame
/// a control appears is the one thing this material exists not to do.
private struct HeaderCluster<Content: View>: View {
    var morphOn: HeaderShape = HeaderShape()
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 7) { content }
            .glassCluster(spacing: 7, morphOn: morphOn)
    }
}

/// Everything that changes which controls the header draws.
///
/// One value rather than four `animation(value:)` modifiers: the clusters
/// re-form as a group, so they have to be told as a group or two of them
/// animate on different clocks.
private struct HeaderShape: Equatable {
    var tab: Tab = .stores
    var busy = false
    var readFailed = false
    var pendingRelease = false
    var locales = 0
}

/// The language switch on tab 3 and tab 4.
private struct LocalePicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 6) {
            Text("Language").font(.system(size: 11)).foregroundStyle(Theme.text2)
            HStack(spacing: 0) {
                ForEach(state.locales, id: \.self) { code in
                    let selected = state.locale == code
                    Button {
                        state.locale = code
                    } label: {
                        Text(code)
                            .font(Theme.mono(11))
                            .foregroundStyle(selected ? Theme.accentText : Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selected ? Theme.accent : .clear)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(code)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .background(Theme.sunken)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))

            // Outside the group, and deliberately. Every segment inside it
            // picks the language you are editing; this one opens a sheet. A
            // command that sits among the choices reads as a fourth choice,
            // and a segmented control with a live segment is a lie about state.
            Button { state.showAddLocale = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a language")
            .help("Add a language")
        }
    }
}

/// The one message channel, presented wherever the user is actually looking.
///
/// `errorMessage` had a single presenter, on the root view. A sheet covers the
/// root, so an action taken inside Settings set the message and SwiftUI held
/// the alert back until that sheet closed. "Delete old run data" read as a
/// dead button, and its answer turned up minutes later attached to nothing the
/// user was doing. Nine sheets sit over this view, and every action taken from
/// inside one of them had the same fault.
///
/// So each sheet carries this too. Only one presentation is frontmost, that
/// one answers, and clearing the message means the root's copy never fires.
struct AppMessage: ViewModifier {
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        content.alert("Super Submitter", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

extension View {
    func appMessage() -> some View { modifier(AppMessage()) }
}

/// States that the work is on disk, for as long as that is news.
///
/// The app has no unsaved state to warn about: every field writes `store.yaml`
/// when it changes. This says so, because a form with no Save button reads as
/// a form that keeps nothing.
///
/// It used to be a row pinned to the foot of the sidebar, under a rule, at all
/// times. That is a status with the weight of a destination, and reassurance
/// that is always on is reassurance nobody reads: it stops being the answer to
/// "did that save?" and becomes furniture, and then the one moment it matters
/// looks like every other moment. It appears on a save and it goes.
///
/// The way to the file went with it and did not disappear: Show store.yaml in
/// Finder is in the File menu, and Settings keeps its own button.
struct SavedChip: View {
    @Environment(AppState.self) private var state
    @State private var recentlySaved = false

    private var line: String {
        guard let date = state.lastSavedAt else { return "Saved" }
        return "Saved \(date.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        Group {
            if recentlySaved {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.green)
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(line)
            }
        }
        // `task(id:)` and not `onChange`, because this has to be cancelled.
        // `onChange` started a three second timer per save and cancelled
        // none of them, so a burst of saves left a queue of them and each
        // one turned the tick off at its own three second mark while later
        // saves turned it back on. It read as a blink.
        //
        // Bare assignments, with the animation scoped below. These were two
        // `withAnimation` calls, which animate every view SwiftUI updates in
        // the same pass and not the flag in the braces. Linking the first app
        // writes the manifest, so `lastSavedAt` is set at the exact moment the
        // sidebar, the header and the tab are all being built for the first
        // time, and the whole window animated in behind a tick nobody was
        // looking at.
        .task(id: state.lastSavedAt) {
            guard state.lastSavedAt != nil else { return }
            recentlySaved = true
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            recentlySaved = false
        }
        .animation(.smooth(duration: recentlySaved ? 0.2 : 0.4), value: recentlySaved)
    }
}

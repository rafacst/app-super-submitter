import SubmitKit
import SwiftUI

/// The shell. Spec section 16.1.
///
/// The content is the window surface, and the sidebar is a panel floating on
/// it, so the two read apart with a gap instead of a rule.
struct RootView: View {
    @Environment(AppState.self) private var state
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 0) {
            Sidebar()
                .panelSurface()
                .padding(Theme.panelGap)
            ContentArea()
        }
        .background(Theme.content)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13))
        .background(TrafficLightInset(inset: Theme.panelGap).frame(width: 0, height: 0))
        // The window hides its title bar, but SwiftUI still insets for it.
        // Without this the panel starts below the traffic lights instead of
        // carrying them, and the shell reads as a bar above a panel.
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $state.showSettings,
               onDismiss: { state.openPendingPaywall() }) { SettingsPanel() }
        .sheet(isPresented: $state.showOnboarding, onDismiss: { hasSeenOnboarding = true }) {
            OnboardingPanel()
        }
        .sheet(isPresented: $state.showExistingAppImport) { ExistingAppImportSheet() }
        .sheet(item: $state.releaseSheet) { store in ReleaseSheet(store: store) }
        .sheet(item: $state.paywall) { trigger in PaywallSheet(trigger: trigger) }
        .sheet(isPresented: $state.showAddLocale) { AddLocaleSheet() }
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
        .alert("Super Submitter", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
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

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader()
            Hairline()
            if state.manifestURL == nil || state.showEntryScreen {
                EmptyAppView()
            } else {
                ScrollView {
                    TabContent(tab: state.selectedTab)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
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
                .strokeBorder(tint.opacity(0.42), lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }
}

/// The 52 point bar above every tab. It carries the title, the one-line
/// question, and the controls that belong to the tab on the right.
private struct ContentHeader: View {
    @Environment(AppState.self) private var state
    @AppStorage("showYAMLToggle") private var yamlToggleVisible = false

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.manifestURL == nil ? "Welcome" : state.selectedTab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(-0.14)
                Text(state.manifestURL == nil
                     ? (state.mode == .publishing
                        ? "Which app do you want to send to the stores?"
                        : "Which app do you want to look after?")
                     : state.selectedTab.question)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
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

            if state.manifestURL != nil { switch state.selectedTab {
            case .details, .media:
                LocalePicker()
            case .plan:
                HStack(spacing: 7) {
                    // No spinner here. The tab body already says "Reading both
                    // stores" beside one, and two spinners for one read read
                    // as two reads.
                    QuietButton(title: "Read the stores again") {
                        Task { await state.readStores() }
                    }
                    Text("Dry run").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    // Turning the dry run off is the moment an apply becomes a
                    // store write, so that is where the paywall belongs.
                    SmallToggle(isOn: Binding(
                        get: { state.dryRun },
                        set: { value in
                            guard value || state.requirePaid(.storeWrite, .apply) else { return }
                            state.dryRun = value
                        }))
                }
            case .release:
                HStack(spacing: 7) {
                    if state.rechecking { Spinner() }
                    QuietButton(title: "Copy as checklist") { state.copyChecklist() }
                    QuietButton(title: "Re-check") { Task { await state.recheck() } }
                }
            default:
                EmptyView()
            } }
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .frame(height: Theme.headerHeight)
        .background(Theme.raised)
    }
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
                Button { state.showAddLocale = true } label: {
                    Text("+ Add")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a locale")
            }
            .background(Theme.sunken)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}

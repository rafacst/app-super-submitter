import SubmitKit
import SwiftUI

/// The shell. Spec section 16.1.
///
/// Two navigation positions, one set of views. The content area does not know
/// which position is active.
struct RootView: View {
    @Environment(AppState.self) private var state
    @AppStorage("navigationPosition") private var position: NavigationPosition = .sidebar
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        @Bindable var state = state
        ZStack(alignment: .topLeading) {
            switch position {
            case .sidebar:
                HStack(spacing: 0) {
                    Sidebar()
                    VHairline(color: Theme.sep)
                    ContentArea()
                }
            case .topBar:
                VStack(spacing: 0) {
                    TopBar()
                    ContentArea()
                }
            }
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13))
        .overlay(alignment: .topLeading) { SwitcherPopover(position: position) }
        .sheet(isPresented: $state.showSettings) { SettingsPanel() }
        .sheet(isPresented: $state.showOnboarding, onDismiss: { hasSeenOnboarding = true }) {
            OnboardingPanel()
        }
        .sheet(item: $state.releaseSheet) { store in ReleaseSheet(store: store) }
        .sheet(isPresented: $state.showAddLocale) { AddLocaleSheet() }
        .alert("Super Submitter", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
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
            if state.manifestURL == nil {
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
            HStack(spacing: 16) {
                StoreMark(store: .apple, size: 34)
                Circle().fill(Theme.sep).frame(width: 5, height: 5)
                StoreMark(store: .google, size: 34)
            }
            .padding(.bottom, 20)

            Text("Point Super Submitter at your app")
                .font(.system(size: 19, weight: .semibold))
                .kerning(-0.3)
            Text("Pick the folder your app is built in. We read the build and keep one small file beside it.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 7)

            Button { state.chooseAppFolder() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").font(.system(size: 12))
                    Text("Select app folder").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 26)

            Button { state.chooseExistingManifest() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 11))
                    Text("Continue work").font(.system(size: 12.5))
                }
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .help("Open the store.yaml of an app you already set up")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }
}

/// The 52 point bar above every tab. It carries the title, the one-line
/// question, and the controls that belong to the tab on the right.
private struct ContentHeader: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.manifestURL == nil ? "Welcome" : state.selectedTab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(-0.14)
                Text(state.manifestURL == nil
                     ? "Which app do you want to send to the stores?"
                     : state.selectedTab.question)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)

            // Every editing tab shows its own block of store.yaml. Spec 16.1.
            if state.manifestURL != nil, state.yamlBlock != nil {
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
                    if state.planReading { Spinner() }
                    QuietButton(title: "Read the stores again") {
                        Task { await state.readStores() }
                    }
                    Text("Dry run").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    SmallToggle(isOn: $state.dryRun)
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

extension Store: Identifiable {
    public var id: String { rawValue }
}

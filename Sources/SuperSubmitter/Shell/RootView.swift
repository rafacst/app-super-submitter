import SubmitKit
import SwiftUI

/// The shell. Spec section 16.1.
///
/// Two navigation positions, one set of views. The content area does not know
/// which position is active.
struct RootView: View {
    @Environment(AppState.self) private var state
    @AppStorage("navigationPosition") private var position: NavigationPosition = .sidebar

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
        .sheet(isPresented: $state.showOnboarding) { OnboardingPanel() }
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
        VStack(spacing: 13) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.text3)
            Text("Link an app to begin")
                .font(.system(size: 17, weight: .semibold))
            Text("Create a new store.yaml or open an existing one. Super Submitter will not show editable store state until a real manifest is linked.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 9) {
                Button("Create new app") { state.chooseNewAppLocation() }
                    .buttonStyle(.borderedProminent)
                Button("Open store.yaml") { state.chooseExistingManifest() }
                    .buttonStyle(.bordered)
            }
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
                     ? "Which store manifest do you want to manage?"
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

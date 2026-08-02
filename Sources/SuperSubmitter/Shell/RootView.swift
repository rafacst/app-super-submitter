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
    }
}

/// The content column: the header, then the tab.
private struct ContentArea: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader()
            Hairline()
            ScrollView {
                TabContent(tab: state.selectedTab)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.content)
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
                Text(state.selectedTab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(-0.14)
                Text(state.selectedTab.question)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)

            switch state.selectedTab {
            case .details, .media:
                LocalePicker()
            case .plan:
                HStack(spacing: 7) {
                    Text("Dry run").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    SmallToggle(isOn: $state.dryRun)
                }
            case .release:
                HStack(spacing: 7) {
                    QuietButton(title: "Copy as checklist")
                    QuietButton(title: "Re-check") { state.rechecked = true }
                }
            default:
                EmptyView()
            }
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
                ForEach(["en-US", "pt-BR"], id: \.self) { code in
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
                Text("+ Add")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
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

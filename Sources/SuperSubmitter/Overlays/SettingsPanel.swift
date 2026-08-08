import AppKit
import SubmitKit
import SwiftUI

/// Settings. A panel over the window, never a second window.
///
/// The provider choice sits here rather than on the Monetization tab. A
/// developer picks RevenueCat or Adapty once per machine, and then edits the
/// catalog on every app. The two jobs belong on two screens.
///
/// Every control here is the AppKit one. A hand-drawn checkbox and a
/// hand-drawn segmented control land on different baselines and different
/// heights, and six of those in one column read as six different apps.
struct SettingsPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    @AppStorage("pollIntervalMinutes") private var pollMinutes = 5
    @AppStorage("dryRunByDefault") private var dryRun = true
    @AppStorage("showYAMLToggle") private var showYAMLToggle = false
    @State private var section: SettingsSection = .workspace

    private static let intervals = [1, 5, 10, 15, 30, 60]

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            PanelTitleBar(title: "Settings") { dismiss() }
            tabStrip
            Hairline()
            // A fixed height, so the panel can never grow past the window and
            // put its own close button off the top of the screen.
            ScrollView {
                body(of: section)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 380)
            .background(Theme.content)
        }
        .frame(width: 560)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
        .onChange(of: state.revenueCatAPIKey) { _, _ in state.revenueCatKeyChanged() }
        .onChange(of: state.revenueCatProjectID) { _, _ in state.updateRevenueCatProject() }
    }

    /// One row of sections across the top, the way a Mac settings window
    /// works. Each section is short enough to read without a scroll.
    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                let selected = section == item
                Button { section = item } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 16, weight: selected ? .semibold : .regular))
                        Text(item.title).font(.system(size: 11.5,
                                                      weight: selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? Theme.accentText : Theme.text2)
                    .frame(width: 92)
                    .padding(.vertical, 7)
                    .background(selected ? Theme.accent : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Theme.raised)
    }

    @ViewBuilder
    private func body(of section: SettingsSection) -> some View {
        switch section {
        case .workspace: workspace
        case .files: files
        case .provider: provider
        case .nuclear: nuclear
        }
    }

    /// Start over. Everything the app holds, gone, and back to onboarding.
    ///
    /// Two confirmations and not one. The first is the ordinary destructive
    /// dialog, which people dismiss by reflex; the second names what goes and
    /// cannot be answered by reflex, because the buttons say different things.
    /// Nothing here reaches outside the app: the store listings, the developer
    /// accounts, and every `store.yaml` on disk are untouched, and the panel
    /// says so before the first click.
    private var nuclear: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 13) {
            SettingRow("Start over", alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Erase everything Super Submitter knows and return to the first-run screen.")
                        .font(.system(size: 12))
                        .frame(width: Self.controlWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Note("This forgets every linked app, every store key in your Keychain, your account, and all run data. It does not touch a store.yaml on your disk, your projects, your developer accounts, or anything already published. Those stay exactly as they are.")
                    Button("Erase everything") { state.nuclearFirstConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.red)
                        .controlSize(.large)
                }
            }
        }
        // First gate: the ordinary destructive dialog.
        .confirmationDialog("Erase everything Super Submitter knows?",
                            isPresented: $state.nuclearFirstConfirm,
                            titleVisibility: .visible) {
            Button("Continue", role: .destructive) { state.nuclearSecondConfirm = true }
            Button("Cancel", role: .cancel) { state.nuclearFirstConfirm = false }
        } message: {
            Text("Every linked app, every store key, your account and all run data. Your files and your store listings are not touched.")
        }
        // Second gate. The destructive button says what it does rather than
        // "OK", so the reflex that cleared the first dialog does not clear
        // this one too.
        .confirmationDialog("This cannot be undone.",
                            isPresented: $state.nuclearSecondConfirm,
                            titleVisibility: .visible) {
            Button("Erase everything and start over", role: .destructive) {
                state.eraseEverything()
                dismiss()
            }
            Button("Keep my data", role: .cancel) { state.nuclearSecondConfirm = false }
        } message: {
            Text("Super Submitter restarts at the first-run screen with nothing in it.")
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingRow("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: Self.controlWidth)
                .onChange(of: appearance) { appearance.apply() }
            }

            SettingRow("Poll interval") {
                Picker("Poll interval", selection: $pollMinutes) {
                    ForEach(Self.intervals, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .labelsHidden()
                .frame(width: Self.controlWidth)
                // The poller reads the value on the next tick, so a
                // restart makes the new interval take effect now.
                .onChange(of: pollMinutes) { state.startPolling() }
            }

            SettingRow("Raw YAML", alignment: .top) {
                Check("Show the YAML toggle on every tab", isOn: $showYAMLToggle,
                      note: "The toggle opens the block of store.yaml behind the tab you are on.")
                    // A hidden toggle must not leave a tab stuck in YAML.
                    .onChange(of: showYAMLToggle) {
                        if !showYAMLToggle { state.showYAML = false }
                    }
            }

            SettingRow("Dry run", alignment: .top) {
                Check("On by default for a new app", isOn: $dryRun,
                      note: "A dry run logs every request and sends none.")
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingRow("Manifest path", alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.manifestURL?.path ?? "No app is open.")
                        .font(Theme.mono(11))
                        .foregroundStyle(state.manifestURL == nil ? Theme.text3 : Theme.text)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(width: Self.controlWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        QuietButton(title: "Show in Finder") { state.revealManifest() }
                        QuietButton(title: "Copy path") {
                            state.copyToPasteboard(state.manifestURL?.path ?? "")
                        }
                    }
                    .disabled(state.manifestURL == nil)
                }
            }

            SettingRow("Build storage", alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.buildStorageSummary)
                        .font(.system(size: 12))
                        .frame(width: Self.controlWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Note("Archives and App Bundles are kept outside your repository. Deleting run data removes the logs and the temporary files. It never deletes a retained archive or a bundle, and it never touches your project.")
                    HStack(spacing: 7) {
                        QuietButton(title: "Reveal") { state.revealBuildStorage() }
                        QuietButton(title: "Delete old run data") {
                            state.pruneBuildStorage()
                        }
                    }
                }
            }
        }
    }

    private var provider: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingRow("Provider", alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Provider", selection: Binding(
                        get: { state.provider },
                        set: { value in state.setProvider(value) })) {
                        Text("None").tag(Manifest.Provider.none)
                        Text("RevenueCat").tag(Manifest.Provider.revenuecat)
                        Text("Adapty").tag(Manifest.Provider.adapty)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: Self.controlWidth)
                    Note("The provider mirrors the same purchases into one more catalog. The plan and the apply cover it beside the two stores.")
                    if state.provider == .revenuecat { revenueCat }
                    if state.provider == .adapty { adapty }
                }
            }

            Hairline()

            Text("The App Store and Google Play keys live on the Stores tab, next to the connection that needs them.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var revenueCat: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 8) {
            SecureField("Secret v2 API key", text: $state.revenueCatAPIKey)
            TextField("Project ID", text: $state.revenueCatProjectID)
            // The status sits under the button and not beside it. It carries
            // the full control width, which is also the width of this whole
            // column, so an HStack gave it every point and squeezed the button
            // to a bar: a tall empty rectangle with the words floating clear of
            // it. Adapty already stacked them, which is why only this one
            // looked broken.
            QuietButton(title: "Test connection") { state.testRevenueCatConnection() }
                .disabled(state.revenueCatAPIKey.isEmpty || state.revenueCatProjectID.isEmpty)
            connectionRow(state.revenueCatConnection)
            Note("The key is stored only in the macOS Keychain. It never reaches store.yaml.")
            Link("Create a RevenueCat account ↗",
                 destination: URL(string: "https://app.revenuecat.com/signup")!)
                .font(.system(size: 11.5))
        }
        .frame(width: Self.controlWidth, alignment: .leading)
    }

    private var adapty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Note("Adapty authenticates through its own CLI. This app reads the status and never runs the login.")
            connectionRow(state.adaptyConnection)
            HStack(spacing: 7) {
                QuietButton(title: "Check CLI login") { state.checkAdapty() }
                QuietButton(title: "Copy login command") {
                    state.copyToPasteboard("adapty auth login")
                }
            }
            Link("Create an Adapty account ↗",
                 destination: URL(string: "https://app.adapty.io/registration")!)
                .font(.system(size: 11.5))
        }
        .frame(width: Self.controlWidth, alignment: .leading)
    }

    /// Connected is green, refused is yellow, and everything else stays quiet.
    /// A refusal in the same grey as the help beside it is a refusal nobody
    /// reads.
    private func connectionRow(_ status: ConnectionStatus) -> some View {
        Group {
            if status.isFailed {
                WarningNote(status.label, width: Self.controlWidth)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(status.isConnected ? Theme.green : Theme.text3)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                    Text(status.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(status.isConnected ? Theme.green : Theme.text2)
                .frame(width: Self.controlWidth, alignment: .leading)
            }
        }
    }

    /// One width for every control, so the second column has one left edge and
    /// one right edge down the whole panel.
    static let controlWidth: CGFloat = 300
    static let labelWidth: CGFloat = 118
}

/// The sections, as the tabs across the top of the panel.
/// Three sections, and every one of them is something you change.
///
/// Account and About left. Neither was a setting: one is the plan and the
/// prices, which now has a tab of its own beside Stores, and the other is the
/// label on the tin, which the sidebar opens at its foot. Both were buried two
/// levels down, behind a sheet and under a tab strip.
enum SettingsSection: String, CaseIterable, Identifiable {
    case workspace, files, provider, nuclear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .files: "Files"
        case .provider: "Provider"
        case .nuclear: "Nuclear"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "macwindow"
        case .files: "folder"
        case .provider: "creditcard"
        case .nuclear: "exclamationmark.octagon"
        }
    }
}

private struct SettingRow<Content: View>: View {
    let label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: Content

    init(_ label: String, alignment: VerticalAlignment = .center,
         @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 14) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .frame(width: SettingsPanel.labelWidth, alignment: .leading)
                // The label sits on the first line of a tall row, not in the
                // middle of it.
                .padding(.top, alignment == .top ? 1 : 0)
            content
            Spacer(minLength: 0)
        }
    }
}

/// A checkbox and the one sentence under it.
private struct Check: View {
    let title: String
    @Binding var isOn: Bool
    let note: String

    init(_ title: String, isOn: Binding<Bool>, note: String) {
        self.title = title
        self._isOn = isOn
        self.note = note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
            Note(note)
        }
        .frame(width: SettingsPanel.controlWidth, alignment: .leading)
    }
}

private struct Note: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.text2)
            .lineSpacing(3)
            .frame(width: SettingsPanel.controlWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

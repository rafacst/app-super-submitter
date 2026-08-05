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
    @AppStorage("navigationPosition") private var position: NavigationPosition = .sidebar
    @AppStorage("pollIntervalMinutes") private var pollMinutes = 5
    @AppStorage("dryRunByDefault") private var dryRun = true
    @AppStorage("showYAMLToggle") private var showYAMLToggle = false

    private static let intervals = [1, 5, 10, 15, 30, 60]

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            header
            settings
        }
        .frame(width: 520)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
        .sheet(isPresented: $state.showAccount) { AccountSheet() }
    }

    private var header: some View {
        ZStack {
            Text("Settings").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Settings")
                Circle().fill(Theme.sep).frame(width: 12, height: 12)
                Circle().fill(Theme.sep).frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.horizontal, 13)
        }
        .frame(height: 44)
        .background(Theme.raised)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Section_("Workspace") {
              VStack(alignment: .leading, spacing: 13) {
                SettingRow("Navigation") {
                    Picker("Navigation", selection: $position) {
                        ForEach(NavigationPosition.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: Self.controlWidth)
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

                SettingRow("Updates", alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        QuietButton(title: "Check for updates") { Updater.check() }
                        Note("Checks the latest signed deployment published in the GitHub repository.")
                    }
                    .frame(width: Self.controlWidth, alignment: .leading)
                }
              }
            }

            Section_("Files") {
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

            Section_("Plan and billing") {
              VStack(alignment: .leading, spacing: 13) {
                SettingRow("Account", alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.accountEmail ?? state.entitlement.email ?? "Not signed in")
                            .font(.system(size: 12.5))
                            .frame(width: Self.controlWidth, alignment: .leading)
                        Text("\(state.planLabel) · \(state.entitlementLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                            .lineSpacing(3)
                            .frame(width: Self.controlWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 7) {
                            if state.accountEmail == nil {
                                QuietButton(title: "Sign in or create account") { state.openAccount() }
                            } else if state.isPaid {
                                QuietButton(title: "Manage billing") {
                                    Task { await state.openBillingPortal() }
                                }
                            } else {
                                QuietButton(title: "See plans") { state.openPaywall(.settings) }
                            }
                            if state.accountEmail != nil {
                                QuietButton(title: "Restore access") {
                                    Task { await state.restoreAccess() }
                                }
                            }
                            if state.accountEmail != nil {
                                QuietButton(title: "Sign out") { state.signOutOfBilling() }
                            }
                        }
                        if let message = state.billingMessage {
                            Note(message)
                        }
                        Note("Signing out returns Super Submitter to free access. It deletes no app, no store.yaml, no build, and no store key.")
                    }
                }
              }
            }

            Section_("Monetization provider") {
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
              }
            }

            Hairline()

            Text("The App Store and Google Play keys live on the Stores tab, next to the connection that needs them.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.content)
        .onChange(of: state.revenueCatAPIKey) { _, _ in state.revenueCatKeyChanged() }
        .onChange(of: state.revenueCatProjectID) { _, _ in state.updateRevenueCatProject() }
    }

    private var revenueCat: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 8) {
            SecureField("Secret v2 API key", text: $state.revenueCatAPIKey)
            TextField("Project ID", text: $state.revenueCatProjectID)
            HStack(spacing: 7) {
                QuietButton(title: "Test connection") { state.testRevenueCatConnection() }
                    .disabled(state.revenueCatAPIKey.isEmpty || state.revenueCatProjectID.isEmpty)
                connectionRow(state.revenueCatConnection)
            }
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

    private func connectionRow(_ status: ConnectionStatus) -> some View {
        HStack(spacing: 6) {
            Circle().fill(status.isConnected ? Theme.green : Theme.text3)
                .frame(width: 7, height: 7)
            Text(status.label)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(status.isConnected ? Theme.green : Theme.text2)
    }

    /// One width for every control, so the second column has one left edge and
    /// one right edge down the whole panel.
    static let controlWidth: CGFloat = 300
    static let labelWidth: CGFloat = 118
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

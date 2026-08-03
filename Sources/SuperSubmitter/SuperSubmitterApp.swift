import AppKit
import SwiftUI


@main
struct SuperSubmitterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        PostHogClient.setup()
    }
    @State private var state = AppState()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        Window("Super Submitter", id: "main") {
            RootView()
                .environment(state)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    // The onboarding states the one promise of the product
                    // before the first credential.
                    // RootView writes the flag when the panel closes. A flag
                    // written here burns the onboarding if the panel never opens.
                    if !hasSeenOnboarding { state.showOnboarding = true }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        // The sidebar and the top bar run under the title bar, so the window
        // shows one surface and not a bar above a bar.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // The two doors of the entry screen, plus the way out. The entry
            // screen hides itself once one app is linked, so without these the
            // second app has nowhere to come from.
            CommandGroup(replacing: .newItem) {
                Button("Submit a New App…") { state.chooseAppFolder() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Update Existing Apps…") { state.showExistingAppImport = true }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Divider()
                Button("Open store.yaml…") { state.chooseExistingManifest() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Remove App from Super Submitter…") {
                    state.askToRemoveApp(at: state.selectedAppIndex)
                }
                .disabled(state.linkedApps.isEmpty)
            }
            // Every edit writes `store.yaml` as the user types, so this repeats
            // a write that already happened. It exists because a Mac user
            // presses Command-S to be sure, and the shell then stamps the time.
            CommandGroup(replacing: .saveItem) {
                Button("Save") { state.saveNow() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(state.manifestURL == nil)
            }
            // The app has no Settings scene. Command-comma opens the panel
            // over the window, so the menu and the sidebar row do one thing.
            // The mode decides which tabs exist, so it belongs in the menu as
            // well as in the shell.
            CommandGroup(after: .toolbar) {
                Picker("Mode", selection: Binding(get: { state.mode },
                                                  set: { state.mode = $0 })) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                Divider()
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { state.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Super Submitter Onboarding") { state.showOnboarding = true }
            }
        }

        MenuBarExtra("Super Submitter", systemImage: "paperplane") {
            MenuBarPopover().environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The package builds a plain executable, not an app bundle yet. Without
/// these two lines the window opens behind every other app.
///
/// ponytail: switch to an Xcode project (xcodegen is on this machine) when
/// the app needs entitlements, an icon, or notarization. Not before.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Only the plain executable needs this. The app bundle carries the
        // asset catalog icon, and overriding it here would replace a whole
        // icon set with one 1024 point image.
        #if SWIFT_PACKAGE
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        #endif
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

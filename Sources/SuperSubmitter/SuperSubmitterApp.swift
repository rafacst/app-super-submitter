import AppKit
import SwiftUI

@main
struct SuperSubmitterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        Window("Super Submitter", id: "main") {
            RootView()
                .environment(state)
                .frame(minWidth: 1040, minHeight: 720)
                .task {
                    // The onboarding states the one promise of the product
                    // before the first credential.
                    if !hasSeenOnboarding {
                        state.showOnboarding = true
                        hasSeenOnboarding = true
                    }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        // The sidebar and the top bar run under the title bar, so the window
        // shows one surface and not a bar above a bar.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // The app has no Settings scene. Command-comma opens the panel
            // over the window, so the menu and the sidebar row do one thing.
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
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

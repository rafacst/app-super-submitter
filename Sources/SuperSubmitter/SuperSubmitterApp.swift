import AppKit
import SwiftUI


@main
struct SuperSubmitterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        PostHogClient.setup()
    }
    // The real defaults, the real Keychain, and the real app list, except
    // while `tools/screenshots.sh` or a `--demo` run is on. See ScreenshotMode.
    @State private var state = ScreenshotMode.makeAppState()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        Window("Super Submitter", id: "main") {
            RootView()
                .environment(state)
                .frame(minWidth: 1120, minHeight: 720)
                // The confirmation link in an account email, and the return
                // from Stripe Checkout. Both come back on the registered
                // scheme, and until this existed the app opened and sat there.
                .onOpenURL { state.handle(callback: $0) }
                .task {
                    // Sparkle quits the app to install, and AppKit will not
                    // quit an app that holds a modal sheet. The updater has
                    // no way to reach the shell, so the shell hands it one.
                    Updater.closeSheets = { state.closeEverySheet() }
                    guard !ScreenshotMode.isActive else {
                        ScreenshotMode.apply(to: state)
                        ScreenshotMode.placeWindow()
                        return
                    }
                    state.configureAccess()
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
            // Where a Mac user looks for both: the app menu, About first and
            // the update check under it.
            CommandGroup(replacing: .appInfo) {
                Button("About Super Submitter") { state.showAbout = true }
                Button("Check for Updates…") { Updater.check() }
                Divider()
            }
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
            // The app owns the stack, so the menu drives it directly. The
            // field editor keeps its own, and the standard item would reach
            // that one instead: every field writes `store.yaml` as it is
            // typed, so the manifest stack is the one a developer means.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { state.undoEdit() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!state.canUndoEdit)
                Button("Redo") { state.redoEdit() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.canRedoEdit)
            }
            // Every edit writes `store.yaml` as the user types, so this repeats
            // a write that already happened. It exists because a Mac user
            // presses Command-S to be sure, and the shell then stamps the time.
            CommandGroup(replacing: .saveItem) {
                Button("Save") { state.saveNow() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(state.manifestURL == nil)
            }
            // About 120 fields across ten tabs, and no way to ask where one
            // of them is. It sits under Edit, where ⌘F lives on the Mac.
            CommandGroup(after: .textEditing) {
                Button("Find a Field…") { state.showFieldSearch = true }
                    .keyboardShortcut("f", modifiers: .command)
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

/// The package builds a plain executable, not an app bundle. Without these
/// two lines the window opens behind every other app.
///
/// The shipping build is the Xcode project, because notarization and the
/// updater both need a real bundle. The package build stays for `swift test`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Before any window draws, so no screen flashes the other theme.
        ScreenshotMode.applyAppearance()
        Appearance.applyStored()
        Updater.start()
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

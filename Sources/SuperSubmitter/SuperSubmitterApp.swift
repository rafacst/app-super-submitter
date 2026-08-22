import AppKit
import QuickLookUI
import SwiftUI


@main
struct SuperSubmitterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        AptabaseClient.setup()
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
                    // A screenshot the store holds is fetched before the panel
                    // can show it, and a fetch that fails has to say so. The
                    // panel is app-wide and the presses come from three
                    // different views, so the shell hands it the one channel
                    // the app already shows errors on.
                    QuickLook.report = { state.errorMessage = $0 }
                    guard !ScreenshotMode.isActive else {
                        ScreenshotMode.apply(to: state)
                        ScreenshotMode.placeWindow()
                        return
                    }
                    // The screen this session opens on. `selectedTab` reports
                    // its own changes, and a launch is not one: the restore
                    // sets it inside `init`, where Swift runs no observer.
                    // Before the onboarding line below, so the two arrive in
                    // the order the developer sees them.
                    state.trackScreen()
                    state.configureAccess()
                    // The keys are already in the Keychain. This is the app
                    // asking the stores about them, rather than the developer
                    // pressing Connect on every launch to tell it what it
                    // could have found out itself.
                    state.verifyStoredConnections()
                    // The onboarding states the one promise of the product
                    // before the first credential.
                    // RootView writes the flag when the panel closes. A flag
                    // written here burns the onboarding if the panel never opens.
                    if !hasSeenOnboarding { state.showOnboarding = true }
                    // And behind it, the choice the onboarding is read for:
                    // a new app, or the apps already in the stores.
                    //
                    // `selectedTab` starts on Stores, and a tab that stands
                    // alone hides the entry screen — so a first launch opened
                    // on a credential form for an app that did not exist yet,
                    // and the two doors were reachable only through Add app in
                    // the tab strip. The erase command in Settings sets these
                    // same two lines and calls them "the first-run screen";
                    // a real first run never ran them.
                    if state.linkedApps.isEmpty { state.showEntryScreen = true }
                    // And where the App Store has each of the linked apps.
                    // The sweep ran on every app change and never at launch,
                    // so the status column opened empty every morning and
                    // filled itself only once you had clicked something.
                    //
                    // Last, and awaited. Everything above it is a local read
                    // that has to happen before the window is usable; this is a
                    // request per linked app, and a first run has neither a key
                    // nor an app, so it returns at its own door.
                    await state.refreshReviewStates()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        // The standard title bar, and it used to be hidden so that the sidebar
        // could carry the window buttons itself.
        //
        // `NavigationSplitView` lays itself out against the window's title bar
        // and cannot do without one: with `.hiddenTitleBar` it draws no sidebar
        // column at all — a blank panel beside a detail pane whose header sits
        // above the top of the window. Verified both ways on this machine.
        //
        // The split view is what gives the app a sidebar a Mac user can drag,
        // collapse and toggle, and what draws the selection, the section
        // headers and the vibrancy the system draws everywhere else. That is
        // worth a title bar.
        .windowToolbarStyle(.unified)
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
                Button("Submit a New App…") { state.startNewApp() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Update Existing Apps…") { state.startAppImport() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Divider()
                Button("Open store.yaml…") { state.chooseExistingManifest() }
                    .keyboardShortcut("o", modifiers: .command)
                // The sidebar used to carry "Saved to store.yaml" as a row,
                // and clicking it showed the file. The row was a status in a
                // navigation column and it has gone; the file it opened is
                // reachable here, where the rest of the file commands are.
                Button("Show store.yaml in Finder") { state.revealManifest() }
                    .disabled(state.manifestURL == nil)
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
            // No Mode picker here any more. The mode used to be a switch above
            // the sidebar that decided which rows existed, and this repeated
            // it. The sidebar lists both jobs at once now, so choosing the
            // mode *is* choosing a row: a second control for it would move the
            // selection out from under the user to a row they did not pick.
            //
            // The app has no Settings scene. Command-comma opens the Settings
            // tab in this window, which is where Settings lives: it is one of
            // the three screens about this Mac in the box at the foot of the
            // sidebar, and a second window for it would be a second place to
            // look for one screen.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    state.showEntryScreen = false
                    state.selectedTab = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Super Submitter Onboarding") { state.showOnboarding = true }
            }
        }

        // The symbol says whether the app is working. It was `paperplane` at
        // all times, so the one item in the whole menu bar that could report a
        // running apply reported nothing.
        //
        // A state change and not a loop. The menu bar is permanent visual
        // territory that the developer cannot dismiss, and a glyph that
        // animates continuously up there wears out in a morning. The filled
        // plane is legible standing still, which is the test: this has to read
        // correctly in a screenshot.
        MenuBarExtra("Super Submitter",
                     systemImage: state.isRunning ? "paperplane.fill" : "paperplane") {
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

    // MARK: - The Quick Look panel
    //
    // `QLPreviewPanel` is one app-wide panel and it refuses a data source from
    // whoever asks for one. It walks the responder chain for the first object
    // that accepts control, and hands the panel to that object alone.
    //
    // The delegate is the right place for it. It sits behind every window in
    // the chain, so a preview opened from the Media tab keeps working
    // whichever window is key, and no view in the SwiftUI hierarchy could hold
    // this without an `NSViewRepresentable` existing only to be a responder.
    //
    // `override` because these three are an Objective-C informal protocol: a
    // category on `NSObject`, so every object already has them and this
    // replaces the inherited versions.
    //
    // `MainActor.assumeIsolated` because that category predates concurrency
    // and so the methods import without isolation. AppKit calls them on the
    // main thread, which is what the assumption asserts, and it traps rather
    // than corrupting anything if that is ever untrue.
    //
    // `// ponytail: three methods on the delegate the app already has.`
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = QuickLook.shared }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = nil }
    }
}


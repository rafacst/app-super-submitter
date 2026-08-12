import AppKit
import Foundation
import SubmitKit

/// Drives the app to one screen, in one appearance, for the website
/// screenshots. `tools/screenshots.sh` is the only caller.
///
/// The two things it removes from that script are the two that would otherwise
/// need a permission grant and still not be deterministic: clicking a sidebar
/// row through the accessibility API, and flipping the whole desktop between
/// light and dark to capture both themes.
///
/// It also hands the script the exact rectangle to capture, so no shell code
/// converts between the bottom-left origin that AppKit uses and the top-left
/// origin that `screencapture -R` wants.
///
/// ponytail: launch arguments, behind `#if DEBUG`. The notarized build carries
/// none of it. Delete this file the day a UI test produces the screenshots.
enum ScreenshotMode {

    /// The screen the run wants, or nil for a normal launch.
    static var screen: String? {
        #if DEBUG
        return value(for: "--screenshot")
        #else
        return nil
        #endif
    }

    /// A demo run: the same isolation as a screenshot run, and none of its
    /// window placement.
    ///
    /// It exists so a build full of example data can be opened beside the real
    /// app without touching it. The isolation is the point: the throwaway
    /// defaults keep the demo apps out of the real app list, and the empty
    /// Keychain account keeps an unsigned build from raising the "allow
    /// access" dialog on every read.
    static var isDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        return false
        #endif
    }

    static var isActive: Bool { screen != nil || isDemo }

    /// What the ⌘F palette opens with, so the screenshot shows a result list
    /// and not an empty box. Empty in every real launch.
    ///
    /// "privacy" and not "url", because the palette answers in two kinds now
    /// and this is the word that reaches both: the fields on the listing, and
    /// the App Store step that no field of this app can satisfy.
    @MainActor
    static var fieldSearchQuery: String {
        #if DEBUG
        return screen == "field-search" ? "privacy" : ""
        #else
        return ""
        #endif
    }

    /// A throwaway suite while a screenshot runs, so the demo app never joins
    /// the linked apps of the developer running the script. The script deletes
    /// the file afterwards.
    static var defaults: UserDefaults {
        guard isActive else { return .standard }
        return UserDefaults(suiteName: "com.rafacst.supersubmitter.screenshots") ?? .standard
    }

    /// A Keychain account that holds nothing.
    ///
    /// The real one does. This binary is unsigned, and the items were written
    /// by a signed build, so every read raises the "allow access" dialog and
    /// blocks the main thread behind it.
    ///
    /// The account alone stopped being enough when the credentials became one
    /// vault item: every account is a key **inside** that item now, so the
    /// account no longer decides which Keychain item is opened.
    /// `isolateCredentials()` is what actually keeps this run off the real
    /// vault, and this name only keeps the two apart inside it.
    static var storeAccount: String {
        isActive ? "screenshots-no-credentials" : "store-credentials"
    }

    /// Keeps the credential vault out of the Keychain entirely.
    ///
    /// It runs before the first read of the process, so nothing has opened the
    /// real item by the time this lands.
    ///
    /// This used to point the vault at a Keychain service of its own, which
    /// was not enough. macOS grants Keychain access to a *binary*, and a
    /// `swift build` binary is a new one every compile, so the run after each
    /// build read an item the previous build had written and raised "allow
    /// access" — a password, on the main thread, on every build. An isolated
    /// run has nothing worth keeping between launches, so it keeps its
    /// credentials in memory and opens no Keychain item at all.
    /// Every `swift build` binary is isolated, not only `--demo`.
    ///
    /// The package target builds a plain unsigned executable and exists for
    /// `swift test` and for checking a change on screen. It is a new binary
    /// on every compile, so it is a new owner to the Keychain on every
    /// compile, and the real vault asks for a password each time. The shipping
    /// build is the Xcode project, it is signed, it keeps one identity across
    /// versions, and it is the only build that opens the real vault.
    static func isolateCredentials() {
        #if SWIFT_PACKAGE
        KeychainCredentials.useMemoryVault()
        #elseif DEBUG
        guard isActive else { return }
        KeychainCredentials.useMemoryVault()
        #endif
    }

    /// The state for this run, built after the vault is pointed somewhere
    /// safe.
    ///
    /// The order matters and a property default is the only place that
    /// guarantees it: `AppState.init` opens the last app and reads its
    /// credentials, and a struct assigns its property defaults before the body
    /// of `init` runs.
    @MainActor
    static func makeAppState() -> AppState {
        isolateCredentials()
        return AppState(defaults: defaults, storeAccount: storeAccount)
    }

    /// Whether the script named an appearance. The stored preference stands
    /// back when it did, so the two do not fight over `NSApp.appearance`.
    static var pinsAppearance: Bool {
        #if DEBUG
        ["light", "dark"].contains(value(for: "--appearance") ?? "")
        #else
        false
        #endif
    }

    /// Forces the appearance, so the script leaves the system setting alone.
    ///
    /// `@MainActor` because `NSApp` is. `pinsAppearance` above it stays
    /// nonisolated on purpose: that one only reads the launch arguments, and
    /// `Appearance.applyStored` asks it from wherever it happens to be.
    @MainActor
    static func applyAppearance() {
        #if DEBUG
        switch value(for: "--appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        #endif
    }

    /// The `AppVersionState` the run wants App Store review to be holding, or
    /// nil for the ordinary draft every other screen is captured in.
    static var reviewState: String? {
        #if DEBUG
        return value(for: "--review")
        #else
        return nil
        #endif
    }

    /// Every workspace the run names, in order. A demo run links several, so
    /// the sidebar holds one app per scenario.
    static var manifestPaths: [String] {
        #if DEBUG
        return (value(for: "--manifest") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        #else
        return []
        #endif
    }

    /// Whether the run wants a made-up price list.
    static var showsMockPlans: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--mock-plans")
        #else
        return false
        #endif
    }

    /// A price list, so the offer can be looked at before a licensing service
    /// exists to answer for one.
    ///
    /// `loadBillingPlans` asks a real server. A build with no `SUPABASE_URL`
    /// has none, so the Account tab draws "The plans could not be loaded"
    /// forever and the one screen whose job is to sell the app is the one
    /// screen that cannot be reviewed.
    ///
    /// ponytail: the amounts are invented and this comment is the only place
    /// that says so. Nothing reads them but the screen: no checkout opens, and
    /// `loadBillingPlans` returns early in an unconfigured build, so the seed
    /// survives the tab's own `.task`.
    @MainActor
    static func seedPlans(_ state: AppState) {
        state.billingPlans = BillingPlans(currency: "USD", plans: [
            BillingPlan(id: "monthly", amount: 900, interval: "month", available: true),
            BillingPlan(id: "annual", amount: 7900, interval: "year", available: true),
            BillingPlan(id: "lifetime", amount: 19900, interval: nil, available: true),
        ])
        state.selectedPlan = "annual"
    }

    /// Puts App Store review in charge of the open version, so the screen that
    /// produces can be photographed.
    ///
    /// Every rule about a version under review hangs off
    /// `actualState.apple.versionState`, and that only ever arrives from a live
    /// store read. The app caches no `ActualState` to disk, so no fixture on
    /// disk reaches the banner, the held row, the mark in the sidebar or the
    /// locked listing. The rules were under test and the drawing of them had
    /// never been seen.
    ///
    /// It seeds the read and stops there. The plan under it is `Planner`'s own
    /// answer to that read, so what lands in the picture is the screen and not
    /// a drawing of one. The plan is also what keeps the seed alive: the
    /// Summary tab reads the stores when it appears unless a plan is already
    /// there, and that read finds no credentials in an isolated run, answers an
    /// empty state, and would wipe this a moment after it was written.
    ///
    /// Only the open app. `appReviewStates` means "what a read said", and
    /// filling it for apps nobody read would put a claim about a store where
    /// the app's own rule is to claim nothing.
    @MainActor
    static func seedReview(_ state: AppState, versionState: String) {
        var apple = state.actualState.apple ?? ActualState.Apple()
        apple.versionState = versionState
        // The banner names the version, and a retrieval reads by id, so the
        // button under the banner needs one to be pressable.
        apple.versionString = state.manifest.release?.versionName ?? "3.2.0"
        if apple.versionId == nil { apple.versionId = "screenshot-version" }
        state.actualState.apple = apple
        state.rememberOpenAppReviewState()
        state.plan = Planner.plan(Planner.Input(
            manifest: state.manifest, actual: state.actualState, stores: state.stores,
            root: state.manifestRoot, packages: state.packages))
    }

    /// Puts the app on the named screen.
    @MainActor
    static func apply(to state: AppState) {
        #if DEBUG
        guard isActive else { return }
        // The welcome screen is the one that needs no app, so linking is
        // driven by the flag and never by the screen name.
        for path in manifestPaths {
            state.link(manifestAt: URL(fileURLWithPath: path))
            // The Manage side lists the apps a store has shipped, and a demo
            // run reads no store: without this its Apps group is empty in
            // every Manage picture. The seed is safe for the same reason the
            // review seed is: the throwaway defaults go with the run.
            state.rememberAppLiveness(state.currentAppKey, live: true)
        }
        // After the linking and before the screen: the seed reads the manifest
        // that linking loaded, and every tab below draws from what it leaves.
        if let reviewState { seedReview(state, versionState: reviewState) }
        if showsMockPlans { seedPlans(state) }
        guard let screen else {
            // A demo run lands on the app it linked, not on the welcome card.
            state.showOnboarding = false
            return
        }
        switch screen {
        case "welcome":
            state.showOnboarding = false
        case "onboarding":
            state.showOnboarding = true
        // The sheets. Each opens over the tab the app already landed on, so
        // none of them needs a tab of its own. Settings left this list when it
        // became a tab: the default below finds it by its own name.
        case "about":
            state.showAbout = true
        case "import":
            state.showExistingAppImport = true
        // The offer, which is a tab and no longer a sheet, and the one panel
        // it still opens.
        case "account":
            state.selectedTab = .account
        case "sign-in":
            state.selectedTab = .account
            state.showSignIn = true
        case "blockers":
            state.showBlockers = true
        case "field-search":
            state.showFieldSearch = true
        // Proves the other half of ⌘F: that an anchor is on a real view and
        // the content column reaches it. `jumpTarget` is consumed by an
        // `onChange`, so setting it here, before the window exists, would set
        // a value nothing ever observed. The beat is what makes it a change.
        case "field-jump":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                state.jump(to: FieldIndex.all.first { $0.id == "details.privacyPolicyURL" }!)
            }
        default:
            state.showOnboarding = false
            // The script names a tab by a slug, and a title holds spaces:
            // "review-info" is "Review info". Letters alone match both.
            //
            // Both jobs, because a tab can be named twice: Details is "Live
            // listing" on the Manage side and the two screens are not the same
            // picture. Publishing is tried first, so a name both jobs share
            // lands where it always did.
            let wanted = letters(screen)
            let found = Mode.allCases.lazy.compactMap { mode in
                Tab.allCases.first { letters($0.title(in: mode)) == wanted }
                    .map { (tab: $0, mode: mode) }
            }.first
            guard let found else {
                // A name that matches nothing used to leave the app on the
                // tab it opened with. The script then wrote that picture
                // under the name of the screen it asked for, and nothing
                // said so. "health" was one: the tab is "App health".
                print("UNKNOWN_SCREEN \(screen)")
                exit(1)
            }
            // The job first. `selectedTab` moves itself into a job that holds
            // it, and a tab both jobs hold would otherwise keep whichever job
            // the last run left behind in the throwaway defaults.
            state.mode = found.mode
            state.selectedTab = found.tab
        }
        #endif
    }

    /// Sizes the window, puts it at a known place, and prints the rectangle
    /// that `screencapture -R` takes. The script waits for that line, so it
    /// also serves as "the window is up".
    @MainActor
    static func placeWindow() {
        #if DEBUG
        // A demo run keeps the ordinary window. Only the screenshot script
        // wants a fixed frame and a floating level.
        guard screen != nil,
              // The MenuBarExtra owns a window too. The real one is the big one.
              let window = NSApp.windows.filter(\.isVisible)
                  .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              // The primary display, and never "whichever one the window
              // opened on". `visibleFrame` shrinks by the height of the Dock,
              // the Dock follows the pointer between displays, and the size
              // below is derived from it: two runs of the same screen came out
              // 820 points tall and 789 points tall on the same Mac.
              let screen = NSScreen.screens.first ?? window.screen else { return }

        let visible = screen.visibleFrame
        let size = NSSize(width: min(1280, visible.width - 80),
                          height: min(820, visible.height - 80))
        let origin = NSPoint(x: visible.minX + 40, y: visible.maxY - size.height - 40)
        window.setFrame(NSRect(origin: origin, size: size), display: true)

        // `screencapture -R` photographs a rectangle of the screen, not a
        // window. Whatever sits on top lands in the picture, including the
        // editor of whoever runs this. Floating clears the normal window level
        // and keeps the shot to this app.
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // The window id, and not a rectangle of the screen.
        //
        // `screencapture -R` photographs a place, so it only matches the
        // window while the window stays put, and this one does not: AppKit
        // pushes it back inside `visibleFrame` after an activate, and macOS
        // restores a remembered frame a moment later. The script waits, the
        // window drifted about 35 points in that gap, and the picture came out
        // with a strip of the sidebar cut off the left. Adding a settle delay
        // only narrowed the gap; nothing closes it.
        //
        // `screencapture -l` photographs a window by id, wherever it is and
        // whatever moved it, so the whole class of drift stops mattering.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            announceWhenActive(window)
        }
        #endif
    }

    #if DEBUG
    /// Prints the capture line only once the window is really the key window of
    /// a really active app.
    ///
    /// `NSApp.activate()` is a request and not a result: it returns before the
    /// activation lands, and the line below used to follow it after a fixed
    /// delay. Every dark capture lost that race, and an inactive Mac window is
    /// a different picture from the one being reviewed — grey traffic lights, a
    /// grey sidebar selection instead of the accent one, and glass buttons dim
    /// enough to read as disabled.
    ///
    /// Each turn asks again, because the activation can also be taken away
    /// between two turns by whatever the developer clicks while this runs.
    @MainActor
    private static func announceWhenActive(_ window: NSWindow, attempt: Int = 0) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        let isKey = window.isKeyWindow || window.attachedSheet?.isKeyWindow == true
        if NSApp.isActive, isKey {
            print("CAPTURE_WINDOW \(window.windowNumber)")
            fflush(stdout)
            return
        }
        // Five seconds. Then say so rather than print the capture line: a
        // picture of an inactive window is worse than no picture, because
        // nothing downstream can tell the two apart.
        guard attempt < 50 else {
            print("CAPTURE_INACTIVE app=\(NSApp.isActive) key=\(isKey)")
            fflush(stdout)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            announceWhenActive(window, attempt: attempt + 1)
        }
    }
    #endif

    private static func letters(_ text: String) -> String {
        text.filter(\.isLetter).lowercased()
    }

    private static func value(for flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

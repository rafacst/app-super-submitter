import AppKit
import Foundation

#if !SWIFT_PACKAGE
import Sparkle
#endif

/// The self-update door.
///
/// `SPUStandardUpdaterController` reads `SUFeedURL` and `SUPublicEDKey` out of
/// Info.plist, asks the user once whether to check on its own, and owns the
/// whole download, verify, and restart flow. There is nothing to configure
/// here that the Info.plist does not already say.
///
/// The delegate exists for one reason. Sparkle installs an update by quitting
/// the app, and AppKit refuses to quit an app that has a modal sheet on a
/// window. "Check for updates" sits inside the Settings panel, which is a
/// sheet, so "Install and Relaunch" asked the app to quit and the log
/// answered "App termination blocked by modal sheet". The app stayed open and
/// the update waited until the user happened to close Settings.
@MainActor
enum Updater {
    /// Closes the shell's sheets. The app installs it at launch, because the
    /// updater cannot reach `AppState` and does not need to know it exists.
    static var closeSheets: () -> Void = {}

    /// Ends the sheets AppKit knows about, at once.
    ///
    /// `closeSheets` moves SwiftUI state, and SwiftUI removes the sheet on a
    /// later run loop pass. Sparkle quits the app in this one, so the last
    /// resort ends the modal session directly.
    static func endAttachedSheets() {
        for window in NSApp.windows {
            for sheet in window.sheets { window.endSheet(sheet) }
        }
    }

    #if SWIFT_PACKAGE
    // `swift build` makes a plain executable, not an app bundle. Sparkle needs
    // the Info.plist keys that only the Xcode build writes, so the package
    // build links no updater and both calls do nothing.
    static func start() {}
    static func check() {}
    #else
    /// Holding the controller starts the background checks. A `static let`
    /// only runs on first use, so launch has to touch it.
    static func start() { _ = controller }

    /// The Settings panel holds one of the two buttons that reach here, and
    /// that panel is a sheet. It closes before the check, so the app is
    /// already free to quit by the time the download finishes.
    static func check() {
        closeSheets()
        controller.updater.checkForUpdates()
    }

    // Two objects, because the two protocols disagree about the main actor.
    // `SPUUpdaterDelegate` is `NS_SWIFT_UI_ACTOR` and
    // `SPUStandardUserDriverDelegate` is not, so one class cannot hold both.
    private static let updaterDelegate = UpdaterDelegate()
    private static let userDriverDelegate = UserDriverDelegate()

    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: updaterDelegate,
        userDriverDelegate: userDriverDelegate
    )
    #endif
}

#if !SWIFT_PACKAGE
/// The last resort, one moment before the app is asked to quit.
///
/// A sheet opened while the update window was already up would otherwise
/// block the install all over again. The protocol carries the main actor, so
/// this runs on it and the sheets are gone before `terminate:` asks.
@MainActor
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Updater.closeSheets()
        Updater.endAttachedSheets()
    }
}

/// Sparkle is about to put its own window in front of the user.
///
/// That is the roomy moment to clear the shell, seconds or minutes before
/// anybody presses "Install and Relaunch", so SwiftUI has all the time it
/// needs to take the sheet down properly.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    /// This protocol claims no actor, so the hop is explicit rather than
    /// assumed. Assuming an actor that the caller did not promise is what
    /// took the app down on Apple sign-in.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState) {
        Task { @MainActor in Updater.closeSheets() }
    }
}
#endif

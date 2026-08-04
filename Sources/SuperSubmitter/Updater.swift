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
/// ponytail: no delegate and no custom sheet. Add one when the app needs a
/// beta channel or a rule the standard flow does not cover. Not before.
@MainActor
enum Updater {
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

    static func check() { controller.updater.checkForUpdates() }

    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif
}

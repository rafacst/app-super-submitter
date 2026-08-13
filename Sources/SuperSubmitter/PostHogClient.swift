import Foundation
import PostHog

enum PostHogClient {
    static func setup() {
        guard let projectToken = value("SSPostHogProjectToken", "POSTHOG_PROJECT_TOKEN") else {
            missingConfiguration("POSTHOG_PROJECT_TOKEN")
            return
        }
        guard let host = value("SSPostHogHost", "POSTHOG_HOST") else {
            missingConfiguration("POSTHOG_HOST")
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        // The SDK installs its screen-view integration on every platform, but
        // the integration itself swizzles `UIViewController.viewDidAppear` and
        // there is no such class on a Mac, so it observes nothing. Left on
        // because it costs nothing and a Catalyst or iOS build would need it.
        // `AppState.selectedTab` sends the screen this app actually shows.
        config.captureScreenViews = true
        // On macOS this reads NSApplication's launch, resign and become-active
        // notifications, so app opened and app backgrounded are real here.
        config.captureApplicationLifecycleEvents = true
        // Both are the SDK's own defaults, stated so that a change upstream
        // does not silently move this app's batching.
        config.flushAt = 20
        config.flushIntervalSeconds = 30
        // Never in a shipped build. It prints every event and every response
        // to the console of a customer's Mac.
#if DEBUG
        config.debug = true
#endif
        PostHogSDK.shared.setup(config)
    }

    /// Ties every following event to the signed-in account, or to nobody.
    ///
    /// One call for both directions, because there is one value to watch.
    /// Four doors sign a developer in (the email form, the sign-up, an
    /// identity provider, and the link in a confirmation email) and a session
    /// restored at launch is a fifth, and every one of them writes
    /// `AppState.accountEmail`. Signing out clears it. Identifying at each of
    /// those five sites would leave the sixth one missing the first time
    /// somebody adds a door.
    ///
    /// The address is the identifier because it is the only identity the
    /// session carries: `SupabaseSession` holds the tokens, the expiry and the
    /// email, and no user id.
    static func identify(_ email: String?) {
        guard let email else {
            PostHogSDK.shared.reset()
            return
        }
        PostHogSDK.shared.identify(email, userProperties: ["email": email])
    }

    /// The environment first, so `swift run` and a Debug build can point at
    /// another project without editing the build. Then the Info.plist, which
    /// is all a double-clicked bundle has: an app opened from Finder inherits
    /// no shell, so the environment alone meant the shipped app measured
    /// nothing at all.
    ///
    /// An empty build setting leaves the plist holding the literal
    /// `$(POSTHOG_PROJECT_TOKEN)`, and that is a missing value, not a token.
    private static func value(_ plistKey: String, _ variable: String) -> String? {
        if let text = ProcessInfo.processInfo.environment[variable], !text.isEmpty {
            return text
        }
        guard let text = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
              !text.isEmpty, !text.hasPrefix("$(") else { return nil }
        return text
    }

    /// Loud in a debug build, silent in a release build, and fatal in
    /// neither.
    ///
    /// `fatalError` here killed the app on launch, because nothing loads
    /// `.env` into the process: `ProcessInfo` sees exported shell variables
    /// only. `swift run SuperSubmitter` therefore crashed for anybody who had
    /// not exported both variables, which is every new contributor and every
    /// CI job. Analytics that cannot start is a missing measurement, never a
    /// reason to stop a developer from submitting an app.
    private static func missingConfiguration(_ variable: String) {
#if DEBUG
        FileHandle.standardError.write(Data(
            "[PostHog] \(variable) is missing, so no event is sent. Export it, or run: set -a && . ./.env && set +a\n".utf8))
#endif
    }
}

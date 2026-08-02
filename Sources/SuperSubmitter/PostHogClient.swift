import Foundation
import PostHog

enum PostHogClient {
    static func setup() {
        guard let projectToken = ProcessInfo.processInfo.environment["POSTHOG_PROJECT_TOKEN"],
              !projectToken.isEmpty else {
            missingConfiguration("POSTHOG_PROJECT_TOKEN")
            return
        }
        guard let host = ProcessInfo.processInfo.environment["POSTHOG_HOST"],
              !host.isEmpty else {
            missingConfiguration("POSTHOG_HOST")
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        PostHogSDK.shared.setup(config)
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

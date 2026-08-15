import Foundation
import Aptabase

enum AptabaseClient {
    static func setup() {
        guard let appKey = value("SSAptabaseAppKey", "APTABASE_APP_KEY") else {
            missingConfiguration("APTABASE_APP_KEY")
            return
        }
        // The key's own region code decides where events go for a hosted
        // instance, but this app's key is self-hosted (`A-SH-…`), and that
        // region resolves to nothing without an explicit host.
        guard let host = value("SSAptabaseHost", "APTABASE_HOST") else {
            missingConfiguration("APTABASE_HOST")
            return
        }
#if DEBUG
        Aptabase.shared.initialize(appKey: appKey,
                                   with: InitOptions(host: host, trackingMode: .asDebug))
#else
        Aptabase.shared.initialize(appKey: appKey, with: InitOptions(host: host))
#endif
        Aptabase.shared.trackEvent("app_started")
    }

    /// The environment first, so `swift run` and a Debug build can point at
    /// another instance without editing the build. Then the Info.plist, which
    /// is all a double-clicked bundle has: an app opened from Finder inherits
    /// no shell, so the environment alone meant the shipped app measured
    /// nothing at all.
    ///
    /// An empty build setting leaves the plist holding the literal
    /// `$(APTABASE_APP_KEY)`, and that is a missing value, not a key.
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
            "[Aptabase] \(variable) is missing, so no event is sent. Export it, or run: set -a && . ./.env && set +a\n".utf8))
#endif
    }
}

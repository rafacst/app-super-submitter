import Foundation

/// What the app read out of a build. Spec section 16.3, tab 2.
///
/// Tab 3 fills its form from this. Every field is optional, because a build
/// can omit any of them, and a missing field is not an error. The developer
/// then types it.
public struct AppPackage: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        case ipa, pkg, aab

        public var store: Store {
            switch self {
            case .ipa, .pkg: .apple
            case .aab: .google
            }
        }
    }

    public var kind: Kind
    public var url: URL

    /// `CFBundleIdentifier`, or the Android `package`.
    public var identifier: String?
    /// `CFBundleShortVersionString`, or `android:versionName`.
    public var versionName: String?
    /// `CFBundleVersion`, or `android:versionCode`.
    public var buildNumber: String?
    /// `CFBundleDisplayName`, then `CFBundleName`, or the Android label.
    public var appName: String?
    /// `CFBundleLocalizations`, or the `values-*` resource folders.
    public var locales: [String] = []
    /// `MinimumOSVersion`, `LSMinimumSystemVersion`, or `minSdkVersion`.
    public var minimumOS: String?
    /// From `UIDeviceFamily`. Empty for a `.aab`, because an Android manifest
    /// names no device class.
    public var deviceClasses: [String] = []
    /// `ITSAppUsesNonExemptEncryption`. Apple only.
    public var usesNonExemptEncryption: Bool?
    /// The `NS*UsageDescription` keys, or the `uses-permission` names.
    public var privacyHints: [String] = []

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url
    }

    /// The count of fields that tab 3 can fill from this build.
    public var filledFieldCount: Int {
        var count = 0
        for value in [identifier, versionName, buildNumber, appName, minimumOS] where value != nil {
            count += 1
        }
        if !locales.isEmpty { count += 1 }
        if !deviceClasses.isEmpty { count += 1 }
        if usesNonExemptEncryption != nil { count += 1 }
        if !privacyHints.isEmpty { count += 1 }
        return count
    }
}

public enum PackageError: Error, LocalizedError, Equatable {
    case unknownType(String)
    case noAppInside(String)
    case unreadable(String, String)

    public var errorDescription: String? {
        switch self {
        case .unknownType(let ext):
            "Super Submitter reads an .ipa, a .pkg, and an .aab. This file is a .\(ext)."
        case .noAppInside(let name):
            "\(name) holds no app. An .ipa needs Payload/<name>.app, and an .aab needs base/manifest/AndroidManifest.xml."
        case .unreadable(let name, let reason):
            "Super Submitter cannot read \(name). \(reason)"
        }
    }
}

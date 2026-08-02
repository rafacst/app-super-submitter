import SubmitKit
import SwiftUI

/// What the app shows before it holds a real app.
///
/// Every screen that reads a store now reads a store. What is left here is the
/// empty-state app list, which needs three rows to explain the switcher, and
/// the onboarding copy, which is prose and not data.
enum DemoData {

    /// The placeholder app list. It appears only while no app is linked.
    static let apps: [DemoApp] = [
        DemoApp(name: "No app yet", initials: "—",
                summary: "Press New app to create a store.yaml",
                apple: .blocked, google: .blocked),
    ]

    // MARK: - The onboarding

    static let onboardingSteps: [(title: String, points: [String])] = [
        ("Choose your stores. Connect each one.", [
            "The App Store takes a .p8 key file, a key id, and an issuer id. Apple shows the file once.",
            "Google Play takes a service account JSON, and an invitation to that account inside the Play Console. No API performs the invitation.",
            "Every secret goes to the macOS Keychain. Nothing is written to a file in your repository.",
        ]),
        ("Pick your build, or pick an app to update.", [
            "Drop an .ipa, a .pkg, or an .aab. Or pick an app that already exists on either account.",
            "We read the bundle id, the version, the build number, the languages, and the minimum OS out of the package.",
            "We warn on the drop when the bundle id is wrong, when the build number is not higher than the store’s, or when the two packages disagree.",
        ]),
        ("Write the details once. We read what the build already knows.", [
            "One form per language. Every field carries a counter against the limit that binds both stores.",
            "Apple allows 30 characters of subtitle and Google allows 80. Press Different for Google and write both.",
            "We never shorten your text. An over-limit field is an error you fix, not a truncation we perform.",
        ]),
        ("Add the screenshots and the videos. We check every size.", [
            "We read the dimensions of every file on the drop, before anything uploads.",
            "A file that matches no bucket is rejected and named, with the nearest accepted size. We offer no resize, because a stretched screenshot fails a review.",
            "Apple takes a video file, 15 to 30 seconds. Google takes a YouTube link and no file.",
        ]),
        ("Set the price and the purchases. We mirror them to RevenueCat or to Adapty.", [
            "One amount, one currency, one base country. We show the price point Apple actually resolved before we write it.",
            "One product id becomes the right object in each store, and the matching product in your provider.",
            "The provider is optional. Choose None and nothing is mirrored.",
        ]),
    ]

    static let onboardingPackageRows: [DemoKeyValue] = [
        .init("Bundle id", "com.fastbillsplit.app"),
        .init("Version", "3.2.0"),
        .init("Build", "412"),
        .init("Languages", "en-US, pt-BR"),
        .init("Minimum OS", "iOS 17.0"),
    ]
}

// MARK: - The value types

enum StoreHealth {
    case matched, changed, blocked

    var mark: String {
        switch self {
        case .matched: "✓"
        case .changed: "!"
        case .blocked: "✕"
        }
    }

    var color: Color {
        switch self {
        case .matched: Theme.green
        case .changed: Theme.yellow
        case .blocked: Theme.red
        }
    }

    var background: Color {
        switch self {
        case .matched: Theme.greenBg
        case .changed: Theme.yellowBg
        case .blocked: Theme.redBg
        }
    }
}

struct DemoApp: Identifiable {
    let name: String
    let initials: String
    let summary: String
    let apple: StoreHealth
    let google: StoreHealth
    var id: String { name }
}

struct DemoKeyValue: Identifiable {
    let key: String
    let value: String
    let mono: Bool
    init(_ key: String, _ value: String, mono: Bool = false) {
        self.key = key
        self.value = value
        self.mono = mono
    }
    var id: String { key }
}

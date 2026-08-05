import SubmitKit
import SwiftUI

/// Static instructional copy. It describes behavior but supplies no example
/// app, credential, package, price, product, or manifest value.
enum OnboardingContent {

    /// One step of the onboarding. The symbol carries the step faster than the
    /// title, so every screen leads with a picture.
    struct Step {
        let title: String
        let symbol: String
        let points: [String]
    }

    static let onboardingSteps: [Step] = [
        Step(title: "Connect your stores.", symbol: "key.fill", points: [
            "The App Store takes a .p8 key, a key id, and an issuer id. Apple shows the file once.",
            "Google Play takes a service account, invited by hand inside the Play Console.",
            "Every secret goes to the macOS Keychain. Nothing lands in your repository.",
        ]),
        Step(title: "Drop your build.", symbol: "shippingbox.fill", points: [
            "An .ipa, a .pkg, or an .aab. Or pick an app that already exists on either account.",
            "We read the bundle id, the version, the build, the languages, and the minimum OS.",
            "A wrong bundle id or a low build number stops you on the drop, not in review.",
        ]),
        Step(title: "Write the listing once.", symbol: "text.alignleft", points: [
            "One form per language. Every field counts against the limit that binds both stores.",
            "Apple allows 30 characters of subtitle. Google allows 80. Write both with one switch.",
            "We never shorten your text. You fix an over-limit field yourself.",
        ]),
        Step(title: "Add the screenshots.", symbol: "photo.fill", points: [
            "We read the size of every file on the drop, before anything uploads.",
            "A wrong size is rejected and named. We offer no resize, because a stretched shot fails review.",
            "Apple takes a video file, 15 to 30 seconds. Google takes a YouTube link.",
        ]),
        Step(title: "Set the price.", symbol: "creditcard.fill", points: [
            "One amount, one currency, one base country. The stores convert the rest.",
            "We show the price point Apple resolved before we write it.",
            "One product id, mirrored to RevenueCat or to Adapty. Or to nothing at all.",
        ]),
    ]

    static let packageFields = [
        "Bundle identifier", "Version", "Build", "Languages", "Minimum OS",
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

    /// The glyph in words. A screen reader cannot say "✕".
    var label: String {
        switch self {
        case .matched: "in sync"
        case .changed: "has changes"
        case .blocked: "blocked"
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

struct AppSummary: Identifiable {
    let id: UUID
    let name: String
    let initials: String
    /// The app's own icon on disk, which the import downloads beside
    /// `store.yaml`. Nil until an import has run, and the row then draws the
    /// initials instead.
    var icon: URL?
    let summary: String
    /// Nil when the app does not go to that store at all.
    ///
    /// A store the developer never picked used to show a red cross, which
    /// says "this is wrong" about a choice they made on purpose. An app that
    /// goes to one store now wears one logo.
    let apple: StoreHealth?
    let google: StoreHealth?

    /// The row read aloud. A store the app does not go to is not named at
    /// all, the same as on the screen.
    var storeSummary: String {
        let parts = [apple.map { "App Store \($0.label)" },
                     google.map { "Google Play \($0.label)" }].compactMap { $0 }
        return parts.isEmpty ? "No store yet" : parts.joined(separator: ", ")
    }
}

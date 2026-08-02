import SubmitKit
import SwiftUI

/// The content of the mockup, one for one.
///
/// The clients are not built yet, so the screens render this. Every string
/// here comes from the design, which makes the app comparable to the mockup
/// side by side. Each block is replaced by a real read as its client lands.
enum DemoData {

    // MARK: - The app switcher

    static let apps: [DemoApp] = [
        DemoApp(name: "Fast Bill Split", initials: "FB", summary: "3.2.0 · 24 changes wait",
                apple: .changed, google: .changed),
        DemoApp(name: "Tide Timer", initials: "TT", summary: "1.8.1 · both stores match",
                apple: .matched, google: .matched),
        DemoApp(name: "Receipt Vault", initials: "RV", summary: "2.0.0 · 1 error blocks the plan",
                apple: .blocked, google: .matched),
    ]

    // MARK: - Tab 2

    static let packages: [DemoPackage] = [
        DemoPackage(title: "iOS · FastBillSplit.ipa", file: "build/FastBillSplit.ipa", rows: [
            .init("Bundle id", "com.fastbillsplit.app", mono: true),
            .init("Version name", "3.2.0", mono: true),
            .init("Build number", "412", mono: true),
            .init("App name", "Fast Bill Split"),
            .init("Languages", "en-US, pt-BR", mono: true),
            .init("Minimum OS", "iOS 17.0"),
            .init("Devices", "iPhone, iPad"),
            .init("Encryption", "No non-exempt encryption"),
            .init("Privacy", "3 permissions found"),
        ]),
        DemoPackage(title: "Android · app-release.aab", file: "build/app-release.aab", rows: [
            .init("Package name", "com.fastbillsplit.app", mono: true),
            .init("Version name", "3.2.0-rc4", mono: true),
            .init("Version code", "412", mono: true),
            .init("App label", "Fast Bill Split"),
            .init("Languages", "en-US, pt-BR", mono: true),
            .init("Minimum SDK", "26 · Android 8.0"),
            .init("Devices", "Phone, tablet"),
            .init("Encryption", "Not applicable"),
            .init("Privacy", "4 permissions found"),
        ]),
    ]

    // MARK: - Tab 4

    static let mediaGroups: [DemoMediaGroup] = [
        DemoMediaGroup(
            name: "Phone", count: "7 of 10", note: "iPhone 6.7 inch and Pixel",
            dropSize: CGSize(width: 88, height: 156),
            shots: Array(repeating: DemoShot(size: CGSize(width: 88, height: 156),
                                             bucket: "iPhone 6.7 inch",
                                             stores: "App Store · Google Play"), count: 4)
                + Array(repeating: DemoShot(size: CGSize(width: 88, height: 156),
                                            bucket: "Pixel 6 · 1080 × 1920",
                                            stores: "Google Play"), count: 3)),
        DemoMediaGroup(
            name: "Tablet 10 inch", count: "2 of 10", note: "iPad Pro 12.9 inch",
            dropSize: CGSize(width: 156, height: 112),
            shots: Array(repeating: DemoShot(size: CGSize(width: 156, height: 112),
                                             bucket: "iPad Pro 12.9 inch",
                                             stores: "App Store · Google Play"), count: 2)),
        DemoMediaGroup(
            name: "Desktop", count: "2 of 10", note: "Mac App Store only",
            dropSize: CGSize(width: 176, height: 110),
            shots: Array(repeating: DemoShot(size: CGSize(width: 176, height: 110),
                                             bucket: "Mac 2880 × 1800",
                                             stores: "App Store"), count: 2)),
    ]

    // MARK: - Tab 5

    static let providers: [DemoProvider] = [
        DemoProvider(key: .none, name: "None",
                     line: "No provider. The stores hold the catalog and nothing mirrors it."),
        DemoProvider(key: .revenuecat, name: "RevenueCat",
                     line: "One app per store. This app creates two products for one id."),
        DemoProvider(key: .adapty, name: "Adapty",
                     line: "One app for both stores. One product carries both store ids."),
    ]

    static let revenueCatScopes = [
        "apps:read", "products:read_write", "entitlements:read_write",
        "offerings:read_write", "packages:read_write",
    ]

    static let plans: [DemoPlan] = [
        DemoPlan(id: "com.fastbillsplit.app.premium.monthly", duration: "1 month",
                 basePlan: "monthly", name: "Premium Monthly", price: "2.99"),
        DemoPlan(id: "com.fastbillsplit.app.premium.yearly", duration: "1 year",
                 basePlan: "annual", name: "Premium Yearly", price: "24.99"),
    ]

    // MARK: - Tab 6

    static let reviewOpenRows: [DemoReviewRow] = [
        .init("Age rating questionnaire",
              "App Store · this app writes the answers. 12 questions, none answered.",
              .needed, "Answer"),
        .init("Content rating (IARC)",
              "Google Play · console only. Open Policy, then App content, then Content rating.",
              .needed, "Open ↗"),
    ]

    static let reviewRows: [DemoReviewRow] = [
        .init("Review notes",
              "App Store · this app writes them. Google Play keeps its own field in the console.",
              .done, "Edit"),
        .init("App categories",
              "App Store · this app writes them. Finance, then Utilities.", .done, "Edit"),
        .init("Google Play category",
              "Console only. The Android Publisher API writes no category.", .unknown, "Open ↗"),
        .init("Privacy policy URL",
              "App Store · one per language. Google Play keeps it in the console.", .done, "Edit"),
        .init("App privacy, nutrition labels",
              "App Store · console only. No API reads or writes them.", .unknown, "Open ↗"),
        .init("Data safety form",
              "Google Play · this app writes it, pre-filled from the 4 permissions the build declares.",
              .done, "Review"),
        .init("Export compliance",
              "From the build: no non-exempt encryption.", .done, "Edit"),
    ]

    // MARK: - Tab 7

    static let matchRows: [(system: String, line: String)] = [
        ("App Store", "Version 3.2.0, build 412. Listing, media, and purchases match."),
        ("Google Play", "Version code 412 in production. Listing, media, and purchases match."),
        ("RevenueCat", "5 products, 2 entitlements, 1 offering. All match."),
    ]

    static let diffColumns: [DemoDiffColumn] = [
        DemoDiffColumn(name: "App Store", summary: "11 writes · 10 uploads", rows: [
            .init(.add, "version 3.2.0 (PREPARE_FOR_SUBMISSION)"),
            .init(.change, #"en-US.whatsNew  "Faster scanning and a new dark theme.""#),
            .init(.change, #"en-US.promotionalText  "Now with receipt scanning.""#),
            .init(.add, "pt-BR.description  (1 402 chars)"),
            .init(.add, "9 screenshots  ·  24.2 MB"),
            .init(.add, "build 412  ·  118.4 MB"),
            .init(.change, "price 4.99 USD  →  point 4.99 USD"),
            .init(.remove, "preview  preview-6.5-en.mov"),
        ]),
        DemoDiffColumn(name: "Google Play", summary: "9 writes · 5 uploads", rows: [
            .init(.change, "en-US.fullDescription  (318 chars)"),
            .init(.change, "en-US.shortDescription  (43 chars)"),
            .init(.add, "pt-BR listing"),
            .init(.add, "4 phoneScreenshots  ·  9.8 MB"),
            .init(.add, "bundle versionCode 412  ·  42.1 MB"),
            .init(.change, "track production  release draft"),
            .init(.change, "basePlan annual  24.99 USD"),
        ]),
        DemoDiffColumn(name: "RevenueCat", summary: "4 writes", rows: [
            .init(.add, "product  com.fastbillsplit.app.pro  (app_store)"),
            .init(.add, "product  com.fastbillsplit.app.pro  (play_store)"),
            .init(.change, "entitlement  pro  attach 2 products"),
            .init(.change, "offering  default  package annual → position 2"),
        ]),
    ]

    // MARK: - Tab 8

    static let runItems: [DemoRunItem] = [
        .group("App Store"),
        .step("Create the version 3.2.0", "201 · 412 ms"),
        .step("Write the app information", "200 · 238 ms"),
        .step("Write 2 languages", "201 · 301 ms"),
        .step("Upload 9 screenshots", "24.2 MB"),
        .step("Upload the build 412", "118.4 MB", long: true),
        .step("Attach the build to the version", "200 · 190 ms"),
        .step("Write the review details", "201 · 214 ms"),
        .step("Write 5 purchases", "200 · 620 ms"),
        .group("Google Play"),
        .step("Open the edit", "201 · 180 ms"),
        .step("Write 2 listings", "200 · 265 ms"),
        .step("Upload 4 screenshots", "9.8 MB"),
        .step("Upload the bundle 412", "42.1 MB", long: true),
        .step("Write the production track, draft", "200 · 300 ms"),
        .step("Validate the edit", "200 · 410 ms"),
        .step("Commit, changes not sent for review", "200 · 502 ms"),
        .group("RevenueCat"),
        .step("Create 2 products", "201 · 240 ms"),
        .step("Attach 2 products to pro", "200 · 155 ms"),
        .step("Write the default offering", "200 · 168 ms"),
    ]

    static let logText = """
        14:02:11  POST  /v1/appStoreVersions                     201   412ms
        14:02:12  PATCH /v1/appStoreVersions/9f2c…                200   238ms
        14:02:13  POST  /v1/appInfoLocalizations                 201   301ms
        14:02:14  POST  /v1/appScreenshots                       201   190ms
        14:02:15  PUT   …uploadOperations[1/6]                   200  1.204s
        14:02:22  POST  /v1/buildUploads                         201   356ms
        """

    // MARK: - Tab 9

    static let appleChecklist: [DemoCheckRow] = [
        .init("a1", "App privacy, nutrition labels", "No API reads this. Open App privacy.", .unknown),
        .init("a2", "App information and categories", "Confirmed: Finance, then Utilities.", .done),
        .init("a3", "Pricing and availability", "Confirmed: 4.99 USD, 175 countries.", .done),
        .init("a4", "The submitted version", "Confirmed: 3.2.0, build 412.", .done),
        .init("a5", "Agreements, tax, and banking", "No API reads this. Open Business.", .unknown),
    ]

    static let googleChecklist: [DemoCheckRow] = [
        .init("g1", "Content rating (IARC)", "Console: Policy, App content, Content rating.", .needed),
        .init("g2", "Data safety", "Confirmed: the form is complete.", .done),
        .init("g3", "Country availability", "Console: Production, Countries and regions.", .unknown),
        .init("g4", "The release in the track", "Confirmed: a draft release in production.", .done),
        .init("g5", "App signing", "Console: Setup, App signing.", .unknown),
        .init("g6", "App access, the reviewer credentials", "Console: Policy, App content, App access.", .unknown),
    ]

    static let providerChecklist: [DemoCheckRow] = [
        .init("r1", "The store credential upload", "Dashboard only. Every provider needs it.", .unknown),
        .init("r2", "The offering", "Confirmed: 2 packages in default.", .done),
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

struct DemoPackage: Identifiable {
    let title: String
    let file: String
    let rows: [DemoKeyValue]
    var id: String { title }
}

struct DemoShot {
    let size: CGSize
    let bucket: String
    let stores: String
}

struct DemoMediaGroup: Identifiable {
    let name: String
    let count: String
    let note: String
    let dropSize: CGSize
    let shots: [DemoShot]
    var id: String { name }
}

struct DemoProvider: Identifiable {
    let key: Manifest.Provider
    let name: String
    let line: String
    var id: String { key.rawValue }
}

struct DemoPlan: Identifiable {
    let id: String
    let duration: String
    let basePlan: String
    let name: String
    let price: String
}

enum CheckState {
    case done, needed, unknown, notApplicable

    var label: String {
        switch self {
        case .done: "Done"
        case .needed: "Needed"
        case .unknown: "Unknown"
        case .notApplicable: "Not applicable"
        }
    }

    var color: Color {
        switch self {
        case .done: Theme.green
        case .needed: Theme.yellow
        case .unknown: Theme.text2
        case .notApplicable: Theme.text3
        }
    }

    var background: Color {
        switch self {
        case .done: Theme.greenBg
        case .needed: Theme.yellowBg
        case .unknown: Theme.sep2
        case .notApplicable: .clear
        }
    }
}

struct DemoReviewRow: Identifiable {
    let title: String
    let reason: String
    let state: CheckState
    let action: String
    init(_ title: String, _ reason: String, _ state: CheckState, _ action: String) {
        self.title = title
        self.reason = reason
        self.state = state
        self.action = action
    }
    var id: String { title }
}

struct DemoCheckRow: Identifiable {
    let id: String
    let title: String
    let reason: String
    let state: CheckState
    init(_ id: String, _ title: String, _ reason: String, _ state: CheckState) {
        self.id = id
        self.title = title
        self.reason = reason
        self.state = state
    }
}

enum DiffSign: String {
    case add = "+", change = "~", remove = "-"

    var color: Color {
        switch self {
        case .add: Theme.green
        case .change: Theme.yellow
        case .remove: Theme.red
        }
    }
}

struct DemoDiffRow: Identifiable {
    let sign: DiffSign
    let text: String
    init(_ sign: DiffSign, _ text: String) {
        self.sign = sign
        self.text = text
    }
    var id: String { sign.rawValue + text }
}

struct DemoDiffColumn: Identifiable {
    let name: String
    let summary: String
    let rows: [DemoDiffRow]
    var id: String { name }
}

struct DemoRunItem: Identifiable {
    let text: String
    let meta: String
    let isGroup: Bool
    let long: Bool
    let id = UUID()

    static func group(_ text: String) -> DemoRunItem {
        DemoRunItem(text: text, meta: "", isGroup: true, long: false)
    }

    static func step(_ text: String, _ meta: String, long: Bool = false) -> DemoRunItem {
        DemoRunItem(text: text, meta: meta, isGroup: false, long: long)
    }
}

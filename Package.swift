// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuperSubmitter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SubmitKit", targets: ["SubmitKit"]),
        .executable(name: "SuperSubmitter", targets: ["SuperSubmitter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.59.3"),
    ],
    targets: [
        // No UI. Every rule in the spec lives here and has a test.
        .target(
            name: "SubmitKit",
            dependencies: ["Yams"],
            resources: [.copy("Resources/screenshot-sizes.json")]
        ),
        // Views only. No logic.
        .executableTarget(
            name: "SuperSubmitter",
            dependencies: [
                "SubmitKit",
                .product(name: "PostHog", package: "posthog-ios"),
            ],
            resources: [.copy("Resources/AppIcon.png")]
        ),
        .testTarget(
            name: "SubmitKitTests",
            dependencies: ["SubmitKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

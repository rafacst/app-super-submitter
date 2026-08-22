import Foundation
import Testing
@testable import SubmitKit

/// A new app is linked by its folder, and the folder already says what the
/// developer would otherwise type: the identifier, the version, the name.
@Suite struct AppleProjectIdentityTests {

    /// One app target and its test bundle, in Debug and Release, which is what
    /// every project file holds.
    private let pbxproj = """
        buildSettings = {
            MARKETING_VERSION = 1.4.2;
            PRODUCT_BUNDLE_IDENTIFIER = com.example.deck;
            INFOPLIST_KEY_CFBundleDisplayName = "Deck Deck Deck";
        };
        buildSettings = {
            MARKETING_VERSION = 1.4.2;
            PRODUCT_BUNDLE_IDENTIFIER = com.example.deck;
        };
        buildSettings = {
            PRODUCT_BUNDLE_IDENTIFIER = com.example.deck.Tests;
        };
        buildSettings = {
            PRODUCT_BUNDLE_IDENTIFIER = com.example.deck.widget;
        };
        """

    @Test func theAppIsReadAndItsCompanionsAreNot() {
        let identity = AppleProjectIdentity.parse(pbxproj)
        #expect(identity.bundleIdentifier == "com.example.deck")
        #expect(identity.marketingVersion == "1.4.2")
        #expect(identity.displayName == "Deck Deck Deck")
    }

    /// A computed value is absent rather than guessed. A wrong identifier and
    /// an empty one are both refused by the store, and only the empty one
    /// reads as the developer's to fill.
    @Test func aSubstitutionIsNotAnAnswer() {
        let identity = AppleProjectIdentity.parse("""
            buildSettings = {
                PRODUCT_BUNDLE_IDENTIFIER = "com.example.$(PRODUCT_NAME:rfc1034identifier)";
                MARKETING_VERSION = "${VERSION}";
            };
            """)
        #expect(identity.bundleIdentifier == nil)
        #expect(identity.marketingVersion == nil)
        #expect(identity.isEmpty)
    }

    /// Nothing to read is an ordinary answer, not a failure.
    @Test func aProjectThatSaysNothingAnswersNothing() {
        #expect(AppleProjectIdentity.parse("").isEmpty)
        #expect(AppleProjectIdentity.read(
            container: URL(fileURLWithPath: "/nowhere/None.xcodeproj")).isEmpty)
    }

    /// The most stated identifier wins, and the shortest breaks a tie, so one
    /// target's override cannot outvote the app.
    ///
    /// One setting per line, which is the only shape Xcode writes.
    @Test func theAppWinsOverAOneOffOverride() {
        let identity = AppleProjectIdentity.parse("""
            buildSettings = {
                PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
            };
            buildSettings = {
                PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
            };
            buildSettings = {
                PRODUCT_BUNDLE_IDENTIFIER = com.example.app.beta;
            };
            """)
        #expect(identity.bundleIdentifier == "com.example.app")
    }

    /// A workspace holds no settings. It answers through the project beside it,
    /// and through none when two of them are candidates.
    @Test func aWorkspaceAnswersThroughTheProjectBesideIt() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbx-\(UUID().uuidString)")
        let project = folder.appendingPathComponent("Deck.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try pbxproj.write(to: project.appendingPathComponent("project.pbxproj"),
                          atomically: true, encoding: .utf8)

        let workspace = folder.appendingPathComponent("Deck.xcworkspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        #expect(AppleProjectIdentity.read(container: workspace).bundleIdentifier
            == "com.example.deck")
        #expect(AppleProjectIdentity.read(container: project).bundleIdentifier
            == "com.example.deck")

        // A second project beside it, under another name: the workspace of the
        // same name still answers, because that pairing is the ordinary shape.
        let pods = folder.appendingPathComponent("Pods.xcodeproj")
        try FileManager.default.createDirectory(at: pods, withIntermediateDirectories: true)
        #expect(AppleProjectIdentity.read(container: workspace).bundleIdentifier
            == "com.example.deck")
    }
}

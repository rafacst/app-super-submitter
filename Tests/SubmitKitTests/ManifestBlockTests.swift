import Foundation
import Testing
@testable import SubmitKit

private func sample() -> Manifest {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setReleaseVersionName("1.0.0")
    manifest.pricing = Manifest.Pricing(base: Price(amount: Decimal(string: "4.99")!,
                                                    currency: "USD", territory: "USA"))
    manifest.addMediaPaths(["assets/a.png"], locale: "en-US", deviceClass: .phone)
    return manifest
}

@Test func aBlockHoldsOnlyTheKeysThatItsTabWrites() throws {
    let yaml = try ManifestFile.encode(sample(), block: .stores)

    #expect(yaml.contains("apps:"))
    #expect(!yaml.contains("listing:"))
    #expect(!yaml.contains("pricing:"))
}

@Test func editingOneBlockLeavesEveryOtherBlockAlone() throws {
    let manifest = sample()
    let edited = """
        media:
          screenshots:
            en-US:
              phone:
                - assets/b.png
                - assets/c.png
        """

    let result = try ManifestFile.apply(edited, block: .media, to: manifest)

    #expect(result.mediaPaths(locale: "en-US", deviceClass: .phone)
        == ["assets/b.png", "assets/c.png"])
    // Nothing else moved.
    #expect(result.apps.apple?.bundleId == "com.example.app")
    #expect(result.listing?.locales["en-US"]?.name == "Example")
    #expect(result.pricing?.base.amount == Decimal(string: "4.99"))
}

@Test func anEmptyBlockClearsThatBlockAndNothingElse() throws {
    let result = try ManifestFile.apply("", block: .media, to: sample())

    #expect(result.media == nil)
    #expect(result.listing != nil)
}

@Test func aKeyFromAnotherTabIsRefusedInsteadOfSilentlyMerged() {
    #expect(throws: ManifestBlockError.unknownKey("pricing", .media)) {
        try ManifestFile.apply("pricing:\n  base:\n    amount: 1\n    currency: USD",
                               block: .media, to: sample())
    }
}

@Test func brokenYAMLChangesNothingBecauseItNeverDecodes() {
    #expect(throws: (any Error).self) {
        try ManifestFile.apply("media: [unclosed", block: .media, to: sample())
    }
}

@Test func everyEditingTabOwnsAtLeastOneKeyAndNoTwoTabsShareOne() {
    var seen: Set<String> = []
    for block in ManifestBlock.allCases {
        #expect(!block.keys.isEmpty)
        for key in block.keys {
            #expect(!seen.contains(key), "\(key) belongs to two tabs")
            seen.insert(key)
        }
    }
}

// MARK: - Media order

@Test func aScreenshotMovesInsideItsBucketAndStaysThere() {
    var manifest = Manifest()
    manifest.addMediaPaths(["a.png", "b.png", "c.png"], locale: "en-US", deviceClass: .phone)

    manifest.moveMediaPath("c.png", by: -1, locale: "en-US", deviceClass: .phone)
    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone)
        == ["a.png", "c.png", "b.png"])

    // A move past either end changes nothing.
    manifest.moveMediaPath("a.png", by: -1, locale: "en-US", deviceClass: .phone)
    #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone)
        == ["a.png", "c.png", "b.png"])
}

// MARK: - The Apple price point

@Test func theNearestPricePointIsChosenAndNeverRounded() {
    let points = [Decimal(string: "3.99")!, Decimal(string: "4.99")!, Decimal(string: "5.99")!]

    #expect(StateReader.nearest(to: Decimal(string: "4.90")!, in: points)
        == Decimal(string: "4.99"))
    #expect(StateReader.nearest(to: Decimal(string: "3.20")!, in: points)
        == Decimal(string: "3.99"))
    #expect(StateReader.nearest(to: Decimal(string: "1.00")!, in: []) == nil)
}

import Foundation
import Testing
@testable import SubmitKit

/// The message a developer reads when `store.yaml` will not load.
///
/// Every one of these used to read "The data couldn't be read because it is
/// missing." and name no key and no line.

private func failure(_ yaml: String) throws -> String {
    do {
        _ = try ManifestFile.decode(yaml)
        Issue.record("that YAML decoded, so there is no message to check")
        return ""
    } catch let error as ManifestError {
        return error.message
    }
}

/// The case that started this: one forgotten key, four hundred lines away.
@Test func aMissingKeyIsNamedAndPlaced() throws {
    let message = try failure("""
    version: 1
    apps:
      apple:
        appId: "1"
        platforms: [IOS]
        bundleId: com.example.app
    pricing:
      base:
        amount: 0
        currency: USD
      territories:
        - territory: USA
          available: true
        - territory: GBR
    """)
    #expect(message.contains("pricing.territories[1].available"))
    #expect(message.contains("is missing"))
    // The block that should have carried the key, not the top of the file.
    #expect(message.contains("line 14"))
}

@Test func aWrongTypeSaysWhatTheKeyTakes() throws {
    let message = try failure("""
    version: 1
    apps:
      apple:
        appId: "1"
        platforms: [IOS]
        bundleId: com.example.app
    pricing:
      base:
        amount: 0
        currency: USD
      autoConvertOtherTerritories: "yes please"
    """)
    #expect(message.contains("pricing.autoConvertOtherTerritories"))
    #expect(message.contains("true or false"))
    #expect(message.contains("line 11"))
}

/// A hand-written decoder already explains itself, so the wrapper keeps its
/// words and only adds the place.
@Test func aDecoderOfItsOwnKeepsItsMessage() throws {
    let message = try failure("""
    version: 1
    apps:
      apple:
        appId: "1"
        platforms: [IOS]
        bundleId: com.example.app
    pricing:
      base:
        amount: "four ninety nine"
        currency: USD
    """)
    #expect(message.contains("four ninety nine"))
    #expect(message.contains("line"))
}

/// A broken document is not a key problem, and Yams already names the line and
/// the column for it. It passes through rather than being reworded.
@Test func aBrokenDocumentKeepsTheYamsMessage() {
    #expect(throws: (any Error).self) {
        try ManifestFile.decode("version: 1\napps:\n  apple:\n   - [unclosed\n")
    }
}

@Test func aPathReadsTheWayAPersonPointsAtIt() {
    #expect(ManifestFile.describe([]) == "")
    #expect(ManifestFile.describe([Key("pricing"), Key("territories"),
                                   Key(index: 0), Key("available")])
        == "pricing.territories[0].available")
}

@Test func everyTypeHasWordsRatherThanASwiftName() {
    #expect(ManifestFile.words(for: Bool.self) == "true or false")
    #expect(ManifestFile.words(for: String.self) == "text")
    #expect(ManifestFile.words(for: Int.self) == "a number")
    #expect(ManifestFile.words(for: [String].self) == "a list")
}

/// The editor writes a block back through the same door, so it explains a
/// failure the same way.
@Test func theBlockEditorExplainsItTheSameWay() throws {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
    do {
        _ = try ManifestFile.apply("release:\n  versionName: [1, 2]\n",
                                   block: .build, to: manifest)
        Issue.record("that block applied")
    } catch let error as ManifestError {
        #expect(error.message.contains("release.versionName"))
    }
}

private struct Key: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ value: String) { stringValue = value }
    init(index: Int) { stringValue = "\(index)"; intValue = index }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = "\(intValue)"; self.intValue = intValue }
}

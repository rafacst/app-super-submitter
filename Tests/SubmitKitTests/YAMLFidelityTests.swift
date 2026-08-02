import Testing
@testable import SubmitKit

// The description is the longest field in the product, up to 4000 characters,
// and it holds line breaks. Yams writes it back as a quoted scalar, not as a
// `|` block. The text survives. The shape of the file changes.
//
// This test guards the text. Spec section 20, question 8 holds the open
// question about the shape and about the comments.

@Test func aMultiLineDescriptionSurvivesTwoSaves() throws {
    let yaml = """
        version: 1
        apps: {}
        listing:
          defaultLocale: en-US
          locales:
            en-US:
              name: Fast Bill Split
              description: |
                Split a restaurant bill with your friends.

                No account. No ads.
        """
    let once = try ManifestFile.decode(yaml)
    let twice = try ManifestFile.decode(ManifestFile.encode(once))
    let thrice = try ManifestFile.decode(ManifestFile.encode(twice))

    let text = try #require(thrice.listing?.locales["en-US"]?.description.value)
    #expect(text == "Split a restaurant bill with your friends.\n\nNo account. No ads.")
    #expect(once == twice)    // a save changes no value
    #expect(once == thrice)
}

@Test func theKeyOrderOfTheManifestSurvivesASave() throws {
    let yaml = """
        version: 1
        apps:
          apple:
            appId: "1234567890"
            platforms: [IOS]
            bundleId: com.example.app
        """
    let encoded = try ManifestFile.encode(try ManifestFile.decode(yaml))
    let appId = try #require(encoded.range(of: "appId"))
    let bundleId = try #require(encoded.range(of: "bundleId"))
    #expect(appId.lowerBound < bundleId.lowerBound)
}

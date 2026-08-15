import CoreGraphics
import Foundation
import ImageIO
import SubmitKit
import Testing
import UniformTypeIdentifiers
@testable import SuperSubmitter

/// Sending the store's own pictures back, for an app that ships more than one
/// iPhone size.
///
/// The bug this guards: `Validator.media` counts screenshots the way Apple does,
/// 10 per display type, and the door that files come in through counted 10 for
/// the whole Phone bucket. The App Store keeps a set per screen size and this
/// app keeps one Phone bucket holding all of them, so a listing with a 6.9 inch
/// set and a 6.7 inch set has up to twenty legal phone files. "Send these 12
/// again" refused all twelve and named a limit the store does not have.
///
/// The iPad went through the same door untouched, because an iPad app usually
/// ships one size and stays under ten. That is why this read as an iPhone bug.

/// A real PNG of exactly these dimensions. The dimensions are the whole point:
/// they are what picks the display type.
private func png(_ width: Int, _ height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

@MainActor
private func openApp(_ sizes: [(Int, Int)]) throws -> (state: AppState, files: [URL],
                                                       folder: URL) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("resend-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let manifestURL = folder.appendingPathComponent("store.yaml")
    try ManifestFile.save(Manifest(), to: manifestURL)

    var files: [URL] = []
    for (index, size) in sizes.enumerated() {
        let url = folder.appendingPathComponent("shot-\(index)-\(size.0)x\(size.1).png")
        try png(size.0, size.1).write(to: url)
        files.append(url)
    }

    let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                         storeAccount: "resend-\(UUID().uuidString)")
    try state.load(from: manifestURL)
    state.manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    state.manifest.addLocale("en-US")
    state.locale = "en-US"
    return (state, files, folder)
}

/// The reported shape: two iPhone sets, six pictures each. Twelve in one
/// bucket, and not one display type over the limit.
///
/// 6.9 inch and 6.5 inch, which really are two sets. 6.9 and 6.7 are not: Apple
/// has no `APP_IPHONE_69` and takes the 1320 x 2868 pictures into the 6.7 inch
/// set, so those two count together and ten of them is the limit.
@MainActor
@Test func everyIPhoneSizeGoesBackTogether() throws {
    let (state, files, folder) = try openApp(
        Array(repeating: (1320, 2868), count: 6) + Array(repeating: (1242, 2688), count: 6))
    defer { try? FileManager.default.removeItem(at: folder) }

    state.addMediaFiles(files, deviceClass: .phone)

    #expect(state.mediaError == nil)
    #expect(state.mediaPaths(deviceClass: .phone).count == 12)
}

/// The picker takes it anyway. Replacing a set means dropping the new
/// pictures before deleting the old ones, which is over the limit for as
/// long as both sit here, and refusing the drop meant deleting blind first.
@MainActor
@Test func elevenOfOneIPhoneSizeIsAcceptedLocally() throws {
    let (state, files, folder) = try openApp(Array(repeating: (1320, 2868), count: 11))
    defer { try? FileManager.default.removeItem(at: folder) }

    state.addMediaFiles(files, deviceClass: .phone)

    #expect(state.mediaError == nil)
    #expect(state.mediaPaths(deviceClass: .phone).count == 11)
}

/// The picker no longer refuses eleven of one size, but the count
/// `Validator.media` acts on before an apply still sees the overflow: the
/// safety net moved to where it actually has to hold, it did not disappear.
@MainActor
@Test func theCountValidatorActsOnStillSeesTheOverflow() throws {
    let (state, files, folder) = try openApp(Array(repeating: (1320, 2868), count: 11))
    defer { try? FileManager.default.removeItem(at: folder) }

    state.addMediaFiles(files, deviceClass: .phone)
    let counts = Validator.appleDisplayTypeCounts(
        state.mediaPaths(deviceClass: .phone), root: folder, deviceClass: .phone)

    #expect(counts["APP_IPHONE_67"] == 11)
}

/// The iPad path, which worked before and has to keep working.
@MainActor
@Test func theIPadStillTakesItsOwnSet() throws {
    let (state, files, folder) = try openApp(Array(repeating: (2064, 2752), count: 8))
    defer { try? FileManager.default.removeItem(at: folder) }

    state.addMediaFiles(files, deviceClass: .tablet10)

    #expect(state.mediaError == nil)
    #expect(state.mediaPaths(deviceClass: .tablet10).count == 8)
}

/// Google counts per device class and takes eight, and that rule is untouched.
@MainActor
@Test func googleStillCountsTheWholeBucket() throws {
    let (state, files, folder) = try openApp(
        Array(repeating: (1320, 2868), count: 5) + Array(repeating: (1290, 2796), count: 5))
    defer { try? FileManager.default.removeItem(at: folder) }
    state.manifest.setGoogleApp(packageName: "com.example.app")

    state.addMediaFiles(files, deviceClass: .phone)

    #expect(state.mediaError?.contains("8") == true)
}

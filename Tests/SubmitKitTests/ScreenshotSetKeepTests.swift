import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SubmitKit

/// One screenshot of an exact size. The display type comes from the pixels, so
/// the size is the whole point of the fixture.
private func writeImage(_ url: URL, width: Int, height: Int) throws {
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

/// The App Store keeps one screenshot set per display type, and the apply
/// deletes the sets the manifest no longer names.
///
/// The plan writes one step per device class, and the step carries only that
/// class's files. Deriving "what to keep" from the step therefore kept one
/// class and deleted the rest: the iPhone step deleted the iPad set, and the
/// iPad step deleted the iPhone set, so an app with screenshots for two device
/// classes published whichever class the run happened to write last. The
/// manifest decides what to keep, not the step.
@Suite(.serialized)
struct ScreenshotSetKeepTests {
    @Test func oneDeviceClassNeverDeletesAnothersScreenshots() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // 1320 x 2868 is APP_IPHONE_69. 2064 x 2752 is APP_IPAD_PRO_3GEN_129.
        try writeImage(folder.appendingPathComponent("phone.png"), width: 1_320, height: 2_868)
        try writeImage(folder.appendingPathComponent("pad.png"), width: 2_064, height: 2_752)

        var manifest = Manifest()
        manifest.setAppleApp(appID: "1", bundleID: "com.example.app")
        manifest.addMediaPaths(["phone.png"], locale: "en-US", deviceClass: .phone)
        manifest.addMediaPaths(["pad.png"], locale: "en-US", deviceClass: .tablet10)

        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        let runner = Runner(plan: PlanResult(), manifest: manifest, actual: ActualState(),
                            root: folder, credentials: StoreCredentials(apple: credential),
                            dryRun: true, access: GrantAll(), emit: { _ in })

        // Both classes, from one call, whichever step is running.
        let keep = await runner.appleWantedBuckets(locale: "en-US")
        #expect(keep == ["APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129"])

        // A locale the manifest says nothing about keeps nothing, which is how
        // a dropped device class still gets its set removed.
        let other = await runner.appleWantedBuckets(locale: "pt-BR")
        #expect(other.isEmpty)
    }
}

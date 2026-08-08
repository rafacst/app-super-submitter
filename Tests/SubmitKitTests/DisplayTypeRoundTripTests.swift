import Foundation
import Testing
@testable import SubmitKit

/// The upload and the import speak the same Apple vocabulary. They used to
/// hold two hand-written copies of it, and the copies drifted: the import's
/// list never named `APP_IPHONE_69`, so the 6.9 inch screenshots that every
/// current app ships were dropped without a word, and it spelled the watch
/// and the vision types the way Apple does not.
@Suite struct DisplayTypeRoundTripTests {

    /// Every size the upload can send names a display type, and that display
    /// type leads back to the device class the size came from.
    @Test func everyUploadableSizeSurvivesTheRoundTrip() throws {
        for deviceClass in Manifest.DeviceClass.allCases {
            for (width, height) in try sizes(for: deviceClass) {
                let info = ImageAssetInfo(width: width, height: height, fileSize: 0)
                let found = try AssetInspector.appleDisplayType(for: info,
                                                                deviceClass: deviceClass)
                let type = try #require(
                    found,
                    "\(width) x \(height) has no Apple display type for \(deviceClass).")
                #expect(Manifest.DeviceClass(storeBucket: type) == deviceClass,
                        "\(type) does not lead back to \(deviceClass).")
            }
        }
    }

    /// The 6.9 inch iPhone and the 13 inch iPad are the two sizes App Store
    /// Connect asks for today. Neither may go missing on the way in.
    @Test func theCurrentAppleBucketsReachADeviceClass() {
        #expect(Manifest.DeviceClass(storeBucket: "APP_IPHONE_69") == .phone)
        #expect(Manifest.DeviceClass(storeBucket: "APP_IPHONE_67") == .phone)
        #expect(Manifest.DeviceClass(storeBucket: "APP_IPAD_PRO_3GEN_129") == .tablet10)
        // Kept from the older hand-written list: Apple still answers with it
        // for a screenshot set uploaded years ago.
        #expect(Manifest.DeviceClass(storeBucket: "APP_IPAD_PRO_129") == .tablet10)
        #expect(Manifest.DeviceClass(storeBucket: "APP_WATCH_SERIES_10") == .watch)
        #expect(Manifest.DeviceClass(storeBucket: "APP_APPLE_VISION_PRO") == .vision)
        #expect(Manifest.DeviceClass(storeBucket: "APP_DESKTOP") == .desktop)
        #expect(Manifest.DeviceClass(storeBucket: "APP_APPLE_TV") == .tv)
    }

    /// The catalog writes a phone size portrait and a Mac size landscape. The
    /// lookup normalizes both, or a Mac screenshot reaches the upload with no
    /// display type and Apple has nowhere to put it.
    @Test func aLandscapeSizeFindsItsDisplayType() throws {
        let mac = ImageAssetInfo(width: 2_880, height: 1_800, fileSize: 0)
        #expect(try AssetInspector.appleDisplayType(for: mac, deviceClass: .desktop)
            == "APP_DESKTOP")
        let tv = ImageAssetInfo(width: 1_920, height: 1_080, fileSize: 0)
        #expect(try AssetInspector.appleDisplayType(for: tv, deviceClass: .tv)
            == "APP_APPLE_TV")
    }

    @Test func anUnknownDisplayTypeIsDroppedRatherThanGuessed() {
        #expect(AssetInspector.deviceClass(forAppleDisplayType: "APP_IPHONE_9000") == nil)
        #expect(AssetInspector.deviceClass(forAppleDisplayType: "") == nil)
    }

    /// The accepted sizes of one device class, out of the same catalog the
    /// validation reads.
    private func sizes(for deviceClass: Manifest.DeviceClass) throws -> [(Int, Int)] {
        // The vision shares 3840 x 2160 with the TV and takes its display type
        // from the device class, not the pixels. The round trip below would
        // otherwise ask one size to lead back to two classes.
        guard deviceClass != .vision else { return [] }
        // The file itself, not a bundle copy. The kit ships it as a resource
        // of its own module, which a test bundle does not carry.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SubmitKit/Resources/screenshot-sizes.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let catalog = try #require(json as? [String: Any])
        let apple = try #require(catalog["apple"] as? [String: [[Int]]])
        return (apple[deviceClass.rawValue] ?? []).map { ($0[0], $0[1]) }
    }
}

/// The Media tab draws a tile per device class, and the shape comes from the
/// same catalog the upload reads.
///
/// One box for every class put a 1440 by 900 desktop screenshot in a portrait
/// card and left ninety points of air under it.
struct DeviceShapeTests {
    @Test func aDesktopScreenIsWideAndAPhoneScreenIsTall() {
        #expect(AssetInspector.aspectRatio(for: .desktop) > 1)
        #expect(AssetInspector.aspectRatio(for: .tv) > 1)
        #expect(AssetInspector.aspectRatio(for: .vision) > 1)
        #expect(AssetInspector.aspectRatio(for: .phone) < 1)
        #expect(AssetInspector.aspectRatio(for: .tablet10) < 1)
        // The watch is nearly square, and it is still taller than it is wide.
        let watch = AssetInspector.aspectRatio(for: .watch)
        #expect(watch < 1 && watch > 0.7)
    }

    /// 1280 x 800 is the size Apple documents for a Mac screenshot.
    @Test func theDesktopShapeIsTheSizeAppleAsksFor() {
        #expect(abs(AssetInspector.aspectRatio(for: .desktop) - 1_280.0 / 800.0) < 0.001)
    }

    /// The small Android tablet has no Apple size of its own, so it falls back
    /// on a portrait shape rather than a square or a divide by zero.
    @Test func theSmallTabletFallsBackToAPortraitShape() {
        let tablet7 = AssetInspector.aspectRatio(for: .tablet7)
        #expect(tablet7 > 0 && tablet7 < 1)
    }
}

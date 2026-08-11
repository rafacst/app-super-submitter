import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SubmitKit

/// How many screenshots are too many, and what Apple counts them against.
///
/// The bug this guards: Apple keeps a separate screenshot set for each iPhone
/// size and this app has one Phone bucket holding all of them. An app that
/// ships 6.9 inch and 6.5 inch pictures imported the same five shots twice, the
/// bucket held fourteen, and the check counted all fourteen against a limit of
/// ten that Apple applies per display type. The apply would have been fine: it
/// splits the files by their own pixel size and always has. Only the count was
/// wrong, and it blocked the submission.
struct ScreenshotDisplayTypeCountTests {

    /// A real PNG of exactly these dimensions. The dimensions are the whole
    /// point: they are what picks the display type.
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

    private func write(_ sizes: [(Int, Int)]) throws -> (root: URL, paths: [String]) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ss-shots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var paths: [String] = []
        for (index, size) in sizes.enumerated() {
            let name = "shot-\(index)-\(size.0)x\(size.1).png"
            try png(size.0, size.1)
                .write(to: root.appendingPathComponent(name))
            paths.append(name)
        }
        return (root, paths)
    }

    /// The reported shape: five pictures at each of two iPhone sizes. Fourteen
    /// in one bucket, and not one display type over the limit.
    @Test func theSamePicturesAtTwoSizesAreTwoSets() throws {
        let (root, paths) = try write(Array(repeating: (1284, 2778), count: 5)
                                      + Array(repeating: (1320, 2868), count: 5))
        defer { try? FileManager.default.removeItem(at: root) }

        let counts = Validator.appleDisplayTypeCounts(paths, root: root, deviceClass: .phone)

        #expect(counts["APP_IPHONE_67"] == 5)
        #expect(counts["APP_IPHONE_69"] == 5)
        #expect(counts.values.allSatisfy { $0 <= 10 })
    }

    /// The limit still bites where Apple actually applies it.
    @Test func elevenOfOneSizeIsStillTooMany() throws {
        let (root, paths) = try write(Array(repeating: (1284, 2778), count: 11))
        defer { try? FileManager.default.removeItem(at: root) }

        let counts = Validator.appleDisplayTypeCounts(paths, root: root, deviceClass: .phone)

        #expect(counts["APP_IPHONE_67"] == 11)
    }

    /// A size Apple does not recognise is left out. The size check reports it
    /// already, and counting it under a made-up heading would report one file
    /// twice under two different words.
    @Test func anUnknownSizeIsNotCountedUnderAnyType() throws {
        let (root, paths) = try write([(123, 456)])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(Validator.appleDisplayTypeCounts(paths, root: root, deviceClass: .phone).isEmpty)
    }

    @Test func aFileThatIsNotThereCountsAgainstNothing() {
        #expect(Validator.appleDisplayTypeCounts(["gone.png"], root: nil,
                                                 deviceClass: .phone).isEmpty)
    }
}

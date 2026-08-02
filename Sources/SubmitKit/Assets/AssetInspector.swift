import AVFoundation
import Foundation
import ImageIO

public struct ImageAssetInfo: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let fileSize: Int64

    public init(width: Int, height: Int, fileSize: Int64) {
        self.width = width
        self.height = height
        self.fileSize = fileSize
    }
}

public enum AssetInspectionError: Error, LocalizedError, Equatable {
    case unreadableImage(String)
    case unsupportedImageType(String)
    case unsupportedVideoType(String)
    case invalidPreviewDuration(Double)
    case unsupportedDimensions(Int, Int, String, String?)
    case missingDimensionCatalog

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let name): "Could not read the dimensions of \(name)."
        case .unsupportedImageType(let type): "Screenshots must be PNG, JPG, or JPEG, not .\(type)."
        case .unsupportedVideoType(let type): "App previews must be MOV, M4V, or MP4, not .\(type)."
        case .invalidPreviewDuration(let seconds):
            "App previews must be 15 to 30 seconds. This file is \(Int(seconds.rounded())) seconds."
        case .unsupportedDimensions(let width, let height, let device, let nearest):
            "\(width) × \(height) is not accepted for \(device)."
                + (nearest.map { " The nearest accepted size is \($0)." } ?? "")
        case .missingDimensionCatalog:
            "The screenshot dimension catalog could not be loaded."
        }
    }
}

public enum AssetInspector {
    public static func image(at url: URL) throws -> ImageAssetInfo {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg"].contains(ext) else {
            throw AssetInspectionError.unsupportedImageType(ext)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw AssetInspectionError.unreadableImage(url.lastPathComponent)
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ImageAssetInfo(width: width, height: height, fileSize: size)
    }

    public static func validatePreview(at url: URL) async throws -> Double {
        let ext = url.pathExtension.lowercased()
        guard ["mov", "m4v", "mp4"].contains(ext) else {
            throw AssetInspectionError.unsupportedVideoType(ext)
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds >= 15, seconds <= 30 else {
            throw AssetInspectionError.invalidPreviewDuration(seconds)
        }
        return seconds
    }

    /// Validates the hard upload rules for every selected store. Apple uses
    /// exact display sizes; Google accepts a bounded range and aspect ratio.
    @discardableResult
    public static func validateImage(at url: URL, deviceClass: Manifest.DeviceClass,
                                     stores: Set<Store>) throws -> ImageAssetInfo {
        let info = try image(at: url)
        try validateDimensions(info, deviceClass: deviceClass, stores: stores)
        return info
    }

    public static func validateDimensions(_ info: ImageAssetInfo,
                                          deviceClass: Manifest.DeviceClass,
                                          stores: Set<Store>) throws {
        _ = try compatibleStores(for: info, deviceClass: deviceClass, selectedStores: stores)
    }

    /// Returns the selected stores that can receive this image. Store routing
    /// is derived from dimensions because Apple and Google frequently accept
    /// different aspect ratios for the same manifest device class.
    public static func compatibleStores(for info: ImageAssetInfo,
                                        deviceClass: Manifest.DeviceClass,
                                        selectedStores: Set<Store>) throws -> Set<Store> {
        var compatible: Set<Store> = []
        var appleNearest: String?
        if selectedStores.contains(.apple), let accepted = try appleSizes()[deviceClass.rawValue] {
            let dimensions = normalized(info.width, info.height)
            if accepted.contains(where: { normalized($0[0], $0[1]) == dimensions }) {
                compatible.insert(.apple)
            } else {
                appleNearest = accepted.min {
                    distance(dimensions, normalized($0[0], $0[1]))
                        < distance(dimensions, normalized($1[0], $1[1]))
                }.map { "\($0[0]) × \($0[1])" }
            }
        }

        if selectedStores.contains(.google), ![.desktop, .vision].contains(deviceClass) {
            let short = min(info.width, info.height)
            let long = max(info.width, info.height)
            let validGeneralSize = short >= 320 && long <= 3_840 && long <= short * 2
            let validWatch = deviceClass != .watch || (info.width == info.height && short >= 384)
            if validGeneralSize && validWatch { compatible.insert(.google) }
        }

        guard !compatible.isEmpty else {
            let nearest = appleNearest ?? (deviceClass == .watch
                ? "384 × 384 or larger square"
                : "320–3840 px, at most 2:1")
            throw AssetInspectionError.unsupportedDimensions(
                info.width, info.height, deviceClass.rawValue, nearest)
        }
        return compatible
    }

    /// The Apple `screenshotDisplayType` for one file. Spec section 6.3: the
    /// pixel dimensions pick the bucket, never the folder name.
    ///
    /// `// ponytail: a lookup table, not a device database. Add a size to the
    /// // JSON when Apple ships a new screen.`
    public static func appleDisplayType(for info: ImageAssetInfo,
                                        deviceClass: Manifest.DeviceClass) throws -> String? {
        if deviceClass == .vision { return "APP_APPLE_VISION_PRO" }
        let (short, long) = normalized(info.width, info.height)
        return try catalog().appleDisplayTypes["\(short)x\(long)"]
    }

    /// The Google `imageType`. Google sorts by device class, so this needs no
    /// dimensions. Spec section 6.3.
    public static func googleImageType(for deviceClass: Manifest.DeviceClass) -> String? {
        switch deviceClass {
        case .phone: "phoneScreenshots"
        case .tablet7: "sevenInchScreenshots"
        case .tablet10: "tenInchScreenshots"
        case .tv: "tvScreenshots"
        case .watch: "wearScreenshots"
        case .desktop, .vision: nil
        }
    }

    private struct ScreenshotCatalog: Decodable {
        let apple: [String: [[Int]]]
        let appleDisplayTypes: [String: String]
    }

    private static func catalog() throws -> ScreenshotCatalog {
        guard let url = Bundle.module.url(forResource: "screenshot-sizes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ScreenshotCatalog.self, from: data) else {
            throw AssetInspectionError.missingDimensionCatalog
        }
        return catalog
    }

    private static func appleSizes() throws -> [String: [[Int]]] {
        try catalog().apple
    }

    private static func normalized(_ width: Int, _ height: Int) -> (Int, Int) {
        (min(width, height), max(width, height))
    }

    private static func distance(_ lhs: (Int, Int), _ rhs: (Int, Int)) -> Int {
        abs(lhs.0 - rhs.0) + abs(lhs.1 - rhs.1)
    }
}

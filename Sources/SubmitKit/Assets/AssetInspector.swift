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
        return try catalog().appleDisplayTypes[sizeKey(info.width, info.height)]
    }

    /// The device class behind an Apple `screenshotDisplayType`.
    ///
    /// It comes out of the same table the upload uses. A second hand-written
    /// list is what broke the import: it never named `APP_IPHONE_69`, so the
    /// 6.9 inch set that every current app ships vanished on the way in, and
    /// the Media tab opened empty on an app whose store is full.
    ///
    /// Nil for an unknown type, so a display type Apple adds tomorrow costs
    /// that one bucket and never the import.
    public static func deviceClass(forAppleDisplayType type: String) -> Manifest.DeviceClass? {
        appleDeviceClasses[type]
    }

    /// Built once. The catalog is a file read and this runs per screenshot.
    private static let appleDeviceClasses: [String: Manifest.DeviceClass] = {
        guard let catalog = try? catalog() else { return [:] }
        var result: [String: Manifest.DeviceClass] = [
            // No size row of its own: vision shares 3840 x 2160 with the TV,
            // so `appleDisplayType` special-cases it and so does this.
            "APP_APPLE_VISION_PRO": .vision,
            // The pre-3rd-generation 12.9 inch iPad. Apple still answers with
            // it for an older screenshot set, and it shares its pixels with
            // `APP_IPAD_PRO_3GEN_129`, so no size row names it.
            "APP_IPAD_PRO_129": .tablet10,
        ]
        // In `allCases` order, not dictionary order, and the first class to
        // claim a display type keeps it. The TV and the vision share 3840 x
        // 2160, so an unordered walk would hand `APP_APPLE_TV` to whichever
        // one the hash table listed first that day.
        for deviceClass in Manifest.DeviceClass.allCases {
            for size in catalog.apple[deviceClass.rawValue] ?? [] where size.count == 2 {
                guard let type = catalog.appleDisplayTypes[sizeKey(size[0], size[1])] else {
                    continue
                }
                if result[type] == nil { result[type] = deviceClass }
            }
        }
        return result
    }()

    /// The shape of one device class's screen, width over height.
    ///
    /// It comes out of the same catalog the upload reads, so a tile can never
    /// draw a shape the app would refuse to accept. A hand-written copy here
    /// is what this file has already been burned by twice.
    ///
    /// The small Android tablet has no Apple size of its own, so it takes the
    /// portrait shape Google asks for.
    public static func aspectRatio(for deviceClass: Manifest.DeviceClass) -> Double {
        guard let size = (try? appleSizes())?[deviceClass.rawValue]?.first,
              size.count == 2, size[1] != 0 else { return 0.6 }
        return Double(size[0]) / Double(size[1])
    }

    /// Every pixel size the App Store takes for one device class, widest
    /// first, as "1290 × 2796".
    ///
    /// The same catalog the upload validates against, so a size named on the
    /// screen is a size the app will accept. Empty for a class the App Store
    /// does not carry, which is the small Android tablet.
    public static func appleSizeLabels(for deviceClass: Manifest.DeviceClass) -> [String] {
        ((try? appleSizes())?[deviceClass.rawValue] ?? [])
            .filter { $0.count == 2 }
            .map { "\($0[0]) × \($0[1])" }
    }

    /// Every App Store display type, largest screen first, with the name App
    /// Store Connect prints beside it in Media Manager.
    ///
    /// A table and not a rule read off the name. `APP_IPHONE_69` is 6.9 inch
    /// and `APP_IPAD_PRO_3GEN_11` is 11 inch, so the digits alone answer
    /// nothing: the same two characters mean tenths in one and units in the
    /// other. The watch names a series and no size at all.
    public static let appleDisplayTypeNames: [(type: String, name: String)] = [
        ("APP_IPHONE_69", "iPhone 6.9 inch"),
        ("APP_IPHONE_67", "iPhone 6.7 inch"),
        ("APP_IPHONE_65", "iPhone 6.5 inch"),
        ("APP_IPHONE_61", "iPhone 6.1 inch"),
        ("APP_IPHONE_58", "iPhone 5.8 inch"),
        ("APP_IPHONE_55", "iPhone 5.5 inch"),
        ("APP_IPHONE_47", "iPhone 4.7 inch"),
        ("APP_IPHONE_40", "iPhone 4 inch"),
        ("APP_IPHONE_35", "iPhone 3.5 inch"),
        ("APP_IPAD_PRO_3GEN_129", "iPad Pro 12.9 inch"),
        ("APP_IPAD_PRO_129", "iPad Pro 12.9 inch (2nd generation)"),
        ("APP_IPAD_PRO_3GEN_11", "iPad Pro 11 inch"),
        ("APP_IPAD_105", "iPad 10.5 inch"),
        ("APP_IPAD_97", "iPad 9.7 inch"),
        ("APP_DESKTOP", "Mac"),
        ("APP_APPLE_VISION_PRO", "Apple Vision Pro"),
        ("APP_APPLE_TV", "Apple TV"),
        ("APP_WATCH_ULTRA", "Apple Watch Ultra"),
        ("APP_WATCH_SERIES_10", "Apple Watch Series 10"),
        ("APP_WATCH_SERIES_7", "Apple Watch Series 7"),
        ("APP_WATCH_SERIES_4", "Apple Watch Series 4"),
        ("APP_WATCH_SERIES_3", "Apple Watch Series 3"),
    ]

    private static let appleDisplayNames: [String: String] =
        Dictionary(appleDisplayTypeNames.map { ($0.type, $0.name) }) { first, _ in first }

    private static let appleDisplayRanks: [String: Int] =
        Dictionary(appleDisplayTypeNames.enumerated().map { ($1.type, $0) }) { first, _ in first }

    /// What to call one screenshot set on the screen. A type this build has
    /// never heard of answers with the store's own name, which is still more
    /// use than nothing.
    public static func appleDisplayName(_ type: String) -> String {
        appleDisplayNames[type] ?? type
    }

    /// Media Manager's order: the largest screen of a family first. A type
    /// with no row sorts last and keeps its name for a tie break.
    public static func appleDisplayRank(_ type: String) -> Int {
        appleDisplayRanks[type] ?? appleDisplayTypeNames.count
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

    public static func applePreviewType(for deviceClass: Manifest.DeviceClass) -> String? {
        switch deviceClass {
        case .phone: "APP_IPHONE_67"
        case .tablet7, .tablet10: "APP_IPAD_PRO_3GEN_129"
        case .desktop: "APP_DESKTOP"
        case .tv: "APP_APPLE_TV"
        case .vision: "APP_APPLE_VISION_PRO"
        case .watch: nil
        }
    }

    private struct ScreenshotCatalog: Decodable {
        let apple: [String: [[Int]]]
        let appleDisplayTypes: [String: String]
    }

    private static func catalog() throws -> ScreenshotCatalog {
        #if SWIFT_PACKAGE
        let resourceBundle = Bundle.module
        #else
        let resourceBundle = Bundle(for: SubmitKitBundleToken.self)
        #endif
        guard let url = resourceBundle.url(forResource: "screenshot-sizes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ScreenshotCatalog.self, from: data) else {
            throw AssetInspectionError.missingDimensionCatalog
        }
        // The file writes a phone size portrait and a desktop or TV size
        // landscape, the way each store's own documentation writes them. The
        // lookup takes one shape, so every key becomes short x long here. It
        // was landscape keys against a portrait lookup that left a Mac and a
        // TV screenshot with no display type at all.
        return ScreenshotCatalog(
            apple: catalog.apple,
            appleDisplayTypes: Dictionary(
                catalog.appleDisplayTypes.map { (normalizedSizeKey($0.key), $0.value) },
                uniquingKeysWith: { first, _ in first }))
    }

    private static func appleSizes() throws -> [String: [[Int]]] {
        try catalog().apple
    }

    private static func normalized(_ width: Int, _ height: Int) -> (Int, Int) {
        (min(width, height), max(width, height))
    }

    private static func sizeKey(_ width: Int, _ height: Int) -> String {
        let (short, long) = normalized(width, height)
        return "\(short)x\(long)"
    }

    private static func normalizedSizeKey(_ key: String) -> String {
        let parts = key.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return key }
        return sizeKey(parts[0], parts[1])
    }

    private static func distance(_ lhs: (Int, Int), _ rhs: (Int, Int)) -> Int {
        abs(lhs.0 - rhs.0) + abs(lhs.1 - rhs.1)
    }
}

#if !SWIFT_PACKAGE
private final class SubmitKitBundleToken {}
#endif

import AppKit
import Foundation
import Testing

/// macOS draws every Dock icon on one grid: the artwork is a 1024 point canvas
/// with the shape inside a centred 824 point box. Icon Composer exports iOS
/// art, which fills all 1024 points, and that icon then sits about a quarter
/// larger than every neighbour in the Dock.
///
/// Regenerate with `swift Supporting/make-macos-icons.swift .` after any
/// export.
@Test func theAppIconLeavesTheMarginMacOSExpects() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let icons = [
        "Supporting/Assets.xcassets/AppIcon.appiconset/icon_1024.png",
        "Supporting/Assets.xcassets/AppIcon.appiconset/icon_512.png",
        "Sources/SuperSubmitter/Resources/AppIcon.png",
    ]

    for path in icons {
        let url = root.appendingPathComponent(path)
        let image = try #require(NSImage(contentsOf: url), "Missing \(path)")
        let data = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        let ratio = try #require(opaqueWidthRatio(rep))
        // 824 of 1024, with room for the antialiased edge.
        #expect(ratio > 0.78 && ratio < 0.83,
                "\(path) covers \(Int(ratio * 100))% of its canvas, not about 80%.")
    }
}

private func opaqueWidthRatio(_ rep: NSBitmapImageRep) -> Double? {
    let width = rep.pixelsWide, height = rep.pixelsHigh
    var minX = width, maxX = -1
    for y in stride(from: 0, to: height, by: 4) {
        for x in 0..<width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
            minX = min(minX, x)
            maxX = max(maxX, x)
        }
    }
    guard maxX >= minX else { return nil }
    return Double(maxX - minX + 1) / Double(width)
}

#!/usr/bin/env swift
import AppKit

// Icon Composer exports iOS art: the squircle fills all 1024 points and
// touches every edge. macOS asks for the same squircle drawn at 824 points
// inside a 1024 canvas, so the Dock can line every icon up on one grid. An
// iOS export used as a macOS icon therefore sits about a quarter too large.
//
// This rebuilds the whole set from the full-bleed master. It reads
// AppIcon-source-1024.png and never an output, so a second run is a no-op.
let body: CGFloat = 824
let canvas: CGFloat = 1024
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
               ?? FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Supporting/AppIcon-source-1024.png")

guard let art = NSImage(contentsOf: source) else {
    FileHandle.standardError.write(Data("No master at \(source.path)\n".utf8))
    exit(1)
}

func write(_ size: Int, to url: URL) {
    let side = CGFloat(size)
    let inset = (canvas - body) / 2 * side / canvas
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    art.draw(in: NSRect(x: inset, y: inset,
                        width: side - inset * 2, height: side - inset * 2))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    print("wrote \(url.lastPathComponent) at \(size)")
}

let set = root.appendingPathComponent("Supporting/Assets.xcassets/AppIcon.appiconset")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    write(size, to: set.appendingPathComponent("icon_\(size).png"))
}
// The SwiftPM executable has no bundle icon, so it sets this one at launch.
write(1024, to: root.appendingPathComponent("Sources/SuperSubmitter/Resources/AppIcon.png"))

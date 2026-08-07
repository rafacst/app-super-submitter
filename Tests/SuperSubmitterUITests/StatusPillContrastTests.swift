import AppKit
import SwiftUI
import Testing
@testable import SuperSubmitter

/// The status pills, against the surface they are actually drawn on.
///
/// Every text tier in `Theme` is tuned against the page. A status pill is the
/// one place that rule does not cover: it puts the word on its own hue at a
/// tenth, which lifts the floor under the text and takes the ratio down with
/// it. Measured off the shipped Release tab, "Done" read 4.23 to 1 and
/// "Needed" 4.38 to 1 — both under the 4.5 to 1 that WCAG 1.4.3 asks of body
/// text, while the same two tints cleared it easily everywhere else.
///
/// The check composites the way the screen does, so it fails if either half of
/// a pair moves: a lighter tint, or a heavier background.

/// The components of a colour as one appearance resolves it.
@MainActor
private func components(_ color: Color, _ appearance: NSAppearance.Name)
    -> (r: Double, g: Double, b: Double, a: Double) {
    var out = (r: 0.0, g: 0.0, b: 0.0, a: 0.0)
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
        out = (Double(ns.redComponent), Double(ns.greenComponent),
               Double(ns.blueComponent), Double(ns.alphaComponent))
    }
    return out
}

/// Lays a colour over an opaque one, the way the pill lays its fill on a card.
private func composite(_ top: (r: Double, g: Double, b: Double, a: Double),
                       over base: (r: Double, g: Double, b: Double, a: Double))
    -> (r: Double, g: Double, b: Double, a: Double) {
    (r: top.r * top.a + base.r * (1 - top.a),
     g: top.g * top.a + base.g * (1 - top.a),
     b: top.b * top.a + base.b * (1 - top.a),
     a: 1)
}

private func luminance(_ c: (r: Double, g: Double, b: Double, a: Double)) -> Double {
    func channel(_ v: Double) -> Double {
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

private func contrast(_ a: Double, _ b: Double) -> Double {
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

@MainActor
@Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
func everyStatusPillClearsTheBodyTextRatio(_ appearance: NSAppearance.Name) {
    // The card the pills sit on. A pill also lands on `content`, which is the
    // easier of the two to clear in light and the harder in dark, so both
    // surfaces are checked rather than the one that happened to be sampled.
    let surfaces = [("raised", Theme.raised), ("content", Theme.content)]

    let pairs: [(name: String, tint: Color, fill: Color)] = [
        ("Done", Theme.green, Theme.greenBg),
        ("Needed", Theme.yellow, Theme.yellowBg),
        ("Failed", Theme.red, Theme.redBg),
        // Not a tinted pill, but the same shape at the same size, and it is
        // read on the same rows. It gets the same bar.
        ("Unknown", Theme.text2, Theme.sep2),
    ]

    for (surfaceName, surface) in surfaces {
        let base = components(surface, appearance)
        for pair in pairs {
            let text = luminance(components(pair.tint, appearance))
            let fill = luminance(composite(components(pair.fill, appearance), over: base))
            let ratio = contrast(text, fill)
            #expect(ratio >= 4.5, """
                The \(pair.name) pill reads \(String(format: "%.2f", ratio)) to 1 \
                on \(surfaceName) in \(appearance.rawValue).
                """)
        }
    }
}

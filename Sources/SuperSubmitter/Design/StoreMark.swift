import SubmitKit
import SwiftUI

/// The two store logos, drawn once and used on every tab.
///
/// Apple ships its logo as an SF Symbol. Google ships no symbol, so the Play
/// triangle is four filled paths in the four brand colours. A logo carries the
/// store faster than the words "App Store", so every place that names a store
/// shows the mark first and the name second.
struct StoreMark: View {
    let store: Store
    var size: CGFloat = 16

    var body: some View {
        switch store {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: size * 0.9))
                .foregroundStyle(Theme.appleMark)
                .frame(width: size, height: size)
        case .google:
            PlayMark().frame(width: size, height: size)
        }
    }
}

/// The Google Play triangle. Four triangles meet on the centre line: the spine
/// on the left, the tip on the right.
struct PlayMark: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let top = CGPoint(x: w * 0.11, y: h * 0.02)
            let foot = CGPoint(x: w * 0.11, y: h * 0.98)
            let waist = CGPoint(x: w * 0.11, y: h * 0.50)
            let fold = CGPoint(x: w * 0.60, y: h * 0.50)
            let tip = CGPoint(x: w * 0.98, y: h * 0.50)
            Self.fill(&context, [top, fold, waist], Theme.playBlue)
            Self.fill(&context, [waist, fold, foot], Theme.playGreen)
            Self.fill(&context, [top, tip, fold], Theme.playRed)
            Self.fill(&context, [fold, tip, foot], Theme.playYellow)
        }
    }

    private static func fill(_ context: inout GraphicsContext, _ points: [CGPoint], _ color: Color) {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}

/// The logo with the store name beside it.
struct StoreLabel: View {
    let store: Store
    var size: CGFloat = 13
    var weight: Font.Weight = .semibold
    var color: Color = Theme.text

    var body: some View {
        HStack(spacing: 7) {
            StoreMark(store: store, size: size + 2)
            Text(store.storeName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
        }
    }
}

extension Store {
    var storeName: String {
        switch self {
        case .apple: "App Store"
        case .google: "Google Play"
        }
    }

    /// The one colour that stands for the store on a chart, a chip, or a rail.
    var tint: Color {
        switch self {
        case .apple: Theme.appleMark
        case .google: Theme.playGreen
        }
    }
}

// MARK: - The icon chip used by every section header

/// A tinted glyph. It sits before a section title so a tab reads as a list of
/// pictures before it reads as a list of words.
struct IconChip: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29)
            .fill(tint.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

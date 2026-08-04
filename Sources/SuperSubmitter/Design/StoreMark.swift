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

/// The Google Play triangle of the 2022 icon. Four wedges meet at the fold, and
/// the outer corners are rounded. The coordinates below are the published
/// artwork on its own 28.99 x 31.99 artboard, scaled into whatever frame the
/// caller gives.
struct PlayMark: View {
    static let artboard = CGSize(width: 28.99, height: 31.99)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.artboard.width,
                            size.height / Self.artboard.height)
            context.translateBy(x: (size.width - Self.artboard.width * scale) / 2,
                                y: (size.height - Self.artboard.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for wedge in Self.wedges { context.fill(wedge.path, with: .color(wedge.color)) }
        }
    }

    struct Wedge {
        let path: Path
        let color: Color
    }

    static let wedges: [Wedge] = [
        Wedge(path: Pen(13.54, 15.28)
            .line(0.12, 29.34)
            .arc(5.45, 31.50, radius: 3.66)
            .line(20.55, 22.90)
            .close(), color: Theme.playRed),
        Wedge(path: Pen(27.11, 12.89)
            .line(20.58, 9.15)
            .line(13.23, 15.60)
            .line(20.61, 22.88)
            .line(27.09, 19.18)
            .arc(28.59, 14.39, radius: 3.54)
            .arc(27.09, 12.89, radius: 3.62)
            .close(), color: Theme.playYellow),
        Wedge(path: Pen(0.12, 2.66)
            .arc(0, 3.58, radius: 3.57)
            .line(0, 28.42)
            .arc(0.12, 29.34, radius: 3.57)
            .line(14, 15.64)
            .close(), color: Theme.playBlue),
        Wedge(path: Pen(13.64, 16)
            .line(20.58, 9.15)
            .line(5.5, 0.51)
            .arc(3.63, 0, radius: 3.73)
            .arc(0.12, 2.65, radius: 3.64)
            .close(), color: Theme.playGreen),
    ]
}

/// A cursor that replays the icon's SVG path commands, so the numbers above
/// stay in the order the artwork publishes them.
///
/// ponytail: every arc in this icon is circular, under a half turn, and turns
/// anticlockwise, so the endpoint-to-centre conversion only covers that case.
/// A second icon with other arc flags needs the full SVG rule.
struct Pen {
    private var path = Path()
    private var point: CGPoint

    init(_ x: CGFloat, _ y: CGFloat) {
        point = CGPoint(x: x, y: y)
        path.move(to: point)
    }

    func line(_ x: CGFloat, _ y: CGFloat) -> Pen {
        var next = self
        next.point = CGPoint(x: x, y: y)
        next.path.addLine(to: next.point)
        return next
    }

    func arc(_ x: CGFloat, _ y: CGFloat, radius: CGFloat) -> Pen {
        var next = self
        let end = CGPoint(x: x, y: y)
        let half = CGPoint(x: (point.x - end.x) / 2, y: (point.y - end.y) / 2)
        let span = half.x * half.x + half.y * half.y
        let reach = max(0, radius * radius - span) / max(span, .leastNonzeroMagnitude)
        // The centre sits off the chord's midpoint, on the side the sweep asks for.
        let offset = sqrt(reach)
        let centre = CGPoint(x: (point.x + end.x) / 2 - offset * half.y,
                             y: (point.y + end.y) / 2 + offset * half.x)
        next.path.addArc(
            center: centre, radius: radius,
            startAngle: .radians(atan2(point.y - centre.y, point.x - centre.x)),
            endAngle: .radians(atan2(end.y - centre.y, end.x - centre.x)),
            clockwise: true)
        next.point = end
        return next
    }

    func close() -> Path {
        var closed = path
        closed.closeSubpath()
        return closed
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

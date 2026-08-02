import SwiftUI

/// The nine tab icons, drawn as the mockup draws them.
///
/// They are not SF Symbols. The set carries two deliberate rhymes that a
/// symbol substitute would lose: tab 1 and tab 7 both show two panels, once
/// for the two stores and once for the two diff columns.
///
/// Every icon is a 16 by 16 stroke drawing at 1.35 points, scaled to the
/// requested size.
struct TabIcon: View {
    let tab: Tab
    var size: CGFloat = 15

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 16
            var transform = CGAffineTransform(scaleX: scale, y: scale)
            let path = Path(Self.path(for: tab).cgPath.copy(using: &transform) ?? .init(rect: .zero, transform: nil))
            context.stroke(
                path,
                with: .color(.primary),
                style: StrokeStyle(lineWidth: 1.35 * scale, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
    }

    static func path(for tab: Tab) -> Path {
        var p = Path()
        switch tab {
        case .stores:
            // Two panels: the two stores.
            p.addRoundedRect(in: CGRect(x: 1.5, y: 4, width: 5.5, height: 8), cornerSize: .init(width: 1.3, height: 1.3))
            p.addRoundedRect(in: CGRect(x: 9, y: 4, width: 5.5, height: 8), cornerSize: .init(width: 1.3, height: 1.3))
        case .build:
            // A box with a lid.
            p.addRoundedRect(in: CGRect(x: 2, y: 3.5, width: 12, height: 9), cornerSize: .init(width: 1.5, height: 1.5))
            p.move(to: .init(x: 2, y: 6.6)); p.addLine(to: .init(x: 14, y: 6.6))
        case .details:
            // Three lines of text, the last one short.
            p.move(to: .init(x: 2.5, y: 4.5)); p.addLine(to: .init(x: 13.5, y: 4.5))
            p.move(to: .init(x: 2.5, y: 8)); p.addLine(to: .init(x: 13.5, y: 8))
            p.move(to: .init(x: 2.5, y: 11.5)); p.addLine(to: .init(x: 9.5, y: 11.5))
        case .media:
            // A picture.
            p.addRoundedRect(in: CGRect(x: 2, y: 3, width: 12, height: 10), cornerSize: .init(width: 1.5, height: 1.5))
            p.addEllipse(in: CGRect(x: 4.5, y: 5.3, width: 2.2, height: 2.2))
            p.move(to: .init(x: 2.6, y: 12))
            p.addLine(to: .init(x: 6.6, y: 8.2))
            p.addLine(to: .init(x: 9.6, y: 10.8))
            p.addLine(to: .init(x: 11.8, y: 9))
            p.addLine(to: .init(x: 13.4, y: 10.4))
        case .money:
            p.addEllipse(in: CGRect(x: 2.4, y: 2.4, width: 11.2, height: 11.2))
            p.move(to: .init(x: 8, y: 4.6)); p.addLine(to: .init(x: 8, y: 11.4))
            p.move(to: .init(x: 9.9, y: 6.2))
            p.addLine(to: .init(x: 7.1, y: 6.2))
            p.addCurve(to: .init(x: 7.1, y: 9), control1: .init(x: 6.33, y: 6.2), control2: .init(x: 6.33, y: 9))
            p.addLine(to: .init(x: 8.9, y: 9))
            p.addCurve(to: .init(x: 8.9, y: 11.8), control1: .init(x: 9.67, y: 9), control2: .init(x: 9.67, y: 11.8))
            p.addLine(to: .init(x: 6.1, y: 11.8))
        case .marketing:
            // A cone that speaks outward: the store telling somebody.
            p.move(to: .init(x: 2, y: 6.4))
            p.addLine(to: .init(x: 6.2, y: 6.4))
            p.addLine(to: .init(x: 11.6, y: 3.2))
            p.addLine(to: .init(x: 11.6, y: 12.8))
            p.addLine(to: .init(x: 6.2, y: 9.6))
            p.addLine(to: .init(x: 2, y: 9.6))
            p.closeSubpath()
            p.move(to: .init(x: 4.6, y: 9.6))
            p.addLine(to: .init(x: 5.4, y: 13.4))
            p.move(to: .init(x: 13.4, y: 6.6))
            p.addLine(to: .init(x: 13.4, y: 9.4))
        case .reviewInfo:
            p.addRoundedRect(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11), cornerSize: .init(width: 1.5, height: 1.5))
            p.move(to: .init(x: 5.3, y: 8.2))
            p.addLine(to: .init(x: 7.2, y: 10))
            p.addLine(to: .init(x: 10.8, y: 6))
        case .plan:
            // Two columns: Apple on the left, Google on the right.
            p.addRoundedRect(in: CGRect(x: 2, y: 3, width: 5, height: 10), cornerSize: .init(width: 1, height: 1))
            p.addRoundedRect(in: CGRect(x: 9, y: 3, width: 5, height: 10), cornerSize: .init(width: 1, height: 1))
        case .submit:
            p.addEllipse(in: CGRect(x: 2.4, y: 2.4, width: 11.2, height: 11.2))
            p.move(to: .init(x: 8, y: 4.8)); p.addLine(to: .init(x: 8, y: 11.2))
            p.move(to: .init(x: 5.4, y: 8.6))
            p.addLine(to: .init(x: 8, y: 11.2))
            p.addLine(to: .init(x: 10.6, y: 8.6))
        case .release:
            p.move(to: .init(x: 4, y: 2.8))
            p.addLine(to: .init(x: 13, y: 8))
            p.addLine(to: .init(x: 4, y: 13.2))
            p.closeSubpath()
        }
        return p
    }
}

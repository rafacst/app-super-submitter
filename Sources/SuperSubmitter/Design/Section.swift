import SwiftUI

/// A titled block on a tab. The glyph carries the block faster than the words,
/// so a long tab reads as a column of pictures first.
///
/// It folds when the caller asks. `DisclosureGroup` was the first answer and it
/// is the wrong one here: it lays its chevron out against whatever the label
/// hands it, so a label of a title over a subtitle came out with the chevron
/// beside neither line. The row below draws the chevron itself, on the title's
/// own baseline, and every fold in the app is then the same shape.
struct Section_<Content: View>: View {
    let title: String
    var icon: String?
    var tint: Color = Theme.accent
    /// The `FieldIndex` id. A section is what the search jumps to when the
    /// fields under it repeat, which is every list of purchases, plans,
    /// offers, and pages.
    var anchor: String?
    /// Whether the header collapses the block.
    var folds = false
    /// The state a folding block opens in. A block whose fields are usually
    /// empty starts shut; a block the developer came for does not.
    var startsOpen = true
    /// The one line under the title. It belongs to a fold, which has to say
    /// what is inside it while it is shut.
    var note: String?
    @ViewBuilder let content: Content

    @State private var open: Bool?

    init(_ title: String, icon: String? = nil, tint: Color = Theme.accent,
         anchor: String? = nil, folds: Bool = false, startsOpen: Bool = true,
         note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.anchor = anchor
        self.folds = folds
        self.startsOpen = startsOpen
        self.note = note
        self.content = content()
    }

    private var isOpen: Bool { open ?? startsOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if folds {
                Button { open = !isOpen } label: { header }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            } else {
                header
            }
            if !folds || isOpen { content.transition(.opacity) }
        }
        // Only when nothing else supplies it. `storePanel` inside `foldBox`
        // already ends in the same frame, and asking for the full width *under*
        // padding makes the card the proposal plus its own inset: a folding
        // section came out 30 points wider than the column it stands in, which
        // pushed the store beside it off the right of the window.
        .frame(maxWidth: folds ? nil : .infinity, alignment: .leading)
        .foldBox(folds)
        .motion(.easeInOut(duration: 0.22), value: isOpen)
        .fieldAnchor(anchor)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if folds {
                Image(systemName: "chevron.right")
                    .font(Theme.font(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 10)
                    .motion(.easeOut(duration: 0.15), value: isOpen)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            if let icon {
                IconChip(symbol: icon, tint: tint, size: 21)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
            }
            VStack(alignment: .leading, spacing: 2) {
                // Sentence case, not ALL CAPS with kerning. Capitals cost
                // scan speed, because a word set in them loses the shape the
                // eye reads it by, and no macOS form heads its groups that
                // way. One struct, so this reaches every tab.
                Text(title).font(Theme.sectionHeader)
                    .foregroundStyle(icon == nil ? Theme.text3 : Theme.text2)
                if let note {
                    Text(note).font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

private extension View {
    /// The box a fold draws around itself: a title-high card while it is shut
    /// and the whole block once it is open.
    ///
    /// It lives here rather than at the call sites, because the two that drew
    /// their own put it in two different places. One wrapped the content, so a
    /// shut fold was a bare header row floating beside the cards it belongs
    /// with and an open one dropped a second panel in under the header. The
    /// other wrapped the whole section and was the only one that looked right.
    /// The clip is what turns the swap into a growth. Without it the fields
    /// arrive at full height inside a box that is still the height of a title,
    /// and they hang out of the bottom of it for the length of the animation.
    /// It stays inside this branch, because a section that never folds never
    /// changes height and clipping one could only cut something it draws.
    @ViewBuilder
    func foldBox(_ folds: Bool) -> some View {
        if folds {
            clipped().storePanel(padding: 14, horizontal: 15)
        } else {
            self
        }
    }
}

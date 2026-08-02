import SwiftUI

/// Tab 3. The listing text, one language at a time.
///
/// Every field carries a counter against the limit that binds both stores. A
/// field over the limit turns red. The app never shortens the text.
struct DetailsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            form
            if !state.keywordsFixed || true {
                preview
            }
        }
    }

    // MARK: - The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldRow(label: "Name", tag: "from the build", counter: "15 / 30") {
                TextWell("Fast Bill Split")
            }

            FieldRow(label: "Subtitle", note: "Apple 30 · Google 80",
                     counter: "26 / 30", link: "Different for Google") {
                TextWell("Split any bill in seconds")
            }

            FieldRow(label: "Description", counter: "318 / 4000") {
                TextWell("Split a restaurant bill with your friends. No account. No ads. Scan the receipt, tap the items each person ordered, and Fast Bill Split works out the tip and the tax for every share.",
                         height: 96)
            }

            FieldRow(label: "What is new", counter: "44 / 500", trailingNote: "Google override on") {
                VStack(alignment: .leading, spacing: 6) {
                    TextWell("Faster scanning and a new dark theme.")
                    HStack(spacing: 8) {
                        Tag("Google only")
                        TextWell("Faster scanning and a new dark theme.", size: 12.5)
                        Text("44 / 500").font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                keywords
                FieldRow(label: "Promotional text", tag: "Apple only", counter: "28 / 170") {
                    TextWell("Now with receipt scanning.")
                }
            }

            HStack(alignment: .top, spacing: 14) {
                FieldRow(label: "Short description", tag: "Google only") {
                    TextWell("Split any bill in seconds with your friends")
                }
                FieldRow(label: "Support URL") {
                    TextWell("https://fastbillsplit.app/support", mono: true)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one field that is over its limit. It is the error that blocks the
    /// whole apply, so it carries the loudest treatment on the tab.
    private var keywords: some View {
        let over = !state.keywordsFixed
        return FieldRow(
            label: "Keywords",
            tag: "Apple only",
            counter: over ? "104 / 100" : "95 / 100",
            counterColor: over ? Theme.red : Theme.text2,
            counterBold: over
        ) {
            VStack(alignment: .leading, spacing: 5) {
                TextWell(
                    over
                        ? "bill,split,tip,receipt,restaurant,dinner,share,check,tab,friends,group,payment"
                        : "bill,split,tip,receipt,restaurant,dinner,share,check,tab,friends",
                    border: over ? Theme.red : Theme.sep,
                    borderWidth: over ? 1 : Theme.hairline)

                if over {
                    HStack(spacing: 10) {
                        Text("4 characters over the limit. Apple refuses the write. This app never shortens your text.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { state.keywordsFixed = true } label: {
                            Text("Drop the last two (demo)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - What each store receives

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What each store receives")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text3)

            PreviewCard(
                header: "App Store · en-US",
                name: "Fast Bill Split",
                sub: "Split any bill in seconds",
                body: "Split a restaurant bill with your friends. No account. No ads. Scan the receipt, tap the items…",
                footer: state.keywordsFixed
                    ? "Keywords: 95 of 100 characters."
                    : "Keywords will not be written. 104 of 100 characters.",
                footerColor: state.keywordsFixed ? Theme.text2 : Theme.red)

            PreviewCard(
                header: "Google Play · en-US",
                name: "Fast Bill Split",
                sub: "Split any bill in seconds with your friends",
                body: "Split a restaurant bill with your friends. No account. No ads. Scan the receipt, tap the items…",
                footer: "Release note: 44 of 500 characters.",
                footerColor: Theme.text2)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(Theme.sunken)
    }
}

// MARK: - The parts

private struct FieldRow<Content: View>: View {
    let label: String
    var tag: String?
    var note: String?
    var counter: String?
    var counterColor: Color = Theme.text2
    var counterBold = false
    var link: String?
    var trailingNote: String?
    @ViewBuilder let content: Content

    init(label: String, tag: String? = nil, note: String? = nil, counter: String? = nil,
         counterColor: Color = Theme.text2, counterBold: Bool = false,
         link: String? = nil, trailingNote: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.label = label
        self.tag = tag
        self.note = note
        self.counter = counter
        self.counterColor = counterColor
        self.counterBold = counterBold
        self.link = link
        self.trailingNote = trailingNote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 7) {
                    Text(label).font(.system(size: 11.5, weight: .medium))
                    if let tag { Tag(tag) }
                    if let note {
                        Text(note).font(.system(size: 11)).foregroundStyle(Theme.text3)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    if let link {
                        Text(link).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    if let trailingNote {
                        Text(trailingNote).font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                    if let counter {
                        Text(counter)
                            .font(.system(size: 11, weight: counterBold ? .semibold : .regular))
                            .foregroundStyle(counterColor)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small outlined label that marks a field as belonging to one store.
struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 4)
            .padding(.vertical, 0.5)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

private struct TextWell: View {
    let text: String
    var size: CGFloat = 13
    var height: CGFloat?
    var mono = false
    var border: Color = Theme.sep
    var borderWidth: CGFloat = Theme.hairline

    init(_ text: String, size: CGFloat = 13, height: CGFloat? = nil, mono: Bool = false,
         border: Color = Theme.sep, borderWidth: CGFloat = Theme.hairline) {
        self.text = text
        self.size = size
        self.height = height
        self.mono = mono
        self.border = border
        self.borderWidth = borderWidth
    }

    var body: some View {
        Text(text)
            .font(mono ? Theme.mono(size) : .system(size: size))
            .lineSpacing(height == nil ? 2 : 5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height, alignment: .topLeading)
            .padding(.horizontal, 9)
            .padding(.vertical, height == nil ? 7 : 8)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(border, lineWidth: borderWidth))
    }
}

private struct PreviewCard: View {
    let header: String
    let name: String
    let sub: String
    let body_: String
    let footer: String
    let footerColor: Color

    init(header: String, name: String, sub: String, body: String,
         footer: String, footerColor: Color) {
        self.header = header
        self.name = name
        self.sub = sub
        self.body_ = body
        self.footer = footer
        self.footerColor = footerColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 15, weight: .semibold)).kerning(-0.15)
                    Text(sub).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Text(body_)
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(footer).font(.system(size: 11)).foregroundStyle(footerColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.content, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

import SwiftUI

/// ⌘F. "Which tab holds the privacy policy URL?"
///
/// Built by hand, and it has to be. `.searchable` needs a `NavigationStack` or
/// a `NavigationSplitView` above it, and this shell has neither by design: it
/// is an `HStack` of a floating panel and a content column. `.searchable` on
/// this hierarchy renders nothing at all.
///
/// It matches `FieldIndex`, a static list, because SwiftUI only ever builds
/// the open tab and a self-registering index would know one tab out of ten.
///
/// Every row is a path and not a pair. The old rows put the field name on the
/// left and the tab name hard against the right edge, forty points of gap
/// between them, which reads as two unrelated columns rather than as one place
/// inside another. A breadcrumb says the same two facts in the order you walk
/// them, and the arrow between them is what makes it a route. The keys that
/// drive the list are written along the bottom, because a palette that answers
/// the arrow keys and never says so is one most people only ever click.
struct FieldSearchSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// Seeded only by the screenshot harness, so the results list has
    /// something in it. Empty in every real launch.
    @State private var query = ScreenshotMode.fieldSearchQuery
    @State private var selection = 0
    @FocusState private var focused: Bool

    /// The list scrolls past this, and this is what the frame shows at once.
    private static let visibleRows = 8
    private static let rowHeight: CGFloat = 34

    private var results: [FieldEntry] { FieldIndex.matches(query) }

    var body: some View {
        VStack(spacing: 0) {
            field
            Hairline()
            if results.isEmpty {
                empty
            } else {
                list
                Hairline()
                footer
            }
        }
        .frame(width: 520)
        .frame(minHeight: results.isEmpty ? 150 : 0)
        .animation(.smooth(duration: 0.22), value: results.count)
        .background(Theme.content)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        // Escape closes it. The rows below take the arrows and Return, and
        // this catches the key whichever row holds the focus.
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) { open() }
    }

    // MARK: - The query

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(Theme.font(size: 13)).foregroundStyle(Theme.text3)
            TextField("Find a field", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.font(size: 15))
                .focused($focused)
                .onAppear { focused = true }
                // A new query invalidates the old row number, and a stale one
                // opens whatever now sits in that position.
                .onChange(of: query) { selection = 0 }
            KeyCap("esc")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(query.isEmpty ? "Type the name of a field."
                 : "No field matches \(query).")
                .font(Theme.font(size: 12.5))
                .foregroundStyle(Theme.text2)
            if query.isEmpty {
                Text("Super Submitter opens the tab and scrolls to it.")
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The routes

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Go to")
                .font(Theme.font(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                            row(entry, selected: index == selection)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                // The arrow keys walk past the eighth row, so the eighth row
                // has to come with them.
                .onChange(of: selection) {
                    guard results.indices.contains(selection) else { return }
                    proxy.scrollTo(results[selection].id, anchor: .bottom)
                }
            }
            .frame(maxHeight: CGFloat(Self.visibleRows) * Self.rowHeight + 12)
        }
    }

    /// One route: the tab it lives on, then the field itself.
    private func row(_ entry: FieldEntry, selected: Bool) -> some View {
        // A real Button, so a click works and VoiceOver reads it as something
        // you can press.
        Button { open(entry) } label: {
            HStack(spacing: 9) {
                Image(systemName: entry.tab.symbol)
                    .font(Theme.font(size: 12))
                    .foregroundStyle(selected ? Theme.accent : Theme.text3)
                    .frame(width: 17)

                Text(entry.tab.title(in: state.mode))
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(Theme.text2)
                Image(systemName: "chevron.right")
                    .font(Theme.font(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                Self.highlighted(entry.label, matching: query)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 10)
                // The arrow appears on the row Return would open, so the
                // keyboard and the pointer agree about which one that is.
                if selected {
                    Image(systemName: "arrow.right")
                        .font(Theme.font(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(selected ? Theme.accent.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.label), on \(entry.tab.title(in: state.mode))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The typed letters, marked inside the label they matched.
    ///
    /// It answers "why is this row here", which matters most on the rows that
    /// match a keyword rather than the visible name. Diacritic insensitive, the
    /// same comparison `FieldIndex` uses to find them.
    static func highlighted(_ text: String, matching query: String) -> Text {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              let range = text.range(of: needle,
                                     options: [.caseInsensitive, .diacriticInsensitive])
        else { return Text(text) }
        return Text(String(text[text.startIndex..<range.lowerBound]))
            + Text(String(text[range])).foregroundColor(Theme.accent).bold()
            + Text(String(text[range.upperBound...]))
    }

    // MARK: - The keys

    private var footer: some View {
        HStack(spacing: 14) {
            hint(["arrow.up", "arrow.down"], "to navigate")
            hint(["return"], "to open")
            Spacer(minLength: 0)
            Text("\(results.count) \(results.count == 1 ? "field" : "fields")")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.text3)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.raised)
        .accessibilityHidden(true)
    }

    private func hint(_ symbols: [String], _ label: String) -> some View {
        HStack(spacing: 5) {
            ForEach(symbols, id: \.self) { KeyCap(symbol: $0) }
            Text(label).font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
        }
    }

    // MARK: - Driving it

    private func move(_ offset: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        selection = min(max(selection + offset, 0), results.count - 1)
        return .handled
    }

    private func open() -> KeyPress.Result {
        guard results.indices.contains(selection) else { return .ignored }
        open(results[selection])
        return .handled
    }

    private func open(_ entry: FieldEntry) {
        // Dismiss first. The shell hosts one sheet, and the scroll it is about
        // to run happens behind this one.
        dismiss()
        state.jump(to: entry)
    }
}

/// One key, drawn as a key.
private struct KeyCap: View {
    private let symbol: String?
    private let text: String?

    init(_ text: String) {
        self.text = text
        self.symbol = nil
    }

    init(symbol: String) {
        self.symbol = symbol
        self.text = nil
    }

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(Theme.font(size: 9, weight: .semibold))
            } else {
                Text(text ?? "").font(Theme.font(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(Theme.text3)
        .frame(minWidth: 18, minHeight: 17)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
    }
}

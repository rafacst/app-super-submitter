import SubmitKit
import SwiftUI

/// One answer the palette can give.
///
/// Two kinds, and one list. A developer who types "privacy" wants the field
/// they fill in and the console step that field cannot satisfy, and asking
/// which of the two they meant is asking them to know the answer first.
enum PaletteMatch: Identifiable, Equatable {
    /// A place in this app, which the palette walks to.
    case field(FieldEntry)
    /// A step in somebody else's console, which the palette opens in a browser
    /// because there is nothing here that can perform it.
    case step(ConsoleRow)

    var id: String {
        switch self {
        case .field(let entry): "field.\(entry.id)"
        case .step(let row): "step.\(row.id)"
        }
    }

    /// The steps still open, matched on the words a developer would type: the
    /// title, the store that asks for it, and the sentence that says why.
    ///
    /// Only the open ones. A palette that lists a step already done offers a
    /// trip to a console to read a tick.
    static func steps(_ query: String, in rows: [ConsoleRow]) -> [ConsoleRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return rows.filter {
            $0.title.containsCaseInsensitive(needle)
                || $0.system.containsCaseInsensitive(needle)
                || $0.reason.containsCaseInsensitive(needle)
        }
    }
}

/// ⌘F. "Which tab holds the privacy policy URL?" — and "what does the App
/// Store still want from me about privacy?"
///
/// One query, two kinds of answer, because a developer who types a word does
/// not know in advance whether this app can satisfy it. A field is a place
/// here and the palette walks to it. A console step is work in somebody else's
/// website and the palette opens it, which is the whole of what any screen in
/// this app can do about one.
///
/// No docs section, and the design draws one. There is no help corpus to
/// index: the explanations in this app are notes attached to the fields they
/// explain, and a third of a palette that answers nothing is worse than a
/// palette with two thirds.
///
/// Built by hand, and it has to be. `.searchable` needs a `NavigationStack` or
/// a `NavigationSplitView` above it, and this shell has neither by design: it
/// is an `HStack` of a floating panel and a content column. `.searchable` on
/// this hierarchy renders nothing at all.
///
/// The fields match `FieldIndex`, a static list, because SwiftUI only ever
/// builds the open tab and a self-registering index would know one tab out of
/// ten. The steps match `consoleRows`, which is the opposite: it is read from
/// the stores and it is empty until a run fills it.
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

    /// The fields first, then the steps. A field is somewhere to go and a step
    /// is a trip out of the app, so the cheaper answer is offered first.
    private var results: [PaletteMatch] {
        FieldIndex.matches(query).map(PaletteMatch.field)
            + PaletteMatch.steps(query, in: state.openConsoleSteps).map(PaletteMatch.step)
    }

    private var fields: [PaletteMatch] { results.filter { if case .field = $0 { true } else { false } } }
    private var steps: [PaletteMatch] { results.filter { if case .step = $0 { true } else { false } } }

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
        .motion(.smooth(duration: 0.22), value: results.count)
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
            TextField("Find a field or a step", text: $query)
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
            Text(query.isEmpty ? "Type the name of a field or a console step."
                 : "Nothing matches \(query).")
                .font(Theme.font(size: 12.5))
                .foregroundStyle(Theme.text2)
            if query.isEmpty {
                Text("A field opens its tab. A step opens the console that asks for it.")
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The routes

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // One flat selection over two headed groups. The arrow keys
                // walk from the last field into the first step without
                // stopping, because a heading is a label and not a row.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if !fields.isEmpty { heading("Fields") }
                    rows(fields, from: 0)
                    if !steps.isEmpty { heading("Do") }
                    rows(steps, from: fields.count)
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

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func rows(_ matches: [PaletteMatch], from offset: Int) -> some View {
        ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
            row(match, selected: index + offset == selection)
                .id(match.id)
        }
    }

    @ViewBuilder
    private func row(_ match: PaletteMatch, selected: Bool) -> some View {
        switch match {
        case .field(let entry): fieldRow(entry, selected: selected)
        case .step(let step): stepRow(step, selected: selected)
        }
    }

    /// One console step: whose console it is, what it wants, and the arrow that
    /// says this one leaves the app.
    private func stepRow(_ step: ConsoleRow, selected: Bool) -> some View {
        Button { open(.step(step)) } label: {
            HStack(spacing: 9) {
                if let store = step.store {
                    StoreMark(store: store, size: 13).frame(width: 17)
                } else {
                    Image(systemName: "cart.fill")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 17)
                }

                Text(step.system)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(Theme.text2)
                Image(systemName: "chevron.right")
                    .font(Theme.font(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                Self.highlighted(step.title, matching: query)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 10)
                Image(systemName: "arrow.up.forward.square")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(selected ? Theme.accent : Theme.text3)
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(selected ? Theme.accent.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(step.title), a step in \(step.system)")
        .accessibilityHint("Opens the console in your browser")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// One route: the tab it lives on, then the field itself.
    private func fieldRow(_ entry: FieldEntry, selected: Bool) -> some View {
        // A real Button, so a click works and VoiceOver reads it as something
        // you can press.
        Button { open(.field(entry)) } label: {
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
            Text("\(results.count) \(results.count == 1 ? "result" : "results")")
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

    private func open(_ match: PaletteMatch) {
        // Dismiss first. The shell hosts one sheet, and the scroll it is about
        // to run happens behind this one.
        dismiss()
        switch match {
        case .field(let entry): state.jump(to: entry)
        case .step(let step): state.open(step.link)
        }
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

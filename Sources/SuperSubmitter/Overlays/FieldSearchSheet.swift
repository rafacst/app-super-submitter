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
struct FieldSearchSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// Seeded only by the screenshot harness, so the results list has
    /// something in it. Empty in every real launch.
    @State private var query = ScreenshotMode.fieldSearchQuery
    @State private var selection = 0
    @FocusState private var focused: Bool

    /// Twelve is what the frame below holds. A palette that scrolls to answer
    /// "where is this field" has already failed to answer it.
    private static let maxRows = 12

    private var results: [FieldEntry] {
        Array(FieldIndex.matches(query).prefix(Self.maxRows))
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            Hairline()
            if results.isEmpty {
                empty
            } else {
                list
            }
        }
        // Sized to the answer, not to the worst case. It was 460 by 360
        // whatever it held, so five results sat in a panel built for twelve
        // and two thirds of it was empty.
        //
        // The empty state keeps a floor, because a palette that opens as a
        // one-line strip and then jumps to full height on the first keystroke
        // is worse than one that never moves.
        .frame(width: 460)
        .frame(minHeight: results.isEmpty ? 148 : 0)
        .animation(.smooth(duration: 0.22), value: results.count)
        // The one sheet in the app that takes glass. It is a small thing over
        // the top of the work rather than a screen of fields, which is the
        // case the material was made for. The dense sheets stay opaque: glass
        // under body copy is a legibility regression.
        .floatingSurface()
        // Escape closes it. The rows below take the arrows and Return, and
        // this catches the key whichever row holds the focus.
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) { open() }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
            TextField("Find a field", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onAppear { focused = true }
                // A new query invalidates the old row number, and a stale one
                // opens whatever now sits in that position.
                .onChange(of: query) { selection = 0 }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(query.isEmpty ? "Type the name of a field."
                 : "No field matches \(query).")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
            if query.isEmpty {
                Text("Super Submitter opens the tab and scrolls to it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                    // A real Button, so a click works and VoiceOver reads it
                    // as something you can press.
                    Button { open(entry) } label: {
                        HStack(spacing: 10) {
                            Text(entry.label)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 12)
                            Text(entry.tab.title)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.text2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == selection ? Theme.accent.opacity(0.16) : .clear)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(entry.label), on \(entry.tab.title)")
                }
            }
        }
    }

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

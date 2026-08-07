import SubmitKit
import SwiftUI

/// Picks one value from a list, and shows the words rather than the code.
///
/// The manifest keeps `FOOD_AND_DRINK` because that is what Apple takes. The
/// screen says "Food and drink", because nobody should have to learn Apple's
/// spelling to fill in a form. `StoreValues` holds the map.
///
/// A value the manifest holds and no list carries still shows, as its own
/// code. The chooser never drops it, and the raw YAML side of the tab writes
/// a value the stores added after this build shipped.
struct ChoiceField: View {
    @Binding var value: String
    let choices: [StoreValues.Choice]
    var emptyLabel = "Not set"
    /// Offers a row that clears the field. A category can be left out; a
    /// currency on a price that exists cannot.
    var allowsNone = true

    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                Text(value.isEmpty ? emptyLabel : ChoiceText.label(for: value, in: choices))
                    .font(.system(size: 12))
                    .foregroundStyle(value.isEmpty ? Theme.text3 : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ChoiceList(choices: ChoiceText.rows(for: value, in: choices),
                       chosen: value.isEmpty ? [] : [value],
                       noneLabel: allowsNone ? emptyLabel : nil,
                       clear: { value = ""; open = false },
                       pick: { value = $0; open = false })
        }
        .accessibilityLabel(value.isEmpty ? emptyLabel
                            : ChoiceText.label(for: value, in: choices))
    }
}

/// Picks any number of values, and writes them back as the comma-separated
/// list the manifest already holds.
///
/// It replaced a text box that asked for `US, DE, BR`. Nobody knows every
/// country code, and a typo there reaches a real store.
struct MultiChoiceField: View {
    @Binding var text: String
    let choices: [StoreValues.Choice]
    /// What no selection means. It is never "nothing": an empty country list
    /// reaches every country, and the line has to say so.
    var emptyLabel: String

    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(alignment: .top, spacing: 6) {
                Text(ChoiceText.summary(of: text, in: choices, empty: emptyLabel))
                    .font(.system(size: 12))
                    .foregroundStyle(text.isEmpty ? Theme.text3 : Theme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ChoiceList(choices: ChoiceText.rows(for: text, in: choices),
                       chosen: Set(ChoiceText.values(from: text)),
                       noneLabel: nil,
                       clear: { text = "" },
                       pick: { text = ChoiceText.toggling($0, in: text) })
        }
        .accessibilityLabel(ChoiceText.summary(of: text, in: choices, empty: emptyLabel))
    }
}

/// The popover both choosers open: a search box over a list of words.
///
/// The search box appears once the list is long enough to scroll. A menu of
/// 266 territories is not a menu, it is a haystack.
private struct ChoiceList: View {
    let choices: [StoreValues.Choice]
    let chosen: Set<String>
    /// Nil on a multi-select, where "none" is simply nothing ticked.
    let noneLabel: String?
    let clear: () -> Void
    let pick: (String) -> Void

    @State private var search = ""

    private var searchable: Bool { choices.count > 12 }

    private var shown: [StoreValues.Choice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return choices }
        return choices.filter {
            $0.label.localizedCaseInsensitiveContains(query)
                || $0.value.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if searchable {
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                Divider()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let noneLabel, search.isEmpty {
                        row(label: noneLabel, ticked: chosen.isEmpty,
                            quiet: true, action: clear)
                        Divider().padding(.leading, 28)
                    }
                    ForEach(shown) { choice in
                        row(label: choice.label, ticked: chosen.contains(choice.value),
                            quiet: false) { pick(choice.value) }
                    }
                    if shown.isEmpty {
                        Text("Nothing matches.")
                            .font(.system(size: 12)).foregroundStyle(Theme.text3)
                            .padding(10)
                    }
                }
            }
            .frame(height: min(CGFloat(max(shown.count, 1)) * 24 + 8, 300))
            if chosen.count > 1 {
                Divider()
                HStack {
                    Text("\(chosen.count) chosen")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button("Clear", action: clear).controlSize(.small)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
            }
        }
        .frame(width: 290)
    }

    private func row(label: String, ticked: Bool, quiet: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(ticked ? 1 : 0)
                    .frame(width: 11)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(quiet ? Theme.text2 : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A path box that reports at once when the file it names is not there.
///
/// The rule lived in the Validator alone, and the Validator runs on the
/// Summary tab. A developer typed a path on Build, moved on, and met the fault
/// three tabs later beside a button that brought them back. The check costs one
/// `fileExists`, so it belongs where the path is entered.
struct PathField: View {
    @Binding var path: String
    var prompt = "Path, relative to the manifest"
    /// Nil while the path is good or empty. `AppState.missingFileNote`.
    let problem: String?
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(prompt, text: $path)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(problem == nil ? .clear : Theme.red, lineWidth: 1))
                    // Not a second label. A screen reader reads the value of
                    // the field it is on, so the fault travels with the field.
                    .accessibilityValue(problem ?? path)
                Button("Choose…", action: choose).controlSize(.small)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.red)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - The jump targets

/// Where the field search lands. `FieldIndex` holds the other half.
///
/// Its own type, and it has to be. A `ForEach` gives its rows an identity of
/// their own, often a `String` product id, and `.id()` matches on the value
/// **and** the type. A bare `String` anchor would answer to a row that happens
/// to spell itself the same way, and the scroll would land on the wrong thing.
struct FieldAnchor: Hashable {
    let id: String
}

extension View {
    /// Marks this view as the place `⌘F` scrolls to for `id`.
    ///
    /// Takes an optional, so a wrapper can pass its own `anchor` straight
    /// through without every call site needing one.
    @ViewBuilder
    func fieldAnchor(_ id: String?) -> some View {
        if let id { self.id(FieldAnchor(id: id)) } else { self }
    }
}

/// One labelled control. The label sits over the field, so a row of three
/// fields lines up whatever the label lengths are.
struct LabeledField<Content: View>: View {
    let label: String
    var note: String?
    var width: CGFloat?
    /// The `FieldIndex` id, on the fields the search can reach. Nil on a field
    /// inside a `ForEach`: one id repeated down a list is not an anchor, it is
    /// a duplicate identity. Those tabs anchor the section instead.
    var anchor: String?
    @ViewBuilder let content: Content

    init(_ label: String, note: String? = nil, width: CGFloat? = nil,
         anchor: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.note = note
        self.width = width
        self.anchor = anchor
        self.content = content()
    }

    /// A note long enough to be a sentence goes under the control instead of
    /// beside the label.
    ///
    /// Both kinds were on the label line. "comma-separated" belongs there: it
    /// qualifies the label and reads as part of it. "Optional. A bundle and an
    /// APK may go into one edit." does not — it is help, it is longer than the
    /// label it follows, and on a row of three fields it pushed the labels out
    /// of their column so there was no column left to scan.
    private var noteIsHelp: Bool { (note?.count ?? 0) > 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
                if let note, !noteIsHelp {
                    Text(note).font(.system(size: 10)).foregroundStyle(Theme.text3)
                }
            }
            content.frame(minHeight: 22)
            if let note, noteIsHelp {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .fieldAnchor(anchor)
        // The note is help for the field, so a reader meets it while it is on
        // the field rather than as a stray line after it.
        .accessibilityElement(children: .contain)
        .accessibilityHint(noteIsHelp ? (note ?? "") : "")
    }
}

/// A row of labelled fields that share the width.
///
/// It exists because a lone field on its own row grew to the whole panel, and
/// a path box 900 points wide says nothing that a box 300 points wide does
/// not. Two or three to a row, always.
struct FieldRow<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) { content }
    }
}

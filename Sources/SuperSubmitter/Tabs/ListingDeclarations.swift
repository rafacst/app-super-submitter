import SubmitKit
import SwiftUI

/// The categories, the store declarations, and the console checklist.
///
/// They sat on Review info, which asks "what does the reviewer need?". None
/// of them answers that: a category is what the listing says about itself, a
/// declaration is what the listing declares, and the console rows are the
/// parts of the listing no API will write. They belong with the listing.
struct ListingDeclarations: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 18) {
            categories
            declarations
        }
        .sheet(isPresented: $state.showAgeRating) { AgeRatingSheet().appMessage() }
        .sheet(isPresented: $state.showDataSafety) { DataSafetySheet().appMessage() }
    }

    private var categories: some View {
        Section_("Categories", icon: "square.grid.2x2.fill", tint: Theme.purple,
                 anchor: "details.categories") {
            VStack(alignment: .leading, spacing: 9) {
                if state.stores.contains(.apple) {
                    LabeledField("Primary", note: "Apple") {
                        ChoiceField(value: state.reviewBinding(.applePrimaryCategory),
                                    choices: state.appleCategoryChoices,
                                    emptyLabel: "Pick a category")
                    }
                    LabeledField("Secondary", note: "Apple, optional") {
                        ChoiceField(value: state.reviewBinding(.appleSecondaryCategory),
                                    choices: state.appleCategoryChoices, emptyLabel: "None")
                    }
                }
            }.storePanel()
        }
    }

    /// Four declarations, each on a chip of its own.
    ///
    /// They were four blocks in one box, separated by three `Divider`s. Evoque
    /// gives every row of its spec table the same soft rounded fill and puts a
    /// gap between them instead of a rule, and that is the better shape here:
    /// these four are unrelated errands, not four lines of one list, and a
    /// rule between them reads as continuation.
    ///
    /// It also adds no line at all, which the rule the `sep` comment sets asks
    /// for — dark mode has no shadow to fall back on, and every extra hairline
    /// spends the little contrast that boundary has.
    private var declarations: some View {
        Section_("Store declarations", icon: "checkmark.shield.fill", tint: Theme.green,
                 anchor: "details.declarations") {
            VStack(spacing: 6) {
                ActionRow(title: "Age rating", detail: "Answer the content questionnaire") {
                    state.showAgeRating = true
                }
                .rowChip()
                ActionRow(title: "Google data safety",
                          detail: "Review declarations stored in the manifest") {
                    state.showDataSafety = true
                }
                .rowChip()
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("The app uses non-exempt encryption", isOn: state.encryptionBinding)
                        .font(Theme.font(size: 12))
                    // The toggle above is what creates the need for this, so
                    // the paperwork appears with the answer that owes it and
                    // stays out of the way of every app that does not.
                    if state.encryptionBinding.wrappedValue { exportCompliance }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .rowChip()
                VStack(alignment: .leading, spacing: 9) {
                    LabeledField("Kids age band", note: "Apple, optional") {
                        ChoiceField(value: state.reviewMetadataBinding("kidsAgeBand"),
                                    choices: StoreValues.kidsAgeBands, emptyLabel: "None")
                    }
                    LabeledField("Review attachments", note: "comma-separated") {
                        TextField("paths", text: state.reviewMetadataBinding("attachments"))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .rowChip()
            }
            .storePanel(padding: 6)
        }
    }
}

private extension View {
    /// One row of a list, as its own soft chip.
    ///
    /// `sunken` on `raised` is a two percent step, which is what makes it soft:
    /// the chip separates itself without drawing anything. The hairline is
    /// `sep2` and not `sep`, because the chip is a grouping inside a card and
    /// not the edge of one.
    func rowChip() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.sep2, lineWidth: Theme.hairline))
    }
}

/// The export compliance declaration, beside the toggle that asks for it.
///
/// Apple attaches it to the build that ships, and it goes to the regulator's
/// review, so the app writes what the developer answers and invents nothing.
private struct ExportCompliance: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.hasEncryptionDeclaration {
                HStack {
                    Text("Export compliance").font(Theme.font(size: 11.5, weight: .semibold))
                    Spacer(minLength: 8)
                    Button(role: .destructive) { state.removeEncryptionDeclaration() } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
                ForEach(AppState.EncryptionFlag.allCases, id: \.self) { flag in
                    Toggle(flag.label, isOn: state.encryptionFlagBinding(flag))
                        .font(Theme.font(size: 11.5))
                }
                LabeledField("Regulator code", note: "when Apple has issued one") {
                    TextField("", text: state.encryptionTextBinding(.codeValue))
                }
                LabeledField("CCATS or ERN document") {
                    PathField(path: state.encryptionTextBinding(.documentPath),
                              problem: state.missingFileNote(
                                for: state.encryptionTextBinding(.documentPath).wrappedValue)) {
                        guard let url = state.chooseOneFile(
                            allowedExtensions: ["pdf", "doc", "docx", "txt"]) else { return }
                        state.encryptionTextBinding(.documentPath).wrappedValue =
                            state.relativePath(for: url)
                    }
                }
                Text("The run creates the declaration in the review state and uploads the document with it.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("An app that uses non-exempt encryption and claims no exemption also owes Apple this declaration.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add the export declaration") { state.addEncryptionDeclaration() }
                    .controlSize(.small)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
    }
}

extension ListingDeclarations {
    var exportCompliance: some View { ExportCompliance() }
}

/// The Console-only rows that the Details tab owns, from the **one** list that
/// tab 9 also reads. A row is never done in one place and open in the other.
/// Spec section 16.6.
///
/// It is a wide list of rows, so it stays in the main column while the small
/// fields above it moved beside the preview.
struct ConsoleStepsPanel: View {
    @Environment(AppState.self) private var state

    var body: some View { consoleSteps }

    /// The listing half of the Release checklist, beside the listing.
    ///
    /// The same rows also appear on Release, and that is on purpose: Release
    /// is the complete pre-flight list and may not be missing any of them.
    /// What was not on purpose was that the two lists carried different names
    /// — "Finish in the console" here, "steps" there — so one list read as two
    /// lists, and a developer could tick a row here and meet what looks like
    /// an untouched copy of it two tabs later. One name, and a line that says
    /// outright this is part of the other one.
    private var consoleSteps: some View {
        Section_("Console steps", icon: "arrow.up.forward.square.fill",
                 tint: Theme.yellow) {
            VStack(spacing: 0) {
                let rows = state.consoleRows.filter(\.onEditingTab)
                if rows.isEmpty {
                    HStack {
                        Text("Read the stores on the Summary tab to fill this list.")
                            .font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                } else {
                    HStack(spacing: 8) {
                        Text(verbatim: "The \(rows.count) of the \(state.consoleRows.count) console steps that belong to the listing.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        Spacer(minLength: 8)
                        QuietButton(title: "See them all") { state.selectedTab = .release }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        ConsoleChecklistRow(row: row)
                    }
                }
            }.storePanel(padding: 0)
        }
    }
}

/// The same row shape as tab 9: one title, one reason, one state, one link.
private struct ConsoleChecklistRow: View {
    @Environment(AppState.self) private var state
    let row: ConsoleRow

    var body: some View {
        let shown = state.markedState(row)
        HStack(spacing: 10) {
            if row.state == .unknown {
                let marked = state.consoleMarks.contains(row.id)
                Button { state.toggleConsoleMark(row.id) } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(marked ? Theme.accent : .clear)
                        .frame(width: 14, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.sep, lineWidth: 1))
                        .overlay(Text(marked ? "✓" : "")
                            .font(Theme.font(size: 8, weight: .bold)).foregroundStyle(.white))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title)
                .accessibilityValue(marked ? "Confirmed" : "Not confirmed")
            } else {
                Color.clear.frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(Theme.font(size: 12.5, weight: .medium))
                Text(row.reason).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            StatePill(text: shown.label, foreground: ReleaseTab.color(shown),
                      background: ReleaseTab.background(shown))
            Button { state.open(row.link) } label: {
                Text("Open ↗").font(Theme.font(size: 11.5)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct ActionRow: View {
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(size: 12.5, weight: .medium))
                Text(detail).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button("Review", action: action)
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// Apple's age rating questionnaire, as App Store Connect reports it.
///
/// This listed five invented keys and sent them as attribute names. Apple has
/// no `user_generated_content` attribute, so it refused the whole request and
/// every apply died at that step. Nothing here names a field now. The rows are
/// what the store read returned, and a row you do not touch is never sent.
private struct AgeRatingSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Age rating").font(Theme.font(size: 17, weight: .semibold))
            if state.ageRatingFields.isEmpty {
                Text("Read the stores to load the questionnaire. Apple owns these fields, so the app asks App Store Connect for them instead of keeping its own list.")
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("App Store Connect holds the value on the right. Change a row to write it on the next apply. Everything you leave alone stays as it is.")
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(state.ageRatingFields, id: \.key) { field in
                            AgeRatingRow(field: field)
                        }
                    }
                }.frame(maxHeight: 380)
            }
            HStack {
                // The rows above list Apple's fields, so a key Apple never had
                // appears nowhere else and this is the only way to remove it.
                // The five the older build wrote are already gone: the decode
                // drops them. This is for a key typed by hand.
                if !state.unknownAgeRatingKeys.isEmpty {
                    QuietButton(title: "Remove \(state.unknownAgeRatingKeys.count) field(s) Apple does not have") {
                        state.removeUnknownAgeRatingKeys()
                    }
                }
                Spacer()
                Button("Done", action: dismiss.callAsFunction).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}

private struct AgeRatingRow: View {
    @Environment(AppState.self) private var state
    let field: AppState.AgeRatingField

    var body: some View {
        HStack(spacing: 10) {
            Text(field.key)
                .font(Theme.font(size: 11.5, design: .monospaced))
                .frame(width: 250, alignment: .leading)
            switch field.held {
            case .flag:
                Toggle("", isOn: state.ageRatingFlagBinding(field))
                    .labelsHidden()
            case .text:
                TextField("", text: state.ageRatingTextBinding(field))
                    .frame(width: 170)
            }
            if field.changed {
                Text("changed").font(Theme.font(size: 10)).foregroundStyle(Theme.yellow)
            } else {
                Text("keeps").font(Theme.font(size: 10)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The Data safety declaration.
///
/// This offered four toggles whose `question_id` values the app invented.
/// Google publishes the ids in its own export and refuses anything else, so
/// the toggles could never declare anything. The CSV is the only real path,
/// and it is the only one here now.
private struct DataSafetySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Google data safety").font(Theme.font(size: 17, weight: .semibold))
            Text("Export the current CSV from Play Console and select it here. The file is sent unchanged, because Google owns its columns and its question ids. Without the file, nothing is written and Play Console keeps the declaration it has.")
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Data safety CSV path", text: state.reviewMetadataBinding("dataSafetyCSV"))
            if !state.staleDataSafetyAnswers.isEmpty {
                Text("This manifest carries \(state.staleDataSafetyAnswers.count) older answers that used question ids Google does not publish. They are never sent.")
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                QuietButton(title: "Remove them") { state.removeDataSafetyAnswers() }
            }
            HStack {
                Link("Open Play Console ↗",
                     destination: URL(string: "https://play.google.com/console/")!)
                Spacer()
                Button("Done", action: dismiss.callAsFunction).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}

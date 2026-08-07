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
        .sheet(isPresented: $state.showAgeRating) { AgeRatingSheet() }
        .sheet(isPresented: $state.showDataSafety) { DataSafetySheet() }
    }

    private var categories: some View {
        Section_("Categories", icon: "square.grid.2x2.fill", tint: Theme.purple,
                 anchor: "details.categories") {
            VStack(alignment: .leading, spacing: 9) {
                if state.stores.contains(.apple) {
                    LabeledField("Primary", note: "Apple") {
                        ChoiceField(value: state.reviewBinding(.applePrimaryCategory),
                                    choices: StoreValues.appleCategories, emptyLabel: "Pick a category")
                    }
                    LabeledField("Secondary", note: "Apple, optional") {
                        ChoiceField(value: state.reviewBinding(.appleSecondaryCategory),
                                    choices: StoreValues.appleCategories, emptyLabel: "None")
                    }
                }
            }.storePanel()
        }
    }

    private var declarations: some View {
        Section_("Store declarations", icon: "checkmark.shield.fill", tint: Theme.green,
                 anchor: "details.declarations") {
            VStack(spacing: 0) {
                ActionRow(title: "Age rating", detail: "Answer the content questionnaire") {
                    state.showAgeRating = true
                }
                Divider()
                ActionRow(title: "Google data safety",
                          detail: "Review declarations stored in the manifest") {
                    state.showDataSafety = true
                }
                Divider()
                Toggle("The app uses non-exempt encryption", isOn: state.encryptionBinding)
                    .font(.system(size: 12))
                    .padding(.horizontal, 14).padding(.vertical, 11)
                Divider()
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
            }.storePanel(padding: 0)
        }
    }
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
                            .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                } else {
                    HStack(spacing: 8) {
                        Text(verbatim: "The \(rows.count) of the \(state.consoleRows.count) console steps that belong to the listing.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
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
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title)
                .accessibilityValue(marked ? "Confirmed" : "Not confirmed")
            } else {
                Color.clear.frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 12.5, weight: .medium))
                Text(row.reason).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            StatePill(text: shown.label, foreground: ReleaseTab.color(shown),
                      background: ReleaseTab.background(shown))
            Button { state.open(row.link) } label: {
                Text("Open ↗").font(.system(size: 11.5)).foregroundStyle(Theme.accent)
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
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button("Review", action: action)
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct AgeRatingSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    private let questions = [
        ("violence", "Violence"), ("sexual_content", "Sexual content"),
        ("profanity", "Profanity or crude humor"), ("gambling", "Gambling"),
        ("user_generated_content", "User-generated content")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Age rating").font(.title2.weight(.semibold))
            Text("Enable every content type present anywhere in the app.")
                .foregroundStyle(Theme.text2)
            ForEach(questions, id: \.0) { key, title in
                Toggle(title, isOn: state.reviewAnswerBinding(group: "age", key: key))
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss.callAsFunction).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 430)
    }
}

private struct DataSafetySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    private let questions = [
        ("collects_personal_data", "Collects personal data"),
        ("shares_personal_data", "Shares personal data with third parties"),
        ("data_encrypted_in_transit", "Data is encrypted in transit"),
        ("supports_data_deletion", "Users can request data deletion")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Google data safety").font(.title2.weight(.semibold))
            Text("For production, export the current CSV from Play Console and select it here. The file is sent unchanged because Google controls its columns and question IDs.")
                .foregroundStyle(Theme.text2)
            TextField("Data safety CSV path", text: state.reviewMetadataBinding("dataSafetyCSV"))
            ForEach(questions, id: \.0) { key, title in
                Toggle(title, isOn: state.reviewAnswerBinding(group: "safety", key: key))
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

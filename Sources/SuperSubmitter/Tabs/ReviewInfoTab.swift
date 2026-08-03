import SubmitKit
import SwiftUI

/// Tab 6. Review metadata is persisted; demo credentials stay in Keychain.
struct ReviewInfoTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 20) {
            reviewContact
            demoAccount
            reviewNotes
            categories
            declarations
            consoleSteps
        }
        .frame(maxWidth: 940, alignment: .leading)
        .sheet(isPresented: $state.showAgeRating) { AgeRatingSheet() }
        .sheet(isPresented: $state.showDataSafety) { DataSafetySheet() }
        .onChange(of: state.reviewerUsername) { _, _ in state.reviewerCredentialsChanged() }
        .onChange(of: state.reviewerPassword) { _, _ in state.reviewerCredentialsChanged() }
    }

    private var reviewContact: some View {
        Section_("Review contact", icon: "person.crop.circle.fill", tint: Theme.accent) {
            HStack {
                TextField("First name", text: state.reviewBinding(.firstName))
                TextField("Last name", text: state.reviewBinding(.lastName))
                TextField("Email", text: state.reviewBinding(.email))
                TextField("Phone", text: state.reviewBinding(.phone))
            }.reviewPanel()
            Text("App Store only; Google Play has no equivalent fields.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
        }
    }

    private var demoAccount: some View {
        @Bindable var state = state
        return Section_("Demo account", icon: "key.fill", tint: Theme.orange) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("The reviewer needs an account to sign in",
                       isOn: state.demoAccountRequiredBinding)
                if state.manifest.review?.demoAccountRequired == true {
                    HStack {
                        TextField("User name", text: $state.reviewerUsername)
                        SecureField("Password", text: $state.reviewerPassword)
                    }
                }
                Text("Credentials are stored in macOS Keychain and never written to the repository.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }.reviewPanel()
        }
    }

    private var reviewNotes: some View {
        Section_("Notes for the reviewer", icon: "note.text", tint: Theme.teal) {
            TextEditor(text: state.reviewBinding(.notes))
                .font(.system(size: 12.5)).scrollContentBackground(.hidden)
                .padding(7).frame(minHeight: 100)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    private var categories: some View {
        Section_("Categories", icon: "square.grid.2x2.fill", tint: Theme.purple) {
            VStack(alignment: .leading, spacing: 9) {
                if state.stores.contains(.apple) {
                    HStack {
                        TextField("Apple primary category",
                                  text: state.reviewBinding(.applePrimaryCategory))
                        TextField("Apple secondary category",
                                  text: state.reviewBinding(.appleSecondaryCategory))
                    }
                }
            }.reviewPanel()
        }
    }

    private var declarations: some View {
        Section_("Store declarations", icon: "checkmark.shield.fill", tint: Theme.green) {
            VStack(spacing: 0) {
                ActionRow(title: "Age rating", detail: "Answer the content questionnaire") {
                    state.showAgeRating = true
                }
                Divider()
                ActionRow(title: "Privacy policy", detail: "Edit the localized URL") {
                    state.selectedTab = .details
                }
                Divider()
                ActionRow(title: "Google data safety",
                          detail: "Review declarations stored in the manifest") {
                    state.showDataSafety = true
                }
                Divider()
                Toggle("The app uses non-exempt encryption", isOn: state.encryptionBinding)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                Divider()
                HStack {
                    Text("Kids age band")
                    TextField("Optional Apple age band",
                              text: state.reviewMetadataBinding("kidsAgeBand"))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                Divider()
                HStack {
                    Text("Review attachments")
                    TextField("Paths, comma-separated",
                              text: state.reviewMetadataBinding("attachments"))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }.reviewPanel(padding: 0)
        }
    }

    /// The Console-only rows that this tab owns, from the **one** list that
    /// tab 9 also reads. A row is never done in one place and open in the
    /// other. Spec section 16.6.
    private var consoleSteps: some View {
        Section_("Finish in the console", icon: "arrow.up.forward.square.fill", tint: Theme.yellow) {
            VStack(spacing: 0) {
                let rows = state.consoleRows.filter(\.onReviewTab)
                if rows.isEmpty {
                    HStack {
                        Text("Read the stores on the Summary tab to fill this list.")
                            .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        ReviewConsoleRow(row: row)
                    }
                }
            }.reviewPanel(padding: 0)
        }
    }
}

/// The same row shape as tab 9: one title, one reason, one state, one link.
private struct ReviewConsoleRow: View {
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
            HStack { Spacer(); Button("Done", action: dismiss.callAsFunction).keyboardShortcut(.defaultAction) }
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
                Link("Open Play Console ↗", destination: URL(string: "https://play.google.com/console/")!)
                Spacer()
                Button("Done", action: dismiss.callAsFunction).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}

private extension View {
    func reviewPanel(padding: CGFloat = 13) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

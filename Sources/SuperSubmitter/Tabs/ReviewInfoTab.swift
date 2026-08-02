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
        }
        .frame(maxWidth: 940, alignment: .leading)
        .sheet(isPresented: $state.showAgeRating) { AgeRatingSheet() }
        .sheet(isPresented: $state.showDataSafety) { DataSafetySheet() }
        .onChange(of: state.reviewerUsername) { _, _ in state.reviewerCredentialsChanged() }
        .onChange(of: state.reviewerPassword) { _, _ in state.reviewerCredentialsChanged() }
    }

    private var reviewContact: some View {
        Section_("Review contact") {
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
        return Section_("Demo account") {
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
        Section_("Notes for the reviewer") {
            TextEditor(text: state.reviewBinding(.notes))
                .font(.system(size: 12.5)).scrollContentBackground(.hidden)
                .padding(7).frame(minHeight: 100)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    private var categories: some View {
        Section_("Categories") {
            VStack(alignment: .leading, spacing: 9) {
                if state.stores.contains(.apple) {
                    HStack {
                        TextField("Apple primary category",
                                  text: state.reviewBinding(.applePrimaryCategory))
                        TextField("Apple secondary category",
                                  text: state.reviewBinding(.appleSecondaryCategory))
                    }
                }
                if state.stores.contains(.google) {
                    HStack {
                        TextField("Google category", text: state.reviewBinding(.googleCategory))
                        Link("Open Play Console ↗",
                             destination: URL(string: "https://play.google.com/console/")!)
                    }
                }
            }.reviewPanel()
        }
    }

    private var declarations: some View {
        Section_("Store declarations") {
            VStack(spacing: 0) {
                ActionRow(title: "Age rating", detail: "Answer the content questionnaire") {
                    state.showAgeRating = true
                }
                Divider()
                ConsoleLinkRow(title: "Google content rating",
                               detail: "The IARC questionnaire is Console only",
                               destination: URL(string: "https://play.google.com/console/")!)
                Divider()
                ActionRow(title: "Privacy policy", detail: "Edit the localized URL") {
                    state.selectedTab = .details
                }
                Divider()
                ConsoleLinkRow(title: "App Store privacy labels",
                               detail: "Nutrition labels are Console only",
                               destination: URL(string: "https://appstoreconnect.apple.com/apps")!)
                Divider()
                ActionRow(title: "Google data safety", detail: "Review declarations stored in the manifest") {
                    state.showDataSafety = true
                }
                Divider()
                Toggle("The app uses non-exempt encryption", isOn: state.encryptionBinding)
                    .padding(.horizontal, 14).padding(.vertical, 11)
            }.reviewPanel(padding: 0)
        }
    }
}

private struct ConsoleLinkRow: View {
    let title: String
    let detail: String
    let destination: URL
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Link("Open ↗", destination: destination)
        }.padding(.horizontal, 14).padding(.vertical, 10)
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
            Text("These answers are saved for planning; confirm them in Play Console before release.")
                .foregroundStyle(Theme.text2)
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

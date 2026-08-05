import SubmitKit
import SwiftUI

/// Tab 6. Review metadata is persisted; demo credentials stay in Keychain.
struct ReviewInfoTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 20) {
            // Two short blocks that answer the same question, so they sit on
            // one row and share a height rather than stacking into a column
            // the reviewer has to scroll.
            HStack(alignment: .top, spacing: 14) {
                reviewContact
                demoAccount
            }
            .fixedSize(horizontal: false, vertical: true)
            reviewNotes
        }
        .frame(maxWidth: 940, alignment: .leading)
        .onChange(of: state.reviewerUsername) { _, _ in state.reviewerCredentialsChanged() }
        .onChange(of: state.reviewerPassword) { _, _ in state.reviewerCredentialsChanged() }
    }

    private var reviewContact: some View {
        Section_("Review contact", icon: "person.crop.circle.fill", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    TextField("First name", text: state.reviewBinding(.firstName))
                    TextField("Last name", text: state.reviewBinding(.lastName))
                }
                TextField("Email", text: state.reviewBinding(.email))
                TextField("Phone", text: state.reviewBinding(.phone))
                Text("App Store only. Google Play has no equivalent fields.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            .storePanel()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var demoAccount: some View {
        @Bindable var state = state
        return Section_("Demo account", icon: "key.fill", tint: Theme.orange) {
            VStack(alignment: .leading, spacing: 9) {
                Toggle("The reviewer needs an account to sign in",
                       isOn: state.demoAccountRequiredBinding)
                if state.manifest.review?.demoAccountRequired == true {
                    TextField("User name", text: $state.reviewerUsername)
                    SecureField("Password", text: $state.reviewerPassword)
                }
                Text("Credentials stay in the macOS Keychain and never reach the repository.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            .storePanel()
            .frame(maxHeight: .infinity, alignment: .top)
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

}

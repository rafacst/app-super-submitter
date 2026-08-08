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
        Section_("Review contact", icon: "person.crop.circle.fill", tint: Theme.accent,
                 anchor: "review.contact") {
            VStack(alignment: .leading, spacing: 9) {
                FieldRow {
                    LabeledField("First name") {
                        TextField("", text: state.reviewBinding(.firstName))
                    }
                    LabeledField("Last name") {
                        TextField("", text: state.reviewBinding(.lastName))
                    }
                }
                FieldRow {
                    LabeledField("Email") {
                        TextField("", text: state.reviewBinding(.email))
                    }
                    LabeledField("Phone", width: 150) {
                        TextField("", text: state.reviewBinding(.phone))
                    }
                }
                Text("App Store only. Google Play has no equivalent fields.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            // The stretch happens before the panel is painted, so the two
            // panels on this row draw to one height instead of two.
            .frame(maxHeight: .infinity, alignment: .top)
            .storePanel()
        }
    }

    private var demoAccount: some View {
        @Bindable var state = state
        return Section_("Demo account", icon: "key.fill", tint: Theme.orange,
                 anchor: "review.demoAccount") {
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
            // The stretch happens before the panel is painted, so the two
            // panels on this row draw to one height instead of two.
            .frame(maxHeight: .infinity, alignment: .top)
            .storePanel()
        }
    }

    /// A range, not a fixed height.
    ///
    /// The reviewer notes run to a page and a half on a real app, and the tab
    /// is inside a scroll view, so a freely growing editor pushed everything
    /// below it past the bottom of the window. The answer was a fixed 420
    /// point box that scrolled its own text — which held the tab still, and
    /// also drew 420 points of empty field around "No login is necessary.
    /// Open the app and scan the sample receipt.", the whole content of this
    /// tab for most apps.
    ///
    /// A ceiling does the same job as a fixed height. The box grows with the
    /// text, stops at roughly where 420 points was, and scrolls beyond it, so
    /// the long note is still held and the short one no longer costs a
    /// screenful.
    private var reviewNotes: some View {
        Section_("Notes for the reviewer", icon: "note.text", tint: Theme.teal,
                 anchor: "review.notes") {
            TextField("", text: state.reviewBinding(.notes), axis: .vertical)
                .textFieldStyle(.plain)
                .returnInsertsLineBreak()
                .lineLimit(4...22)
                .font(.system(size: 12.5))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

}

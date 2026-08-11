import SubmitKit
import SwiftUI

/// Tab 6. Review metadata is persisted; demo credentials stay in Keychain.
///
/// **Why one column per store.** The tab drew three boxes and every one of them
/// was Apple's. Play asks for no review contact and no notes, and the sign-in
/// the boxes hold can never be sent to it, because the Android Publisher API
/// publishes no app access endpoint. So the screen said nothing at all about
/// half of where the app is going, and the one thing Play does need was two
/// tabs away in a console list. Standing the stores side by side puts each
/// store's own answer under its own name, and Play's column says outright that
/// its half is a paste into a console.
///
/// There is no switch between merged and side by side. The Details switch earns
/// its place: merged, a field both stores read is one box instead of the same
/// sentence twice. Here the two columns hold different things, so merging only
/// stacked them, and a control that offers two spellings of one screen answers
/// nothing.
struct ReviewInfoTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 16) {
            statusBar
            if columns {
                HStack(alignment: .top, spacing: 16) {
                    appleColumn.frame(maxWidth: .infinity, alignment: .leading)
                    googleColumn.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    if shows(.apple) { appleColumn }
                    if shows(.google) { googleColumn }
                }
            }
        }
        .frame(maxWidth: 940, alignment: .leading)
        .onChange(of: state.reviewerUsername) { _, _ in state.reviewerCredentialsChanged() }
        .onChange(of: state.reviewerPassword) { _, _ in state.reviewerCredentialsChanged() }
    }

    // MARK: - The bar over the columns

    /// What the screen is worth reading for before any single box is: what
    /// stops the send, and what this version inherits from the last one.
    private var statusBar: some View {
        HStack(spacing: 14) {
            let blockers = state.badge(for: .reviewInfo)?.errors ?? 0
            if blockers > 0 {
                Button { state.selectedTab = .plan } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.red).frame(width: 7, height: 7)
                        Text(blockers == 1 ? "1 blocker · here" : "\(blockers) blockers · here")
                            .font(Theme.font(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.red)
                        Image(systemName: "chevron.right")
                            .font(Theme.font(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.red.opacity(0.6))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Theme.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if let note = Self.carriedOverNote(state.actualState) {
                Text(note).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
            }
        }
    }

    // MARK: - The App Store column

    private var appleColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            columnHeader(.apple)
            reviewContact
            demoAccount
            reviewNotes
        }
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
            }
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
                    // The account the released version was approved with.
                    //
                    // The sign-in lives in the Keychain and never in the
                    // manifest, and a Keychain is per machine. So an app that
                    // has shipped three times with a demo account opened these
                    // two fields empty on a new Mac. Apple carries the review
                    // detail into the next version, so the store remembers what
                    // this machine does not.
                    //
                    // An offer and not an autofill. It writes a credential, and
                    // a credential that appears on its own is one nobody
                    // decided to use.
                    if let stored = state.storedDemoAccount {
                        HStack(spacing: 8) {
                            Text(stored.password == nil
                                 ? "The App Store holds \(stored.name) for this app. Apple does not return the password."
                                 : "The App Store holds \(stored.name) for this app.")
                                .font(Theme.font(size: 11.5))
                                .foregroundStyle(Theme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            QuietButton(title: "Use it") { state.fillDemoAccountFromStore() }
                        }
                    }
                    // The way to the account without leaving this tab. The
                    // offer above waits for a read, and the only read was the
                    // whole pass over both stores on the Summary tab.
                    HStack(spacing: 8) {
                        QuietButton(title: "Retrieve from App Store") {
                            Task { await state.readDemoAccountFromStore() }
                        }
                        .disabled(state.demoAccountReading)
                        if state.demoAccountReading { Spinner() }
                        Spacer(minLength: 0)
                    }
                    if let note = state.demoAccountReadNote {
                        Text(note)
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Credentials stay in the macOS Keychain and never reach the repository.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                .font(Theme.font(size: 12.5))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    // MARK: - The Google Play column

    /// Play's whole half of the screen, and it is a console visit.
    ///
    /// The two rows come from the one list tab 9 reads, so a step ticked here
    /// is ticked there. The copy button is the only thing this tab adds: the
    /// sign-in above cannot be sent, so a paste is the whole path.
    private var googleColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            columnHeader(.google)
            // Named for what it is, and not for the first row in it. The row
            // is already called "App access, the reviewer credentials", and a
            // title over it saying "App access" is the same words twice.
            Section_("Console steps", icon: "arrow.up.forward.square.fill", tint: Theme.yellow,
                     anchor: "review.console") {
                VStack(spacing: 0) {
                    let rows = Self.consoleSteps(in: state.consoleRows)
                    if rows.isEmpty {
                        HStack {
                            Text("Read the stores on the Summary tab to fill this list.")
                                .font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider() }
                            ConsoleChecklistRow(row: row)
                        }
                    }
                    Divider()
                    HStack(spacing: 8) {
                        Text("The sign-in above cannot be sent. Paste it into Policy, then App content, then App access.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        QuietButton(title: "Copy the demo account") { state.copyDemoAccount() }
                            .disabled(state.demoAccountClipboard == nil)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .storePanel(padding: 0)
            }
            Text("Play asks for no review contact and no notes. What a reviewer needs lives entirely in App access.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(style: StrokeStyle(lineWidth: Theme.hairline, dash: [3, 3]))
                    .foregroundStyle(Theme.sep))
        }
    }

    // MARK: - Helpers

    private func columnHeader(_ store: Store) -> some View {
        HStack(spacing: 8) {
            StoreMark(store: store, size: 14)
            Text(store.storeName).font(Theme.font(size: 13, weight: .semibold))
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// Two columns need two stores. One store still stands alone.
    private var columns: Bool { state.stores.count > 1 }

    /// Before any store is picked the Apple column carries the fields, so the
    /// tab draws what it always drew rather than nothing at all.
    private func shows(_ store: Store) -> Bool {
        state.stores.isEmpty ? store == .apple : state.stores.contains(store)
    }

    // MARK: - What the screen has to judge

    /// What the next version inherits from the released one.
    ///
    /// Store policy again: Apple carries the review detail forward, so a
    /// developer who leaves these boxes alone still submits the last version's
    /// answers. Nil on a first submission, which inherits nothing.
    static func carriedOverNote(_ actual: ActualState) -> String? {
        actual.apple?.liveVersionString.map {
            "Apple carries these over from \($0) unless you change them"
        }
    }

    /// The console steps that answer "what does the reviewer need?".
    ///
    /// Two of them, both Play's. The rest of the console list is what the
    /// listing declares about itself and stays on the Details tab. Ordered by
    /// this list and not by the checklist, so App access leads.
    static func consoleSteps(in rows: [ConsoleRow]) -> [ConsoleRow] {
        ["google.access", "google.dataSafety"].compactMap { id in
            rows.first { $0.id == id }
        }
    }
}

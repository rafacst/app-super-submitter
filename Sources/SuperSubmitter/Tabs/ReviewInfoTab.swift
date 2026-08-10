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
/// Export compliance opens the tab because it is the one question here that
/// stops a submission. It sat on the Details inspector under a Bool toggle
/// while the console row for it said "answer it on the Review info tab", so the
/// instruction pointed at a screen that did not hold the control.
struct ReviewInfoTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 16) {
            statusBar
            exportComplianceCard
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
            let blockers = (state.badge(for: .reviewInfo)?.errors ?? 0)
                + (blocksTheSend ? 1 : 0)
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
            if state.stores.count > 1 {
                QuietButton(title: state.reviewMerged ? "Split by store" : "Merge the columns") {
                    state.reviewMerged.toggle()
                }
            }
        }
    }

    // MARK: - The one question that stops a submission

    /// Apple asks the export compliance question once per build and refuses the
    /// submission until the build carries an answer. The card is the answer,
    /// here, rather than a console visit.
    private var exportComplianceCard: some View {
        Section_("Export compliance", icon: "lock.shield.fill",
                 tint: blocksTheSend ? Theme.red : Theme.green,
                 anchor: "review.encryption") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    StoreMark(store: .apple, size: 12)
                    Text("Apple asks this once per build")
                        .font(Theme.font(size: 12.5, weight: .medium))
                    if blocksTheSend {
                        Text("Blocks the send")
                            .font(Theme.font(size: 11, weight: .medium))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 7).padding(.vertical, 1.5)
                            .background(Theme.red.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    Spacer(minLength: 0)
                }
                Text(blocksTheSend
                     ? "Apple refuses the submission without it. Answer it here, no console visit needed."
                     : "Answered. Change it here if this build changed what the app encrypts.")
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                // Two answers and no third, so a question nobody has answered
                // selects neither. A Bool could not say that, and the toggle
                // this replaces drew an unasked question as a settled "no".
                Picker("Export compliance", selection: Binding(
                    get: { state.encryptionAnswer },
                    set: { state.setEncryptionAnswer($0) })) {
                    Text("Uses no non-exempt encryption").tag(Bool?.some(false))
                    Text("It does use encryption").tag(Bool?.some(true))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                // The answer above is what creates the need for this, so the
                // paperwork appears with the answer that owes it and stays out
                // of the way of every app that does not.
                if state.encryptionAnswer == true { ExportCompliance() }
            }
            // The card carries the colour of the answer, so an open question
            // reads as an open question from across the screen.
            .storePanel(background: blocksTheSend ? Theme.red.opacity(0.09) : Theme.raised,
                        border: blocksTheSend ? Theme.red.opacity(0.32) : Theme.sep)
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

    /// Two columns need two stores and the width for them.
    private var columns: Bool { state.stores.count > 1 && !state.reviewMerged }

    /// Before any store is picked the Apple column carries the fields, so the
    /// tab draws what it always drew rather than nothing at all.
    private func shows(_ store: Store) -> Bool {
        state.stores.isEmpty ? store == .apple : state.stores.contains(store)
    }

    private var blocksTheSend: Bool {
        Self.blocksTheSend(manifest: state.manifest, actual: state.actualState,
                           stores: state.stores)
    }

    // MARK: - What the screen has to judge

    /// Whether Apple is still waiting for the export compliance answer.
    ///
    /// Store policy and not an API constraint: no endpoint refuses a request
    /// for the missing flag, and `appStoreVersions` takes a submission that
    /// omits it. Apple refuses at review instead, which is the worst place to
    /// learn it. The same two sources `ConsoleChecklist` reads, in the same
    /// order: the manifest answers it, and so does a build that shipped with
    /// `ITSAppUsesNonExemptEncryption` set.
    static func blocksTheSend(manifest: Manifest, actual: ActualState,
                              stores: Set<Store>) -> Bool {
        guard stores.contains(.apple) else { return false }
        return manifest.review?.usesNonExemptEncryption == nil
            && actual.apple?.buildUsesNonExemptEncryption == nil
    }

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

/// The export compliance declaration, beside the answer that asks for it.
///
/// Apple attaches it to the build that ships, and it goes to the regulator's
/// review, so the app writes what the developer answers and invents nothing.
private struct ExportCompliance: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.hasEncryptionDeclaration {
                HStack {
                    Text("The declaration").font(Theme.font(size: 11.5, weight: .semibold))
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

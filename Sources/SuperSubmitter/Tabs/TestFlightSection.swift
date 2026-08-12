import AppKit
import SubmitKit
import SwiftUI

/// TestFlight, on the tab that invites the people who read it.
///
/// It is the App Store twin of the Google tester groups, so it sits beside
/// them rather than on Release: a group and an address are manifest values, and
/// the Release tab is where a version is sent, not where one is described.
///
/// The runner and the planner have carried the whole block since the start.
/// Nothing on any tab wrote it, so the only way to reach a tester was the raw
/// YAML editor.
struct TestFlightSection: View {
    @Environment(AppState.self) private var state

    /// It no longer folds. It was five field groups deep on the Build tab,
    /// where a developer had come to drop a package, so it opened shut behind
    /// a chevron and a line describing itself. This is the tab it names, and a
    /// screen may not hide the thing it exists for.
    var body: some View {
        Section_("TestFlight", icon: "paperplane.circle.fill", tint: Theme.accent,
                 anchor: "build.testFlight",
                 note: "Groups, what to test, the page, and the licence") {
            // The card the fold used to draw around itself. Without it the
            // Apple column stood as bare fields beside a Google column of
            // panels, and the two read as different kinds of thing.
            Group {
                if state.testFlight == nil {
                    empty
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        TestFlightSendPanel()
                        Divider().overlay(Theme.sep)
                        groups
                        Divider().overlay(Theme.sep)
                        buildNotes
                        Divider().overlay(Theme.sep)
                        page
                        Divider().overlay(Theme.sep)
                        licence
                        Divider().overlay(Theme.sep)
                        switches
                        Divider().overlay(Theme.sep)
                        footer
                    }
                }
            }
            .storePanel(padding: 14)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing goes to a tester until this block exists. An external group invites real addresses, so the plan shows every invitation before the run sends one.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set up TestFlight") { state.addTestFlight() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The groups

    private var groups: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Groups").font(Theme.font(size: 12, weight: .semibold))
            ForEach(Array(state.betaGroups.enumerated()), id: \.offset) { index, _ in
                group(index)
            }
            Button("Add a group") { state.addBetaGroup() }.controlSize(.small)
            // One sentence under the list, not one under every card. It says
            // the same thing about every group, and repeated four times it read
            // as four different warnings.
            Text("Apple emails each address the first time it appears here. The plan counts the new ones, so a second apply invites nobody twice.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One group: who is in it, which kind it is, and what TestFlight does with
    /// it.
    ///
    /// The kind comes first under the names, because it decides the rest of the
    /// card. An internal group takes the App Store Connect users of the team,
    /// it skips the beta review, and Apple faults a public link on it, so the
    /// link row is not drawn for one.
    private func group(_ index: Int) -> some View {
        let isInternal = state.betaGroupFlagBinding(index: index, flag: .internalGroup)
        let publicLink = state.betaGroupFlagBinding(index: index, flag: .publicLink)
        return VStack(alignment: .leading, spacing: 8) {
            FieldRow {
                LabeledField("Group name", width: 200) {
                    TextField("", text: state.betaGroupBinding(index: index, field: .name))
                }
                // "comma-separated addresses" and not the note it carried:
                // over 24 characters a note drops under its own control, which
                // left this field standing a line higher than the name beside
                // it in a row that aligns on the bottom.
                LabeledField("Testers", note: "comma-separated") {
                    TextField("", text: state.betaGroupBinding(index: index, field: .testers))
                }
                Button(role: .destructive) { state.removeBetaGroup(at: index) } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .accessibilityLabel("Remove this group")
            }
            kind(index, isInternal: isInternal)
            if !isInternal.wrappedValue { link(index, publicLink: publicLink) }
            HStack(spacing: 14) {
                Toggle("Every new build joins this group",
                       isOn: state.betaGroupFlagBinding(index: index, flag: .automaticBuilds))
                Toggle("Testers can send feedback",
                       isOn: state.betaGroupFlagBinding(index: index, flag: .feedback))
                Spacer(minLength: 0)
            }
            .font(Theme.font(size: 11.5))
            // The caption sits over the two switches rather than beside them.
            // A card is about three hundred points wide, and on that line the
            // sentence was the part that lost: it came out as "The iOS build
            // also rea…" beside one group and on two lines beside the next.
            VStack(alignment: .leading, spacing: 4) {
                Text("The iOS build also reaches")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                HStack(spacing: 14) {
                    Toggle("Apple silicon Macs",
                           isOn: state.betaGroupFlagBinding(index: index, flag: .iosBuildsOnMac))
                    Toggle("Apple Vision Pro",
                           isOn: state.betaGroupFlagBinding(index: index,
                                                            flag: .iosBuildsOnVision))
                    Spacer(minLength: 0)
                }
                .font(Theme.font(size: 11.5))
            }
        }
        .padding(9)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
    }

    /// Internal or external. Apple settles this when it creates the group and
    /// takes no later change, so the card says so rather than letting a switch
    /// promise something no apply can keep.
    private func kind(_ index: Int, isInternal: Binding<Bool>) -> some View {
        let created = state.liveBetaGroup(index) != nil
        return HStack(spacing: 10) {
            Picker("", selection: isInternal) {
                Text("External").tag(false)
                Text("Internal").tag(true)
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 170)
            .disabled(created)
            Text(kindNote(isInternal: isInternal.wrappedValue, created: created))
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Group kind")
    }

    private func kindNote(isInternal: Bool, created: Bool) -> String {
        if created {
            return "Apple fixed this when it created the group, so no apply changes it now."
        }
        return isInternal
            ? "The App Store Connect users of your team, and nobody else. It needs no beta review."
            : "Anybody you invite, once Apple has reviewed the build."
    }

    /// The public link: the switch, its cap, and the address Apple gave back.
    ///
    /// The cap used to be a labelled field on the switch row, so turning the
    /// link on made the row twice as tall and pushed the switch beside it down
    /// the card. It reads on one line here, and the row keeps its height.
    private func link(_ index: Int, publicLink: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Public link", isOn: publicLink)
                if publicLink.wrappedValue {
                    Text("Limit").foregroundStyle(Theme.text2)
                    TextField("no cap", text: state.betaGroupBinding(index: index,
                                                                     field: .publicLinkLimit))
                        .frame(width: 80)
                        .accessibilityLabel("Public link limit")
                    Text("testers").foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .font(Theme.font(size: 11.5))
            if let url = state.betaGroupPublicLink(index: index) {
                HStack(spacing: 8) {
                    Text(url).font(Theme.mono(11)).foregroundStyle(Theme.text2)
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    }
                    .controlSize(.small)
                    if let link = URL(string: url) {
                        Link("Open", destination: link).font(Theme.font(size: 11.5))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - What the tester reads

    private var buildNotes: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledField("What to Test", note: state.locale,
                         anchor: "build.whatToTest") {
                TextField("", text: state.whatToTestBinding(locale: state.locale),
                          axis: .vertical)
                    .returnInsertsLineBreak()
                    .lineLimit(2...8)
            }
            Text("Apple keys this to the build, so every upload carries it again.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TestFlight page").font(Theme.font(size: 12, weight: .semibold))
                .fieldAnchor("build.testFlightPage")
            LabeledField("Description", note: state.locale) {
                TextField("", text: state.testFlightPageBinding(locale: state.locale,
                                                                field: .description),
                          axis: .vertical)
                    .returnInsertsLineBreak()
                    .lineLimit(2...6)
            }
            FieldRow {
                LabeledField("Feedback email") {
                    TextField("", text: state.testFlightPageBinding(locale: state.locale,
                                                                     field: .feedbackEmail))
                }
                LabeledField("Marketing URL") {
                    TextField("", text: state.testFlightPageBinding(locale: state.locale,
                                                                     field: .marketingUrl))
                }
                LabeledField("Privacy policy URL") {
                    TextField("", text: state.testFlightPageBinding(locale: state.locale,
                                                                     field: .privacyPolicyUrl))
                }
            }
            Text("This belongs to the app, not to one build, so it survives every upload.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
        }
    }

    // MARK: - The licence the testers accept

    /// Apple fills this with its own standard text and every external tester
    /// accepts it before the first install, so a stale one blocks the beta as
    /// surely as a missing build does.
    private var licence: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Beta licence agreement").font(Theme.font(size: 12, weight: .semibold))
                .fieldAnchor("build.betaLicence")
            TextEditor(text: state.betaLicenseAgreementBinding)
                .font(Theme.font(size: 12))
                .resizableHeight("build.betaLicence", base: 90)
                .scrollContentBackground(.hidden)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
            Text("Leave it empty and Apple's own standard licence stays. Every external tester accepts whatever is here before they install the build.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The two switches

    /// The beta review is a queue. It gets the warning colour that the
    /// migration toggle on Monetization gets, and for the same reason: the
    /// switch is the decision, and the run only carries it out.
    private var switches: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Email the testers when a build arrives", isOn: state.betaAutoNotifyBinding)
            HStack(spacing: 8) {
                Toggle("Send the build to beta review", isOn: state.betaSubmitForReviewBinding)
                if state.betaSubmitForReviewBinding.wrappedValue {
                    StatePill(text: "Takes a place in a queue",
                              foreground: Theme.yellow, background: Theme.yellowBg)
                }
                Spacer(minLength: 0)
            }
            Text("An external group cannot receive a build until Apple has reviewed it. The plan shows this row before the run performs it.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            // The apply writes the beta review contact from the review block,
            // and nothing on this tab said where that block is. A beta review
            // fails on a missing contact as readily as on a bad build.
            NoteWithAction("Apple asks for a review contact, and for a demo account when the app needs one. The apply takes both from Review info.") {
                QuietButton(title: "Open Review info") { state.selectedTab = .reviewInfo }
            }
        }
        .font(Theme.font(size: 12))
    }

    // MARK: - Dropping the block

    /// It used to sit in the "Groups" heading, where the one control that drops
    /// the whole block read as the one that drops the groups. It says what it
    /// does here, and it is the last thing on the panel rather than the first.
    private var footer: some View {
        NoteWithAction("Removing the block stops every TestFlight write. The groups and the testers Apple already holds stay exactly as they are.") {
            Button(role: .destructive) { state.removeTestFlight() } label: {
                Text("Remove TestFlight").font(Theme.font(size: 11))
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Starting the beta from the panel that describes it

/// The one button that sends the beta.
///
/// Every field above it describes a beta and none of them started one. The
/// rows exist and the runner has always carried them; they were only reachable
/// through the Summary tab, which reads both stores, draws the whole diff of
/// the release, and sends the listing and the media beside the beta. A
/// developer who came here to give three friends a build had to learn all of
/// that first, and then send more than they asked for.
///
/// This runs the TestFlight rows and nothing else: the upload of the build the
/// manifest names, the answer to the encryption question that Apple asks
/// before any tester may install, the groups, the invitations, the build each
/// group receives, the notes, the page, the licence, the review contact, and
/// the beta review itself.
///
/// It reads the App Store first, every time. `sendToTestFlight()` says why:
/// a stale comparison here invites somebody twice and asks Apple to create a
/// group it already holds.
struct TestFlightSendPanel: View {
    @Environment(AppState.self) private var state
    @State private var confirming = false

    /// The rows below the fold of the confirmation. Four fits the dialog at
    /// every type size; the rest are counted rather than listed.
    private static let namedRows = 4

    var body: some View {
        let rows = state.changes(for: .testFlight)
        let running = state.directApplyRunning(.testFlight)
        let message = state.directApplyMessage(for: .testFlight)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rows.isEmpty
                         ? "TestFlight holds everything on this panel."
                         : "\(rows.count) \(rows.count == 1 ? "row" : "rows") to send")
                        .font(Theme.font(size: 12.5, weight: .medium))
                    // The rows themselves belong to the confirmation, where
                    // they are read before anything is sent. Here the first one
                    // arrived carrying the planner's "unverified · " marker,
                    // which says nothing to a developer who has not read the
                    // stores yet and is the state this button exists to fix.
                    Text(message.isEmpty ? subtitle : message)
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(state.directApplyFailed(.testFlight)
                                         ? Theme.red : Theme.text2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if running || state.planReading { Spinner() }
                Button(buttonTitle(running: running)) { start() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(running || state.planReading || rows.isEmpty)
            }
            // Not "a second send invites nobody twice". The group list already
            // says that, and one panel saying one thing twice reads as two
            // rules.
            Text("It reads the App Store first, so the confirmation names exactly what goes.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Send this to TestFlight?", isPresented: $confirming) {
            Button("Send it") { state.applyDirectly(.testFlight) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmation)
        }
    }

    /// The line under the count, before a run has anything to report. It names
    /// the two rows that reach a person, because those are the two that make
    /// this button different from every other apply in the app.
    private var subtitle: String {
        "Apple emails every new tester, and a beta review takes a place in a queue."
    }

    private func buttonTitle(running: Bool) -> String {
        if state.planReading { return "Reading…" }
        return running ? "Sending…" : "Send to TestFlight"
    }

    /// Reads, then asks. The read is what makes the numbers in the dialog the
    /// real ones: before it, the plan counts every tester as a new invitation
    /// because it has nothing to compare them against.
    private func start() {
        Task {
            await state.readStores()
            confirming = true
        }
    }

    private var confirmation: String {
        let rows = state.changes(for: .testFlight)
        guard !rows.isEmpty else {
            return "The App Store already holds every row on this panel, so this sends nothing."
        }
        let named = rows.prefix(Self.namedRows).joined(separator: "\n")
        let rest = rows.count - Self.namedRows
        return "Super Submitter sends \(rows.count) \(rows.count == 1 ? "row" : "rows") now:\n"
            + named + (rest > 0 ? "\n… and \(rest) more" : "")
            + "\n\nApple emails every address it does not already hold, and a build sent to beta review takes its place in the queue. Neither one can be taken back."
    }
}

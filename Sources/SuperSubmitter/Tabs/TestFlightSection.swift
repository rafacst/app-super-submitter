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
                        groups
                        Divider().overlay(Theme.sep)
                        buildNotes
                        Divider().overlay(Theme.sep)
                        page
                        Divider().overlay(Theme.sep)
                        licence
                        Divider().overlay(Theme.sep)
                        switches
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
            HStack {
                Text("Groups").font(Theme.font(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Button(role: .destructive) { state.removeTestFlight() } label: {
                    Text("Remove TestFlight").font(Theme.font(size: 11))
                }
                .controlSize(.small)
            }
            ForEach(Array(state.betaGroups.enumerated()), id: \.offset) { index, _ in
                group(index)
            }
            Button("Add a group") { state.addBetaGroup() }.controlSize(.small)
        }
    }

    private func group(_ index: Int) -> some View {
        let publicLink = state.betaGroupFlagBinding(index: index, flag: .publicLink)
        return VStack(alignment: .leading, spacing: 8) {
            FieldRow {
                LabeledField("Group name", width: 240) {
                    TextField("", text: state.betaGroupBinding(index: index, field: .name))
                }
                LabeledField("Testers", note: "comma-separated addresses") {
                    TextField("", text: state.betaGroupBinding(index: index, field: .testers))
                }
                Button(role: .destructive) { state.removeBetaGroup(at: index) } label: {
                    Image(systemName: "trash")
                }
            }
            HStack(spacing: 14) {
                Toggle("Public link", isOn: publicLink)
                if publicLink.wrappedValue {
                    LabeledField("Limit", note: "blank for no cap", width: 150) {
                        TextField("", text: state.betaGroupBinding(index: index,
                                                                   field: .publicLinkLimit))
                    }
                }
                Toggle("Every new build joins this group",
                       isOn: state.betaGroupFlagBinding(index: index, flag: .automaticBuilds))
                Spacer(minLength: 0)
            }
            .font(Theme.font(size: 11.5))
            Text("Apple emails each address the first time it appears here. The plan counts the new ones, so a second apply invites nobody twice.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
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
        }
        .font(Theme.font(size: 12))
    }
}

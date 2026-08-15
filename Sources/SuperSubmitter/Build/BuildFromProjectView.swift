import SubmitKit
import SwiftUI

/// Build from Project. upload-spec section 10.
///
/// The screen follows the work: link, choose, preflight, confirm, build,
/// inspect, confirm again, upload. Nothing skips a confirmation.
struct BuildFromProjectView: View {
    @Environment(AppState.self) private var state
    /// The failure panel's own fold, open when the panel appears. See
    /// `errorPanel`.
    @State private var diagnosticsOpen = true
    /// The success card's delete. The artifact section carries the same
    /// question against the same file, and both ask it with
    /// `deleteArtifactConfirmation`.
    @State private var deleting = false
    /// The developer's own answer about the preflight list, and nil until they
    /// give one. See `showsChecks` for what decides it meanwhile.
    @State private var checksOpen: Bool?

    private var flow: BuildFlow { state.buildFlow }

    /// Whether the twelve read-only rows are on screen.
    ///
    /// Shut while every check is ready, which is the ordinary state of a
    /// project that has been linked once and builds every day. Open by itself
    /// the moment a row is not, because a card that hides the reason a build
    /// cannot start is worse than one that shows twelve rows nobody reads.
    private var showsChecks: Bool { checksOpen ?? !preflightIsQuiet }

    /// Nothing on the preflight card needs reading.
    private var preflightIsQuiet: Bool {
        flow.blockingReason == nil
            && !preflightRows(flow.snapshot).contains { $0.2 == .blocked || $0.2 == .warning }
    }

    /// The one line that stands for the checks while they are folded away.
    ///
    /// It answers what the list answers together: whether this build may run,
    /// and what it will build. The rows themselves are twelve values a
    /// developer reads once, when one of them is wrong.
    private var preflightSummary: (text: String, status: PreflightRow.Status) {
        guard flow.state != .preflight else {
            return ("Reading the toolchain, the signing, and the store…", .unknown)
        }
        let rows = preflightRows(flow.snapshot)
        let what = [flow.snapshot.scheme ?? flow.snapshot.variantTask,
                    flow.snapshot.marketingVersion.map { version in
                        flow.snapshot.buildVersion.map { "\(version) (\($0))" } ?? version
                    }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let blocked = rows.filter { $0.2 == .blocked }.count
        let warnings = rows.filter { $0.2 == .warning }.count
        if blocked > 0 || flow.blockingReason != nil {
            return ("\(max(blocked, 1)) of \(rows.count) checks blocked", .blocked)
        }
        if warnings > 0 {
            return ("\(warnings) of \(rows.count) checks to settle", .warning)
        }
        return (what.isEmpty ? "\(rows.count) checks ready"
                             : "\(rows.count) checks ready · \(what)", .ready)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if flow.project == nil, flow.candidate == nil, flow.failure == nil {
                storeRow
                if !flow.containers.isEmpty, flow.state == .needsSelection {
                    containerChooser
                } else {
                    linkCard
                }
            } else {
                if flow.project != nil {
                    // One box: what is linked, and every choice about what it
                    // builds. They were two cards standing on top of each
                    // other, one holding a name and five buttons and the other
                    // holding two pickers, and a choice a developer makes
                    // before pressing Build had no more claim to a border of
                    // its own than the folder it is made about.
                    //
                    // What the build is for. One app id ships iOS and macOS
                    // and the two are not in step, so the platform is a
                    // choice on every apple project and not a fact of the
                    // container. Without this row the flow archived whatever
                    // the link had guessed, which is iOS for every Xcode
                    // project, and the scheme, the Gradle variant and the JDK
                    // had no control either.
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Project")
                            .font(Theme.font(size: 13.5, weight: .semibold))
                        projectCard
                        Divider().overlay(Theme.sep)
                        selectionBlock
                        Divider().overlay(Theme.sep)
                        preflightCard
                    }
                    .storePanel(horizontal: 15)
                }
                if flow.state.isActive || flow.candidate != nil || flow.failure != nil {
                    liveRun
                }
                // The artifact is not here. It is a section of the Artifacts
                // box below, with the package a developer supplies and the
                // builds the store already holds: one question, one box. What
                // stays is the run and the preflight, which are not artifacts.
                if let failure = flow.failure { errorPanel(failure) }
                if flow.state == .complete { successCard }
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
        .task {
            flow.loadSavedProject()
            flow.resumeUnfinishedRuns()
        }
        .sheet(isPresented: Bindable(flow).showBuildConfirmation) { buildConfirmation }
        .sheet(isPresented: Bindable(flow).showBuildBothConfirmation) { buildBothConfirmation }
        .sheet(isPresented: Bindable(flow).showUploadConfirmation) { uploadConfirmation }
        .deleteArtifactConfirmation($deleting, flow: flow)
    }

    /// A card's rows, in two columns.
    ///
    /// An app that ships on one store builds one platform, and this screen was
    /// then a single column of cards whose contents are label and value pairs
    /// a few words wide. Preflight is twelve of them and the artifact is nine,
    /// so most of a 980 point card was empty and the card was twice as tall as
    /// its contents needed.
    ///
    /// Splitting the rows rather than standing the cards side by side, because
    /// a row shrinks and a card does not: the project card carries five buttons
    /// on one line, and two of those cards on one row overflow the window
    /// instead of folding.
    ///
    /// It was a `ViewThatFits`, with one column behind the two. That measures
    /// what the *contents* want rather than what the card has, so one long
    /// value — an Android SDK path, a store message of a full sentence, a
    /// developer directory — restacked the whole card into a single column and
    /// the list changed shape as the values arrived. The layout is a property
    /// of the card, not of the longest string in it: the columns stay, and a
    /// value too long for its half wraps onto the next line inside it.
    private func twoColumns<Row, Cell: View>(
        _ rows: [Row], @ViewBuilder cell: @escaping (Row) -> Cell) -> some View {
        let half = (rows.count + 1) / 2
        return HStack(alignment: .top, spacing: 22) {
            column(Array(rows.prefix(half)), cell: cell)
            column(Array(rows.dropFirst(half)), cell: cell)
        }
    }

    private func column<Row, Cell: View>(
        _ rows: [Row], @ViewBuilder cell: @escaping (Row) -> Cell) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                cell(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Linking

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Build from a project folder").font(Theme.font(size: 13, weight: .semibold))
            Text("Super Submitter runs your own Xcode or Gradle build, reads the artifact it produced, and uploads that exact file. It never edits your project, your versions, or your signing.")
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 9) {
                Button { flow.linkFolder() } label: {
                    Text("Link Project Folder")
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                if flow.state == .discovering { Spinner() }
                Spacer(minLength: 0)
            }
            Text("Building can execute scripts, package plug-ins, and compiler macros supplied by the project you choose.")
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .storePanel(horizontal: 15)
    }

    // MARK: - 10.2 The project card

    private var projectCard: some View {
        let project = flow.project
        return HStack(alignment: .top, spacing: 18) {
            HStack(spacing: 10) {
                Text(project?.platform == .android ? "Gradle" : "Xcode")
                    .font(Theme.font(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project?.displayName ?? "").font(Theme.font(size: 13, weight: .semibold))
                    Text(project?.containerURL.lastPathComponent ?? "")
                        .font(Theme.mono(11)).foregroundStyle(Theme.text2)
                    if let revision = flow.candidate?.sourceRevision {
                        Text(revision.label).font(Theme.mono(10.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 7) {
                if let validated = project?.lastValidatedAt {
                    Text("checked \(validated.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                }
                HStack(spacing: 7) {
                    QuietButton(title: "Recheck") { Task { await flow.refreshPreflight() } }
                    QuietButton(title: "Reveal Folder") {
                        flow.reveal(project?.rootPath ?? "")
                    }
                    QuietButton(title: project?.platform == .android
                                ? "Open in Android Studio" : "Open in Xcode") { flow.openInIDE() }
                    QuietButton(title: "Change Selection") { flow.linkFolder() }
                    QuietButton(title: "Unlink") { flow.unlink() }
                        // The sentence this replaces stood under the row on every
                        // visit, in the smallest grey the app has, answering a
                        // question the developer asks once and only about the
                        // button it belongs to.
                        .help("Unlink removes this link only. It never deletes the project or its build output.")
                }
            }
        }
    }

    private var containerChooser: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Choose the container").font(Theme.font(size: 12.5, weight: .semibold))
            ForEach(flow.containers) { container in
                Button {
                    guard let root = flow.discoveryRoot else { return }
                    Task { await flow.select(container: container, root: root) }
                } label: {
                    HStack(spacing: 9) {
                        Text(container.kind.rawValue)
                            .font(Theme.font(size: 10.5))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 66, alignment: .leading)
                        Text(container.name).font(Theme.font(size: 12))
                        if !container.isBuildable {
                            StatePill(text: "Blocked", foreground: Theme.red,
                                      background: Theme.redBg)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!container.isBuildable)
                if !container.reasons.isEmpty {
                    Text(container.reasons.joined(separator: " "))
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.yellow)
                }
            }
        }
        .storePanel(horizontal: 15)
    }

    /// Which store this tab is building for.
    ///
    /// An app on both stores builds from two projects, and this tab had no way
    /// to say which one it meant: the platform came from whichever folder was
    /// linked last, and linking the second replaced the first.
    ///
    /// Above the link card and not inside the project card, because the card
    /// that shows when the store you switched to has no folder yet is the link
    /// card, and a switch you cannot undo from the screen it lands on is a
    /// trap.
    @ViewBuilder
    private var storeRow: some View {
        if state.stores.count > 1 {
            selectionRow("Store") {
                Picker("", selection: Binding(
                    get: { flow.platform.store },
                    set: { flow.choosePlatform($0 == .google ? .android : .ios) })) {
                    Text("App Store").tag(Store.apple)
                    Text("Google Play").tag(Store.google)
                }
                .labelsHidden().pickerStyle(.segmented)
                .disabled(flow.isBusy)
            }
        }
    }

    /// One row of the block: a label column and a control column, and both are
    /// the same width on every row.
    ///
    /// Each row used to size its own control — a segmented picker of 240 for
    /// Store, one of 170 for Platform, a 340 point menu for Scheme — so no two
    /// of them started or ended on the same x. Three rows of one block, in
    /// three widths, is what looked broken.
    private func selectionRow<Control: View>(
        _ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 9) {
            Text(label).font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
                .frame(width: Self.labelWidth, alignment: .leading)
            control()
                .frame(width: Self.controlWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private static let labelWidth: CGFloat = 92
    private static let controlWidth: CGFloat = 340

    private var selectionBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            storeRow
            if flow.project?.platform != .android {
                selectionRow("Platform") {
                    Picker("", selection: Binding(get: { flow.platform },
                                                  set: { flow.choosePlatform($0) })) {
                        Text("iOS").tag(BuildPlatform.ios)
                        Text("macOS").tag(BuildPlatform.macos)
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
                if let info = flow.containerInfo {
                    chooser("Scheme", options: info.schemes,
                            selected: flow.project?.selection.scheme) { flow.chooseScheme($0) }
                }
            } else {
                if !flow.variants.isEmpty {
                    chooser("Variant", options: flow.variants.map(\.qualifiedTask),
                            selected: flow.project?.selection.variantTask) { task in
                        guard let variant = flow.variants.first(where: {
                            $0.qualifiedTask == task
                        }) else { return }
                        flow.chooseVariant(variant)
                    }
                }
                if let jdks = flow.androidToolchain?.availableJDKs, jdks.count > 1 {
                    chooser("JDK", options: jdks.map(\.home),
                            selected: flow.project?.selection.javaHome) { flow.chooseJDK($0) }
                }
            }
            buildOptions
        }
    }

    /// The two answers the developer gives about the build itself, beside the
    /// pickers that say what is built.
    ///
    /// They stood at the foot of the preflight card, under twelve rows of
    /// read-only checks, which is a card of facts with two decisions buried in
    /// it. A check is something the app read; these are things the developer
    /// chooses, and every other choice on this tab is now in this box.
    @ViewBuilder
    private var buildOptions: some View {
        if flow.project?.platform != .android {
            // upload-spec 8.6. The sentence stays: this is the one control on
            // the tab that lets a build change something at Apple, and consent
            // asked without saying what it permits is not consent.
            Toggle(isOn: Bindable(flow).allowProvisioningUpdates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let Xcode update the provisioning")
                        .font(Theme.font(size: 12))
                    Text("Xcode may contact Apple and create or change an App ID, a certificate, or a profile.")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Toggle(isOn: Bindable(flow).alwaysReviewArtifact) {
                Text("Always review the built artifact before upload")
                    .font(Theme.font(size: 12))
            }
            .toggleStyle(.checkbox)
        }
    }

    private func chooser(_ label: String, options: [String], selected: String?,
                         choose: @escaping (String) -> Void) -> some View {
        selectionRow(label) {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { choose(option) }
                }
            } label: {
                HStack {
                    Text(selected ?? "Choose \(label.lowercased())…")
                        .font(Theme.font(size: 12))
                        .foregroundStyle(selected == nil ? Theme.text3 : Theme.text)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text("▾").font(Theme.font(size: 9)).foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        }
    }

    // MARK: - 10.3 The preflight card

    private var preflightCard: some View {
        let snapshot = flow.snapshot
        let summary = preflightSummary
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("Preflight").font(Theme.font(size: 12.5, weight: .semibold))
                Circle().fill(summary.status.color).frame(width: 6, height: 6)
                    .accessibilityLabel(summary.status.label)
                Text(summary.text)
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                if flow.state == .preflight { Spinner() }
                // The checks are what the app read, and a developer reads them
                // when something is wrong. Twelve rows of green were the top
                // half of this screen on every visit, and they pushed the one
                // button that starts the work down with them.
                QuietButton(title: showsChecks ? "Hide checks" : "Show checks") {
                    checksOpen = !showsChecks
                }
                if flow.state == .complete || flow.state == .cancelled {
                    ActionButton(title: flow.project?.platform == .android
                                 ? "Build a new App Bundle" : "Build a new archive") {
                        flow.buildAgain()
                    }
                }
                if flow.project?.platform == .android, !flow.state.isActive {
                    QuietButton(title: "Choose Built AAB") { flow.chooseBuiltBundle() }
                }
                // The command belongs to the checks it reads.
                //
                // It stood at the foot of the screen, under the live run, the
                // artifact card and the error panel, so on a tall window the
                // one button that starts the work was below the fold and the
                // card that says whether it may run was at the top. Building
                // is free, so this one wears no lock however the account
                // stands.
                if flow.state == .readyToBuild || flow.state == .failed {
                    // One press for an app that goes to both stores. It builds
                    // the App Bundle and then the archive: see
                    // `BuildFlow.buildBothStores` for why that order.
                    if flow.canBuildBothStores {
                        QuietButton(title: "Build Both Stores") {
                            flow.showBuildBothConfirmation = true
                        }
                    }
                    ActionButton(title: flow.project?.platform == .android
                                 ? "Build App Bundle" : "Build Archive",
                                 enabled: flow.canBuild) {
                        flow.showBuildConfirmation = true
                    }
                }
            }
            .padding(.bottom, showsChecks ? 9 : 0)

            if showsChecks {
                twoColumns(preflightRows(snapshot)) { label, value, status in
                    PreflightRow(label: label, value: value, status: status)
                }
            }

            if let override = flow.buildNumberOverride {
                Divider().padding(.vertical, 7)
                HStack(alignment: .top, spacing: 9) {
                    Text("This run builds number \(override). Your project keeps the number it has, and Super Submitter changes nothing in it.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    QuietButton(title: "Use the project's number") {
                        flow.useProjectBuildNumber()
                    }
                }
            }

            if let override = flow.marketingVersionOverride {
                Divider().padding(.vertical, 7)
                HStack(alignment: .top, spacing: 9) {
                    Text("This run builds version \(override), the release version in store.yaml. Your project keeps the version it has, and Super Submitter changes nothing in it.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    QuietButton(title: "Use the project's version") {
                        flow.useProjectVersion()
                    }
                }
            } else if let wanted = flow.versionFromManifest {
                Divider().padding(.vertical, 7)
                HStack(alignment: .top, spacing: 9) {
                    StatePill(text: "Version", foreground: Theme.yellow,
                              background: Theme.yellowBg)
                    // Said here, before the archive. The same disagreement was
                    // already caught after the build, where it blocks the
                    // upload and costs the whole build to find out.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("store.yaml names \(flow.run.platform.store.storeName) version \(wanted) and this project builds \(flow.snapshot.marketingVersion ?? "another one"). The upload is refused while they disagree.")
                            .font(Theme.font(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        // Only where the build takes the number from the
                        // command line. Gradle does not, so on Android the row
                        // says the two numbers and the developer settles it on
                        // the tab above or in the project.
                        if flow.canBuildTheManifestVersion {
                            QuietButton(title: "Build version \(wanted) instead") {
                                flow.useManifestVersion()
                            }
                        } else {
                            Text("Change the Google Play version above, or the version in the project.")
                                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            if let blocking = flow.blockingReason {
                Divider().padding(.vertical, 7)
                HStack(alignment: .top, spacing: 9) {
                    StatePill(text: "Blocked", foreground: Theme.red, background: Theme.redBg)
                    // The way out beside what is stopping it. A duplicate build
                    // number is the one block on this card that the app itself
                    // can clear, and the trip to Xcode to raise the number by
                    // one was the whole of the old answer.
                    VStack(alignment: .leading, spacing: 8) {
                        Text(blocking).font(Theme.font(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        if let next = flow.nextFreeBuildNumber {
                            QuietButton(title: "Build number \(next) instead") {
                                flow.useNextBuildNumber()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            ForEach(flow.warnings, id: \.self) { warning in
                Text(warning).font(Theme.font(size: 11.5)).foregroundStyle(Theme.yellow)
            }
        }
        // The checks are a fold like the log and like every other one.
        .motion(.easeInOut(duration: 0.22), value: showsChecks)
    }

    private func preflightRows(_ snapshot: PreflightSnapshot)
        -> [(String, String, PreflightRow.Status)] {
        var rows: [(String, String, PreflightRow.Status)] = []
        func add(_ label: String, _ value: String?, key: String = "",
                 blockingWhenEmpty: Bool = false) {
            let isEmpty = value?.isEmpty != false
            let text = isEmpty ? (flow.state == .preflight ? "Checking…" : "Not read") : value!
            let status: PreflightRow.Status
            if isEmpty, flow.state == .preflight {
                status = .unknown
            } else if snapshot.isUncertain(key) {
                status = .unknown
            } else if isEmpty {
                status = blockingWhenEmpty ? .blocked : .unknown
            } else {
                status = .ready
            }
            rows.append((label, text, status))
        }
        add("Toolchain", snapshot.toolchain, blockingWhenEmpty: true)
        if flow.project?.platform == .android {
            add("Gradle", snapshot.gradleVersion)
            add("JDK", snapshot.javaVersion)
            add("Android SDK", snapshot.androidSDKPath, blockingWhenEmpty: true)
            add("Module and task", snapshot.variantTask, blockingWhenEmpty: true)
            add("Output", snapshot.outputExpectation)
        } else {
            add("SDK", snapshot.sdk)
            add("Scheme", snapshot.scheme, blockingWhenEmpty: true)
            add("Configuration", snapshot.configuration)
            add("Destination", snapshot.destination)
            add("Team", snapshot.team)
            add("Signing", snapshot.signingStyle)
        }
        add("Product", snapshot.productName, key: "productName")
        add("Identifier", snapshot.productIdentifier, key: "productIdentifier")
        // Yellow, and it names the other number. Green beside a version the
        // upload is going to refuse is the app agreeing with itself and not
        // with the developer, who has the release version on screen above.
        if let wanted = flow.versionFromManifest {
            rows.append(("Version",
                         "\(snapshot.marketingVersion ?? "Not read") · store.yaml names \(wanted)",
                         .warning))
        } else {
            add("Version", snapshot.marketingVersion, key: "marketingVersion")
        }
        add("Build", snapshot.buildVersion, key: "buildVersion")
        if let conflict = snapshot.remoteConflict {
            rows.append(("Store", conflict,
                         flow.blocking == nil ? .ready : .blocked))
        }
        return rows
    }

    // MARK: - 10.4 The live run

    /// How long the run has taken, counted while it runs.
    ///
    /// `flow.elapsed` reads the clock, and a clock is not observable state, so
    /// the label only ever redrew when something else on the screen changed:
    /// opening the log moved a value SwiftUI does watch, and the minutes
    /// jumped. `TimelineView` is the redraw, and it stops with the run rather
    /// than ticking over a number that has stopped moving.
    @ViewBuilder
    private var elapsedLabel: some View {
        if flow.state.isActive, let startedAt = flow.startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { _ in
                elapsedText
            }
        } else if !flow.elapsed.isEmpty {
            elapsedText
        }
    }

    private var elapsedText: some View {
        Text("\(flow.elapsed) elapsed")
            .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
            .monospacedDigit()
    }

    private var liveRun: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if flow.state.isActive { Spinner() }
                Text(flow.state.stepTitle).font(Theme.font(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                elapsedLabel
            }
            Text(explanation).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if flow.state == .uploading || flow.state == .processingOrValidating {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.sep)
                        Capsule().fill(Theme.accent)
                            .frame(width: geometry.size.width * max(0.03, flow.uploadProgress))
                    }
                }
                .frame(height: 6)
            }
            if let processing = flow.processingLabel {
                Text(processing).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }

            HStack(spacing: 7) {
                if flow.state.isActive, flow.state != .processingOrValidating {
                    QuietButton(title: "Cancel") { flow.cancel() }
                }
                if flow.state == .processingOrValidating {
                    QuietButton(title: "Stop waiting") { flow.stopWaiting() }
                }
                if flow.state == .recoveryRequired {
                    QuietButton(title: "Resume checking") { flow.resumeChecking() }
                }
                if flow.run.cleanupState == .needsAttention {
                    QuietButton(title: "Retry cleanup") { flow.retryCleanup() }
                }
                Spacer(minLength: 0)
                QuietButton(title: flow.logOpen ? "Hide log" : "Show log") {
                    flow.logOpen.toggle()
                }
            }

            if flow.logOpen { LogView(lines: flow.logLines, copyText: flow.logText) }
        }
        .storePanel(horizontal: 15)
        // The log is a fold like every other one, including when a failure
        // opens it rather than the button.
        .motion(.easeInOut(duration: 0.22), value: flow.logOpen)
    }

    private var explanation: String {
        switch flow.state {
        case .preflight:
            "Checking the toolchain, build settings, signing, and store conflicts. Nothing is being built or uploaded."
        case .building:
            "Your own build tool is running. Super Submitter reads its output and changes nothing in the project."
        case .inspectingArtifact:
            "Inspecting the artifact. The artifact, not the preflight, decides what gets uploaded."
        case .uploading:
            "Sending the exact file that this run produced."
        case .processingOrValidating:
            "The store is processing the upload. This can outlive the app, and it resumes later."
        case .cancelling:
            "Stopping this run's own processes, then checking what the store already holds."
        default:
            "Nothing is running."
        }
    }

    // MARK: - 10.5 The two confirmations

    private var buildConfirmation: some View {
        ConfirmationSheet(
            title: flow.project?.platform == .android
                ? "Build the App Bundle?" : "Build the archive?",
            body: flow.buildConfirmationText,
            rows: buildRows,
            note: buildNote,
            confirm: flow.project?.platform == .android ? "Build App Bundle" : "Build Archive",
            destructive: false) {
            flow.startBuild()
        }
    }

    /// Two projects, so the question names both of them. Building runs the
    /// scripts of each, and one press may not consent to a project the
    /// developer never saw named.
    private var buildBothConfirmation: some View {
        ConfirmationSheet(
            title: "Build both stores?",
            body: "Build the App Bundle from \(folderName(.google)) and then the archive from \(folderName(.apple)). This can run scripts and plug-ins supplied by either project.",
            rows: [("Order", "Google Play first, then the App Store"),
                   ("Google Play", flow.savedProject(for: .google)?.containerPath ?? "no project"),
                   ("App Store", flow.savedProject(for: .apple)?.containerPath ?? "no project")],
            note: "Neither artifact is sent. The App Bundle is written into store.yaml and the archive waits on this tab, each with its own upload confirmation.",
            confirm: "Build Both",
            destructive: false) {
            flow.buildBothStores()
        }
    }

    private func folderName(_ store: Store) -> String {
        flow.savedProject(for: store)?.rootURL.lastPathComponent ?? "its folder"
    }

    /// The note must state the two things that change what happens next, and
    /// the build number when it is not the project's own.
    private var buildNote: String {
        var note = flow.allowProvisioningUpdates
            ? "Xcode may contact Apple and create or change an App ID, a certificate, or a profile during this build."
            : "Xcode will not change any App ID, certificate, or profile."
        if let override = flow.buildNumberOverride {
            note = "This build carries the number \(override), which you chose here. "
                + "The project file keeps its own number. " + note
        }
        guard flow.project?.platform != .android else {
            return note + " The build stops afterwards, and you confirm the upload separately."
        }
        return note + (flow.alwaysReviewArtifact
            ? " The build stops afterwards, and you confirm the upload separately."
            : " When the built archive matches this summary exactly, the upload starts by itself.")
    }

    private var buildRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Folder", flow.project?.rootPath ?? ""),
            ("Container", flow.project?.containerURL.lastPathComponent ?? ""),
            ("Toolchain", flow.snapshot.toolchain ?? ""),
        ]
        if flow.project?.platform == .android {
            rows += [("Task", flow.snapshot.variantTask ?? ""),
                     ("JDK", flow.snapshot.javaVersion ?? ""),
                     ("Output", flow.snapshot.outputExpectation ?? "")]
        } else {
            rows += [("Scheme", flow.snapshot.scheme ?? ""),
                     ("Configuration", flow.snapshot.configuration ?? ""),
                     ("Destination", flow.snapshot.destination ?? ""),
                     ("Identifier", flow.snapshot.productIdentifier ?? ""),
                     ("Version", "\(flow.snapshot.marketingVersion ?? "") (\(flow.snapshot.buildVersion ?? ""))"),
                     ("Team", flow.snapshot.team ?? ""),
                     ("Archive", "Kept outside your repository, in Application Support")]
        }
        rows.append(("Store", flow.snapshot.remoteConflict ?? "not checked"))
        return rows
    }

    private var uploadConfirmation: some View {
        ConfirmationSheet(
            title: "Upload this build?",
            body: flow.uploadConfirmationText,
            rows: uploadRows,
            note: "The upload cannot be recalled reliably once the store accepts it.",
            confirm: "Upload",
            destructive: false) {
            flow.startUpload()
        }
    }

    private var uploadRows: [(String, String)] {
        guard let candidate = flow.candidate else { return [] }
        var rows: [(String, String)] = [
            ("Product", candidate.productName),
            ("Identifier", candidate.productIdentifier),
            ("Version", candidate.marketingVersion),
            (candidate.platform == .android ? "Version code" : "Build", candidate.buildVersion),
            ("Size", candidate.sizeText),
            ("SHA-256", String(candidate.sha256.prefix(16)) + "…"),
            ("Signature", candidate.signingSummary.verified == true
                ? "verified" : "not verified"),
            ("Store", flow.snapshot.remoteConflict ?? "not checked"),
            ("Method", candidate.platform == .android
                ? "One Google Play edit, committed as a draft"
                : "xcodebuild -exportArchive, destination upload"),
        ]
        if !candidate.mismatches.isEmpty {
            rows.append(("Changed since preflight",
                         candidate.mismatches.map(\.field).joined(separator: ", ")))
        }
        return rows
    }

    // MARK: - 10.6 Success and 10.7 Errors

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(flow.artifactOnly ? "The artifact is kept." : "The build reached the store.")
                .font(Theme.font(size: 15, weight: .semibold))
            if let candidate = flow.candidate {
                Text(flow.artifactOnly
                     ? "\(candidate.productIdentifier) \(candidate.marketingVersion) (\(candidate.buildVersion)) was kept locally and was not uploaded."
                     : "\(candidate.productIdentifier) \(candidate.marketingVersion) (\(candidate.buildVersion)) is in the store as a draft. Nothing was sent for review.")
                    .font(Theme.font(size: 12.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 7) {
                if let link = flow.successLink {
                    QuietButton(title: flow.candidate?.platform == .android
                                ? "Open Play Console ↗" : "Open App Store Connect ↗") {
                        state.open(link)
                    }
                }
                if let candidate = flow.candidate, !flow.artifactDeleted {
                    QuietButton(title: candidate.platform == .android
                                ? "Reveal AAB" : "Reveal Archive") {
                        flow.reveal(candidate.artifactPath)
                    }
                    // The moment it is most wanted: the store holds the build,
                    // so the copy on this Mac is a few hundred megabytes that
                    // have done their job.
                    if flow.artifactIsDeletable {
                        QuietButton(title: "Delete Archive") { deleting = true }
                    }
                }
                QuietButton(title: "Continue to Summary") {
                    state.adoptBuiltArtifact(from: flow)
                    state.selectedTab = .plan
                }
                Spacer(minLength: 0)
            }
        }
        .storePanel(horizontal: 15, background: Theme.greenBg, border: Theme.green, borderWidth: 1)
    }

    private func errorPanel(_ failure: BuildFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                StatePill(text: failure.category.rawValue, foreground: Theme.red,
                          background: Theme.redBg)
                Text(failure.stage).font(Theme.font(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text(failure.message).font(Theme.font(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            if let recovery = failure.recovery {
                Text(recovery).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if failure.retainedArtifact != nil || failure.retainedRemoteEdit != nil {
                Text(retention(failure))
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 7) {
                Button { flow.retry() } label: {
                    Text("Retry")
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                if failure.category == .signing || failure.category == .configuration {
                    QuietButton(title: flow.project?.platform == .android
                                ? "Open in Android Studio" : "Open in Xcode") { flow.openInIDE() }
                }
                if let path = failure.retainedArtifact {
                    QuietButton(title: "Reveal artifact") { flow.reveal(path) }
                }
                QuietButton(title: "Copy Redacted Diagnostics") { flow.copyDiagnostics() }
                Spacer(minLength: 0)
            }
            // Open. A failure panel that hides what the tool said behind a
            // triangle is a panel that reports an exit status and nothing
            // else, and the exit status is the one part nobody can act on.
            if let diagnostics = failure.diagnostics, !diagnostics.isEmpty {
                DisclosureGroup("Diagnostics", isExpanded: $diagnosticsOpen) {
                    ScrollView {
                        Text(diagnostics).font(Theme.mono(10.5))
                            .foregroundStyle(Theme.text2).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                }
                .font(Theme.font(size: 11.5))
                .motion(.smooth(duration: 0.22), value: diagnosticsOpen)
            }
        }
        .storePanel(horizontal: 15, background: Theme.redBg, border: Theme.red, borderWidth: 1)
    }

    private func retention(_ failure: BuildFailure) -> String {
        var parts: [String] = []
        if failure.retainedArtifact != nil {
            parts.append("The built artifact is kept.")
        }
        if let edit = failure.retainedRemoteEdit {
            parts.append("The Google edit \(edit) is recorded; an uncommitted edit is invisible and expires by itself.")
        }
        return parts.joined(separator: " ")
    }
}

/// The artifact this Mac produced, without a panel of its own.
struct BuiltArtifactSection: View {
    @Environment(AppState.self) private var state
    @State private var detailsOpen: Bool?
    @State private var deleting = false

    private var flow: BuildFlow { state.buildFlow }

    private var showsDetails: Bool {
        detailsOpen ?? (flow.state == .needsUploadConfirmation)
    }

    var body: some View {
        if let candidate = flow.candidate { card(candidate) }
    }

    private func card(_ candidate: BuildCandidate) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text("Built on this Mac").font(Theme.font(size: 12.5, weight: .semibold))
                Text("\(candidate.marketingVersion) (\(candidate.buildVersion)) · \(candidate.sizeText)")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatePill(text: candidate.signingSummary.verified == true
                          ? "Signature verified" : "Signature not verified",
                          foreground: candidate.signingSummary.verified == true
                              ? Theme.green : Theme.red,
                          background: candidate.signingSummary.verified == true
                              ? Theme.greenBg : Theme.redBg)
                QuietButton(title: showsDetails ? "Hide details" : "Show details") {
                    detailsOpen = !showsDetails
                }
            }
            if showsDetails {
                ArtifactRows(rows: Self.rows(candidate))
            }
            ForEach(candidate.mismatches) { mismatch in
                HStack(alignment: .top, spacing: 9) {
                    StatePill(text: mismatch.blocksUpload ? "Blocked" : "Changed",
                              foreground: mismatch.blocksUpload ? Theme.red : Theme.yellow,
                              background: mismatch.blocksUpload ? Theme.redBg : Theme.yellowBg)
                    Text("\(mismatch.field): the preflight said \(mismatch.expected) and the artifact holds \(mismatch.actual).")
                        .font(Theme.font(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 7) {
                if flow.state == .needsUploadConfirmation {
                    ActionButton(title: "Upload to the store", enabled: flow.canUpload,
                                 paid: (.storeUpload, .upload)) {
                        flow.showUploadConfirmation = true
                    }
                    ActionButton(title: "Keep the artifact and stop", kind: .secondary) {
                        flow.keepArtifact()
                    }
                }
                if flow.artifactDeleted {
                    Text("Deleted from this Mac. The record above is what was built.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                } else {
                    QuietButton(title: "Reveal artifact") { flow.reveal(candidate.artifactPath) }
                    if flow.artifactIsDeletable {
                        QuietButton(title: "Delete artifact") { deleting = true }
                    }
                }
                if flow.project == nil, flow.state != .complete {
                    QuietButton(title: "Start over") { flow.reset() }
                }
                Spacer(minLength: 0)
            }
            if let held = flow.uploadBlockedByReview,
               flow.state == .needsUploadConfirmation {
                HStack(spacing: 8) {
                    StatePill(text: "Held", foreground: Theme.yellow,
                              background: Theme.yellowBg)
                    Text(held).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(.easeInOut(duration: 0.22), value: showsDetails)
        .deleteArtifactConfirmation($deleting, flow: flow)
    }

    static func rows(_ candidate: BuildCandidate) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Product", candidate.productName),
            ("Identifier", candidate.productIdentifier),
            ("Version", candidate.marketingVersion),
            (candidate.platform == .android ? "Version code" : "Build", candidate.buildVersion),
            ("Size", candidate.sizeText),
            ("SHA-256", candidate.sha256.isEmpty ? "Not read" : candidate.sha256),
            ("Path", candidate.artifactPath),
        ]
        if let subject = candidate.signingSummary.certificateSubject {
            rows.append(("Certificate", subject))
        }
        if let team = candidate.signingSummary.team { rows.append(("Team", team)) }
        if let identity = candidate.signingSummary.identity {
            rows.append(("Identity", identity))
        }
        return rows
    }
}

private struct ArtifactRows: View {
    let rows: [(String, String)]

    var body: some View {
        let half = (rows.count + 1) / 2
        HStack(alignment: .top, spacing: 22) {
            column(Array(rows.prefix(half)))
            column(Array(rows.dropFirst(half)))
        }
    }

    private func column(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.0).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .frame(width: 96, alignment: .leading)
                    Text(row.1).font(Theme.mono(11.5)).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Both delete buttons ask one question about the same file.
    func deleteArtifactConfirmation(_ isPresented: Binding<Bool>,
                                    flow: BuildFlow) -> some View {
        confirmationDialog("Delete the built artifact?", isPresented: isPresented,
                           titleVisibility: .visible) {
            Button("Delete", role: .destructive) { flow.deleteArtifact() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The archive Super Submitter built is removed from this Mac. Your project is untouched, and a build the store has already accepted stays where it is. Building again makes a new one.")
        }
    }
}

// MARK: - The small parts

struct PreflightRow: View {
    enum Status: Equatable { case ready, warning, unknown, blocked

        var color: Color {
            switch self {
            case .ready: Theme.green
            case .warning: Theme.yellow
            case .unknown: Theme.text3
            case .blocked: Theme.red
            }
        }

        var label: String {
            switch self {
            case .ready: "Ready"
            case .warning: "Warning"
            case .unknown: "To be verified"
            case .blocked: "Blocked"
            }
        }
    }

    let label: String
    let value: String
    let status: Status

    /// The dot leads the row.
    ///
    /// It followed the value, against the far edge of the column, so a row of
    /// three words put its own status six hundred points away from itself and
    /// the eye crossed an empty half of the card to read a colour. Leading, the
    /// dots are one column the length of the list, which is what a column of
    /// states is for, and the gap they were holding open is gone.
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(status.color).frame(width: 6, height: 6).padding(.top, 5)
                .accessibilityLabel(status.label)
            Text(label).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(Theme.font(size: 11.5))
                .foregroundStyle(status == .blocked ? Theme.red : Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

/// One guarded action, with the exact values it will use.
struct ConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let body_: String
    let rows: [(String, String)]
    let note: String
    let confirm: String
    let destructive: Bool
    let action: () -> Void

    init(title: String, body: String, rows: [(String, String)], note: String,
         confirm: String, destructive: Bool, action: @escaping () -> Void) {
        self.title = title
        self.body_ = body
        self.rows = rows
        self.note = note
        self.confirm = confirm
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(Theme.font(size: 15, weight: .semibold))
            Text(body_).font(Theme.font(size: 12.5)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { key, value in
                    HStack(alignment: .top, spacing: 12) {
                        Text(key).foregroundStyle(Theme.text2)
                            .frame(width: 118, alignment: .leading)
                        Text(value).font(Theme.mono(11.5)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(Theme.font(size: 11.5))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))

            Text(note).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Spacer()
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(size: 13)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Button {
                    dismiss()
                    action()
                } label: {
                    Text(confirm).font(Theme.font(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(destructive ? Theme.redFill : Theme.accent,
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 18)
        .frame(width: 560)
        .background(Theme.content)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }
}

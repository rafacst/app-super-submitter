import SubmitKit
import SwiftUI

/// The five things a release passes through, and what each of them holds now.
///
/// The tab answered "what changes" in exact detail and never answered "where
/// am I": a developer met a diff with no account of the pass around it, and
/// "does apply send this to a customer" was answered by the small print under
/// a button. Each caption reads real state or says plainly that it has none.
/// None of them invents a number.
enum RunwayStep {

    /// What the listing holds, in languages rather than in fields: a field
    /// count needs a read of both stores to mean anything, and this step has to
    /// say something true before the first read.
    @MainActor
    static func describe(_ state: AppState) -> String {
        let locales = state.locales.count
        guard locales > 0 else { return "no language yet" }
        return locales == 1 ? "1 language" : "\(locales) languages"
    }

    /// The artifacts the manifest names, and how many of those files are on
    /// this Mac. An attached build is the one thing a version cannot ship
    /// without and the one thing the manifest cannot prove by itself.
    @MainActor
    static func build(_ state: AppState) -> String {
        let named = AppPackage.Kind.allCases.filter { kind in
            let path: String? = switch kind {
            case .ipa: state.manifest.release?.build?.ios
            case .pkg: state.manifest.release?.build?.macos
            case .aab: state.manifest.release?.build?.android
            }
            return !(path ?? "").isEmpty
        }
        guard !named.isEmpty else { return storeBuild(state) ?? "no artifact named" }
        let here = named.filter { state.missingBuildNote($0) == nil }.count
        let word = named.count == 1 ? "artifact" : "artifacts"
        if here == 0 { return "\(named.count) \(word) named, none found" }
        if here == named.count { return "\(named.count) \(word) ready" }
        return "\(named.count) \(word) named, \(here) found"
    }

    /// What App Store Connect already holds for this version.
    ///
    /// An Apple build names no file on purpose: `xcodebuild -exportArchive`
    /// sends the binary itself, so `adoptBuiltArtifact` writes no path and the
    /// artifact that ships is the one in the store. Reading the manifest alone,
    /// this step answered "no artifact named" for every Apple app that ever
    /// existed, including the minute after a build reached the store, which is
    /// the minute a developer comes here to check.
    ///
    /// The number is the highest in this version's train, which is the build
    /// the upload just added. It is named only when it is the build being
    /// described: a version can hold an older build than the newest one on the
    /// store, and printing the highest number beside "attached" would name a
    /// build that is not the attached one. When the number cannot be trusted
    /// the row still says a build is there, because the build is the answer
    /// and its number is the detail.
    @MainActor
    private static func storeBuild(_ state: AppState) -> String? {
        guard let apple = state.actualState.apple else { return nil }
        let newest = apple.highestBuildNumber.map { "build \($0)" } ?? "a build"
        if let attached = apple.attachedBuildId {
            return "\(attached == apple.buildIdForVersion ? newest : "a build") attached"
        }
        if apple.buildIdForVersion != nil { return "\(newest) uploaded, not attached" }
        return nil
    }

    /// The two numbers the whole tab produces, or the fact that it has not
    /// produced them yet.
    @MainActor
    static func plan(_ state: AppState) -> String {
        guard let plan = state.plan else {
            return state.planReading ? "reading the stores" : "not read yet"
        }
        return "\(plan.writeCount) writes · \(plan.uploadCount) uploads"
    }

    /// Where a run ends. This is the sentence the product is built around, and
    /// a dry run ends somewhere else entirely.
    @MainActor
    static func apply(_ state: AppState) -> String {
        state.dryRun ? "dry run, sends nothing" : "writes drafts only"
    }

    /// Nothing here reaches a customer. The Release tab does, and only when it
    /// is pressed.
    @MainActor
    static func release(_ state: AppState) -> String {
        state.stores.count > 1 ? "you press it, one store at a time" : "you press it"
    }
}

/// Tab 7. Every change, before any write. This tab is the safety model of the
/// product, and it is the one screen that can refuse to continue.
struct PlanTab: View {
    @Environment(AppState.self) private var state
    /// Holds the question open while the developer answers it. See applyRow.
    @State private var confirmingApply = false
    /// Shut by default. See acknowledgedSummary.
    @State private var showingAcknowledged = false
    /// The systems whose rows are open. Empty, so every column arrives shut.
    @State private var openColumns: Set<PlanSystem> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The runway stays put while the tab under it changes between the
            // placeholders, the diff and the run. It is the one part of this
            // screen that answers a question the diff cannot: where the release
            // has got to, and where pressing the button ends.
            if !state.showsRun { runway }
            // What Apple said, and the two ways forward while it has not said
            // anything yet. Above the diff, because a diff nobody may send is
            // not the first thing this screen has to answer.
            if !state.showsRun { reviewBanner }
            content
        }
    }

    // MARK: - The version App Store review is holding

    /// One panel, three states: Apple is still reading it, Apple approved it,
    /// or Apple refused it.
    @ViewBuilder
    private var reviewBanner: some View {
        if let answer = state.reviewOutcome {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Circle().fill(Self.outcomeColour(answer.outcome))
                        .frame(width: 8, height: 8)
                    Text(answer.line)
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    // The reason lives in the Resolution Center and in no
                    // endpoint, so a refusal offers the one place that has it.
                    if answer.outcome == .refused {
                        QuietButton(title: "Open App Store Connect") {
                            state.open("https://appstoreconnect.apple.com/apps/\(state.manifest.apps.apple?.appId ?? "")/distribution")
                        }
                    }
                }
                // The card below drops this finding's row, because the banner
                // is already saying it in more words. The row carried the only
                // tick that unlocks this apply, so the tick lands here.
                if let waiting = state.reviewWarningNeedingAcknowledgement {
                    HStack(spacing: 9) {
                        AcknowledgeToggle(id: waiting.id)
                        Text("The apply stays shut until you have read this.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        Spacer(minLength: 0)
                    }
                }
                if state.reviewNeedsAChoice { reviewChoice }
                if let path = state.reviewPath, state.appleHoldsAVersion {
                    reviewChosen(path)
                }
                if let error = state.reviewRetrievalError { ErrorLine(text: error) }
            }
            .storePanel(background: Self.outcomeColour(answer.outcome).opacity(0.08),
                        border: Self.outcomeColour(answer.outcome).opacity(0.3))
        }
    }

    private static func outcomeColour(_ outcome: AppleVersionState.Outcome) -> Color {
        switch outcome {
        case .waiting: Theme.yellow
        case .approved: Theme.green
        case .refused: Theme.red
        }
    }

    /// The question, asked once per version.
    ///
    /// Two real answers and no default. Looking at what was sent and starting
    /// the version after it are different jobs, and the app cannot know which
    /// one the developer opened it for.
    private var reviewChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing can be sent until Apple answers. Two things can be done now.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            HStack(spacing: 9) {
                Button("See what was sent") {
                    state.chooseReviewPath(.inspect)
                    Task { await state.retrieveVersionInReview() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Button("Write the next version") { state.chooseReviewPath(.next) }
                Spacer(minLength: 0)
            }
            Text("Seeing what was sent reads the text and the screenshots of the version Apple is reading, and locks the listing while you look. Writing the next version leaves everything open, and the drafts wait here until Apple answers.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the developer picked, and the way back out of it.
    private func reviewChosen(_ path: AppState.ReviewPath) -> some View {
        HStack(spacing: 9) {
            if state.reviewRetrieving { Spinner() }
            Text(path == .inspect
                 ? "Showing what was sent. The listing is read-only while Apple has it."
                 : "Writing the next version. Everything is editable and nothing is sent yet.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if path == .inspect {
                QuietButton(title: "Read it again") {
                    Task { await state.retrieveVersionInReview() }
                }
                .disabled(state.reviewRetrieving)
            }
            QuietButton(title: "Change") { state.clearReviewPath() }
        }
    }

    private var content: some View {
        Group {
            // The run replaces the diff on the same tab. Pressing Apply used
            // to move the developer to a tab of its own, which put a
            // navigation step between the decision and its consequence.
            if state.showsRun {
                RunSection()
            } else if state.planReading {
                reading
            } else if let plan = state.plan {
                if plan.isEmpty && plan.findings.isEmpty {
                    nothingToChange
                } else {
                    theDiff(plan)
                }
            } else {
                notReadYet
            }
        }
        // The placeholders dissolve into the plan they were standing in for.
        // The geometry already matches, so a crossfade is the whole transition
        // this needs: nothing has to travel because nothing has moved.
        .motion(.smooth(duration: 0.25), value: state.planReading)
        .task(id: state.manifestURL) {
            // The app never skips the plan. Without it, the app writes to a
            // live listing on a guess.
            //
            // The read happens once, and after that only when the developer
            // asks. Reading on every visit meant that leaving to check one
            // field and coming back cost a full pass over both stores, and
            // the diff the developer was reading vanished behind a spinner
            // while it happened.
            //
            // A plan older than the manifest stays impossible, which is what
            // made this safe to change: every edit calls `invalidatePlan`, so
            // a plan on screen was always read after the last edit. What it
            // can lag is the store itself, so the read time sits on the
            // screen and "Read the stores again" is in the header.
            guard !state.planReading, !state.stores.isEmpty, state.plan == nil
            else { return }
            await state.readStores()
        }
    }

    // MARK: - The runway

    /// The version being shipped, and the five steps it passes through.
    private var runway: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(shipTitle).font(Theme.font(size: 17, weight: .semibold))
                Spacer(minLength: 8)
                // The failure panel below carries its own retry beside the
                // reason it failed. Two "Read again" buttons on one screen is
                // one button too many, and the one next to the message is the
                // one that explains itself.
                if state.planReadFailures.isEmpty {
                    if state.plan?.readAt != nil {
                        Text("Read at \(readTime)")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    }
                    QuietButton(title: "Read again") { Task { await state.readStores() } }
                }
            }
            // The rule under the title, and one between every pair of steps.
            // Five captions of five different lengths ran edge to edge with
            // nothing between them, so "3 artifacts named, none found" and the
            // number of the step after it read as one sentence, and the eye had
            // to find the column boundaries from the numbers alone.
            Hairline()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(stepList) { entry in
                        // `Divider` in an `HStack` is the vertical rule, sized
                        // to the tallest column by AppKit rather than by a
                        // guess at how many lines a caption takes.
                        if entry.number > 1 {
                            Divider().overlay(Theme.sep).padding(.horizontal, 10)
                        }
                        step(entry)
                    }
                }
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(stepList) { entry in step(entry) }
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    /// The five steps, as data.
    ///
    /// It was a `@ViewBuilder`, which hands back one opaque value: nothing can
    /// count it, and nothing can put a rule between its parts. Two layouts draw
    /// this list and both want separators, so the list is data and the drawing
    /// is the loop.
    private var stepList: [RunwayEntry] {
        [RunwayEntry(number: 1, title: "Describe",
                     caption: RunwayStep.describe(state), tab: .details),
         RunwayEntry(number: 2, title: "Build",
                     caption: RunwayStep.build(state), tab: .build),
         RunwayEntry(number: 3, title: "Plan",
                     caption: RunwayStep.plan(state), tab: nil),
         RunwayEntry(number: 4, title: "Apply",
                     caption: RunwayStep.apply(state), tab: nil),
         RunwayEntry(number: 5, title: "Release",
                     caption: RunwayStep.release(state), tab: .release)]
    }

    /// One step. The three that own a tab open it; Plan and Apply are this
    /// screen, so pressing them would go nowhere.
    @ViewBuilder
    private func step(_ entry: RunwayEntry) -> some View {
        let here = entry.number == 3 || entry.number == 4
        let body = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(verbatim: "\(entry.number)")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(here ? Theme.accentText : Theme.text3)
                    .frame(width: 15, height: 15)
                    .background(here ? Theme.accent : Theme.sunken, in: Circle())
                Text(entry.title)
                    .font(Theme.font(size: 12.5, weight: here ? .semibold : .medium))
                    .foregroundStyle(here ? Theme.text : Theme.text2)
            }
            Text(entry.caption).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The whole column, so the rules beside it run the full height and the
        // one caption that takes two lines does not shorten its own divider.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        if let tab = entry.tab {
            Button { state.selectedTab = tab } label: { body.contentShape(.rect) }
                .buttonStyle(.plain)
                .help("Open \(tab.title)")
        } else {
            body
        }
    }

    /// The release this pass sends, named by the version in the manifest.
    private var shipTitle: String {
        let version = state.manifest.displayVersionName ?? ""
        return version.isEmpty ? "Ship this release" : "Ship \(version)"
    }

    // MARK: - Before the read

    /// One line and a spinner, over the shape of the answer.
    ///
    /// The read takes seconds against two APIs, and the tab drew a single line
    /// on an empty page for all of it. When the plan landed, a grid of columns
    /// and two counters appeared where there had been nothing, and the page
    /// jumped by most of its own height.
    ///
    /// The placeholders match the real grid: the same adaptive 320 point
    /// columns, the same card, the same header row, so nothing moves sideways
    /// when the real thing replaces them. One card per store being read, and
    /// never a fixed number, because a developer with one store connected must
    /// not watch two columns load.
    ///
    /// `.redacted(reason: .placeholder)` and not a hand-drawn shimmer. It is
    /// the system's own treatment, it needs no loop, and the report warns that
    /// a conspicuous repeating shimmer is the wrong thing in dense desktop
    /// work. The spinner above already says the app is busy.
    private var reading: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Spinner()
                Text("Reading both stores. This writes nothing.")
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.text2)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14,
                                         alignment: .top)],
                      alignment: .leading, spacing: 14) {
                ForEach(Store.allCases.filter { state.stores.contains($0) }) { store in
                    placeholderColumn(store)
                }
            }
            .redacted(reason: .placeholder)
            // Not spoken. A reader would otherwise hear four lines of dummy
            // text as though they were the plan. The line above says what is
            // happening, and it is the only thing here worth hearing.
            .accessibilityHidden(true)
        }
    }

    /// One store's column, at the size the real one will be.
    private func placeholderColumn(_ store: Store) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StoreMark(store: store, size: 16)
                Text(store.storeName).font(Theme.font(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                Text("0 writes").font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            VStack(alignment: .leading, spacing: 0) {
                // Four rows, of three lengths. Every row at one width reads as
                // a bar chart rather than as text that has not arrived.
                ForEach(["Reading the listing for every language",
                         "Reading the media",
                         "Reading the prices and the purchases",
                         "Reading the release"], id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("~").font(Theme.mono(11.5, weight: .bold))
                        Text(line).font(Theme.mono(11.5))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var notReadYet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing read yet.").font(Theme.font(size: 15, weight: .semibold))
            Text("The plan reads every store and compares it to these tabs. It opens no Google edit, it creates no Apple resource, and it writes nothing.")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Read the stores") { Task { await state.readStores() } }
        }
    }

    // MARK: - Nothing changed

    /// A real state, and a common one. It means the work is done, so it reads
    /// as a success and not as an empty box.
    private var nothingToChange: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Circle()
                    .fill(Theme.greenBg)
                    .frame(width: 26, height: 26)
                    .overlay(Text("✓").font(Theme.font(size: 13)).foregroundStyle(Theme.green))
                Text("Nothing to change.")
                    .font(Theme.font(size: 17, weight: .semibold))
                    .kerning(-0.17)
            }
            Text("Both stores match what these tabs hold. The last read ran at \(readTime). A second apply would write nothing.")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(matchRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Hairline(color: Theme.sep2) }
                    HStack(spacing: 12) {
                        Text(row.system)
                            .font(Theme.font(size: 12.5, weight: .medium))
                            .frame(width: Theme.scaled(110), alignment: .leading)
                        Text(row.line).font(Theme.font(size: 12.5)).foregroundStyle(Theme.text2)
                        Spacer(minLength: 8)
                        Text("In sync").font(Theme.font(size: 11.5)).foregroundStyle(Theme.green)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))

            HStack(spacing: 9) {
                QuietButton(title: "Read the stores again") {
                    Task { await state.readStores() }
                }
                Button { state.selectedTab = .release } label: {
                    Text("Go to Release")
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var matchRows: [(system: String, line: String)] {
        var rows: [(String, String)] = []
        if state.stores.contains(.apple) {
            let version = state.actualState.apple?.versionString ?? "no version"
            rows.append(("App Store",
                         "Version \(version). Listing, media, and purchases match."))
        }
        if state.stores.contains(.google) {
            let code = state.actualState.google?.highestVersionCode.map(String.init) ?? "none"
            let track = state.manifest.googlePrimaryTrack
            rows.append(("Google Play",
                         "Version code \(code) in \(track). Listing, media, and purchases match."))
        }
        if let provider = state.actualState.provider, provider.kind != .none {
            rows.append((provider.kind == .adapty ? "Adapty" : "RevenueCat",
                         "\(provider.productIds.count) products, \(provider.entitlementKeys.count) entitlements, \(provider.offeringKeys.count) offerings. All match."))
        }
        return rows
    }

    private var readTime: String {
        guard let date = state.plan?.readAt else { return "no time" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - The diff

    /// The diff first.
    ///
    /// It is the reason to use this product: no other tool shows a developer
    /// the exact rows before they reach a store. It used to sit under an error
    /// card, a bar of three counters, and a list of findings, which is to say
    /// at the bottom of a scroll. The counters describe the diff, so they now
    /// read after it, and the findings sit against the button they block.
    private func theDiff(_ plan: PlanResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !state.planReadFailures.isEmpty { readFailure(state.planReadFailures) }
            columns(plan)
            counters(plan)
            if !shownFindings(plan).isEmpty { validations(plan) }
            applyRow(plan)
        }
    }

    /// The message already opens with the name of the store that failed, so
    /// the banner adds no sentence of its own. "A store could not be read"
    /// in front of "App Store: …" reads as two stores to anyone who
    /// connected one.
    ///
    /// One row per store. Joined into a paragraph, two failures repeated the
    /// same twelve words — "Check the key file, the key id, and the issuer id
    /// on the Stores tab" — and the reader had to find the second sentence
    /// inside the first. The pill says the state once, at the top, because it
    /// is the same state for every row.
    private func readFailure(_ messages: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                StatePill(text: "Read failed", foreground: Theme.red, background: Theme.redBg)
                Spacer(minLength: 8)
                QuietButton(title: "Read again") { Task { await state.readStores() } }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)

            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                if index > 0 { Hairline(color: Theme.red.opacity(0.3)) }
                HStack(alignment: .top, spacing: 9) {
                    Text(message)
                        .font(Theme.font(size: 12))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    QuietButton(title: message.hasPrefix("Provider:")
                                ? "Open Settings" : "Open Stores") {
                        state.fixReadFailure(message)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.red, lineWidth: 1))
    }

    /// The two numbers the whole tab exists to produce.
    ///
    /// They were three counters in a row of grey, inside one card, beside two
    /// hairline dividers. The tab computes a diff across two stores and every
    /// figure it arrives at was set in the quietest tier the app has.
    ///
    /// Two cards and not three. The byte count is not an event, it is the size
    /// of one, so it reads as the second line of the uploads card instead of
    /// standing beside it as an equal.
    private func counters(_ plan: PlanResult) -> some View {
        HStack(spacing: 12) {
            StatCard(symbol: "square.and.pencil",
                     value: "\(plan.writeCount)", label: "writes",
                     tint: Theme.accent, badge: Theme.accentFill)
            StatCard(symbol: "arrow.up.circle.fill",
                     value: "\(plan.uploadCount)", label: "uploads",
                     detail: plan.uploadCount == 0 ? nil : plan.uploadSizeText,
                     tint: Theme.teal, badge: Theme.tealFill)
            // The apply row below already says where this ends. Saying it
            // twice on one screen is what made the page long.
            Text("Ends in a draft. Nothing reaches a customer.")
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text2)
                .padding(.leading, 4)
            Spacer(minLength: 0)
        }
    }

    /// The panel takes the colour of the loudest thing in it, and a hold is not
    /// loud. A box that is red because a version is in review says the
    /// developer broke something, on the one screen whose job is to say what is
    /// true. Red for an error, yellow for a warning, and the plain card for a
    /// hold on its own.
    /// The rows the card draws, which is not every finding.
    ///
    /// The banner at the top of this tab already carries Apple's answer, in
    /// more words and with the two ways forward attached. Repeating it as a row
    /// underneath said the same sentence twice on one screen, which is the
    /// habit this whole pass is undoing. The finding itself stays in the plan:
    /// it is what blocks the apply, and the note under the button reads it.
    private func shownFindings(_ plan: PlanResult) -> [Finding] {
        guard state.reviewOutcome != nil else { return plan.findings }
        return plan.findings.filter { $0.id != Validator.appleVersionFindingID }
    }

    private func validations(_ plan: PlanResult) -> some View {
        let shown = shownFindings(plan)
        let errors = shown.contains { $0.severity == .error }
        let warnings = shown.contains { $0.severity == .warning }
        let accent = errors ? Theme.red : (warnings ? Theme.yellow : Theme.sep)
        let fill = errors ? Theme.redBg : (warnings ? Theme.yellowBg : Theme.raised)
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(headline(shown))
                    .font(Theme.font(size: 12.5, weight: .semibold))
                    .foregroundStyle(errors ? Theme.red
                                     : (warnings ? Theme.yellow : Theme.text))
                Text(subhead(shown))
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)

            ForEach(shown) { finding in
                ValidationRow(finding: finding)
            }
        }
        .background(fill, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(accent, lineWidth: errors || warnings ? 1 : Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func headline(_ shown: [Finding]) -> String {
        let errors = shown.filter { $0.severity == .error }.count
        let warnings = shown.filter { $0.severity == .warning }.count
        let held = shown.filter { $0.severity == .held }.count
        var pieces: [String] = []
        if errors > 0 { pieces.append("\(errors) \(errors == 1 ? "error" : "errors")") }
        if warnings > 0 { pieces.append("\(warnings) \(warnings == 1 ? "warning" : "warnings")") }
        // "1 held" reads as a count of nothing. The store is the subject here,
        // because the store is what everybody is waiting for.
        if held > 0 { pieces.append(held == 1 ? "1 on hold" : "\(held) on hold") }
        return pieces.joined(separator: ", ")
    }

    /// One sentence, and only where it adds something the rows do not.
    ///
    /// A warning carries its own "Acknowledge", which says the rest. A hold has
    /// no control at all, so it is the case that has to say out loud that
    /// nothing is broken: the apply button is off and the reason is not the
    /// developer's doing.
    private func subhead(_ shown: [Finding]) -> String {
        if shown.contains(where: { $0.severity == .error }) {
            return "Fix the errors to unlock the apply."
        }
        if shown.contains(where: { $0.severity == .held }) {
            return "Nothing here is wrong. The apply waits for the store to answer."
        }
        return ""
    }

    /// Apple on the left, Google in the middle, the provider on the right.
    /// The order never changes anywhere in the app.
    /// Three columns while they fit, and a wrapping grid when they do not.
    ///
    /// Every line here is monospaced, so a column that gets too narrow does
    /// not reflow gracefully — it wraps mid-identifier and the diff stops
    /// reading as a diff. The grid keeps 320 points under every column and
    /// wraps rather than squeeze.
    ///
    /// `alignment: .top` on the item, or a short column floats to the middle
    /// of the row and the three headers no longer line up. See the Release
    /// checklist for why this is a grid and not `ViewThatFits`.
    private func columns(_ plan: PlanResult) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14,
                                     alignment: .top)],
                  alignment: .leading, spacing: 14) {
            ForEach(plan.systems, id: \.self) { system in column(plan, system) }
        }
    }

    /// One system's rows, behind a chevron.
    ///
    /// Shut on arrival, and every one of them. Forty writes across three
    /// systems is four screens of scrolling between the runway and the apply
    /// button, and the summary in the header — "17 writes · 8 uploads" — is
    /// what a developer reads first anyway. The rows are the detail behind
    /// that number, so they wait to be asked for.
    private func column(_ plan: PlanResult, _ system: PlanSystem) -> some View {
        let steps = plan.steps(for: system)
        let open = openColumns.contains(system)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if open { openColumns.remove(system) } else { openColumns.insert(system) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(Theme.font(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                        .motion(.easeOut(duration: 0.15), value: open)
                    mark(for: system)
                    Text(name(for: system)).font(Theme.font(size: 12.5, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(summary(steps)).font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(open ? "Expanded" : "Collapsed")

            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(step.kind.rawValue)
                                .font(Theme.mono(11.5, weight: .bold))
                                .foregroundStyle(color(step.kind))
                                .frame(width: Theme.scaled(9), alignment: .leading)
                            Text(step.summary)
                                .font(Theme.mono(11.5))
                                .foregroundStyle(color(step.kind))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 5)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The clip is what makes it grow rather than blink: without it the
        // rows arrive at full height inside a card that is still the height
        // of a header. Same rule as the Build folds.
        .clipped()
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .motion(.easeInOut(duration: 0.22), value: open)
    }

    /// The logo of the column. The provider has none, so it takes a glyph.
    @ViewBuilder
    private func mark(for system: PlanSystem) -> some View {
        switch system {
        case .apple: StoreMark(store: .apple, size: 16)
        case .google: StoreMark(store: .google, size: 16)
        case .provider: IconChip(symbol: "arrow.triangle.2.circlepath",
                                 tint: Theme.orange, size: 18)
        }
    }

    private func name(for system: PlanSystem) -> String {
        switch system {
        case .apple: "App Store"
        case .google: "Google Play"
        case .provider: state.provider == .adapty ? "Adapty" : "RevenueCat"
        }
    }

    private func summary(_ steps: [PlanStep]) -> String {
        let uploads = steps.reduce(0) { $0 + $1.uploadCount }
        let writes = steps.filter { !$0.isUpload }.count
        return uploads == 0 ? "\(writes) writes" : "\(writes) writes · \(uploads) uploads"
    }

    /// Three events, three colours, and none of them red.
    ///
    /// `.remove` was red, which broke the one rule the palette has: red says
    /// irreversible and nothing else may use it. A cleared field in a draft is
    /// reversible — the apply writes a draft, and only the Release tab sends
    /// one — so red overstated it by a whole category. `ChangedTag` had already
    /// settled the same question in the same words: orange and not red,
    /// because an edit is not irreversible.
    private func color(_ kind: ChangeKind) -> Color {
        switch kind {
        case .add: Theme.green
        case .change: Theme.yellow
        case .remove: Theme.orange
        }
    }

    /// Prominent, and deliberately not red. It writes a draft, and a draft is
    /// reversible. Red belongs to tab 9 alone.
    private func applyRow(_ plan: PlanResult) -> some View {
        // A locked apply stays pressable and opens the pricing sheet. A dry
        // run is free and never locks.
        let locked = !state.dryRun && !state.can(.storeWrite)
        let blocked = !locked && !state.canApply
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 16) {
                ProminentButton(title: state.dryRun ? "Dry run" : "Apply",
                                enabled: !blocked) {
                    guard state.dryRun || state.requirePaid(.storeWrite, .apply) else { return }
                    guard state.canApply else { return }
                    // A dry run sends nothing, so it asks nothing. A real apply
                    // is the moment the app first touches a live store, and it
                    // is the only place in Publishing where that happens.
                    guard !state.dryRun else { return runNow() }
                    confirmingApply = true
                }
                .disabled(blocked)

                Text(applyNote(plan))
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .frame(maxWidth: 520, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            acknowledgedSummary(plan)
        }
        .confirmationDialog("Write to \(state.storeListText)?",
                            isPresented: $confirmingApply, titleVisibility: .visible) {
            Button("Write the drafts") { runNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmLine(plan))
        }
    }

    /// What the developer waved through, beside the button that acts on it.
    ///
    /// The acknowledged set decided whether the apply could run and then said
    /// nothing more, so the one moment it mattered, the moment before the
    /// write, was the one moment nobody could review it. Folded shut by
    /// default: the count is the answer, and the list is the detail.
    @ViewBuilder
    private func acknowledgedSummary(_ plan: PlanResult) -> some View {
        let accepted = plan.warnings.filter { state.acknowledged.contains($0.id) }
        if !accepted.isEmpty {
            DisclosureGroup(isExpanded: $showingAcknowledged) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(accepted) { finding in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.message)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(finding.location).foregroundStyle(Theme.text3)
                        }
                        .frame(maxWidth: 520, alignment: .leading)
                    }
                }
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text2)
                .padding(.top, 7)
            } label: {
                // Verbatim, so the count keeps its digits in every locale.
                Text(verbatim: "\(accepted.count) \(accepted.count == 1 ? "warning" : "warnings") acknowledged")
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: 560, alignment: .leading)
            .motion(.easeInOut(duration: 0.22), value: showingAcknowledged)
        }
    }

    private func runNow() { state.startRun() }

    private func confirmLine(_ plan: PlanResult) -> String {
        "\(plan.writeCount) writes and \(plan.uploadCount) uploads reach \(state.storeListText) now."
            + "\n\nEach one lands in a draft. Nothing goes to review, and nothing reaches a"
            + " customer, until you send it yourself on the Release tab."
    }

    /// One line, and never a second one. The counters, the warning rows, and
    /// the button already carry what they carry.
    private func applyNote(_ plan: PlanResult) -> String {
        if state.dryRun {
            return "A dry run logs every request and sends none."
        }
        if !state.can(.storeWrite) {
            return "Store writes need paid access. Reading and dry runs stay free."
        }
        if !plan.errors.isEmpty {
            let count = plan.errors.count
            return "\(count) \(count == 1 ? "error blocks" : "errors block") the apply."
        }
        // The hold's own sentence, not a summary of it. It already says which
        // version and which store, and this is the line right under the button
        // it switched off.
        if let hold = plan.held.first {
            return plan.held.count == 1
                ? hold.message
                : "The stores are holding this version. The apply waits until they answer."
        }
        if state.unacknowledgedWarnings > 0 {
            let count = state.unacknowledgedWarnings
            return "Acknowledge \(count == 1 ? "the warning" : "the \(count) warnings") to unlock the apply."
        }
        return "Writes a draft to each store. It sends nothing to review."
    }
}

/// One number from the plan: the word, then a solid glyph badge beside a large
/// figure, on a soft tint of the badge's own hue.
///
/// The tint carries meaning and is not decoration. A write and an upload are
/// two different events — one changes a field, the other sends a file, and the
/// second is the slow half of every apply — so the two take two hues and a
/// developer can tell at a glance which kind of work an apply is mostly made
/// of.
///
/// The badge is a solid fill with a white glyph, and not the `IconChip` wash
/// used elsewhere. A wash of the same hue at 15% on a card of the same hue at
/// 12% is two tones four percent apart, which is the amount of contrast that
/// made the dark-mode card borders disappear. See the `sep` note.
private struct StatCard: View {
    let symbol: String
    let value: String
    let label: String
    /// The size of the upload, under the count of them. Absent when there is
    /// nothing to send, because "0 bytes" is a fact nobody asked for.
    var detail: String?
    /// The display hue, for the card. `badge` is the same hue taken deep
    /// enough to sit under white.
    let tint: Color
    let badge: Color

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(badge)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: symbol)
                    .font(Theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentText))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(Theme.font(size: 22, weight: .semibold))
                    .kerning(-0.44)
                    // Every read of the stores moves these, and proportional
                    // digits shuffled the words underneath when they moved.
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(detail.map { "\(label) · \($0)" } ?? label)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 186, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(tint.opacity(0.30), lineWidth: Theme.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(detail.map { "\(label), \($0)" } ?? label)")
    }
}

/// The tick that dismisses one warning.
///
/// Two places draw it: the validation row, and the review banner for the one
/// warning that row does not draw. One control, so the two can never disagree
/// about what a tick looks like or what it does.
private struct AcknowledgeToggle: View {
    @Environment(AppState.self) private var state
    let id: String

    var body: some View {
        let acked = state.acknowledged.contains(id)
        Button {
            if acked { state.acknowledged.remove(id) }
            else { state.acknowledged.insert(id) }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(acked ? Theme.accent : .clear)
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.sep, lineWidth: 1))
                    .overlay(Text(acked ? "✓" : "")
                        .font(Theme.font(size: 8, weight: .bold)).foregroundStyle(.white))
                // "Acknowledge", not "I accept this". The first person and the
                // word "accept" read as a consent form, and this dismisses a
                // warning. It is also the word the state already uses:
                // `acknowledged`.
                Text("Acknowledge").font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(acked ? "Acknowledged" : "Not acknowledged")
    }
}

/// One step of the runway across the top of the tab.
private struct RunwayEntry: Identifiable {
    let number: Int
    let title: String
    let caption: String
    let tab: Tab?

    var id: Int { number }
}

private struct ValidationRow: View {
    @Environment(AppState.self) private var state
    let finding: Finding

    private var isError: Bool { finding.severity == .error }
    /// Only a warning is waved through. An error is fixed and a hold is
    /// waited out, and neither is dismissed by a tick.
    private var isWarning: Bool { finding.severity == .warning }

    /// The field the fix starts at, where the finding named one.
    ///
    /// "Fix on Details" opened a tab of forty rows at the top. A refusal that
    /// knows which half of the listing Apple objected to can land on the first
    /// box of it, which is the difference between a route and a direction.
    private var jump: FieldEntry? {
        finding.fixAnchor.flatMap { anchor in
            FieldIndex.all.first { $0.id == anchor }
        }
    }

    /// The tab this row would open, unless that is the tab the row is on. A
    /// "Fix on Summary" button under a message on the Summary tab goes
    /// nowhere, and the screen drew one beside every store finding.
    private var destination: Tab? {
        let tab = state.tab(for: finding.fix)
        guard jump != nil || tab != .plan else { return nil }
        return tab
    }

    private var pill: (text: String, foreground: Color, background: Color) {
        switch finding.severity {
        case .error: ("Error", Theme.red, Theme.redBg)
        case .warning: ("Warning", Theme.yellow, Theme.yellowBg)
        // Grey, and the one word that says who is waiting for whom. It is not
        // an amber "almost an error": nothing is wrong.
        case .held: ("Held", Theme.text2, Theme.sunken)
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            StatePill(text: pill.text, foreground: pill.foreground,
                      background: pill.background)
                // Through `Theme.scaled`, because the pill inside it is text.
                // Left at a flat 58 the column held "Error" and cut "Warning"
                // in half, and it will do it again on the next type change.
                .frame(width: Theme.scaled(64), alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.message)
                    .font(Theme.font(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.location).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            if isWarning { AcknowledgeToggle(id: finding.id) }
            if let destination {
                // "Fix" only where there is something to fix. A hold is
                // somebody else's turn, so its button offers the place the
                // work continues rather than promising a repair. The anchor
                // changes where the button lands, never what it says.
                QuietButton(title: isError || isWarning
                            ? "Fix on \(destination.title)"
                            : "Go to \(destination.title)") {
                    if let jump { state.jump(to: jump) } else { state.selectedTab = destination }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(Theme.content)
    }
}

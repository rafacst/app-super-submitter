import SubmitKit
import SwiftUI

/// Tab 7. Every change, before any write. This tab is the safety model of the
/// product, and it is the one screen that can refuse to continue.
struct PlanTab: View {
    @Environment(AppState.self) private var state
    /// Holds the question open while the developer answers it. See applyRow.
    @State private var confirmingApply = false
    /// Shut by default. See acknowledgedSummary.
    @State private var showingAcknowledged = false

    var body: some View {
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

    // MARK: - Before the read

    private var reading: some View {
        HStack(spacing: 11) {
            Spinner()
            Text("Reading both stores. This writes nothing.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
        }
    }

    private var notReadYet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing read yet.").font(.system(size: 15, weight: .semibold))
            Text("The plan reads every store and compares it to these tabs. It opens no Google edit, it creates no Apple resource, and it writes nothing.")
                .font(.system(size: 13))
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
                    .overlay(Text("✓").font(.system(size: 13)).foregroundStyle(Theme.green))
                Text("Nothing to change.")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.17)
            }
            Text("Both stores match what these tabs hold. The last read ran at \(readTime). A second apply would write nothing.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(matchRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Hairline(color: Theme.sep2) }
                    HStack(spacing: 12) {
                        Text(row.system)
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 110, alignment: .leading)
                        Text(row.line).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                        Spacer(minLength: 8)
                        Text("In sync").font(.system(size: 11.5)).foregroundStyle(Theme.green)
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
                        .font(.system(size: 12.5, weight: .medium))
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
            if !plan.findings.isEmpty { validations(plan) }
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
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    // The fix for every one of these is the same tab, and the
                    // message already names it. A row that says where to go
                    // and does not go there makes the reader do the walk.
                    QuietButton(title: "Open Stores") { state.selectedTab = .stores }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.red, lineWidth: 1))
    }

    private func counters(_ plan: PlanResult) -> some View {
        HStack(spacing: 26) {
            Counter(value: "\(plan.writeCount)", label: "writes")
            Rectangle().fill(Theme.sep2).frame(width: 1, height: 28)
            Counter(value: "\(plan.uploadCount)", label: "uploads")
            Rectangle().fill(Theme.sep2).frame(width: 1, height: 28)
            Counter(value: plan.uploadSizeText, label: "to upload")
            Spacer(minLength: 0)
            // The apply row below already says where this ends. Saying it
            // twice on one screen is what made the page long.
            Text("Ends in a draft. Nothing reaches a customer.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private func validations(_ plan: PlanResult) -> some View {
        let blocked = plan.isBlocked
        let accent = blocked ? Theme.red : Theme.yellow
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(headline(plan))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent)
                // Only the blocking case needs a sentence. Every warning row
                // carries its own "Acknowledge", which says the rest.
                if blocked {
                    Text("Fix the errors to unlock the apply.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)

            ForEach(plan.findings) { finding in
                ValidationRow(finding: finding)
            }
        }
        .background(blocked ? Theme.redBg : Theme.yellowBg,
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(accent, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func headline(_ plan: PlanResult) -> String {
        let errors = plan.errors.count
        let warnings = plan.warnings.count
        var pieces: [String] = []
        if errors > 0 { pieces.append("\(errors) \(errors == 1 ? "error" : "errors")") }
        if warnings > 0 { pieces.append("\(warnings) \(warnings == 1 ? "warning" : "warnings")") }
        return pieces.joined(separator: ", ")
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

    private func column(_ plan: PlanResult, _ system: PlanSystem) -> some View {
        let steps = plan.steps(for: system)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                mark(for: system)
                Text(name(for: system)).font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                Text(summary(steps)).font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(step.kind.rawValue)
                            .font(Theme.mono(11.5, weight: .bold))
                            .foregroundStyle(color(step.kind))
                            .frame(width: 9, alignment: .leading)
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
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

    private func color(_ kind: ChangeKind) -> Color {
        switch kind {
        case .add: Theme.green
        case .change: Theme.yellow
        case .remove: Theme.red
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
                    .font(.system(size: 12))
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
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .padding(.top, 7)
            } label: {
                // Verbatim, so the count keeps its digits in every locale.
                Text(verbatim: "\(accepted.count) \(accepted.count == 1 ? "warning" : "warnings") acknowledged")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: 560, alignment: .leading)
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
        if plan.isBlocked {
            let count = plan.errors.count
            return "\(count) \(count == 1 ? "error blocks" : "errors block") the apply."
        }
        if state.unacknowledgedWarnings > 0 {
            let count = state.unacknowledgedWarnings
            return "Acknowledge \(count == 1 ? "the warning" : "the \(count) warnings") to unlock the apply."
        }
        return "Writes a draft to each store. It sends nothing to review."
    }
}

private struct Counter: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold)).kerning(-0.34)
                // The three counters sit in a row and each read moves them.
                // Proportional digits made the labels underneath shuffle.
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
        }
    }
}

private struct ValidationRow: View {
    @Environment(AppState.self) private var state
    let finding: Finding

    private var isError: Bool { finding.severity == .error }

    var body: some View {
        HStack(spacing: 11) {
            StatePill(text: isError ? "Error" : "Warning",
                      foreground: isError ? Theme.red : Theme.yellow,
                      background: isError ? Theme.redBg : Theme.yellowBg)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.message)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.location).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            if !isError {
                let acked = state.acknowledged.contains(finding.id)
                Button {
                    if acked { state.acknowledged.remove(finding.id) }
                    else { state.acknowledged.insert(finding.id) }
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(acked ? Theme.accent : .clear)
                            .frame(width: 14, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.sep, lineWidth: 1))
                            .overlay(Text(acked ? "✓" : "")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                        // "Acknowledge", not "I accept this". The first person
                        // and the word "accept" read as a consent form, and
                        // this dismisses a warning. It is also the word the
                        // state already uses: `acknowledged`.
                        Text("Acknowledge").font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(acked ? "Acknowledged" : "Not acknowledged")
            }
            QuietButton(title: "Fix on \(state.tab(for: finding.fix).title)") {
                state.selectedTab = state.tab(for: finding.fix)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(Theme.content)
    }
}

import SubmitKit
import SwiftUI

/// Tab 7. Every change, before any write. This tab is the safety model of the
/// product, and it is the one screen that can refuse to continue.
struct PlanTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.planReading {
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
            // Opening the tab is the whole request. It used to read only when
            // no plan existed at all, so a developer who edited a field and
            // came back read a diff against the stores as they were an hour
            // ago. A read writes nothing and costs nothing, and a stale plan
            // is the one thing this screen may not show.
            guard !state.planReading, !state.stores.isEmpty else { return }
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

    private func theDiff(_ plan: PlanResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let planError = state.planError { readFailure(planError) }
            counters(plan)
            if !plan.findings.isEmpty { validations(plan) }
            columns(plan)
            applyRow(plan)
        }
    }

    /// The message already opens with the name of the store that failed, so
    /// the banner adds no sentence of its own. "A store could not be read"
    /// in front of "App Store: …" reads as two stores to anyone who
    /// connected one.
    private func readFailure(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            StatePill(text: "Read failed", foreground: Theme.red, background: Theme.redBg)
            Text(message)
                .font(.system(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            QuietButton(title: "Read again") { Task { await state.readStores() } }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
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
                // carries its own "I accept this", which says the rest.
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
    private func columns(_ plan: PlanResult) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(plan.systems, id: \.self) { system in
                let steps = plan.steps(for: system)
                VStack(alignment: .leading, spacing: 0) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }
        }
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
        return HStack(alignment: .center, spacing: 16) {
            Button {
                guard state.dryRun || state.requirePaid(.storeWrite, .apply) else { return }
                guard state.canApply else { return }
                state.selectedTab = .submit
                state.startRun()
            } label: {
                Text(state.dryRun ? "Dry run" : "Apply")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(blocked ? Theme.text3 : Theme.accentText)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .background(blocked ? Theme.sep2 : Theme.accent,
                                in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(blocked)

            Text(applyNote(plan))
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
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
            return "Accept \(count == 1 ? "the warning" : "the \(count) warnings") to unlock the apply."
        }
        return "Writes a draft to each store. It sends nothing to review."
    }
}

private struct Counter: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 17, weight: .semibold)).kerning(-0.34)
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
                        Text("I accept this").font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(acked ? "Accepted" : "Not accepted")
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

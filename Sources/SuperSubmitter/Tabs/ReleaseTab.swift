import SubmitKit
import SwiftUI

/// Tab 9. The checklist, the status, then the two irreversible buttons.
///
/// The order on the screen is the order of the work. The checklist sits
/// between the draft and the review, and that placement is the point.
struct ReleaseTab: View {
    @Environment(AppState.self) private var state
    @State private var undoing: Store?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if state.consoleRows.isEmpty {
                notReadYet
            } else {
                checklist
            }
            status
            if state.stores.contains(.apple) { appleReleaseControls }
            if let error = state.releaseError { failure(error) }
            sendToReview
            // A review to answer, a crash rate to read, and a recovery to
            // deploy all belong to a live app, so they moved to Managing.
        }
        .task(id: state.manifestURL) {
            guard state.consoleRows.isEmpty, !state.stores.isEmpty else { return }
            state.loadConsoleMarks()
        }
        .confirmationDialog(undoQuestion, isPresented: $undoing.isPresent, presenting: undoing) { store in
            Button(store == .apple ? "Cancel the submission" : "Halt the rollout",
                   role: .destructive) {
                Task { await state.undoRelease(store) }
            }
            Button("Keep it", role: .cancel) {}
        } message: { store in
            Text(store == .apple
                ? "The App Store loses its place in the review queue. A new submission starts at the back of it."
                : "Google stops new installs of this rollout. Every device that already has the build keeps it.")
        }
    }

    private var undoQuestion: String {
        undoing == .apple ? "Cancel the App Store submission?" : "Halt the Google Play rollout?"
    }

    private var appleReleaseControls: some View {
        HStack(spacing: 14) {
            Picker("App Store release", selection: state.appleReleaseTypeBinding()) {
                Text("Manual").tag(Manifest.Release.ReleaseType.manual)
                Text("After approval").tag(Manifest.Release.ReleaseType.afterApproval)
                Text("Scheduled").tag(Manifest.Release.ReleaseType.scheduled)
            }
            .frame(width: 260)
            Toggle("Phased release", isOn: state.applePhasedReleaseBinding())
            if state.manifest.release?.apple?.phasedRelease == true {
                Picker("State", selection: state.applePhasedStateBinding()) {
                    Text("Active").tag(Manifest.Release.PhasedReleaseState.active)
                    Text("Paused").tag(Manifest.Release.PhasedReleaseState.paused)
                }
                .frame(width: 180)
            }
            Spacer()
        }
        .font(.system(size: 12))
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - The checklist

    private var cards: [(name: String, rows: [ConsoleRow])] {
        var result: [(String, [ConsoleRow])] = []
        for system in ["App Store", "Google Play", "RevenueCat", "Adapty"] {
            let rows = state.consoleRows.filter { $0.system == system }
            guard !rows.isEmpty else { continue }
            result.append((system, rows))
        }
        return result
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Verbatim and monospaced, for the reason the Summary counters
            // are: a localized "\(int)" carries the locale's grouping
            // separator, and proportional digits shuffle the words after them
            // every time a step is ticked.
            Text(verbatim: "\(state.consoleDone) of \(state.consoleRows.count) steps are done")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("Every row below happens in a console. No API performs it.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
    }

    private var notReadYet: some View {
        HStack(spacing: 11) {
            Text("The checklist needs one read of the stores.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
            QuietButton(title: "Read the stores") { Task { await state.recheck() } }
            Spacer(minLength: 0)
        }
        .storePanel(padding: 12, horizontal: 15)
    }

    private var checklist: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(cards, id: \.name) { card in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        SystemMark(name: card.name)
                        Text(card.name).font(.system(size: 12.5, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(verbatim: "\(card.rows.filter { state.markedState($0) == .done }.count) of \(card.rows.count)")
                            .font(.system(size: 11)).foregroundStyle(Theme.text2)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    ForEach(card.rows) { row in
                        Hairline(color: Theme.sep2)
                        ChecklistRow(row: row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }
        }
    }

    // MARK: - The status

    private var status: some View {
        HStack(spacing: 14) {
            ForEach(Store.allCases.filter { state.stores.contains($0) }) { store in
                StatusCard(status: state.statuses[store]
                    ?? StoreStatus(store: store, phase: .noDraft,
                                   detail: state.detail(for: store)))
            }
        }
    }

    private func failure(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            StatePill(text: "Failed", foreground: Theme.red, background: Theme.redBg)
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Text("The other store is untouched. This app never chained the two.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.red, lineWidth: 1))
    }

    // MARK: - The two buttons

    private var sendToReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("Send to review").font(.system(size: 14, weight: .semibold))
                Text("One button per store. These two are the only irreversible actions in this app.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 0) {
                if state.stores.contains(.apple) {
                    column(.apple)
                }
                if state.stores.count == 2 {
                    Rectangle().fill(Theme.sep).frame(width: 1).padding(.horizontal, 18)
                }
                if state.stores.contains(.google) {
                    column(.google)
                }
            }
        }
    }

    private func column(_ store: Store) -> some View {
        let released = store == .apple ? state.appleReleased : state.googleReleased
        let blockers = state.releaseBlockers(for: store)
        // A locked button stays pressable and opens the pricing sheet. A
        // disabled button with no explanation is the worst of both.
        let locked = !released && !state.can(.storeRelease)
        let blocked = !locked && !released && (!state.applied || !blockers.isEmpty)
        let name = store == .apple ? "App Store" : "Google Play"
        let approvedApple = store == .apple
            && state.actualState.apple?.versionState == "PENDING_DEVELOPER_RELEASE"
        let other = store == .apple ? "Google Play" : "The App Store"
        return ReleaseColumn(
            store: store,
            lines: lines(store),
            label: released ? "Sent to \(name) review"
                : approvedApple ? "Release the approved App Store version"
                : "Send to \(name) review",
            done: released,
            blocked: blocked,
            hint: hint(store, released: released, blockers: blockers, other: other),
            hintColor: blocked && !released ? Theme.yellow : Theme.text2,
            undoTitle: state.canUndoRelease(store)
                ? (store == .apple ? "Cancel the submission" : "Halt the rollout")
                : nil,
            undo: { undoing = store }
        ) {
            // The confirmation names an irreversible action. Opening it for
            // somebody who cannot perform it wastes the one screen that has to
            // be read carefully.
            guard state.requirePaid(.storeRelease, .release) else { return }
            state.releaseSheet = store
        }
    }

    private func lines(_ store: Store) -> String {
        let version = state.manifest.release?.versionName ?? "no version"
        switch store {
        case .apple:
            let release = state.manifest.release?.apple?.releaseType?.rawValue ?? "MANUAL"
            let phased = state.manifest.release?.apple?.phasedRelease == true
                ? ", phased over 7 days" : ""
            return "App Store · version \(version)\n\(Self.appleRelease(release))\(phased)."
        case .google:
            let track = state.manifest.googlePrimaryTrack
            let status = state.manifest.release?.google?.status ?? "completed"
            return "Google Play · version \(version)\n\(track) track, \(Self.googleRelease(status))."
        }
    }

    private func hint(_ store: Store, released: Bool, blockers: [ConsoleRow],
                      other: String) -> String {
        if !released, !state.can(.storeRelease) {
            return "Releasing to review needs paid access. Your draft stays as it is."
        }
        if released {
            return store == .apple
                ? "You can cancel this submission only before the review starts."
                : "You can halt a staged rollout only. A completed rollout cannot be halted."
        }
        if !state.applied {
            return "Blocked: no draft exists yet. Run an apply on the Summary tab first."
        }
        if let first = blockers.first {
            return "Blocked: \(first.title.lowercased()) is not done. Finish it in the console, then press Re-check."
        }
        return "This sends \(store == .apple ? "the App Store" : "Google Play") and nothing else. \(other) stays a draft."
    }

    static func appleRelease(_ value: String) -> String {
        switch value {
        case "AFTER_APPROVAL": "Release after approval"
        case "SCHEDULED": "Release on a date"
        default: "Release manually"
        }
    }

    static func googleRelease(_ value: String) -> String {
        switch value {
        case "inProgress": "staged rollout"
        case "draft": "draft"
        case "halted": "halted"
        default: "completed rollout"
        }
    }
}

private struct ChecklistRow: View {
    @Environment(AppState.self) private var state
    let row: ConsoleRow

    var body: some View {
        let shown = state.markedState(row)
        return HStack(alignment: .top, spacing: 10) {
            // Only an Unknown row takes a hand-made mark. No API can read it,
            // so the developer is the only source.
            //
            // The other rows keep an empty column, and an empty column is a
            // rule you cannot see: two rows side by side, one tickable and one
            // not, with nothing to say why. They now carry the reason. A tick
            // box on an API-read row would be worse than missing — it would
            // let the developer mark a step done that the store says is not,
            // on the one screen in the app that may never overstate a state.
            Group {
                if row.state == .unknown {
                    let marked = state.consoleMarks.contains(row.id)
                    Button {
                        state.toggleConsoleMark(row.id)
                    } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(marked ? Theme.accent : .clear)
                            .frame(width: 14, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.controlEdge, lineWidth: 1))
                            .overlay(Text(marked ? "✓" : "")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(marked ? "Confirmed" : "Not confirmed")
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 14, height: 14)
                        .help("The store reports this one. There is nothing to tick.")
                        .accessibilityLabel("Reported by the store")
                }
            }
            .frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.reason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                if shown != .done {
                    Button { state.open(row.link) } label: {
                        Text("Open ↗").font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(row.title)")
                }
            }
            Spacer(minLength: 6)
            StatePill(text: shown.label, foreground: ReleaseTab.color(shown),
                      background: ReleaseTab.background(shown))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension ReleaseTab {
    static func color(_ state: ConsoleState) -> Color {
        switch state {
        case .done: Theme.green
        case .needed: Theme.yellow
        case .unknown: Theme.text2
        case .notApplicable: Theme.text3
        }
    }

    static func background(_ state: ConsoleState) -> Color {
        switch state {
        case .done: Theme.greenBg
        case .needed: Theme.yellowBg
        case .unknown: Theme.sep2
        case .notApplicable: .clear
        }
    }
}

private struct StatusCard: View {
    let status: StoreStatus

    var body: some View {
        HStack(spacing: 11) {
            StoreMark(store: status.store, size: 20)

            // A round dot is a draft. A square dot is in a queue. The two
            // read apart with no colour.
            Group {
                if status.phase.isReleased {
                    RoundedRectangle(cornerRadius: 1).fill(Theme.yellow)
                } else {
                    Circle().fill(Theme.text3)
                }
            }
            .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.storeName).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(status.phase.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.phase.isReleased ? Theme.yellow : Theme.text)
        }
        .storePanel(padding: 12, horizontal: 15)
    }

    private var detail: String {
        guard let checked = status.checkedAt else { return status.detail }
        return "\(status.detail) · checked \(checked.formatted(date: .omitted, time: .shortened))"
    }
}

/// One of the two red buttons, with the text above it and the recovery below.
private struct ReleaseColumn: View {
    let store: Store
    let lines: String
    let label: String
    let done: Bool
    let blocked: Bool
    let hint: String
    let hintColor: Color
    /// The take-back. It appears only while the store still accepts one, so a
    /// missing title is the normal case and not an error.
    var undoTitle: String?
    var undo: () -> Void = {}
    let action: () -> Void

    private var inactive: Bool { done || blocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StoreLabel(store: store, size: 12.5)
            Text(lines)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text(label)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(inactive ? Theme.text3 : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(inactive ? Theme.sep2 : Theme.redFill,
                                in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(inactive ? Theme.sep : Theme.redFill, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(inactive)

            Text(hint)
                .font(.system(size: 11.5))
                .foregroundStyle(hintColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let undoTitle {
                QuietButton(title: undoTitle, action: undo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The logo for a checklist card. The two providers carry no logo, so they take
/// the glyph the Monetization tab already uses for a mirror.
private struct SystemMark: View {
    let name: String

    var body: some View {
        switch name {
        case "App Store": StoreMark(store: .apple, size: 16)
        case "Google Play": StoreMark(store: .google, size: 16)
        default: IconChip(symbol: "arrow.triangle.2.circlepath", tint: Theme.orange, size: 18)
        }
    }
}

import SubmitKit
import SwiftUI

/// Tab 9. The checklist, the status, then the two irreversible buttons.
///
/// The order on the screen is the order of the work. The checklist sits
/// between the draft and the review, and that placement is the point.
struct ReleaseTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            checklist
            status
            sendToReview
        }
    }

    // MARK: - The checklist

    private var cards: [(name: String, rows: [DemoCheckRow])] {
        var result: [(String, [DemoCheckRow])] = [
            ("App Store", DemoData.appleChecklist),
            ("Google Play", googleRows),
        ]
        if state.hasProvider {
            result.append((state.provider == .adapty ? "Adapty" : "RevenueCat",
                           DemoData.providerChecklist))
        }
        return result
    }

    /// The content rating turns Done after a re-check. It is the row that
    /// blocks the Google button, so it must be able to change.
    private var googleRows: [DemoCheckRow] {
        DemoData.googleChecklist.map { row in
            guard row.id == "g1", state.rechecked else { return row }
            return DemoCheckRow(row.id, row.title, row.reason, .done)
        }
    }

    private func effectiveState(_ row: DemoCheckRow) -> CheckState {
        if row.state == .unknown, state.checked.contains(row.id) { return .done }
        return row.state
    }

    private var doneCount: (done: Int, total: Int) {
        let all = cards.flatMap(\.rows)
        return (all.filter { effectiveState($0) == .done }.count, all.count)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(doneCount.done) of \(doneCount.total) steps are done")
                .font(.system(size: 14, weight: .semibold))
            Text("Every row below happens in a console. No API performs it.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
    }

    private var checklist: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(cards, id: \.name) { card in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.name).font(.system(size: 12.5, weight: .semibold))
                        Spacer(minLength: 8)
                        Text("\(card.rows.filter { effectiveState($0) == .done }.count) of \(card.rows.count)")
                            .font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    ForEach(card.rows) { row in
                        Hairline(color: Theme.sep2)
                        ChecklistRow(row: row, state_: effectiveState(row))
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
            StatusCard(store: "App Store", detail: "Version 3.2.0 · build 412",
                       released: state.appleReleased, applied: state.applied)
            StatusCard(store: "Google Play", detail: "Version 3.2.0 · version code 412 · production",
                       released: state.googleReleased, applied: state.applied)
        }
    }

    // MARK: - The two buttons

    private var googleBlocked: Bool { !state.rechecked && !state.checked.contains("g1") }

    private var sendToReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("Send to review").font(.system(size: 14, weight: .semibold))
                Text("One button per store. These two are the only irreversible actions in this app.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 0) {
                ReleaseColumn(
                    lines: "App Store · version 3.2.0, build 412\nRelease after approval, phased over 7 days.",
                    label: state.appleReleased ? "Sent to App Store review" : "Send to App Store review",
                    done: state.appleReleased,
                    blocked: false,
                    hint: state.appleReleased
                        ? "Sent at 14:11. You can cancel this submission only before the review starts."
                        : "This sends the App Store and nothing else. Google Play stays a draft.",
                    hintColor: Theme.text2
                ) { state.releaseSheet = .apple }

                Rectangle().fill(Theme.sep).frame(width: 1).padding(.horizontal, 18)

                ReleaseColumn(
                    lines: "Google Play · version 3.2.0, version code 412\nProduction track, completed rollout.",
                    label: state.googleReleased ? "Sent to Google Play review" : "Send to Google Play review",
                    done: state.googleReleased,
                    blocked: googleBlocked,
                    hint: state.googleReleased
                        ? "Sent at 14:12. You can halt a staged rollout only. A completed rollout cannot be halted."
                        : googleBlocked
                            ? "Blocked: the content rating (IARC) is not done. Finish it in the Play Console, then press Re-check."
                            : "This sends Google Play and nothing else. The App Store is untouched.",
                    hintColor: googleBlocked && !state.googleReleased ? Theme.yellow : Theme.text2
                ) { state.releaseSheet = .google }
            }
        }
    }
}

private struct ChecklistRow: View {
    @Environment(AppState.self) private var state
    let row: DemoCheckRow
    let state_: CheckState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Only an Unknown row takes a hand-made mark. No API can read it,
            // so the developer is the only source.
            Group {
                if row.state == .unknown {
                    let marked = state.checked.contains(row.id)
                    Button {
                        if marked { state.checked.remove(row.id) }
                        else { state.checked.insert(row.id) }
                    } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(marked ? Theme.accent : .clear)
                            .frame(width: 14, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.sep, lineWidth: 1))
                            .overlay(Text(marked ? "✓" : "")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(marked ? "Confirmed" : "Not confirmed")
                } else {
                    Color.clear.frame(width: 14, height: 14)
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
                if state_ != .done {
                    Text("Open ↗").font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 6)
            StatePill(text: state_.label, foreground: state_.color, background: state_.background)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StatusCard: View {
    let store: String
    let detail: String
    let released: Bool
    let applied: Bool

    private var label: String {
        if released { "Waiting for review" }
        else if applied { "Draft, ready to release" }
        else { "No draft yet" }
    }

    var body: some View {
        HStack(spacing: 11) {
            // A round dot is a draft. A square dot is in a queue. The two
            // read apart with no colour.
            Group {
                if released {
                    RoundedRectangle(cornerRadius: 1).fill(Theme.yellow)
                } else {
                    Circle().fill(Theme.text3)
                }
            }
            .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(store).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(released ? Theme.yellow : Theme.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

/// One of the two red buttons, with the text above it and the recovery below.
private struct ReleaseColumn: View {
    let lines: String
    let label: String
    let done: Bool
    let blocked: Bool
    let hint: String
    let hintColor: Color
    let action: () -> Void

    private var inactive: Bool { done || blocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

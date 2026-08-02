import SwiftUI

/// Tab 7. Every change, before any write. This tab is the safety model of the
/// product, and it is the one screen that can refuse to continue.
struct PlanTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.applied {
            nothingToChange
        } else {
            theDiff
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
            Text("Both stores match what these tabs hold. The last read ran at 14:02. A second apply would write nothing.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(DemoData.matchRows.enumerated()), id: \.offset) { index, row in
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
                QuietButton(title: "Read the stores again")
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

    // MARK: - The diff

    private var theDiff: some View {
        VStack(alignment: .leading, spacing: 18) {
            counters
            validations
            columns
            applyRow
        }
    }

    private var counters: some View {
        HStack(spacing: 26) {
            Counter(value: "24", label: "writes")
            Rectangle().fill(Theme.sep2).frame(width: 1, height: 28)
            Counter(value: "13", label: "uploads")
            Rectangle().fill(Theme.sep2).frame(width: 1, height: 28)
            Counter(value: "142.6 MB", label: "to upload")
            Spacer(minLength: 0)
            Text("This plan writes nothing to a customer. It ends with a draft in each store.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .frame(maxWidth: 300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var validations: some View {
        let blocked = state.planIsBlocked
        let accent = blocked ? Theme.red : Theme.yellow
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(blocked ? "1 error, 2 warnings" : "2 warnings")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent)
                Text(blocked
                     ? "An error blocks the apply. A warning needs one acknowledgement."
                     : "A warning needs one acknowledgement. Nothing blocks the apply.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)

            if blocked {
                ValidationRow(
                    kind: "Error", color: Theme.red, background: Theme.redBg,
                    text: "Keywords are 104 characters. The limit is 100.",
                    where_: "App Store · Details · en-US · Keywords",
                    button: "Fix on Details", ackKey: nil) { state.selectedTab = .details }
            }
            ValidationRow(
                kind: "Warning", color: Theme.yellow, background: Theme.yellowBg,
                text: "The version name differs between the two packages.",
                where_: "Build · 3.2.0 and 3.2.0-rc4",
                button: "Fix on Build", ackKey: "w1") { state.selectedTab = .build }
            ValidationRow(
                kind: "Warning", color: Theme.yellow, background: Theme.yellowBg,
                text: "pt-BR has screenshots for the App Store and none for Google Play.",
                where_: "Media · pt-BR · phone",
                button: "Fix on Media", ackKey: "w2") { state.selectedTab = .media }
        }
        .background(blocked ? Theme.redBg : Theme.yellowBg,
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(accent, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    /// Apple on the left, Google in the middle, the provider on the right.
    /// The order never changes anywhere in the app.
    private var columns: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(state.hasProvider ? DemoData.diffColumns : Array(DemoData.diffColumns.prefix(2))) { column in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(column.name).font(.system(size: 12.5, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(column.summary).font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(column.rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.sign.rawValue)
                                    .font(Theme.mono(11.5, weight: .bold))
                                    .foregroundStyle(row.sign.color)
                                    .frame(width: 9, alignment: .leading)
                                Text(row.text)
                                    .font(Theme.mono(11.5))
                                    .foregroundStyle(row.sign.color)
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

    /// Prominent, and deliberately not red. It writes a draft, and a draft is
    /// reversible. Red belongs to tab 9 alone.
    private var applyRow: some View {
        let blocked = state.planIsBlocked
        return HStack(alignment: .center, spacing: 16) {
            Button {
                guard !blocked else { return }
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

            Text(applyNote)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var applyNote: String {
        if state.dryRun {
            "A dry run logs every request and sends none. Nothing reaches a store."
        } else if state.planIsBlocked {
            "1 error blocks the apply. Fix the keywords on Details, then this button writes a draft to each store."
        } else {
            "This writes 24 changes and 13 uploads. It ends with a draft in each store. It sends nothing to review."
        }
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
    let kind: String
    let color: Color
    let background: Color
    let text: String
    let where_: String
    let button: String
    let ackKey: String?
    let fix: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            StatePill(text: kind, foreground: color, background: background)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 12.5))
                Text(where_).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            if let ackKey {
                let acked = state.acknowledged.contains(ackKey)
                Button {
                    if acked { state.acknowledged.remove(ackKey) }
                    else { state.acknowledged.insert(ackKey) }
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
            QuietButton(title: button, action: fix)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(Theme.content)
    }
}

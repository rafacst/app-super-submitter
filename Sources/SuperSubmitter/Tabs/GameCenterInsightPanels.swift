import Charts
import SubmitKit
import SwiftUI

/// The two Gaming panels that are not a desired state.
///
/// Everything else on this tab describes what the game should hold and reaches
/// the store through the plan. These two answer a question instead: **how is
/// matchmaking doing**, and **does this leaderboard format a score the way my
/// game expects**. Neither one is a manifest value and neither ever appears in
/// a plan.

/// Panel 9. The ten metric series Apple publishes for matchmaking.
///
/// It stores nothing. The table lives while it is on screen, and the next read
/// asks Apple again, which is the rule every metric in this app follows.
///
/// The panel is behind its own button and says what it costs before it starts,
/// the same way the sales trend does. One request per press, and the developer
/// picks which series.
struct GameCenterMetricsPanel: View {
    @Environment(AppState.self) private var state
    @State private var metric: AppleGameCenterMatchmakingClient.Metric = .queueSizes
    @State private var target = ""
    @State private var table = ReportTable()
    @State private var reading = false

    private var targets: [StoreValues.Choice] {
        state.gameCenterMetricTargets(metric.owner)
    }

    /// The one this run would ask about: what the developer picked, or the
    /// first one there is.
    private var chosenTarget: String? {
        if targets.contains(where: { $0.id == target }) { return target }
        return targets.first?.id
    }

    var body: some View {
        Section_("Matchmaking metrics", icon: "chart.xyaxis.line", tint: Theme.accent,
                 anchor: "gaming.metrics", folds: true, startsOpen: false,
                 note: "How matchmaking is doing. Read on a button, and kept nowhere.") {
            VStack(alignment: .leading, spacing: 11) {
                FieldRow {
                    LabeledField("Series", width: 280) {
                        Menu(metric.label) {
                            ForEach(AppleGameCenterMatchmakingClient.Metric.allCases) { row in
                                Button(row.label) { metric = row }
                            }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }
                    LabeledField(ownerLabel, width: 240) {
                        if targets.isEmpty {
                            Text(emptyTargets)
                                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ChoiceField(value: Binding(get: { chosenTarget ?? "" },
                                                       set: { target = $0 }),
                                        choices: targets, allowsNone: false)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button(reading ? "Reading…" : "Read this series") { read() }
                        .controlSize(.small)
                        .disabled(reading || chosenTarget == nil)
                    if reading { Spinner() }
                    Text("One request, in fifteen minute windows. Nothing is saved: closing this panel drops what it drew.")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if !table.isEmpty {
                    Divider().overlay(Theme.sep)
                    GameCenterMetricChart(table: table)
                    GameCenterMetricTable(table: table)
                } else if !reading, state.gamingActionMessage.isEmpty {
                    Text("Apple answers with the window it has. A queue nobody has waited in reads as nothing at all, and that is an answer.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .storePanel(padding: 14)
        }
    }

    /// What the id in the path belongs to. Apple hangs these ten off three
    /// different resources, and the panel asks for the right one rather than
    /// offering every id it holds.
    private var ownerLabel: String {
        switch metric.owner {
        case .detail: "For"
        case .queue: "Queue"
        case .rule: "Rule"
        }
    }

    private var emptyTargets: String {
        switch metric.owner {
        case .detail: "Read the stores first."
        case .queue: "App Store Connect holds no queue for this account yet."
        case .rule: "App Store Connect holds no matchmaking rule yet."
        }
    }

    private func read() {
        guard let id = chosenTarget else { return }
        reading = true
        table = ReportTable()
        Task {
            table = await state.readGameCenterMetric(metric, id: id)
            reading = false
        }
    }
}

/// The header and the first rows of a metric series.
///
/// A whole series belongs in a spreadsheet and not in a window, so this prints
/// the top of it under the chart, the same way the Reports panel does.
struct GameCenterMetricTable: View {
    let table: ReportTable

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(([table.columns] + table.rows.prefix(11)).enumerated()),
                        id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(Theme.mono(10))
                                .foregroundStyle(index == 0 ? Theme.text2 : Theme.text3)
                                .frame(width: Theme.scaled(112), alignment: .leading)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 200)
    }
}

private struct GameCenterMetricChart: View {
    let table: ReportTable
    @State private var measure: Int?

    private var measures: [Int] {
        table.columns.indices.filter { index in
            let values = table.values(at: index).filter { !$0.isEmpty }
            return !values.isEmpty && values.allSatisfy { Double($0) != nil }
        }
    }
    private var chosenMeasure: Int? { measure ?? measures.first }
    private var group: Int? { table.labelColumns.first }

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let series: String
        var id: String { "\(date.timeIntervalSinceReferenceDate)-\(series)" }
    }

    private var points: [Point] {
        guard let dateColumn = table.columns.firstIndex(of: "Date"),
              let measure = chosenMeasure else { return [] }
        return table.rows.compactMap { row in
            guard row.indices.contains(dateColumn), row.indices.contains(measure),
                  let date = try? Date(row[dateColumn], strategy: .iso8601),
                  let value = Double(row[measure]) else { return nil }
            let series = group.flatMap { row.indices.contains($0) ? row[$0] : nil }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? table.columns[measure]
            return Point(date: date, value: value, series: series)
        }
    }

    var body: some View {
        if let measure = chosenMeasure, !points.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if measures.count > 1 {
                    Menu(table.columns[measure]) {
                        ForEach(measures, id: \.self) { index in
                            Button(table.columns[index]) { self.measure = index }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                Chart(points) { point in
                    LineMark(x: .value("Time", point.date),
                             y: .value(table.columns[measure], point.value))
                        .foregroundStyle(by: .value("Series", point.series))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(Theme.sep)
                        AxisValueLabel(format: .dateTime.month().day().hour().minute())
                    }
                }
                .frame(height: 110)
                .accessibilityLabel("\(table.columns[measure]) over \(points.count) fifteen minute windows")
            }
        }
    }
}

/// Panel 10. Three calls that write, and none of them writes a catalog.
///
/// They are a developer's own tools: run a rule set against synthetic players
/// and see what it matches, post one score, post one achievement's progress.
/// Neither submission is a manifest value and neither ever appears in a plan.
///
/// `preReleased` defaults to on everywhere here, so a mistaken press lands on
/// the prerelease side and not on the board that players are looking at.
struct GameCenterTestDataPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Test data", icon: "testtube.2", tint: Theme.accent,
                 anchor: "gaming.testData", folds: true, startsOpen: false,
                 note: "Check the game against what App Store Connect holds. None of this is a manifest value.") {
            VStack(alignment: .leading, spacing: 14) {
                GameCenterRuleSetTest()
                Divider().overlay(Theme.sep)
                GameCenterScoreSubmission()
                Divider().overlay(Theme.sep)
                GameCenterAchievementSubmission()
            }
            .storePanel(padding: 14)
        }
    }
}

/// Runs a rule set against synthetic players.
///
/// No confirmation, because there is nothing to undo. Apple evaluates the
/// rules and answers; the requests exist for the length of the call and Apple
/// stores none of them.
struct GameCenterRuleSetTest: View {
    @Environment(AppState.self) private var state
    @State private var ruleSet = ""
    @State private var requests = "4"
    @State private var players = "1"
    @State private var matches: [AppleGameCenterMatchmakingClient.TestMatch] = []
    @State private var running = false

    /// The rule sets App Store Connect actually holds. A set that exists only
    /// in `store.yaml` has nothing to test yet, and the note says so.
    private var choices: [StoreValues.Choice] {
        (state.liveGameCenter?.ruleSets ?? [:]).values
            .sorted { $0.referenceName < $1.referenceName }
            .map { .init($0.referenceName, $0.referenceName) }
    }

    private var chosen: String? {
        if choices.contains(where: { $0.id == ruleSet }) { return ruleSet }
        return choices.first?.id
    }

    private var requestCount: Int? {
        Int(requests).flatMap { (1...10).contains($0) ? $0 : nil }
    }

    private var playerCount: Int? {
        Int(players).flatMap { (1...16).contains($0) ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Test a rule set").font(Theme.font(size: 12, weight: .semibold))
            if choices.isEmpty {
                Text("App Store Connect holds no rule set for this account yet. Send one from the button at the top of this tab, and it becomes testable here.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FieldRow {
                    LabeledField("Rule set", width: 220) {
                        ChoiceField(value: Binding(get: { chosen ?? "" },
                                                   set: { ruleSet = $0 }),
                                    choices: choices, allowsNone: false)
                    }
                    LabeledField("Requests", note: "1 to 10", width: 110) {
                        TextField("4", text: $requests)
                    }
                    LabeledField("Players in each", note: "1 to 16", width: 110) {
                        TextField("1", text: $players)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button(running ? "Running…" : "Run the test") { run() }
                        .controlSize(.small)
                        .disabled(running || chosen == nil || requestCount == nil
                                  || playerCount == nil)
                    if running { Spinner() }
                    Text("It changes nothing in the account. Apple scores the rules against these players and answers.")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if !matches.isEmpty { results }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(matches) { match in
                HStack(spacing: 8) {
                    Text("Match \(match.id + 1)")
                        .font(Theme.font(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 74, alignment: .leading)
                    Text(match.requestNames.joined(separator: ", "))
                        .font(Theme.font(size: 11))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func run() {
        guard let name = chosen, let requestCount, let playerCount else { return }
        running = true
        Task {
            matches = await state.testGameCenterRuleSet(
                named: name, requests: requestCount,
                playersPerRequest: playerCount)
            running = false
        }
    }
}

/// Posts one score for one player.
struct GameCenterScoreSubmission: View {
    @Environment(AppState.self) private var state
    @State private var leaderboard = ""
    @State private var player = ""
    @State private var score = ""
    @State private var preReleased = true
    @State private var confirming = false
    @State private var sending = false

    private var chosen: String? {
        let choices = state.leaderboardChoices
        if choices.contains(where: { $0.id == leaderboard }) { return leaderboard }
        return choices.first?.id
    }

    private var scoreValue: Double? {
        guard let value = Double(score), value.isFinite else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Post a score").font(Theme.font(size: 12, weight: .semibold))
            FieldRow {
                LabeledField("Leaderboard", width: 240) {
                    ChoiceField(value: Binding(get: { chosen ?? "" },
                                               set: { leaderboard = $0 }),
                                choices: state.leaderboardChoices,
                                emptyLabel: "No leaderboard yet")
                }
                LabeledField("Player", note: "The scoped player id", width: 220) {
                    TextField("G:1234567890", text: $player)
                }
                LabeledField("Score", width: 130) {
                    TextField("1000", text: $score)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Toggle("Prerelease data", isOn: $preReleased)
                    .font(Theme.font(size: 11.5))
                Button(sending ? "Sending…" : "Post the score") { confirming = true }
                    .controlSize(.small)
                    .disabled(sending || chosen == nil || player.isEmpty
                              || scoreValue == nil)
                if sending { Spinner() }
                Spacer(minLength: 0)
            }
            Text("A scoped player id is the one the game reads from GameKit for this player. Leave the switch on and the entry lands on the prerelease side, where no player sees it.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Post this score?", isPresented: $confirming) {
            Button("Post it") { send() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(score) goes to \(chosen ?? "") for player \(player), on the \(preReleased ? "prerelease" : "live") side. A live entry is a real score on a real board.")
        }
    }

    private func send() {
        guard let id = chosen, let value = scoreValue else { return }
        sending = true
        Task {
            await state.submitGameCenterScore(leaderboard: id, playerID: player,
                                              score: value, preReleased: preReleased)
            sending = false
        }
    }
}

/// Posts achievement progress for one player, as a percentage.
struct GameCenterAchievementSubmission: View {
    @Environment(AppState.self) private var state
    @State private var achievement = ""
    @State private var player = ""
    @State private var percentage = "100"
    @State private var preReleased = true
    @State private var confirming = false
    @State private var sending = false

    private var chosen: String? {
        let choices = state.achievementChoices
        if choices.contains(where: { $0.id == achievement }) { return achievement }
        return choices.first?.id
    }

    private var value: Int? {
        guard let number = Int(percentage), (0...100).contains(number) else { return nil }
        return number
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Post achievement progress").font(Theme.font(size: 12, weight: .semibold))
            FieldRow {
                LabeledField("Achievement", width: 240) {
                    ChoiceField(value: Binding(get: { chosen ?? "" },
                                               set: { achievement = $0 }),
                                choices: state.achievementChoices,
                                emptyLabel: "No achievement yet")
                }
                LabeledField("Player", note: "The scoped player id", width: 220) {
                    TextField("G:1234567890", text: $player)
                }
                LabeledField("Progress", note: "0 to 100", width: 110) {
                    TextField("100", text: $percentage)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Toggle("Prerelease data", isOn: $preReleased)
                    .font(Theme.font(size: 11.5))
                Button(sending ? "Sending…" : "Post the progress") { confirming = true }
                    .controlSize(.small)
                    .disabled(sending || chosen == nil || player.isEmpty || value == nil)
                if sending { Spinner() }
                Spacer(minLength: 0)
            }
        }
        .confirmationDialog("Post this progress?", isPresented: $confirming) {
            Button("Post it") { send() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(percentage)% of \(chosen ?? "") goes to player \(player), on the \(preReleased ? "prerelease" : "live") side. On the live side the player has earned it.")
        }
    }

    private func send() {
        guard let id = chosen, let number = value else { return }
        sending = true
        Task {
            await state.submitGameCenterAchievement(
                achievement: id, playerID: player, percentage: number,
                preReleased: preReleased)
            sending = false
        }
    }
}

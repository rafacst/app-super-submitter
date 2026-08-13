import SubmitKit
import SwiftUI

/// Panel 8. How Game Center puts a match together.
///
/// Two things, and one points at the other. A **rule set** says what a good
/// match looks like: how many players, which sides they take, and the tests a
/// candidate has to pass. A **queue** is what a waiting player joins, and it
/// names the rule set that matches them. So the rule sets come first on the
/// screen, and a queue picks one from a chooser rather than repeating its name.
///
/// The panel draws nothing but its own sentence until a rule set exists, and it
/// says why: a queue with no rule set matches nobody.
struct GameCenterMatchmakingPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Matchmaking", icon: "person.3.fill", tint: Theme.accent,
                 anchor: "gaming.matchmaking", folds: true,
                 startsOpen: !state.matchmakingRuleSets.isEmpty,
                 note: "The rules a match has to pass, and the queues players wait in") {
            VStack(alignment: .leading, spacing: 14) {
                ruleSets
                Divider().overlay(Theme.sep)
                queues
            }
            .storePanel(padding: 14)
        }
    }

    // MARK: - The rule sets

    private var ruleSets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rule sets").font(Theme.font(size: 12, weight: .semibold))
            ForEach(Array(state.matchmakingRuleSets.enumerated()), id: \.offset) { index, set in
                ruleSetCard(index, set)
            }
            Button("Add a rule set") { state.addRuleSet() }.controlSize(.small)
        }
    }

    private func ruleSetCard(_ index: Int,
                             _ set: Manifest.GameCenter.RuleSet) -> some View {
        // A rule set the account holds can be deleted from here, and that is
        // not the same act as dropping the row: a queue that matches with it
        // stops matching players.
        GameCenterCard(set.name,
                       storeDeletion: state.liveGameCenter?.ruleSets[set.name] == nil
                           ? nil : .ruleSet(name: set.name),
                       remove: { state.removeRuleSet(at: index) }) {
            FieldRow {
                LabeledField("Name", note: "A queue points at this name",
                             width: 220) {
                    TextField("Ranked 2v2", text: state.ruleSetText(index, \.name))
                }
                LabeledField("Rule language", note: "Apple's revision",
                             width: 110) {
                    TextField("1", text: state.ruleSetLanguageVersion(index))
                }
                Spacer(minLength: 0)
            }
            GameCenterRange(lowLabel: "Fewest players", highLabel: "Most players",
                            low: state.ruleSetPair(index, at: 0),
                            high: state.ruleSetPair(index, at: 1))
            teams(index, set)
            rules(index, set)
        }
    }

    /// The sides of a match. A game with no sides needs none of these, so the
    /// list starts empty rather than with a Blue and a Red nobody asked for.
    private func teams(_ index: Int, _ set: Manifest.GameCenter.RuleSet) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Teams")
                .font(Theme.font(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
            if (set.teams ?? []).isEmpty {
                Text("No teams. Every player is on one side, which is what a free-for-all match wants.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array((set.teams ?? []).enumerated()), id: \.offset) { slot, _ in
                FieldRow {
                    LabeledField("Team name", width: 160) {
                        TextField("Blue", text: state.teamName(index, slot))
                    }
                    LabeledField("Fewest", width: 90) {
                        TextField("2", text: state.teamPair(index, slot, at: 0))
                    }
                    LabeledField("Most", width: 90) {
                        TextField("2", text: state.teamPair(index, slot, at: 1))
                    }
                    if state.liveGameCenter?.ruleSets[set.name]?.teams[
                        set.teams?[safe: slot]?.name ?? ""] != nil {
                        GameCenterStoreDeleteButton(
                            .team(ruleSet: set.name,
                                  name: set.teams?[safe: slot]?.name ?? ""))
                    }
                    Button(role: .destructive) {
                        state.removeTeam(ruleSet: index, at: slot)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Remove this team")
                    Spacer(minLength: 0)
                }
            }
            Button("Add a team") { state.addTeam(ruleSet: index) }.controlSize(.small)
        }
    }

    /// The tests themselves. Each one is an expression in Apple's rule
    /// language, and what the rule does with that expression is a choice of
    /// two, so it is a chooser holding both meanings rather than the words
    /// COMPATIBLE and DISTANCE.
    private func rules(_ index: Int, _ set: Manifest.GameCenter.RuleSet) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Rules")
                .font(Theme.font(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
            ForEach(Array((set.rules ?? []).enumerated()), id: \.offset) { slot, _ in
                VStack(alignment: .leading, spacing: 6) {
                    FieldRow {
                        LabeledField("Rule name", width: 170) {
                            TextField("Skill spread", text: state.ruleName(index, slot))
                        }
                        LabeledField("What it does", width: 240) {
                            ChoiceField(value: state.ruleText(index, slot, \.type),
                                        choices: StoreValues.matchmakingRuleTypes,
                                        emptyLabel: "Refuse the match when it is false",
                                        allowsNone: false)
                        }
                        LabeledField("Weight", note: "Against the others",
                                     width: 80) {
                            TextField("1", text: state.ruleWeight(index, slot))
                        }
                        if state.liveGameCenter?.ruleSets[set.name]?.rules[
                            set.rules?[safe: slot]?.name ?? ""] != nil {
                            GameCenterStoreDeleteButton(
                                .rule(ruleSet: set.name,
                                      name: set.rules?[safe: slot]?.name ?? ""))
                        }
                        Button(role: .destructive) {
                            state.removeRule(ruleSet: index, at: slot)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Remove this rule")
                    }
                    LabeledField("Expression",
                                 note: "Apple's rule language. For example: abs(requests.skill - requests.skill) < 200") {
                        TextField("abs(requests.skill - requests.skill) < 200",
                                  text: state.ruleText(index, slot, \.expression))
                    }
                    LabeledField("What it is for",
                                 note: "Optional. It appears beside the rule in App Store Connect.") {
                        TextField("Keep the skill gap small.",
                                  text: state.ruleText(index, slot, \.description))
                    }
                }
                .padding(8)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            }
            Button("Add a rule") { state.addRule(ruleSet: index) }.controlSize(.small)
        }
    }

    // MARK: - The queues

    private var queues: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Queues").font(Theme.font(size: 12, weight: .semibold))
            if state.matchmakingRuleSets.isEmpty {
                Text("A queue matches players with a rule set, so add a rule set above and a queue can point at it.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(state.matchmakingQueues.enumerated()), id: \.offset) { index, queue in
                    queueCard(index, queue)
                }
                Button("Add a queue") { state.addQueue() }.controlSize(.small)
            }
        }
    }

    private func queueCard(_ index: Int,
                           _ queue: Manifest.GameCenter.Queue) -> some View {
        GameCenterCard(queue.name,
                       storeDeletion: state.liveGameCenter?.queues[queue.name] == nil
                           ? nil : .queue(name: queue.name),
                       remove: { state.removeQueue(at: index) }) {
            FieldRow {
                LabeledField("Name", width: 220) {
                    TextField("Ranked", text: state.queueName(index))
                }
                LabeledField("Matches with",
                             note: "Picked from the rule sets above") {
                    ChoiceField(value: state.queueText(index, \.ruleSet),
                                choices: state.ruleSetChoices,
                                emptyLabel: "No rule set picked yet",
                                allowsNone: false)
                }
            }
            LabeledField("Older releases that share this queue",
                         note: "Bundle ids, comma-separated. Leave it empty unless a previous version of the game has to match against this one.") {
                TextField("com.studio.game.classic", text: state.queueBundleIDs(index))
            }
        }
    }
}

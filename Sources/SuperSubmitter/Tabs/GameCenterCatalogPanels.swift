import SubmitKit
import SwiftUI

/// Panels 3 to 7 of the Gaming tab: the five families of Game Center object.
///
/// **No field asks the developer to know Apple's spelling.** Everything Apple
/// offers as a fixed set of answers is a control with the answers in it: a tick
/// box where the answer is yes or no, a two-way picker where it is one of two
/// meanings, a chooser where it is one of a list. Where a field points at
/// another object, the chooser holds this manifest's own objects, so a set
/// member and a challenge board are picked rather than typed, and the id the
/// game passes to GameKit can never be mistyped into one.
///
/// **Removing a card removes it from the manifest and from nothing else.** The
/// object Apple holds keeps every score and every earned achievement, and the
/// plan simply stops managing it. Archiving is the switch on the card, and that
/// one does reach the store.

// MARK: - Panel 3, achievements

struct GameCenterAchievementsPanel: View {
    @Environment(AppState.self) private var state

    /// Apple allows 1000 points across a whole game, so the running total
    /// belongs beside the list and not in a validator three tabs away.
    private var spent: Int {
        state.achievements.reduce(0) { $0 + ($1.points ?? 0) }
    }

    var body: some View {
        Section_("Achievements", icon: "trophy.fill", tint: Theme.accent,
                 anchor: "gaming.achievements", folds: true,
                 startsOpen: !state.achievements.isEmpty,
                 note: "What a player earns, and what they read when they earn it") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.achievements.enumerated()), id: \.offset) { index, item in
                    card(index, item)
                }
                HStack(spacing: 12) {
                    Button("Add an achievement") { state.addAchievement() }
                        .controlSize(.small)
                GameCenterStoreRows(family: .achievement)
                    if !state.achievements.isEmpty {
                        Text("\(spent) of 1000 points used")
                            .font(Theme.font(size: 10.5))
                            .foregroundStyle(spent > 1000 ? Theme.red : Theme.text3)
                            .monospacedDigit()
                    }
                }
                Text("Apple takes 1 to 100 points for one achievement, and 1000 across the whole game.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .storePanel(padding: 14)
        }
    }

    private func card(_ index: Int, _ item: Manifest.GameCenter.Achievement) -> some View {
        GameCenterCard(item.name ?? item.id, family: .achievement, vendorID: item.id,
                       remove: { state.removeObject(\.achievements, at: index) }) {
            FieldRow {
                LabeledField("Id", note: "Your game passes this to GameKit", width: 220) {
                    TextField("com.studio.game.first_win",
                              text: state.objectID(\.achievements, index, \.id))
                }
                LabeledField("Name in App Store Connect", width: 200) {
                    TextField("First win",
                              text: state.objectText(\.achievements, index, \.name))
                }
                LabeledField("Points", note: "1 to 100", width: 80) {
                    TextField("10", text: state.objectNumber(\.achievements, index, \.points))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("A player can earn it more than once",
                       isOn: state.objectFlag(\.achievements, index, \.repeatable))
                Toggle("Show it before it is earned",
                       isOn: state.objectFlag(\.achievements, index, \.showBeforeEarned,
                                              default: true))
                Toggle("Archived, so players keep it but nobody earns it now",
                       isOn: state.objectFlag(\.achievements, index, \.archived))
            }
            .font(Theme.font(size: 11.5))
            GameCenterLocales { code in
                VStack(alignment: .leading, spacing: 6) {
                    FieldRow {
                        LabeledField("Title") {
                            TextField("First win", text: state.localeText(
                                \.achievements, index, \.locales, code, \.name,
                                empty: .init()))
                        }
                    }
                    FieldRow {
                        LabeledField("Before it is earned") {
                            TextField("Win a match.", text: state.localeText(
                                \.achievements, index, \.locales, code, \.beforeEarned,
                                empty: .init()))
                        }
                        LabeledField("After it is earned") {
                            TextField("You won a match.", text: state.localeText(
                                \.achievements, index, \.locales, code, \.afterEarned,
                                empty: .init()))
                        }
                    }
                    GameCenterImageField(path: state.localeText(
                        \.achievements, index, \.locales, code, \.image, empty: .init()))
                }
            }
        }
    }
}

// MARK: - Panel 4, leaderboards

struct GameCenterLeaderboardsPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Leaderboards", icon: "list.number", tint: Theme.accent,
                 anchor: "gaming.leaderboards", folds: true,
                 startsOpen: !state.leaderboards.isEmpty,
                 note: "How a score is ranked, written, and how often the board starts over") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.leaderboards.enumerated()), id: \.offset) { index, item in
                    card(index, item)
                }
                Button("Add a leaderboard") { state.addLeaderboard() }.controlSize(.small)
                GameCenterStoreRows(family: .leaderboard)
            }
            .storePanel(padding: 14)
        }
    }

    private func card(_ index: Int, _ item: Manifest.GameCenter.Leaderboard) -> some View {
        GameCenterCard(item.name ?? item.id, family: .leaderboard, vendorID: item.id,
                       remove: { state.removeObject(\.leaderboards, at: index) }) {
            FieldRow {
                LabeledField("Id", note: "Your game passes this to GameKit", width: 220) {
                    TextField("com.studio.game.high_score",
                              text: state.objectID(\.leaderboards, index, \.id))
                }
                LabeledField("Name in App Store Connect") {
                    TextField("High score",
                              text: state.objectText(\.leaderboards, index, \.name))
                }
            }
            // Two meanings each, so a two-way picker says both of them at once.
            // "asc" and "best" are Apple's spellings and neither one tells a
            // developer what it does to a score.
            FieldRow {
                LabeledField("Which score wins", width: 260) {
                    Picker("", selection: state.objectChoice(\.leaderboards, index, \.sort,
                                                             default: .desc)) {
                        ForEach(Manifest.GameCenter.ScoreSort.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                LabeledField("Which of a player's scores", width: 260) {
                    Picker("", selection: state.objectChoice(\.leaderboards, index,
                                                             \.submission, default: .best)) {
                        ForEach(Manifest.GameCenter.SubmissionType.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            FieldRow {
                LabeledField("How a score reads", width: 240) {
                    ChoiceField(value: state.objectText(\.leaderboards, index, \.format),
                                choices: StoreValues.leaderboardFormats,
                                emptyLabel: "Whole number",
                                allowsNone: false)
                }
                LabeledField("Who sees the board", width: 240) {
                    Picker("", selection: state.objectChoice(\.leaderboards, index,
                                                             \.visibility, default: .all)) {
                        ForEach(Manifest.GameCenter.Visibility.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            GameCenterRange(lowLabel: "Lowest score it takes",
                            highLabel: "Highest score it takes",
                            note: "Optional",
                            low: state.objectPair(\.leaderboards, index, \.scoreRange, at: 0),
                            high: state.objectPair(\.leaderboards, index, \.scoreRange, at: 1))
            Toggle("Archived, so players keep it but nobody scores to it now",
                   isOn: state.objectFlag(\.leaderboards, index, \.archived))
                .font(Theme.font(size: 11.5))
            recurrence(index)
            GameCenterLocales { code in
                VStack(alignment: .leading, spacing: 6) {
                    FieldRow {
                        LabeledField("Title") {
                            TextField("High score", text: state.localeText(
                                \.leaderboards, index, \.locales, code, \.name,
                                empty: .init()))
                        }
                        LabeledField("Description") {
                            TextField("The best run of the week.", text: state.localeText(
                                \.leaderboards, index, \.locales, code, \.description,
                                empty: .init()))
                        }
                    }
                    FieldRow {
                        LabeledField("Word after a score", note: "points", width: 150) {
                            TextField("points", text: state.localeText(
                                \.leaderboards, index, \.locales, code, \.suffix,
                                empty: .init()))
                        }
                        LabeledField("After exactly one", note: "point", width: 150) {
                            TextField("point", text: state.localeText(
                                \.leaderboards, index, \.locales, code, \.suffixSingular,
                                empty: .init()))
                        }
                        LabeledField("Format here instead") {
                            ChoiceField(value: state.localeText(
                                \.leaderboards, index, \.locales, code, \.format,
                                empty: .init()),
                                        choices: StoreValues.leaderboardFormats,
                                        emptyLabel: "Same as the board")
                        }
                    }
                    GameCenterImageField(path: state.localeText(
                        \.leaderboards, index, \.locales, code, \.image, empty: .init()))
                }
            }
        }
    }

    /// A board either runs forever or it starts over, so the schedule is behind
    /// one tick box and its three fields appear only once it is ticked.
    private func recurrence(_ index: Int) -> some View {
        let recurs = state.leaderboardRecurs(index)
        return VStack(alignment: .leading, spacing: 7) {
            Toggle("The board starts over on a schedule", isOn: recurs)
                .font(Theme.font(size: 11.5))
            if recurs.wrappedValue {
                FieldRow {
                    LabeledField("First period opens", note: "For example 2026-09-01T00:00:00Z",
                                 width: 200) {
                        TextField("2026-09-01T00:00:00Z",
                                  text: state.recurrenceText(index, \.start))
                    }
                    LabeledField("One period lasts", note: "P1W is a week",
                                 width: 130) {
                        TextField("P1W", text: state.recurrenceText(index, \.duration))
                    }
                    LabeledField("Repeats", note: "An iCalendar rule") {
                        TextField("FREQ=WEEKLY", text: state.recurrenceText(index, \.rule))
                    }
                }
            }
        }
    }
}

// MARK: - Panel 5, leaderboard sets

struct GameCenterLeaderboardSetsPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Leaderboard sets", icon: "square.stack.3d.up.fill", tint: Theme.accent,
                 anchor: "gaming.leaderboardSets", folds: true,
                 startsOpen: !state.leaderboardSets.isEmpty,
                 note: "A group of boards the player meets as one screen") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.leaderboardSets.enumerated()), id: \.offset) { index, item in
                    card(index, item)
                }
                Button("Add a set") { state.addLeaderboardSet() }.controlSize(.small)
                GameCenterStoreRows(family: .leaderboardSet)
                // Apple deprecated the write on a member localization and left
                // the read live, so this app can never name a board inside a
                // set. Saying it here is honest; a field that wrote nothing
                // would not be.
                Text("A board keeps its own name inside a set. Apple no longer takes a per-set name from the API, so the name each board carries above is the one a player reads.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .storePanel(padding: 14)
        }
    }

    private func card(_ index: Int, _ item: Manifest.GameCenter.LeaderboardSet) -> some View {
        GameCenterCard(item.name ?? item.id, family: .leaderboardSet, vendorID: item.id,
                       remove: { state.removeObject(\.leaderboardSets, at: index) }) {
            FieldRow {
                LabeledField("Id", note: "Your game passes this to GameKit", width: 220) {
                    TextField("com.studio.game.all_boards",
                              text: state.objectID(\.leaderboardSets, index, \.id))
                }
                LabeledField("Name in App Store Connect") {
                    TextField("All boards",
                              text: state.objectText(\.leaderboardSets, index, \.name))
                }
            }
            LabeledField("The boards in it",
                         note: "Picked from the leaderboards above, so an id is never mistyped") {
                MultiChoiceField(text: state.objectIDList(\.leaderboardSets, index,
                                                          \.leaderboards),
                                 choices: state.leaderboardChoices,
                                 emptyLabel: state.leaderboards.isEmpty
                                     ? "Add a leaderboard first"
                                     : "No board in this set yet")
            }
            GameCenterLocales { code in
                VStack(alignment: .leading, spacing: 6) {
                    LabeledField("Title") {
                        TextField("All boards", text: state.localeText(
                            \.leaderboardSets, index, \.locales, code, \.name,
                            empty: .init()))
                    }
                    GameCenterImageField(path: state.localeText(
                        \.leaderboardSets, index, \.locales, code, \.image, empty: .init()))
                }
            }
            memberNames(item)
        }
    }
}

extension GameCenterLeaderboardSetsPanel {
    /// The names Apple already holds for the boards inside this set.
    ///
    /// It is drawn and never edited, because Apple deprecated the write on a
    /// member localization and left the read and the delete live. A name here
    /// that no longer matches the game is one a developer has to change in the
    /// console, and the app says so rather than offering a field that no apply
    /// could ever send.
    @ViewBuilder
    func memberNames(_ item: Manifest.GameCenter.LeaderboardSet) -> some View {
        let names = state.liveGameCenter?.memberLocalizations[item.id] ?? []
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Names App Store Connect already holds inside this set")
                    .font(Theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                ForEach(names) { name in
                    HStack(spacing: 8) {
                        Text(name.locale)
                            .font(Theme.font(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                            .frame(width: 54, alignment: .leading)
                        Text(name.name.isEmpty ? "No name" : name.name)
                            .font(Theme.font(size: 11))
                            .foregroundStyle(name.name.isEmpty ? Theme.text3 : Theme.text)
                        Spacer(minLength: 0)
                    }
                }
                Text("Read only. Apple no longer takes a per-set name from the API, so changing one of these is a job for App Store Connect.")
                    .font(Theme.font(size: 10)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Panel 6, activities

struct GameCenterActivitiesPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Activities", icon: "person.2.fill", tint: Theme.accent,
                 anchor: "gaming.activities", folds: true,
                 startsOpen: !state.gameActivities.isEmpty,
                 note: "Something players do together, and what it awards") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.gameActivities.enumerated()), id: \.offset) { index, item in
                    card(index, item)
                }
                Button("Add an activity") { state.addGameActivity() }.controlSize(.small)
                GameCenterStoreRows(family: .activity)
            }
            .storePanel(padding: 14)
        }
    }

    private func card(_ index: Int, _ item: Manifest.GameCenter.Activity) -> some View {
        GameCenterCard(item.name ?? item.id, family: .activity, vendorID: item.id,
                       remove: { state.removeObject(\.activities, at: index) }) {
            FieldRow {
                LabeledField("Id", note: "Your game passes this to GameKit", width: 220) {
                    TextField("com.studio.game.coop_raid",
                              text: state.objectID(\.activities, index, \.id))
                }
                LabeledField("Name in App Store Connect") {
                    TextField("Co-op raid",
                              text: state.objectText(\.activities, index, \.name))
                }
            }
            LabeledField("How players take part", width: 380) {
                Picker("", selection: state.objectChoice(\.activities, index, \.playStyle,
                                                         default: .synchronous)) {
                    ForEach(Manifest.GameCenter.PlayStyle.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            GameCenterRange(lowLabel: "Fewest players", highLabel: "Most players",
                            low: state.objectPair(\.activities, index, \.players, at: 0),
                            high: state.objectPair(\.activities, index, \.players, at: 1))
            LabeledField("Where a player without the game goes",
                         note: "Optional. A web page that explains the activity.") {
                TextField("https://studio.example/raid",
                          text: state.objectText(\.activities, index, \.fallbackUrl))
            }
            FieldRow {
                LabeledField("Achievements it can award") {
                    MultiChoiceField(text: state.objectIDList(\.activities, index,
                                                              \.achievements),
                                     choices: state.achievementChoices,
                                     emptyLabel: state.achievements.isEmpty
                                         ? "Add an achievement first" : "None")
                }
                LabeledField("Leaderboards it scores to") {
                    MultiChoiceField(text: state.objectIDList(\.activities, index,
                                                              \.leaderboards),
                                     choices: state.leaderboardChoices,
                                     emptyLabel: state.leaderboards.isEmpty
                                         ? "Add a leaderboard first" : "None")
                }
            }
            Toggle("Archived, so it no longer starts",
                   isOn: state.objectFlag(\.activities, index, \.archived))
                .font(Theme.font(size: 11.5))
            LabeledField("Image every locale falls back to") {
                GameCenterImageField(path: state.objectText(\.activities, index, \.image))
            }
            GameCenterLocales { code in
                VStack(alignment: .leading, spacing: 6) {
                    FieldRow {
                        LabeledField("Title") {
                            TextField("Co-op raid", text: state.localeText(
                                \.activities, index, \.locales, code, \.name, empty: .init()))
                        }
                        LabeledField("Description") {
                            TextField("Clear the raid with a friend.",
                                      text: state.localeText(\.activities, index, \.locales,
                                                             code, \.description,
                                                             empty: .init()))
                        }
                    }
                    GameCenterImageField(path: state.localeText(
                        \.activities, index, \.locales, code, \.image, empty: .init()))
                }
            }
        }
    }
}

// MARK: - Panel 7, challenges

struct GameCenterChallengesPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Challenges", icon: "flag.2.crossed.fill", tint: Theme.accent,
                 anchor: "gaming.challenges", folds: true,
                 startsOpen: !state.gameChallenges.isEmpty,
                 note: "A contest between friends, scored from one leaderboard") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.gameChallenges.enumerated()), id: \.offset) { index, item in
                    card(index, item)
                }
                Button("Add a challenge") { state.addGameChallenge() }.controlSize(.small)
                GameCenterStoreRows(family: .challenge)
                Text("A challenge scores from a leaderboard, so add the board first and pick it here.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .storePanel(padding: 14)
        }
    }

    private func card(_ index: Int, _ item: Manifest.GameCenter.Challenge) -> some View {
        GameCenterCard(item.name ?? item.id, family: .challenge, vendorID: item.id,
                       remove: { state.removeObject(\.challenges, at: index) }) {
            FieldRow {
                LabeledField("Id", note: "Your game passes this to GameKit", width: 220) {
                    TextField("com.studio.game.weekly_duel",
                              text: state.objectID(\.challenges, index, \.id))
                }
                LabeledField("Name in App Store Connect") {
                    TextField("Weekly duel",
                              text: state.objectText(\.challenges, index, \.name))
                }
            }
            LabeledField("The leaderboard it scores from",
                         note: "Picked from the leaderboards above") {
                ChoiceField(value: state.objectText(\.challenges, index, \.leaderboard),
                            choices: state.leaderboardChoices,
                            emptyLabel: state.leaderboards.isEmpty
                                ? "Add a leaderboard first" : "No board picked yet")
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Players can take it on again",
                       isOn: state.objectFlag(\.challenges, index, \.repeatable))
                Toggle("Archived, so nobody starts it now",
                       isOn: state.objectFlag(\.challenges, index, \.archived))
            }
            .font(Theme.font(size: 11.5))
            LabeledField("Image every locale falls back to") {
                GameCenterImageField(path: state.objectText(\.challenges, index, \.image))
            }
            GameCenterLocales { code in
                VStack(alignment: .leading, spacing: 6) {
                    FieldRow {
                        LabeledField("Title") {
                            TextField("Weekly duel", text: state.localeText(
                                \.challenges, index, \.locales, code, \.name, empty: .init()))
                        }
                        LabeledField("Description") {
                            TextField("Beat your friend's score this week.",
                                      text: state.localeText(\.challenges, index, \.locales,
                                                             code, \.description,
                                                             empty: .init()))
                        }
                    }
                    GameCenterImageField(path: state.localeText(
                        \.challenges, index, \.locales, code, \.image, empty: .init()))
                }
            }
        }
    }
}

// MARK: - The image box

/// The same path box the screenshots and the purchase art use, so a missing
/// file is named where it is entered rather than on the Summary tab.
///
/// Apple takes a 512 by 512 PNG for every one of these, and the note says so
/// once per box instead of once per family.
struct GameCenterImageField: View {
    @Environment(AppState.self) private var state
    @Binding var path: String

    var body: some View {
        PathField(path: $path, prompt: "art/gc/first_win.png",
                  problem: state.missingFileNote(for: path)) {
            guard let url = state.chooseOneFile(allowedExtensions: ["png"]) else { return }
            path = state.relativePath(for: url)
        }
    }
}

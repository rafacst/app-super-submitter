import SubmitKit
import SwiftUI

/// The Gaming tab. Everything Game Center holds for a game.
///
/// **One store.** Play Games Services lives on a separate Google API on a
/// separate host, and the Publisher API this app speaks holds no games resource
/// at all. So this is a single-store tab like Marketing, and it says so once in
/// its header rather than once per panel.
///
/// **It writes `store.yaml` and calls nothing.** Every field here is a manifest
/// value. A Game Center object reaches a player through an App Store version
/// that carries the configuration, so the plan on the Summary tab is still what
/// decides that anything is sent.
///
/// **Most apps are not games.** The tab opens on one sentence and one button
/// until the developer turns Game Center on. The sidebar row stays visible for
/// every app, because hiding it would mean deciding whether an app is a game,
/// and the only honest source for that is the App Store category, which a draft
/// may not hold yet.
struct GamingTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !state.stores.contains(.apple) {
                noAppleStore
            } else if !state.hasGameCenter {
                GameCenterEmptyPanel()
            } else {
                // The button first. Nothing on this tab needs a build, so a
                // developer who came to change one leaderboard can send it
                // from here without opening Summary. It is drawn in both
                // modes, because Gaming is a publishing tab that a live game
                // is edited on.
                GameCenterSendPanel()
                GamingActionBanner()
                GameCenterDetailPanel()
                GameCenterAchievementsPanel()
                GameCenterLeaderboardsPanel()
                GameCenterLeaderboardSetsPanel()
                GameCenterActivitiesPanel()
                GameCenterChallengesPanel()
                GameCenterMatchmakingPanel()
                // The two panels that answer a question instead of describing
                // a desired state. Both are folded shut, because both cost a
                // request and neither belongs to the edit a developer came
                // here to make.
                GameCenterMetricsPanel()
                GameCenterTestDataPanel()
            }
        }
        .frame(maxWidth: 1040, alignment: .leading)
    }

    private var noAppleStore: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.teal)
            Text("Game Center is an App Store service. Turn the App Store on in Stores, and this tab has something to write. Google Play has no equivalent: Play Games Services is a separate API that this app does not speak.")
                .font(Theme.font(size: 12.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: 700, alignment: .leading)
        .background(Theme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The whole tab before Game Center is on: what it gives a game, and one
/// button.
///
/// The button writes `gameCenter.enabled: true` and calls nothing. The apply
/// creates the detail in App Store Connect. A tab that made a store call on its
/// first press would be the only editing tab in the app that does.
struct GameCenterEmptyPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Game Center", icon: "gamecontroller.fill", tint: Theme.accent,
                 anchor: "gaming.detail") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Game Center gives a game achievements, leaderboards, challenges and matchmaking. Turning it on creates the configuration in App Store Connect.")
                    .font(Theme.font(size: 12.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing here reaches a player until an App Store version carries it.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                // A game that already ships has a configuration up there
                // before this tab has a block. Saying so here is what turns
                // the button from "create something" into "start managing what
                // I already have".
                Divider().overlay(Theme.sep)
                GameCenterStoreSummary()
                Button(state.liveGameCenter?.exists == true
                       ? "Manage Game Center here" : "Turn on Game Center") {
                    state.turnOnGameCenter()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .storePanel(padding: 14)
        }
    }
}

/// Panel 2. The configuration itself: whether it exists, the group it shares
/// with, the board Game Center opens on, and the versions that carry it.
struct GameCenterDetailPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("The configuration", icon: "gamecontroller.fill", tint: Theme.accent,
                 anchor: "gaming.detail",
                 note: "App Store only. Every field writes store.yaml.") {
            VStack(alignment: .leading, spacing: 12) {
                GameCenterStoreSummary()
                Divider().overlay(Theme.sep)
                FieldRow {
                    LabeledField("Shared group", note: "Optional. Games in one group share their objects.",
                                 width: 240) {
                        TextField("Studio shared",
                                  text: state.gameCenterText(\.group))
                    }
                    GameCenterGroupDelete()
                    LabeledField("Opening leaderboard",
                                 note: "The board Game Center shows first") {
                        ChoiceField(value: state.gameCenterText(\.defaultLeaderboard),
                                    choices: state.leaderboardChoices,
                                    emptyLabel: "No opening board")
                    }
                }
                // A version of this game, not an OS version. Apple keeps this
                // as a relationship to the App Store versions of the app, so
                // the value has to name one of them.
                LabeledField("Challenges start at",
                             note: "App Store versions of this game, comma-separated. For example: 1.4.0. Leave it empty to offer challenges on every version that supports them.") {
                    TextField("1.4.0",
                              text: state.gameCenterList(\.challengesMinimumPlatformVersions))
                }
                Divider().overlay(Theme.sep)
                GameCenterVersionRows()
                Divider().overlay(Theme.sep)
                NoteWithAction("Removing the block stops the app managing Game Center. Nothing is deleted in App Store Connect, and every score and earned achievement stays exactly as it is.") {
                    Button("Remove the block", role: .destructive) {
                        state.removeGameCenter()
                    }
                    .controlSize(.small)
                }
            }
            .storePanel(padding: 14)
        }
    }
}

/// What the last call that was not a plan step reported.
///
/// One line for the whole tab, near the top, because one of those calls runs
/// at a time: a delete, a metric read, or a test submission. A card deep in a
/// list has no room to report a failure, and a message that appeared down
/// there would be off screen the moment the list scrolled.
struct GamingActionBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if !state.gamingActionMessage.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: state.gamingActionFailed
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(state.gamingActionFailed ? Theme.red : Theme.green)
                Text(state.gamingActionMessage)
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Dismiss") { state.gamingActionMessage = "" }
                    .controlSize(.small)
            }
            .padding(11)
            .frame(maxWidth: 700, alignment: .leading)
            .background((state.gamingActionFailed ? Theme.red : Theme.green).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

/// Removes the shared group from the account.
///
/// It is the one destructive button on this tab that reaches past this game.
/// A group is account-wide, so deleting it takes the shared achievements and
/// leaderboards from every game in it, and this app knows about one of them.
/// The confirmation says exactly that.
struct GameCenterGroupDelete: View {
    @Environment(AppState.self) private var state
    @State private var deleting = false

    private var name: String? {
        guard let name = state.gameCenter?.group, !name.isEmpty,
              state.liveGameCenter?.groups[name] != nil else { return nil }
        return name
    }

    var body: some View {
        if let name {
            Button("Delete the group", role: .destructive) { deleting = true }
                .controlSize(.small)
                .gameCenterDeleteConfirmation($deleting, .group(name: name))
        }
    }
}

struct GameCenterStoreDeleteButton: View {
    let deletion: AppState.GameCenterDeletion
    @State private var deleting = false

    init(_ deletion: AppState.GameCenterDeletion) {
        self.deletion = deletion
    }

    var body: some View {
        Button(role: .destructive) { deleting = true } label: {
            Image(systemName: "trash.slash")
        }
        .controlSize(.small)
        .accessibilityLabel(deletion.title)
        .help("Delete it in App Store Connect")
        .gameCenterDeleteConfirmation($deleting, deletion)
    }
}

/// The App Store versions that carry the configuration.
///
/// A Game Center version has no release call of its own. Every `*Release`
/// resource Apple published is deprecated and the v2 model replaces none of
/// them, so a new achievement reaches players through the App Store version
/// that carries it and through nothing else. That is the whole reason this row
/// exists, and the panel says it rather than offering a button no endpoint
/// backs.
struct GameCenterVersionRows: View {
    @Environment(AppState.self) private var state

    /// The version this manifest is publishing, so the common case is one
    /// click instead of typing a number that is already on the Build tab.
    private var releaseVersion: String? {
        let version = state.manifest.release?.apple?.versionName
            ?? state.manifest.release?.versionName
        guard let version, !version.isEmpty else { return nil }
        return version
    }

    private var rows: [String] {
        (state.gameCenter?.appVersions ?? [:]).keys.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("The App Store versions that carry it")
                .font(Theme.font(size: 12, weight: .semibold))
            if rows.isEmpty {
                Text("No version carries this configuration yet, so no player sees it. A Game Center version has no release call of its own: it ships with the App Store version that carries it.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows, id: \.self) { version in
                versionRow(version)
            }
            if let releaseVersion, !rows.contains(releaseVersion) {
                Button("Carry it on \(releaseVersion)") {
                    state.editGameCenter { block in
                        var versions = block.appVersions ?? [:]
                        versions[releaseVersion] = .init(enabled: true)
                        block.appVersions = versions
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func versionRow(_ version: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(version).font(Theme.font(size: 12, weight: .semibold))
                Toggle("Carries Game Center", isOn: Binding(
                    get: { state.gameCenter?.appVersions?[version]?.enabled ?? true },
                    set: { value in
                        state.editGameCenter { block in
                            block.appVersions?[version]?.enabled = value
                        }
                    }))
                    .font(Theme.font(size: 11.5))
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    state.editGameCenter { block in
                        block.appVersions?[version] = nil
                        if block.appVersions?.isEmpty == true { block.appVersions = nil }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .accessibilityLabel("Stop carrying Game Center on \(version)")
            }
            LabeledField("Keeps the scores from",
                         note: "Older versions, comma-separated. Their leaderboard scores and earned achievements carry over.") {
                TextField("1.3.0, 1.2.0", text: Binding(
                    get: {
                        (state.gameCenter?.appVersions?[version]?.compatibility ?? [])
                            .joined(separator: ", ")
                    },
                    set: { value in
                        let list = AppState.splitList(value)
                        state.editGameCenter { block in
                            block.appVersions?[version]?.compatibility =
                                list.isEmpty ? nil : list
                        }
                    }))
            }
        }
        .padding(9)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - The shared shapes

/// One card in a family list, with the destructive button every card carries.
///
/// Five families draw the same box: a sunken rectangle, a title row holding the
/// id, and a trash button that removes the row from the manifest and nothing
/// from App Store Connect. `// ponytail: one card, five families.`
struct GameCenterCard<Content: View>: View {
    @Environment(AppState.self) private var state
    let title: String
    /// The family and id this card edits, so the header can say whether App
    /// Store Connect already holds it. Nil on a card that has no store twin,
    /// which is every matchmaking card: Apple keys those by reference name and
    /// the read has no vendor identifier to match them on.
    var family: AppleGameCenterCatalogClient.Family?
    var vendorID: String = ""
    /// What the destructive button removes from App Store Connect, for a card
    /// whose row Apple keys by reference name rather than by a vendor
    /// identifier: a rule set, a queue. A card that names a family works its
    /// own out.
    var storeDeletion: AppState.GameCenterDeletion?
    let remove: () -> Void
    @ViewBuilder let content: Content
    @State private var deleting = false

    init(_ title: String, family: AppleGameCenterCatalogClient.Family? = nil,
         vendorID: String = "", storeDeletion: AppState.GameCenterDeletion? = nil,
         remove: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.family = family
        self.vendorID = vendorID
        self.storeDeletion = storeDeletion
        self.remove = remove
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(Theme.font(size: 12, weight: .semibold))
                    .foregroundStyle(title.isEmpty ? Theme.text3 : Theme.text)
                    .lineLimit(1)
                if let family {
                    GameCenterStoreBadge(family: family, vendorID: vendorID)
                }
                Spacer(minLength: 0)
                // Two different removals, and they are not the same act. The
                // trash stops this app managing the row and leaves everything
                // in App Store Connect. The second one takes the object away
                // up there, with every score behind it, so it appears only
                // when there is something up there to take and it confirms in
                // its own words.
                if deletion != nil {
                    Button(role: .destructive) { deleting = true } label: {
                        Image(systemName: "trash.slash")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Delete \(title.isEmpty ? "this row" : title) in App Store Connect")
                    .help("Delete it in App Store Connect, with every score behind it")
                }
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .accessibilityLabel("Stop managing \(title.isEmpty ? "this row" : title)")
                .help("Stop managing it here. Nothing changes in App Store Connect")
            }
            content
        }
        .padding(9)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
        .gameCenterDeleteConfirmation($deleting, deletion)
    }

    /// What the destructive button would remove, or nil when App Store Connect
    /// holds nothing to remove and the button is not drawn.
    private var deletion: AppState.GameCenterDeletion? {
        if let storeDeletion { return storeDeletion }
        guard let family, !vendorID.isEmpty,
              state.liveObject(family, vendorID) != nil else { return nil }
        return .object(family: family, vendorID: vendorID,
                       name: title.isEmpty ? vendorID : title)
    }
}

/// The one confirmation every destructive Game Center button uses.
///
/// One place, because every one of them says the same shape of thing: what
/// goes, what goes with it, and that no call brings it back. Spelling that out
/// per card would be five chances to word it more softly than it is.
extension View {
    func gameCenterDeleteConfirmation(_ presented: Binding<Bool>,
                                      _ deletion: AppState.GameCenterDeletion?) -> some View {
        modifier(GameCenterDeleteConfirmation(presented: presented, deletion: deletion))
    }
}

private struct GameCenterDeleteConfirmation: ViewModifier {
    @Environment(AppState.self) private var state
    @Binding var presented: Bool
    let deletion: AppState.GameCenterDeletion?

    func body(content: Content) -> some View {
        content.confirmationDialog(deletion?.title ?? "", isPresented: $presented) {
            Button("Delete it in App Store Connect", role: .destructive) {
                guard let deletion else { return }
                Task { await state.deleteInGameCenter(deletion) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletion?.message ?? "")
        }
    }
}

/// The locale rows of one object.
///
/// One row per locale the **listing** already holds, in the order the Details
/// tab draws them, so a game with three locales gets three rows and never a
/// locale picker of its own. A locale is therefore never added here by
/// accident, and the one list of locales stays the one on Details.
struct GameCenterLocales<Content: View>: View {
    @Environment(AppState.self) private var state
    let title: String
    @ViewBuilder let row: (String) -> Content

    init(_ title: String = "What the player reads",
         @ViewBuilder row: @escaping (String) -> Content) {
        self.title = title
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.locales.isEmpty {
                Text("Add a locale on the Details tab, and it gets a row here. Apple shows the reference name to a player when a locale is missing.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(title)
                    .font(Theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                ForEach(state.locales, id: \.self) { code in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(code)
                            .font(Theme.font(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                        row(code)
                    }
                }
            }
        }
    }
}

/// The two boxes a pair of numbers is really two questions.
struct GameCenterRange: View {
    let lowLabel: String
    let highLabel: String
    var note: String?
    @Binding var low: String
    @Binding var high: String

    var body: some View {
        FieldRow {
            LabeledField(lowLabel, note: note, width: 150) {
                TextField("", text: $low)
            }
            LabeledField(highLabel, width: 150) {
                TextField("", text: $high)
            }
            Spacer(minLength: 0)
        }
    }
}

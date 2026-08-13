import SubmitKit
import SwiftUI

/// What App Store Connect already holds, drawn beside what the manifest asks
/// for.
///
/// The Gaming tab is an editing tab, so the store side is never the thing being
/// edited. It answers two questions a developer cannot otherwise answer without
/// opening the console: **does this object already exist**, and **what else is
/// up there that my manifest has never heard of**.
///
/// The second question is the one that matters for a game that already ships.
/// Forty achievements exist in App Store Connect and the manifest is empty, so
/// the panel lists all forty and brings them into `store.yaml` on a button.
/// That write reaches the manifest and never the store.

/// One line per family: how many the store holds, and how many are new here.
struct GameCenterStoreRows: View {
    @Environment(AppState.self) private var state
    let family: AppleGameCenterCatalogClient.Family

    private var live: ActualState.Apple.GameCenter? { state.liveGameCenter }
    private var missing: [AppleGameCenterCatalogClient.Object] { state.storeOnly(family) }

    var body: some View {
        if let live, live.read, live.exists {
            VStack(alignment: .leading, spacing: 7) {
                Divider().overlay(Theme.sep)
                if live.unreadFamilies.contains(family.rawValue) {
                    unread
                } else {
                    header(live)
                    if !missing.isEmpty { list }
                }
            }
        }
    }

    private var unread: some View {
        Label("App Store Connect did not answer for the \(family.label). What is on this screen is the manifest alone.",
              systemImage: "exclamationmark.triangle.fill")
            .font(Theme.font(size: 10.5))
            .foregroundStyle(Theme.yellow)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func header(_ live: ActualState.Apple.GameCenter) -> some View {
        let held = live.objects(family).count
        return NoteWithAction(held == 0
            ? "App Store Connect holds no \(family.label) for this game yet."
            : "App Store Connect holds \(held) \(held == 1 ? family.noun : family.label), and \(missing.count) of them are not in this manifest.") {
            if !missing.isEmpty {
                Button("Bring in all \(missing.count)") {
                    state.importEveryObject(family)
                }
                .controlSize(.small)
            }
        }
    }

    /// The objects only the store has. Each one names itself and comes across
    /// on its own button, because a developer often wants three of forty.
    private var list: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(missing) { object in
                HStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.text3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(object.displayName)
                            .font(Theme.font(size: 11.5))
                            .lineLimit(1)
                        Text(object.vendorIdentifier)
                            .font(Theme.font(size: 10))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if object.archived == true {
                        Text("Archived")
                            .font(Theme.font(size: 10))
                            .foregroundStyle(Theme.text3)
                    }
                    Button("Bring in") { state.importObject(family, object) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// Whether App Store Connect already holds the object on this card.
///
/// It sits on the card's title row, because "does this exist yet" changes what
/// the apply will do to it: an id the store already holds is a change, and an
/// id it does not is a create. A developer reading a card should not have to
/// guess which.
struct GameCenterStoreBadge: View {
    @Environment(AppState.self) private var state
    let family: AppleGameCenterCatalogClient.Family
    let vendorID: String

    var body: some View {
        // Nothing at all before a read. A badge saying "new" when the app has
        // simply never looked would be a claim it cannot support.
        if let live = state.liveGameCenter, live.read, live.exists,
           !live.unreadFamilies.contains(family.rawValue), !vendorID.isEmpty {
            if let object = state.liveObject(family, vendorID) {
                badge("In App Store Connect", Theme.green,
                      hint: object.archived == true ? "and archived there" : nil)
            } else {
                badge("New", Theme.text3, hint: nil)
            }
        }
    }

    private func badge(_ label: String, _ tint: Color, hint: String?) -> some View {
        Text(hint.map { "\(label), \($0)" } ?? label)
            .font(Theme.font(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// The read itself, at the head of the configuration panel.
///
/// Three states and one sentence each, because they mean three different
/// things: nobody has looked yet, the store has no configuration, or the read
/// failed and every count below it is the manifest talking to itself.
struct GameCenterStoreSummary: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.gameCenterReadFailed {
                line("App Store Connect did not answer when this app was last read, so nothing on this tab has been checked against the store.",
                     "exclamationmark.triangle.fill", Theme.yellow)
            } else if let live = state.liveGameCenter, live.read {
                if let detail = live.detail {
                    held(detail, live)
                } else {
                    line("App Store Connect holds no Game Center configuration for this app yet. The apply creates one.",
                         "info.circle.fill", Theme.teal)
                }
            } else {
                line("This app has not been read yet. Open Summary and read the stores to see what App Store Connect already holds.",
                     "info.circle.fill", Theme.teal)
            }
        }
    }

    /// What the store holds, in one line and a count per family.
    private func held(_ detail: AppleGameCenterClient.Detail,
                      _ live: ActualState.Apple.GameCenter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            line("App Store Connect holds a Game Center configuration for this app.",
                 "checkmark.circle.fill", Theme.green)
            HStack(spacing: 14) {
                ForEach(AppleGameCenterCatalogClient.Family.allCases, id: \.self) { family in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(live.objects(family).count)")
                            .font(Theme.font(size: 13, weight: .semibold))
                            .monospacedDigit()
                        Text(family.label)
                            .font(Theme.font(size: 10))
                            .foregroundStyle(Theme.text3)
                    }
                }
                Spacer(minLength: 0)
            }
            if let group = detail.groupName {
                Text("It belongs to the group \(group).")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if let board = detail.defaultLeaderboardVendorID {
                Text("It opens on \(board).")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            }
        }
    }

    private func line(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(Theme.font(size: 11))
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// The one button that sends Game Center.
///
/// **Why this tab has a button at all.** Nothing on it needs a build. A
/// leaderboard, an achievement, a rule set and a queue are all written the
/// moment they are sent, so a developer who came here to fix the sort order of
/// one board should not have to open Summary, read both stores, and send the
/// listing and the media beside it.
///
/// It sends the `apple.gameCenter` rows and nothing else: the configuration,
/// the group, the five families with their locales and their pictures, the
/// matchmaking, and last the App Store version that carries the configuration.
///
/// **It reads the App Store first**, every time. A stale comparison here asks
/// Apple to create an achievement it already holds, and Apple answers 409 on
/// the vendor identifier.
struct GameCenterSendPanel: View {
    @Environment(AppState.self) private var state
    @State private var confirming = false

    /// The rows below the fold of the confirmation. Four fits the dialog at
    /// every type size; the rest are counted rather than listed.
    private static let namedRows = 4

    var body: some View {
        let rows = state.changes(for: .gameCenter)
        let running = state.directApplyRunning(.gameCenter)
        let message = state.directApplyMessage(for: .gameCenter)
        let errors = state.gameCenterErrors()
        return Section_("Send to Game Center", icon: "paperplane.fill", tint: Theme.accent,
                        anchor: "gaming.send") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rows.isEmpty
                             ? "App Store Connect holds everything on this tab."
                             : "\(rows.count) \(rows.count == 1 ? "row" : "rows") to send")
                            .font(Theme.font(size: 12.5, weight: .medium))
                        Text(message.isEmpty ? subtitle(errors) : message)
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(state.directApplyFailed(.gameCenter)
                                             || !errors.isEmpty ? Theme.red : Theme.text2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if running || state.planReading { Spinner() }
                    Button(buttonTitle(running: running)) { start() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(running || state.planReading || rows.isEmpty
                                  || !errors.isEmpty)
                }
                // The one sentence that is true of this tab and of no other.
                Text("Nothing here reaches a player until an App Store version carries it. An archived object stops appearing in the game, and a deleted one takes every score with it.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Send this to Game Center?", isPresented: $confirming) {
            Button("Send it") { state.applyDirectly(.gameCenter) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmation)
        }
    }

    /// The line under the count. An error comes first, because Apple refuses
    /// the value and the apply would stop partway with the rows before it
    /// already written.
    private func subtitle(_ errors: [Finding]) -> String {
        if let first = errors.first {
            return errors.count == 1
                ? first.message
                : "\(errors.count) problems stop this send. The first: \(first.message)"
        }
        return "It reads the App Store first, so the confirmation names exactly what goes."
    }

    private func buttonTitle(running: Bool) -> String {
        if state.planReading { return "Reading…" }
        return running ? "Sending…" : "Send to Game Center"
    }

    /// Reads, then asks. The read is what makes the numbers in the dialog the
    /// real ones: before it, every object counts as new because the plan has
    /// nothing to compare it against.
    private func start() {
        Task {
            await state.readStores()
            confirming = true
        }
    }

    private var confirmation: String {
        let rows = state.changes(for: .gameCenter)
        guard !rows.isEmpty else {
            return "App Store Connect already holds every row on this tab, so this sends nothing."
        }
        let named = rows.prefix(Self.namedRows).joined(separator: "\n")
        let rest = rows.count - Self.namedRows
        return "Super Submitter sends \(rows.count) \(rows.count == 1 ? "row" : "rows") now:\n"
            + named + (rest > 0 ? "\n… and \(rest) more" : "")
            + "\n\nNothing here reaches a player until an App Store version carries it. An archived object stops appearing in the game, and a deleted one takes every score with it."
    }
}

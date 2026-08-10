import SubmitKit
import SwiftUI

/// What is stopping the release, one click from anywhere.
///
/// The list itself is not new. It stood at the head of the Release tab, which
/// is the one screen a developer reaches after they have already decided to
/// send. The question it answers — "can I ship today" — is asked from every
/// other screen and at every other moment, and answering it meant walking to
/// the last tab to look.
///
/// So the same rows get a way in from the header band, which is on every
/// screen. Nothing here reads a second source: `releaseBlockers` is what the
/// two release buttons already obey, so the panel and the buttons can never
/// disagree about what is stopping what.
extension AppState {

    /// Every row holding a store back, across the stores this app uses.
    ///
    /// In store order and not in row order, so the two stores read as two
    /// lists rather than as one interleaved one.
    var blockersEverywhere: [ConsoleRow] {
        Store.allCases
            .filter(stores.contains)
            .flatMap { releaseBlockers(for: $0) }
    }

    /// The version the two release buttons send, named the way the manifest
    /// names it.
    var releaseVersionName: String {
        let version = manifest.release?.versionName ?? ""
        return version.isEmpty ? "this release" : version
    }

    /// The sentence at the head of the list, in the app's own arithmetic.
    func blockersHeadline(_ count: Int) -> String {
        count == 1
            ? "1 thing is stopping \(releaseVersionName)"
            : "\(count) things are stopping \(releaseVersionName)"
    }
}

/// The rows themselves, drawn once for the Release tab and for the panel.
///
/// `action` is what the caller puts at the end of each row. The Release tab
/// passes nothing, because the row's own checklist is a few hundred points
/// below it on the same screen. The panel passes the way out to the console,
/// because from there the row is the only thing on the screen.
struct BlockersList<Action: View>: View {
    let rows: [ConsoleRow]
    let headline: String
    var recheck: (() -> Void)?
    @ViewBuilder var action: (ConsoleRow) -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(headline)
                    .font(Theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let recheck { QuietButton(title: "Re-check", action: recheck) }
            }
            .padding(.horizontal, 15).padding(.vertical, 10)

            ForEach(rows) { row in
                Hairline(color: Theme.red.opacity(0.3))
                HStack(alignment: .top, spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(Theme.font(size: 12.5, weight: .medium))
                        Text(row.reason)
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(row.system).font(Theme.font(size: 11))
                        .foregroundStyle(Theme.text3)
                    action(row)
                }
                .padding(.horizontal, 15).padding(.vertical, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.red, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

extension BlockersList where Action == EmptyView {
    init(rows: [ConsoleRow], headline: String, recheck: (() -> Void)? = nil) {
        self.init(rows: rows, headline: headline, recheck: recheck) { _ in EmptyView() }
    }
}

/// The way in, in the header band, and only while there is something to say.
///
/// It is silent on a release with nothing stopping it. A permanent control
/// that reads zero for weeks is furniture, and the one week it reads three
/// looks like every other week.
struct BlockersButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let count = state.blockersEverywhere.count
        // Not on Release. That tab opens on this same list at full length, and
        // a band that counts what the card under it names is the count printed
        // twice on one screen.
        if count > 0, state.selectedTab != .release {
            Button { state.showBlockers = true } label: {
                HStack(spacing: 7) {
                    Circle().fill(Theme.red).frame(width: 7, height: 7)
                    Text("\(count) \(count == 1 ? "blocker" : "blockers")")
                        .font(Theme.font(size: 12.5, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(Theme.font(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.red)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.red.opacity(0.35), lineWidth: Theme.hairline))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.blockersHeadline(count))
            .help("What is stopping the release")
        }
    }
}

/// The panel behind that button.
///
/// Every row here is a step in somebody else's website, so every row leaves
/// the app. The foot carries the two things a developer does with this list
/// once they have read it: take it somewhere else, or go and look at the whole
/// checklist it was drawn from.
struct BlockersPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let rows = state.blockersEverywhere
        VStack(spacing: 0) {
            PanelTitleBar(title: "What is stopping the release") { dismiss() }
            VStack(alignment: .leading, spacing: 13) {
                if rows.isEmpty {
                    Text("Nothing is stopping \(state.releaseVersionName).")
                        .font(Theme.font(size: 12.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    BlockersList(rows: rows,
                                 headline: state.blockersHeadline(rows.count),
                                 recheck: { Task { await state.recheck() } }) { row in
                        Button { state.open(row.link) } label: {
                            HStack(spacing: 5) {
                                Text("Open").font(Theme.font(size: 11.5, weight: .medium))
                                Image(systemName: "arrow.up.forward.square")
                                    .font(Theme.font(size: 10))
                            }
                            .foregroundStyle(Theme.red)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(row.title) in \(row.system)")
                    }

                    Text("Everything else can be prepared and kept as a draft today.")
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 7) {
                    QuietButton(title: "Show the checklist") {
                        dismiss()
                        state.selectedTab = .release
                    }
                    QuietButton(title: "Copy as checklist") { state.copyChecklist() }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Theme.content)
        }
        .frame(width: 460)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }
}

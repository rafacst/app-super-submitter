import SubmitKit
import SwiftUI

/// The builds App Store Connect already holds, and the one this version ships.
///
/// Apple keeps every build it processed and lets a version take one of them.
/// This app took the highest processed build of the version's train and offered
/// no way to say otherwise, so a build that was in the store, was ready, and was
/// not the newest could not be shipped: the developer's only route was the
/// console. That is what this panel is.
///
/// Nothing here writes to a store. The choice lands in `store.yaml`, the plan
/// draws the attach row, and the apply sends it.
struct AppleBuildsPanel: View {
    @Environment(AppState.self) private var state
    @State private var loading = false
    /// Which app and train the rows on screen belong to, or nil while there
    /// are none. It was a `Bool`, and a `Bool` cannot tell "already fetched"
    /// from "fetched, for the app before this one": switching app in the tab
    /// strip left the previous app's builds under the new app's name, and the
    /// fetch that would have replaced them was refused as already done.
    @State private var loadedKey: String?
    @State private var error: String?
    @State private var builds: [UploadService.RemoteBuild] = []
    /// How many rows are drawn. An app that has been shipping for a year holds
    /// hundreds of builds, and every one of them was on the screen: the panel
    /// ran off the bottom of the tab and the Fetch button, the note and the
    /// chosen line went with it.
    @State private var shown = Self.page

    /// One press of "Show 10 more". Ten is a screen of rows, and the newest ten
    /// is what a developer comes here for.
    private static let page = 10

    /// Whether the rows on screen answer for the app the tab is showing.
    private var loaded: Bool { loadedKey == taskKey }

    /// What a fetched list belongs to: one app id and one train. Both change
    /// the answer, and both can change without this panel leaving the screen.
    private var taskKey: String {
        "\(state.appleActionAppID ?? "")·\(state.applePlatform.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            NoteWithAction(note) {
                QuietButton(title: loading ? "Fetching…"
                                   : (loaded ? "Fetch them again" : "Fetch the builds")) {
                    load()
                }
                .disabled(loading)
            }
            .font(Theme.font(size: 11.5))

            if let error { WarningNote(error) }
            if loaded, builds.isEmpty {
                Text("App Store Connect holds no build for this app on \(state.applePlatform == .macOS ? "macOS" : "iOS") yet.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            if loaded, !builds.isEmpty { list }
            if let chosen = state.chosenAppleBuildNumber, !chosen.isEmpty { chosenLine(chosen) }
        }
        .fieldAnchor("build.storeBuilds")
        // The list, without being asked for it. A panel titled "Builds in App
        // Store Connect" that holds no build until a button is pressed is the
        // app asking the developer to confirm that they meant the thing they
        // opened. The read is read-only and it writes nothing.
        //
        // Keyed on the app and the platform, because those are the two answers
        // the list depends on: switching app in the tab strip, or switching an
        // app's train from iOS to macOS, both make the rows on screen the
        // wrong ones.
        .task(id: taskKey) {
            guard !loaded, !loading, state.appleActionAppID != nil else { return }
            load()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            StoreMark(store: .apple, size: 16)
            Text("Builds in App Store Connect")
                .font(Theme.font(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text("The chip says what became of each one")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
        }
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var note: String {
        state.chosenAppleBuildNumber?.isEmpty == false
            ? "The apply attaches the build named below. Nothing here uploads a binary."
            : "Without a choice the apply attaches the highest processed build of version \(train.isEmpty ? "this release" : train). Pick one to say otherwise."
    }

    /// The release version this app writes to. A build outside it belongs to
    /// another train, and Apple gives a version only its own train's builds.
    private var train: String { state.manifest.versionName(for: .apple) ?? "" }

    /// The newest first, because `appleStoreBuilds` sorts by upload date and
    /// falls back to the build number.
    private var visible: [UploadService.RemoteBuild] { Self.window(builds, shown: shown) }

    /// A static, so the rule can be tested without a view around it.
    static func window(_ builds: [UploadService.RemoteBuild],
                       shown: Int) -> [UploadService.RemoteBuild] {
        Array(builds.prefix(max(0, shown)))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { build in
                row(build)
                if build.id != visible.last?.id { Hairline() }
            }
            if builds.count > shown { more }
        }
    }

    /// The next ten, and how far down the list this is.
    ///
    /// The count is said because the list is now a window onto something
    /// longer, and a developer looking for a build from March needs to know
    /// whether it is worth pressing this eleven times.
    private var more: some View {
        let remaining = builds.count - shown
        return VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                QuietButton(title: "Show \(min(Self.page, remaining)) more") {
                    shown += Self.page
                }
                Text("\(shown) of \(builds.count) builds")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                Spacer(minLength: 8)
                if remaining > Self.page {
                    QuietButton(title: "Show all \(builds.count)") { shown = builds.count }
                }
            }
            .padding(.top, 9)
        }
    }

    private func row(_ build: UploadService.RemoteBuild) -> some View {
        let chosen = build.number == state.chosenAppleBuildNumber
            && (train.isEmpty || build.version == train)
        let attached = build.id == state.actualState.apple?.attachedBuildId
        // Apple takes no build of another version, so the row says so instead
        // of offering a choice that the store would refuse.
        let otherTrain = !train.isEmpty && build.version != train
        // A build one version already holds is not one Apple lets another take.
        // The chip says which version has it; a button beside that sentence
        // would be offering a write the store refuses.
        let free = build.versionState == nil || attached
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(build.version) (\(build.number))")
                .font(Theme.mono(11.5))
                .frame(minWidth: Theme.scaled(110), alignment: .leading)
            statePill(build)
            if attached {
                StatePill(text: "On the version", foreground: Theme.accent,
                          background: Theme.accentBg)
            }
            if let uploaded = build.uploaded {
                Text(uploaded.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 8)
            if otherTrain {
                Text("version \(build.version)")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            } else if chosen {
                QuietButton(title: "Let the app choose") { state.chooseAppleBuild(nil) }
            } else if build.processed, !build.expired, free {
                QuietButton(title: "Ship this build") { state.chooseAppleBuild(build) }
            }
        }
        .padding(.vertical, 7)
    }

    /// What became of one build, in the words the rest of the app uses.
    ///
    /// Every processed build read "Ready", including the one that shipped a
    /// year ago and the one a reviewer is reading right now. Processing is what
    /// the store did to the file; what a developer comes to this list for is
    /// what became of the build, and that is the state of the version holding
    /// it. So the version answers first, in `AppleStanding`'s vocabulary, which
    /// is the same one the sidebar chip and the Build tab already speak.
    ///
    /// The file's own words are left for a build no version has taken: still
    /// processing, refused by the store, expired past Apple's ninety days, or
    /// ready and free for a version to take.
    @ViewBuilder
    private func statePill(_ build: UploadService.RemoteBuild) -> some View {
        if build.versionState == "REPLACED_WITH_NEW_VERSION" {
            // The one word this list takes differently from the app chip. An
            // app whose newest version replaced an older one is still live, so
            // the chip beside its name says Live. A build is not the app: the
            // superseded one shipped and is not what customers are running, and
            // two rows both reading "Live" is the answer this list exists to
            // stop giving.
            StatePill(text: "Replaced", foreground: Theme.text3, background: Theme.sunken)
        } else if let version = build.versionState {
            let standing = AppleStanding(state: version)
            StatePill(text: standing.label, foreground: standing.tint,
                      background: standing.fill)
        } else if !build.processed {
            let refused = ["FAILED", "INVALID"].contains(build.state)
            StatePill(text: refused ? "Refused" : "Processing",
                      foreground: refused ? Theme.red : Theme.yellow,
                      background: refused ? Theme.redBg : Theme.yellowBg)
        } else if build.expired {
            StatePill(text: "Expired", foreground: Theme.text3, background: Theme.sunken)
        } else {
            StatePill(text: "Ready", foreground: Theme.green, background: Theme.greenBg)
        }
    }

    /// A number in the manifest that the fetched list cannot account for. It is
    /// the state a typed version change leaves behind, and the plan reports it
    /// as no build at all three tabs away from here.
    private func chosenLine(_ chosen: String) -> some View {
        let found = builds.contains { $0.number == chosen && $0.version == train }
        // The row carrying "Let the app choose" may be past the window. This
        // panel exists to ship a build that is not the newest, so the chosen one
        // is exactly the row most likely to fall off the end, and undoing the
        // choice may not depend on pressing Show more until it comes back.
        let onScreen = visible.contains { $0.number == chosen && $0.version == train }
        return Group {
            if loaded, !found {
                WarningNote("store.yaml ships build \(chosen)\(train.isEmpty ? "" : " of version \(train)") and App Store Connect holds no processed build with that number. Pick another one, or let the app choose.")
            } else {
                HStack(spacing: 8) {
                    Text("store.yaml ships build \(chosen)\(train.isEmpty ? "" : " of version \(train)").")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    if found, !onScreen {
                        QuietButton(title: "Let the app choose") { state.chooseAppleBuild(nil) }
                    }
                    Spacer(minLength: 8)
                }
            }
        }
    }

    private func load() {
        loading = true
        error = nil
        // Back to the newest ten. A second fetch is a fresh answer, and keeping
        // a window the developer opened against the last one would leave rows
        // showing for builds that are no longer in the list.
        shown = Self.page
        // The key at the moment of the call. The developer is free to switch
        // app while Apple answers, and rows fetched for the app they left must
        // not be marked as this one's.
        let key = taskKey
        Task {
            do {
                builds = try await state.appleStoreBuilds()
                loadedKey = key
            } catch {
                self.error = error.localizedDescription
                loadedKey = nil
            }
            loading = false
        }
    }
}

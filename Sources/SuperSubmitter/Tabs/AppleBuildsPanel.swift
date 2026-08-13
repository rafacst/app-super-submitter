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
    @State private var loaded = false
    @State private var error: String?
    @State private var builds: [UploadService.RemoteBuild] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            NoteWithAction(note) {
                QuietButton(title: loading ? "Fetching…" : "Fetch the builds") { load() }
                    .disabled(loading)
            }
            .font(Theme.font(size: 11.5))

            if let error { WarningNote(error) }
            if loaded, builds.isEmpty {
                Text("App Store Connect holds no build for this app on \(state.applePlatform == .macOS ? "macOS" : "iOS") yet.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            if !builds.isEmpty { list }
            if let chosen = state.chosenAppleBuildNumber, !chosen.isEmpty { chosenLine(chosen) }
        }
        .storePanel(padding: 14, horizontal: 15)
        .fieldAnchor("build.storeBuilds")
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

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(builds) { build in
                row(build)
                if build.id != builds.last?.id { Hairline() }
            }
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
        return Group {
            if loaded, !found {
                WarningNote("store.yaml ships build \(chosen)\(train.isEmpty ? "" : " of version \(train)") and App Store Connect holds no processed build with that number. Pick another one, or let the app choose.")
            } else {
                Text("store.yaml ships build \(chosen)\(train.isEmpty ? "" : " of version \(train)").")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
        }
    }

    private func load() {
        loading = true
        error = nil
        Task {
            do {
                builds = try await state.appleStoreBuilds()
                loaded = true
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

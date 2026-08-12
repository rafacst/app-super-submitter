import AppKit
import SubmitKit
import SwiftUI

/// Internal app sharing, on the Beta testing tab.
///
/// It is the nearest thing Google has to handing one person a build: the
/// upload stays off the store, with no edit, no track and no version code, so
/// it collides with nothing a plan prepared and reaches whoever holds the
/// link. It used to sit inside the Build tab's tooling fold, beside the
/// diagnostics, where the one feature that gives a tester a build was filed
/// under maintenance.
struct InternalSharingPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var error: String?
    @State private var shared: GoogleActionsClient.SharedArtifact?

    private var artifact: (path: String, isBundle: Bool)? { state.googleSharableArtifact }

    var body: some View {
        Section_("Internal app sharing", icon: "link.badge.plus", tint: Theme.teal,
                 anchor: "beta.internalSharing") {
            VStack(alignment: .leading, spacing: 10) {
                NoteWithAction("Upload the Android build and get a private install link. This writes no draft and it uses no version code.") {
                    QuietButton(title: busy ? "Uploading…" : "Upload and share") { share() }
                        .disabled(busy || artifact == nil || state.googleActionPackage == nil)
                }

                if let artifact {
                    Text("\(artifact.isBundle ? "App Bundle" : "APK") · \(artifact.path)")
                        .font(Theme.mono(11)).foregroundStyle(Theme.text3)
                        .textSelection(.enabled)
                } else {
                    Label("The manifest names no Android build yet.",
                          systemImage: "info.circle")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                }

                if let error { ErrorLine(text: error) }

                if let shared {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Install link").font(Theme.font(size: 12, weight: .semibold))
                        HStack(spacing: 8) {
                            Text(shared.downloadUrl).font(Theme.mono(11))
                                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(shared.downloadUrl,
                                                               forType: .string)
                            }
                            .controlSize(.small)
                            if let url = URL(string: shared.downloadUrl) {
                                Link("Open", destination: url).font(Theme.font(size: 11.5))
                            }
                        }
                        if let sha = shared.sha256 {
                            Text("sha256 \(sha)").font(Theme.mono(10))
                                .foregroundStyle(Theme.text3)
                                .textSelection(.enabled)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .storePanel(padding: 14)
        }
    }

    private func share() {
        track($busy, $error) { shared = try await state.shareGoogleArtifactInternally() }
    }
}

// MARK: - Reviews and app recovery, on tab 9

/// The two Google surfaces that only matter once the app is live: what people
/// wrote about it, and the remote fix for a bad release.
///
/// Both sit behind a button rather than on tab load, the same rule that
/// `StoreDiagnosticsPanel` follows: neither call is free, and neither answers
/// a question the tab asks by itself.
/// The APKs Google signs and serves.
///
/// Play re-signs what it delivers, so the file on a device is never the App
/// Bundle that went up. A developer reading a crash report from the store
/// needs these files, and no other part of the app could fetch them.
struct GeneratedAPKPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var apks: [GoogleActionsClient.GeneratedAPK] = []
    @State private var saved: [String: URL] = [:]

    var body: some View {
        Section_("The APKs Google signs", icon: "square.and.arrow.down", tint: Theme.playBlue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Play re-signs every build it serves. These are the files that match a crash report from the store. Reading and downloading change nothing.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch the APKs") { load() }
                        .disabled(busy || state.googleLatestVersionCode == nil)
                }

                if state.googleLatestVersionCode == nil {
                    Text("Read the stores on the Summary tab first, so this knows which version code to ask for.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                }
                if let error { ErrorLine(text: error) }
                if loaded, apks.isEmpty {
                    Text("Google generated no APK for this version code.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                }
                ForEach(apks) { apk in
                    HStack(spacing: 9) {
                        Image(systemName: "shippingbox")
                            .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        Text(apk.kind).font(Theme.mono(11))
                        Text("version code \(apk.versionCode)")
                            .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        Spacer(minLength: 8)
                        if let file = saved[apk.id] {
                            Button("Show") {
                                NSWorkspace.shared.activateFileViewerSelecting([file])
                            }
                            .controlSize(.small)
                        } else {
                            Button("Download") { download(apk) }
                                .controlSize(.small).disabled(busy)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .storePanel(padding: 14)
        }
    }

    private func load() {
        guard let code = state.googleLatestVersionCode else { return }
        track($busy, $error) {
            apks = try await state.googleGeneratedAPKs(versionCode: code)
            loaded = true
        }
    }

    private func download(_ apk: GoogleActionsClient.GeneratedAPK) {
        track($busy, $error) { saved[apk.id] = try await state.downloadGoogleAPK(apk) }
    }
}

struct GoogleReviewsPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var reviews: [GoogleActionsClient.Review] = []
    @State private var drafts: [String: String] = [:]
    @State private var confirming: GoogleActionsClient.Review?

    var body: some View {
        Section_("Google Play reviews", icon: "star.bubble", tint: Theme.yellow) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The reviews of the last week. A reply is public, and a second reply replaces the first.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch reviews") { load() }
                        .disabled(busy || state.googleActionPackage == nil)
                }

                if let error { ErrorLine(text: error) }
                if loaded, reviews.isEmpty {
                    Text("Google reports no review in the last week.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                }
                ForEach(reviews) { review in
                    reviewRow(review)
                    if review.id != reviews.last?.id {
                        Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                    }
                }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Publish this reply?", isPresented: $confirming.isPresent,
                            presenting: confirming) { review in
            Button("Publish the reply", role: .destructive) { send(review) }
            Button("Cancel", role: .cancel) {}
        } message: { review in
            Text("Every Play Store visitor reads it under \(review.authorName ?? "this review"). A second reply replaces it, and no call removes it.")
        }
    }

    @ViewBuilder private func reviewRow(_ review: GoogleActionsClient.Review) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(review.authorName ?? "Anonymous")
                    .font(Theme.font(size: 12, weight: .semibold))
                if let stars = review.starRating {
                    Text(String(repeating: "★", count: max(0, min(5, stars))))
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.yellow)
                }
                Spacer()
                if let date = review.lastModified {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                }
            }
            if let text = review.text, !text.isEmpty {
                Text(text).font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = review.developerReply, !reply.isEmpty {
                Label(reply, systemImage: "arrowshape.turn.up.left")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TextField("Write a reply, 350 characters",
                          text: draftBinding(review.id), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .returnInsertsLineBreak()
                    .font(Theme.font(size: 12))
                    .lineLimit(1...3)
                let draft = (drafts[review.id] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Text("\(draft.count)/350")
                    .font(Theme.mono(10))
                    .foregroundStyle(draft.count > 350 ? Theme.red : Theme.text3)
                Button("Reply") { confirming = review }
                    .controlSize(.small)
                    .disabled(busy || draft.isEmpty || draft.count > 350)
            }
        }
        .padding(.vertical, 6)
    }

    private func draftBinding(_ id: String) -> Binding<String> {
        Binding(get: { drafts[id] ?? "" }, set: { drafts[id] = $0 })
    }

    private func load() {
        track($busy, $error) {
            reviews = try await state.googleReviews()
            loaded = true
        }
    }

    private func send(_ review: GoogleActionsClient.Review) {
        let text = (drafts[review.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        track($busy, $error) {
            try await state.replyToGoogleReview(id: review.id, text: text)
            drafts[review.id] = ""
            // Re-read, so the row shows what Google actually stored rather
            // than what this app sent.
            reviews = try await state.googleReviews()
        }
    }
}

struct GoogleRecoveryPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var actions: [GoogleActionsClient.RecoveryAction] = []
    @State private var deploying: GoogleActionsClient.RecoveryAction?

    var body: some View {
        Section_("Google Play app recovery", icon: "cross.case", tint: Theme.red) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The remote fix for a bad release. A draft reaches nobody. A deploy reaches every targeted installation, and no call takes it back.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Working…" : "Fetch recoveries") { load() }
                        .disabled(busy || state.googleActionPackage == nil)
                }

                if let error { ErrorLine(text: error) }
                if loaded {
                    if actions.isEmpty {
                        Text("Google holds no recovery action for this app.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    }
                    ForEach(actions) { action in recoveryRow(action) }
                    HStack {
                        Spacer()
                        Button("Create a draft recovery") { createDraft() }
                            .controlSize(.small)
                            .disabled(busy)
                    }
                }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Deploy this recovery?", isPresented: $deploying.isPresent,
                            presenting: deploying) { action in
            Button("Deploy to every targeted device", role: .destructive) { deploy(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text("Recovery \(action.id) goes out to every installation it targets. Cancelling later stops a further rollout, and it restores nothing that already landed.")
        }
    }

    @ViewBuilder private func recoveryRow(_ action: GoogleActionsClient.RecoveryAction) -> some View {
        let live = action.deployTime != nil && action.cancelTime == nil
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(action.id).font(Theme.mono(11.5)).textSelection(.enabled)
                    Text(Self.statusLabel(action))
                        .font(Theme.font(size: 10.5, weight: .semibold))
                        .foregroundStyle(live ? Theme.red : Theme.text3)
                }
                if !action.targetedVersionCodes.isEmpty {
                    Text("version codes \(action.targetedVersionCodes.map(String.init).joined(separator: ", "))")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                }
            }
            Spacer()
            if live {
                Button("Cancel rollout") { cancel(action) }
                    .controlSize(.small).disabled(busy)
            } else if action.cancelTime == nil {
                Button("Target everyone") { widen(action) }
                    .controlSize(.small).disabled(busy)
                Button("Deploy") { deploying = action }
                    .controlSize(.small).disabled(busy)
            }
        }
        .padding(.vertical, 5)
    }

    static func statusLabel(_ action: GoogleActionsClient.RecoveryAction) -> String {
        if action.cancelTime != nil { return "CANCELLED" }
        if action.deployTime != nil { return "LIVE" }
        return action.status ?? "DRAFT"
    }

    private func load() { track($busy, $error) { actions = try await state.googleRecoveryActions(); loaded = true } }

    private func createDraft() {
        track($busy, $error) {
            _ = try await state.createGoogleRecoveryDraft()
            actions = try await state.googleRecoveryActions()
        }
    }

    private func deploy(_ action: GoogleActionsClient.RecoveryAction) {
        track($busy, $error) {
            try await state.deployGoogleRecovery(id: action.id)
            actions = try await state.googleRecoveryActions()
        }
    }

    private func cancel(_ action: GoogleActionsClient.RecoveryAction) {
        track($busy, $error) {
            try await state.cancelGoogleRecovery(id: action.id)
            actions = try await state.googleRecoveryActions()
        }
    }

    private func widen(_ action: GoogleActionsClient.RecoveryAction) {
        track($busy, $error) {
            try await state.widenGoogleRecovery(id: action.id)
            actions = try await state.googleRecoveryActions()
        }
    }
}

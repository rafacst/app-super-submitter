import SubmitKit
import SwiftUI

/// The App Store twin of `GoogleReviewsPanel`.
///
/// Google Play had a reviews panel and the App Store had none, so an Apple
/// developer had to open App Store Connect for the one job the API supports.
/// The two sit side by side on the Reviews tab of Managing now.
struct AppStoreActionsPanel: View {
    var body: some View {
        AppleReviewsPanel()
    }
}

private struct AppleReviewsPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var reviews: [AppleActionsClient.Review] = []
    @State private var drafts: [String: String] = [:]
    @State private var confirming: AppleActionsClient.Review?

    private var limit: Int { AppleActionsClient.replyLimit }

    var body: some View {
        Section_("App Store reviews", icon: "star.bubble", tint: Theme.orange) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The newest reviews. A reply is public, and Apple keeps one reply per review, so a second one replaces the first.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch reviews") { load() }
                        .disabled(busy || state.appleActionAppID == nil)
                }

                if let error { ErrorLine(text: error) }
                if loaded, reviews.isEmpty {
                    Text("Apple reports no review for this app.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
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
            Text("Every App Store visitor reads it under \(review.authorName ?? "this review"). It replaces any reply that is there now.")
        }
    }

    @ViewBuilder private func reviewRow(_ review: AppleActionsClient.Review) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(review.authorName ?? "Anonymous")
                    .font(.system(size: 12, weight: .semibold))
                if let stars = review.starRating {
                    Text(String(repeating: "★", count: max(0, min(5, stars))))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.yellow)
                }
                if let territory = review.territory {
                    Text(territory).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                }
                Spacer()
                if let date = review.lastModified {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
            }
            if let title = review.title, !title.isEmpty {
                Text(title).font(.system(size: 12, weight: .medium))
            }
            if let text = review.text, !text.isEmpty {
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = review.developerReply, !reply.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Label(reply, systemImage: "arrowshape.turn.up.left")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let responseId = review.responseId {
                        Button("Remove") { remove(responseId) }
                            .controlSize(.small)
                            .disabled(busy)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Write a reply", text: draftBinding(review.id), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .lineLimit(1...4)
                let draft = (drafts[review.id] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Text("\(draft.count)/\(limit)")
                    .font(Theme.mono(10))
                    .foregroundStyle(draft.count > limit ? Theme.red : Theme.text3)
                Button(review.responseId == nil ? "Reply" : "Replace") { confirming = review }
                    .controlSize(.small)
                    .disabled(busy || draft.isEmpty || draft.count > limit)
            }
        }
        .padding(.vertical, 6)
    }

    private func draftBinding(_ id: String) -> Binding<String> {
        Binding(get: { drafts[id] ?? "" }, set: { drafts[id] = $0 })
    }

    private func load() {
        track($busy, $error) {
            reviews = try await state.appleReviews()
            loaded = true
        }
    }

    private func send(_ review: AppleActionsClient.Review) {
        let text = (drafts[review.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        run {
            try await state.replyToAppleReview(id: review.id, responseId: review.responseId,
                                               text: text)
            drafts[review.id] = ""
        }
    }

    private func remove(_ responseId: String) {
        run { try await state.removeAppleReviewReply(responseId: responseId) }
    }

    /// Every write re-reads afterwards, so a row shows what Apple stored
    /// rather than what this app sent.
    private func run(_ work: @escaping () async throws -> Void) {
        track($busy, $error) {
            try await work()
            reviews = try await state.appleReviews()
        }
    }
}

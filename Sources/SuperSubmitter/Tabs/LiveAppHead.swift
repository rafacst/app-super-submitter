import SubmitKit
import SwiftUI

/// The head of the Live app tab: one line of news, then one card per store.
///
/// The tab was a column of panels, each with a Fetch button of its own, and a
/// developer who wanted to know how the shipped app was doing pressed four of
/// them and then read four paragraphs to find three numbers. The question the
/// tab asks is "what are the customers seeing", and the answer is a number per
/// store, so the numbers come first and the panels that produce them stay
/// underneath for the detail.
///
/// It reads. Nothing here writes, and the strip says so, because every other
/// tab in this app has a button that changes a store.
///
/// **What is not here, and why.** The design's cards carry a star rating and a
/// rating count for each store. Neither store publishes one: Apple's reference
/// has `CustomerReview`, which is one review with one rating, and no app-level
/// summary anywhere; the Play Developer API has no ratings resource, and the
/// Reporting API metric sets are rates. Averaging the reviews the app fetched
/// would be a sample of a page and not the store's figure, so the cards carry
/// the numbers the stores really answer and no others.
struct LiveAppHead: View {
    @Environment(AppState.self) private var state

    @State private var busy = false
    @State private var loaded = false
    @State private var apple: [StoreVitalsClient.Metric] = []
    @State private var google: [StoreVitalsClient.Metric] = []
    @State private var failures: [String] = []
    @State private var change: StoreVitalsClient.RateChange?
    @State private var waiting: [Store: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            strip
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { cards }
                VStack(alignment: .leading, spacing: 12) { cards }
            }
            ForEach(failures, id: \.self) { failure in
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The one line of news

    private var strip: some View {
        HStack(spacing: 10) {
            if let change {
                Circle().fill(change.isWorse ? Theme.orange : Theme.green)
                    .frame(width: 7, height: 7)
                Text(change.line)
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if loaded {
                Text("Both stores answered.")
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 8)
            // The one claim this tab makes about itself, and it earns its place:
            // every other tab has a button that changes a store.
            Text("Everything on this tab is a read")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
            if busy { Spinner() }
            QuietButton(title: busy ? "Reading…" : "Read both stores") { load() }
                .disabled(busy || state.stores.isEmpty)
        }
    }

    // MARK: - A card per store

    @ViewBuilder private var cards: some View {
        ForEach(Store.allCases.filter(state.stores.contains)) { store in
            card(store).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func card(_ store: Store) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                StoreLabel(store: store, size: 12.5)
                if let version = version(store) {
                    Text(verbatim: "· \(version)")
                        .font(Theme.font(size: 12.5)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            let figures = figures(store)
            if figures.isEmpty {
                Text(loaded
                     ? "\(store.storeName) reports no measurement yet. It needs a release that enough devices have run."
                     : "Press Read both stores.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Wrapping, because three figures at 21 points do not fit a
                // half-width card on a narrow window and a clipped number is
                // worse than a wrapped one.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) { blocks(figures) }
                    VStack(alignment: .leading, spacing: 9) { blocks(figures) }
                }
            }
        }
        .storePanel(padding: 13)
    }

    @ViewBuilder private func blocks(_ figures: [Figure]) -> some View {
        ForEach(figures) { figure in
            VStack(alignment: .leading, spacing: 2) {
                Text(figure.value)
                    .font(Theme.font(size: 20, weight: .semibold))
                    .foregroundStyle(figure.warns ? Theme.orange : Theme.text)
                Text(figure.caption)
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(figure.value) \(figure.caption)")
        }
    }

    /// One headline number on a card.
    private struct Figure: Identifiable {
        let value: String
        let caption: String
        var warns = false

        var id: String { caption }
    }

    /// The version each store is answering about.
    ///
    /// Apple keys its metrics to the attached build and Google keys its rates
    /// to a version code, so the two cards name different things and each names
    /// its own.
    private func version(_ store: Store) -> String? {
        switch store {
        case .apple:
            let apple = state.actualState.apple
            return apple?.liveVersionString ?? apple?.versionString
        // Google keys a rate to a version code, so the card names the newest
        // code the read found rather than the version name Apple uses.
        case .google:
            return state.actualState.google?.highestVersionCode.map(String.init)
        }
    }

    /// What the store really answered, as headline numbers.
    ///
    /// The metric rows keep their full list in the panel below. This picks the
    /// one or two a developer reads first and leaves the rest where they were.
    private func figures(_ store: Store) -> [Figure] {
        var result: [Figure] = []
        switch store {
        case .apple:
            if let launch = apple.first(where: { $0.name.lowercased().contains("launch") }) {
                result.append(Figure(value: launch.value,
                                     caption: launch.detail.map { "launch · \($0)" } ?? "launch"))
            } else if let first = apple.first {
                result.append(Figure(value: first.value, caption: first.name.lowercased()))
            }
        case .google:
            for metric in google.prefix(2) {
                result.append(Figure(
                    value: metric.value,
                    caption: metric.name.lowercased()
                        .replacingOccurrences(of: "user-perceived ", with: "")
                        + (metric.detail.map { " · \($0)" } ?? ""),
                    warns: metric.name.contains("crash") && change?.isWorse == true))
            }
        }
        if let count = waiting[store] {
            result.append(Figure(value: "\(count)",
                                 caption: count == 1 ? "review to answer" : "reviews to answer"))
        }
        return result
    }

    // MARK: - The read

    /// Every read this tab's head needs, in one press.
    ///
    /// The panels below keep their own buttons. Pressing both reads the same
    /// thing twice, which costs a request and no correctness: each panel owns
    /// the detail it draws and this owns the headline.
    private func load() {
        busy = true
        Task {
            let vitals = await state.storeVitals()
            apple = vitals.apple
            google = vitals.google
            failures = vitals.failures
            change = await state.googleCrashRateChange()
            waiting = await reviewsWaiting()
            loaded = true
            busy = false
        }
    }

    /// How many reviews have no reply yet.
    ///
    /// Bounded by what each store returns: Apple answers a newest-first page
    /// and Google answers the last week. The caption says "reviews to answer"
    /// rather than a total, because a total is not what either store gave.
    private func reviewsWaiting() async -> [Store: Int] {
        var result: [Store: Int] = [:]
        if state.stores.contains(.apple), let reviews = try? await state.appleReviews() {
            result[.apple] = reviews.filter { $0.responseId == nil }.count
        }
        if state.stores.contains(.google), let reviews = try? await state.googleReviews() {
            result[.google] = reviews.filter {
                ($0.developerReply ?? "").isEmpty
            }.count
        }
        return result
    }
}

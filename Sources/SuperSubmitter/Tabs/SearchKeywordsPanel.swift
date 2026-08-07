import SubmitKit
import SwiftUI

/// Which custom product page the App Store search reaches.
///
/// This is **not** the Keywords field above it. That one is a hundred
/// characters of comma-separated text and the manifest owns it. This links a
/// word from that field to a custom product page, and Apple opened those to
/// organic search in July 2025. A customer who searches a linked word lands on
/// that page, with the screenshots written for that word, instead of on the
/// default product page.
///
/// Apple publishes no way to create a keyword. The pool comes from the
/// Keywords field of the latest approved version, so this panel links what the
/// account already holds and invents nothing.
struct SearchKeywordsPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var pool: [String] = []
    @State private var targets: [AppleKeywordsClient.Target] = []
    @State private var linked: [String: [String]] = [:]
    @State private var confirming: Change?

    /// One link or unlink, held until the developer confirms it.
    struct Change: Identifiable {
        var id: String { "\(target.id)/\(keyword)/\(link)" }
        let keyword: String
        let target: AppleKeywordsClient.Target
        let link: Bool
    }

    var body: some View {
        Section_("Search keywords", icon: "magnifyingglass", tint: Theme.teal,
                 anchor: "details.searchKeywords") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Send one search term to one custom product page. A customer who searches a linked word reaches that page instead of the default one. The words come from the Keywords field of your latest approved version, and Apple publishes no way to add one.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch the keywords") { load() }
                        .disabled(busy || state.appleActionAppID == nil)
                }

                if let error { ErrorLine(text: error) }
                if loaded, pool.isEmpty {
                    Text("Your account holds no search keyword for this app. Apple builds the pool from the Keywords field of the latest approved version, so it stays empty until one is approved.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loaded, !pool.isEmpty, targets.isEmpty {
                    Text("This app has no custom product page. Add one under Marketing, apply it, and each page appears here with its own keywords.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(targets) { target in targetBlock(target) }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Change what the search reaches?",
                            isPresented: $confirming.isPresent, presenting: confirming) { change in
            Button(change.link ? "Link the keyword" : "Unlink the keyword",
                   role: change.link ? nil : .destructive) { apply(change) }
            Button("Cancel", role: .cancel) {}
        } message: { change in
            Text(change.link
                 ? "A \(change.target.locale) search for this word reaches \(change.target.pageName) instead of your default product page. Apple Search Ads on the same word still wins."
                 : "A \(change.target.locale) search for this word returns to your default product page. The keyword stays in your account, so nothing is destroyed.")
        }
    }

    private func targetBlock(_ target: AppleKeywordsClient.Target) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(target.pageName).font(.system(size: 12, weight: .semibold))
                Text(target.locale).font(.system(size: 11)).foregroundStyle(Theme.text3)
                if !target.visible {
                    StatePill(text: "NOT VISIBLE", foreground: Theme.orange,
                              background: Theme.sunken)
                }
                Spacer(minLength: 0)
            }
            if !target.visible {
                Text("Apple reaches a page that is not visible from a campaign only. A keyword here meets nobody until you make the page visible.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(pool, id: \.self) { keyword in
                let isLinked = linked[target.id]?.contains(keyword) ?? false
                HStack(spacing: 9) {
                    Image(systemName: isLinked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isLinked ? Theme.green : Theme.text3)
                        .font(.system(size: 11))
                    Text(keyword).font(Theme.mono(10.5)).foregroundStyle(Theme.text2)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(isLinked ? "Unlink" : "Link") {
                        confirming = Change(keyword: keyword, target: target, link: !isLinked)
                    }
                    .controlSize(.small)
                    .disabled(busy)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func load() {
        track($busy, $error) {
            pool = try await state.appleKeywordPool()
            targets = try await state.appleKeywordTargets()
            linked = await state.appleLinkedKeywords(for: targets)
            loaded = true
        }
    }

    private func apply(_ change: Change) {
        track($busy, $error) {
            try await state.setAppleKeyword(change.keyword, targetID: change.target.id,
                                            linked: change.link)
            linked = await state.appleLinkedKeywords(for: targets)
        }
    }
}

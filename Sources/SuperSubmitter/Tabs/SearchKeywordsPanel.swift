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
                // One line, and the rule behind a disclosure. Three paragraphs
                // stood between the developer and the one list they came for,
                // and the panel read as an essay with a button in it. The rule
                // is still here in full for whoever needs it once.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Link an approved App Store keyword to a custom product page.")
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        // Outside the disclosure. The read is the task, and a
                        // button that has to be opened for is a button nobody
                        // finds.
                        QuietButton(title: busy ? "Fetching…" : "Fetch the keywords") { load() }
                            .disabled(busy || state.appleActionAppID == nil)
                    }

                    DisclosureGroup("How Apple supplies these keywords") {
                        Text("Apple builds this read-only list from the Keywords field of the latest approved version. The API links an existing keyword ID. It cannot create a keyword.")
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .font(Theme.font(size: 11.5))

                    platformRow
                }

                if let error { ErrorLine(text: error) }
                if loaded, pool.isEmpty {
                    Text("Your account holds no search keyword for this app. Apple builds the pool from the Keywords field of the latest approved version, so it stays empty until one is approved.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loaded, !pool.isEmpty, targets.isEmpty {
                    Text("This app has no custom product page. Add one under Marketing, apply it, and each page appears here with its own keywords.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(targets) { target in targetBlock(target) }
            }
            .storePanel(padding: 14)
        }
        // The list on screen belongs to the platform it was read for. Keeping
        // it after a switch would show the iOS words under the word macOS.
        .onChange(of: state.applePlatform) { _, _ in
            pool = []
            linked = [:]
            loaded = false
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

    /// Which platform's pool this is, and the way to the other one.
    ///
    /// Apple keeps a pool per platform and refuses the read without being told
    /// which, so this panel had to name it somewhere. The picker beside the app
    /// id is the same control and it is a rail away, on a panel about
    /// identifiers, which is not where somebody stands when they want the Mac
    /// keywords. It writes the same value, so the two never disagree.
    ///
    /// Nothing at all for an app on one platform: a choice of one is a control
    /// that asks a question with no second answer.
    @ViewBuilder
    private var platformRow: some View {
        if state.appleplatformChoices.count > 1 {
            HStack(spacing: 9) {
                Text("Apple keeps a pool for each platform. This reads")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                ApplePlatformPicker(width: 200)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func targetBlock(_ target: AppleKeywordsClient.Target) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(target.pageName).font(Theme.font(size: 12, weight: .semibold))
                Text(target.locale).font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                if !target.visible {
                    StatePill(text: "NOT VISIBLE", foreground: Theme.orange,
                              background: Theme.sunken)
                }
                Spacer(minLength: 0)
            }
            if !target.visible {
                Text("Apple reaches a page that is not visible from a campaign only. A keyword here meets nobody until you make the page visible.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(pool, id: \.self) { keyword in
                let isLinked = linked[target.id]?.contains(keyword) ?? false
                HStack(spacing: 9) {
                    Image(systemName: isLinked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isLinked ? Theme.green : Theme.text3)
                        .font(Theme.font(size: 11))
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

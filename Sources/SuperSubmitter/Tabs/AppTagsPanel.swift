import SubmitKit
import SwiftUI

/// The labels the App Store puts on the app by itself.
///
/// Every other field on this tab is the developer's own words. These are not:
/// Apple derives them from what the app is, and they steer where the store
/// shows it. They appear nowhere else in this app, and nothing in `store.yaml`
/// holds them, because the store writes them and not the manifest.
///
/// The developer cannot create one and no call deletes one. The one control
/// Apple publishes is whether a tag is shown on the product page, which is how
/// a tag that misrepresents the app is dealt with. Hiding one is reversible:
/// Apple keeps the tag, and showing it again is the same call.
struct AppTagsPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var tags: [AppleActionsClient.Tag] = []
    @State private var hiding: AppleActionsClient.Tag?

    var body: some View {
        Section_("App Store tags", icon: "tag", tint: Theme.green,
                 anchor: "details.appTags") {
            VStack(alignment: .leading, spacing: 9) {
                // Who owns a tag and what a hide undoes was said three times,
                // once per paragraph, above a list that is usually five rows
                // long. It is said once now, and the rule keeps its own line
                // behind a disclosure.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Show or hide the tags that Apple assigned to this app.")
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        QuietButton(title: busy ? "Fetching…" : "Fetch the tags") { load() }
                            .disabled(busy || state.appleActionAppID == nil)
                    }

                    DisclosureGroup("How App Store tags work") {
                        Text("Apple creates the tags. The API only changes visibleInAppStore. Hiding a tag is reversible, and store.yaml does not store it.")
                            .font(Theme.font(size: 11.5))
                            .foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .font(Theme.font(size: 11.5))
                }

                if let error { ErrorLine(text: error) }
                if loaded, tags.isEmpty {
                    Text("Apple has put no tag on this app. Tags arrive with a review, so a first submission has none until Apple has looked at it.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(tags) { tag in
                    HStack(spacing: 9) {
                        Text(tag.name).font(Theme.font(size: 12))
                        if !tag.visibleInAppStore {
                            StatePill(text: "HIDDEN", foreground: Theme.text3,
                                      background: Theme.sunken)
                        }
                        Spacer(minLength: 8)
                        Button(tag.visibleInAppStore ? "Take it off the page" : "Show it again") {
                            if tag.visibleInAppStore { hiding = tag } else { show(tag) }
                        }
                        .controlSize(.small).disabled(busy)
                    }
                }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Take this tag off the page?", isPresented: $hiding.isPresent,
                            presenting: hiding) { tag in
            Button("Take it off", role: .destructive) { hide(tag) }
            Button("Cancel", role: .cancel) {}
        } message: { tag in
            Text("No App Store visitor sees \(tag.name) on the product page, and the store stops showing the app under it. Apple keeps the tag, so showing it again is one button.")
        }
    }

    private func load() {
        track($busy, $error) {
            tags = try await state.appleTags()
            loaded = true
        }
    }

    private func hide(_ tag: AppleActionsClient.Tag) { set(tag, visible: false) }
    private func show(_ tag: AppleActionsClient.Tag) { set(tag, visible: true) }

    private func set(_ tag: AppleActionsClient.Tag, visible: Bool) {
        track($busy, $error) {
            try await state.setAppleTagVisible(tag.id, visible: visible)
            tags = try await state.appleTags()
        }
    }
}

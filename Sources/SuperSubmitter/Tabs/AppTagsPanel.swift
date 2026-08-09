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
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Apple's own labels for what this app is. They are not keywords and not a category.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        QuietButton(title: busy ? "Fetching…" : "Fetch the tags") { load() }
                            .disabled(busy || state.appleActionAppID == nil)
                    }
                    Text("Apple writes them, App Store Connect holds them, and store.yaml never carries them. Apple describes a tag as a label that groups the app and decides which App Store territories feature it, so a wrong one costs the app the places it would be shown.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You cannot add a tag and nothing deletes one. The single control Apple publishes is whether a tag appears on the product page, and it goes both ways: taking one off is undone by putting it back.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
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

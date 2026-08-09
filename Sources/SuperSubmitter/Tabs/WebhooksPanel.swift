import SubmitKit
import SwiftUI

/// The other direction: Apple telling a server that something happened.
///
/// Every other panel in this app asks App Store Connect a question. A webhook
/// is the answer arriving on its own, in seconds rather than on the Release
/// tab's five-minute poll.
///
/// The panel is honest about its own limit. A Mac app is not running most of
/// the time, so the events go to whatever server the URL names and not to this
/// window. What this panel is for is configuring the hook and reading what
/// Apple already delivered, which is the only place a failing endpoint shows
/// itself at all.
struct WebhooksPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var hooks: [AppleWebhooksClient.Hook] = []
    @State private var deliveries: [String: [AppleWebhooksClient.Delivery]] = [:]
    @State private var open: Set<String> = []

    @State private var newName = ""
    @State private var newURL = ""
    @State private var newSecret = ""
    @State private var newEvents = "APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"
    @State private var confirmingCreate = false
    @State private var deleting: AppleWebhooksClient.Hook?

    var body: some View {
        Section_("Webhooks", icon: "bolt.horizontal", tint: Theme.purple) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let error { ErrorLine(text: error) }
                if loaded {
                    if hooks.isEmpty {
                        Text("This app has no webhook. Apple pushes nothing until one exists.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    }
                    ForEach(hooks) { hook in
                        Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                        hookRow(hook)
                    }
                    Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                    create
                }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Create this webhook?", isPresented: $confirmingCreate) {
            Button("Create the webhook") { send() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple sends every event you picked to \(newURL.trimmingCharacters(in: .whitespaces)) from now on. The secret goes to Apple and is never written to store.yaml or to this app's own files, so keep your copy.")
        }
        .confirmationDialog("Delete this webhook?", isPresented: $deleting.isPresent,
                            presenting: deleting) { hook in
            Button("Delete the webhook", role: .destructive) { remove(hook) }
            Button("Cancel", role: .cancel) {}
        } message: { hook in
            Text("Apple stops pushing to \(hook.url), and the secret goes with the configuration. A webhook that comes back is a new one with a new secret. Switching it off instead keeps both.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Apple pushes an event to your own server the moment it happens: a review state, a finished build, a tester's crash. This app configures the hook and reads the deliveries; the events reach the server, not this window.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            QuietButton(title: busy ? "Fetching…" : "Fetch the webhooks") { load() }
                .disabled(busy || state.appleActionAppID == nil)
        }
    }

    // MARK: - One webhook

    @ViewBuilder private func hookRow(_ hook: AppleWebhooksClient.Hook) -> some View {
        let expanded = open.contains(hook.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Button { toggle(hook) } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(Theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse the deliveries" : "Show the deliveries")

                Text(hook.name).font(Theme.font(size: 12, weight: .medium))
                if !hook.enabled {
                    StatePill(text: "OFF", foreground: Theme.text3, background: Theme.sunken)
                }
                Spacer(minLength: 8)
                Text("\(hook.eventTypes.count) events")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                Button(hook.enabled ? "Switch off" : "Switch on") {
                    setEnabled(hook, !hook.enabled)
                }
                .controlSize(.small).disabled(busy)
                Button("Send a test") { ping(hook) }
                    .controlSize(.small).disabled(busy || !hook.enabled)
                Button("Delete") { deleting = hook }
                    .controlSize(.small).disabled(busy)
            }
            Text(hook.url).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                .textSelection(.enabled).lineLimit(1)
            if expanded { deliveryBlock(hook) }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func deliveryBlock(_ hook: AppleWebhooksClient.Hook) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ChoiceText.summary(of: ChoiceText.text(from: hook.eventTypes),
                                    in: AppleWebhooksClient.eventTypes,
                                    empty: "No event"))
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            let rows = deliveries[hook.id] ?? []
            if rows.isEmpty {
                Text("Apple has delivered nothing yet.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            }
            ForEach(rows) { delivery in
                HStack(spacing: 8) {
                    Text(delivery.state?.lowercased() ?? "unknown")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(delivery.state == "SUCCEEDED" ? Theme.green
                                         : delivery.state == "PENDING" ? Theme.yellow : Theme.red)
                        .frame(width: 70, alignment: .leading)
                    if let status = delivery.responseStatus {
                        Text("HTTP \(status)").font(Theme.mono(10))
                            .foregroundStyle(Theme.text3)
                    }
                    if let message = delivery.errorMessage, !message.isEmpty {
                        Text(message).font(Theme.font(size: 10.5))
                            .foregroundStyle(Theme.orange).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let date = delivery.createdDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
        .padding(.leading, 23)
    }

    // MARK: - Making one

    private var create: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Add a webhook").font(Theme.font(size: 12, weight: .semibold))
            FieldRow {
                LabeledField("Name", width: 180) {
                    TextField("", text: $newName)
                }
                LabeledField("URL", note: "https only") {
                    TextField("https://example.com/hooks/appstore", text: $newURL)
                }
            }
            FieldRow {
                LabeledField("Secret",
                             note: "Your server verifies each delivery with it. It goes to Apple and nowhere else.",
                             width: 260) {
                    SecureField("", text: $newSecret)
                }
                LabeledField("Events") {
                    MultiChoiceField(text: $newEvents,
                                     choices: AppleWebhooksClient.eventTypes,
                                     emptyLabel: "Pick at least one event")
                }
            }
            HStack {
                Button("Create the webhook") { confirmingCreate = true }
                    .controlSize(.small)
                    .disabled(busy || newSecret.isEmpty
                              || !newURL.lowercased().hasPrefix("https://")
                              || ChoiceText.values(from: newEvents).isEmpty)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - The work

    private func load() {
        track($busy, $error) {
            hooks = try await state.appleWebhookList()
            loaded = true
        }
    }

    private func toggle(_ hook: AppleWebhooksClient.Hook) {
        if open.contains(hook.id) {
            open.remove(hook.id)
            return
        }
        open.insert(hook.id)
        guard deliveries[hook.id] == nil else { return }
        track($busy, $error) {
            deliveries[hook.id] = try await state.appleWebhooks().deliveries(hookID: hook.id)
        }
    }

    private func send() {
        track($busy, $error) {
            try await state.createAppleWebhook(
                name: newName, url: newURL.trimmingCharacters(in: .whitespacesAndNewlines),
                secret: newSecret, eventTypes: ChoiceText.values(from: newEvents))
            // The secret is gone from this app the moment Apple has it.
            newSecret = ""
            newName = ""
            newURL = ""
            hooks = try await state.appleWebhookList()
        }
    }

    private func setEnabled(_ hook: AppleWebhooksClient.Hook, _ enabled: Bool) {
        track($busy, $error) {
            try await state.appleWebhooks().setEnabled(hookID: hook.id, enabled)
            hooks = try await state.appleWebhookList()
        }
    }

    private func ping(_ hook: AppleWebhooksClient.Hook) {
        track($busy, $error) {
            try await state.appleWebhooks().ping(hookID: hook.id)
            deliveries[hook.id] = try await state.appleWebhooks().deliveries(hookID: hook.id)
            open.insert(hook.id)
        }
    }

    private func remove(_ hook: AppleWebhooksClient.Hook) {
        track($busy, $error) {
            try await state.appleWebhooks().delete(hookID: hook.id)
            hooks = try await state.appleWebhookList()
        }
    }
}

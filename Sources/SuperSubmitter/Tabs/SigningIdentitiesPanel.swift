import SubmitKit
import SwiftUI

/// When the signing identities lapse.
///
/// Every call behind this is a read. Nothing here revokes a certificate or
/// deletes a profile: a revoked certificate breaks every machine that signs
/// with it, so that stays in the Developer portal where one person owns the
/// consequence.
///
/// Two rows at the bottom write, and both are deliberate exceptions. A device
/// is a UDID on a list, and a tester whose phone is not on it cannot install a
/// build. A bundle ID is a name in a namespace, and it is the one bootstrap
/// step of a new app that Apple's API allows at all.
///
/// The value is the expiry. A certificate and a profile both lapse on a date
/// that nothing else in the app shows, and the first sign of a lapse is usually
/// a failed build.
struct SigningIdentitiesPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var items: [AppleProvisioningClient.Item] = []
    @State private var failures: [String] = []

    @State private var deviceName = ""
    @State private var deviceUDID = ""
    @State private var devicePlatform = "IOS"
    @State private var confirmingDevice = false

    @State private var bundleName = ""
    @State private var bundleIdentifier = ""
    @State private var bundlePlatform = "IOS"
    @State private var confirmingBundle = false

    var body: some View {
        Section_("Signing identities", icon: "seal", tint: Theme.purple) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The certificates, profiles, devices, and identifiers of the team, with the dates they lapse. Super Submitter reads these and revokes none.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Fetching…" : "Fetch the identities") { load() }
                        .disabled(busy)
                }

                ForEach(failures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loaded, items.isEmpty, failures.isEmpty {
                    Text("The account holds no signing identity yet.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                }
                if !expiring.isEmpty { expiryNote }

                if let error { ErrorLine(text: error) }

                ForEach(AppleProvisioningClient.Item.Kind.allCases, id: \.self) { kind in
                    let group = items.filter { $0.kind == kind }
                    if !group.isEmpty { block(kind, group) }
                }

                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                registerDevice
                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                addBundleID
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Register this device?", isPresented: $confirmingDevice) {
            Button("Register the device") { register() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It takes one slot of the yearly device quota, and Apple only clears that quota when the membership renews. Check the identifier before you spend the slot.")
        }
        .confirmationDialog("Create this bundle ID?", isPresented: $confirmingBundle) {
            Button("Create the bundle ID") { createBundle() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It reserves \(bundleIdentifier.trimmingCharacters(in: .whitespaces)) for this team, and no call here deletes one again. It does not create the App Store record: Apple publishes no call for that, so you still make the app once in App Store Connect.")
        }
    }

    // MARK: - The two writes

    /// A tester whose phone is not on this list cannot install a build, which
    /// is why this is the one provisioning write every team makes constantly.
    private var registerDevice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Register a device").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                TextField("Anna's iPhone", text: $deviceName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Device identifier", text: $deviceUDID)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
                Picker("", selection: $devicePlatform) {
                    ForEach(AppleProvisioningClient.platforms) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
                .frame(width: 170)
                Button("Register") { confirmingDevice = true }
                    .controlSize(.small)
                    .disabled(busy
                              || deviceName.trimmingCharacters(in: .whitespaces).isEmpty
                              || !AppleProvisioningClient.looksLikeAUDID(
                                deviceUDID.trimmingCharacters(in: .whitespaces)))
            }
            Text("Xcode shows the identifier under Window ▸ Devices and Simulators. It costs one slot of the yearly quota, so a typo is spent until the membership renews.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The closest thing to a "new app" call that Apple publishes. There is no
    /// `POST /v1/apps`, so the app record itself is still made by a person in
    /// App Store Connect, and this is the step before it.
    private var addBundleID: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Create a bundle ID").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                TextField("My App", text: $bundleName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                // No sample identifier in the box. `RuntimePlaceholderTests`
                // bans a placeholder dataset from the runtime sources, and a
                // fake bundle ID is one.
                TextField("Reverse-DNS identifier", text: $bundleIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
                Picker("", selection: $bundlePlatform) {
                    ForEach(AppleProvisioningClient.platforms) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
                .frame(width: 170)
                Button("Create") { confirmingBundle = true }
                    .controlSize(.small)
                    .disabled(busy || !AppleProvisioningClient.looksLikeABundleID(
                        bundleIdentifier.trimmingCharacters(in: .whitespaces)))
            }
            Text("Apple publishes no call that creates the App Store record, so this reserves the identifier and you make the app once in App Store Connect. Nothing here deletes one again.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The whole point of the panel, so it goes above the lists and not inside
    /// one of them.
    private var expiring: [AppleProvisioningClient.Item] {
        items.filter { $0.isExpired || $0.expiresSoon() }
    }

    private var expiryNote: some View {
        WarningNote(expiring.contains(where: \.isExpired)
            ? "\(expiring.count) of these have lapsed or lapse within 30 days. Renew them in the Developer portal before the next build."
            : "\(expiring.count) of these lapse within 30 days. Renew them in the Developer portal before the next build.")
    }

    private func block(_ kind: AppleProvisioningClient.Item.Kind,
                       _ group: [AppleProvisioningClient.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.system(size: 12, weight: .semibold))
            ForEach(group) { item in row(item) }
        }
        .padding(.vertical, 4)
    }

    private func row(_ item: AppleProvisioningClient.Item) -> some View {
        HStack(spacing: 9) {
            Text(item.name).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                .lineLimit(1)
            if let detail = item.detail {
                Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let platform = item.platform {
                Text(platform).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if let state = item.state {
                Text(state).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if let expiry = item.expiresAt {
                Text(expiry.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10.5))
                    .foregroundStyle(item.isExpired ? Theme.orange
                        : item.expiresSoon() ? Theme.orange : Theme.text3)
            }
        }
    }

    private func load() {
        busy = true
        Task {
            let result = await state.appleProvisioning()
            items = result.items
            failures = result.failures
            loaded = true
            busy = false
        }
    }

    /// Both writes re-read afterwards, so the list shows what Apple stored
    /// rather than what this app sent.
    private func register() {
        track($busy, $error) {
            try await state.registerAppleDevice(name: deviceName, platform: devicePlatform,
                                                udid: deviceUDID.trimmingCharacters(
                                                    in: .whitespacesAndNewlines))
            deviceName = ""
            deviceUDID = ""
            let result = await state.appleProvisioning()
            items = result.items
            failures = result.failures
            loaded = true
        }
    }

    private func createBundle() {
        track($busy, $error) {
            try await state.createAppleBundleID(
                name: bundleName,
                identifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                platform: bundlePlatform)
            bundleName = ""
            bundleIdentifier = ""
            let result = await state.appleProvisioning()
            items = result.items
            failures = result.failures
            loaded = true
        }
    }
}

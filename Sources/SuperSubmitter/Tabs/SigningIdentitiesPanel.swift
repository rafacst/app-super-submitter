import SubmitKit
import SwiftUI

/// When the signing identities lapse.
///
/// Every call behind this is a read. Nothing here revokes a certificate or
/// deletes a profile: a revoked certificate breaks every machine that signs
/// with it, so that stays in the Developer portal where one person owns the
/// consequence.
///
/// Two forms at the bottom write, and both are deliberate exceptions. A device
/// is a UDID on a list, and a tester whose phone is not on it cannot install a
/// build. A bundle ID is a name in a namespace, and it is the one bootstrap
/// step of a new app that Apple's API allows at all.
///
/// The value is the expiry. A certificate and a profile both lapse on a date
/// that nothing else in the app shows, and the first sign of a lapse is usually
/// a failed build.
///
/// **Everything is folded.** This panel lives in the build inspector, which is
/// a column about a third of the window wide, and a real team holds forty
/// identities. Drawn open, one fetch pushed the three panels above it off the
/// screen and buried the one line that matters, which is the count of the ones
/// that lapse. A group opens when the developer asks, or by itself when
/// something inside it is about to lapse.
struct SigningIdentitiesPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var items: [AppleProvisioningClient.Item] = []
    @State private var failures: [String] = []
    /// The groups that are open. A fetch fills it with the groups that hold
    /// something lapsing, so the panel opens on the problem and nothing else.
    @State private var open: Set<AppleProvisioningClient.Item.Kind> = []
    @State private var addOpen = false

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
                header
                ForEach(failures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error { ErrorLine(text: error) }
                if loaded, items.isEmpty, failures.isEmpty {
                    Text("The account holds no signing identity yet.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                }
                if !expiring.isEmpty { expiryNote }

                ForEach(AppleProvisioningClient.Item.Kind.allCases, id: \.self) { kind in
                    let group = items.filter { $0.kind == kind }
                    if !group.isEmpty { block(kind, group) }
                }

                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                addSomething
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

    /// The sentence and the button stack in this column rather than sharing a
    /// row. Side by side they left the sentence about four words wide.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The certificates, profiles, devices, and identifiers of the team, with the dates they lapse. Super Submitter reads these and revokes none.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                QuietButton(title: busy ? "Fetching…" : "Fetch the identities") { load() }
                    .disabled(busy)
                if loaded, !items.isEmpty {
                    Text("\(items.count) identities")
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - One folded group

    /// A group opens on a click, and on a fetch that found something lapsing
    /// inside it.
    ///
    /// `// ponytail: no inner scroll view. The fold is the fix, and a vertical
    /// // scroll inside the inspector's own vertical scroll steals the wheel
    /// // from it. A developer who opens Bundle IDs asked for the bundle IDs.`
    private func block(_ kind: AppleProvisioningClient.Item.Kind,
                       _ group: [AppleProvisioningClient.Item]) -> some View {
        DisclosureGroup(isExpanded: expansion(kind)) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Self.rows(kind, group)) { item in row(item) }
            }
            .padding(.top, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            groupLabel(kind, group)
        }
    }

    private func groupLabel(_ kind: AppleProvisioningClient.Item.Kind,
                            _ group: [AppleProvisioningClient.Item]) -> some View {
        let lapsing = group.filter { $0.isExpired || $0.expiresSoon() }.count
        return HStack(spacing: 7) {
            Image(systemName: kind.symbol)
                .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                .frame(width: 13)
            Text(kind.title).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 6)
            if lapsing > 0 {
                StatePill(text: "\(lapsing) LAPSING", foreground: Theme.orange,
                          background: Theme.sunken)
            }
            Text("\(group.count)").font(Theme.mono(10.5)).foregroundStyle(Theme.text3)
        }
        .contentShape(.rect)
    }

    /// The rows of one group.
    ///
    /// A capability is the exception. Apple returns one row per bundle ID that
    /// holds it and the read keeps no owner, so the raw list was "In app
    /// purchase" nine times down the column. They fold into one row per name
    /// with the count beside it.
    static func rows(_ kind: AppleProvisioningClient.Item.Kind,
                     _ group: [AppleProvisioningClient.Item]) -> [AppleProvisioningClient.Item] {
        guard kind == .capability else { return group }
        var seen: [String: Int] = [:]
        var order: [String] = []
        for item in group {
            if seen[item.name] == nil { order.append(item.name) }
            seen[item.name, default: 0] += 1
        }
        return order.map { name in
            var item = AppleProvisioningClient.Item(id: name, kind: .capability, name: name)
            if let count = seen[name], count > 1 { item.detail = "×\(count)" }
            return item
        }
    }

    /// Two lines, not five columns. A bundle identifier is 30 characters and a
    /// UDID is 40, and beside a name, a platform, a state, and a date in a
    /// third of a window every one of them was an ellipsis.
    private func row(_ item: AppleProvisioningClient.Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(item.name).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if let expiry = item.expiresAt {
                    Text(expiry.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10.5))
                        .foregroundStyle(item.isExpired || item.expiresSoon()
                                         ? Theme.orange : Theme.text3)
                }
            }
            if item.detail != nil || item.platform != nil || item.state != nil {
                HStack(spacing: 7) {
                    if let detail = item.detail {
                        Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 6)
                    if let platform = item.platform {
                        Text(platform).font(.system(size: 10))
                            .foregroundStyle(Theme.text3)
                    }
                    if let state = item.state {
                        Text(state).font(.system(size: 10)).foregroundStyle(Theme.text3)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - The two writes

    /// Both forms behind one fold. Neither is a thing a developer does on the
    /// way past, and open they were half the panel.
    private var addSomething: some View {
        DisclosureGroup(isExpanded: $addOpen) {
            VStack(alignment: .leading, spacing: 14) {
                registerDevice
                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                addBundleID
            }
            .padding(.top, 9)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    .frame(width: 13)
                Text("Register a device or create a bundle ID")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
    }

    /// A tester whose phone is not on this list cannot install a build, which
    /// is why this is the one provisioning write every team makes constantly.
    ///
    /// The fields stack. Four controls on one row put the button off the right
    /// edge of the inspector, where it could not be pressed at all.
    private var registerDevice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Register a device").font(.system(size: 11.5, weight: .medium))
            TextField("Anna's iPhone", text: $deviceName)
                .textFieldStyle(.roundedBorder)
            TextField("Device identifier", text: $deviceUDID)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(11))
            HStack(spacing: 8) {
                Picker("", selection: $devicePlatform) {
                    ForEach(AppleProvisioningClient.platforms) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Create a bundle ID").font(.system(size: 11.5, weight: .medium))
            TextField("My App", text: $bundleName)
                .textFieldStyle(.roundedBorder)
            // No sample identifier in the box. `RuntimePlaceholderTests`
            // bans a placeholder dataset from the runtime sources, and a
            // fake bundle ID is one.
            TextField("Reverse-DNS identifier", text: $bundleIdentifier)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(11))
            HStack(spacing: 8) {
                Picker("", selection: $bundlePlatform) {
                    ForEach(AppleProvisioningClient.platforms) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
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

    // MARK: - The expiry

    /// The whole point of the panel, so it goes above the folds and not inside
    /// one of them.
    private var expiring: [AppleProvisioningClient.Item] {
        items.filter { $0.isExpired || $0.expiresSoon() }
    }

    private var expiryNote: some View {
        WarningNote(expiring.contains(where: \.isExpired)
            ? "\(expiring.count) of these have lapsed or lapse within 30 days. Renew them in the Developer portal before the next build."
            : "\(expiring.count) of these lapse within 30 days. Renew them in the Developer portal before the next build.")
    }

    private func expansion(_ kind: AppleProvisioningClient.Item.Kind) -> Binding<Bool> {
        Binding(get: { open.contains(kind) }, set: { value in
            if value { open.insert(kind) } else { open.remove(kind) }
        })
    }

    /// The groups a fetch opens by itself: the ones that hold something lapsing,
    /// and no others. A fetch that found nothing lapsing draws a list of counts,
    /// which is the honest answer at a glance.
    static func groupsToOpen(_ items: [AppleProvisioningClient.Item])
    -> Set<AppleProvisioningClient.Item.Kind> {
        Set(items.filter { $0.isExpired || $0.expiresSoon() }.map(\.kind))
    }

    // MARK: - The work

    private func load() {
        busy = true
        Task {
            let result = await state.appleProvisioning()
            items = result.items
            failures = result.failures
            open = Self.groupsToOpen(result.items)
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
            await reread(showing: .device)
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
            await reread(showing: .bundleId)
        }
    }

    /// The read after a write opens the group the new row landed in, so the
    /// developer sees what Apple stored instead of a count that went up by one
    /// behind a fold.
    private func reread(showing kind: AppleProvisioningClient.Item.Kind) async {
        let result = await state.appleProvisioning()
        items = result.items
        failures = result.failures
        open.insert(kind)
        loaded = true
    }
}

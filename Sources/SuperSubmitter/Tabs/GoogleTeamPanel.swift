import SubmitKit
import SwiftUI

/// Who may reach the Google Play developer account, on tab 1.
///
/// It sits under the credential cards because it answers the same question
/// they do: not "what does this app say", but "whose account is this and who
/// is on it". Like the credentials, one answer covers every app, so the panel
/// works with no app open.
///
/// Google publishes no method that answers the developer account id, so the
/// field above the list takes it once and the defaults keep it. Everything
/// here is off until that id is there.
///
/// The reads are free. The three writes reach a colleague: an invitation is an
/// email, a permission change takes up to 48 hours to land, and a removal
/// shuts somebody out. Each of those confirms first, the same rule the review
/// reply and the recovery deploy follow.
struct GoogleTeamPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var members: [GoogleTeamClient.Member] = []
    /// The permission list a row is editing, keyed by the member's resource
    /// name. A row with no entry is showing what Google holds.
    @State private var accountDrafts: [String: String] = [:]
    @State private var grantDrafts: [String: String] = [:]
    @State private var newGrantPackages: [String: String] = [:]
    @State private var expanded: Set<String> = []
    @State private var inviteEmail = ""
    @State private var invitePermissions = "CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL"
    @State private var confirmingInvite = false
    @State private var removing: GoogleTeamClient.Member?
    @State private var revoking: GoogleTeamClient.Grant?

    private var ready: Bool {
        !state.googleDeveloperId.isEmpty && state.hasCredential(for: .google)
    }

    var body: some View {
        Section_("The people on this developer account", icon: "person.2",
                 tint: Theme.playGreen) {
            VStack(alignment: .leading, spacing: 12) {
                header
                developerField
                if let error { ErrorLine(text: error) }
                if loaded {
                    if members.isEmpty {
                        Text("Google lists nobody on this developer account. Check the id above, and check that the service account may manage permissions.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(members) { member in
                        Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                        memberRow(member)
                    }
                    Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                    invite
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .storePanel(padding: 14)
        }
        .confirmationDialog("Invite this person?", isPresented: $confirmingInvite) {
            Button("Send the invitation") { send() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Google emails \(inviteEmail.trimmingCharacters(in: .whitespaces)) an invitation to this developer account. They hold the permissions you picked from the moment they accept it.")
        }
        .confirmationDialog("Remove this person?", isPresented: $removing.isPresent,
                            presenting: removing) { member in
            Button("Remove all their access", role: .destructive) { remove(member) }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.email) loses access to this developer account and to every app on it. No call puts them back; a new invitation does, and they have to accept it again.")
        }
        .confirmationDialog("Take this app away?", isPresented: $revoking.isPresent,
                            presenting: revoking) { grant in
            Button("Revoke the app access", role: .destructive) { revoke(grant) }
            Button("Cancel", role: .cancel) {}
        } message: { grant in
            Text("They lose \(grant.packageName). Whatever the account-level permissions give them stays.")
        }
    }

    // MARK: - The head of the panel

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Read who has access, change what they may do, invite somebody, or take an app away. Reading changes nothing; the three writes each ask first.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            QuietButton(title: busy ? "Fetching…" : "Fetch the team") { load() }
                .disabled(busy || !ready)
        }
    }

    @ViewBuilder private var developerField: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                TextField("Developer account id", text: $state.googleDeveloperId)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11.5))
                    .frame(width: 220)
                if !state.hasCredential(for: .google) {
                    Text("Connect Google above first.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            Text("It is the number after /developers/ in any Play Console URL. Google offers no call that answers it. It belongs to the account, so it stays in the app’s settings and out of store.yaml.")
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - One person

    @ViewBuilder private func memberRow(_ member: GoogleTeamClient.Member) -> some View {
        let open = expanded.contains(member.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Button {
                    if open { expanded.remove(member.id) } else { expanded.insert(member.id) }
                } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(Theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "Collapse \(member.email)" : "Expand \(member.email)")

                Text(member.email).font(Theme.font(size: 12, weight: .medium))
                    .textSelection(.enabled)
                if let pill = Self.statePill(member) {
                    StatePill(text: pill.text, foreground: pill.tint,
                              background: Theme.sunken)
                }
                Spacer(minLength: 8)
                Text(Self.countLine(member))
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                if !member.partial {
                    Button("Remove") { removing = member }
                        .controlSize(.small).disabled(busy)
                }
            }

            if let expiry = member.expirationTime {
                Text("Access ends \(expiry)")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if member.partial {
                Text("Google did not show every permission this person holds, which is what it answers for the account owner and whenever the service account cannot manage every app. Change this one in the Play Console; a write from here would drop what it cannot see.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if open { detail(member) }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func detail(_ member: GoogleTeamClient.Member) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            LabeledField("Account permissions",
                         note: "They apply to every app. Google takes up to 48 hours to propagate a change.") {
                HStack(spacing: 8) {
                    MultiChoiceField(text: accountBinding(member),
                                     choices: StoreValues.googleAccountPermissions,
                                     emptyLabel: "No account-wide permission")
                        .disabled(member.partial)
                    if accountDrafts[member.id] != nil {
                        Button("Save") { saveAccount(member) }
                            .controlSize(.small).disabled(busy)
                        Button("Cancel") { accountDrafts[member.id] = nil }
                            .controlSize(.small)
                    }
                }
            }

            ForEach(member.grants) { grant in
                LabeledField(grant.packageName) {
                    HStack(spacing: 8) {
                        MultiChoiceField(text: grantBinding(grant),
                                         choices: StoreValues.googleAppPermissions,
                                         emptyLabel: "No app permission")
                            .disabled(member.partial)
                        if grantDrafts[grant.id] != nil {
                            Button("Save") { saveGrant(member, grant) }
                                .controlSize(.small).disabled(busy)
                            Button("Cancel") { grantDrafts[grant.id] = nil }
                                .controlSize(.small)
                        }
                        Button("Revoke") { revoking = grant }
                            .controlSize(.small).disabled(busy || member.partial)
                    }
                }
            }

            if !member.partial { addGrant(member) }
        }
        .padding(.leading, 23)
    }

    /// Gives one more app to a person who is already on the account.
    ///
    /// The field starts on the package the open app names, because that is the
    /// app the developer is standing in. It takes any other package too, since
    /// the account holds more than one.
    @ViewBuilder private func addGrant(_ member: GoogleTeamClient.Member) -> some View {
        HStack(spacing: 8) {
            TextField("Package name", text: newGrantBinding(member))
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(11))
                .frame(width: 200)
            Button("Give app access") { addAccess(member) }
                .controlSize(.small)
                .disabled(busy || newGrantBinding(member).wrappedValue
                    .trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Inviting somebody

    private var invite: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Invite somebody").font(Theme.font(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                TextField("name@example.com", text: $inviteEmail)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                MultiChoiceField(text: $invitePermissions,
                                 choices: StoreValues.googleAccountPermissions,
                                 emptyLabel: "No account-wide permission")
                    .frame(width: 260)
                Button("Invite") { confirmingInvite = true }
                    .controlSize(.small)
                    .disabled(busy || !GoogleTeamClient.looksLikeAnAddress(
                        inviteEmail.trimmingCharacters(in: .whitespaces)))
                Spacer(minLength: 0)
            }
            Text("Give app-level access after they appear in the list. An invitation with no account-wide permission is normal: it is how a person who only works on one app gets in.")
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The bindings

    private func accountBinding(_ member: GoogleTeamClient.Member) -> Binding<String> {
        Binding(
            get: { accountDrafts[member.id]
                ?? ChoiceText.text(from: member.accountPermissions) },
            set: { accountDrafts[member.id] = $0 })
    }

    private func grantBinding(_ grant: GoogleTeamClient.Grant) -> Binding<String> {
        Binding(
            get: { grantDrafts[grant.id] ?? ChoiceText.text(from: grant.permissions) },
            set: { grantDrafts[grant.id] = $0 })
    }

    private func newGrantBinding(_ member: GoogleTeamClient.Member) -> Binding<String> {
        Binding(
            get: {
                newGrantPackages[member.id]
                    ?? state.manifest.apps.google?.packageName ?? ""
            },
            set: { newGrantPackages[member.id] = $0 })
    }

    // MARK: - How a row reads

    static func statePill(_ member: GoogleTeamClient.Member) -> (text: String, tint: Color)? {
        switch member.accessState {
        case "ACCESS_GRANTED": nil
        case "INVITED": ("INVITED", Theme.yellow)
        case "INVITATION_EXPIRED": ("INVITATION EXPIRED", Theme.orange)
        case "ACCESS_EXPIRED": ("ACCESS EXPIRED", Theme.orange)
        case let other?: (AppleWords.title(other).uppercased(), Theme.text3)
        case nil: nil
        }
    }

    static func countLine(_ member: GoogleTeamClient.Member) -> String {
        let account = member.accountPermissions.count
        let apps = member.grants.count
        let first = account == 1 ? "1 account permission" : "\(account) account permissions"
        let second = apps == 1 ? "1 app" : "\(apps) apps"
        return "\(first)  ·  \(second)"
    }

    // MARK: - The work

    private func load() {
        track($busy, $error) {
            members = try await state.googleTeamMembers()
            accountDrafts = [:]
            grantDrafts = [:]
            loaded = true
        }
    }

    private func send() {
        let email = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        track($busy, $error) {
            try await state.inviteGoogleTeamMember(
                email: email, permissions: ChoiceText.values(from: invitePermissions))
            inviteEmail = ""
            members = try await state.googleTeamMembers()
        }
    }

    private func saveAccount(_ member: GoogleTeamClient.Member) {
        guard let draft = accountDrafts[member.id] else { return }
        track($busy, $error) {
            try await state.setGoogleTeamPermissions(
                member: member.id, permissions: ChoiceText.values(from: draft))
            accountDrafts[member.id] = nil
            members = try await state.googleTeamMembers()
        }
    }

    private func saveGrant(_ member: GoogleTeamClient.Member,
                           _ grant: GoogleTeamClient.Grant) {
        guard let draft = grantDrafts[grant.id] else { return }
        track($busy, $error) {
            try await state.setGoogleGrantPermissions(
                grant: grant.id, permissions: ChoiceText.values(from: draft))
            grantDrafts[grant.id] = nil
            members = try await state.googleTeamMembers()
        }
    }

    private func addAccess(_ member: GoogleTeamClient.Member) {
        let package = newGrantBinding(member).wrappedValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        track($busy, $error) {
            // No permission yet. Google creates the grant, the row appears,
            // and the chooser beside it is where the permissions are picked.
            try await state.grantGoogleTeamAccess(member: member.id,
                                                  packageName: package,
                                                  permissions: [])
            newGrantPackages[member.id] = nil
            members = try await state.googleTeamMembers()
        }
    }

    private func remove(_ member: GoogleTeamClient.Member) {
        track($busy, $error) {
            try await state.removeGoogleTeamMember(member.id)
            members = try await state.googleTeamMembers()
        }
    }

    private func revoke(_ grant: GoogleTeamClient.Grant) {
        track($busy, $error) {
            try await state.revokeGoogleGrant(grant.id)
            members = try await state.googleTeamMembers()
        }
    }
}

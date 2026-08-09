import SubmitKit
import SwiftUI

/// Who may reach the App Store Connect account, on tab 1.
///
/// It is the App Store twin of `GoogleTeamPanel` and it sits beside it, under
/// the credential cards, because it answers the same question they do: not
/// "what does this app say", but "whose account is this and who is on it". One
/// answer covers every app, so the panel works with no app open.
///
/// Apple keeps the accepted people and the pending invitations on two
/// resources. They are one list here, because "who is on this account" is one
/// question, and a pending row says so.
///
/// The reads are free. The three writes reach a colleague: an invitation is an
/// email, a role change gives or takes access, and a removal shuts somebody
/// out. Each of those confirms first, the same rule the review reply follows.
struct AppleTeamPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var members: [AppleTeamClient.Member] = []
    /// The role list a row is editing, keyed by the member id. A row with no
    /// entry is showing what Apple holds.
    @State private var roleDrafts: [String: String] = [:]
    @State private var expanded: Set<String> = []

    @State private var inviteEmail = ""
    @State private var inviteFirstName = ""
    @State private var inviteLastName = ""
    @State private var inviteRoles = "DEVELOPER"
    @State private var inviteAllApps = false
    @State private var confirmingInvite = false
    @State private var removing: AppleTeamClient.Member?

    var body: some View {
        Section_("The people on this App Store Connect account", icon: "person.2",
                 tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let error { ErrorLine(text: error) }
                if loaded {
                    if members.isEmpty {
                        Text("Apple lists nobody. A key without the Admin or Account Holder role cannot read the team, which is a permission state and not a fault.")
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
            Text("Apple emails \(inviteEmail.trimmingCharacters(in: .whitespaces)) an invitation. They hold the roles you picked from the moment they accept it.")
        }
        .confirmationDialog("Remove this person?", isPresented: $removing.isPresent,
                            presenting: removing) { member in
            Button(member.pending ? "Withdraw the invitation" : "Remove all their access",
                   role: .destructive) { remove(member) }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text(member.pending
                 ? "\(member.email) never joins, and the link in their email stops working. Inviting them again is a new invitation."
                 : "\(member.email) loses access to this account and to every app on it. No call puts them back; a new invitation does, and they have to accept it again.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Read who has access, change what they may do, invite somebody, or take their access away. Reading changes nothing; the three writes each ask first.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            QuietButton(title: busy ? "Fetching…" : "Fetch the team") { load() }
                .disabled(busy || !state.hasCredential(for: .apple))
        }
    }

    // MARK: - One person

    @ViewBuilder private func memberRow(_ member: AppleTeamClient.Member) -> some View {
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
                if !member.name.isEmpty {
                    Text(member.name).font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                }
                if member.pending {
                    StatePill(text: "INVITED", foreground: Theme.yellow,
                              background: Theme.sunken)
                }
                if member.isAccountOwner {
                    StatePill(text: "ACCOUNT HOLDER", foreground: Theme.text2,
                              background: Theme.sunken)
                }
                Spacer(minLength: 8)
                Text(Self.countLine(member))
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                Button(member.pending ? "Withdraw" : "Remove") { removing = member }
                    .controlSize(.small).disabled(busy || member.isAccountOwner)
            }
            if let expiry = member.expirationDate {
                Text("The invitation lapses \(expiry.formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if member.isAccountOwner {
                Text("Apple gives this role to the person who enrolled and refuses every change to it through the API. It is an App Store Connect job, and only they can start it.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if open { detail(member) }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func detail(_ member: AppleTeamClient.Member) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            LabeledField("Roles",
                         note: "A role left out is a role taken away. Apple refuses a change to a pending invitation, so those are read-only until the person accepts.") {
                HStack(spacing: 8) {
                    MultiChoiceField(text: roleBinding(member),
                                     choices: StoreValues.appleUserRoles,
                                     emptyLabel: "No role")
                        .disabled(member.pending || member.isAccountOwner)
                    if roleDrafts[member.id] != nil {
                        Button("Save") { saveRoles(member) }
                            .controlSize(.small).disabled(busy)
                        Button("Cancel") { roleDrafts[member.id] = nil }
                            .controlSize(.small)
                    }
                }
            }
            HStack(spacing: 10) {
                Text(member.allAppsVisible
                     ? "Sees every app on the account."
                     : member.visibleApps.isEmpty
                        ? "Sees no app yet."
                        : "Sees \(member.visibleApps.count) apps.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                if !member.pending, !member.isAccountOwner {
                    if member.allAppsVisible {
                        Button("Limit them to this app") { scope(member, toThisApp: true) }
                            .controlSize(.small)
                            .disabled(busy || state.appleActionAppID == nil)
                    } else {
                        Button("Give them every app") { scope(member, toThisApp: false) }
                            .controlSize(.small).disabled(busy)
                    }
                }
                Spacer(minLength: 0)
            }
            if member.provisioningAllowed {
                Text("May reach the certificates and the profiles on the Developer website.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.leading, 23)
    }

    // MARK: - Inviting somebody

    private var invite: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Invite somebody").font(Theme.font(size: 12, weight: .semibold))
            FieldRow {
                LabeledField("Email", width: 220) {
                    TextField("name@example.com", text: $inviteEmail)
                }
                LabeledField("First name", width: 140) {
                    TextField("", text: $inviteFirstName)
                }
                LabeledField("Last name", width: 140) {
                    TextField("", text: $inviteLastName)
                }
            }
            FieldRow {
                LabeledField("Roles") {
                    MultiChoiceField(text: $inviteRoles,
                                     choices: StoreValues.appleUserRoles,
                                     emptyLabel: "Pick at least one role")
                }
                LabeledField(" ", width: 150) {
                    Toggle("Every app", isOn: $inviteAllApps)
                }
            }
            HStack {
                Button("Invite") { confirmingInvite = true }
                    .controlSize(.small)
                    .disabled(busy || ChoiceText.values(from: inviteRoles).isEmpty
                              || !GoogleTeamClient.looksLikeAnAddress(
                                inviteEmail.trimmingCharacters(in: .whitespaces))
                              || inviteFirstName.trimmingCharacters(in: .whitespaces).isEmpty
                              || inviteLastName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
            Text("Apple wants both names on an invitation. Without \"Every app\" the person starts on the app this manifest names, and the account holder widens that in App Store Connect.")
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The bindings

    private func roleBinding(_ member: AppleTeamClient.Member) -> Binding<String> {
        Binding(get: { roleDrafts[member.id] ?? ChoiceText.text(from: member.roles) },
                set: { roleDrafts[member.id] = $0 })
    }

    static func countLine(_ member: AppleTeamClient.Member) -> String {
        let roles = member.roles.count
        let first = roles == 1 ? "1 role" : "\(roles) roles"
        let second = member.allAppsVisible
            ? "every app"
            : member.visibleApps.count == 1 ? "1 app" : "\(member.visibleApps.count) apps"
        return "\(first)  ·  \(second)"
    }

    // MARK: - The work

    private func load() {
        track($busy, $error) {
            members = try await state.appleTeamMembers()
            roleDrafts = [:]
            loaded = true
        }
    }

    private func send() {
        track($busy, $error) {
            try await state.inviteAppleTeamMember(
                email: inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                firstName: inviteFirstName, lastName: inviteLastName,
                roles: ChoiceText.values(from: inviteRoles),
                allAppsVisible: inviteAllApps)
            inviteEmail = ""
            inviteFirstName = ""
            inviteLastName = ""
            members = try await state.appleTeamMembers()
        }
    }

    private func saveRoles(_ member: AppleTeamClient.Member) {
        guard let draft = roleDrafts[member.id] else { return }
        track($busy, $error) {
            try await state.setAppleTeamRoles(member,
                                              roles: ChoiceText.values(from: draft),
                                              allAppsVisible: member.allAppsVisible)
            roleDrafts[member.id] = nil
            members = try await state.appleTeamMembers()
        }
    }

    /// Either the whole account or the one app the manifest names. Apple takes
    /// a list of app ids, and this app knows one of them, so the wider choice
    /// stays the flag.
    private func scope(_ member: AppleTeamClient.Member, toThisApp: Bool) {
        track($busy, $error) {
            if toThisApp {
                guard let appID = state.appleActionAppID else { return }
                try await state.setAppleTeamVisibleApps(member, appIDs: [appID])
            } else {
                try await state.setAppleTeamRoles(member, roles: member.roles,
                                                  allAppsVisible: true)
            }
            members = try await state.appleTeamMembers()
        }
    }

    private func remove(_ member: AppleTeamClient.Member) {
        track($busy, $error) {
            try await state.removeAppleTeamMember(member)
            members = try await state.appleTeamMembers()
        }
    }
}

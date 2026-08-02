import SwiftUI

/// Tab 6. Everything the reviewer needs and nothing the customer sees.
///
/// The open rows sit first. This is the tab a developer forgets, and a
/// forgotten row returns as a rejection days later.
struct ReviewInfoTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            openRows
            reviewContact
            demoAccount
            everythingElse
        }
        .frame(maxWidth: 940, alignment: .leading)
    }

    private var openRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Open rows").font(.system(size: 12.5, weight: .semibold))
                Text("2 of 9 rows need you. They sit first, because this is the tab a developer forgets.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
            }
            RowCard(rows: DemoData.reviewOpenRows, emphasised: true)
        }
    }

    private var reviewContact: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review contact").font(.system(size: 12.5, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                SmallField(label: "First name", value: "Rafa", minWidth: 150)
                SmallField(label: "Last name", value: "C", minWidth: 150)
                SmallField(label: "Email", value: "dev@fastbillsplit.app", minWidth: 190, mono: true)
                SmallField(label: "Phone", value: "+351 000 000 000", minWidth: 150, mono: true)
            }
            Text("App Store only. Google Play has no equivalent field.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
        }
    }

    /// The password goes to the Keychain, and the panel says so. A password
    /// field next to a YAML toggle would tell the developer the wrong thing.
    private var demoAccount: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Demo account").font(.system(size: 12.5, weight: .semibold))
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    StaticToggle(isOn: true)
                    Text("The reviewer needs an account to sign in").font(.system(size: 12.5))
                }
                HStack(alignment: .top, spacing: 12) {
                    SmallField(label: "User name", value: "review@fastbillsplit.app",
                               minWidth: 220, mono: true)
                    SmallField(label: "Password", value: "••••••••••••", minWidth: 160, mono: true)
                    Spacer(minLength: 0)
                }
                Text("The user name and the password go to the macOS Keychain. They are never written to a file in your repository.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    private var everythingElse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Everything else").font(.system(size: 12.5, weight: .semibold))
            RowCard(rows: DemoData.reviewRows, emphasised: false)
        }
    }
}

private struct RowCard: View {
    let rows: [DemoReviewRow]
    let emphasised: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Hairline(color: Theme.sep2) }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.system(size: 12.5, weight: emphasised ? .medium : .regular))
                        Text(row.reason)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    StatePill(text: row.state.label,
                              foreground: row.state.color,
                              background: row.state.background)
                    QuietButton(title: row.action)
                        .frame(minWidth: emphasised ? 0 : 78)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, emphasised ? 11 : 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

struct SmallField: View {
    let label: String
    let value: String
    var minWidth: CGFloat = 150
    var mono = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            Text(value)
                .font(mono ? Theme.mono(12) : .system(size: 12.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(minWidth: minWidth, alignment: .leading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}

struct StaticToggle: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.accent : Theme.sep)
            Circle().fill(.white).frame(width: 16, height: 16)
        }
        .frame(width: 34, height: 20)
        .padding(2)
    }
}

import SwiftUI

/// Tab 2. Two paths to the same state: drop a build, or pick an app that
/// already exists.
struct BuildTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                submitABuild
                Rectangle().fill(Theme.sep2).frame(width: 1)
                updateAnApp
            }

            if state.buildRead {
                packageCards
                filledLine
                versionWarning
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    // MARK: - The two paths

    private var submitABuild: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Submit a build").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 9) {
                DropWell(
                    title: state.buildRead ? "FastBillSplit.ipa · 118.4 MB" : "iOS or macOS package",
                    prompt: ".ipa or .pkg · drop here or")
                DropWell(
                    title: state.buildRead ? "app-release.aab · 42.1 MB" : "Android package",
                    prompt: ".aab · drop here or")
            }
            if !state.buildRead {
                Button {
                    state.buildRead = true
                } label: {
                    Text("Simulate a drop of both packages")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var updateAnApp: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Update an app that exists").font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 9) {
                PickerRow(label: "App Store", value: "Fast Bill Split", trailing: "1234567890")
                PickerRow(label: "Google Play", value: "com.fastbillsplit.app", trailing: nil)
            }
            Text("Both paths end in the same state. Picking an app reads its current listing into the forms.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - What the build holds

    private var packageCards: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(DemoData.packages) { package in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Theme.sunken)
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(package.title).font(.system(size: 13, weight: .semibold))
                            Text(package.file)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.text2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(package.rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.key)
                                    .foregroundStyle(Theme.text2)
                                    .frame(width: 112, alignment: .leading)
                                Text(row.value)
                                    .font(row.mono ? Theme.mono(12) : .system(size: 12))
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }
        }
    }

    private var filledLine: some View {
        HStack(spacing: 14) {
            Text("We filled 8 fields on the Details tab.").font(.system(size: 12.5))
            QuietButton(title: "Open Details") { state.selectedTab = .details }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var versionWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text("The version name differs between the two packages.")
                    .font(.system(size: 12.5, weight: .medium))
                Text("The .ipa reads 3.2.0 and the .aab reads 3.2.0-rc4. Google Play shows the release name to nobody, but the two stores then hold two different numbers. Set one name on the Build tab.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            QuietButton(title: "Use 3.2.0")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.yellow, lineWidth: 1))
    }
}

private struct DropWell: View {
    let title: String
    let prompt: String

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.field)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                .frame(width: 26, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                HStack(spacing: 3) {
                    Text(prompt).foregroundStyle(Theme.text2)
                    Text("choose a file…").foregroundStyle(Theme.accent)
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

private struct PickerRow: View {
    let label: String
    let value: String
    let trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            HStack {
                HStack(spacing: 6) {
                    Text(value)
                    if let trailing {
                        Text(trailing).foregroundStyle(Theme.text2)
                    }
                }
                Spacer()
                Text("▾").font(.system(size: 9)).foregroundStyle(Theme.text3)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}

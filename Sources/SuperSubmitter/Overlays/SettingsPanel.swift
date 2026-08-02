import SwiftUI

/// Settings. A panel over the window, never a second window.
///
/// Four items and no credential. The App Store and Google Play keys live on
/// the Stores tab, and the RevenueCat key lives on the Money tab, next to the
/// choice that needs them.
struct SettingsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("navigationPosition") private var position: NavigationPosition = .sidebar
    @AppStorage("pollIntervalMinutes") private var pollMinutes = 5
    @AppStorage("dryRunByDefault") private var dryRun = true

    var body: some View {
        VStack(spacing: 0) {
            header
            body_
        }
        .frame(width: 480)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        ZStack {
            Text("Settings").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Settings")
                Circle().fill(Theme.sep).frame(width: 12, height: 12)
                Circle().fill(Theme.sep).frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.horizontal, 13)
        }
        .frame(height: 44)
        .background(Theme.raised)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingRow("Navigation") {
                HStack(spacing: 0) {
                    ForEach(NavigationPosition.allCases) { option in
                        let selected = position == option
                        Button {
                            position = option
                        } label: {
                            Text(option.label)
                                .font(.system(size: 12))
                                .foregroundStyle(selected ? Theme.accentText : Theme.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .background(selected ? Theme.accent : .clear)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .background(Theme.sunken)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }

            SettingRow("Poll interval") {
                Menu {
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { minutes in
                        Button("\(minutes) minutes") { pollMinutes = minutes }
                    }
                } label: {
                    HStack {
                        Text("\(pollMinutes) minutes").font(.system(size: 12))
                        Spacer(minLength: 6)
                        Text("▾").font(.system(size: 9)).foregroundStyle(Theme.text3)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(width: 130)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            SettingRow("Dry run", alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Button {
                        dryRun.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(dryRun ? Theme.accent : .clear)
                                .frame(width: 14, height: 14)
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Theme.sep, lineWidth: 1))
                                .overlay(Text(dryRun ? "✓" : "")
                                    .font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                            Text("On by default for a new app").font(.system(size: 12.5))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(dryRun ? "On" : "Off")

                    Text("A dry run logs every request and sends none.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineSpacing(3)
                        .frame(maxWidth: 270, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Settings holds no credential. The App Store and Google Play keys live on the Stores tab. The RevenueCat key lives on the Money tab.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.content)
    }
}

private struct SettingRow<Content: View>: View {
    let label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: Content

    init(_ label: String, alignment: VerticalAlignment = .center,
         @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 14) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .frame(width: 120, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

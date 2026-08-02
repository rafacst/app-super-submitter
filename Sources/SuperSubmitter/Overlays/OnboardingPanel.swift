import SwiftUI

/// The onboarding. Five steps, then the promise.
///
/// The last screen is the emotional centre of the product. It states what the
/// app will and will not do before the developer hands over a private key.
struct OnboardingPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private var isPromise: Bool { step == 5 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if isPromise { promise } else { stepScene }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            footer
        }
        .frame(width: 1000, height: 660)
        .background(Theme.content)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Circle().fill(Theme.accent).frame(width: 9, height: 9)
                Text("Super Submitter").font(.system(size: 12.5, weight: .semibold))
            }
            Spacer()
            Button("Skip") { dismiss() }
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 22)
        .frame(height: Theme.headerHeight)
    }

    // MARK: - A step

    private var stepScene: some View {
        HStack(alignment: .center, spacing: 52) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text("STEP \(step + 1) OF 5")
                        .font(.system(size: 10.5, weight: .medium))
                        .kerning(0.65)
                        .foregroundStyle(Theme.accent)
                    Rectangle().fill(Theme.sep2).frame(height: 1)
                }

                Text(DemoData.onboardingSteps[step].title)
                    .font(.system(size: 23, weight: .semibold))
                    .kerning(-0.46)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(DemoData.onboardingSteps[step].points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Theme.text3).frame(width: 4, height: 4).padding(.top, 7)
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.text2)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            illustration.frame(width: 330)
        }
        .frame(maxWidth: 900)
    }

    @ViewBuilder private var illustration: some View {
        switch step {
        case 0: storesArt
        case 1: buildArt
        case 2: detailsArt
        case 3: mediaArt
        default: moneyArt
        }
    }

    private var storesArt: some View {
        VStack(spacing: 9) {
            SelectedStoreRow(name: "App Store")
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.field)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                        .frame(width: 22, height: 27)
                    Text("AuthKey_9F2KQ4X8L1.p8")
                        .font(Theme.mono(11)).foregroundStyle(Theme.text2)
                }
                HStack(spacing: 7) {
                    ChipField("key id")
                    ChipField("issuer id")
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))

            SelectedStoreRow(name: "Google Play")

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.green).frame(width: 6, height: 6)
                Text("Both keys go to the macOS Keychain.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private var buildArt: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Hatched(cornerRadius: 8).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FastBillSplit.ipa").font(.system(size: 12, weight: .semibold))
                    Text("118.4 MB · read in 1.2s")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(13)

            VStack(spacing: 0) {
                ForEach(DemoData.onboardingPackageRows) { row in
                    HStack(spacing: 10) {
                        Text(row.key)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 96, alignment: .leading)
                        Text(row.value).font(Theme.mono(11))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 5)

            Text("8 fields filled on the Details tab.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.green)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var detailsArt: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Subtitle").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("26 / 30").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
                MiniWell("Split any bill in seconds")
                Text("Different for Google")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Keywords").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("104 / 100").font(.system(size: 11)).foregroundStyle(Theme.red)
                }
                MiniWell("bill,split,tip,receipt,restaurant,dinner,share,check,tab,friends,group,payment",
                         border: Theme.red, borderWidth: 1)
                Text("Over the limit. We never shorten it for you.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.red)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var mediaArt: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Phone").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("3 of 10").font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        Hatched(cornerRadius: 5).frame(height: 104)
                        Text("iPhone 6.7″").font(.system(size: 10)).foregroundStyle(Theme.text2)
                    }
                }
                // The rejected tile. It names the dimensions and offers no
                // resize, because a stretched screenshot fails a review.
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.redBg)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Theme.red, lineWidth: 1))
                        .frame(height: 104)
                    Text("1179 × 2555\nno bucket")
                        .font(.system(size: 10)).foregroundStyle(Theme.red)
                }
            }
            Text("Apple takes a video file. Google takes a YouTube link and no file.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var moneyArt: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(spacing: 8) {
                PriceLine("You asked for", "4.99 USD", color: Theme.text)
                PriceLine("Apple resolved", "4.99 USD", color: Theme.green)
                PriceLine("Google base region", "4.99 USD", color: Theme.green)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))

            HStack(spacing: 7) {
                MiniProvider("None", selected: false)
                MiniProvider("RevenueCat", selected: true)
                MiniProvider("Adapty", selected: false)
            }

            Text("One product id becomes the right object in each store, and one mirror in your provider.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .padding(.horizontal, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The promise

    private var promise: some View {
        VStack(spacing: 30) {
            Text("We prepare a draft.\nYou press release.")
                .font(.system(size: 34, weight: .semibold))
                .kerning(-1.02)
                .lineSpacing(6)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                PromiseCell(tag: "TABS 1–6", tagColor: Theme.text3,
                            line: "You fill the forms. Nothing leaves this Mac.")
                Rectangle().fill(Theme.sep).frame(width: Theme.hairline)
                PromiseCell(tag: "TABS 7–8", tagColor: Theme.text3,
                            line: "You read the diff. We write a draft to each store.")
                Rectangle().fill(Theme.sep).frame(width: Theme.hairline)
                PromiseCell(tag: "TAB 9", tagColor: Theme.red,
                            line: "Two red buttons, one per store. The only irreversible step.")
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Nothing before tab 9 can reach a customer, take a place in a review queue, or be undone by hand.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 640)
    }

    // MARK: - The footer

    private var footer: some View {
        HStack {
            Group {
                if step > 0 {
                    QuietButton(title: "Back") { step -= 1 }
                }
            }
            .frame(width: 120, alignment: .leading)

            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { index in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { step = index }
                    } label: {
                        Capsule()
                            .fill(index == step ? Theme.accent : Theme.sep)
                            .frame(width: index == step ? 18 : 6, height: 6)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(index == 5 ? "Promise" : "Step \(index + 1)")
                    .accessibilityAddTraits(index == step ? .isSelected : [])
                }
            }
            Spacer()

            HStack {
                Spacer()
                Button {
                    if step >= 5 { dismiss() } else { step += 1 }
                } label: {
                    Text(step == 4 ? "One last thing" : step == 5 ? "Start" : "Next")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 120)
        }
        .padding(.horizontal, 28)
        .frame(height: 76)
    }
}

// MARK: - The small parts

private struct SelectedStoreRow: View {
    let name: String

    var body: some View {
        HStack {
            Text(name).font(.system(size: 12.5, weight: .semibold))
            Spacer()
            Circle().fill(Theme.accent).frame(width: 15, height: 15)
                .overlay(Text("✓").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.accent, lineWidth: 1.5))
    }
}

private struct ChipField: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

private struct MiniWell: View {
    let text: String
    var border: Color = Theme.sep
    var borderWidth: CGFloat = Theme.hairline

    init(_ text: String, border: Color = Theme.sep, borderWidth: CGFloat = Theme.hairline) {
        self.text = text
        self.border = border
        self.borderWidth = borderWidth
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(border, lineWidth: borderWidth))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PriceLine: View {
    let label: String
    let value: String
    let color: Color

    init(_ label: String, _ value: String, color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(Theme.mono(11.5)).foregroundStyle(color)
        }
    }
}

private struct MiniProvider: View {
    let name: String
    let selected: Bool

    init(_ name: String, selected: Bool) {
        self.name = name
        self.selected = selected
    }

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Theme.accent : Theme.sep,
                              lineWidth: selected ? 1.5 : Theme.hairline))
    }
}

private struct PromiseCell: View {
    let tag: String
    let tagColor: Color
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tag)
                .font(.system(size: 10, weight: .medium))
                .kerning(0.6)
                .foregroundStyle(tagColor)
            Text(line)
                .font(.system(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

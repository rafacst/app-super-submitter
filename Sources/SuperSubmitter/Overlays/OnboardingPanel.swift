import SubmitKit
import SwiftUI

/// The onboarding. Five steps, then the promise.
///
/// Every step plays. The right half is not a picture of the tab, it is the tab
/// doing its work: a switch turns on, a package lands, a counter fills, a
/// screenshot is rejected. The loop repeats while the reader stays on the step.
///
/// The scenes invent no value. They show the shape of the work and the state
/// of a control, never an app name, a key, a file, or a price.
struct OnboardingPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private static let tints: [Color] = [
        Theme.accent, Theme.purple, Theme.teal, Theme.pink, Theme.green, Theme.orange,
    ]

    private var isPromise: Bool { step == 5 }
    private var tint: Color { Self.tints[step] }
    private var content: OnboardingContent.Step? {
        isPromise ? nil : OnboardingContent.onboardingSteps[step]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if isPromise { promise } else { stepScene }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 54)
            footer
        }
        // A sheet takes its minimum width, so the size is fixed. It stays
        // inside the smallest window the app allows.
        .frame(width: 1120, height: 700)
        .background(wash)
        .foregroundStyle(Theme.text)
        .onExitCommand { dismiss() }
    }

    /// The colour behind the panel. It carries the tint of the step, so the six
    /// screens do not read as one grey slab.
    private var wash: some View {
        ZStack {
            Theme.content
            RadialGradient(colors: [tint.opacity(0.17), .clear],
                           center: .init(x: 0.80, y: 0.28),
                           startRadius: 8, endRadius: 640)
            RadialGradient(colors: [Theme.accent.opacity(0.09), .clear],
                           center: .init(x: 0.02, y: 1.0),
                           startRadius: 8, endRadius: 520)
        }
        .animation(.easeInOut(duration: 0.55), value: step)
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 9) {
                Circle().fill(tint).frame(width: 9, height: 9)
                Text("Super Submitter").font(.system(size: 12.5, weight: .semibold))
            }

            Spacer(minLength: 12)

            // The rail. Six segments, one per screen, filled up to the current.
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Self.tints[index] : Theme.sep)
                        .frame(width: index == step ? 26 : 14, height: 3)
                }
            }

            Spacer(minLength: 12)

            Button("Skip") { dismiss() }
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 22)
        // Its own number, not `Theme.headerHeight`. That band grew to carry a
        // screen title over a question; this one carries six dots and a Skip,
        // and it borrowed the height rather than the job.
        .frame(height: 52)
    }

    // MARK: - A step

    private var stepScene: some View {
        HStack(alignment: .center, spacing: 58) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 11) {
                    IconChip(symbol: content?.symbol ?? "circle", tint: tint, size: 30)
                    Text("STEP \(step + 1) OF 5")
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.7)
                        .foregroundStyle(tint)
                    Rectangle().fill(Theme.sep2).frame(height: 1)
                }

                Text(content?.title ?? "")
                    .font(.system(size: 30, weight: .semibold))
                    .kerning(-0.6)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(content?.points ?? [], id: \.self) { point in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tint)
                                .frame(width: 15, height: 15)
                                .background(tint.opacity(0.15), in: Circle())
                            Text(point)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text2)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: 430, alignment: .leading)

            illustration
                .frame(width: 440)
                .id(step)
        }
        .frame(maxWidth: 1010)
    }

    @ViewBuilder private var illustration: some View {
        switch step {
        case 0: StoresScene()
        case 1: BuildScene()
        case 2: DetailsScene()
        case 3: MediaScene()
        default: MoneyScene()
        }
    }

    // MARK: - The promise

    private var promise: some View {
        VStack(spacing: 32) {
            HStack(spacing: 14) {
                StoreMark(store: .apple, size: 30)
                Circle().fill(Theme.sep).frame(width: 4, height: 4)
                StoreMark(store: .google, size: 30)
            }

            Text("We prepare a draft.\nYou press release.")
                .font(.system(size: 40, weight: .semibold))
                .kerning(-1.2)
                .lineSpacing(6)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                PromiseCell(symbol: "square.and.pencil", tint: Theme.accent, tag: "TABS 1–6",
                            line: "You fill the forms. Nothing leaves this Mac.")
                Rectangle().fill(Theme.sep).frame(width: Theme.hairline)
                PromiseCell(symbol: "arrow.left.arrow.right", tint: Theme.teal, tag: "TABS 7–8",
                            line: "You read the diff. We write a draft to each store.")
                Rectangle().fill(Theme.sep).frame(width: Theme.hairline)
                PromiseCell(symbol: "paperplane.fill", tint: Theme.red, tag: "TAB 9",
                            line: "Two red buttons, one per store. The only irreversible step.")
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Nothing before tab 9 can reach a customer, take a place in a review queue, or be undone by hand.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 780)
    }

    // MARK: - The footer

    private var footer: some View {
        HStack {
            Group {
                if step > 0 {
                    QuietButton(title: "Back") { move(to: step - 1) }
                }
            }
            .frame(width: 156, alignment: .leading)

            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { index in
                    Button { move(to: index) } label: {
                        Capsule()
                            .fill(index == step ? Self.tints[index] : Theme.sep)
                            .frame(width: index == step ? 20 : 6, height: 6)
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
                    if step >= 5 { dismiss() } else { move(to: step + 1) }
                } label: {
                    HStack(spacing: 7) {
                        Text(step == 4 ? "One last thing" : step == 5 ? "Start" : "Next")
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                        Image(systemName: step == 5 ? "checkmark" : "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 130)
        }
        .padding(.horizontal, 28)
        .frame(height: 78)
    }

    private func move(to index: Int) {
        withAnimation(.easeOut(duration: 0.22)) { step = index }
    }
}

// MARK: - The beat

/// Drives a phase counter while the view is on screen: 0, 1, 2 … then it rests,
/// resets, and plays again. Every scene reads `phase` to decide what has
/// arrived, what is switched on, and what is still empty.
private struct Beats<Content: View>: View {
    let count: Int
    var beat: Duration = .milliseconds(760)
    var rest: Duration = .seconds(2)
    @ViewBuilder var content: (Int) -> Content
    @State private var phase = 0

    var body: some View {
        content(phase).task {
            while !Task.isCancelled {
                for _ in 0..<count {
                    try? await Task.sleep(for: beat)
                    if Task.isCancelled { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { phase += 1 }
                }
                try? await Task.sleep(for: rest)
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.3)) { phase = 0 }
            }
        }
    }
}

/// Content that arrives on a beat. It fades up from below and stays.
private struct Reveal<Content: View>: View {
    let on: Bool
    var rise: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : rise)
            .scaleEffect(on ? 1 : 0.97, anchor: .top)
    }
}

// MARK: - Step 1, the stores

private struct StoresScene: View {
    var body: some View {
        Beats(count: 5) { phase in
            VStack(spacing: 10) {
                StoreConnectCard(store: .apple, on: phase >= 1)
                Reveal(on: phase >= 2) {
                    SecretCard(symbol: "key.fill", tint: Theme.orange,
                               caption: "Private key selected",
                               chips: ["key id", "issuer id"])
                }
                StoreConnectCard(store: .google, on: phase >= 3)
                Reveal(on: phase >= 4) {
                    SecretCard(symbol: "doc.text.fill", tint: Theme.playBlue,
                               caption: "Service account selected",
                               chips: ["invited in Play Console"])
                }
                Reveal(on: phase >= 5) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10)).foregroundStyle(Theme.green)
                        Text("Both secrets go to the macOS Keychain.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.green)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.greenBg, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct StoreConnectCard: View {
    let store: Store
    let on: Bool

    var body: some View {
        HStack(spacing: 11) {
            StoreMark(store: store, size: 21)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.storeName).font(.system(size: 13, weight: .semibold))
                Text(on ? "Connected" : "Off")
                    .font(.system(size: 11))
                    .foregroundStyle(on ? Theme.green : Theme.text3)
            }
            Spacer(minLength: 0)
            // The same mark the Stores tab draws. This card is a picture of
            // that tab, and it used to draw a switch instead, so the first
            // thing the app taught was a control the app does not have.
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(on ? Theme.accent : Theme.text3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(on ? Theme.accent : Theme.sep, lineWidth: on ? 1.5 : Theme.hairline))
    }
}

private struct SecretCard: View {
    let symbol: String
    let tint: Color
    let caption: String
    let chips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                IconChip(symbol: symbol, tint: tint, size: 24)
                Text(caption).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
                ForEach(chips, id: \.self) { ChipField($0) }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

// MARK: - Step 2, the build

private struct BuildScene: View {
    private static let fields = OnboardingContent.packageFields

    var body: some View {
        Beats(count: 5) { phase in
            VStack(alignment: .leading, spacing: 0) {
                dropWell(landed: phase >= 1)

                VStack(spacing: 0) {
                    ForEach(Array(Self.fields.enumerated()), id: \.offset) { index, field in
                        Reveal(on: index < max(0, phase - 1) * 2, rise: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.down.left")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.purple)
                                Text(field)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.text2)
                                    .frame(width: 118, alignment: .leading)
                                Text("From the package").font(Theme.mono(11))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                        }
                    }
                }
                .padding(.vertical, 6)

                Reveal(on: phase >= 5) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.green)
                        Text("Checked against the store before anything uploads.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.green)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.greenBg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func dropWell(landed: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if landed {
                    IconChip(symbol: "shippingbox.fill", tint: Theme.purple, size: 38)
                } else {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 38, height: 38)
                }
            }
            .scaleEffect(landed ? 1 : 0.75)

            VStack(alignment: .leading, spacing: 2) {
                Text(landed ? "Package selected" : "Drop your build here")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(landed ? "Metadata is read on this Mac" : ".ipa · .pkg · .aab")
                    .font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(landed ? Theme.purple.opacity(0.08) : Theme.sunken)
    }
}

// MARK: - Step 3, the details

private struct DetailsScene: View {
    var body: some View {
        Beats(count: 5) { phase in
            VStack(alignment: .leading, spacing: 14) {
                CounterField(label: "Subtitle", limit: 30, store: .apple,
                             fill: min(1, Double(phase) / 3), focused: phase >= 1)

                Reveal(on: phase >= 4, rise: 6) {
                    HStack(spacing: 9) {
                        // A tick box, because the Details tab uses a tick box.
                        Image(systemName: phase >= 4 ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14))
                            .foregroundStyle(phase >= 4 ? Theme.accent : Theme.text3)
                        Text("Different text for Google")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer(minLength: 0)
                    }
                }

                Reveal(on: phase >= 5) {
                    CounterField(label: "Short description", limit: 80, store: .google,
                                 fill: 0.42, focused: false)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}

/// A field with the counter that every listing field carries. The bar shows how
/// much of the limit is spent. No text is invented inside the well.
private struct CounterField: View {
    let label: String
    let limit: Int
    let store: Store
    let fill: Double
    let focused: Bool

    private var used: Int { Int((Double(limit) * fill).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                StoreMark(store: store, size: 13)
                Text(label).font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 0)
                Text("\(used) / \(limit)")
                    .font(Theme.mono(11))
                    .foregroundStyle(fill >= 1 ? Theme.yellow : Theme.text2)
            }

            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.field)
                .frame(height: 34)
                .overlay(alignment: .leading) {
                    // The text as a bar. The app never invents the words.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.text3.opacity(0.35))
                        .frame(width: max(0, fill) * 250, height: 7)
                        .padding(.leading, 10)
                }
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(focused ? Theme.pink : Theme.sep,
                                  lineWidth: focused ? 1.5 : Theme.hairline))

            ProgressLine(fill: fill, tint: fill >= 1 ? Theme.yellow : Theme.pink)
        }
    }
}

private struct ProgressLine: View {
    let fill: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sep2)
                Capsule().fill(tint).frame(width: geometry.size.width * min(1, max(0, fill)))
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Step 4, the media

private struct MediaScene: View {
    var body: some View {
        Beats(count: 5) { phase in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    IconChip(symbol: "iphone", tint: Theme.pink, size: 22)
                    Text("Phone").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(phase >= 3 ? "2 accepted · 1 rejected" : "\(min(phase, 2)) accepted")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                }

                HStack(alignment: .top, spacing: 9) {
                    ShotTile(on: phase >= 1, rejected: false)
                    ShotTile(on: phase >= 2, rejected: false)
                    ShotTile(on: phase >= 3, rejected: true)
                }

                Reveal(on: phase >= 4, rise: 6) {
                    HStack(spacing: 9) {
                        VideoChip(store: .apple, symbol: "film.fill",
                                  line: "A video file, 15 to 30 s")
                        VideoChip(store: .google, symbol: "link",
                                  line: "A YouTube link")
                    }
                }

                Reveal(on: phase >= 5) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.green)
                        Text("Every size is read on the drop, before anything uploads.")
                            .font(.system(size: 11)).foregroundStyle(Theme.green)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}

private struct ShotTile: View {
    let on: Bool
    let rejected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if rejected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.redBg)
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.red, lineWidth: 1.5))
                        .overlay(Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.red))
                } else {
                    Hatched(cornerRadius: 7)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.green)
                                .padding(5)
                        }
                }
            }
            .frame(height: 116)

            Text(rejected ? "Wrong size, rejected" : "Accepted size")
                .font(.system(size: 10))
                .foregroundStyle(rejected ? Theme.red : Theme.text2)
        }
        .opacity(on ? 1 : 0)
        .scaleEffect(on ? 1 : 0.86)
        .rotationEffect(.degrees(on ? 0 : (rejected ? 6 : -4)))
    }
}

private struct VideoChip: View {
    let store: Store
    let symbol: String
    let line: String

    var body: some View {
        HStack(spacing: 8) {
            StoreMark(store: store, size: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.storeName).font(.system(size: 11, weight: .semibold))
                Text(line).font(.system(size: 10.5)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

// MARK: - Step 5, the money

private struct MoneyScene: View {
    var body: some View {
        Beats(count: 5) { phase in
            VStack(alignment: .leading, spacing: 11) {
                VStack(spacing: 9) {
                    ResolveRow(icon: "textformat.123", tint: Theme.green,
                               label: "Requested price",
                               state: phase >= 1 ? .set("Entered by you") : .waiting)
                    Divider().overlay(Theme.sep2)
                    ResolveRow(icon: "apple.logo", tint: Theme.appleMark,
                               label: "App Store price point",
                               state: phase >= 3 ? .done("Resolved by Apple")
                                    : phase >= 2 ? .working : .waiting)
                    Divider().overlay(Theme.sep2)
                    ResolveRow(icon: "globe", tint: Theme.playBlue,
                               label: "Google base region",
                               state: phase >= 3 ? .done("From the store") : .waiting)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))

                Reveal(on: phase >= 4, rise: 6) {
                    HStack(spacing: 7) {
                        ProviderPill("None", selected: false)
                        ProviderPill("RevenueCat", selected: true)
                        ProviderPill("Adapty", selected: false)
                    }
                }

                Reveal(on: phase >= 5) {
                    VStack(spacing: 7) {
                        HStack(spacing: 8) {
                            IconChip(symbol: "cube.fill", tint: Theme.green, size: 20)
                            Text("One product id").font(.system(size: 11.5, weight: .medium))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text3)
                        }
                        HStack(spacing: 7) {
                            MirrorPill { StoreLabel(store: .apple, size: 10.5) }
                            MirrorPill { StoreLabel(store: .google, size: 10.5) }
                            MirrorPill {
                                HStack(spacing: 6) {
                                    IconChip(symbol: "arrow.triangle.2.circlepath",
                                             tint: Theme.orange, size: 14)
                                    Text("Provider").font(.system(size: 10.5, weight: .semibold))
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
            }
        }
    }
}

private struct ResolveRow: View {
    enum State {
        case waiting, working, set(String), done(String)
    }

    let icon: String
    let tint: Color
    let label: String
    let state: State

    var body: some View {
        HStack(spacing: 9) {
            IconChip(symbol: icon, tint: tint, size: 20)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            switch state {
            case .waiting:
                Text("Waiting").font(Theme.mono(11)).foregroundStyle(Theme.text3)
            case .working:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                    Text("Asking the store").font(Theme.mono(11)).foregroundStyle(Theme.yellow)
                }
            case .set(let text):
                Text(text).font(Theme.mono(11)).foregroundStyle(Theme.text)
            case .done(let text):
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(Theme.green)
                    Text(text).font(Theme.mono(11)).foregroundStyle(Theme.green)
                }
            }
        }
    }
}

private struct MirrorPill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

// MARK: - The small parts

private struct ChipField: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

private struct ProviderPill: View {
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
            .background(selected ? Theme.orange.opacity(0.12) : Theme.raised,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Theme.orange : Theme.sep,
                              lineWidth: selected ? 1.5 : Theme.hairline))
    }
}

private struct PromiseCell: View {
    let symbol: String
    let tint: Color
    let tag: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconChip(symbol: symbol, tint: tint, size: 26)
            Text(tag)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(tint)
            Text(line)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

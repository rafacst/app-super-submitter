import Foundation
import SwiftUI

/// Tab 8. The run. It writes drafts and it releases nothing.
struct SubmitTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.runIndex < 0 {
                readyToRun
            } else {
                stepList
                if uploading { uploadPanel }
                logPanel
                if state.runDone { finished }
            }
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private var uploading: Bool {
        guard state.runIndex >= 0, state.runIndex < DemoData.runItems.count else { return false }
        return DemoData.runItems[state.runIndex].long
    }

    private var uploadClock: String {
        let elapsedSeconds = Int((state.runProgress * 480).rounded())
        return String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    // MARK: - Before

    private var readyToRun: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to run.").font(.system(size: 15, weight: .semibold))
            Text("24 writes and 13 uploads, across App Store, Google Play, and RevenueCat. The run ends with a draft in each store. It sends nothing to review.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Review the plan first") { state.selectedTab = .plan }
        }
    }

    // MARK: - During

    private var stepList: some View {
        VStack(spacing: 0) {
            ForEach(Array(DemoData.runItems.enumerated()), id: \.element.id) { index, item in
                if item.isGroup {
                    HStack {
                        Text(item.text)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                        Spacer()
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(Theme.sunken)
                } else {
                    let done = index < state.runIndex
                    let active = index == state.runIndex
                    HStack(spacing: 11) {
                        Group {
                            if done {
                                Text("✓").font(.system(size: 12)).foregroundStyle(Theme.green)
                            } else if active {
                                Spinner()
                            } else {
                                Text("·").font(.system(size: 11)).foregroundStyle(Theme.text3)
                            }
                        }
                        .frame(width: 16)

                        Text(item.text)
                            .font(.system(size: 12.5))
                            .foregroundStyle(done || active ? Theme.text : Theme.text3)
                        Spacer(minLength: 8)
                        Text(done || active ? item.meta : "")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    /// The longest wait in the app. It needs a real bar, a clock, and a way
    /// out, because a progress animation with no progress is a lie.
    private var uploadPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Uploading FastBillSplit.ipa · 118.4 MB")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 8)
                Text("\(uploadClock) elapsed · about 8 minutes total")
                    .font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.sep)
                    Capsule().fill(Theme.accent)
                        .frame(width: geometry.size.width * state.runProgress)
                }
            }
            .frame(height: 6)
            HStack {
                Text("Apple processes the build after the upload. This is the longest wait in the app.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                QuietButton(title: "Cancel")
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                state.logOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(state.logOpen ? "▼" : "▶").font(.system(size: 8)).foregroundStyle(Theme.text2)
                    Text("Log").font(.system(size: 12))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(state.logOpen ? "Expanded" : "Collapsed")

            if state.logOpen {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(DemoData.logText)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - After

    private var finished: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The run ended. Every store holds a draft.")
                .font(.system(size: 17, weight: .semibold))
                .kerning(-0.17)
            Text("Nothing went to review. Nothing reached a customer. Both drafts are visible in the two consoles.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { state.selectedTab = .release } label: {
                Text("Go to Release")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }
}

struct Spinner: View {
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.7).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

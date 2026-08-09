import Foundation
import SubmitKit
import SwiftUI

/// The run, under the plan that produced it. It writes drafts and releases
/// nothing.
///
/// This was a tab of its own, and before a plan existed it held one sentence
/// that pointed at the Summary tab. That is a navigation step charging rent
/// for a dead end: the plan and the run are one act, and the diff belongs in
/// front of the developer while the writes go out.
struct RunSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepList
            if let failure = state.runFailure { failurePanel(failure) }
            if let message = state.providerFailure { providerPanel(message) }
            if uploading { uploadPanel }
            logPanel
            if state.runDone { finished }
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private var uploading: Bool {
        guard state.runIndex >= 0, state.runIndex < state.runSteps.count,
              state.runFailure == nil, !state.runDone else { return false }
        return state.runSteps[state.runIndex].isUpload
    }

    // MARK: - During

    private var stepList: some View {
        VStack(spacing: 0) {
            ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                HStack(spacing: 7) {
                    switch group.system {
                    case PlanSystem.apple: StoreMark(store: .apple, size: 14)
                    case PlanSystem.google: StoreMark(store: .google, size: 14)
                    default: IconChip(symbol: "arrow.triangle.2.circlepath",
                                      tint: Theme.orange, size: 16)
                    }
                    Text(group.name)
                        .font(Theme.font(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Spacer()
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Theme.sunken)

                ForEach(group.indices, id: \.self) { index in
                    row(index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var grouped: [(name: String, system: PlanSystem, indices: [Int])] {
        var result: [(String, PlanSystem, [Int])] = []
        for (index, step) in state.runSteps.enumerated() {
            let name = switch step.system {
            case PlanSystem.apple: "App Store"
            case PlanSystem.google: "Google Play"
            case PlanSystem.provider: state.provider == .adapty ? "Adapty" : "RevenueCat"
            }
            if result.last?.0 == name {
                result[result.count - 1].2.append(index)
            } else {
                result.append((name, step.system, [index]))
            }
        }
        return result
    }

    private func row(_ index: Int) -> some View {
        let step = state.runSteps[index]
        let stepState = state.stepStates.indices.contains(index)
            ? state.stepStates[index] : .pending
        return HStack(spacing: 11) {
            Group {
                switch stepState {
                case .done:
                    Text("✓").font(Theme.font(size: 12)).foregroundStyle(Theme.green)
                case .running:
                    Spinner()
                case .failed:
                    Text("✕").font(Theme.font(size: 12)).foregroundStyle(Theme.red)
                case .skipped:
                    Text("–").font(Theme.font(size: 12)).foregroundStyle(Theme.yellow)
                case .pending:
                    Text("·").font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                }
            }
            .frame(width: 16)

            Text(step.title)
                .font(Theme.font(size: 12.5))
                .foregroundStyle(stepState == .pending ? Theme.text3 : Theme.text)
            Spacer(minLength: 8)
            Text(state.stepMeta.indices.contains(index) ? state.stepMeta[index] : "")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
    }

    /// The longest wait in the app. It needs a real bar, a clock, and a way
    /// out, because a progress animation with no progress is a lie.
    private var uploadPanel: some View {
        let step = state.runSteps[state.runIndex]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(Theme.font(size: 12.5, weight: .medium))
                Spacer(minLength: 8)
                Text(state.runDetail)
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
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
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                QuietButton(title: "Cancel") { state.cancelRun() }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    // MARK: - The failure panels, section 11

    /// What the undo can and cannot take back.
    ///
    /// A run that never opened a Google edit has no Play Console draft to
    /// explain, and the panel used to explain one anyway. An App Store apply
    /// read a paragraph about a store it does not publish to.
    private func recoveryNote(_ failure: RunFailure) -> String {
        if failure.canUndoGoogleEdit {
            return "The undo deletes the Google edit that this run opened. It removes no App Store screenshot, because Apple keeps them in the version and a second apply reuses them by checksum."
        }
        guard state.runSteps.contains(where: { $0.system == .google }) else {
            return "Every write in this run ended in a draft, so nothing reached the customers. A retry writes into the same version and reuses what already landed."
        }
        return "The Google edit is already committed, so the undo cannot remove the Play Console draft. The fix is another apply with a corrected manifest. The draft harms nobody in the meantime."
    }

    private func failurePanel(_ failure: RunFailure) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("The run stopped at \(state.runSteps[safe: failure.stepIndex]?.title ?? "a step").")
                .font(Theme.font(size: 13.5, weight: .semibold))
            Text(failure.message)
                .font(Theme.font(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(recoveryNote(failure))
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 9) {
                Button { state.retryFromFailure() } label: {
                    Text("Retry from the failed step")
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                QuietButton(title: "Undo what this run created") { state.undoRun() }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.red, lineWidth: 1))
    }

    /// Spec 11.2. The app never holds a store draft for a mirror, so the run
    /// already finished and the first button is the state you are in.
    private func providerPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("The provider sync failed. The store drafts are untouched.")
                .font(Theme.font(size: 13.5, weight: .semibold))
            Text(message)
                .font(Theme.font(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("The run skipped the provider and finished. A row for it sits on the Release tab.")
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text2)
            HStack(spacing: 9) {
                QuietButton(title: "Retry the provider sync") { state.retryProviderSync() }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.yellow, lineWidth: 1))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                state.logOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(state.logOpen ? "▼" : "▶").font(Theme.font(size: 8)).foregroundStyle(Theme.text2)
                    Text("Log").font(Theme.font(size: 12))
                    Spacer(minLength: 0)
                    Text("\(state.logLines.count) calls")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(state.logOpen ? "Expanded" : "Collapsed")

            // The same virtualized box the build log uses. This one holds a
            // line per API call rather than per line of compiler output, so it
            // never froze, but a run of a large plan still laid out every call
            // to draw the last ten.
            if state.logOpen {
                LogView(lines: state.logLines).padding(.horizontal, 5)
                    .padding(.bottom, 5)
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
            Text(state.dryRun
                 ? "The dry run ended. Nothing was sent."
                 : "The run ended. Every store holds a draft.")
                .font(Theme.font(size: 17, weight: .semibold))
                .kerning(-0.17)
            Text(state.dryRun
                 ? "Every request above was built and logged. No store received one. Turn the dry run off in the bar at the top to write the drafts."
                 : "Nothing went to review. Nothing reached a customer. Both drafts are visible in the two consoles.")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            // A dry run leaves the developer where they started, so the way
            // back is the plan itself and not another tab.
            Button { state.dryRun ? state.dismissRun() : (state.selectedTab = .release) } label: {
                Text(state.dryRun ? "Back to the plan" : "Go to Release")
                    .font(Theme.font(size: 12.5, weight: .medium))
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

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

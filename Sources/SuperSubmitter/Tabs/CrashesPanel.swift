import AppKit
import SubmitKit
import SwiftUI

/// Why the app crashed, from the two places Apple keeps it.
///
/// The vitals panel above answers "is it healthy" with a number. This answers
/// the question that number raises, and it is the one thing a developer opens
/// App Store Connect for that this app could not do: read the call stack.
///
/// The top half is aggregate and comes off the released build: Apple groups the
/// hangs, the launches, and the disk writes by the code that caused them. The
/// bottom half is one tester on TestFlight, with their own words attached.
///
/// Everything here is a read.
struct CrashesPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var diagnosticType = ""
    @State private var signatures: [AppleDiagnosticsClient.Signature] = []
    @State private var logs: [String: [AppleDiagnosticsClient.Log]] = [:]
    @State private var open: Set<String> = []

    @State private var feedbackBusy = false
    @State private var feedbackLoaded = false
    @State private var feedback: [AppleDiagnosticsClient.Feedback] = []
    @State private var feedbackFailures: [String] = []

    var body: some View {
        Section_("What went wrong", icon: "ladybug", tint: Theme.orange) {
            VStack(alignment: .leading, spacing: 12) {
                aggregate
                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                testers
            }
            .storePanel(padding: 14)
        }
    }

    // MARK: - The released build

    @ViewBuilder private var aggregate: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Apple groups what the released build did by the code that caused it, and each pattern carries the anonymized call stacks behind it. It needs a build that enough devices have run.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Picker("", selection: $diagnosticType) {
                Text("Every kind").tag("")
                ForEach(AppleDiagnosticsClient.diagnosticTypes, id: \.self) { kind in
                    Text(AppleWords.title(kind)).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            QuietButton(title: busy ? "Fetching…" : "Fetch the patterns") { load() }
                .disabled(busy || state.actualState.apple?.attachedBuildId == nil)
        }

        if let error { ErrorLine(text: error) }
        if state.actualState.apple?.attachedBuildId == nil {
            Text("Apple keys these to a build. Read the stores on the Summary tab, so the app knows which build is attached.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        } else if loaded, signatures.isEmpty {
            Text("Apple reports no pattern for the attached build. That is what a fresh release looks like, and it is a state and not a fault.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(signatures) { signature in signatureRow(signature) }
    }

    @ViewBuilder private func signatureRow(_ signature: AppleDiagnosticsClient.Signature) -> some View {
        let expanded = open.contains(signature.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Button { toggle(signature) } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse the call stacks" : "Show the call stacks")

                if let kind = signature.diagnosticType {
                    StatePill(text: AppleWords.title(kind).uppercased(),
                              foreground: Theme.text2, background: Theme.sunken)
                }
                Text(signature.signature)
                    .font(Theme.mono(11)).lineLimit(expanded ? nil : 1)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let share = signature.share {
                    Text(share).font(Theme.mono(11))
                        .foregroundStyle((signature.weight ?? 0) > 0.25 ? Theme.orange : Theme.text3)
                }
                Button("Save the log") { save(signature) }
                    .controlSize(.small)
                    .disabled(busy)
            }
            if expanded { logBlock(signature) }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private func logBlock(_ signature: AppleDiagnosticsClient.Signature) -> some View {
        let entries = logs[signature.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("Apple holds no log for this pattern.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        if let device = entry.deviceType {
                            Text(device).font(.system(size: 11, weight: .medium))
                        }
                        if let os = entry.osVersion {
                            Text(os).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                        }
                        if let version = entry.appVersion {
                            Text(version).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                        }
                        Spacer(minLength: 8)
                        if let detail = entry.detail {
                            Text(detail).font(.system(size: 10.5))
                                .foregroundStyle(Theme.text3).lineLimit(1)
                        }
                    }
                    // Only the frames Apple blames on this app. The system
                    // libraries around them are in the file the button saves.
                    ForEach(Array(entry.frames.enumerated()), id: \.offset) { _, frame in
                        Text(frame).font(Theme.mono(10)).foregroundStyle(Theme.text2)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.leading, 23)
    }

    // MARK: - What the testers sent

    @ViewBuilder private var testers: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What the TestFlight testers sent")
                    .font(.system(size: 12, weight: .semibold))
                Text("A crash or a screenshot arrives the moment a tester sends it, with whatever they typed beside it. It is the beta half of the same question.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            QuietButton(title: feedbackBusy ? "Fetching…" : "Fetch the feedback") { loadFeedback() }
                .disabled(feedbackBusy || state.appleActionAppID == nil)
        }

        ForEach(feedbackFailures, id: \.self) { failure in ErrorLine(text: failure) }
        if feedbackLoaded, feedback.isEmpty, feedbackFailures.isEmpty {
            Text("No tester has sent anything for this app.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        }
        ForEach(feedback) { item in feedbackRow(item) }
    }

    private func feedbackRow(_ item: AppleDiagnosticsClient.Feedback) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatePill(text: item.kind == .crash ? "CRASH" : "SCREENSHOT",
                          foreground: item.kind == .crash ? Theme.orange : Theme.text2,
                          background: Theme.sunken)
                if let email = item.testerEmail {
                    Text(email).font(.system(size: 11.5)).textSelection(.enabled)
                }
                if let device = item.deviceModel {
                    Text(device).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                }
                if let os = item.osVersion {
                    Text(os).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 8)
                if let date = item.createdDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                }
                // Apple puts the whole report in the resource, so the button
                // is one call and the file is the report.
                if item.kind == .crash {
                    Button("Save the crash report") { saveCrashLog(item) }
                        .controlSize(.small).disabled(feedbackBusy)
                }
            }
            if let comment = item.comment, !comment.isEmpty {
                Text(comment).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The image URLs expire, so nothing is downloaded here and the
            // link opens the one Apple served with the row.
            ForEach(Array(item.screenshots.enumerated()), id: \.offset) { index, url in
                Link("Screenshot \(index + 1) ↗", destination: url)
                    .font(.system(size: 11))
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - The work

    private func load() {
        track($busy, $error) {
            signatures = try await state.appleCrashSignatures(
                diagnosticType: diagnosticType.isEmpty ? nil : diagnosticType)
            logs = [:]
            open = []
            loaded = true
        }
    }

    private func toggle(_ signature: AppleDiagnosticsClient.Signature) {
        if open.contains(signature.id) {
            open.remove(signature.id)
            return
        }
        open.insert(signature.id)
        guard logs[signature.id] == nil else { return }
        track($busy, $error) {
            logs[signature.id] = try await state.appleCrashLogs(signatureID: signature.id)
        }
    }

    /// The whole log, as Apple served it. The rows above drop the addresses
    /// and the system frames, and those are half of what a crash report is
    /// read for, so the file keeps everything.
    private func save(_ signature: AppleDiagnosticsClient.Signature) {
        track($busy, $error) {
            let data = try await state.appleCrashLogFile(signatureID: signature.id)
            let panel = NSSavePanel()
            panel.title = "Save the diagnostic log"
            panel.nameFieldStringValue = "\(signature.diagnosticType?.lowercased() ?? "diagnostic")-\(signature.id.prefix(8)).json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
        }
    }

    private func loadFeedback() {
        feedbackBusy = true
        Task {
            let result = await state.appleBetaFeedback()
            feedback = result.items
            feedbackFailures = result.failures
            feedbackLoaded = true
            feedbackBusy = false
        }
    }

    /// A tester's own crash report. Apple carries the whole thing as text, so
    /// this writes it as a `.crash` file, which is what Xcode opens.
    private func saveCrashLog(_ item: AppleDiagnosticsClient.Feedback) {
        feedbackBusy = true
        Task {
            do {
                guard let text = try await state.appleFeedbackCrashLog(
                    submissionID: item.id) else {
                    feedbackFailures = ["Apple holds no crash report for that submission."]
                    feedbackBusy = false
                    return
                }
                let panel = NSSavePanel()
                panel.title = "Save the crash report"
                panel.nameFieldStringValue = "tester-\(item.id.prefix(8)).crash"
                if panel.runModal() == .OK, let url = panel.url {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                feedbackFailures = [error.localizedDescription]
            }
            feedbackBusy = false
        }
    }
}

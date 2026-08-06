import SubmitKit
import SwiftUI

/// Xcode Cloud, beside the local build.
///
/// The Build tab already makes a build on this Mac. This is the other way to
/// get one: ask Apple. It sits on the same tab because it answers the same
/// question, and it stays out of the plan because a build run is an action.
struct XcodeCloudPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var workflows: [XcodeCloudClient.Workflow] = []
    @State private var runs: [String: [XcodeCloudClient.BuildRun]] = [:]
    @State private var confirming: XcodeCloudClient.Workflow?

    var body: some View {
        Section_("Xcode Cloud", icon: "cloud", tint: Theme.purple) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apple builds the app instead of this Mac. A run spends the compute minutes on your account, and nothing gives them back.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    QuietButton(title: busy ? "Reading…" : "Read the workflows") { load() }
                        .disabled(busy || state.appleActionAppID == nil)
                }

                if let error { ErrorLine(text: error) }
                if loaded, workflows.isEmpty {
                    Text("This app has no Xcode Cloud workflow. You create one in Xcode, and it appears here.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(workflows) { workflow in workflowRow(workflow) }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Start this build?", isPresented: $confirming.isPresent,
                            presenting: confirming) { workflow in
            Button("Start the build") { start(workflow) }
            Button("Cancel", role: .cancel) {}
        } message: { workflow in
            Text("Apple runs \(workflow.name) and it spends the compute minutes of your account. Cancelling the run later does not give them back.")
        }
    }

    @ViewBuilder private func workflowRow(_ workflow: XcodeCloudClient.Workflow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Text(workflow.name).font(.system(size: 12, weight: .medium))
                Text(workflow.productName)
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                if !workflow.enabled {
                    StatePill(text: "OFF", foreground: Theme.text3, background: Theme.sunken)
                }
                Spacer(minLength: 8)
                Button("Start a build") { confirming = workflow }
                    .controlSize(.small)
                    .disabled(busy || !workflow.enabled)
            }
            ForEach(runs[workflow.id] ?? []) { run in
                HStack(spacing: 8) {
                    Text("#\(run.number.map(String.init) ?? "?")")
                        .font(Theme.mono(10)).foregroundStyle(Theme.text3)
                    Text(run.state.lowercased())
                        .font(.system(size: 11))
                        .foregroundStyle(run.completionStatus == "SUCCEEDED"
                                         ? Theme.green
                                         : run.completionStatus == nil
                                            ? Theme.yellow : Theme.red)
                    Spacer(minLength: 8)
                    if let date = run.startedAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func load() {
        track($busy, $error) {
            workflows = try await state.xcodeCloudWorkflows()
            for workflow in workflows {
                runs[workflow.id] = try? await state.xcodeCloudRuns(workflowID: workflow.id)
            }
            loaded = true
        }
    }

    private func start(_ workflow: XcodeCloudClient.Workflow) {
        track($busy, $error) {
            _ = try await state.startXcodeCloudBuild(workflowID: workflow.id)
            runs[workflow.id] = try await state.xcodeCloudRuns(workflowID: workflow.id)
        }
    }
}

import SubmitKit
import SwiftUI

/// Xcode Cloud, beside the local build.
///
/// The Build tab already makes a build on this Mac. This is the other way to
/// get one: ask Apple. It sits on the same tab because it answers the same
/// question, and it stays out of the plan because a build run is an action.
///
/// A run row opens to what the run actually did: the steps, how many errors
/// each one hit, the tests that failed, and the files it produced. A run that
/// says `FAILED` and nothing else is half an answer, and it was the half this
/// panel had.
struct XcodeCloudPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var workflows: [XcodeCloudClient.Workflow] = []
    @State private var runs: [String: [XcodeCloudClient.BuildRun]] = [:]
    @State private var confirming: XcodeCloudClient.Workflow?

    @State private var actions: [String: [XcodeCloudClient.Action]] = [:]
    @State private var artifacts: [String: [XcodeCloudClient.Artifact]] = [:]
    @State private var failures: [String: [XcodeCloudClient.TestFailure]] = [:]
    @State private var openRuns: Set<String> = []
    @State private var repositories: [XcodeCloudClient.Repository] = []
    @State private var repositoriesLoaded = false

    var body: some View {
        Section_("Xcode Cloud", icon: "cloud", tint: Theme.purple) {
            VStack(alignment: .leading, spacing: 10) {
                NoteWithAction("Apple builds the app instead of this Mac. A run spends the compute minutes on your account, and nothing gives them back.") {
                    QuietButton(title: busy ? "Fetching…" : "Fetch the workflows") { load() }
                        .disabled(busy || state.appleActionAppID == nil)
                }

                if let error { ErrorLine(text: error) }
                if loaded, workflows.isEmpty {
                    Text("This app has no Xcode Cloud workflow. You create one in Xcode, and it appears here.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(workflows) { workflow in workflowRow(workflow) }
                if loaded { sources }
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
                Text(workflow.name).font(Theme.font(size: 12, weight: .medium))
                Text(workflow.productName)
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                if !workflow.enabled {
                    StatePill(text: "OFF", foreground: Theme.text3, background: Theme.sunken)
                }
                Spacer(minLength: 8)
                // Off and on again, and nothing else. Authoring a workflow
                // takes the Xcode version, the actions, and the start
                // conditions, which is a form that belongs in Xcode.
                Button(workflow.enabled ? "Switch off" : "Switch on") {
                    setEnabled(workflow, !workflow.enabled)
                }
                .controlSize(.small).disabled(busy)
                Button("Start a build") { confirming = workflow }
                    .controlSize(.small)
                    .disabled(busy || !workflow.enabled)
            }
            ForEach(runs[workflow.id] ?? []) { run in runRow(run) }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private func runRow(_ run: XcodeCloudClient.BuildRun) -> some View {
        let open = openRuns.contains(run.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                DisclosureButton(isOpen: open,
                                 label: open ? "Collapse the run"
                                             : "Show what the run did") { toggle(run) }

                Text("#\(run.number.map(String.init) ?? "?")")
                    .font(Theme.mono(10)).foregroundStyle(Theme.text3)
                Text(run.state.lowercased())
                    .font(Theme.font(size: 11))
                    .foregroundStyle(run.completionStatus == "SUCCEEDED"
                                     ? Theme.green
                                     : run.completionStatus == nil
                                        ? Theme.yellow : Theme.red)
                Spacer(minLength: 8)
                if let date = run.startedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                }
            }
            if open { runDetail(run) }
        }
    }

    /// What the run did, step by step. This is the half the panel was missing:
    /// a status word says a run failed, and the actions say where.
    @ViewBuilder private func runDetail(_ run: XcodeCloudClient.BuildRun) -> some View {
        let steps = actions[run.id] ?? []
        VStack(alignment: .leading, spacing: 7) {
            if steps.isEmpty {
                Text("Apple reports no step for this run yet.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            }
            ForEach(steps) { step in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(step.name).font(Theme.font(size: 11.5, weight: .medium))
                        Text(step.state.lowercased())
                            .font(Theme.font(size: 11))
                            .foregroundStyle(step.completionStatus == "SUCCEEDED"
                                             ? Theme.green
                                             : step.completionStatus == nil
                                                ? Theme.yellow : Theme.red)
                        Spacer(minLength: 8)
                        if let issues = step.issues {
                            Text(issues).font(Theme.font(size: 10.5))
                                .foregroundStyle(Theme.orange)
                        }
                    }
                    ForEach(failures[step.id] ?? []) { failure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text([failure.className, failure.name].compactMap { $0 }
                                .joined(separator: "."))
                                .font(Theme.mono(10)).foregroundStyle(Theme.red)
                            if let message = failure.message, !message.isEmpty {
                                Text(message).font(Theme.font(size: 10.5))
                                    .foregroundStyle(Theme.text3)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.leading, 10)
                    }
                    // Apple serves an artifact from a URL that expires, so
                    // nothing is cached here and the link opens the one that
                    // came with the row.
                    ForEach(artifacts[step.id] ?? []) { artifact in
                        HStack(spacing: 6) {
                            if let url = artifact.downloadURL {
                                Link(artifact.fileName, destination: url)
                                    .font(Theme.font(size: 10.5))
                            } else {
                                Text(artifact.fileName).font(Theme.font(size: 10.5))
                                    .foregroundStyle(Theme.text3)
                            }
                            if let type = artifact.fileType {
                                Text(AppleWords.title(type)).font(Theme.font(size: 10))
                                    .foregroundStyle(Theme.text3)
                            }
                            if let size = artifact.fileSize {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(size),
                                                               countStyle: .file))
                                    .font(Theme.mono(10)).foregroundStyle(Theme.text3)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 10)
                    }
                }
                .padding(8)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.leading, 23)
    }

    /// What the workflows build from. It answers the question a red run raises
    /// second: which branch was that, and is there a pull request behind it.
    @ViewBuilder private var sources: some View {
        Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("The connected repositories")
                    .font(Theme.font(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                QuietButton(title: "Fetch the repositories") { loadSources() }
                    .disabled(busy)
            }
            if repositoriesLoaded, repositories.isEmpty {
                Text("App Store Connect has no source-control connection. You make one in Xcode when you create the first workflow.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(repositories) { repository in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(repository.name).font(Theme.font(size: 11.5, weight: .medium))
                        if let owner = repository.owner {
                            Text(owner).font(Theme.font(size: 10.5))
                                .foregroundStyle(Theme.text3)
                        }
                        Spacer(minLength: 8)
                        Text("\(repository.references.count) branches  ·  \(repository.pullRequests.count) open pull requests")
                            .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                    ForEach(repository.pullRequests.prefix(5), id: \.self) { request in
                        Text(request).font(Theme.font(size: 10.5))
                            .foregroundStyle(Theme.text3).lineLimit(1)
                            .padding(.leading, 10)
                    }
                }
                .padding(.vertical, 3)
            }
        }
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

    /// The steps come first, then each step's own failures and files. One step
    /// that answers an error costs the others nothing, which is what a run
    /// still in progress looks like.
    private func toggle(_ run: XcodeCloudClient.BuildRun) {
        if openRuns.contains(run.id) {
            openRuns.remove(run.id)
            return
        }
        openRuns.insert(run.id)
        guard actions[run.id] == nil else { return }
        track($busy, $error) {
            let steps = try await state.xcodeCloudActions(runID: run.id)
            actions[run.id] = steps
            for step in steps {
                artifacts[step.id] = try? await state.xcodeCloudArtifacts(actionID: step.id)
                failures[step.id] = try? await state.xcodeCloudTestFailures(actionID: step.id)
            }
        }
    }

    private func loadSources() {
        track($busy, $error) {
            repositories = try await state.xcodeCloudRepositories()
            repositoriesLoaded = true
        }
    }

    private func setEnabled(_ workflow: XcodeCloudClient.Workflow, _ enabled: Bool) {
        track($busy, $error) {
            try await state.setXcodeCloudWorkflowEnabled(workflow.id, enabled: enabled)
            workflows = try await state.xcodeCloudWorkflows()
        }
    }
}

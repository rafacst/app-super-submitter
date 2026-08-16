import SwiftUI

/// The temporary progress and API call log for one remote draft save.
struct RemoteSaveTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            status
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Store calls")
                        .font(Theme.font(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(state.remoteSaveLoggedCalls) calls")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.text3)
                }
                LogView(lines: state.remoteSaveLogLines, height: 320,
                        copyText: state.remoteSaveLogText)
            }
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                if state.directApplyState == .running || state.planReading {
                    Spinner()
                } else {
                    Image(systemName: state.directApplyState == .failed
                          ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(state.directApplyState == .failed
                                         ? Theme.red : Theme.green)
                }
                Text(state.remoteSaveSourceTitle.isEmpty
                     ? "Remote draft save" : "Save \(state.remoteSaveSourceTitle) remotely")
                    .font(Theme.font(size: 14, weight: .semibold))
            }
            Text(state.remoteSaveDetail)
                .font(Theme.font(size: 12))
                .foregroundStyle(state.directApplyState == .failed ? Theme.red : Theme.text2)
            if let progress = state.remoteSaveProgress {
                ProgressView(value: progress)
                Text("\(completedSteps) of \(state.remoteSaveStepStates.count) rows complete")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.text3)
            } else if state.directApplyState == .running || state.planReading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var completedSteps: Int {
        state.remoteSaveStepStates.filter {
            $0 == .done || $0 == .failed || $0 == .skipped
        }.count
    }
}

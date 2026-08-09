import SubmitKit
import SwiftUI

/// The raw block behind one tab. Spec section 16.1.
///
/// The form and this editor write the same file. The editor slices the
/// document by the top-level keys that the tab owns, so an edit here can never
/// drop a block that another tab holds.
struct YAMLEditor: View {
    @Environment(AppState.self) private var state
    let block: ManifestBlock

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text("The raw `store.yaml` block behind this tab.")
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                if state.yamlDirty {
                    Text("Not saved").font(Theme.font(size: 11.5)).foregroundStyle(Theme.yellow)
                    QuietButton(title: "Revert") { state.loadYAML(block) }
                }
                Button { state.saveYAML(block) } label: {
                    Text("Save the YAML")
                        .font(Theme.font(size: 12, weight: .medium))
                        .foregroundStyle(state.yamlDirty ? Theme.accentText : Theme.text3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(state.yamlDirty ? Theme.accent : Theme.sep2,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!state.yamlDirty)
            }

            TextEditor(text: Binding(
                get: { state.yamlText },
                set: { state.yamlText = $0; state.yamlDirty = true }))
                .font(Theme.mono(12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 320)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(state.yamlError == nil ? Theme.sep : Theme.red,
                                  lineWidth: state.yamlError == nil ? Theme.hairline : 1))

            if let error = state.yamlError {
                HStack(alignment: .top, spacing: 9) {
                    StatePill(text: "YAML", foreground: Theme.red, background: Theme.redBg)
                    Text(error)
                        .font(Theme.font(size: 12))
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: 940, alignment: .leading)
        .task(id: block) { state.loadYAML(block) }
    }
}

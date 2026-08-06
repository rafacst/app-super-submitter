import SubmitKit
import SwiftUI

/// The Android files that go into the edit next to the bundle.
///
/// They are paths, not drop wells, because something else produced them: the
/// Gradle build writes the mapping file and the symbols, and the app only
/// names them. Spec section 7.4, steps 6 to 9.
struct AndroidArtifactsSection: View {
    @Environment(AppState.self) private var state

    private static let fileFields: [AppState.ArtifactField] = [
        .apk, .mappingFile, .nativeSymbols, .expansionMain, .expansionPatch, .deviceTierConfig,
    ]

    var body: some View {
        Section_("Android artifacts", icon: "shippingbox.fill", tint: Theme.playGreen) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.fileFields, id: \.self) { field in
                    HStack(spacing: 10) {
                        Text(field.label)
                            .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                            .frame(width: 150, alignment: .leading)
                        TextField("Path, relative to the manifest",
                                  text: state.artifactBinding(field))
                            .frame(maxWidth: 340)
                        Button("Choose…") { chooseFile(field) }
                            .controlSize(.small)
                        Text(field.hint)
                            .font(.system(size: 11)).foregroundStyle(Theme.text3)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                externalApk
            }
            .storePanel()
        }
    }

    @ViewBuilder
    private var externalApk: some View {
        Divider().overlay(Theme.sep)
        if state.hasExternalApk {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Externally hosted APK")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Button(role: .destructive) { state.removeExternalApk() } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
                Text("Google accepts this from a Google Play organization only. A normal account answers 403.")
                    .font(.system(size: 11)).foregroundStyle(Theme.yellow)
                HStack {
                    TextField("https://…", text: state.externalApkBinding(.url))
                    TextField("Application label", text: state.externalApkBinding(.label))
                        .frame(width: 160)
                }
                HStack {
                    TextField("Version code", text: state.externalApkBinding(.versionCode))
                        .frame(width: 110)
                    TextField("Version name", text: state.externalApkBinding(.versionName))
                        .frame(width: 120)
                    TextField("Minimum SDK", text: state.externalApkBinding(.minimumSdk))
                        .frame(width: 110)
                }
                TextField("Signing certificates, base64, comma-separated",
                          text: state.externalApkBinding(.certificates))
            }
        } else {
            Button("Add an externally hosted APK") { state.addExternalApk() }
                .controlSize(.small)
        }
    }

    private func chooseFile(_ field: AppState.ArtifactField) {
        let extensions: [String] = switch field {
        case .apk: ["apk"]
        case .mappingFile: ["txt", "map"]
        case .nativeSymbols: ["zip"]
        case .expansionMain, .expansionPatch: ["obb"]
        case .deviceTierConfig: ["json"]
        }
        guard let url = state.chooseOneFile(allowedExtensions: extensions) else { return }
        state.artifactBinding(field).wrappedValue = state.relativePath(for: url)
    }
}

/// The tracks that an apply writes and the countries that a release reaches.
struct GoogleTracksSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section_("Google tracks and rollout", icon: "chart.line.uptrend.xyaxis", tint: Theme.playBlue) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    LabeledContent("Release track") {
                        TextField("production", text: state.googlePrimaryTrackBinding)
                            .frame(width: 150)
                    }
                    Text("The one track that the Release tab sends.")
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    LabeledContent("Write these tracks") {
                        TextField("internal, production", text: state.googleTracksBinding)
                            .frame(width: 260)
                    }
                    Text("One edit reaches them all. Empty means the release track alone.")
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    Spacer(minLength: 0)
                }
                Divider().overlay(Theme.sep)
                HStack(spacing: 10) {
                    LabeledContent("Countries") {
                        TextField("US, DE, BR", text: state.googleCountriesBinding)
                            .frame(width: 260)
                    }
                    Toggle("Include the rest of the world",
                           isOn: state.googleRestOfWorldBinding)
                        .disabled(state.googleCountriesBinding.wrappedValue.isEmpty)
                    Spacer(minLength: 0)
                }
                Text("An empty country list reaches every country. Two-letter uppercase codes.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            .storePanel()
        }
    }
}

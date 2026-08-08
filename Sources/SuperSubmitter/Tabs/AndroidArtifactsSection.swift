import SubmitKit
import SwiftUI

/// The Android files that go into the edit next to the bundle.
///
/// They are paths, not drop wells, because something else produced them: the
/// Gradle build writes the mapping file and the symbols, and the app only
/// names them. Spec section 7.4, steps 6 to 9.
struct AndroidArtifactsSection: View {
    @Environment(AppState.self) private var state

    /// The three a normal Android release names.
    private static let common: [AppState.ArtifactField] = [
        .apk, .mappingFile, .nativeSymbols,
    ]

    /// The three that only an APK release or a device-tier build ever needs.
    ///
    /// A bundle carries its own assets, so the two expansion files apply to an
    /// APK alone, and most apps ship neither. Six boxes on first sight said
    /// they were all part of the job.
    private static let rare: [AppState.ArtifactField] = [
        .expansionMain, .expansionPatch, .deviceTierConfig,
    ]

    /// Open when one of them holds a value. A path folded out of sight is a
    /// path nobody can find again.
    @State private var showRare = false

    var body: some View {
        Section_("Android artifacts", icon: "shippingbox.fill", tint: Theme.playGreen,
                 anchor: "build.androidArtifacts") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.common, id: \.self) { field in
                    pathRow(field)
                }
                DisclosureGroup("Expansion files and device tiers", isExpanded: $showRare) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.rare, id: \.self) { field in
                            pathRow(field)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 12))
                externalApk
            }
            .storePanel()
            .onAppear { showRare = Self.rare.contains { !state.artifactBinding($0).wrappedValue.isEmpty } }
        }
    }

    private func pathRow(_ field: AppState.ArtifactField) -> some View {
        let binding = state.artifactBinding(field)
        return LabeledField(field.label, note: field.hint) {
            PathField(path: binding,
                      problem: state.missingFileNote(for: binding.wrappedValue)) {
                chooseFile(field)
            }
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
        Section_("Google tracks and rollout", icon: "chart.line.uptrend.xyaxis",
                 tint: Theme.playBlue, anchor: "build.googleTracks") {
            VStack(alignment: .leading, spacing: 11) {
                LabeledField("Release track", anchor: "build.releaseTrack") {
                    ChoiceField(value: state.googlePrimaryTrackBinding,
                                choices: StoreValues.googleTracks,
                                emptyLabel: "Pick a track", allowsNone: false)
                }
                LabeledField("Write these tracks") {
                    MultiChoiceField(text: state.googleTracksBinding,
                                     choices: StoreValues.googleTracks,
                                     emptyLabel: "The release track alone")
                }
                Text("The release track is the one the Release tab sends. One edit reaches every track you write.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Theme.sep)
                LabeledField("Countries", anchor: "build.countries") {
                    MultiChoiceField(text: state.googleCountriesBinding,
                                     choices: StoreValues.googleCountries,
                                     emptyLabel: "Every country")
                }
                Toggle("Include the rest of the world", isOn: state.googleRestOfWorldBinding)
                    .disabled(state.googleCountriesBinding.wrappedValue.isEmpty)
                    .font(.system(size: 12))
                testers
            }
            .storePanel()
        }
    }

    /// Who may install a closed track.
    ///
    /// Production reaches everybody, so it takes no list and gets no row. Every
    /// other track the apply writes reaches nobody until a group is named here,
    /// and the apply has always sent this field.
    @ViewBuilder
    private var testers: some View {
        let closed = state.manifest.googleTracks.filter { $0 != "production" }
        if !closed.isEmpty {
            Divider().overlay(Theme.sep)
            VStack(alignment: .leading, spacing: 9) {
                Text("Track testers").font(.system(size: 12, weight: .semibold))
                    .fieldAnchor("build.googleTesters")
                ForEach(closed, id: \.self) { track in
                    LabeledField(track, note: "Google Groups, comma-separated") {
                        TextField("beta-testers@googlegroups.com",
                                  text: state.googleTestersBinding(track: track))
                    }
                }
                Text("Google takes group addresses only. It keeps the single tester list in the Play Console, and it replaces the whole list on every apply.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

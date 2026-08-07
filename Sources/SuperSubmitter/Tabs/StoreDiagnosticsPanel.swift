import AppKit
import SubmitKit
import SwiftUI

/// Read-only store artifacts that used to exist only as unreachable AppState
/// methods. A deliberate button keeps these relatively expensive calls out of
/// normal tab rendering.
struct StoreDiagnosticsPanel: View {
    @Environment(AppState.self) private var state
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var apks: [StoreDiagnostics.GeneratedApk] = []
    @State private var tiers: [StoreDiagnostics.DeviceTierConfig] = []
    @State private var bundles: [StoreDiagnostics.BuildBundle] = []
    @State private var icons: [String] = []
    @State private var territories: [StoreDiagnostics.Territory] = []
    @State private var categories: [StoreDiagnostics.AppCategory] = []

    var body: some View {
        Section_("Store diagnostics", icon: "stethoscope", tint: Theme.teal) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Inspect generated artifacts and store reference data without changing a draft.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    Spacer()
                    QuietButton(title: loading ? "Fetching…" : "Fetch diagnostics") { load() }
                        .disabled(loading)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
                } else if loaded {
                    diagnosticsGrid
                    if !apks.isEmpty { generatedApks }
                    if !tiers.isEmpty { deviceTiers }
                    if !bundles.isEmpty { buildBundles }
                    if !icons.isEmpty { buildIcons }
                    if !territories.isEmpty || !categories.isEmpty { referenceData }
                }
            }
            .padding(14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }

    private var diagnosticsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
            diagnosticRow("Generated APKs", value: apks.count)
            diagnosticRow("Device tier configurations", value: tiers.count)
            diagnosticRow("Apple build bundles", value: bundles.count)
            diagnosticRow("Apple build icons", value: icons.count)
            diagnosticRow("App Store territories", value: territories.count)
            diagnosticRow("App Store categories", value: categories.count)
        }
        .font(.system(size: 12))
    }

    private func diagnosticRow(_ label: String, value: Int) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.text2)
            Text(value.formatted()).fontWeight(.medium)
        }
    }

    private var generatedApks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Google generated APKs").font(.system(size: 12, weight: .semibold))
            ForEach(apks) { apk in
                HStack {
                    Text(apk.kind).frame(width: 80, alignment: .leading)
                    Text(apk.downloadId).fontDesign(.monospaced).textSelection(.enabled)
                    Spacer()
                    Button("Download") { download(apk) }.controlSize(.small)
                }
                .font(.system(size: 11.5))
            }
        }
    }

    private var buildBundles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apple build contents").font(.system(size: 12, weight: .semibold))
            ForEach(bundles) { bundle in
                HStack {
                    Text(bundle.name ?? bundle.id).textSelection(.enabled)
                    Spacer()
                    Text(bundle.kind ?? "bundle").foregroundStyle(Theme.text2)
                    if let size = bundle.fileSizeBytes {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .foregroundStyle(Theme.text2)
                    }
                }
                .font(.system(size: 11.5))
            }
        }
    }

    private var deviceTiers: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Google device tier configurations")
                .font(.system(size: 12, weight: .semibold))
            ForEach(tiers) { tier in
                Text("\(tier.id) · \(tier.groupCount) groups")
                    .font(Theme.mono(11)).textSelection(.enabled)
            }
        }
    }

    private var buildIcons: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Apple build icons").font(.system(size: 12, weight: .semibold))
            ForEach(icons, id: \.self) { value in
                if let url = URL(string: value) {
                    Link(value, destination: url).font(.system(size: 11))
                } else {
                    Text(value).font(Theme.mono(11)).textSelection(.enabled)
                }
            }
        }
    }

    private var referenceData: some View {
        DisclosureGroup("Territories and app categories") {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !territories.isEmpty {
                        Text("Territories").font(.system(size: 11.5, weight: .semibold))
                        Text(territories.map { territory in
                            territory.currency.map { "\(territory.id) (\($0))" } ?? territory.id
                        }.joined(separator: ", "))
                        .font(Theme.mono(10.5)).textSelection(.enabled)
                    }
                    if !categories.isEmpty {
                        Text("Categories").font(.system(size: 11.5, weight: .semibold))
                        Text(categories.map(\.id).joined(separator: ", "))
                            .font(Theme.mono(10.5)).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
        }
        .font(.system(size: 11.5))
    }

    private func load() {
        loading = true
        error = nil
        Task {
            do {
                async let readTiers = state.googleDeviceTierConfigs()
                async let readBundles = state.appleBuildBundles()
                async let readIcons = state.appleBuildIcons()
                async let readTerritories = state.appleTerritories()
                async let readCategories = state.appleAppCategories()
                let version = state.actualState.google?.highestVersionCode
                async let readApks = loadApks(version)
                (apks, tiers, bundles, icons, territories, categories) = try await (
                    readApks, readTiers, readBundles, readIcons, readTerritories, readCategories)
                loaded = true
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func loadApks(_ version: Int?) async throws
        -> [StoreDiagnostics.GeneratedApk] {
        guard let version else { return [] }
        return try await state.googleGeneratedApks(versionCode: version)
    }

    private func download(_ apk: StoreDiagnostics.GeneratedApk) {
        guard let package = state.manifest.apps.google?.packageName,
              let version = state.actualState.google?.highestVersionCode else { return }
        Task {
            do {
                let directory = FileManager.default.urls(for: .downloadsDirectory,
                                                         in: .userDomainMask)[0]
                    .appendingPathComponent("Super Submitter", isDirectory: true)
                let url = try await state.diagnostics().downloadGeneratedApk(
                    packageName: package, versionCode: version,
                    downloadId: apk.downloadId, to: directory)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

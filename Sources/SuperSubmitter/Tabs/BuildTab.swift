import SubmitKit
import SwiftUI

/// Tab 2. Dropped packages are parsed by SubmitKit and immediately update the
/// release/build paths and build-derived listing fields in `store.yaml`.
struct BuildTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            versionSection
            source
            if state.showBuildFromProject {
                BuildFromProjectView()
            } else {
                importSection
            }
            StoreDiagnosticsPanel()
            if state.stores.contains(.apple) { XcodeCloudPanel() }
            // A lapsed certificate reads as a failed build, so it belongs
            // beside the build and not on a tab of its own.
            if state.stores.contains(.apple) { SigningIdentitiesPanel() }
            if state.stores.contains(.google) { InternalSharingPanel() }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    /// The number this submission carries, and the only place that takes one.
    ///
    /// It used to arrive from a package or from an import and from nowhere
    /// else. An update with no build attached kept whatever the import read,
    /// and the Summary's "Version 1.2 is not above 1.4, which is live on the
    /// App Store" sent the developer to this tab, which showed a version and
    /// never took one. Its own error had no fix on the tab it named.
    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Version").font(.system(size: 12.5, weight: .semibold))
                TextField("1.0", text: state.releaseVersionBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .monospacedDigit()
                if let live = state.liveAppleVersion {
                    Text(verbatim: "\(live) is live on the App Store")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                // Only when it would change something. A button offering the
                // number already in the field is a button that does nothing.
                if let next = state.nextAppleVersion,
                   next != state.manifest.release?.versionName {
                    QuietButton(title: "Use \(next)") { state.useReleaseVersion(next) }
                }
            }
            Text("Apple refuses a version that does not climb past the one on sale. A package you import fills this in while it is empty.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    /// Two ways to get a build: run the project, or import a package that
    /// something else produced. Both feed the same inspection and the same
    /// upload confirmation. upload-spec 10.1 and 13.3.
    private var source: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { fromProject in
                let selected = state.showBuildFromProject == fromProject
                Button {
                    state.showBuildFromProject = fromProject
                } label: {
                    Text(fromProject ? "Build from project" : "Import a package")
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.accentText : Theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(selected ? Theme.accent : .clear)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(Theme.sunken)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // One row, one height. Each box stretches to the taller of the
            // two, so the rule between them runs the whole way down.
            HStack(alignment: .top, spacing: 14) {
                submitBuilds
                Rectangle().fill(Theme.sep2).frame(width: 1)
                updateExistingApp
            }
            .fixedSize(horizontal: false, vertical: true)

            if !state.packages.isEmpty {
                packageCards
                filledLine
                ForEach(validationMessages, id: \.self) { message in
                    WarningLine(message: message)
                }
                if let mismatch = versionMismatch {
                    versionWarning(mismatch)
                }
            }
            // Side by side. Both answer "what goes into the Google edit", and
            // stacked they left the right half of a 980 point tab empty.
            if state.stores.contains(.google) {
                HStack(alignment: .top, spacing: 14) {
                    AndroidArtifactsSection()
                    GoogleTracksSection().frame(width: 330)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var submitBuilds: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Submit a build").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 9) {
                PackageDropWell(
                    title: state.packages[.ipa]?.url.lastPathComponent ?? "iOS package",
                    prompt: ".ipa · drop here or",
                    extensions: ["ipa"], reading: state.readingPackages.contains(.ipa),
                    error: state.packageErrors[.ipa],
                    note: state.missingBuildNote(.ipa),
                    choose: { state.chooseBuildFiles(allowedExtensions: ["ipa"]) },
                    accept: state.importPackages)
                PackageDropWell(
                    title: state.packages[.pkg]?.url.lastPathComponent ?? "Mac App Store package",
                    prompt: ".pkg · drop here or",
                    extensions: ["pkg"], reading: state.readingPackages.contains(.pkg),
                    error: state.packageErrors[.pkg],
                    note: state.missingBuildNote(.pkg),
                    choose: { state.chooseBuildFiles(allowedExtensions: ["pkg"]) },
                    accept: state.importPackages)
                PackageDropWell(
                    title: state.packages[.aab]?.url.lastPathComponent ?? "Android package",
                    prompt: ".aab · drop here or",
                    extensions: ["aab"], reading: state.readingPackages.contains(.aab),
                    error: state.packageErrors[.aab],
                    note: state.missingBuildNote(.aab),
                    choose: { state.chooseBuildFiles(allowedExtensions: ["aab"]) },
                    accept: state.importPackages)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var updateExistingApp: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Update an app that exists").font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 4) {
                    StoreLabel(store: .apple, size: 11, weight: .medium, color: Theme.text2)
                    if state.remoteAppleApps.isEmpty {
                        PickerActionRow(value: state.appleAppID.isEmpty ? "Connect and test App Store first" : state.appleBundleID) {
                            state.selectedTab = .stores
                        }
                    } else {
                        Menu {
                            ForEach(state.remoteAppleApps) { app in
                                Button("\(app.name) · \(app.identifier)") {
                                    state.chooseRemoteAppleApp(app)
                                }
                            }
                        } label: {
                            PickerLabel(value: state.appleBundleID.isEmpty ? "Choose an app" : state.appleBundleID)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    StoreLabel(store: .google, size: 11, weight: .medium, color: Theme.text2)
                    PickerActionRow(value: state.googlePackageName.isEmpty
                                    ? "Set and test a package on Stores"
                                    : state.googlePackageName) {
                        state.selectedTab = .stores
                    }
                }
            }

            Text("App Store apps come from the connected account. Android Publisher cannot list apps, so Google uses the tested package name from Stores.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                QuietButton(
                    title: state.listingImportStatus == .connecting ? "Fetching…" : "Fetch the current listings",
                    action: state.importExistingListing)
                    .disabled(state.listingImportStatus == .connecting)
                switch state.listingImportStatus {
                case .connected(let message):
                    Text(message).foregroundStyle(Theme.green)
                case .failed(let message):
                    WarningNote(message)
                default:
                    EmptyView()
                }
            }
            .font(.system(size: 11.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var sortedPackages: [AppPackage] {
        AppPackage.Kind.allCases.compactMap { state.packages[$0] }
    }

    private var packageCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(sortedPackages, id: \.kind) { package in
                    PackageCard(package: package)
                }
            }
            // An imported package skips the source build and skips nothing
            // else: the same inspection, signature check, identity comparison,
            // remote conflict check, and upload confirmation apply.
            HStack(spacing: 9) {
                ForEach(sortedPackages, id: \.kind) { package in
                    QuietButton(title: "Inspect and upload \(package.url.lastPathComponent)") {
                        state.showBuildFromProject = true
                        state.buildFlow.adoptImported(package.url)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var filledLine: some View {
        let count = sortedPackages.reduce(0) { $0 + $1.filledFieldCount }
        return HStack(spacing: 14) {
            Text("Inspected \(count) build fields and saved their manifest values.")
                .font(.system(size: 12.5))
            QuietButton(title: "Open Details") { state.selectedTab = .details }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var versionMismatch: (apple: String, google: String)? {
        let apple = state.packages[.ipa]?.versionName ?? state.packages[.pkg]?.versionName
        let google = state.packages[.aab]?.versionName
        guard let apple, let google, apple != google else { return nil }
        return (apple, google)
    }

    private var validationMessages: [String] {
        sortedPackages.compactMap { package in
            switch package.kind {
            case .ipa, .pkg:
                guard let expected = state.manifest.apps.apple?.bundleId,
                      !expected.isEmpty, let actual = package.identifier,
                      expected != actual else { return nil }
                return "\(package.url.lastPathComponent) uses \(actual), but the selected App Store app uses \(expected)."
            case .aab:
                guard let expected = state.manifest.apps.google?.packageName,
                      !expected.isEmpty, let actual = package.identifier,
                      expected != actual else { return nil }
                return "\(package.url.lastPathComponent) uses \(actual), but the selected Google Play app uses \(expected)."
            }
        }
    }

    private func versionWarning(_ mismatch: (apple: String, google: String)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text("The version name differs between the Apple and Android packages.")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Apple reads \(mismatch.apple); Google reads \(mismatch.google). Choose the release name that the manifest should use.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            QuietButton(title: "Use \(mismatch.apple)") {
                state.useReleaseVersion(mismatch.apple)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.yellow, lineWidth: 1))
    }
}

private struct PackageDropWell: View {
    let title: String
    let prompt: String
    let extensions: Set<String>
    let reading: Bool
    /// A package that was dropped and could not be read. This is a fault.
    let error: String?
    /// The manifest names a path and nothing sits there yet.
    ///
    /// Its own channel, and it has to be. This is the state every app is in
    /// before its first build, so all three wells carried it, in red, on the
    /// first launch: three faults reported for a developer who had done
    /// nothing wrong. Red is what the app says when a drop failed, and it
    /// only keeps that meaning while the ordinary case is quiet.
    var note: String?
    let choose: () -> Void
    let accept: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.field)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                    .frame(width: 26, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading ? "Inspecting \(title)…" : title)
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 3) {
                        Text(prompt).foregroundStyle(Theme.text2)
                        Button("choose a file…", action: choose)
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                    .font(.system(size: 11))
                }
                Spacer(minLength: 0)
                if reading { ProgressView().controlSize(.small) }
            }
            if let error {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let note {
                Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(targeted ? Theme.field : Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(targeted ? Theme.accent : Theme.controlEdge,
                          style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [3, 3])))
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { extensions.contains($0.pathExtension.lowercased()) }
            guard !accepted.isEmpty else { return false }
            accept(accepted)
            return true
        } isTargeted: { targeted = $0 }
    }
}

private struct PackageCard: View {
    let package: AppPackage

    var rows: [(String, String)] {
        [
            (package.kind == .aab ? "Package name" : "Bundle id", package.identifier ?? "Not found"),
            ("Version name", package.versionName ?? "Not found"),
            (package.kind == .aab ? "Version code" : "Build number", package.buildNumber ?? "Not found"),
            ("App name", package.appName ?? "Not found"),
            ("Languages", package.locales.isEmpty ? "None declared" : package.locales.joined(separator: ", ")),
            (package.kind == .aab ? "Minimum SDK" : "Minimum OS", package.minimumOS ?? "Not found"),
            ("Devices", package.deviceClasses.isEmpty ? "Not declared" : package.deviceClasses.joined(separator: ", ")),
            ("Encryption", package.usesNonExemptEncryption.map { $0 ? "Uses non-exempt encryption" : "No non-exempt encryption" } ?? "Not applicable"),
            ("Privacy", "\(package.privacyHints.count) hints found"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 9).fill(Theme.sunken)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(package.kind.rawValue.uppercased()) · \(package.url.lastPathComponent)")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(package.url.path).font(Theme.mono(10.5)).foregroundStyle(Theme.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.0).foregroundStyle(Theme.text2).frame(width: 105, alignment: .leading)
                        Text(row.1).font(Theme.mono(11.5))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 15).padding(.vertical, 5)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

private struct PickerLabel: View {
    let value: String
    var body: some View {
        HStack {
            Text(value)
            Spacer()
            Text("▾").font(.system(size: 9)).foregroundStyle(Theme.text3)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
    }
}

private struct PickerActionRow: View {
    let value: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { PickerLabel(value: value) }
            .buttonStyle(.plain)
    }
}

private struct WarningLine: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.red, lineWidth: 1))
    }
}

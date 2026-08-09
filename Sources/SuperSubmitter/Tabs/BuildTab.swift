import SubmitKit
import SwiftUI

/// Tab 2. Dropped packages are parsed by SubmitKit and immediately update the
/// release/build paths and build-derived listing fields in `store.yaml`.
struct BuildTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            source.frame(maxWidth: .infinity, alignment: .trailing)
            storeIdentitySection
            if state.showBuildFromProject {
                BuildFromProjectView()
            } else {
                importSection
            }
            storeTools
        }
        .frame(maxWidth: 1040, alignment: .leading)
    }

    /// Two ways to get a build: run the project, or import a package that
    /// something else produced. Both feed the same inspection and the same
    /// upload confirmation. upload-spec 10.1 and 13.3.
    ///
    /// The chips above it are `ApplePlatformStandings`.
    private var source: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { fromProject in
                let selected = state.showBuildFromProject == fromProject
                Button {
                    state.showBuildFromProject = fromProject
                } label: {
                    Text(fromProject ? "Build from project" : "Import a package")
                        .font(Theme.font(size: 12, weight: selected ? .semibold : .regular))
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

    private var storeIdentitySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("This app in the stores")
                .font(Theme.font(size: 13.5, weight: .semibold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    if state.stores.contains(.apple) { appleIdentity }
                    if state.stores.contains(.google) { googleIdentity }
                }
                VStack(alignment: .leading, spacing: 10) {
                    if state.stores.contains(.apple) { appleIdentity }
                    if state.stores.contains(.google) { googleIdentity }
                }
            }

            Divider().overlay(Theme.sep)
            versionRow

            HStack(alignment: .top, spacing: 10) {
                QuietButton(
                    title: state.listingImportStatus == .connecting
                        ? "Fetching…" : "Fetch the current listings",
                    action: state.importExistingListing)
                    .disabled(state.listingImportStatus == .connecting)
                switch state.listingImportStatus {
                case .connected(let message):
                    Text(message).foregroundStyle(Theme.green)
                case .failed(let message):
                    WarningNote(message)
                default:
                    Text("The store owns these identifiers; importing an existing listing fills them in.")
                        .foregroundStyle(Theme.text3)
                }
            }
            .font(Theme.font(size: 11.5))
        }
        .storePanel(padding: 14, horizontal: 15)
    }

    /// The store owns these three, and this tab shows them.
    ///
    /// Only one of them is ever a control here, and only sometimes: the bundle
    /// id becomes a menu once a read has answered with the apps of the team.
    /// Every other case is a fact, so it is drawn as one. They were buttons
    /// that jumped to Stores, which is a field-shaped thing that cannot be
    /// edited answering a click by leaving the screen. The way to a value that
    /// is missing is a sentence with a button in it, under the row, where a
    /// call to action can say what it will do.
    private var appleIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoreLabel(store: .apple, size: 11, weight: .medium, color: Theme.text2)
            Text("Bundle id · App id")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            HStack(spacing: 8) {
                if state.remoteAppleApps.isEmpty {
                    identityValue(state.appleBundleID, placeholder: "Bundle id")
                } else {
                    Menu {
                        ForEach(state.remoteAppleApps) { app in
                            Button("\(app.name) · \(app.identifier)") {
                                state.chooseRemoteAppleApp(app)
                            }
                        }
                    } label: {
                        PickerLabel(value: state.appleBundleID.isEmpty
                                    ? "Choose an app" : state.appleBundleID)
                    }
                    .menuStyle(.borderlessButton)
                }
                identityValue(state.appleAppID, placeholder: "App id", width: 120)
                Spacer(minLength: 0)
            }
            if state.appleBundleID.isEmpty, state.remoteAppleApps.isEmpty {
                missingIdentityNote("Connect App Store Connect to choose the app.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var googleIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoreLabel(store: .google, size: 11, weight: .medium, color: Theme.text2)
            Text("Package name")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            identityValue(state.googlePackageName, placeholder: "Package name")
            if state.googlePackageName.isEmpty {
                missingIdentityNote("Set and test a package name on Stores.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func identityValue(_ value: String, placeholder: String,
                               width: CGFloat? = nil) -> some View {
        Text(value.isEmpty ? placeholder : value)
            .font(Theme.mono(11.5))
            .foregroundStyle(value.isEmpty ? Theme.text3 : Theme.text)
            .lineLimit(1)
            .textSelection(.enabled)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private func missingIdentityNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            QuietButton(title: "Open Stores") { state.selectedTab = .stores }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var versionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Release version").font(Theme.font(size: 11.5, weight: .medium))
            TextField("1.0", text: state.releaseVersionBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
                .monospacedDigit()
            if let live = state.liveAppleVersion {
                Text(verbatim: "\(live) is live on the App Store")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if let next = state.nextAppleVersion,
               next != state.manifest.release?.versionName {
                QuietButton(title: "Use \(next)") { state.useReleaseVersion(next) }
            }
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            storeBuildColumns
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
        }
    }

    private var storeBuildColumns: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                if state.stores.contains(.apple) {
                    appleBuildCard
                        .frame(minWidth: 0, maxWidth: .infinity,
                               maxHeight: .infinity, alignment: .top)
                }
                if state.stores.contains(.google) {
                    googleBuildCard
                        .frame(minWidth: 0, maxWidth: .infinity,
                               maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                if state.stores.contains(.apple) {
                    TestFlightSection()
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                }
                if state.stores.contains(.google) {
                    googleOptions
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    private var appleBuildCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            storeBuildHeader(.apple, title: "App Store takes", detail: ".ipa or .pkg")
            PackageDropWell(
                title: state.packages[.ipa]?.url.lastPathComponent ?? "iOS package",
                prompt: ".ipa · drop here or",
                extensions: ["ipa"], reading: state.readingPackages.contains(.ipa),
                error: state.packageErrors[.ipa], note: state.missingBuildNote(.ipa),
                choose: { state.chooseBuildFiles(allowedExtensions: ["ipa"]) },
                accept: state.importPackages)
            PackageDropWell(
                title: state.packages[.pkg]?.url.lastPathComponent ?? "Mac App Store package",
                prompt: ".pkg · drop here or",
                extensions: ["pkg"], reading: state.readingPackages.contains(.pkg),
                error: state.packageErrors[.pkg], note: state.missingBuildNote(.pkg),
                choose: { state.chooseBuildFiles(allowedExtensions: ["pkg"]) },
                accept: state.importPackages)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .storePanel(padding: 14, horizontal: 15)
    }

    private var googleBuildCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            storeBuildHeader(.google, title: "Google Play takes", detail: ".aab or .apk")
            PackageDropWell(
                title: state.packages[.aab]?.url.lastPathComponent ?? "Android package",
                prompt: ".aab · drop here or",
                extensions: ["aab"], reading: state.readingPackages.contains(.aab),
                error: state.packageErrors[.aab], note: state.missingBuildNote(.aab),
                choose: { state.chooseBuildFiles(allowedExtensions: ["aab"]) },
                accept: state.importPackages)
            Text("Play has no TestFlight equivalent. Testers and rollout belong to the track below.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .storePanel(padding: 14, horizontal: 15)
    }

    private func storeBuildHeader(_ store: Store, title: String,
                                  detail: String) -> some View {
        HStack(spacing: 8) {
            StoreMark(store: store, size: 16)
            Text(title).font(Theme.font(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(detail).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
        }
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var googleOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            GoogleTracksSection()
            AndroidArtifactsSection()
        }
    }

    private var storeTools: some View {
        Section_("Store tooling", icon: "wrench.and.screwdriver.fill",
                 tint: Theme.purple, folds: true, startsOpen: false,
                 note: "Diagnostics, Xcode Cloud, signing identities, and internal sharing") {
            VStack(alignment: .leading, spacing: 14) {
                StoreDiagnosticsPanel()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        if state.stores.contains(.apple) {
                            VStack(alignment: .leading, spacing: 14) {
                                XcodeCloudPanel()
                                SigningIdentitiesPanel()
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        if state.stores.contains(.google) {
                            InternalSharingPanel()
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        if state.stores.contains(.apple) {
                            XcodeCloudPanel()
                            SigningIdentitiesPanel()
                        }
                        if state.stores.contains(.google) { InternalSharingPanel() }
                    }
                }
            }
        }
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
                .font(Theme.font(size: 12.5))
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
            Text("!").font(Theme.font(size: 13, weight: .bold)).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text("The version name differs between the Apple and Android packages.")
                    .font(Theme.font(size: 12.5, weight: .medium))
                Text("Apple reads \(mismatch.apple); Google reads \(mismatch.google). Choose the release name that the manifest should use.")
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
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
                        .font(Theme.font(size: 12, weight: .medium))
                    HStack(spacing: 3) {
                        Text(prompt).foregroundStyle(Theme.text2)
                        Button("choose a file…", action: choose)
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                    .font(Theme.font(size: 11))
                }
                Spacer(minLength: 0)
                if reading { ProgressView().controlSize(.small) }
            }
            if let error {
                Text(error).font(Theme.font(size: 10.5)).foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let note {
                Text(note).font(Theme.font(size: 10.5)).foregroundStyle(Theme.text2)
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
        .motion(.easeOut(duration: 0.12), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { extensions.contains($0.pathExtension.lowercased()) }
            // A wrong extension is refused here, so the tick has to sit after
            // the filter and not before it. Three wells stand in a column and
            // an .aab dropped on the .ipa one is the common slip.
            guard !accepted.isEmpty else { return false }
            accept(accepted)
            Haptic.drop()
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
                        .font(Theme.font(size: 13, weight: .semibold)).lineLimit(1)
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
                    .font(Theme.font(size: 12))
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
            Text("▾").font(Theme.font(size: 9)).foregroundStyle(Theme.text3)
        }
        .font(Theme.font(size: 12))
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
    }
}

private struct WarningLine: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!").font(Theme.font(size: 13, weight: .bold)).foregroundStyle(Theme.red)
            Text(message).font(Theme.font(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.red, lineWidth: 1))
    }
}

/// Where each platform of this app id stands on the App Store.
///
/// One app id carries a version train per platform and they are not in step:
/// a Mac app can be on sale while its iOS twin has never left the draft. Every
/// other number on this tab is narrowed to the platform being submitted, so
/// before this the developer had one line, "1.5 is live on the App Store", and
/// no way to tell which platform it was talking about — or that the other one
/// was not out at all.
///
/// It costs no request of its own. `/v1/apps/{id}/appStoreVersions` answers for
/// every platform at once, and the state reader was already discarding all but
/// one. See `StoreImportReader.applePlatformStandings`.
///
/// It draws nothing until a read has happened. A row of chips that all said
/// "Not on the store" before the app had asked would be a wrong answer, and a
/// wrong answer about what is live is worse than no answer.
struct ApplePlatformStandings: View {
    @Environment(AppState.self) private var state

    /// The platforms the manifest declares, each with what the store said, and
    /// the ones the store answered for that the manifest does not name.
    private var rows: [(platform: Manifest.Platform,
                        standing: ActualState.Apple.PlatformStanding?)] {
        let read = state.actualState.apple?.platforms ?? []
        let declared = state.manifest.apps.apple?.platforms ?? []
        let extra = read.compactMap { Manifest.Platform(rawValue: $0.platform) }
            .filter { !declared.contains($0) }
        return (declared + extra).map { platform in
            (platform, read.first { $0.platform == platform.rawValue })
        }
    }

    var body: some View {
        let rows = rows
        if state.stores.contains(.apple), !(state.actualState.apple?.platforms ?? []).isEmpty,
           !rows.isEmpty {
            HStack(spacing: 7) {
                Text("On the App Store")
                    .font(Theme.font(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text3)
                    .textCase(.uppercase)
                    .kerning(0.3)
                ForEach(rows, id: \.platform) { row in
                    let standing = AppleStanding(row.standing)
                    StatePill(text: "\(row.platform.shortName) · \(standing.label)",
                              foreground: standing.tint, background: standing.fill)
                        .help(standing.detail(for: row.platform))
                        .accessibilityLabel("\(row.platform.shortName). \(standing.detail(for: row.platform))")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }
}

/// One platform's `AppVersionState`, in the words a developer uses.
///
/// Apple names fifteen states and they answer a question nobody asked on this
/// tab. What a developer wants before choosing a platform to submit is whether
/// that platform is out, on its way, stuck, or has never shipped, so the
/// fifteen collapse into five.
///
/// The live version decides the word. That is the question the chips exist for:
/// one app id ships on two platforms and only one of them is on sale. A version
/// on its way is the second question, and it goes in the tooltip with the
/// numbers, where the detail belongs.
///
/// Green means a customer can buy it. Yellow means Apple has it. Red means it
/// came back. Grey means nothing is on sale. No blue: blue is the accent this
/// app uses for a choice, and none of these is one.
struct AppleStanding {
    let label: String
    let tint: Color
    let fill: Color
    private let standing: ActualState.Apple.PlatformStanding?

    init(_ standing: ActualState.Apple.PlatformStanding?) {
        self.standing = standing
        (label, tint, fill) = Self.words(
            for: standing?.liveState ?? standing?.pendingState, hasVersion: standing != nil)
    }

    private static func words(for state: String?, hasVersion: Bool)
        -> (String, Color, Color) {
        switch state {
        case _ where !hasVersion, nil, "":
            ("Not on the store", Theme.text3, Theme.sunken)
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION":
            ("Live", Theme.green, Theme.greenBg)
        case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE":
            ("Off sale", Theme.text3, Theme.sunken)
        case "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "ACCEPTED":
            ("Approved", Theme.green, Theme.greenBg)
        case "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW",
             "PROCESSING_FOR_DISTRIBUTION", "WAITING_FOR_EXPORT_COMPLIANCE":
            ("In review", Theme.yellow, Theme.yellowBg)
        case "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY":
            ("Rejected", Theme.red, Theme.redBg)
        default:
            // PREPARE_FOR_SUBMISSION, and anything Apple adds after this ships.
            // A state this app has never heard of is still a draft: a version
            // that exists and is not on sale.
            ("Draft", Theme.text2, Theme.sunken)
        }
    }

    /// The numbers and the version on its way. The chip carries the word.
    func detail(for platform: Manifest.Platform) -> String {
        guard let standing else {
            return "\(platform.shortName) has no version on the App Store yet."
        }
        var parts: [String] = []
        if let live = standing.live { parts.append("\(live) is \(label.lowercased())") }
        if let pending = standing.pending {
            let word = Self.words(for: standing.pendingState, hasVersion: true).0
            parts.append("\(pending) is \(word.lowercased())")
        }
        if parts.isEmpty { return "\(platform.shortName): \(label)." }
        return "\(platform.shortName). " + parts.joined(separator: ", ") + "."
    }
}

import SubmitKit
import SwiftUI

/// Tab 2. Dropped packages are parsed by SubmitKit and immediately update the
/// release/build paths and build-derived listing fields in `store.yaml`.
struct BuildTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            storeIdentitySection
            questionRow
            if state.showBuildFromProject {
                BuildFromProjectView()
            } else {
                importSection
            }
            // Neither source above: the binary is in the store already. It
            // stands under both of them because it answers the same question
            // and it is the answer for an app whose build reached Apple by
            // Xcode, Transporter, or Xcode Cloud.
            if state.stores.contains(.apple) { AppleBuildsPanel() }
            storeTools
        }
        .frame(maxWidth: 1040, alignment: .leading)
    }

    /// The two questions this tab asks before there is a package: where the
    /// build comes from, and what Apple is owed about it.
    ///
    /// One row of two boxes of one height. The source switch was a bare
    /// segmented control floating over the top of the tab with nothing to say
    /// what it switched, and the answer to it changes everything below.
    private var questionRow: some View {
        HStack(alignment: .top, spacing: 14) {
            buildSource
                .frame(minWidth: 0, maxWidth: .infinity,
                       maxHeight: .infinity, alignment: .top)
            if state.stores.contains(.apple) {
                exportCompliance
                    .frame(minWidth: 0, maxWidth: .infinity,
                           maxHeight: .infinity, alignment: .top)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Two ways to get a build: run the project, or import a package that
    /// something else produced. Both feed the same inspection and the same
    /// upload confirmation. upload-spec 10.1 and 13.3.
    private var buildSource: some View {
        VStack(alignment: .leading, spacing: 9) {
            panelHead("shippingbox.fill", tint: Theme.accent, title: "Build source",
                      detail: "Where the package comes from")
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
                            .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .storePanel(padding: 10, horizontal: 13)
    }

    /// Apple's export compliance answer, on the tab that makes the build that
    /// owes it.
    ///
    /// It is a yes or no question, and it was a card two tabs away on the
    /// Details inspector, under a toggle that read an absent answer as a
    /// settled "no". Apple asks it once per build and refuses the submission
    /// without one, so the Build button waits for it: see
    /// `BuildFlow.blockingReason`, which tests exactly what this box shows.
    private var exportCompliance: some View {
        let unanswered = state.encryptionAnswer == nil
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                panelHead("lock.shield.fill",
                          tint: unanswered ? Theme.red : Theme.green,
                          title: "Export compliance",
                          detail: "Apple asks this once per build")
                if unanswered {
                    StatePill(text: "Needed", foreground: Theme.red,
                              background: Theme.redBg)
                }
            }
            // Two answers and no third, so a question nobody has answered
            // selects neither segment. A Bool could not say that, which is how
            // an unasked question came to draw a settled "no" over every app
            // that had never been asked.
            Picker("Export compliance", selection: Binding(
                get: { state.encryptionAnswer },
                set: { state.setEncryptionAnswer($0) })) {
                Text("Uses no non-exempt encryption").tag(Bool?.some(false))
                Text("It does use encryption").tag(Bool?.some(true))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // The answer above is what creates the need for this, so the
            // paperwork appears with the answer that owes it and stays out
            // of the way of every app that does not.
            if state.encryptionAnswer == true { ExportCompliance() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .storePanel(padding: 10, horizontal: 13,
                    border: unanswered ? Theme.red.opacity(0.3) : Theme.sep)
        .fieldAnchor("build.encryption")
    }

    /// The head both boxes wear: a glyph, the question, and who asks it.
    private func panelHead(_ icon: String, tint: Color, title: String,
                           detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(Theme.font(size: 11.5))
                .foregroundStyle(tint)
            Text(title).font(Theme.font(size: 12.5, weight: .medium))
            Text(detail)
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
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
        // The store has fixed them. See `AppState.storeFixedTheIdentifiers`.
        let fixed = state.storeFixedTheIdentifiers(.apple)
        return VStack(alignment: .leading, spacing: 4) {
            StoreLabel(store: .apple, size: 11, weight: .medium, color: Theme.text2)
            Text("Bundle id · App id")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            HStack(spacing: 8) {
                identityField(Binding(get: { state.appleBundleID },
                                      set: { state.appleBundleID = $0 }),
                              placeholder: "Bundle id",
                              locked: fixed) { state.updateAppleAppFields() }
                // The picker stays. It is the right way in when it is
                // available, because it fills both fields from apps that
                // really exist. It is no longer the only way in.
                //
                // One visible app never reaches here: the connect fills the
                // field with it, because a menu of one asks the developer to
                // confirm what the app has already read.
                //
                // It goes with the boxes on a shipped app. Picking another app
                // writes both of these, which is the change the store refuses.
                if state.remoteAppleApps.count > 1, !fixed {
                    Menu {
                        ForEach(state.remoteAppleApps) { app in
                            Button("\(app.name) · \(app.identifier)") {
                                state.chooseRemoteAppleApp(app)
                            }
                        }
                    } label: {
                        PickerLabel(value: "Choose")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                identityField(Binding(get: { state.appleAppID },
                                      set: { state.appleAppID = $0 }),
                              placeholder: "App id",
                              width: 120,
                              locked: fixed) { state.updateAppleAppFields() }
                Spacer(minLength: 0)
            }
            if fixed {
                fixedIdentityNote("The App Store assigned these when the app shipped. Neither one changes now.")
            } else if state.appleBundleID.isEmpty, state.remoteAppleApps.isEmpty {
                missingIdentityNote("Connect App Store Connect to choose the app, or type it.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var googleIdentity: some View {
        let fixed = state.storeFixedTheIdentifiers(.google)
        return VStack(alignment: .leading, spacing: 4) {
            StoreLabel(store: .google, size: 11, weight: .medium, color: Theme.text2)
            Text("Package name")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            // Typed here, not only on Stores, and now picked as well. The
            // Android Publisher API is package-scoped and lists nothing, which
            // is why this row had no picker while App Store Connect got one,
            // and why the package name was the one required identifier a
            // developer had to remember. The Play Developer Reporting API
            // answers it for the same credential.
            HStack(spacing: 8) {
                // The same box the App Store column draws, and no placeholder.
                // The label above it already says "Package name", and the
                // field repeated the word directly under it: one column of two
                // said its one field's name twice, and the other did not.
                identityField(Binding(get: { state.googlePackageName },
                                      set: { state.googlePackageName = $0 }),
                              placeholder: "",
                              locked: fixed) { state.updateGoogleAppFields() }
                if state.remoteGoogleApps.count > 1, !fixed {
                    Menu {
                        ForEach(state.remoteGoogleApps) { app in
                            Button("\(app.name) · \(app.identifier)") {
                                state.chooseRemoteGoogleApp(app)
                            }
                        }
                    } label: {
                        PickerLabel(value: "Choose")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
            if fixed {
                fixedIdentityNote("Google Play holds this package name. It cannot change once a build has landed.")
            } else if state.googlePackageName.isEmpty, state.remoteGoogleApps.isEmpty {
                missingIdentityNote("Connect Google Play to choose the app, or type it.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One identifier, typed.
    ///
    /// It was a value and not a box, on the grounds that the store decides
    /// these and an editable field is an invitation to invent an App id. That
    /// reasoning holds for what the field means and not for what it costs: a
    /// required value with no way in is a dead end, and every way in this app
    /// offered went through somewhere else. An import fills these, the picker
    /// beside them fills these, and neither is available to a developer whose
    /// credential cannot list the app or who has not connected one yet. The
    /// answer to that was the YAML editor.
    ///
    /// So it is typed, and the paragraph above it still says where the value
    /// comes from. The invitation is answered by saying what is true, not by
    /// taking the keyboard away.
    /// - Parameter locked: the store has fixed this identifier. The box keeps
    ///   its shape and stops taking characters, because the value is still the
    ///   answer to "which app is this?" and hiding it would lose that.
    private func identityField(_ text: Binding<String>, placeholder: String,
                               width: CGFloat? = nil,
                               locked: Bool = false,
                               commit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Theme.mono(11.5))
            .lineLimit(1)
            .disabled(locked)
            .foregroundStyle(locked ? Theme.text2 : Theme.text)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            .onChange(of: text.wrappedValue) { commit() }
    }

    private func missingIdentityNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            QuietButton(title: "Open Stores") { state.selectedTab = .stores }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// Why a box that holds a value takes no characters. Without it the row is
    /// a field that ignores the keyboard and says nothing about why.
    private func fixedIdentityNote(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill").font(Theme.font(size: 9))
            Text(text).font(Theme.font(size: 11))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.text3)
        .padding(.top, 2)
    }

    /// The number this submission carries, per store.
    ///
    /// One field for both was the whole of this row, and the two stores do not
    /// number together: an app that shipped on the App Store first is on 1.4.1
    /// there and on 1.0.0 in Play, and the one field refused the Android
    /// upload against a number that belongs to Apple. A release that really is
    /// one release across both stores is a tick away, and it is the shape
    /// every manifest written before this already had.
    @ViewBuilder
    private var versionRow: some View {
        @Bindable var state = state
        if state.showsVersionPerStore, !state.sharesOneVersion {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Store.allCases.filter(state.stores.contains)) { store in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        StoreLabel(store: store, size: 11.5, weight: .medium)
                            .frame(width: 108, alignment: .leading)
                        versionField(state.releaseVersionBinding(for: store))
                        if store == .apple, let live = state.liveAppleVersion {
                            liveVersionNote(live)
                        }
                        Spacer(minLength: 8)
                        if store == .apple, let next = state.nextAppleVersion,
                           next != state.manifest.versionName(for: .apple) {
                            QuietButton(title: "Use \(next)") {
                                state.releaseVersionBinding(for: .apple).wrappedValue = next
                            }
                        }
                    }
                }
                sameVersionToggle
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Release version").font(Theme.font(size: 11.5, weight: .medium))
                    versionField(state.releaseVersionBinding)
                    if let live = state.liveAppleVersion, state.stores.contains(.apple) {
                        liveVersionNote(live)
                    }
                    Spacer(minLength: 8)
                    if let next = state.nextAppleVersion,
                       next != state.manifest.release?.versionName {
                        QuietButton(title: "Use \(next)") { state.useReleaseVersion(next) }
                    }
                }
                if state.showsVersionPerStore { sameVersionToggle }
            }
        }
    }

    private var sameVersionToggle: some View {
        @Bindable var state = state
        return Toggle("Use the same version on both stores",
                      isOn: $state.sharesOneVersion)
            .toggleStyle(.checkbox)
            .font(Theme.font(size: 11.5))
            .foregroundStyle(Theme.text2)
    }

    private func versionField(_ text: Binding<String>) -> some View {
        TextField("1.0", text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 96)
            .monospacedDigit()
    }

    private func liveVersionNote(_ live: String) -> some View {
        Text(verbatim: "\(live) is live on the App Store")
            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            .monospacedDigit()
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
            // TestFlight stood in the column beside this one and is a tab of
            // its own now. Nothing takes its place: the Android options fill
            // the width they were sharing.
            if state.stores.contains(.google) { googleOptions }
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
            Text("Play has no TestFlight equivalent. The rollout belongs to the track below, and the testers of a closed track to the Beta testing tab.")
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
                 note: "Diagnostics, Xcode Cloud, and signing identities") {
            // One column. Internal app sharing was the Google half of a
            // `ViewThatFits` pair here and now belongs to Beta testing, which
            // is what it does: it hands a build to a tester off the store.
            // What is left is Apple's and stacks the full width.
            VStack(alignment: .leading, spacing: 14) {
                StoreDiagnosticsPanel()
                if state.stores.contains(.apple) {
                    XcodeCloudPanel()
                    SigningIdentitiesPanel()
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

/// One app's `AppVersionState`, in the words a developer uses.
///
/// Apple names fifteen states and they answer a question nobody asked in a
/// list of apps. What a developer wants is whether an app is out, on its way,
/// stuck, or has never shipped, so the fifteen collapse into five.
///
/// One colour for one holder. Green means the customers have it. Yellow means
/// Apple has it. Orange means the developer has it, and it is the state most of
/// this app's screens are written for. Red means it came back. Grey means there
/// is nothing on the store to hold.
///
/// Blue is the one that is neither: approved, and one press of Release away
/// from green. Blue is what this app paints the thing you act on, and that is
/// exactly what the state is. It is not orange, because nothing is left to
/// write, and not green, because nobody can buy it yet.
///
/// "Refused" and not "Rejected", because that is the word the review banner,
/// the validator and the Summary row all use for the same answer.
///
/// `DEVELOPER_REJECTED` is a draft and not a refusal. The developer withdrew
/// it, Apple never answered, and a red chip would send somebody looking for a
/// reason nobody ever wrote. See `AppleVersionState.outcome`, which drops it
/// for the same reason.
struct AppleStanding {
    let label: String
    let tint: Color
    let fill: Color
    /// A reviewer has it open right now, rather than Apple holding it in a
    /// queue. The chip animates on this and on nothing else: a pulse that
    /// meant "somewhere between submitted and answered" would pulse for the
    /// days a version spends waiting, which is motion that says nothing.
    let active: Bool

    /// One bare `AppVersionState`. The sidebar caches one per linked app, and
    /// the chip beside the app name is what it asks this question for.
    ///
    /// Nil is nobody having asked, and the empty string is a store that
    /// answered and holds no version. They are two different things to a
    /// developer and they were one word.
    init(state: String?) {
        (label, tint, fill) = Self.words(for: state)
        active = state == "IN_REVIEW"
    }

    /// The one fact both stores answer, for an app with no App Store version
    /// state to collapse: Google Play publishes no review state at all, and
    /// every app wears this between being linked and its first read answering.
    ///
    /// Nil is nobody having asked. See `AppState.appLiveStates`.
    init(shipped: Bool?) {
        self.init(state: shipped.map { $0 ? "READY_FOR_SALE" : "" })
    }

    private static func words(for state: String?) -> (String, Color, Color) {
        switch state {
        case nil:
            // Grey, and the same grey as an app with nothing on the store. It
            // is the tier this app paints "there is nothing here to act on",
            // and an unread app is exactly that until a read says otherwise.
            ("Unknown", Theme.text3, Theme.sunken)
        case "":
            ("Not on the store", Theme.text3, Theme.sunken)
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION":
            ("Live", Theme.green, Theme.greenBg)
        case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE":
            ("Off sale", Theme.text3, Theme.sunken)
        case "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "ACCEPTED",
             "PROCESSING_FOR_DISTRIBUTION":
            // Apple said yes and nobody can buy it yet. It is not "Live": the
            // release is still a button somebody has to press, and that button
            // is the Release tab. Processing for distribution is past the
            // answer too: Apple is preparing to ship it, not reading it.
            ("Approved", Theme.accent, Theme.accentBg)
        // Two states and not one. Waiting in Apple's queue and being read by a
        // reviewer are days apart and were the same word, so the chip could
        // not tell a developer whether anything had started. `applePhase`
        // already draws this line for the status card; this is the same line,
        // in the same vocabulary.
        case "WAITING_FOR_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE":
            ("In queue", Theme.yellow, Theme.yellowBg)
        case "IN_REVIEW":
            ("In review", Theme.yellow, Theme.yellowBg)
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY":
            ("Refused", Theme.red, Theme.redBg)
        default:
            // PREPARE_FOR_SUBMISSION, DEVELOPER_REJECTED, and anything Apple
            // adds after this ships. A state this app has never heard of is
            // still a draft: a version that exists and is not on sale.
            ("Draft", Theme.orange, Theme.orangeBg)
        }
    }
}

/// The export compliance declaration, beside the answer that asks for it.
///
/// Apple attaches it to the build that ships, and it goes to the regulator's
/// review, so the app writes what the developer answers and invents nothing.
private struct ExportCompliance: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.hasEncryptionDeclaration {
                HStack {
                    Text("The declaration").font(Theme.font(size: 11.5, weight: .semibold))
                    Spacer(minLength: 8)
                    Button(role: .destructive) { state.removeEncryptionDeclaration() } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
                ForEach(AppState.EncryptionFlag.allCases, id: \.self) { flag in
                    Toggle(flag.label, isOn: state.encryptionFlagBinding(flag))
                        .font(Theme.font(size: 11.5))
                }
                LabeledField("Regulator code", note: "when Apple has issued one") {
                    TextField("", text: state.encryptionTextBinding(.codeValue))
                }
                LabeledField("CCATS or ERN document") {
                    PathField(path: state.encryptionTextBinding(.documentPath),
                              problem: state.missingFileNote(
                                for: state.encryptionTextBinding(.documentPath).wrappedValue)) {
                        guard let url = state.chooseOneFile(
                            allowedExtensions: ["pdf", "doc", "docx", "txt"]) else { return }
                        state.encryptionTextBinding(.documentPath).wrappedValue =
                            state.relativePath(for: url)
                    }
                }
                Text("The run creates the declaration in the review state and uploads the document with it.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("An app that uses non-exempt encryption and claims no exemption also owes Apple this declaration.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add the export declaration") { state.addEncryptionDeclaration() }
                    .controlSize(.small)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
    }
}

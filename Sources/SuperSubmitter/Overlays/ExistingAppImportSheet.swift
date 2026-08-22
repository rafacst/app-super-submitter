import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

struct ExistingAppImportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var model = ExistingAppImportModel()
    @State private var appleImporterOpen = false
    @State private var googleImporterOpen = false
    /// The import that is waiting on the "this will replace local data"
    /// question. It is the work itself, so the answer runs exactly what the
    /// button would have run.
    @State private var pendingImport: (([ExistingAppCandidate]) async throws -> [URL])?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    switch model.step {
                    case .credentials: credentialsStep
                    case .apps: appsStep
                    case .folders: foldersStep
                    case .destination: importingStep
                    case .complete: completeStep
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(width: 900, height: 720)
        .background(Theme.content)
        .confirmationDialog("Replace the local data?",
                            isPresented: Binding(
                                get: { pendingImport != nil },
                                set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("Replace with store data", role: .destructive) {
                guard let pendingImport else { return }
                self.pendingImport = nil
                performImport(pendingImport)
            }
            Button("Keep the local data", role: .cancel) { pendingImport = nil }
        } message: {
            Text("This import will replace the proposed data in an existing store.yaml. Save a draft first if you want another local copy.")
        }
        // The keys the app already holds. Without this the sheet asked for
        // them on every import, one line under the sentence that promises it
        // asks once.
        .onAppear {
            model.purpose = state.importPurpose
            model.seedCredentials(from: state)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconChip(symbol: model.purpose == .newApp
                     ? "paperplane.fill" : "arrow.triangle.2.circlepath",
                     tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.purpose == .newApp ? "Submit a new app" : "Update existing apps")
                    .font(Theme.font(size: 17, weight: .semibold))
                Text(stepLabel).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    let reached = steps.firstIndex(of: model.step) ?? 0
                    Capsule().fill(index <= reached ? tint : Theme.sep)
                        .frame(width: step == model.step ? 28 : 15, height: 4)
                }
            }
            .motion(.smooth(duration: 0.2), value: model.step)
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Connect the stores first").font(Theme.font(size: 22, weight: .semibold))
                Text(model.purpose == .newApp
                     ? "Pick the stores this app goes to, and connect them. You enter these once. The key covers every app in your developer account, and it goes to the macOS Keychain."
                     : "You enter these once. The key covers every app in your developer account, and it goes to the macOS Keychain when the import starts.")
                    .font(Theme.font(size: 13)).foregroundStyle(Theme.text2)
            }
            // The Stores tab layout, because this asks the Stores tab question:
            // each credential card in the column under the store it belongs to.
            StoreSelectionGrid(selected: model.stores, toggle: model.toggleStore) { store in
                switch store {
                case .apple:
                    if model.stores.contains(.apple) { appleCard }
                case .google:
                    if model.stores.contains(.google) { googleCard }
                }
            }
            limitationNote
            errorView
        }
    }

    /// No status word and no connect button, unlike the Stores tab. Nothing has
    /// called App Store Connect yet at this point, and the footer of this sheet
    /// is what will: a second Connect inside the card would be the same job,
    /// half done.
    private var appleCard: some View {
        @Bindable var model = model
        return CredentialCard(
            store: .apple,
            open: model.credentialDetailsOpen(.apple),
            toggle: { model.toggleCredentialDetails(.apple) },
            guide: .apple,
            guideOpen: model.guideOpen.contains(.apple),
            toggleGuide: { model.toggleGuide(.apple) }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FileWell(
                    name: model.appleFileName,
                    emptyName: "App Store Connect private key",
                    prompt: "Drop the .p8 file, or",
                    choose: { appleImporterOpen = true },
                    accept: { take($0, extension: "p8", with: model.importAppleKey) })
                EditableField(label: "Key ID", value: $model.appleKeyID, prompt: "Key ID",
                              limit: AppleCredential.keyIDLength)
                EditableField(label: "Issuer id", value: $model.appleIssuerID,
                              prompt: "Issuer UUID", limit: AppleCredential.issuerIDLength)
            }
        }
        // Each importer hangs off its own card. Stacking them on one view lets
        // only the last one present.
        .fileImporter(isPresented: $appleImporterOpen,
                      allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data]) {
            handleFile($0, importWith: model.importAppleKey)
        }
        .transition(.credentialPanel)
    }

    private var googleCard: some View {
        CredentialCard(
            store: .google,
            open: model.credentialDetailsOpen(.google),
            toggle: { model.toggleCredentialDetails(.google) },
            guide: .google,
            guideOpen: model.guideOpen.contains(.google),
            toggleGuide: { model.toggleGuide(.google) }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FileWell(
                    name: model.googleFileName,
                    emptyName: "Google service-account key",
                    prompt: "Drop the service account JSON, or",
                    choose: { googleImporterOpen = true },
                    accept: { take($0, extension: "json", with: model.importGoogleKey) })
                if let email = model.googleCredential?.clientEmail {
                    Text(email).font(Theme.mono(11)).foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                }
            }
        }
        .fileImporter(isPresented: $googleImporterOpen, allowedContentTypes: [.json]) {
            handleFile($0, importWith: model.importGoogleKey)
        }
        .transition(.credentialPanel)
    }

    private var appsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose the apps to update").font(Theme.font(size: 22, weight: .semibold))
                    Text("Select as many apps as you want. Matching Apple and Google identifiers become one workspace.")
                        .font(Theme.font(size: 13)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Button("Select all") { model.selection.selectAll(model.candidates) }
                    .buttonStyle(.borderless)
            }

            if model.stores.contains(.google) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Google Play package names").font(Theme.font(size: 13, weight: .semibold))
                    Text("Apps are listed through the Play Developer Reporting API. You can also paste package names when that API is not enabled; each is permission-checked before import.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    HStack(alignment: .top) {
                        TextField("company.product, company.otherproduct", text: $model.googlePackages,
                                  axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            // A newline separates two packages here, the same
                            // as a comma. `addGooglePackages` splits on both.
                            .returnInsertsLineBreak()
                            .lineLimit(2...4)
                        QuietButton(title: "Add packages", action: model.addGooglePackages)
                    }
                }
                .padding(14).background(Theme.sunken, in: RoundedRectangle(cornerRadius: 10))
            }

            if let note = model.iconNote {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(Theme.text3)
                    Text(note)
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
            }

            if model.candidates.isEmpty {
                ContentUnavailableView("No apps found", systemImage: "rectangle.stack.badge.questionmark",
                    description: Text("Check the credential permissions or add a Google package name."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                // The App Store block, then the Google Play block.
                ForEach([Store.apple, .google], id: \.self) { store in
                    let apps = model.candidates(for: store)
                    if !apps.isEmpty { storeGrid(store, apps) }
                }
            }
            errorView
        }
    }

    /// One row per app, and a folder button on each.
    ///
    /// The old sheet asked for one folder when one app was chosen and asked
    /// for nothing at all when several were: every `store.yaml` went into
    /// Super Submitter's own workspace, and the folder question came back
    /// weeks later, per app, on a Build tab the developer had to find. The
    /// question belongs here, where they are already choosing the apps, and
    /// the answer is still allowed to be "later".
    private var foldersStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.purpose == .newApp ? "Where does this app live?"
                                              : "Where does each app live?")
                    .font(Theme.font(size: 22, weight: .semibold))
                Text(model.purpose == .newApp
                     ? "Choose the folder of the project. Super Submitter writes store.yaml inside it and reads what the project already says: the identifier, the version and the name."
                     : "Super Submitter keeps store.yaml beside your source. Link the folder of each app now, or leave it and link it from the Build tab later.")
                    .font(Theme.font(size: 13)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.purpose == .newApp {
                folderRow(key: ExistingAppImportModel.newAppKey,
                          name: model.newAppFolder?.lastPathComponent ?? "Your app",
                          detail: "The folder that holds the Xcode or Gradle project")
            } else {
                VStack(spacing: 9) {
                    ForEach(model.selectedGroups) { group in
                        folderRow(key: group.id, name: group.folderName,
                                  detail: group.identifier)
                    }
                }
            }
            if model.purpose == .update, model.appsWithoutFolder > 0 {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "clock.badge.questionmark").foregroundStyle(Theme.yellow)
                    Text("\(model.appsWithoutFolder) of these keep their store.yaml in Super Submitter's own folder for now. Each one says so in the window until you link its folder, and linking it moves the file across.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 9))
            }
            errorView
        }
    }

    private func folderRow(key: String, name: String, detail: String) -> some View {
        let folder = model.folders[key]
        return HStack(spacing: 12) {
            IconChip(symbol: folder == nil ? "folder" : "folder.fill",
                     tint: folder == nil ? Theme.text3 : Theme.teal, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.font(size: 13, weight: .medium)).lineLimit(1)
                Text(folder?.path ?? detail)
                    .font(Theme.mono(10))
                    .foregroundStyle(folder == nil ? Theme.text3 : Theme.text2)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if folder != nil {
                Button("Change…") { chooseFolder(for: key, named: name) }
                    .buttonStyle(.borderless)
            } else {
                QuietButton(title: "Link folder…") { chooseFolder(for: key, named: name) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(folder == nil ? Theme.sep : Theme.teal.opacity(0.5),
                          lineWidth: Theme.hairline))
    }

    private var importingStep: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(model.purpose == .newApp ? "Reading the project…" : "Importing current store data…")
                .font(Theme.font(size: 18, weight: .semibold))
            Text(model.purpose == .newApp
                 ? "Super Submitter is looking for the Xcode or Gradle project in this folder and taking the identifier, the version and the name it states."
                 : "Super Submitter is creating local workspaces, downloading available listing metadata, and saving the credentials in the Keychain.")
                .font(Theme.font(size: 13)).foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            errorView
        }
        .frame(maxWidth: .infinity, minHeight: 480)
    }

    private var completeStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            Label(completeTitle, systemImage: "checkmark.circle.fill")
                .font(Theme.font(size: 22, weight: .semibold)).foregroundStyle(Theme.green)
            Text(completeDetail)
                .font(Theme.font(size: 13)).foregroundStyle(Theme.text2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 16)], spacing: 24) {
                ForEach(Array(model.selectedCandidates.enumerated()), id: \.element.id) { index, candidate in
                    ImportedMark(candidate: candidate, icon: model.icons[candidate.id],
                                 delay: Double(index) * 0.09)
                }
            }
            .padding(.top, 6)
        }
    }

    /// One app is named. Several are not, because a list of names in a heading
    /// reads worse than the file paths already below it.
    private var completeTitle: String {
        guard let name = model.selectedGroupName else {
            return "Your apps are loaded, let's get to work"
        }
        return "Your app \(name) was loaded, let's get to work"
    }

    private var completeDetail: String {
        let placed = model.selectedGroups.count - model.appsWithoutFolder
        let where_ = state.mode == .managing
            ? "Super Submitter keeps the workspace, so nothing landed in your folders."
            : (model.appsWithoutFolder == 0
               ? "Each app has its own store.yaml in the folder you linked."
               : "\(placed) of them have their store.yaml in the folder you linked. The rest keep it in Super Submitter's own folder until you link one, and each says so in the window.")
        return "\(where_) They share the credentials you entered, so no tab asks for them again. "
            + "Each app opens on the screen it was last left on."
    }

    private var footer: some View {
        HStack {
            if let back = backStep {
                Button("Back") { model.step = back }.buttonStyle(.borderless)
            }
            Spacer()
            Button(model.step == .complete ? "Done" : "Cancel") { dismiss() }
            switch model.step {
            case .credentials:
                Button(model.loading ? "Connecting…"
                       : (model.purpose == .newApp ? "Continue" : "Connect and list apps")) {
                    if model.purpose == .newApp {
                        state.adoptCredentials(apple: model.appleCredential,
                                               google: model.googleCredential)
                        model.step = .folders
                    } else {
                        Task { await model.discover() }
                    }
                }
                .buttonStyle(.borderedProminent).tint(tint)
                .disabled(!model.canDiscover || model.loading)
            case .apps:
                // Managing needs no folder. There is no repository to sit
                // beside, so Super Submitter keeps the workspace itself.
                Button(state.mode == .managing
                       ? "Bring in \(model.selection.count) apps" : "Choose folders") {
                    if state.mode == .managing { importManaged() } else { model.step = .folders }
                }
                .buttonStyle(.borderedProminent).tint(tint)
                .disabled(model.selection.count == 0)
            case .folders:
                Button(model.purpose == .newApp ? "Create the app" : importTitle) {
                    if model.purpose == .newApp { createNewApp() } else { importGrouped() }
                }
                .buttonStyle(.borderedProminent).tint(tint)
                // A new app has nowhere to write without one. An import of
                // apps the stores already hold does: the folder can come later.
                .disabled(model.purpose == .newApp && model.newAppFolder == nil)
            case .destination, .complete:
                EmptyView()
            }
        }
        .padding(.horizontal, 24).frame(height: 62)
        .background(Theme.raised).overlay(alignment: .top) { Hairline() }
    }

    /// The colour of the door. The update sheet has always been teal; a new
    /// app is the accent, the same as the card that opens it.
    private var tint: Color { model.purpose == .newApp ? Theme.accent : Theme.teal }

    /// The screens this door actually shows, for the rail and the count.
    private var steps: [ExistingAppImportModel.Step] {
        switch model.purpose {
        case .newApp: [.credentials, .folders, .destination]
        case .update:
            state.mode == .managing
                ? [.credentials, .apps, .destination, .complete]
                : [.credentials, .apps, .folders, .destination, .complete]
        }
    }

    private var backStep: ExistingAppImportModel.Step? {
        switch model.step {
        case .apps: .credentials
        case .folders: model.purpose == .newApp ? .credentials : .apps
        default: nil
        }
    }

    private var importTitle: String {
        let count = model.selectedGroups.count
        return "Bring in \(count) \(count == 1 ? "app" : "apps")"
    }

    private var limitationNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.teal)
            Text("Apple lists apps through App Store Connect. Google lists them through the Play Developer Reporting API; package-name entry remains available as a fallback.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
        }
        .padding(12).background(Theme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var errorView: some View {
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.font(size: 12)).foregroundStyle(Theme.red)
        }
    }

    private var stepLabel: String {
        let total = steps.count
        let index = (steps.firstIndex(of: model.step) ?? 0) + 1
        let name = switch model.step {
        case .credentials: "Credentials"
        case .apps: "App selection"
        case .folders: "Folders"
        case .destination: "Import"
        case .complete: "Complete"
        }
        return "\(index) of \(total) · \(name)"
    }

    private func handleFile(_ result: Result<URL, Error>,
                            importWith: (URL) throws -> Void) {
        do { try importWith(result.get()); model.error = nil }
        catch { model.error = error.localizedDescription }
    }

    /// A dropped file. It answers the well, which paints the drop as refused
    /// when the answer is false, so a `.json` on the Apple card says so where
    /// the developer is looking instead of in the error line at the bottom.
    private func take(_ urls: [URL], extension type: String,
                      with importer: (URL) throws -> Void) -> Bool {
        guard let url = urls.first,
              url.pathExtension.lowercased() == type else { return false }
        do { try importer(url); model.error = nil; return true }
        catch { model.error = error.localizedDescription; return false }
    }

    /// One folder, for one app, from the row that asked for it.
    ///
    /// It used to ask once for everything: one folder for one app, or one
    /// parent folder that several apps would each take a subfolder of. The
    /// parent never ran — the multi-app path skipped the question entirely —
    /// and a parent is the wrong question anyway, because a developer's five
    /// repositories are rarely five folders side by side.
    private func chooseFolder(for key: String, named name: String) {
        let panel = NSOpenPanel()
        panel.title = "Select the folder of \(name)"
        panel.explain("Choose the folder of \(name). store.yaml goes inside it.")
        panel.prompt = "Select"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.folders[key] = url
    }

    private func storeGrid(_ store: Store, _ apps: [ExistingAppCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                StoreLabel(store: store, size: 12.5)
                Text("\(apps.count)")
                    .font(Theme.font(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.sunken, in: Capsule())
                Spacer()
            }
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(apps) { candidate in
                    CandidateTile(candidate: candidate, icon: model.icons[candidate.id],
                                  selected: model.selection.contains(candidate)) {
                        model.selection.toggle(candidate)
                    }
                }
            }
        }
    }

    /// Five across, and as many rows as the account has apps.
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    /// The managing path. Super Submitter owns the folder, so it asks for
    /// nothing and the import starts on the button.
    private func importManaged() {
        requestImport { candidates in
            try await state.importManagedApps(
                candidates, appleCredential: model.appleCredential,
                googleCredential: model.googleCredential)
        }
    }

    /// The publishing path: every app into the folder its row named, and the
    /// rows that named none into Super Submitter's own workspace, marked so
    /// the window keeps asking and a later link moves the file across.
    ///
    /// One import per app, because the destinations differ per app. That is
    /// what `importManagedApps` already does with the folders it owns, and it
    /// is why `importExistingApps` never has to split a parent folder.
    private func importGrouped() {
        let groups = model.selectedGroups
        requestImport { _ in
            for group in groups {
                if let folder = model.folders[group.id] {
                    let accessed = folder.startAccessingSecurityScopedResource()
                    defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                    _ = try await state.importExistingApps(
                        group.candidates, destination: folder,
                        appleCredential: model.appleCredential,
                        googleCredential: model.googleCredential)
                } else {
                    _ = try await state.importManagedApps(
                        group.candidates, appleCredential: model.appleCredential,
                        googleCredential: model.googleCredential,
                        awaitingProjectFolder: true)
                }
            }
            return []
        }
    }

    /// The new-app door. Nothing is imported: the folder is read, `store.yaml`
    /// is written into it, and whatever the project already states fills the
    /// manifest. See `AppState.createApp`.
    private func createNewApp() {
        guard let folder = model.newAppFolder else { return }
        model.step = .destination
        model.error = nil
        Task {
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            await state.createApp(in: folder, stores: model.stores)
            dismiss()
        }
    }

    /// Asks before an import writes over local work, then runs it.
    private func requestImport(
        _ work: @escaping ([ExistingAppCandidate]) async throws -> [URL]) {
        guard !state.importWouldReplaceLocalData(model.selectedCandidates,
                                                 folders: model.folders) else {
            pendingImport = work
            return
        }
        performImport(work)
    }

    private func performImport(
        _ work: @escaping ([ExistingAppCandidate]) async throws -> [URL]) {
        model.step = .destination
        model.error = nil
        Task {
            do {
                _ = try await work(model.selectedCandidates)
                model.step = .complete
            } catch {
                model.error = error.localizedDescription
                model.step = .apps
            }
        }
    }
}

/// One app that just landed. The glow behind the icon is the icon itself,
/// blurred, so every app arrives in its own colour and none of them fight the
/// artwork. They fade in one after another, in the order they were picked.
private struct ImportedMark: View {
    let candidate: ExistingAppCandidate
    let icon: URL?
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 9) {
            AsyncImage(url: icon) { image in
                image.resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .background {
                        image.resizable().aspectRatio(contentMode: .fit)
                            .blur(radius: 20).saturation(1.6).opacity(0.75)
                    }
            } placeholder: {
                // No icon: the store mark over a glow of the store colour.
                RoundedRectangle(cornerRadius: 16)
                    .fill(candidate.store.tint.opacity(0.14))
                    .overlay(StoreMark(store: candidate.store, size: 30))
                    .shadow(color: candidate.store.tint.opacity(0.55), radius: 18)
            }
            .frame(width: 72, height: 72)

            Text(candidate.name)
                .font(Theme.font(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.text2)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 104)
        }
        .opacity(shown ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.8))
        .onAppear {
            withAnimation(.spring(duration: 0.65).delay(reduceMotion ? 0 : delay)) { shown = true }
        }
    }
}

private struct CandidateTile: View {
    let candidate: ExistingAppCandidate
    let icon: URL?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                mark
                VStack(spacing: 2) {
                    Text(candidate.name)
                        .font(Theme.font(size: 11.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(height: 28, alignment: .top)
                    Text(candidate.identifier)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // What the record ships on. A Mac icon carries its own
                    // rounded corners and a transparent margin, so a Mac app
                    // already looks unlike its neighbours here. This says why.
                    if let label = candidate.platformLabel {
                        Text(label)
                            .font(Theme.font(size: 9, weight: .medium))
                            .foregroundStyle(Theme.text2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.sunken, in: Capsule())
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.teal.opacity(0.10) : Theme.raised,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(selected ? Theme.teal : Theme.sep,
                              lineWidth: selected ? 1.4 : Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.name)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var mark: some View {
        AsyncImage(url: icon) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            RoundedRectangle(cornerRadius: 13)
                .fill(candidate.store.tint.opacity(0.12))
                .overlay(StoreMark(store: candidate.store, size: 26))
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .overlay(alignment: .topTrailing) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(Theme.font(size: 15))
                .foregroundStyle(selected ? Theme.teal : Theme.text3)
                .background(Circle().fill(Theme.content).padding(1.5))
                .offset(x: 6, y: -6)
        }
    }
}

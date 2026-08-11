import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

struct ExistingAppImportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var model = ExistingAppImportModel()
    @State private var appleImporterOpen = false
    @State private var googleImporterOpen = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    switch model.step {
                    case .credentials: credentialsStep
                    case .apps: appsStep
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
        // The keys the app already holds. Without this the sheet asked for
        // them on every import, one line under the sentence that promises it
        // asks once.
        .onAppear { model.seedCredentials(from: state) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconChip(symbol: "arrow.triangle.2.circlepath", tint: Theme.teal, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update existing apps").font(Theme.font(size: 17, weight: .semibold))
                Text(stepLabel).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(index <= model.step.rawValue ? Theme.teal : Theme.sep)
                        .frame(width: index == model.step.rawValue ? 28 : 15, height: 4)
                }
            }
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
                Text("You enter these once. The key covers every app in your developer account, and it goes to the macOS Keychain when the import starts.")
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

    private var importingStep: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Importing current store data…").font(Theme.font(size: 18, weight: .semibold))
            Text("Super Submitter is creating local workspaces, downloading available listing metadata, and saving the credentials in the Keychain.")
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
        let landing = state.mode == .managing ? "Reviews" : "Build"
        let where_ = state.mode == .managing
            ? "Super Submitter keeps the workspace, so nothing landed in your folders."
            : "Each app has its own store.yaml beside it."
        return "\(where_) They share the credentials you entered, so no tab asks for them again. "
            + "The last imported app is open on the \(landing) tab."
    }

    private var footer: some View {
        HStack {
            if model.step == .apps {
                Button("Back") { model.step = .credentials }.buttonStyle(.borderless)
            }
            Spacer()
            Button(model.step == .complete ? "Done" : "Cancel") { dismiss() }
            if model.step == .credentials {
                Button(model.loading ? "Connecting…" : "Connect and list apps") {
                    Task { await model.discover() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.teal)
                .disabled(!model.canDiscover || model.loading)
            } else if model.step == .apps {
                // Managing needs no folder. There is no repository to sit
                // beside, so Super Submitter keeps the workspace itself.
                Button(state.mode == .managing
                       ? "Bring in \(model.selection.count) apps"
                       : (model.selectedGroupName == nil
                          ? "Choose the folder for these apps…" : "Choose the app folder…")) {
                    if state.mode == .managing { importManaged() } else { chooseFolder() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.teal)
                .disabled(model.selection.count == 0)
            }
        }
        .padding(.horizontal, 24).frame(height: 62)
        .background(Theme.raised).overlay(alignment: .top) { Hairline() }
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
        switch model.step {
        case .credentials: "1 of 4 · Credentials"
        case .apps: "2 of 4 · App selection"
        case .destination: "3 of 4 · Import"
        case .complete: "4 of 4 · Complete"
        }
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

    /// Super Submitter keeps `store.yaml` beside the app, so the panel asks for
    /// the folder of the app itself. Several apps at once need one folder that
    /// holds them all, and each app then takes its own folder inside it.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        if let name = model.selectedGroupName {
            panel.title = "Select the folder of \(name)"
            panel.message = "Choose the folder of \(name). Super Submitter writes store.yaml inside it."
        } else {
            panel.title = "Select the folder for these apps"
            panel.message = "Choose the folder that holds your app folders. Each app takes its own folder inside it."
        }
        panel.prompt = "Select"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importSelected(into: url)
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
        model.step = .destination
        model.error = nil
        Task {
            do {
                _ = try await state.importManagedApps(
                    model.selectedCandidates,
                    appleCredential: model.appleCredential,
                    googleCredential: model.googleCredential)
                model.step = .complete
            } catch {
                model.error = error.localizedDescription
                model.step = .apps
            }
        }
    }

    private func importSelected(into url: URL) {
        model.step = .destination
        model.error = nil
        let accessed = url.startAccessingSecurityScopedResource()
        Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await state.importExistingApps(
                    model.selectedCandidates, destination: url,
                    appleCredential: model.appleCredential,
                    googleCredential: model.googleCredential)
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

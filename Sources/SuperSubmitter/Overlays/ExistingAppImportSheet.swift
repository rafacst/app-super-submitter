import SubmitKit
import SwiftUI
import UniformTypeIdentifiers

struct ExistingAppImportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var model = ExistingAppImportModel()
    @State private var appleImporterOpen = false
    @State private var googleImporterOpen = false
    @State private var destinationImporterOpen = false

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
        .fileImporter(isPresented: $appleImporterOpen,
                      allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data]) {
            handleFile($0, importWith: model.importAppleKey)
        }
        .fileImporter(isPresented: $googleImporterOpen, allowedContentTypes: [.json]) {
            handleFile($0, importWith: model.importGoogleKey)
        }
        .fileImporter(isPresented: $destinationImporterOpen, allowedContentTypes: [.folder]) {
            guard case .success(let url) = $0 else {
                if case .failure(let error) = $0 { model.error = error.localizedDescription }
                return
            }
            importSelected(into: url)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconChip(symbol: "arrow.triangle.2.circlepath", tint: Theme.teal, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update existing apps").font(.system(size: 17, weight: .semibold))
                Text(stepLabel).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
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
                Text("Connect the stores first").font(.system(size: 22, weight: .semibold))
                Text("Credentials are held in memory while you choose apps. They are saved to the Keychain separately for every imported app.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            StoreSelectionGrid(selected: model.stores, toggle: model.toggleStore)

            if model.stores.contains(.apple) {
                credentialSection(store: .apple) {
                    HStack(alignment: .bottom, spacing: 12) {
                        labeledField("Key ID", text: $model.appleKeyID, prompt: "ABC123DEFG")
                        labeledField("Issuer ID", text: $model.appleIssuerID,
                                     prompt: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
                        chooseFile(title: model.appleFileName.isEmpty
                                   ? "Choose .p8 key" : model.appleFileName) {
                            appleImporterOpen = true
                        }
                    }
                }
            }
            if model.stores.contains(.google) {
                credentialSection(store: .google) {
                    HStack {
                        chooseFile(title: model.googleFileName.isEmpty
                                   ? "Choose service-account JSON" : model.googleFileName) {
                            googleImporterOpen = true
                        }
                        if let email = model.googleCredential?.clientEmail {
                            Text(email).font(Theme.mono(11)).foregroundStyle(Theme.text2)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            limitationNote
            errorView
        }
    }

    private var appsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose the apps to update").font(.system(size: 22, weight: .semibold))
                    Text("Select as many apps as you want. Matching Apple and Google identifiers become one workspace.")
                        .font(.system(size: 13)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Button("Select all") { model.selection.selectAll(model.candidates) }
                    .buttonStyle(.borderless)
            }

            if model.stores.contains(.google) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Google Play package names").font(.system(size: 13, weight: .semibold))
                    Text("Google provides no API to enumerate a service account's apps. Paste one or more known package names; each is permission-checked before import.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    HStack(alignment: .top) {
                        TextField("com.example.app, com.example.other", text: $model.googlePackages,
                                  axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                        QuietButton(title: "Add packages", action: model.addGooglePackages)
                    }
                }
                .padding(14).background(Theme.sunken, in: RoundedRectangle(cornerRadius: 10))
            }

            if model.candidates.isEmpty {
                ContentUnavailableView("No apps found", systemImage: "rectangle.stack.badge.questionmark",
                    description: Text("Check the credential permissions or add a Google package name."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(model.candidates) { candidate in
                        CandidateRow(candidate: candidate,
                                     selected: model.selection.contains(candidate)) {
                            model.selection.toggle(candidate)
                        }
                    }
                }
            }
            errorView
        }
    }

    private var importingStep: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Importing current store data…").font(.system(size: 18, weight: .semibold))
            Text("Super Submitter is creating local workspaces, downloading available listing metadata, and saving credentials in the Keychain.")
                .font(.system(size: 13)).foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            errorView
        }
        .frame(maxWidth: .infinity, minHeight: 480)
    }

    private var completeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Apps are ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.green)
            Text("Each app has its own store.yaml and Keychain credential. The last imported app is open on the Build tab.")
                .font(.system(size: 13)).foregroundStyle(Theme.text2)
            ForEach(model.imported, id: \.path) { url in
                HStack {
                    Image(systemName: "doc.text.fill").foregroundStyle(Theme.teal)
                    Text(url.path).font(Theme.mono(11)).textSelection(.enabled)
                }
                .padding(11).background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
            }
        }
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
                Button("Choose destination…") { destinationImporterOpen = true }
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
            Text("Apple returns every app visible to the API key. Google Play intentionally has no equivalent list-apps endpoint, so its package names are entered on the next screen.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
        }
        .padding(12).background(Theme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var errorView: some View {
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(Theme.red)
        }
    }

    private func credentialSection<Content: View>(store: Store,
                                                   @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            StoreLabel(store: store, size: 14)
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.sep,
                                                                 lineWidth: Theme.hairline))
    }

    private func labeledField(_ label: String, text: Binding<String>,
                              prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            TextField(prompt, text: text).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    private func chooseFile(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: "doc.badge.plus") }
            .buttonStyle(.bordered).controlSize(.large)
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

    private func importSelected(into url: URL) {
        model.step = .destination
        model.error = nil
        let accessed = url.startAccessingSecurityScopedResource()
        Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                model.imported = try await state.importExistingApps(
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

private struct CandidateRow: View {
    let candidate: ExistingAppCandidate
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                StoreMark(store: candidate.store, size: 28).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name).font(.system(size: 13.5, weight: .semibold))
                    Text(candidate.identifier).font(Theme.mono(11)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19)).foregroundStyle(selected ? Theme.teal : Theme.text3)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(selected ? Theme.teal.opacity(0.09) : Theme.raised,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Theme.teal : Theme.sep,
                              lineWidth: selected ? 1.2 : Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

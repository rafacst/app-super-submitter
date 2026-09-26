import SubmitKit
import SwiftUI

/// One press that gives the store added second what the first one has.
///
/// An app that shipped on the App Store and now adds Google Play, or the other
/// way round, had to fill the new store field by field: the screenshots, the
/// icon, the short description, the release notes, each retyped or dragged in
/// again. Most of a listing is one value in `store.yaml` for both stores, so
/// the copy fills what is not: see `Manifest.copyStore`. It writes to
/// `store.yaml` only, one undo step, and nothing reaches a store until the
/// developer sends it.
///
/// It sits on the Stores tab because that is where the second store is added.
struct StoreCopyPanel: View {
    @Environment(AppState.self) private var state
    /// The store the developer asked to copy from, while the question is open.
    @State private var asking: Store?
    @State private var busy = false
    @State private var report: StoreCopyReport?

    var body: some View {
        Section_("Copy between the stores", icon: "arrow.left.arrow.right",
                 tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Give one store what the other already has: the name, the texts, the screenshots, the icon and the product details. Only the values both stores accept are copied, and nothing reaches a store until you send it.")
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ActionButton(title: "App Store to Google Play", kind: .secondary,
                                 enabled: !busy) { asking = .apple }
                    ActionButton(title: "Google Play to App Store", kind: .secondary,
                                 enabled: !busy) { asking = .google }
                    if busy { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }
                if let report { result(report) }
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Copy between the stores?", isPresented: $asking.isPresent,
                            presenting: asking) { source in
            Button("Copy to \(Self.other(source).storeName)") { copy(from: source) }
            Button("Cancel", role: .cancel) {}
        } message: { source in
            Text(Self.question(from: source))
        }
        // A report is about one app. Another app opened here is a new question.
        .onChange(of: state.manifestURL) { report = nil }
    }

    private static func other(_ store: Store) -> Store {
        store == .apple ? .google : .apple
    }

    /// What the copy replaces, said before it does. Undo takes it back, and the
    /// developer should not need to.
    private static func question(from source: Store) -> String {
        switch source {
        case .apple:
            "Google Play takes the App Store's short description, release notes, screenshots and icon in store.yaml, in place of its own. A field both stores share is filled only where store.yaml is empty. Nothing is sent until you send it, and Edit > Undo takes the copy back."
        case .google:
            "The App Store takes Google Play's short description as its subtitle, its release notes as what is new, and the screenshots that fit its screen sizes, in place of its own in store.yaml. A field both stores share is filled only where store.yaml is empty. Nothing is sent until you send it, and Edit > Undo takes the copy back."
        }
    }

    private func copy(from source: Store) {
        busy = true
        Task {
            report = await state.copyStore(from: source)
            busy = false
        }
    }

    // MARK: - The result

    private func result(_ report: StoreCopyReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(report.copied.isEmpty
                 ? "Nothing changed. \(report.target.storeName) already gets the same values."
                 : "Copied to \(report.target.storeName) in store.yaml")
                .font(Theme.font(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
            lines(report.copied, symbol: "checkmark", tint: Theme.green)
            ForEach(report.skipped.indices, id: \.self) { index in
                WarningNote(report.skipped[index])
            }
            lines(report.shared, symbol: "equal", tint: Theme.text3)
            if !report.noEquivalent.isEmpty {
                Fold("Not copied: no field in the other store") {
                    lines(report.noEquivalent, symbol: "minus", tint: Theme.text3)
                        .padding(.top, 6)
                }
                .font(Theme.font(size: 11.5))
            }
            if !report.copied.isEmpty {
                Text("Send it when you are ready. Edit > Undo takes the copy back.")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.top, 2)
    }

    private func lines(_ items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: symbol)
                        .font(Theme.font(size: 9.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 12)
                    Text(items[index])
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

import SubmitKit
import SwiftUI

/// Tab 3. All controls edit the active locale in `store.yaml` immediately.
struct DetailsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Publishing sends this tab through the Summary tab, which
                // plans and then writes. Managing has none, so it writes here.
                if state.mode == .managing { DirectApplyBar(target: .listing) }
                editor("Name", field: .name,
                       limit: BindingLimits.binding(for: .name, stores: state.stores))
                googleOverrideEditor("Subtitle", shared: .subtitle,
                                     google: .googleShortDescription, bindingField: .subtitle)
                editor("Description", field: .description,
                       limit: BindingLimits.binding(for: .description, stores: state.stores),
                       multiline: true)
                googleOverrideEditor("What is new", shared: .whatsNew,
                                     google: .googleWhatsNew, bindingField: .whatsNew)

                if state.stores.contains(.apple) {
                    editor("Keywords", field: .keywords,
                           limit: BindingLimits.binding(for: .keywords, stores: state.stores),
                           tag: "Apple only")
                    editor("Promotional text", field: .promotionalText,
                           limit: BindingLimits.binding(for: .promotionalText, stores: state.stores),
                           tag: "Apple only")
                }
                if state.stores.contains(.google) {
                    editor("Short description", field: .googleShortDescription, limit: 80,
                           tag: "Google only")
                }
                editor("Support URL", field: .supportURL)
                if state.stores.contains(.apple) {
                    editor("Marketing URL", field: .marketingURL, tag: "Apple only")
                }
                editor("Privacy policy URL", field: .privacyPolicyURL)
                if state.stores.contains(.apple) {
                    editor("Privacy policy text", field: .privacyPolicyText,
                           multiline: true, tag: "Apple only")
                    editor("Privacy choices URL", field: .privacyChoicesURL,
                           tag: "Apple only")
                }
                // The parts of the listing that no API will write. It is a
                // wide list of rows, so it stays in this column while the
                // short fields sit beside the preview.
                ConsoleStepsPanel().padding(.top, 6)
                // Apple's own keyword resource, beside the Keywords field it
                // is so easily mistaken for.
                if state.stores.contains(.apple) {
                    SearchKeywordsPanel().padding(.top, 6)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func editor(_ title: String, field: ListingTextField, limit: Int? = nil,
                        multiline: Bool = false, tag: String? = nil) -> some View {
        let value = state.manifest.listingText(locale: state.locale, field: field)
        let overLimit = limit.map { value.count > $0 } ?? false
        // Grey means "this is what the store already says". The developer
        // types over it and it goes black, because the text no longer matches
        // what the store holds and the run will write it.
        let live = state.storeSnapshot.text(field, locale: state.locale)
        let unchanged = !live.isEmpty && live.allSatisfy { $0.value == value }
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 11.5, weight: .medium))
                if let tag { Tag(tag) }
                if unchanged { KeptTag() } else if !live.isEmpty { ChangedTag() }
                Spacer()
                if let limit {
                    // A character budget is a count of characters, not a
                    // quantity, so it takes no thousands separator: the 4000
                    // character description limit read as "4.000".
                    Text(verbatim: "\(value.count) / \(limit)")
                        .font(.system(size: 11, weight: overLimit ? .semibold : .regular))
                        .foregroundStyle(overLimit ? Theme.red : Theme.text2)
                        // The count changes on every key, so the digits have
                        // to hold their column or the label jitters as you type.
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(value.count) of \(limit) characters")
                }
            }
            if multiline {
                TextEditor(text: state.listingBinding(field).limited(to: limit))
                    .font(.system(size: 13))
                    .foregroundStyle(unchanged ? Theme.text2 : Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 90)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(overLimit ? Theme.red : Theme.sep,
                                      lineWidth: overLimit ? 1 : Theme.hairline))
            } else {
                TextField(title, text: state.listingBinding(field).limited(to: limit))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(unchanged ? Theme.text2 : Theme.text)
            }
            if overLimit {
                Text("\(value.count - (limit ?? 0)) characters over the store limit. The value is not shortened automatically.")
                    .font(.system(size: 11)).foregroundStyle(Theme.red)
            }
            liveValues(field, live: live, current: value)
        }
    }

    /// What the stores hold for this field today, when it is not what the
    /// developer is about to send. A matching value says nothing, so it stays
    /// out of the way.
    ///
    /// The App Store answers twice, and both answers matter. The draft is what
    /// a run patches, and an App Store Connect draft is usually empty. The
    /// live version is what a customer reads. Showing only the draft reported
    /// an app with no description while its page was full, so the live text is
    /// listed too, with the one button that takes it.
    @ViewBuilder
    private func liveValues(_ field: ListingTextField,
                            live: [(store: Store, value: String)],
                            current: String) -> some View {
        let differing = live.filter { $0.value != current }
        let onAppStore = state.storeSnapshot.liveOnAppStore(field, locale: state.locale)
            .flatMap { $0 == current ? nil : $0 }
        if !differing.isEmpty || onAppStore != nil {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(differing, id: \.store) { entry in
                    entryRow(label: "In the \(entry.store.storeName) draft",
                             store: entry.store, value: entry.value, field: field)
                }
                if let onAppStore {
                    entryRow(label: "On the App Store now", store: .apple,
                             value: onAppStore, field: field)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.sep2, lineWidth: Theme.hairline))
        }
    }

    private func entryRow(label: String, store: Store, value: String,
                          field: ListingTextField) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                StoreMark(store: store, size: 11)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text3)
                    .textCase(.uppercase)
                    .kerning(0.3)
                Spacer(minLength: 8)
                QuietButton(title: "Use this") {
                    state.listingBinding(field).wrappedValue = value
                }
                .accessibilityLabel("Use the text \(label.lowercased())")
            }
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(2)
                .lineLimit(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func googleOverrideEditor(_ title: String, shared: ListingTextField,
                                      google: ListingTextField,
                                      bindingField: ListingField) -> some View {
        let overrides: Set<Store> = state.manifest.hasGoogleOverride(locale: state.locale, field: google)
            ? [.google] : []
        editor(title, field: shared,
               limit: BindingLimits.binding(for: bindingField, stores: state.stores,
                                             overriddenIn: overrides),
               multiline: title == "What is new")
        if state.stores.contains(.google) {
            Toggle("Use different text for Google Play", isOn: state.googleOverrideBinding(google))
                .font(.system(size: 11.5))
            if state.manifest.hasGoogleOverride(locale: state.locale, field: google) {
                editor("Google Play \(title.lowercased())", field: google,
                       limit: title == "Subtitle" ? 80 : 500, multiline: title == "What is new",
                       tag: "Google only")
            }
        }
    }

}

/// The listing as each store will show it.
///
/// A view of its own, and not a property on `DetailsTab`. A property has to be
/// reached through an instance, and an instance built by hand outside the view
/// tree carries no environment, so reading `state` from it traps at the first
/// draw. The inspector needs this beside the editor, so it has to be a node
/// the tree can install.
private struct StoreReceivesPreview: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let name = state.manifest.listingText(locale: state.locale, field: .name)
        let subtitle = state.manifest.listingText(locale: state.locale, field: .subtitle)
        let description = state.manifest.listingText(locale: state.locale, field: .description)
        let googleSubtitle = state.manifest.hasGoogleOverride(locale: state.locale,
                                                             field: .googleShortDescription)
            ? state.manifest.listingText(locale: state.locale, field: .googleShortDescription)
            : subtitle
        return VStack(alignment: .leading, spacing: 14) {
            Text("What each store receives")
                .font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                .foregroundStyle(Theme.text3)
            if state.stores.contains(.apple) {
                StoreTextPreview(store: .apple, locale: state.locale, name: name,
                                 subtitle: subtitle, description: description)
            }
            if state.stores.contains(.google) {
                StoreTextPreview(store: .google, locale: state.locale, name: name,
                                 subtitle: googleSubtitle, description: description)
            }
        }
    }
}

/// What the listing looks like, and the values the store decides.
///
/// It was a fixed 340 point column welded to the right of the tab. Nothing in
/// it is prose the developer writes, so it was reference material taking a
/// third of the width away from the writing, and there was no way to put it
/// away. The shell now shows it as an inspector, which is the container macOS
/// has for exactly this: reference beside a document, hidden on a toggle.
struct DetailsInspector: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StoreReceivesPreview()
                // The ids and the declarations are fields, not reference, but
                // they answer "which app is this" and not "what does the
                // listing say". A box for `GAMES` has no business being 900
                // points wide between two paragraphs of listing text.
                if !state.stores.isEmpty { AppIdentifiers() }
                ListingDeclarations()
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.sunken)
    }
}

struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

/// The mark on a field that still says what the store says.
///
/// The grey text carries the message and this names it, because grey alone is
/// a colour and a colour alone is not a label. Both stores hold this text, so
/// the update sends nothing for this field.
struct KeptTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
            Text("Kept").font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.text3)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Theme.sunken, in: Capsule())
        .accessibilityLabel("Unchanged. The store already holds this text.")
    }
}

/// The mark on a field that no longer says what the store says.
///
/// It appears only once a store has answered for this field. A field nobody
/// has read carries neither chip, because "changed from what" has no answer
/// yet. Orange and not red: red says irreversible, and an edit is not.
struct ChangedTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "pencil").font(.system(size: 8, weight: .bold))
            Text("Changed").font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.orange)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Theme.orange.opacity(0.13), in: Capsule())
        .accessibilityLabel("Changed. The run will write this text to the store.")
    }
}

private struct StoreTextPreview: View {
    let store: Store
    let locale: String
    let name: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StoreMark(store: store, size: 13)
                Text("\(store.storeName) · \(locale)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            }
            Text(name.isEmpty ? "Untitled app" : name).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.text2)
            Text(description).font(.system(size: 11.5)).lineLimit(5)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

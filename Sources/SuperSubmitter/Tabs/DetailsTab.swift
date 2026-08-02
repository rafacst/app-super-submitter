import SubmitKit
import SwiftUI

/// Tab 3. All controls edit the active locale in `store.yaml` immediately.
struct DetailsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
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
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            preview
        }
    }

    @ViewBuilder
    private func editor(_ title: String, field: ListingTextField, limit: Int? = nil,
                        multiline: Bool = false, tag: String? = nil) -> some View {
        let value = state.manifest.listingText(locale: state.locale, field: field)
        let overLimit = limit.map { value.count > $0 } ?? false
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 11.5, weight: .medium))
                if let tag { Tag(tag) }
                Spacer()
                if let limit {
                    Text("\(value.count) / \(limit)")
                        .font(.system(size: 11, weight: overLimit ? .semibold : .regular))
                        .foregroundStyle(overLimit ? Theme.red : Theme.text2)
                }
            }
            if multiline {
                TextEditor(text: state.listingBinding(field))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 90)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(overLimit ? Theme.red : Theme.sep,
                                      lineWidth: overLimit ? 1 : Theme.hairline))
            } else {
                TextField(title, text: state.listingBinding(field))
                    .textFieldStyle(.roundedBorder)
            }
            if overLimit {
                Text("\(value.count - (limit ?? 0)) characters over the store limit. The value is not shortened automatically.")
                    .font(.system(size: 11)).foregroundStyle(Theme.red)
            }
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

    private var preview: some View {
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
            Spacer(minLength: 0)
        }
        .padding(18).frame(width: 300, alignment: .leading).background(Theme.sunken)
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

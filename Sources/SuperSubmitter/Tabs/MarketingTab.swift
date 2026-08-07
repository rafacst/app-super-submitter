import SubmitKit
import SwiftUI

/// Tab 7. The App Store resources that shape how the store sells the app.
///
/// Google Play offers no equivalent for anything on this tab, so the header
/// says it once instead of every section repeating it. Spec section 7.3.1.
struct MarketingTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            DirectApplyBar(target: .marketing)
            customProductPages
            experiments
            events
            licenceAgreement
            smallResources
        }
        .frame(maxWidth: 940, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Theme.text3)
            Text("Every field on this tab reaches the App Store alone. Google Play has no equivalent for any of it.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - The pages

    private var customProductPages: some View {
        let pages = state.marketing.customProductPages ?? []
        return Section_("Custom product pages", icon: "doc.on.doc.fill", tint: Theme.accent,
                        anchor: "marketing.customPages") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        FieldRow {
                            LabeledField("Key", width: 170) {
                                TextField("", text: state.customProductPageBinding(index: index,
                                                                                   name: false))
                            }
                            LabeledField("Name", width: 300) {
                                TextField("", text: state.customProductPageBinding(index: index,
                                                                                   name: true))
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                state.removeCustomProductPage(at: index)
                            } label: { Image(systemName: "trash") }
                        }
                        LabeledField("Promotional text, \(state.locale)", note: "170",
                                     width: 620) {
                            TextField("", text: state.customProductPageTextBinding(
                                index: index, locale: state.locale)
                                .limited(to: MarketingLimits.customProductPagePromotionalText))
                        }
                        Text("Apple allows 35 pages.")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }.storePanel()
                }
                Button("Add a custom product page") { state.addCustomProductPage() }
            }
        }
    }

    // MARK: - The experiments

    private var experiments: some View {
        let items = state.marketing.experiments ?? []
        return Section_("Product page experiments", icon: "flask.fill", tint: Theme.purple,
                        anchor: "marketing.experiments") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        FieldRow {
                            LabeledField("Key", width: 170) {
                                TextField("", text: state.experimentBinding(index: index,
                                                                            name: false))
                            }
                            LabeledField("Name", width: 300) {
                                TextField("", text: state.experimentBinding(index: index,
                                                                            name: true))
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                state.removeExperiment(at: index)
                            } label: { Image(systemName: "trash") }
                        }
                        FieldRow {
                            LabeledField("Traffic", width: 290) {
                                HStack(spacing: 8) {
                                    Slider(value: state.experimentTrafficBinding(index: index),
                                           in: 1...100, step: 1)
                                    Text("\(Int(state.experimentTrafficBinding(index: index).wrappedValue)) %")
                                        .font(Theme.mono(11.5)).frame(width: 40, alignment: .trailing)
                                }
                            }
                            LabeledField("Treatments", note: "comma-separated", width: 320) {
                                TextField("", text: state.experimentTreatmentsBinding(index: index))
                            }
                            Spacer(minLength: 0)
                        }
                        Text("The app creates the experiment and never starts it. Apple allows 3 treatments.")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }.storePanel()
                }
                Button("Add an experiment") { state.addExperiment() }
            }
        }
    }

    // MARK: - The events

    private var events: some View {
        let items = state.marketing.events ?? []
        return Section_("In-app events", icon: "calendar", tint: Theme.pink,
                        anchor: "marketing.events") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        FieldRow {
                            LabeledField("Key", width: 170) {
                                TextField("", text: state.appEventBinding(index: index,
                                                                          badge: false))
                            }
                            LabeledField("Badge", width: 300) {
                                ChoiceField(value: state.appEventBinding(index: index, badge: true),
                                            choices: StoreValues.eventBadges,
                                            emptyLabel: "No badge")
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                state.removeAppEvent(at: index)
                            } label: { Image(systemName: "trash") }
                        }
                        FieldRow {
                            LabeledField("Name, \(state.locale)", note: "30", width: 260) {
                                TextField("", text: state.appEventTextBinding(
                                    index: index, locale: state.locale, field: .name)
                                    .limited(to: MarketingLimits.appEventName))
                            }
                            LabeledField("Short description", note: "50", width: 340) {
                                TextField("", text: state.appEventTextBinding(
                                    index: index, locale: state.locale, field: .shortDescription)
                                    .limited(to: MarketingLimits.appEventShortDescription))
                            }
                            Spacer(minLength: 0)
                        }
                        LabeledField("Long description", note: "120", width: 620) {
                            TextField("", text: state.appEventTextBinding(
                                index: index, locale: state.locale, field: .longDescription)
                                .limited(to: MarketingLimits.appEventLongDescription))
                        }
                    }.storePanel()
                }
                Button("Add an in-app event") { state.addAppEvent() }
            }
        }
    }

    // MARK: - The licence agreement

    private var licenceAgreement: some View {
        Section_("Licence agreement", icon: "doc.text.fill", tint: Theme.teal,
                 anchor: "marketing.eula") {
            VStack(alignment: .leading, spacing: 7) {
                TextEditor(text: state.eulaTextBinding)
                    .font(.system(size: 12))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
                FieldRow {
                    LabeledField("Territories") {
                        MultiChoiceField(text: state.eulaTerritoriesBinding,
                                         choices: StoreValues.appleTerritories,
                                         emptyLabel: "Every territory")
                            .disabled(state.eulaTextBinding.wrappedValue.isEmpty)
                    }
                    LabeledField("Length", width: 90) {
                        Text("\(state.eulaTextBinding.wrappedValue.count) / 10000")
                            .font(Theme.mono(11))
                            .foregroundStyle(state.eulaTextBinding.wrappedValue.count > 10_000
                                             ? Theme.red : Theme.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("An empty agreement leaves the Apple standard licence in place.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.storePanel()
        }
    }

    // MARK: - The small resources

    private var smallResources: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 18) {
                routingCoverage
                nomination
            }
            VStack(alignment: .leading, spacing: 18) {
                accessibility
                appClip
            }
        }
    }

    private var routingCoverage: some View {
        Section_("Routing app coverage", icon: "map.fill", tint: Theme.green,
                 anchor: "marketing.routing") {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    TextField("assets/coverage.geojson", text: state.routingCoverageBinding)
                    Button("Choose…") {
                        guard let url = state.chooseOneFile(allowedExtensions: ["geojson", "json"])
                        else { return }
                        state.routingCoverageBinding.wrappedValue = state.relativePath(for: url)
                    }.controlSize(.small)
                }
                Text("A GeoJSON file. Only a routing app needs one.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.storePanel()
        }
    }

    private var nomination: some View {
        Section_("Featuring nomination", icon: "star.fill", tint: Theme.yellow,
                 anchor: "marketing.nomination") {
            VStack(alignment: .leading, spacing: 7) {
                TextField("Name", text: state.nominationBinding(.name))
                Picker("Type", selection: state.nominationBinding(.type)) {
                    ForEach(StoreValues.nominationTypes) { Text($0.label).tag($0.value) }
                }.labelsHidden()
                TextField("Description", text: state.nominationBinding(.description),
                          axis: .vertical)
                    .lineLimit(2...4)
                Text("The app creates a draft and never submits it.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.storePanel()
        }
    }

    private var accessibility: some View {
        Section_("Accessibility declaration", icon: "figure.wave", tint: Theme.orange,
                 anchor: "marketing.accessibility") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(StoreValues.accessibilityFeatures) { feature in
                    Toggle(feature.label, isOn: state.accessibilityBinding(feature.value))
                        .font(.system(size: 11.5))
                }
                Text("The declaration is written as a draft.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.storePanel()
        }
    }

    private var appClip: some View {
        Section_("App Clip default experience", icon: "bolt.fill", tint: Theme.accent,
                 anchor: "marketing.appClip") {
            VStack(alignment: .leading, spacing: 7) {
                Picker("Action", selection: state.appClipActionBinding) {
                    Text("None").tag("")
                    ForEach(StoreValues.appClipActions) { Text($0.label).tag($0.value) }
                }.labelsHidden()
                TextField("Subtitle, \(state.locale)",
                          text: state.appClipSubtitleBinding(locale: state.locale))
                Text("Xcode creates the clip. This writes what the store shows.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.storePanel()
        }
    }
}

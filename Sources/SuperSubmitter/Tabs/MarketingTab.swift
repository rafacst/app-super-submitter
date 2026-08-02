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
        return Section_("Custom product pages") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            TextField("Key",
                                      text: state.customProductPageBinding(index: index,
                                                                           name: false))
                                .frame(width: 150)
                            TextField("Name",
                                      text: state.customProductPageBinding(index: index,
                                                                           name: true))
                            Button(role: .destructive) {
                                state.removeCustomProductPage(at: index)
                            } label: { Image(systemName: "trash") }
                        }
                        TextField("Promotional text, \(state.locale)",
                                  text: state.customProductPageTextBinding(index: index,
                                                                           locale: state.locale))
                        Text("The limit is 170 characters. Apple allows 35 pages.")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }.marketingPanel()
                }
                Button("Add a custom product page") { state.addCustomProductPage() }
            }
        }
    }

    // MARK: - The experiments

    private var experiments: some View {
        let items = state.marketing.experiments ?? []
        return Section_("Product page experiments") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            TextField("Key",
                                      text: state.experimentBinding(index: index, name: false))
                                .frame(width: 150)
                            TextField("Name",
                                      text: state.experimentBinding(index: index, name: true))
                            Button(role: .destructive) {
                                state.removeExperiment(at: index)
                            } label: { Image(systemName: "trash") }
                        }
                        HStack(spacing: 10) {
                            Text("Traffic")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                            Slider(value: state.experimentTrafficBinding(index: index),
                                   in: 1...100, step: 1)
                                .frame(width: 220)
                            Text("\(Int(state.experimentTrafficBinding(index: index).wrappedValue)) %")
                                .font(Theme.mono(11.5)).frame(width: 46, alignment: .leading)
                            TextField("Treatments, comma-separated",
                                      text: state.experimentTreatmentsBinding(index: index))
                        }
                        Text("The app creates the experiment and never starts it. Apple allows 3 treatments.")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }.marketingPanel()
                }
                Button("Add an experiment") { state.addExperiment() }
            }
        }
    }

    // MARK: - The events

    private var events: some View {
        let items = state.marketing.events ?? []
        return Section_("In-app events") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            TextField("Key",
                                      text: state.appEventBinding(index: index, badge: false))
                                .frame(width: 150)
                            TextField("Badge, for example BADGE_LIVE_EVENT",
                                      text: state.appEventBinding(index: index, badge: true))
                            Button(role: .destructive) {
                                state.removeAppEvent(at: index)
                            } label: { Image(systemName: "trash") }
                        }
                        TextField("Name, \(state.locale)  ·  30 characters",
                                  text: state.appEventTextBinding(index: index,
                                                                  locale: state.locale,
                                                                  field: .name))
                        TextField("Short description  ·  50 characters",
                                  text: state.appEventTextBinding(index: index,
                                                                  locale: state.locale,
                                                                  field: .shortDescription))
                        TextField("Long description  ·  120 characters",
                                  text: state.appEventTextBinding(index: index,
                                                                  locale: state.locale,
                                                                  field: .longDescription))
                    }.marketingPanel()
                }
                Button("Add an in-app event") { state.addAppEvent() }
            }
        }
    }

    // MARK: - The licence agreement

    private var licenceAgreement: some View {
        Section_("Licence agreement") {
            VStack(alignment: .leading, spacing: 7) {
                TextEditor(text: state.eulaTextBinding)
                    .font(.system(size: 12))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
                HStack {
                    TextField("Territories, comma-separated. Empty means every territory.",
                              text: state.eulaTerritoriesBinding)
                        .disabled(state.eulaTextBinding.wrappedValue.isEmpty)
                    Text("\(state.eulaTextBinding.wrappedValue.count) / 10000")
                        .font(Theme.mono(11))
                        .foregroundStyle(state.eulaTextBinding.wrappedValue.count > 10_000
                                         ? Theme.red : Theme.text3)
                }
                Text("An empty agreement leaves the Apple standard licence in place.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.marketingPanel()
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
        Section_("Routing app coverage") {
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
            }.marketingPanel()
        }
    }

    private var nomination: some View {
        Section_("Featuring nomination") {
            VStack(alignment: .leading, spacing: 7) {
                TextField("Name", text: state.nominationBinding(.name))
                Picker("Type", selection: state.nominationBinding(.type)) {
                    ForEach(["APP_LAUNCH", "APP_ENHANCEMENTS", "IN_APP_EVENT",
                             "NEW_CONTENT"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
                TextField("Description", text: state.nominationBinding(.description),
                          axis: .vertical)
                    .lineLimit(2...4)
                Text("The app creates a draft and never submits it.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.marketingPanel()
        }
    }

    private var accessibility: some View {
        Section_("Accessibility declaration") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(AppState.accessibilityFeatures, id: \.self) { feature in
                    Toggle(feature.split(separator: "_").map(\.capitalized).joined(separator: " "),
                           isOn: state.accessibilityBinding(feature))
                        .font(.system(size: 11.5))
                }
                Text("The declaration is written as a draft.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.marketingPanel()
        }
    }

    private var appClip: some View {
        Section_("App Clip default experience") {
            VStack(alignment: .leading, spacing: 7) {
                Picker("Action", selection: state.appClipActionBinding) {
                    Text("None").tag("")
                    ForEach(["OPEN", "VIEW", "PLAY"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
                TextField("Subtitle, \(state.locale)",
                          text: state.appClipSubtitleBinding(locale: state.locale))
                Text("Xcode creates the clip. This writes what the store shows.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }.marketingPanel()
        }
    }
}

private extension View {
    func marketingPanel() -> some View {
        padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

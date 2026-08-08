import SubmitKit
import SwiftUI

/// The App Store marketing block of the new tab.
///
/// Every list here follows the same three calls: read the list, replace the
/// list, save. The manifest owns the order, and the tab never sorts.
extension AppState {

    var marketing: Manifest.Marketing { manifest.marketing ?? Manifest.Marketing() }

    private func setMarketing(_ value: Manifest.Marketing) {
        let empty = value.customProductPages == nil && value.experiments == nil
            && value.events == nil && value.eula == nil && value.routingCoverage == nil
            && value.nomination == nil && value.accessibility == nil && value.appClip == nil
        manifest.marketing = empty ? nil : value
        saveManifestReportingErrors()
    }

    // MARK: - The custom product pages

    func addCustomProductPage() {
        var value = marketing
        var pages = value.customProductPages ?? []
        pages.append(.init(key: "page-\(pages.count + 1)", name: "New page"))
        value.customProductPages = pages
        setMarketing(value)
    }

    func removeCustomProductPage(at index: Int) {
        var value = marketing
        guard value.customProductPages?.indices.contains(index) == true else { return }
        value.customProductPages?.remove(at: index)
        if value.customProductPages?.isEmpty == true { value.customProductPages = nil }
        setMarketing(value)
    }

    func customProductPageBinding(index: Int, name: Bool) -> Binding<String> {
        Binding(get: {
            guard let page = self.marketing.customProductPages?[safe: index] else { return "" }
            return name ? page.name : page.key
        }, set: { text in
            var value = self.marketing
            guard value.customProductPages?.indices.contains(index) == true else { return }
            if name { value.customProductPages?[index].name = text }
            else { value.customProductPages?[index].key = text }
            self.setMarketing(value)
        })
    }

    /// The promotional text of one page, in one locale. The default locale is
    /// the one the tab shows, the same rule as the Details tab.
    func customProductPageTextBinding(index: Int, locale: String) -> Binding<String> {
        Binding(get: {
            self.marketing.customProductPages?[safe: index]?
                .locales?[locale]?.promotionalText ?? ""
        }, set: { text in
            var value = self.marketing
            guard value.customProductPages?.indices.contains(index) == true else { return }
            var locales = value.customProductPages?[index].locales ?? [:]
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { locales.removeValue(forKey: locale) }
            else { locales[locale] = .init(promotionalText: text) }
            value.customProductPages?[index].locales = locales.isEmpty ? nil : locales
            self.setMarketing(value)
        })
    }

    // MARK: - The experiments

    func addExperiment() {
        var value = marketing
        var list = value.experiments ?? []
        list.append(.init(key: "experiment-\(list.count + 1)", name: "New experiment",
                          trafficProportion: 50,
                          treatments: [.init(key: "treatment-b", name: "Variant B")]))
        value.experiments = list
        setMarketing(value)
    }

    func removeExperiment(at index: Int) {
        var value = marketing
        guard value.experiments?.indices.contains(index) == true else { return }
        value.experiments?.remove(at: index)
        if value.experiments?.isEmpty == true { value.experiments = nil }
        setMarketing(value)
    }

    func experimentBinding(index: Int, name: Bool) -> Binding<String> {
        Binding(get: {
            guard let item = self.marketing.experiments?[safe: index] else { return "" }
            return name ? item.name : item.key
        }, set: { text in
            var value = self.marketing
            guard value.experiments?.indices.contains(index) == true else { return }
            if name { value.experiments?[index].name = text }
            else { value.experiments?[index].key = text }
            self.setMarketing(value)
        })
    }

    func experimentTrafficBinding(index: Int) -> Binding<Double> {
        Binding(get: {
            Double(self.marketing.experiments?[safe: index]?.trafficProportion ?? 50)
        }, set: { number in
            var value = self.marketing
            guard value.experiments?.indices.contains(index) == true else { return }
            value.experiments?[index].trafficProportion = Int(number.rounded())
            self.setMarketing(value)
        })
    }

    /// The treatments, as one comma-separated field. Apple allows three.
    func experimentTreatmentsBinding(index: Int) -> Binding<String> {
        Binding(get: {
            (self.marketing.experiments?[safe: index]?.treatments ?? [])
                .map(\.key).joined(separator: ", ")
        }, set: { text in
            var value = self.marketing
            guard value.experiments?.indices.contains(index) == true else { return }
            value.experiments?[index].treatments = Self.splitList(text).map {
                .init(key: $0, name: $0)
            }
            self.setMarketing(value)
        })
    }

    // MARK: - The in-app events

    func addAppEvent() {
        var value = marketing
        var list = value.events ?? []
        list.append(.init(key: "event-\(list.count + 1)", badge: "BADGE_LIVE_EVENT"))
        value.events = list
        setMarketing(value)
    }

    func removeAppEvent(at index: Int) {
        var value = marketing
        guard value.events?.indices.contains(index) == true else { return }
        value.events?.remove(at: index)
        if value.events?.isEmpty == true { value.events = nil }
        setMarketing(value)
    }

    func appEventBinding(index: Int, badge: Bool) -> Binding<String> {
        Binding(get: {
            guard let item = self.marketing.events?[safe: index] else { return "" }
            return badge ? item.badge ?? "" : item.key
        }, set: { text in
            var value = self.marketing
            guard value.events?.indices.contains(index) == true else { return }
            if badge { value.events?[index].badge = text.isEmpty ? nil : text }
            else { value.events?[index].key = text }
            self.setMarketing(value)
        })
    }

    enum AppEventTextField { case name, shortDescription, longDescription }

    func appEventTextBinding(index: Int, locale: String,
                             field: AppEventTextField) -> Binding<String> {
        Binding(get: {
            let text = self.marketing.events?[safe: index]?.locales?[locale]
            return switch field {
            case .name: text?.name ?? ""
            case .shortDescription: text?.shortDescription ?? ""
            case .longDescription: text?.longDescription ?? ""
            }
        }, set: { text in
            var value = self.marketing
            guard value.events?.indices.contains(index) == true else { return }
            var locales = value.events?[index].locales ?? [:]
            var entry = locales[locale] ?? .init()
            switch field {
            case .name: entry.name = text.isEmpty ? nil : text
            case .shortDescription: entry.shortDescription = text.isEmpty ? nil : text
            case .longDescription: entry.longDescription = text.isEmpty ? nil : text
            }
            let blank = entry.name == nil && entry.shortDescription == nil
                && entry.longDescription == nil
            if blank { locales.removeValue(forKey: locale) } else { locales[locale] = entry }
            value.events?[index].locales = locales.isEmpty ? nil : locales
            self.setMarketing(value)
        })
    }

    // MARK: - The single-value blocks

    var eulaTextBinding: Binding<String> {
        Binding(get: { self.marketing.eula?.text ?? "" },
                set: { text in
                    var value = self.marketing
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.eula = trimmed.isEmpty
                        ? nil
                        : .init(text: text, territories: value.eula?.territories)
                    self.setMarketing(value)
                })
    }

    var eulaTerritoriesBinding: Binding<String> {
        Binding(get: { (self.marketing.eula?.territories ?? []).joined(separator: ", ") },
                set: { text in
                    var value = self.marketing
                    guard var eula = value.eula else { return }
                    let list = Self.splitList(text).map { $0.uppercased() }
                    eula.territories = list.isEmpty ? nil : list
                    value.eula = eula
                    self.setMarketing(value)
                })
    }

    var routingCoverageBinding: Binding<String> {
        Binding(get: { self.marketing.routingCoverage ?? "" },
                set: { text in
                    var value = self.marketing
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.routingCoverage = trimmed.isEmpty ? nil : trimmed
                    self.setMarketing(value)
                })
    }

    enum NominationField { case name, type, description }

    func nominationBinding(_ field: NominationField) -> Binding<String> {
        Binding(get: {
            guard let nomination = self.marketing.nomination else { return "" }
            return switch field {
            case .name: nomination.name
            case .type: nomination.type
            case .description: nomination.description ?? ""
            }
        }, set: { text in
            var value = self.marketing
            var nomination = value.nomination
                ?? .init(name: "", type: "APP_LAUNCH")
            switch field {
            case .name: nomination.name = text
            case .type: nomination.type = text
            case .description: nomination.description = text.isEmpty ? nil : text
            }
            value.nomination = nomination.name.isEmpty && nomination.description == nil
                ? nil : nomination
            self.setMarketing(value)
        })
    }

    func accessibilityBinding(_ feature: String) -> Binding<Bool> {
        Binding(get: { self.marketing.accessibility?.supports.contains(feature) == true },
                set: { on in
                    var value = self.marketing
                    var supports = value.accessibility?.supports ?? []
                    if on {
                        if !supports.contains(feature) { supports.append(feature) }
                    } else {
                        supports.removeAll { $0 == feature }
                    }
                    value.accessibility = supports.isEmpty ? nil : .init(supports: supports)
                    self.setMarketing(value)
                })
    }

    var appClipActionBinding: Binding<String> {
        Binding(get: { self.marketing.appClip?.action ?? "" },
                set: { text in
                    var value = self.marketing
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty, value.appClip?.locales == nil {
                        value.appClip = nil
                    } else {
                        var clip = value.appClip ?? .init()
                        clip.action = trimmed.isEmpty ? nil : trimmed
                        value.appClip = clip
                    }
                    self.setMarketing(value)
                })
    }

    func appClipSubtitleBinding(locale: String) -> Binding<String> {
        appClipLocaleBinding(locale: locale, field: .subtitle)
    }

    /// The picture on the App Clip card. Apple keeps one per locale, beside
    /// the subtitle a reader sees under it.
    func appClipHeaderImageBinding(locale: String) -> Binding<String> {
        appClipLocaleBinding(locale: locale, field: .headerImage)
    }

    enum AppClipLocaleField { case subtitle, title, headerImage }

    /// One writer for the whole locale.
    ///
    /// The subtitle binding built a fresh `ClipLocale` on every keystroke, so
    /// typing a subtitle threw away the title beside it. With a header image
    /// on the same locale that would have thrown away a picture too.
    func appClipLocaleBinding(locale: String,
                              field: AppClipLocaleField) -> Binding<String> {
        Binding(get: {
            let text = self.marketing.appClip?.locales?[locale]
            return switch field {
            case .subtitle: text?.subtitle ?? ""
            case .title: text?.title ?? ""
            case .headerImage: text?.headerImage ?? ""
            }
        }, set: { text in
            var value = self.marketing
            var clip = value.appClip ?? .init()
            var locales = clip.locales ?? [:]
            var entry = locales[locale] ?? .init()
            let stored: String? = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? nil : text
            switch field {
            case .subtitle: entry.subtitle = stored
            case .title: entry.title = stored
            case .headerImage: entry.headerImage = stored
            }
            let empty = entry.subtitle == nil && entry.title == nil
                && entry.headerImage == nil
            if empty { locales.removeValue(forKey: locale) } else { locales[locale] = entry }
            clip.locales = locales.isEmpty ? nil : locales
            value.appClip = clip.action == nil && clip.locales == nil ? nil : clip
            self.setMarketing(value)
        })
    }
}

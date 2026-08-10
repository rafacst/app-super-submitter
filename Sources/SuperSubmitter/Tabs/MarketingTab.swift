import SubmitKit
import SwiftUI

/// Tab 7. The App Store resources that shape how the store sells the app.
///
/// **One store answers, so one store gets the width.** Google Play has no
/// equivalent for anything here. That was a grey footnote, then a column of its
/// own, and the column was 300 points of a 1040 point tab spent saying that
/// there is nothing in it: the App Store half was squeezed into what was left
/// and its own columns ran off the side of the window. The answer is still a
/// real one and it is one sentence long, so it is the ⓘ beside the store that
/// does answer. See `PlayHasNoneOfThis`.
///
/// The pages and the experiments are rows now and not open editors. Every one
/// of them drew all of its fields at once, so a tab with four pages was four
/// screens of boxes, and none of them said what the App Store already held. The
/// read has always carried that: `customProductPageNames` and `experiments`.
/// A row says what a page is and where it stands, and it opens onto the same
/// fields it always had.
struct MarketingTab: View {
    @Environment(AppState.self) private var state
    @State private var openPages: Set<Int> = []
    @State private var openExperiments: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DirectApplyBar(target: .marketing)
            appStoreColumn
            smallResources
        }
        .frame(maxWidth: 1040, alignment: .leading)
    }

    // MARK: - The one store that answers

    private var appStoreColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            columnHeader(.apple,
                         note: "every write here lands as a draft")
            customProductPages
            experiments
            events
        }
    }

    private func columnHeader(_ store: Store, note: String?) -> some View {
        HStack(spacing: 8) {
            StoreMark(store: store, size: 14)
            Text(store.storeName).font(Theme.font(size: 13, weight: .semibold))
            if state.stores.contains(.google) { PlayHasNoneOfThis() }
            Spacer(minLength: 8)
            if let note {
                Text(note).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: - The pages

    private var customProductPages: some View {
        let pages = state.marketing.customProductPages ?? []
        // No fold of its own. Every row inside it already opens, so a fold here
        // put an accordion inside an accordion and a field three clicks deep.
        // The header row says "2 of 35", which is the summary a shut fold would
        // have been standing in for.
        return Section_("Custom product pages", icon: "doc.on.doc.fill", tint: Theme.accent,
                        anchor: "marketing.customPages") {
            VStack(spacing: 0) {
                listHeader(count: "\(pages.count) of 35",
                           action: "Add a custom product page") {
                    state.addCustomProductPage()
                }
                if pages.isEmpty {
                    emptyLine("No page yet. A page is the same app under its own name, with its own screenshots and its own promotional text.")
                }
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        pageRow(index: index, page: page)
                        if openPages.contains(index) { pageEditor(index: index) }
                    }
                    .padding(.horizontal, 13).padding(.vertical, 9)
                }
            }
            .storePanel(padding: 0)
        }
    }

    /// One page: what it is called, what it carries, and where it stands.
    private func pageRow(index: Int, page: Manifest.Marketing.CustomProductPage) -> some View {
        let shots = Self.screenshotCount(page, locale: state.locale)
        let standing = Self.pageStatus(key: page.key, name: page.name, actual: state.actualState)
        return Button {
            toggle(index, in: $openPages)
        } label: {
            HStack(spacing: 10) {
                thumbnail(Self.firstScreenshot(page, locale: state.locale))
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.name.isEmpty ? page.key : page.name)
                        .font(Theme.font(size: 12.5))
                    Text(verbatim: "ppid=\(page.key) · \(shots) \(shots == 1 ? "screenshot" : "screenshots")")
                        .font(Theme.mono(11)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 8)
                StatePill(text: standing.text, foreground: standing.colour,
                          background: standing.background)
                Image(systemName: openPages.contains(index) ? "chevron.down" : "chevron.right")
                    .font(Theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func pageEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldRow {
                LabeledField("Key", width: 170) {
                    TextField("", text: state.customProductPageBinding(index: index, name: false))
                }
                LabeledField("Name", width: 300) {
                    TextField("", text: state.customProductPageBinding(index: index, name: true))
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    state.removeCustomProductPage(at: index)
                } label: { Image(systemName: "trash") }
            }
            LabeledField("Promotional text, \(state.locale)", note: "170") {
                TextField("", text: state.customProductPageTextBinding(
                    index: index, locale: state.locale)
                    .limited(to: MarketingLimits.customProductPagePromotionalText))
            }
            pageScreenshots(index: index)
        }
    }

    /// The pictures a page shows, and the way to the tab that holds them.
    ///
    /// Apple's `appCustomProductPageLocalizations` carries an
    /// `appScreenshotSets` relationship and the apply has always uploaded to
    /// it. The manifest has always held the paths. No control ever drew one, so
    /// the only way to give a page its own screenshots was the raw YAML editor.
    ///
    /// Nothing here is the page inheriting the default product page. That is
    /// what an empty list has always meant to the apply, which uploads nothing
    /// and leaves Apple showing what the page already shows.
    private func pageScreenshots(index: Int) -> some View {
        let held = state.customProductPageScreenshots(index: index, locale: state.locale)
        let sizes = held.keys.sorted()
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Screenshots, \(state.locale)")
                    .font(Theme.font(size: 11.5, weight: .medium))
                Spacer(minLength: 8)
                if held.isEmpty {
                    QuietButton(title: "Take the App Store screenshots") {
                        state.takeMediaScreenshots(intoPage: index, locale: state.locale)
                    }
                } else {
                    QuietButton(title: "Take them again") {
                        state.takeMediaScreenshots(intoPage: index, locale: state.locale)
                    }
                    QuietButton(title: "Clear") {
                        state.clearPageScreenshots(index: index, locale: state.locale)
                    }
                }
                QuietButton(title: "Open Media") { state.selectedTab = .media }
            }
            if held.isEmpty {
                Text("This page inherits the default product page. Take the App Store screenshots to start from them, then swap the ones this page should show.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(sizes, id: \.self) { size in
                    pageScreenshotRow(index: index, size: size, paths: held[size] ?? [])
                }
            }
        }
    }

    /// One device class of one page: what it shows, and the way to change it.
    private func pageScreenshotRow(index: Int, size: String, paths: [String]) -> some View {
        HStack(spacing: 8) {
            Text(Manifest.DeviceClass(rawValue: size)?.label ?? size)
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                .frame(width: Theme.scaled(110), alignment: .leading)
            ForEach(paths.prefix(6), id: \.self) { path in
                thumbnail(path)
            }
            if paths.count > 6 {
                Text(verbatim: "+\(paths.count - 6)")
                    .font(Theme.mono(10)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                state.setPageScreenshots(index: index, locale: state.locale,
                                         device: size, paths: [])
            } label: { Image(systemName: "trash") }
            .controlSize(.small)
        }
    }

    // MARK: - The experiments

    private var experiments: some View {
        let items = state.marketing.experiments ?? []
        // The same reason as the pages above: every experiment row opens.
        return Section_("Product page experiments", icon: "flask.fill", tint: Theme.purple,
                        anchor: "marketing.experiments") {
            VStack(spacing: 0) {
                listHeader(count: items.isEmpty
                               ? "" : "\(items.count) \(items.count == 1 ? "experiment" : "experiments")",
                           action: "Add an experiment") { state.addExperiment() }
                if items.isEmpty {
                    emptyLine("No experiment yet. An experiment shows a treatment to a share of the people who reach your page.")
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        experimentRow(index: index, experiment: item)
                        if openExperiments.contains(index) { experimentEditor(index: index) }
                    }
                    .padding(.horizontal, 13).padding(.vertical, 9)
                }
                Divider()
                // The last step of an experiment, and the one the manifest
                // cannot hold: promoting addresses Apple's own treatment id,
                // and it happens once, on a button.
                if state.stores.contains(.apple) {
                    PromoteTreatment().padding(.horizontal, 13).padding(.vertical, 9)
                }
            }
            .storePanel(padding: 0)
        }
    }

    private func experimentRow(index: Int,
                               experiment: Manifest.Marketing.Experiment) -> some View {
        let standing = Self.experimentStatus(key: experiment.key, name: experiment.name,
                                             actual: state.actualState)
        let held = Self.experiment(key: experiment.key, name: experiment.name,
                                   actual: state.actualState)
        let share = held?.trafficProportion ?? experiment.trafficProportion ?? 50
        let formatter = ISO8601DateFormatter()
        let day = Self.dayOfRun(start: held?.startDate.flatMap(formatter.date(from:)),
                                end: held?.endDate.flatMap(formatter.date(from:)),
                                now: Date())
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle(index, in: $openExperiments)
            } label: {
                HStack(spacing: 9) {
                    Text(verbatim: "\(experiment.name.isEmpty ? experiment.key : experiment.name) · \(share)% traffic")
                        .font(Theme.font(size: 12.5))
                    StatePill(text: day.map { "\(standing.text) · \($0)" } ?? standing.text,
                              foreground: standing.colour, background: standing.background)
                    Spacer(minLength: 8)
                    Image(systemName: openExperiments.contains(index)
                          ? "chevron.down" : "chevron.right")
                        .font(Theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            experimentResult(experiment)
        }
    }

    /// What each treatment did, when Apple can say.
    ///
    /// It usually cannot. The App Store Connect API reference documents the
    /// transport of an analytics report and never its contents: no report name,
    /// no column, no dimension, and `AppStoreVersionExperimentTreatment` carries
    /// no id that appears in one. So this draws the shape and never a number it
    /// has not been given. The Account tab fetches a report and prints the
    /// columns the account really returned.
    private func experimentResult(_ experiment: Manifest.Marketing.Experiment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(["Control"] + experiment.treatments.map(\.name), id: \.self) { name in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name.isEmpty ? "Treatment" : name)
                            .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                            .lineLimit(1)
                        Capsule().fill(Theme.sep2).frame(height: 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Its own line. As a trailing overlay it was drawn on top of the
            // last treatment's name, which is the one thing on the row that
            // cannot be guessed from the rest of it.
            HStack(spacing: 6) {
                Text("Apple publishes no per-treatment numbers. App Store Connect holds the result.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                Spacer(minLength: 0)
            }
        }
    }

    private func experimentEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldRow {
                LabeledField("Key", width: 170) {
                    TextField("", text: state.experimentBinding(index: index, name: false))
                }
                LabeledField("Name", width: 300) {
                    TextField("", text: state.experimentBinding(index: index, name: true))
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
                            .font(Theme.mono(11.5))
                            .frame(width: Theme.scaled(40), alignment: .trailing)
                    }
                }
                LabeledField("Treatments", note: "comma-separated", width: 320) {
                    TextField("", text: state.experimentTreatmentsBinding(index: index))
                }
                Spacer(minLength: 0)
            }
            Text("The app creates the experiment and never starts it. Apple allows 3 treatments.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
        }
    }

    // MARK: - The shared row furniture

    private func listHeader(count: String, action: String,
                            press: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            if !count.isEmpty {
                Text(count).font(Theme.mono(11)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 8)
            QuietButton(title: action, action: press)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
    }

    private func emptyLine(_ text: String) -> some View {
        HStack {
            Text(text).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.bottom, 9)
    }

    private func thumbnail(_ path: String?) -> some View {
        Group {
            if let path, !path.isEmpty {
                AsyncImage(url: state.mediaURL(for: path)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Hatched()
                }
            } else {
                Hatched()
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.sep2, lineWidth: Theme.hairline))
    }

    private func toggle(_ index: Int, in set: Binding<Set<Int>>) {
        if set.wrappedValue.contains(index) {
            set.wrappedValue.remove(index)
        } else {
            set.wrappedValue.insert(index)
        }
    }

    // MARK: - The events

    private var events: some View {
        let items = state.marketing.events ?? []
        return Section_("In-app events", icon: "calendar", tint: Theme.pink,
                        anchor: "marketing.events", folds: true) {
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

    // MARK: - The small resources

    /// The three App Store resources that are not the listing and not a page.
    ///
    /// The licence agreement and the accessibility declaration used to stand
    /// here. Neither one sells the app: one is the contract the customer
    /// accepts and the other is what the app can do for a customer who cannot
    /// see it. Both describe the app, so both moved to Details with the rest of
    /// the description.
    private var smallResources: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 18) {
                routingCoverage
                nomination
            }
            VStack(alignment: .leading, spacing: 18) {
                appClip
            }
        }
    }

    private var routingCoverage: some View {
        Section_("Routing app coverage", icon: "map.fill", tint: Theme.green,
                 anchor: "marketing.routing", folds: true, startsOpen: false,
                 note: "A GeoJSON file. Only a routing app needs one.") {
            HStack {
                TextField("assets/coverage.geojson", text: state.routingCoverageBinding)
                Button("Choose…") {
                    guard let url = state.chooseOneFile(allowedExtensions: ["geojson", "json"])
                    else { return }
                    state.routingCoverageBinding.wrappedValue = state.relativePath(for: url)
                }.controlSize(.small)
            }
        }
    }

    private var nomination: some View {
        Section_("Featuring nomination", icon: "star.fill", tint: Theme.yellow,
                 anchor: "marketing.nomination", folds: true, startsOpen: false,
                 note: "The app creates a draft and never submits it.") {
            VStack(alignment: .leading, spacing: 7) {
                TextField("Name", text: state.nominationBinding(.name))
                Picker("Type", selection: state.nominationBinding(.type)) {
                    ForEach(StoreValues.nominationTypes) { Text($0.label).tag($0.value) }
                }.labelsHidden()
                TextField("Description", text: state.nominationBinding(.description),
                          axis: .vertical)
                    .returnInsertsLineBreak()
                    .lineLimit(2...4)
            }
        }
    }

    /// The same path box the routing coverage and the purchase screenshots
    /// use, so a missing file is named here and not three tabs away.
    private var headerImageField: some View {
        let binding = state.appClipHeaderImageBinding(locale: state.locale)
        return PathField(path: binding,
                         problem: state.missingFileNote(for: binding.wrappedValue)) {
            guard let url = state.chooseOneFile(allowedExtensions: ["png", "jpg", "jpeg"])
            else { return }
            binding.wrappedValue = state.relativePath(for: url)
        }
    }

    private var appClip: some View {
        Section_("App Clip default experience", icon: "bolt.fill", tint: Theme.accent,
                 anchor: "marketing.appClip", folds: true, startsOpen: false,
                 note: "Xcode creates the clip. This writes what the store shows.") {
            VStack(alignment: .leading, spacing: 7) {
                Picker("Action", selection: state.appClipActionBinding) {
                    Text("None").tag("")
                    ForEach(StoreValues.appClipActions) { Text($0.label).tag($0.value) }
                }.labelsHidden()
                TextField("Subtitle, \(state.locale)",
                          text: state.appClipSubtitleBinding(locale: state.locale))
                // The visual half of the same card. Apple keeps one image per
                // locale, so it sits under the subtitle it appears above.
                LabeledField("Header image, \(state.locale)") {
                    headerImageField
                }
            }
        }
    }
}

// MARK: - What each store already holds

extension MarketingTab {
    /// One resource's standing, in the colour it has earned.
    struct Standing {
        var text: String
        var colour: Color
        var background: Color
    }

    static let notRead = Standing(text: "Not read", colour: Theme.text2,
                                  background: Theme.sep2)

    /// Whether the App Store holds this custom product page.
    ///
    /// `StoreIdentity` is the one rule, and the apply and the planner read it
    /// too. A store that has been through the older build can be holding the
    /// page under either spelling, so checking one of the two called a live
    /// page missing.
    ///
    /// Nothing read means nothing to compare against, and "Will add" would be a
    /// claim about a store nobody has asked.
    static func pageStatus(key: String, name: String, actual: ActualState) -> Standing {
        guard let apple = actual.apple, !apple.customProductPageNames.isEmpty
        else { return notRead }
        return StoreIdentity.holds(key: key, name: name, in: apple.customProductPageNames)
            ? Standing(text: "Live", colour: Theme.green, background: Theme.greenBg)
            : Standing(text: "Will add", colour: Theme.orange,
                       background: Theme.orange.opacity(0.13))
    }

    /// Apple's own word for where an experiment stands, title-cased and not
    /// reworded. `AppleWords` holds the one table the whole app reads.
    static func experimentStatus(key: String, name: String, actual: ActualState) -> Standing {
        guard let apple = actual.apple, !apple.experiments.isEmpty else { return notRead }
        guard let found = StoreIdentity.value(key: key, name: name, in: apple.experiments)
        else {
            return Standing(text: "Will add", colour: Theme.orange,
                            background: Theme.orange.opacity(0.13))
        }
        return Standing(text: AppleWords.title(found.state),
                        colour: found.state == "ACCEPTED" || found.state == "APPROVED"
                            ? Theme.green : Theme.yellow,
                        background: found.state == "ACCEPTED" || found.state == "APPROVED"
                            ? Theme.greenBg : Theme.yellowBg)
    }

    /// The experiment Apple holds for this row, under either spelling.
    static func experiment(key: String, name: String,
                           actual: ActualState) -> ActualState.Apple.Experiment? {
        StoreIdentity.value(key: key, name: name, in: actual.apple?.experiments ?? [:])
    }

    /// How far into its run an experiment is.
    ///
    /// Nil until Apple returns a start date, because an experiment that has not
    /// started has no day one and printing one reports a run that never began.
    static func dayOfRun(start: Date?, end: Date?, now: Date) -> String? {
        guard let start else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = (calendar.dateComponents([.day], from: start, to: now).day ?? 0) + 1
        guard day > 0 else { return nil }
        guard let end,
              let total = calendar.dateComponents([.day], from: start, to: end).day, total > 0
        else { return "day \(day)" }
        return "day \(day) of \(total)"
    }

    /// The pictures one page carries in the locale on screen.
    ///
    /// The manifest has always held these, per locale and per device class, and
    /// the apply uploads them. No control on this tab ever drew one, so the
    /// only way to see a page's screenshots was the raw YAML editor.
    static func screenshotCount(_ page: Manifest.Marketing.CustomProductPage,
                                locale: String) -> Int {
        (page.locales?[locale]?.screenshots ?? [:]).values.reduce(0) { $0 + $1.count }
    }

    /// The first picture of a page, for the thumbnail beside its name.
    static func firstScreenshot(_ page: Manifest.Marketing.CustomProductPage,
                                locale: String) -> String? {
        (page.locales?[locale]?.screenshots ?? [:])
            .sorted { $0.key < $1.key }
            .first { !$0.value.isEmpty }?
            .value.first
    }
}

/// Promoting one treatment of a product page experiment.
///
/// The app writes the experiments and their treatments above, and it never
/// starts one, because a running experiment changes what a real customer sees.
/// This is the step after the experiment is over: the treatment that won
/// becomes the product page.
///
/// It cannot come from the manifest. A promotion addresses Apple's own
/// treatment id, and it happens once, so it is a button and not a plan row.
private struct PromoteTreatment: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var treatments: [AppleActionsClient.Treatment] = []
    @State private var selection = ""
    @State private var confirming = false

    private var chosen: AppleActionsClient.Treatment? {
        treatments.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Promote a treatment").font(Theme.font(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                QuietButton(title: busy ? "Fetching…" : "Fetch the treatments") { load() }
                    .disabled(busy || state.actualState.apple?.versionId == nil)
            }
            if let error { ErrorLine(text: error) }
            if state.actualState.apple?.versionId == nil {
                Text("Read the stores on the Summary tab first, so the app knows which version the treatments belong to.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if loaded, treatments.isEmpty {
                Text("Apple holds no treatment for this version. The experiments above create them on the next run.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !treatments.isEmpty {
                HStack(spacing: 8) {
                    Picker("", selection: $selection) {
                        Text("Pick a treatment").tag("")
                        ForEach(treatments) { treatment in
                            Text("\(treatment.experimentName)  ·  \(treatment.name)")
                                .tag(treatment.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 380)
                    Button("Promote it") { confirming = true }
                        .controlSize(.small)
                        .disabled(busy || chosen == nil)
                    Spacer(minLength: 0)
                }
                Text("The winning treatment's screenshots and text replace the ones on the live page. Promoting a different treatment is the way back.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .storePanel()
        .confirmationDialog("Promote this treatment?", isPresented: $confirming) {
            Button("Promote it", role: .destructive) { promote() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every App Store visitor sees \(chosen?.name ?? "this treatment") on the product page from now on. Promoting a different treatment is the way back.")
        }
    }

    private func load() {
        track($busy, $error) {
            treatments = try await state.appleTreatments()
            loaded = true
        }
    }

    private func promote() {
        guard let chosen else { return }
        track($busy, $error) {
            try await state.promoteAppleTreatment(chosen.id)
        }
    }
}

/// What Google Play does with everything on this tab, behind the ⓘ beside the
/// store that does answer.
///
/// Play has all three of these products and publishes none of them: custom
/// store listings, store listing experiments and LiveOps events live in the
/// Play Console, and the Android Publisher API exposes no endpoint for any of
/// them. That is a fact about the API and not about this app.
///
/// It was a column, 300 points of a 1040 point tab, and every one of those
/// points said the same sentence: there is nothing here. A tab that gives a
/// third of itself to an absence is a tab whose one working store is squeezed,
/// so the absence is one glyph and the sentence is a click away.
private struct PlayHasNoneOfThis: View {
    @Environment(AppState.self) private var state
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "info.circle")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.text3)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What Google Play does with these")
        .help("Play has none of this")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    StoreMark(store: .google, size: 14)
                    Text("Play has none of this")
                        .font(Theme.font(size: 12, weight: .semibold))
                }
                Text("Custom store listings, store listing experiments and LiveOps events all exist in the Play Console, and the Android Publisher API exposes none of them.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    state.open("https://play.google.com/console")
                } label: {
                    Text("Open Play Console ↗")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(13)
            .frame(maxWidth: 320, alignment: .leading)
        }
    }
}

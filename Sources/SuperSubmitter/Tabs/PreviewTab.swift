import SubmitKit
import SwiftUI

/// The app as a customer meets it.
///
/// Every other tab in this app is a form: it shows the fields a store takes,
/// one under another, in the order the API takes them. None of them answers
/// the question a developer actually has, which is what the thing will look
/// like. A name that fits a text field truncates on a phone, a subtitle reads
/// as a sentence in a form and as a headline on a page, and eight screenshots
/// in a grid of tiles are a carousel of two by the time anybody sees them.
///
/// **One source rule.** The draft wins, and the store fills what the draft
/// leaves empty. It is the same rule `StateReader.readLiveMedia` uses for the
/// pictures, for the same reason: what the developer is about to send is what
/// they came to look at, and a field they have not touched is still whatever
/// the customers are reading now. That one rule is what lets one screen serve
/// both jobs without a mode of its own:
///
/// - A new app has no store side at all, so every line is the draft, and the
///   page is a mockup of what the app will look like once it ships.
/// - An imported app has a manifest that `mergeAppleImport` filled from the
///   store, so the page is what the store holds today.
/// - A live app with an edit in it shows the edit where the edit is and the
///   store everywhere else, which is the page the next submission will make.
///
/// **Nothing is saved and nothing needs to be.** The two sources are already
/// on disk: `store.yaml` and `.super-submitter/store-snapshot.json`. `AppState`
/// is `@Observable` and both hang off it, so a saved screenshot or a rewritten
/// description reaches this screen because it is a view of those files and not
/// a copy of them. A cache here would be a third copy to keep in step with two.
///
/// **The empty slots stay.** A store page with no screenshots still has a
/// place where the screenshots go, so an empty bucket draws the shape of what
/// is missing rather than closing up. Half the value of the screen is seeing
/// which parts of the page are still blank.
struct PreviewTab: View {
    @Environment(AppState.self) private var state

    /// Nil until the developer picks. See `store`.
    @State private var picked: Store?

    /// The width the page is drawn at.
    ///
    /// Both stores lay a product page out in one column on a phone, and that
    /// column is what every measurement on the page is tuned for: the name
    /// wraps where the phone wraps it, the description clamps where the phone
    /// clamps it. Drawn at the width of a Mac window it would be a page no
    /// customer will ever see, which is the one thing this screen may not be.
    private static let pageWidth: CGFloat = 412

    // MARK: - Which store

    /// The stores this app goes to, App Store first, the order the tabs use.
    ///
    /// An app that names no store is treated as an App Store app, the same
    /// default `DetailsTab.shows(_:)` takes, so the page is never empty for
    /// the want of a checkbox nobody ticked.
    private var stores: [Store] {
        let chosen = Store.allCases.filter { state.stores.contains($0) }
        return chosen.isEmpty ? [.apple] : chosen
    }

    /// The store on screen. The pick, while the pick is still one of this
    /// app's stores: a developer who previews Play and then unticks Play would
    /// otherwise be left looking at a page for a store the app does not go to.
    private var store: Store {
        picked.flatMap { stores.contains($0) ? $0 : nil } ?? stores[0]
    }

    // MARK: - The page

    private var row: AppSummary? {
        state.appRows.indices.contains(state.selectedAppIndex)
            ? state.appRows[state.selectedAppIndex] : nil
    }

    /// One field of the page. The draft first, then the store. See the note on
    /// the type for why this order and not the other one.
    private func text(_ field: ListingTextField) -> String {
        let draft = state.manifest.listingText(locale: state.locale, field: field)
        return draft.isEmpty
            ? state.storeSnapshot.live(field, store: store, locale: state.locale)
            : draft
    }

    /// The line under the name. Apple calls it the subtitle and Play calls it
    /// the short description, and both stores draw it in the same place.
    private var tagline: String {
        store == .apple ? text(.subtitle) : text(.googleShortDescription)
    }

    /// The release notes, under each store's own heading.
    private var whatsNew: String {
        let field: ListingTextField = store == .apple ? .whatsNew : .googleWhatsNew
        let value = text(field)
        // Play falls back to the shared field, the same way the run does when
        // no Play-specific note is written.
        return value.isEmpty && store == .google ? text(.whatsNew) : value
    }

    /// The size the page is drawn at.
    ///
    /// A store page leads with one device, and phone is the one nearly every
    /// listing leads with, so phone wins whenever it holds anything. The first
    /// size that holds something wins otherwise: a Mac-only app has no phone
    /// screenshots and its page is not therefore an empty page.
    private var deviceClass: Manifest.DeviceClass {
        let order: [Manifest.DeviceClass] = [.phone, .tablet10, .tablet7,
                                             .desktop, .vision, .tv, .watch]
        return order.first { !screenshots(deviceClass: $0).isEmpty } ?? .phone
    }

    private func screenshots(deviceClass: Manifest.DeviceClass) -> [URL] {
        let paths = state.mediaPaths(deviceClass: deviceClass, store: store)
        guard paths.isEmpty else { return paths.map(state.mediaURL(for:)) }
        return state.storeSnapshot.screenshots(locale: state.locale,
                                               deviceClass: deviceClass)
            .first { $0.store == store }?.urls ?? []
    }

    /// The icon, from the store that shows it, or the one file on disk.
    ///
    /// `media.icon` is Play's field: Apple takes no icon file and extracts one
    /// from the binary instead. It stands in on the Apple side because the two
    /// are the same artwork in every app that has one, and `iconNote` says so
    /// rather than letting a stand-in pass for the store's own.
    private var icon: URL? {
        state.storeSnapshot.icon(store, locale: state.locale)
            ?? state.manifest.media?.icon
                .flatMap { Planner.resolve($0, root: state.manifestRoot) }
    }

    /// Why the App Store side has no icon of its own yet.
    ///
    /// Apple has nothing to answer with until a build carrying an icon reaches
    /// App Store Connect, so this is not a failure and may not read as one.
    /// `AppState.captureAppleIcon()` fills it in the moment a submission goes.
    /// It has two cases because the screen has two, and the first draft of it
    /// had one: "there is none to show yet" was printed over an icon that was
    /// plainly on the screen, because `media.icon` had stood in and the note
    /// did not know. A line that argues with the picture beside it is worse
    /// than no line.
    private var iconNote: String? {
        guard store == .apple, state.storeSnapshot.appleIcon == nil else { return nil }
        let head = "The App Store takes its icon from the app binary and not from a file"
        let tail = " It fills in here as soon as you send this app to App Store review."
        return icon == nil
            ? head + ", so there is none to show yet." + tail
            : head + ". This is the icon file from the manifest, standing in." + tail
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if stores.count > 1 { storePicker }
            // Not a `WarningNote`. Nothing is wrong: the icon is where Apple
            // keeps it and this app has not been given it yet. A yellow
            // triangle over that sends a developer looking for a mistake they
            // did not make.
            if let iconNote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(Theme.font(size: 10)).padding(.top, 2)
                    Text(iconNote).font(Theme.font(size: 11.5)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.text3)
                .frame(width: Self.pageWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            page
                .frame(width: Self.pageWidth)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Only when the app goes to both. One store is not a choice.
    private var storePicker: some View {
        Picker("Store", selection: Binding(get: { store },
                                           set: { picked = $0 })) {
            ForEach(stores) { store in
                Text(store.storeName).tag(store)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Play leads with the banner. The App Store has no element like
            // it, so the Apple page starts one row further down rather than
            // holding a gap for something Apple never draws.
            if store == .google { featureGraphic }
            header
            Divider_()
            shots
            Divider_()
            if store == .apple {
                block("Description", text(.description))
                Divider_()
                block("What's New", whatsNew, version: state.manifest.displayVersionName)
                Divider_()
                information
            } else {
                block("About this app", text(.description))
                Divider_()
                block("What's new", whatsNew, version: state.manifest.displayVersionName)
                Divider_()
                information
            }
        }
        .background(Theme.content, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }

    private var featureGraphic: some View {
        Group {
            if let url = state.storeSnapshot.featureGraphic(locale: state.locale) {
                PreviewImage(url: url, fill: true)
            } else {
                Mock(label: "Feature graphic")
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let icon {
                    // The frame before the clip. The other way round the
                    // picture is cropped at whatever size it arrived at and
                    // then scaled, so a 1024pt icon came back with a corner
                    // radius of about two points.
                    PreviewImage(url: icon, fill: true)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(
                            cornerRadius: store == .apple ? 20 : 44))
                } else {
                    // The badge the sidebar already draws for an app with no
                    // icon file. Two answers to "no icon" would be two.
                    AppIconBadge(icon: nil, initials: row?.initials ?? "", size: 88)
                }
            }
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                Line(text(.name), fallback: row?.name ?? "App name",
                     font: Theme.font(size: 19, weight: .semibold), limit: 2)
                Line(tagline,
                     fallback: store == .apple ? "Subtitle" : "Short description",
                     font: Theme.font(size: 12.5), colour: Theme.text2, limit: 2)
                Spacer(minLength: 6)
                getButton
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    /// Drawn, not built. It is the one element on the page that does nothing,
    /// and it is here because a page without it does not read as a store page.
    private var getButton: some View {
        Text(store == .apple ? "GET" : "Install")
            .font(Theme.font(size: 12, weight: .bold))
            .foregroundStyle(store == .apple ? Theme.accent : Color.white)
            .padding(.horizontal, store == .apple ? 20 : 26)
            .padding(.vertical, store == .apple ? 5 : 7)
            .background(store == .apple ? Theme.sunken : Theme.playGreen,
                        in: Capsule())
            .accessibilityHidden(true)
    }

    private var shots: some View {
        VStack(alignment: .leading, spacing: 8) {
            let urls = screenshots(deviceClass: deviceClass)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if urls.isEmpty {
                        // Three, because one grey block reads as a broken
                        // image and three read as an empty carousel.
                        ForEach(0..<3, id: \.self) { _ in
                            Mock(label: nil)
                                .frame(width: 150, height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        ForEach(urls, id: \.self) { url in
                            PreviewImage(url: url)
                                .frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                // The Media tab opens a screenshot at full
                                // size on a click and so does this one.
                                .onTapGesture { QuickLook.show(url) }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 300)
        }
        .padding(.vertical, 16)
    }

    private func block(_ title: String, _ body: String,
                       version: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Theme.font(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                if let version, !version.isEmpty {
                    Text(version)
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                        .monospacedDigit()
                }
            }
            Line(body, fallback: "Nothing written here yet.",
                 font: Theme.font(size: 12.5), colour: Theme.text2, limit: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The links block both stores end a page with.
    private var information: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Information").font(Theme.font(size: 15, weight: .semibold))
            // Apple names three, Play names the privacy policy and the site.
            let links: [(String, ListingTextField)] = store == .apple
                ? [("Developer Website", .marketingURL), ("App Support", .supportURL),
                   ("Privacy Policy", .privacyPolicyURL)]
                : [("Website", .marketingURL), ("Privacy Policy", .privacyPolicyURL)]
            ForEach(links, id: \.0) { label, field in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(label)
                        .font(Theme.font(size: 12)).foregroundStyle(Theme.text3)
                    Spacer(minLength: 8)
                    Line(text(field), fallback: "Not set", font: Theme.font(size: 12),
                         colour: Theme.accent, limit: 1)
                        .frame(maxWidth: 210, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The parts

/// One line of the page, or the shape of the line that is missing.
///
/// The empty case is the whole point of the screen, so it is drawn and never
/// skipped: a page that closed up around its empty fields would show a
/// developer a tidy page and hide the four things still to write.
private struct Line: View {
    let value: String
    let fallback: String
    var font: Font = Theme.body
    var colour: Color = Theme.text
    var limit: Int

    init(_ value: String, fallback: String, font: Font = Theme.body,
         colour: Color = Theme.text, limit: Int) {
        self.value = value
        self.fallback = fallback
        self.font = font
        self.colour = colour
        self.limit = limit
    }

    var body: some View {
        // Verbatim. A store listing is the developer's own words and nothing
        // here may go through `LocalizedStringKey`, which would read a stray
        // bracket in a description as markup.
        Text(verbatim: value.isEmpty ? fallback : value)
            .font(font)
            .foregroundStyle(value.isEmpty ? Theme.text3.opacity(0.75) : colour)
            .lineLimit(limit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The shape of an element that has nothing in it yet.
private struct Mock: View {
    let label: String?

    var body: some View {
        ZStack {
            Theme.sunken
            if let label {
                Text(label).font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            }
        }
    }
}

/// A picture from disk, or one the store is serving.
///
/// Two loaders, because the two sources need two. `NSImage(contentsOf:)` on an
/// https URL blocks the thread it is called on for a whole network read, and
/// `AsyncImage` on a file URL puts a scheduler between the view and a file it
/// could have opened outright. The Media tab already splits them this way.
private struct PreviewImage: View {
    let url: URL
    /// Fill crops to the frame and fit keeps the whole picture.
    ///
    /// The icon and the banner fill: both are drawn in a slot of a shape the
    /// store fixed, and a letterboxed icon is not what the store draws. A
    /// screenshot fits, because its shape is the thing being checked and a
    /// carousel that crops one is a carousel that lies about it.
    var fill = false

    @ViewBuilder
    private func drawn(_ image: Image) -> some View {
        if fill {
            image.resizable().scaledToFill()
        } else {
            image.resizable().scaledToFit()
        }
    }

    var body: some View {
        if url.isFileURL {
            if let image = NSImage(contentsOf: url) {
                drawn(Image(nsImage: image))
            } else {
                Mock(label: nil)
            }
        } else {
            AsyncImage(url: url) { drawn($0) } placeholder: { Mock(label: nil) }
        }
    }
}

/// The rule between two blocks of the page. `Divider` takes the system inset
/// and the page draws edge to edge.
private struct Divider_: View {
    var body: some View {
        Rectangle().fill(Theme.sep2).frame(height: Theme.hairline)
    }
}

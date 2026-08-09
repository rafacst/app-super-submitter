import AppKit
import SubmitKit
import SwiftUI

/// Tab 4. Files are validated before their relative paths are written to the manifest.
struct MediaTab: View {
    @Environment(AppState.self) private var state
    /// The groups the developer opened or closed by hand. A device class that
    /// is missing here follows what it holds, so an import that fills a bucket
    /// opens it and nothing has to be told about the new files.
    @State private var open: [Manifest.DeviceClass: Bool] = [:]
    /// The tile a dragged screenshot would land in front of.
    ///
    /// One value for the whole tab and not one per group. A drag has one
    /// pointer, so only one tile can ever be targeted, and a flag per group
    /// would leave a stale line behind in the group the pointer left.
    @State private var dropTarget: String?

    private var groups: [(String, Manifest.DeviceClass)] {
        var values: [(String, Manifest.DeviceClass)] = [("Phone", .phone)]
        if state.stores.contains(.google) { values.append(("Small tablet", .tablet7)) }
        values.append(("Large tablet", .tablet10))
        if state.stores.contains(.apple) { values.append(("Desktop", .desktop)) }
        values.append(contentsOf: [("Watch", .watch), ("TV", .tv)])
        if state.stores.contains(.apple) { values.append(("Vision", .vision)) }
        return values
    }

    /// The stores that take a device class.
    ///
    /// A fact of the two catalogues rather than a layout choice, so it is
    /// answered once: Play alone reads a 7 inch tablet, Apple alone reads a
    /// Mac screen and a Vision one, and everything else goes to both.
    ///
    /// This is about which store *accepts* a size, not about whose pictures
    /// fill it. A size both stores take still holds a list per store, because
    /// the two listings rarely show the same eight images.
    static func takers(_ device: Manifest.DeviceClass) -> Set<Store> {
        switch device {
        case .desktop, .vision: [.apple]
        case .tablet7: [.google]
        default: [.apple, .google]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Publishing sends this tab through the Summary tab, which
            // plans and then writes. Managing has none, so it writes here.
            if state.mode == .managing { DirectApplyBar(target: .media) }
            if let error = state.mediaError { WarningNote(error) }
            flowNote
            // Grouped by the store that asks for the size. Seven device
            // classes in one column said nothing about which store wanted
            // which, so a developer had to know the two catalogues already to
            // read the page.
            band(shared, title: "Both stores take these sizes",
                 detail: "Each store keeps its own pictures. Merge a size to send one set to both.")
            band(only(.apple), title: "App Store only", store: .apple)
            band(only(.google), title: "Google Play only", store: .google)
            videoSection
            if state.stores.contains(.google) { googleGraphics }
        }
        // The one tab that never capped itself. Without this the group header
        // stretches to the window, which put "Choose images…" about 1400
        // points from the name of the group it belongs to.
        .frame(maxWidth: 980, alignment: .leading)
        // A column per store means a list per store, so the sizes that hold
        // pictures get one on arrival and on every change of language. Only
        // the sizes that hold something: see `splitMediaForThisLocale`.
        .task(id: state.locale) { state.splitMediaForThisLocale() }
    }

    /// The sizes both selected stores read.
    private var shared: [(String, Manifest.DeviceClass)] {
        groups.filter { Self.takers($0.1).isSuperset(of: state.stores) && state.stores.count > 1 }
    }

    /// The sizes one selected store reads and the other does not. With a
    /// single store picked, every size lands here, which is the truth: they
    /// all belong to that one store.
    private func only(_ store: Store) -> [(String, Manifest.DeviceClass)] {
        guard state.stores.contains(store) else { return [] }
        guard state.stores.count > 1 else {
            return groups.filter { Self.takers($0.1).contains(store) }
        }
        return groups.filter { Self.takers($0.1) == [store] }
    }

    /// One store's sizes, under that store's name.
    @ViewBuilder
    private func band(_ entries: [(String, Manifest.DeviceClass)], title: String,
                      store: Store? = nil, detail: String? = nil) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                storeBand(title, store: store, detail: detail)
                ForEach(entries, id: \.1) { name, device in
                    mediaGroup(name, device: device)
                }
            }
        }
    }

    private func storeBand(_ title: String, store: Store?, detail: String?) -> some View {
        HStack(spacing: 8) {
            if let store { StoreMark(store: store, size: 15) }
            Text(title).font(Theme.font(size: 13, weight: .semibold))
            if let detail {
                Text(detail).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 8)
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// The tile takes the shape of the screen it shows.
    ///
    /// One 112 by 160 box for every device class put a 1440 by 900 desktop
    /// screenshot in a portrait card and left ninety points of air under it,
    /// five times across the row. The catalog already knows every shape.
    ///
    /// The floor is the caption: "1290 × 2796" needs more width than a phone
    /// screen has at this height, so a portrait tile keeps the old column and
    /// centres its image in it.
    private static func tile(_ deviceClass: Manifest.DeviceClass) -> CGSize {
        let side: CGFloat = 150
        let aspect = AssetInspector.aspectRatio(for: deviceClass)
        return CGSize(width: max(112, aspect >= 1 ? side : side * aspect),
                      height: aspect >= 1 ? side / aspect : side)
    }

    /// What this tab is for, which is a different sentence on an app that has
    /// shipped and an app that has not.
    ///
    /// An update carries its screenshots forward by itself, so the job here is
    /// to say that nothing is required and what changing one costs. A first
    /// submission has the opposite problem: neither store accepts a listing
    /// with no screenshots at all, and the tab used to say so nowhere.
    @ViewBuilder
    private var flowNote: some View {
        let sends = state.stores.sorted { $0.rawValue < $1.rawValue }
            .map(\.storeName).joined(separator: " and ")
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: state.isUpdatingLiveApp
                  ? "arrow.triangle.2.circlepath" : "exclamationmark.circle.fill")
                .font(Theme.font(size: 11))
                .foregroundStyle(state.isUpdatingLiveApp ? Theme.text2 : Theme.yellow)
            VStack(alignment: .leading, spacing: 3) {
                if state.isUpdatingLiveApp {
                    Text("Keep the current screenshots, or replace a size.")
                        .font(Theme.font(size: 11.5, weight: .semibold))
                    Text("An empty size keeps what is live. Adding images replaces that size only.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    // An update that shows no live pictures is either an app
                    // with none or a read that did not reach them, and an
                    // empty grid says neither.
                    if !state.hasLiveScreenshots {
                        Text("None read for \(state.locale) yet. Run a read on the Summary tab.")
                            .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    }
                } else {
                    Text("Screenshots are required.")
                        .font(Theme.font(size: 11.5, weight: .semibold))
                    Text("\(sends) will not accept this listing without them. The ⓘ beside each size lists the pixel dimensions it takes.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .storePanel()
    }

    private func mediaGroup(_ name: String, device: Manifest.DeviceClass) -> some View {
        let paths = state.mediaPaths(deviceClass: device)
        let limit = state.stores.contains(.google) ? 8 : 10
        // An import already downloaded these same images into the tiles, so
        // the faded strip stays out of the way when the bucket holds them.
        let live = paths.contains(where: AppState.isImported)
            ? []
            : state.storeSnapshot.screenshots(locale: state.locale, deviceClass: device)
        // A group opens on what it holds. Nil is the default, so a bucket the
        // next import fills opens by itself, and a developer who closed one by
        // hand keeps it closed. Every store shows seven device classes and an
        // app answers two of them, so six empty dashed cards used to push the
        // one group with screenshots in it most of a screen down.
        let isOpen = open[device] ?? !(paths.isEmpty && live.isEmpty)
        let tile = Self.tile(device)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button { open[device] = !isOpen } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.right")
                            .font(Theme.font(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                        Text(name).font(Theme.font(size: 12.5, weight: .semibold))
                        // Verbatim, so a locale that groups thousands cannot
                        // render a count as "1.242". The digits also have to
                        // hold still while the number changes, or the name
                        // beside them shuffles.
                        Text(verbatim: "\(paths.count) of \(limit)")
                            .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        // The store's own count, so a collapsed group still
                        // says the App Store is showing five pictures here.
                        // Without it a developer who changed nothing read the
                        // same "0 of 10" as one who has no screenshots at all.
                        if !live.isEmpty {
                            let count = live.reduce(0) { $0 + $1.urls.count }
                            StatePill(text: "\(count) LIVE", foreground: Theme.text2,
                                      background: Theme.sunken)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name), \(paths.count) of \(limit)")
                .accessibilityHint(isOpen ? "Hide the images" : "Show the images")
                SizeInfoButton(name: name, deviceClass: device,
                               stores: state.stores)
                Spacer()
                // A closed group carries no control. Six "Choose images…"
                // buttons down the right of a page is the noise this tab is
                // here to lose.
                if isOpen {
                    Button("Choose images…") { state.chooseMediaFiles(deviceClass: device) }
                        .controlSize(.small)
                }
            }
            if isOpen {
                // One row per store when the app ships on both, because the
                // two listings rarely show the same eight pictures. A size
                // that holds one list for both says so and offers the split.
                let rows: [Store?] = state.stores.count > 1 && state.mediaIsSplit(device)
                    ? Store.allCases.filter(state.stores.contains)
                    : [nil]
                ForEach(rows, id: \.self) { store in
                    tiles(name, device, tile: tile, store: store)
                }
                mergeControl(device)
                liveScreenshots(live)
            }
        }
        .motion(.snappy(duration: 0.18), value: isOpen)
    }


    /// One store's pictures for one size, or the shared list when the size
    /// holds a single one.
    @ViewBuilder
    private func tiles(_ name: String, _ device: Manifest.DeviceClass, tile: CGSize,
                       store: Store?) -> some View {
        let paths = state.mediaPaths(deviceClass: device, store: store)
        VStack(alignment: .leading, spacing: 6) {
            if let store {
                HStack(spacing: 6) {
                    StoreMark(store: store, size: 13)
                    Text(store.storeName).font(Theme.font(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.text2)
                    Text(verbatim: "\(paths.count)")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                        .monospacedDigit()
                    // The pixel sizes this store takes for this size, beside
                    // this store's own row. The group header carries the pair;
                    // a developer filling the Play row wants Play's numbers.
                    SizeInfoButton(name: name, deviceClass: device, stores: [store])
                    Spacer(minLength: 0)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                        MediaTile(path: path, size: tile,
                                  info: state.imageInfo(for: path),
                                  stores: state.imageStores(for: path, deviceClass: device),
                                  url: state.mediaURL(for: path),
                                  fromStore: AppState.isImported(path),
                                  canMoveEarlier: index > 0,
                                  canMoveLater: index < paths.count - 1,
                                  insertBefore: dropTarget == path,
                                  move: { offset in
                                      state.moveMedia(path, by: offset, deviceClass: device,
                                                      store: store)
                                  }) {
                            state.removeMedia(path, deviceClass: device, store: store)
                        }
                        // Drag to reorder. The payload is the manifest
                        // path, so a tile dragged out of the window carries
                        // text and never a promise of a file the app would
                        // have to write.
                        .draggable(path)
                        .dropDestination(for: String.self) { dropped, _ in
                            dropTarget = nil
                            guard let moved = dropped.first else { return false }
                            state.moveMedia(moved, before: path, deviceClass: device,
                                            store: store)
                            Haptic.drop()
                            return true
                        } isTargeted: { inside in
                            // The tile itself draws the insertion line, so
                            // this only has to name which one is targeted.
                            dropTarget = inside ? path : nil
                        }
                    }
                    MediaDropTile(title: "Drop images\nor choose files",
                                  width: tile.width, height: tile.height,
                                  choose: {
                                      state.chooseMediaFiles(deviceClass: device, store: store)
                                  },
                                  accept: {
                                      state.addMediaFiles($0, deviceClass: device, store: store)
                                  })
                }
            }
        }
    }

    /// The one line that says whether the two stores share this size, and the
    /// way to change it.
    @ViewBuilder
    private func mergeControl(_ device: Manifest.DeviceClass) -> some View {
        if state.stores.count > 1 {
            let split = state.mediaIsSplit(device)
            HStack(spacing: 6) {
                Rectangle().fill(Theme.sep2).frame(width: 12, height: Theme.hairline)
                Text(split ? "Each store has its own pictures · "
                           : "Both stores get these · ")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                Button(split ? "use the same images" : "use different images") {
                    if split { state.mergeMedia(device) } else { state.splitMedia(device) }
                }
                .buttonStyle(.plain)
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
            }
        }
    }

    /// What each store shows today. It is faded and it takes no input, because
    /// nothing here is a file the developer owns yet.
    @ViewBuilder
    private func liveScreenshots(_ live: [(store: Store, urls: [URL])]) -> some View {
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(live, id: \.store) { entry in
                    LiveMediaStrip(store: entry.store, urls: entry.urls, isVideo: false)
                }
                LiveMediaWarning()
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.sep2, lineWidth: Theme.hairline))
        }
    }

    /// The two files Google asks for beside the screenshots.
    ///
    /// They are paths and not tiles, for the reason the Android artifacts are:
    /// each one is a single file with an exact size that something else
    /// produced, and a drop grid of one is a grid pretending to be a field.
    private var googleGraphics: some View {
        Section_("Google graphics", icon: "app.badge.fill", tint: Theme.playGreen,
                 anchor: "media.googleGraphics") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AppState.GoogleGraphic.allCases, id: \.self) { graphic in
                    let binding = state.googleGraphicBinding(graphic)
                    LabeledField(graphic.label, note: graphic.note) {
                        PathField(path: binding,
                                  problem: state.missingFileNote(for: binding.wrappedValue)) {
                            guard let url = state.chooseOneFile(
                                allowedExtensions: graphic.extensions) else { return }
                            binding.wrappedValue = state.relativePath(for: url)
                        }
                    }
                }
                Text("Google Play refuses a listing without both. The App Store needs neither: it reads the icon out of the build.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .storePanel()
        }
    }

    private var videoSection: some View {
        let device: Manifest.DeviceClass = .phone
        let previews = state.mediaPaths(deviceClass: device, previews: true)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Video").font(Theme.font(size: 12.5, weight: .semibold))
                .fieldAnchor("media.video")
            Text("Apple takes a 15 to 30 second video file. Google takes a YouTube URL.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StoreLabel(store: .apple, size: 11.5)
                        Text("previews").font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        Spacer()
                        Button("Choose videos…") {
                            state.chooseMediaFiles(deviceClass: device, previews: true)
                        }.controlSize(.small)
                    }
                    ForEach(previews, id: \.self) { path in
                        HStack {
                            Image(systemName: "film")
                            Text(state.mediaURL(for: path).lastPathComponent).lineLimit(1)
                            Spacer()
                            Button("Remove") {
                                state.removeMedia(path, deviceClass: device, previews: true)
                            }.controlSize(.small)
                        }.font(Theme.font(size: 11.5))
                    }
                    MediaDropTile(
                        title: "Drop .mov, .m4v, or .mp4",
                        choose: { state.chooseMediaFiles(deviceClass: device, previews: true) },
                        accept: {
                            state.addMediaFiles($0, deviceClass: device, previews: true)
                        })
                        .frame(maxWidth: .infinity)
                    let live = state.storeSnapshot.previews(locale: state.locale,
                                                            deviceClass: device)
                    if !live.isEmpty {
                        LiveMediaStrip(store: .apple, urls: live, isVideo: true)
                        LiveMediaWarning(noun: "previews")
                    }
                }
                .storePanel(padding: 14)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        StoreLabel(store: .google, size: 11.5)
                        Text("YouTube URL").font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                    }
                    TextField("https://youtube.com/watch?v=…",
                              text: state.listingBinding(.googleVideo))
                        .textFieldStyle(.roundedBorder)
                    Text("Leave blank to omit the video.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                }
                .storePanel(padding: 14)
            }
        }
    }
}

/// One store's live media, faded so it never reads as a file to edit.
private struct LiveMediaStrip: View {
    let store: Store
    let urls: [URL]
    let isVideo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                StoreMark(store: store, size: 11)
                Text("On \(store.storeName) now")
                    .font(Theme.font(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text3)
                    .textCase(.uppercase)
                    .kerning(0.3)
                Text("\(urls.count)")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        Group {
                            if isVideo {
                                Hatched()
                                    .overlay(Image(systemName: "film")
                                        .font(Theme.font(size: 20))
                                        .foregroundStyle(Theme.text3))
                            } else {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Hatched()
                                }
                            }
                        }
                        .frame(width: 84, height: 120)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 5))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .opacity(0.55)
        .allowsHitTesting(false)
        .accessibilityLabel("\(urls.count) \(isVideo ? "previews" : "screenshots") on \(store.storeName) now")
    }
}

private struct LiveMediaWarning: View {
    var noun = "screenshots"

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Theme.font(size: 10.5))
                .foregroundStyle(Theme.yellow)
            Text("These are the \(noun) the store shows today. Leave this size empty to keep them. Add images and the run replaces this whole set.")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The pixel sizes one device class takes, behind the ⓘ beside its name.
///
/// The App Store refuses a screenshot whose dimensions are not one of these,
/// and a developer who does not know that finds out from a rejected upload.
/// The list is the catalog the upload itself validates against, so the popover
/// cannot name a size the app would then turn away.
private struct SizeInfoButton: View {
    let name: String
    let deviceClass: Manifest.DeviceClass
    let stores: Set<Store>

    @State private var open = false

    var body: some View {
        let sizes = AssetInspector.appleSizeLabels(for: deviceClass)
        let googleBucket = AssetInspector.googleImageType(for: deviceClass)
        // Nothing to say about a class neither store carries.
        if !sizes.isEmpty || googleBucket != nil {
            Button { open = true } label: {
                Image(systemName: "info.circle")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.text3)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("The sizes \(name) accepts")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(name) sizes").font(Theme.font(size: 12, weight: .semibold))
                    if stores.contains(.apple), !sizes.isEmpty {
                        Text("App Store").font(Theme.font(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                        Text(sizes.joined(separator: "\n"))
                            .font(Theme.mono(11)).foregroundStyle(Theme.text)
                        Text("Portrait or landscape. Any other size is refused.")
                            .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                    if stores.contains(.google), googleBucket != nil {
                        Text("Google Play").font(Theme.font(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                        Text("320 to 3840 pixels on each side, and no side more than twice the other.")
                            .font(Theme.font(size: 11)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(13)
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
    }
}

private struct MediaTile: View {
    let path: String
    let size: CGSize
    let info: ImageAssetInfo?
    let stores: Set<Store>
    let url: URL
    var fromStore = false
    var canMoveEarlier = false
    var canMoveLater = false
    /// True while another tile is being dragged onto this one. The caller owns
    /// it, because only the caller knows which tile the pointer is over.
    var insertBefore = false
    var move: (Int) -> Void = { _ in }
    let remove: () -> Void

    /// Whether the pointer is on this tile. See the button row below, and the
    /// cursor in `hover(_:)`.
    @State private var hovering = false

    /// The pointer says the picture opens, and puts itself back afterwards.
    ///
    /// `NSCursor` is a stack, so every push owes a pop. A bare push and pop in
    /// `onHover` leaks one: pressing the trash button removes the tile while
    /// the pointer is still on it, `onHover(false)` never arrives, and the
    /// pointing hand is left on the whole app until something else pushes over
    /// it. Deleting a screenshot you are hovering is the ordinary way to
    /// delete one, so that is the common path and not the edge case.
    ///
    /// The flag is what makes the pop safe: it says whether this tile owns a
    /// push, so `onDisappear` can return the one it took and no more.
    private func hover(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Hatched() }
            }
            .frame(width: size.width, height: size.height)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                // The import downloaded this one. It says so, because a tile
                // reads as a file the developer chose and this one is the
                // store's own picture coming back.
                if fromStore {
                    Text("From the store")
                        .font(Theme.font(size: 9, weight: .medium))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.raised, in: Capsule())
                        .padding(5)
                }
            }
            Text(url.lastPathComponent).font(Theme.font(size: 10.5)).lineLimit(1)
            if let info {
                // Verbatim, so the numbers stay numbers. `Text("\(int)")` goes
                // through LocalizedStringKey, which groups by locale, and a
                // 1242 by 2208 screenshot came out as "1.242 × 2.208". No
                // locale writes a resolution with a thousands separator.
                Text(verbatim: "\(info.width) × \(info.height)")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text2)
                    .monospacedDigit()
            }
            // The logos, not the words. A tile is 112 points wide and the two
            // names are "App Store · Google Play", so the line truncated to
            // "App Store · Google Pl…" — losing the exact fact the row is
            // there to carry, on the tiles that go to both stores. Two marks
            // fit, say the same thing, and read at a glance down a grid.
            HStack(spacing: 4) {
                ForEach(stores.sorted { $0.rawValue < $1.rawValue }) { store in
                    StoreMark(store: store, size: 11)
                }
            }
            .frame(height: 13, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel(stores.sorted { $0.rawValue < $1.rawValue }
                .map(\.storeName).joined(separator: " and "))
            // The list order is the order that both stores show, so the tile
            // carries the two moves next to the removal.
            // WCAG 2.5.2 asks 24 by 24. A mini button is about 22 by 16, and
            // these are the controls that reorder what both stores show.
            //
            // They fade in under the pointer. Ten tiles drew thirty buttons at
            // all times, which is a wall of chrome across a tab that is meant
            // to be read as pictures.
            //
            // `.opacity` and not an `if`. Removing them from the hierarchy
            // would resize every tile as the pointer crossed it, take them out
            // of the keyboard order, and hide them from VoiceOver, and the
            // report is firm that hover may never be the only route. They stay
            // present, focusable and spoken; only the ink comes and goes. The
            // context menu below is the third route.
            HStack(spacing: 4) {
                TileButton(symbol: "arrow.left", label: "Move earlier",
                           enabled: canMoveEarlier) { move(-1) }
                TileButton(symbol: "arrow.right", label: "Move later",
                           enabled: canMoveLater) { move(1) }
                TileButton(symbol: "trash", label: "Remove", enabled: true,
                           tint: Theme.red, action: remove)
            }
            .opacity(hovering ? 1 : 0)
        }
        .frame(width: size.width, alignment: .leading)
        .onHover(perform: hover)
        .onDisappear {
            // The tile can be removed while the pointer is on it. See `hover`.
            if hovering { NSCursor.pop(); hovering = false }
        }
        .motion(.easeOut(duration: 0.12), value: hovering)
        // Quick Look, the way Finder does it. The tab holds real image files
        // and a developer checking one used to open Finder to find it.
        .onTapGesture(count: 2) { QuickLook.show(url) }
        // Every hover action, plus the preview, on a route that needs no
        // pointer skill and no hover at all.
        .contextMenu {
            Button("Quick Look") { QuickLook.show(url) }
            Divider()
            Button("Move Earlier") { move(-1) }.disabled(!canMoveEarlier)
            Button("Move Later") { move(1) }.disabled(!canMoveLater)
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Remove", role: .destructive, action: remove)
        }
        // Where a dragged tile would land. The order of these tiles is the
        // order both stores put on the listing page, so "before this one" is
        // the whole point of the drag and it was invisible until it finished.
        .overlay(alignment: .leading) {
            if insertBefore {
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 3)
                    .offset(x: -6.5)
            }
        }
        .motion(.snappy(duration: 0.15), value: insertBefore)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityHint("Double click to preview")
    }
}

/// One square control under a tile, at the size a pointer can actually hit.
///
/// The three used to be mini push buttons about 22 by 16 points, which is
/// under the 24 by 24 that WCAG 2.5.2 asks and under what a trackpad hits
/// first time.
private struct TileButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    var tint: Color = Theme.text2
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.font(size: 11, weight: .medium))
                .foregroundStyle(enabled ? tint : Theme.text3)
                .frame(width: 24, height: 24)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.controlEdge, lineWidth: Theme.hairline))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// The dashed target at the end of a row of screenshots.
///
/// It owns its drop rather than leaving the caller to attach one, which is how
/// `FileWell` and `PackageDropWell` already work. Both callers used to hang a
/// `.dropDestination` on the outside, so the tile could not know it was being
/// dragged onto and the one target on the tab whose whole purpose is to accept
/// a drop was the only one that never lit up.
private struct MediaDropTile: View {
    let title: String
    /// Nil lets the caller size it, which the video section does.
    var width: CGFloat?
    var height: CGFloat = 82
    let choose: () -> Void
    let accept: ([URL]) -> Void

    @State private var targeted = false

    var body: some View {
        Button(action: choose) {
            Text(title)
                .font(Theme.font(size: 11))
                .foregroundStyle(targeted ? Theme.accent : Theme.text3)
                .multilineTextAlignment(.center).padding(8)
                .frame(maxWidth: .infinity).frame(height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .background(targeted ? Theme.accent.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(targeted ? Theme.accent : Theme.controlEdge,
                          style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [3, 3])))
        .motion(.easeOut(duration: 0.12), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            accept(urls)
            Haptic.drop()
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// Shared with onboarding for decorative artwork.
struct Hatched: View {
    var cornerRadius: CGFloat = 6
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sunken))
            var stripes = Path()
            var x = -size.height
            while x < size.width + size.height {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 12
            }
            context.stroke(stripes, with: .color(Theme.sep2), lineWidth: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

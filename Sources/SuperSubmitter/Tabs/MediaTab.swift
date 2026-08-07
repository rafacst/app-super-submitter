import AppKit
import SubmitKit
import SwiftUI

/// Tab 4. Files are validated before their relative paths are written to the manifest.
struct MediaTab: View {
    @Environment(AppState.self) private var state

    private var groups: [(String, Manifest.DeviceClass)] {
        var values: [(String, Manifest.DeviceClass)] = [("Phone", .phone)]
        if state.stores.contains(.google) { values.append(("Small tablet", .tablet7)) }
        values.append(("Large tablet", .tablet10))
        if state.stores.contains(.apple) { values.append(("Desktop", .desktop)) }
        values.append(contentsOf: [("Watch", .watch), ("TV", .tv)])
        if state.stores.contains(.apple) { values.append(("Vision", .vision)) }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Publishing sends this tab through the Summary tab, which
            // plans and then writes. Managing has none, so it writes here.
            if state.mode == .managing { DirectApplyBar(target: .media) }
            if let error = state.mediaError { WarningNote(error) }
            ForEach(groups, id: \.1) { name, device in
                mediaGroup(name, device: device)
            }
            videoSection
        }
    }

    private func mediaGroup(_ name: String, device: Manifest.DeviceClass) -> some View {
        let paths = state.mediaPaths(deviceClass: device)
        let limit = state.stores.contains(.google) ? 8 : 10
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(name).font(.system(size: 12.5, weight: .semibold))
                Text("\(paths.count) of \(limit)").font(.system(size: 11)).foregroundStyle(Theme.text2)
                Spacer()
                Button("Choose images…") { state.chooseMediaFiles(deviceClass: device) }
                    .controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                        MediaTile(path: path, info: state.imageInfo(for: path),
                                  stores: state.imageStores(for: path, deviceClass: device),
                                  url: state.mediaURL(for: path),
                                  fromStore: AppState.isImported(path),
                                  canMoveEarlier: index > 0,
                                  canMoveLater: index < paths.count - 1,
                                  move: { offset in
                                      state.moveMedia(path, by: offset, deviceClass: device)
                                  }) {
                            state.removeMedia(path, deviceClass: device)
                        }
                        // Drag to reorder. The payload is the manifest path, so
                        // a tile dragged out of the window carries text and
                        // never a promise of a file the app would have to write.
                        .draggable(path)
                        .dropDestination(for: String.self) { dropped, _ in
                            guard let moved = dropped.first else { return false }
                            state.moveMedia(moved, before: path, deviceClass: device)
                            return true
                        }
                    }
                    MediaDropTile(title: "Drop images\nor choose files") {
                        state.chooseMediaFiles(deviceClass: device)
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        state.addMediaFiles(urls, deviceClass: device)
                        return true
                    }
                }
            }
            liveScreenshots(device)
        }
    }

    /// What each store shows today. It is faded and it takes no input, because
    /// nothing here is a file the developer owns yet.
    ///
    /// An import already downloaded these same images into the tiles above,
    /// so the strip stays out of the way when the bucket holds them. The
    /// alternative was every screenshot drawn twice on one row.
    @ViewBuilder
    private func liveScreenshots(_ device: Manifest.DeviceClass) -> some View {
        let imported = state.mediaPaths(deviceClass: device).contains(where: AppState.isImported)
        let live = imported
            ? []
            : state.storeSnapshot.screenshots(locale: state.locale, deviceClass: device)
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

    private var videoSection: some View {
        let device: Manifest.DeviceClass = .phone
        let previews = state.mediaPaths(deviceClass: device, previews: true)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Video").font(.system(size: 12.5, weight: .semibold))
            Text("Apple takes a 15 to 30 second video file. Google takes a YouTube URL.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StoreLabel(store: .apple, size: 11.5)
                        Text("previews").font(.system(size: 11.5)).foregroundStyle(Theme.text2)
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
                        }.font(.system(size: 11.5))
                    }
                    MediaDropTile(title: "Drop .mov, .m4v, or .mp4") {
                        state.chooseMediaFiles(deviceClass: device, previews: true)
                    }
                    .frame(maxWidth: .infinity)
                    .dropDestination(for: URL.self) { urls, _ in
                        state.addMediaFiles(urls, deviceClass: device, previews: true)
                        return true
                    }
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
                        Text("YouTube URL").font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    }
                    TextField("https://youtube.com/watch?v=…",
                              text: state.listingBinding(.googleVideo))
                        .textFieldStyle(.roundedBorder)
                    Text("Leave blank to omit the video.")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
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
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text3)
                    .textCase(.uppercase)
                    .kerning(0.3)
                Text("\(urls.count)")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        Group {
                            if isVideo {
                                Hatched()
                                    .overlay(Image(systemName: "film")
                                        .font(.system(size: 20))
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
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.yellow)
            Text("These are the current \(noun). If you upload new ones they will be replaced.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MediaTile: View {
    let path: String
    let info: ImageAssetInfo?
    let stores: Set<Store>
    let url: URL
    var fromStore = false
    var canMoveEarlier = false
    var canMoveLater = false
    var move: (Int) -> Void = { _ in }
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Hatched() }
            }
            .frame(width: 112, height: 160)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                // The import downloaded this one. It says so, because a tile
                // reads as a file the developer chose and this one is the
                // store's own picture coming back.
                if fromStore {
                    Text("From the store")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.raised, in: Capsule())
                        .padding(5)
                }
            }
            Text(url.lastPathComponent).font(.system(size: 10.5)).lineLimit(1)
            if let info {
                // Verbatim, so the numbers stay numbers. `Text("\(int)")` goes
                // through LocalizedStringKey, which groups by locale, and a
                // 1242 by 2208 screenshot came out as "1.242 × 2.208". No
                // locale writes a resolution with a thousands separator.
                Text(verbatim: "\(info.width) × \(info.height)")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text2)
                    .monospacedDigit()
            }
            Text(stores.sorted { $0.rawValue < $1.rawValue }.map {
                $0 == .apple ? "App Store" : "Google Play"
            }.joined(separator: " · "))
                .font(.system(size: 10)).foregroundStyle(Theme.text3).lineLimit(1)
            // The list order is the order that both stores show, so the tile
            // carries the two moves next to the removal.
            // WCAG 2.5.2 asks 24 by 24. A mini button is about 22 by 16, and
            // these are the controls that reorder what both stores show.
            HStack(spacing: 4) {
                TileButton(symbol: "arrow.left", label: "Move earlier",
                           enabled: canMoveEarlier) { move(-1) }
                TileButton(symbol: "arrow.right", label: "Move later",
                           enabled: canMoveLater) { move(1) }
                TileButton(symbol: "trash", label: "Remove", enabled: true,
                           tint: Theme.red, action: remove)
            }
        }.frame(width: 112, alignment: .leading)
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
                .font(.system(size: 11, weight: .medium))
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

private struct MediaDropTile: View {
    let title: String
    let choose: () -> Void
    var body: some View {
        Button(action: choose) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center).padding(8)
                .frame(width: 112).frame(minHeight: 82)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.controlEdge, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
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

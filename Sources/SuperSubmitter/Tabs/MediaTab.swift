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
            if let error = state.mediaError {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.red)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.redBg, in: RoundedRectangle(cornerRadius: 7))
            }
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
                                  canMoveEarlier: index > 0,
                                  canMoveLater: index < paths.count - 1,
                                  move: { offset in
                                      state.moveMedia(path, by: offset, deviceClass: device)
                                  }) {
                            state.removeMedia(path, deviceClass: device)
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
    @ViewBuilder
    private func liveScreenshots(_ device: Manifest.DeviceClass) -> some View {
        let live = state.storeSnapshot.screenshots(locale: state.locale, deviceClass: device)
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
                .mediaPanel()

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
                .mediaPanel()
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
            Text(url.lastPathComponent).font(.system(size: 10.5)).lineLimit(1)
            if let info {
                Text("\(info.width) × \(info.height)")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text2)
            }
            Text(stores.sorted { $0.rawValue < $1.rawValue }.map {
                $0 == .apple ? "App Store" : "Google Play"
            }.joined(separator: " · "))
                .font(.system(size: 10)).foregroundStyle(Theme.text3).lineLimit(1)
            // The list order is the order that both stores show, so the tile
            // carries the two moves next to the removal.
            HStack(spacing: 4) {
                Button("←") { move(-1) }
                    .controlSize(.mini)
                    .disabled(!canMoveEarlier)
                    .accessibilityLabel("Move earlier")
                Button("→") { move(1) }
                    .controlSize(.mini)
                    .disabled(!canMoveLater)
                    .accessibilityLabel("Move later")
                Button("Remove", action: remove).controlSize(.mini)
            }
        }.frame(width: 112, alignment: .leading)
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
            .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

private extension View {
    func mediaPanel() -> some View {
        padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
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

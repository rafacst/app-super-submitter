import SwiftUI

/// Tab 4. The screenshots and the videos.
///
/// The app reads the dimensions on the drop, before any upload. Every tile
/// names the bucket it landed in and the stores that receive it.
struct MediaTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(DemoData.mediaGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(group.name).font(.system(size: 12.5, weight: .semibold))
                        Text(group.count).font(.system(size: 11)).foregroundStyle(Theme.text2)
                        Text(group.note).font(.system(size: 11)).foregroundStyle(Theme.text3)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Array(group.shots.enumerated()), id: \.offset) { _, shot in
                                ShotTile(shot: shot)
                            }
                            DropTile(size: group.dropSize)
                        }
                    }
                }
            }

            videoSection
        }
    }

    /// The one rule on this tab that surprises a developer, stated in a line.
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Video").font(.system(size: 12.5, weight: .semibold))
            Text("Apple takes a video file. Google takes a YouTube link and no file.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)

            HStack(alignment: .top, spacing: 14) {
                // A drop target, because Apple takes a file.
                VStack(alignment: .leading, spacing: 6) {
                    Text("App Store · app preview").font(.system(size: 11.5, weight: .semibold))
                    Text("Drop a .mov, .m4v, or .mp4. 15 to 30 seconds. At most 3 per device size.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) {
                        Hatched(cornerRadius: 3).frame(width: 38, height: 24)
                        Text("preview-6.7-en.mov").font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("22s").font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))

                // A plain field, because Google takes no file. The two must
                // not look alike, because they are not alike.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Google Play · YouTube URL").font(.system(size: 11.5, weight: .semibold))
                    Text("Google accepts no video file. A link, or nothing.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("https://youtube.com/watch?v=7Qm2xKp")
                        .font(Theme.mono(12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
            }
            .frame(maxWidth: 820)
        }
    }
}

private struct ShotTile: View {
    let shot: DemoShot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Hatched(cornerRadius: 6)
                .frame(width: shot.size.width, height: shot.size.height)
            Text(shot.bucket)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Text(shot.stores)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: shot.size.width, alignment: .leading)
    }
}

private struct DropTile: View {
    let size: CGSize

    var body: some View {
        VStack(spacing: 2) {
            Text("Drop images")
            Text("or choose files")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.text3)
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(width: size.width, height: size.height)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// The diagonal hatch that stands in for an image that is not loaded.
struct Hatched: View {
    var cornerRadius: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.sunken))
            var stripes = Path()
            let step: CGFloat = 12
            var x = -size.height
            while x < size.width + size.height {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(stripes, with: .color(Theme.sep2), lineWidth: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

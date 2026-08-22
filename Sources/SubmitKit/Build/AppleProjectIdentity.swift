import Foundation

/// What an Xcode project says it builds, read from the project file itself.
///
/// The same trade `AndroidBuildService.identity` makes, for the same reason:
/// the alternative is `xcodebuild -showBuildSettings`, which needs a scheme, a
/// toolchain and several seconds of process time to fill three fields on an
/// app that has not been linked yet. This reads one file and runs nothing.
///
/// A value the project computes is simply absent. `$(PRODUCT_NAME)` and every
/// other substitution is dropped rather than guessed, because a bundle
/// identifier that is wrong is worse than a bundle identifier that is empty:
/// the store refuses the upload either way, and only the empty one is obviously
/// the developer's to fill.
public struct AppleProjectIdentity: Sendable, Equatable {
    public var bundleIdentifier: String?
    public var marketingVersion: String?
    public var displayName: String?

    public init(bundleIdentifier: String? = nil, marketingVersion: String? = nil,
                displayName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.marketingVersion = marketingVersion
        self.displayName = displayName
    }

    public var isEmpty: Bool {
        bundleIdentifier == nil && marketingVersion == nil && displayName == nil
    }

    /// Reads the `project.pbxproj` that belongs to a discovered container.
    ///
    /// A workspace holds no build settings of its own, so it answers through
    /// the project beside it. A workspace with several projects answers with
    /// none: picking one of them is a guess, and the Build tab asks that
    /// question properly once a scheme is chosen.
    public static func read(container: URL) -> AppleProjectIdentity {
        guard let project = projectFile(for: container),
              let text = try? String(contentsOf: project, encoding: .utf8) else {
            return AppleProjectIdentity()
        }
        return parse(text)
    }

    static func projectFile(for container: URL) -> URL? {
        let file = { (project: URL) in project.appendingPathComponent("project.pbxproj") }
        if container.pathExtension == "xcodeproj" { return file(container) }
        guard container.pathExtension == "xcworkspace" else { return nil }
        let folder = container.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "xcodeproj" } ?? []
        // The project of the same name first: a workspace beside its own
        // project is the ordinary shape, and CocoaPods puts a second one
        // there under the Pods name.
        if let matching = siblings.first(where: {
            $0.deletingPathExtension().lastPathComponent
                == container.deletingPathExtension().lastPathComponent
        }) {
            return file(matching)
        }
        return siblings.count == 1 ? file(siblings[0]) : nil
    }

    static func parse(_ text: String) -> AppleProjectIdentity {
        var result = AppleProjectIdentity()
        result.bundleIdentifier = pick(values(of: "PRODUCT_BUNDLE_IDENTIFIER", in: text)
            // A test bundle and an extension carry their own identifier under
            // the app's. Every one of them is a suffix of the app's own, so
            // the app is what is left once the known suffixes are dropped.
            .filter { !isCompanion($0) })
        result.marketingVersion = pick(values(of: "MARKETING_VERSION", in: text))
        result.displayName = pick(values(of: "INFOPLIST_KEY_CFBundleDisplayName", in: text))
        return result
    }

    /// The value a settings line holds, for every target that names it.
    ///
    /// `KEY = value;` is the whole grammar of the settings block, and the
    /// value may be quoted. A line whose value carries a substitution is
    /// dropped here rather than downstream.
    static func values(of key: String, in text: String) -> [String] {
        var found: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) = "), trimmed.hasSuffix(";") else { continue }
            var value = String(trimmed.dropFirst(key.count + 3).dropLast())
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count > 1 {
                value = String(value.dropFirst().dropLast())
            }
            guard !value.isEmpty, !value.contains("$(") , !value.contains("${") else { continue }
            found.append(value)
        }
        return found
    }

    /// The value the project states most often, and the shortest of those.
    ///
    /// A project file holds one line per target per configuration, so the app
    /// itself is named twice or more while a one-off override is named once.
    /// Shortest breaks a tie because a companion identifier is the app's own
    /// with something added to it.
    static func pick(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        let counts = values.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.keys.sorted { left, right in
            let (a, b) = (counts[left] ?? 0, counts[right] ?? 0)
            if a != b { return a > b }
            if left.count != right.count { return left.count < right.count }
            return left < right
        }.first
    }

    static func isCompanion(_ identifier: String) -> Bool {
        let last = identifier.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        return ["tests", "uitests", "testing", "widget", "widgets", "extension",
                "watchkitapp", "watchkitextension", "clip", "notificationservice",
                "shareextension", "intents", "intentsui"].contains(last)
            || last.hasSuffix("tests")
    }
}

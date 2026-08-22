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
    /// `ITSAppUsesNonExemptEncryption`, as the project states it.
    ///
    /// Apple takes this answer from inside the binary and changes it for
    /// nobody, so a project that states it has already decided. Nil when the
    /// project says nothing, and nil is the developer's question to answer.
    public var usesNonExemptEncryption: Bool?

    public init(bundleIdentifier: String? = nil, marketingVersion: String? = nil,
                displayName: String? = nil, usesNonExemptEncryption: Bool? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.marketingVersion = marketingVersion
        self.displayName = displayName
        self.usesNonExemptEncryption = usesNonExemptEncryption
    }

    public var isEmpty: Bool {
        bundleIdentifier == nil && marketingVersion == nil && displayName == nil
            && usesNonExemptEncryption == nil
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
        var result = parse(text)
        // The `Info.plist` beside the project, for the one key the settings
        // block does not carry when the project ships a file of its own.
        // `SRCROOT` is the folder that holds the `.xcodeproj`, and
        // `INFOPLIST_FILE` is written relative to it.
        if result.usesNonExemptEncryption == nil {
            let root = project.deletingLastPathComponent().deletingLastPathComponent()
            result.usesNonExemptEncryption = infoPlistEncryption(in: text, root: root)
        }
        return result
    }

    /// `ITSAppUsesNonExemptEncryption` out of the `Info.plist` the project
    /// names.
    ///
    /// A project that generates its plist states the answer as
    /// `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` and never reaches here.
    /// One that ships a file names it in `INFOPLIST_FILE`, and that file is
    /// the only place the answer exists.
    ///
    /// A project with several targets names several files, and `pick` takes
    /// the one stated most often, which is the app rather than a test bundle.
    static func infoPlistEncryption(in text: String, root: URL) -> Bool? {
        guard let named = pick(values(of: "INFOPLIST_FILE", in: text)) else { return nil }
        let url = URL(fileURLWithPath: named, relativeTo: root)
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["ITSAppUsesNonExemptEncryption"] as? Bool
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
        // The generated-plist form. Xcode writes the plist keys into the
        // settings block, so a project made since Xcode 13 states this here
        // and has no `Info.plist` file at all.
        result.usesNonExemptEncryption = pick(
            values(of: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption", in: text))
            .flatMap(boolean(from:))
        return result
    }

    /// A build setting as a yes or no. Xcode writes `YES` and `NO`; a plist
    /// key copied into the settings block may read `true` or `false`.
    /// Anything else is not an answer and stays nil.
    static func boolean(from value: String) -> Bool? {
        switch value.lowercased() {
        case "yes", "true", "1": true
        case "no", "false", "0": false
        default: nil
        }
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

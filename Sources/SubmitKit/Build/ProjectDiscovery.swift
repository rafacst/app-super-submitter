import Foundation

/// What a scan of one selected folder found. upload-spec section 7.3.
///
/// Discovery returns candidates. It never authorizes a build.
public struct DiscoveryResult: Sendable, Equatable {
    public var containers: [Container] = []
    /// True when the bounded walk stopped before it saw everything, so the
    /// screen can say the list may be incomplete.
    public var truncated = false
    public var notes: [String] = []

    public init() {}

    public struct Container: Sendable, Equatable, Identifiable {
        public var path: String
        public var kind: LinkedSourceProject.ContainerKind
        public var platform: BuildPlatform?
        /// Why this container can, or cannot, produce a distributable.
        public var reasons: [String] = []
        public var isBuildable = true
        public var id: String { path }

        public init(path: String, kind: LinkedSourceProject.ContainerKind,
                    platform: BuildPlatform? = nil, reasons: [String] = [],
                    isBuildable: Bool = true) {
            self.path = path
            self.kind = kind
            self.platform = platform
            self.reasons = reasons
            self.isBuildable = isBuildable
        }

        public var url: URL { URL(fileURLWithPath: path) }
        public var name: String { url.lastPathComponent }
    }
}

/// A bounded walk of one selected folder. upload-spec section 7.2.
///
/// `// ponytail: one enumerator with a depth cap and a resolved-path check.
/// // No index, no watcher, no background crawl of the home directory.`
public enum ProjectDiscovery {
    /// Generated output, dependency checkouts, and IDE caches. Walking them
    /// finds nothing and costs minutes on a large repository.
    static let skipped: Set<String> = [
        ".git", ".build", ".swiftpm", "build", "DerivedData", "node_modules",
        ".gradle", ".idea", ".venv", "Carthage", "Pods", "vendor", ".cache",
        "__pycache__", ".tuist", ".ccache",
    ]

    static let maxDepth = 6
    static let maxEntries = 20_000

    public static func scan(root: URL) -> DiscoveryResult {
        var result = DiscoveryResult()
        let manager = FileManager.default
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        var entries = 0

        guard let walker = manager.enumerator(
            at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            result.notes.append("The folder could not be read.")
            return result
        }

        while let url = walker.nextObject() as? URL {
            entries += 1
            if entries > maxEntries {
                result.truncated = true
                break
            }
            if walker.level > maxDepth {
                walker.skipDescendants()
                result.truncated = true
                continue
            }
            let name = url.lastPathComponent
            if skipped.contains(name) {
                walker.skipDescendants()
                continue
            }
            // A symlink whose target leaves the selected folder is not part of
            // this project. upload-spec section 3.6.
            if escapesRoot(url, root: base) {
                walker.skipDescendants()
                continue
            }

            switch url.pathExtension {
            case "xcworkspace":
                // Xcode's own workspace inside a project is not a container
                // the developer chose. upload-spec section 8.2.
                guard url.deletingLastPathComponent().pathExtension != "xcodeproj" else {
                    walker.skipDescendants()
                    continue
                }
                result.containers.append(.init(path: url.path, kind: .workspace))
                walker.skipDescendants()
            case "xcodeproj":
                result.containers.append(.init(path: url.path, kind: .project))
                walker.skipDescendants()
            default:
                if name == "gradlew" {
                    let folder = url.deletingLastPathComponent()
                    var container = DiscoveryResult.Container(
                        path: folder.path, kind: .gradle, platform: .android)
                    let hasSettings = ["settings.gradle", "settings.gradle.kts"].contains {
                        manager.fileExists(atPath: folder.appendingPathComponent($0).path)
                    }
                    if !hasSettings {
                        container.reasons.append(
                            "No settings.gradle or settings.gradle.kts sits next to gradlew.")
                        container.isBuildable = false
                    }
                    if !manager.isExecutableFile(atPath: url.path) {
                        container.reasons.append(
                            "gradlew is not executable. Run chmod +x gradlew in the project.")
                        container.isBuildable = false
                    }
                    result.containers.append(container)
                }
            }
        }

        result.containers.sort { left, right in
            left.path.components(separatedBy: "/").count
                == right.path.components(separatedBy: "/").count
                ? left.path < right.path
                : left.path.components(separatedBy: "/").count
                    < right.path.components(separatedBy: "/").count
        }
        if result.containers.isEmpty {
            result.notes.append(
                "No Xcode workspace, Xcode project, or Gradle wrapper was found in this folder.")
        }
        if result.truncated {
            result.notes.append(
                "The scan stopped at its depth or entry limit, so this list may be incomplete.")
        }
        return result
    }

    /// True when the entry is a symlink whose resolved path leaves the root.
    static func escapesRoot(_ url: URL, root: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink == true else { return false }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let baseComponents = root.standardizedFileURL.pathComponents
        let targetComponents = resolved.pathComponents
        guard targetComponents.count >= baseComponents.count else { return true }
        return !targetComponents.starts(with: baseComponents)
    }

    /// The workspace that a container list recommends, or nil when the choice
    /// is ambiguous. A workspace never wins silently against a second one.
    public static func recommended(_ containers: [DiscoveryResult.Container])
        -> DiscoveryResult.Container? {
        let buildable = containers.filter(\.isBuildable)
        let workspaces = buildable.filter { $0.kind == .workspace }
        if workspaces.count == 1, buildable.filter({ $0.kind == .gradle }).isEmpty {
            return workspaces[0]
        }
        if workspaces.isEmpty, buildable.count == 1 { return buildable[0] }
        return nil
    }

    /// The git revision of the folder, when it is a repository. Informational.
    public static func revision(at root: URL,
                                runner: any CommandRunning = ProcessRunner())
        -> BuildCandidate.SourceRevision? {
        guard let head = try? runner.run("/usr/bin/git",
                                         ["-C", root.path, "rev-parse", "HEAD"]),
              head.status == 0, let commit = head.lines.first else { return nil }
        let branch = try? runner.run("/usr/bin/git",
                                     ["-C", root.path, "rev-parse", "--abbrev-ref", "HEAD"])
        let status = try? runner.run("/usr/bin/git", ["-C", root.path, "status", "--porcelain"])
        return BuildCandidate.SourceRevision(
            commit: commit,
            branch: branch?.status == 0 ? branch?.lines.first : nil,
            isDirty: !(status?.lines.isEmpty ?? true))
    }
}

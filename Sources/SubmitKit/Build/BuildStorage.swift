import Foundation

/// The app-owned directories. upload-spec section 11.
///
/// Nothing here ever writes inside the developer's repository, and nothing
/// here ever deletes a file inside it.
public struct BuildStorage: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Super Submitter", isDirectory: true)
    }

    public var projects: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    /// Where a managed app keeps its `store.yaml`.
    ///
    /// Publishing puts the file beside the source, because the developer keeps
    /// it in their repository. Managing has no repository to sit beside: the
    /// app is already built and already out there, so the workspace belongs to
    /// Super Submitter and the user is never asked for a folder.
    public var managed: URL { root.appendingPathComponent("Managed", isDirectory: true) }

    /// `Managed/<name>-<identifier>/`, made if it is not there yet.
    ///
    /// The identifier keeps two apps with the same display name apart, which a
    /// name alone cannot do.
    public func managedFolder(name: String, identifier: String) throws -> URL {
        let folder = managed.appendingPathComponent(
            "\(Self.safe(name))-\(Self.safe(identifier))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    /// Where the local drafts go: one file per press of Save a draft, holding
    /// the list of linked apps and the text of every `store.yaml` in it.
    ///
    /// Outside the app bundle on purpose. A draft exists for the update that
    /// replaces the bundle, and anything kept inside it goes with it.
    public var drafts: URL { root.appendingPathComponent("Drafts", isDirectory: true) }
    public var archives: URL { root.appendingPathComponent("Archives", isDirectory: true) }
    public var artifacts: URL { root.appendingPathComponent("Artifacts", isDirectory: true) }
    public var runs: URL { root.appendingPathComponent("Runs", isDirectory: true) }
    public var scratch: URL { root.appendingPathComponent("Scratch", isDirectory: true) }

    /// `Archives/<bundle-id>/<UTC timestamp>-<run-id>.xcarchive`.
    ///
    /// Never a shared predictable temporary name: two runs of the same app
    /// must not collide, and a retained archive must survive the next run.
    public func archiveURL(bundleID: String, runID: UUID, date: Date = Date()) throws -> URL {
        let folder = archives.appendingPathComponent(Self.safe(bundleID), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(
            "\(Self.stamp(date))-\(runID.uuidString.prefix(8)).xcarchive")
    }

    public func exportURL(runID: UUID) throws -> URL {
        let folder = runFolder(runID).appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public func runFolder(_ runID: UUID) -> URL {
        runs.appendingPathComponent(runID.uuidString, isDirectory: true)
    }

    /// A `0700` directory for the short-lived `.p8` and the export options.
    /// The caller removes it unconditionally.
    public func makeScratch(runID: UUID) throws -> URL {
        let folder = scratch.appendingPathComponent(runID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return folder
    }

    /// Writes a secret to a `0600` file inside the scratch directory.
    public func writeSecret(_ text: String, named name: String, runID: UUID) throws -> URL {
        let folder = try makeScratch(runID: runID)
        let file = folder.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: file.path)
        return file
    }

    /// Unconditional cleanup. It runs on success, on error, and on a cancel.
    public func removeScratch(runID: UUID) {
        try? FileManager.default.removeItem(
            at: scratch.appendingPathComponent(runID.uuidString, isDirectory: true))
    }

    // MARK: - The linked projects

    /// One record that decodes, or nothing in its place.
    ///
    /// `[LinkedSourceProject]` decodes all or nothing: one entry this build
    /// cannot read threw, the decode returned nil, and `loadProjects` answered
    /// the empty list. Every app then looked unlinked, and the next link wrote
    /// that empty list back over the file, so the loss became permanent. A
    /// record written by a newer build, or by an older one before a field
    /// existed, is enough to do it.
    private struct Tolerant: Decodable {
        let project: LinkedSourceProject?

        init(from decoder: any Decoder) throws {
            project = try? LinkedSourceProject(from: decoder)
        }
    }

    /// Every linked project this build can read.
    ///
    /// A record it cannot read is skipped and the rest still load. The file
    /// itself being unreadable or not an array is still the empty list: there
    /// is nothing to salvage from that and no link to lose.
    public func loadProjects() -> [LinkedSourceProject] {
        let file = projects.appendingPathComponent("projects.json")
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([Tolerant].self, from: data)
        else { return [] }
        return list.compactMap(\.project)
    }

    public func saveProjects(_ list: [LinkedSourceProject]) throws {
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(list)
        try data.write(to: projects.appendingPathComponent("projects.json"), options: .atomic)
    }

    // MARK: - The runs

    public func save(_ run: UploadRun) throws {
        let folder = runFolder(run.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(run)
        try data.write(to: folder.appendingPathComponent("run.json"), options: .atomic)
    }

    /// The runs that a relaunch must resume: an upload or a poll that outlived
    /// the app process, or a cleanup that never confirmed.
    public func unfinishedRuns() -> [UploadRun] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: runs, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("run.json")),
                  let run = try? JSONDecoder().decode(UploadRun.self, from: data) else {
                return nil
            }
            let unfinished = run.state == .processingOrValidating
                || run.state == .recoveryRequired
                || run.cleanupState == .pending || run.cleanupState == .needsAttention
            return unfinished ? run : nil
        }.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Retention

    /// Removes completed run and scratch folders older than the age, and
    /// reports what it removed. It keeps resumable work and never touches the
    /// selected source repository or retained archives.
    @discardableResult
    public func prune(olderThan age: TimeInterval, now: Date = Date()) -> [URL] {
        var removed: [URL] = []
        let unfinishedIDs = Set(unfinishedRuns().map { $0.id.uuidString })
        for base in [runs, scratch] {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for folder in folders {
                guard !unfinishedIDs.contains(folder.lastPathComponent) else { continue }
                let date = (try? folder.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? now
                guard now.timeIntervalSince(date) > age else { continue }
                try? FileManager.default.removeItem(at: folder)
                removed.append(folder)
            }
        }
        return removed
    }

    /// The retained archives, newest first, for the retention screen.
    public func retainedArchives() -> [URL] {
        let apps = (try? FileManager.default.contentsOfDirectory(
            at: archives, includingPropertiesForKeys: nil)) ?? []
        return apps.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        }.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
    }

    // MARK: - Removing what this app made

    /// Why a deletion was refused.
    public enum Refusal: Error, Equatable {
        /// The path is outside the app's own folders. The file is the
        /// developer's, so this app does not delete it.
        case notThisApp
    }

    /// Whether a path is inside the app's own folders.
    ///
    /// The one question that decides whether this app may delete a file, and
    /// the platform does not answer it. An Apple archive is written into
    /// `Archives/`, so it is ours. Gradle writes the `.aab` under
    /// `build/outputs/bundle/` inside the developer's project, and **Choose
    /// Built AAB** takes any file on the disk. Deleting either would break the
    /// promise at the top of this file.
    ///
    /// Compared by path component and not by string prefix. A neighbouring
    /// folder named "Super Submitter Backup" carries the root's whole path as
    /// its own first characters, and a `hasPrefix` check would hand it to
    /// `removeItem`.
    public func owns(_ url: URL) -> Bool {
        let ours = Self.parts(root)
        let theirs = Self.parts(url)
        return theirs.count > ours.count && Array(theirs.prefix(ours.count)) == ours
    }

    /// Removes one artifact this app made, and refuses everything else.
    public func removeArtifact(at url: URL) throws {
        guard owns(url) else { throw Refusal.notThisApp }
        try FileManager.default.removeItem(at: url)
    }

    /// Every retained archive, removed, and reported back.
    ///
    /// Separate from `prune`, which keeps these on purpose: an archive is the
    /// one thing in here a developer may still want after a run is over. This
    /// is the answer to that, so it is never automatic and never on a timer.
    @discardableResult
    public func removeRetainedArchives() -> [URL] {
        var removed: [URL] = []
        for archive in retainedArchives() {
            guard (try? removeArtifact(at: archive)) != nil else { continue }
            removed.append(archive)
        }
        return removed
    }

    /// A path in the form the ownership check compares. Symlinks resolved, so
    /// `/tmp` and `/private/tmp` are one answer and not two.
    private static func parts(_ url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }

    static func safe(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars)
        return result.isEmpty || result == "." || result == ".." ? "unknown" : result
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

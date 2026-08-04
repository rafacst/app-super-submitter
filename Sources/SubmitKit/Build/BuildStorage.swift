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

    public func loadProjects() -> [LinkedSourceProject] {
        let file = projects.appendingPathComponent("projects.json")
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([LinkedSourceProject].self, from: data)
        else { return [] }
        return list
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

    /// One redacted JSONL line per streamed output line.
    public func logURL(runID: UUID) throws -> URL {
        let folder = runFolder(runID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("build.jsonl")
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

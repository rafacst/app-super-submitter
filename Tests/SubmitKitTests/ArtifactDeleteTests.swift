import Foundation
import Testing
@testable import SubmitKit

/// Deleting an artifact, and the one file it must never delete.
///
/// The bug this guards: `artifactPath` does not always name a file this app
/// made. An Apple archive is written into `Archives/`, but Gradle writes the
/// `.aab` under `build/outputs/bundle/` inside the developer's project, and
/// **Choose Built AAB** takes any file on the disk. A delete that trusted the
/// path would remove the developer's own build output, which is the promise
/// `BuildStorage` makes in its first three lines.
struct ArtifactDeleteTests {

    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ss-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("build".utf8).write(to: url)
        return url
    }

    @Test func anArchiveThisAppWroteIsRemoved() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root)
        let archive = try write(storage.archiveURL(bundleID: "com.example.app", runID: UUID()))

        #expect(storage.owns(archive))
        try storage.removeArtifact(at: archive)

        #expect(!FileManager.default.fileExists(atPath: archive.path))
    }

    /// The one it must never do. Gradle's output is the developer's file, in
    /// the developer's folder, and it is what `artifactPath` holds for every
    /// Android build.
    @Test func aBundleInsideTheDevelopersProjectIsRefused() throws {
        let root = try folder()
        let project = try folder()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: project)
        }
        let storage = BuildStorage(root: root)
        let bundle = try write(project.appendingPathComponent("app/build/outputs/bundle/app.aab"))

        #expect(!storage.owns(bundle))
        #expect(throws: BuildStorage.Refusal.notThisApp) {
            try storage.removeArtifact(at: bundle)
        }
        #expect(FileManager.default.fileExists(atPath: bundle.path))
    }

    /// The prefix trap. "Super Submitter Backup" begins with every character of
    /// "Super Submitter", so a `hasPrefix` check would call the neighbour ours
    /// and delete somebody's backup folder.
    @Test func aNeighbourWhoseNameStartsTheSameIsRefused() throws {
        let base = try folder()
        defer { try? FileManager.default.removeItem(at: base) }
        let storage = BuildStorage(root: base.appendingPathComponent("Super Submitter"))
        let neighbour = try write(base.appendingPathComponent("Super Submitter Backup/app.zip"))

        #expect(!storage.owns(neighbour))
        #expect(throws: BuildStorage.Refusal.notThisApp) {
            try storage.removeArtifact(at: neighbour)
        }
        #expect(FileManager.default.fileExists(atPath: neighbour.path))
    }

    /// The root itself is not an artifact. Nothing may ask for the whole folder.
    @Test func theStorageRootIsNotItsOwnArtifact() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root)

        #expect(!storage.owns(root))
        #expect(throws: BuildStorage.Refusal.notThisApp) {
            try storage.removeArtifact(at: root)
        }
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test func everyRetainedArchiveGoesAndIsReported() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = BuildStorage(root: root)
        let first = try write(storage.archiveURL(bundleID: "com.example.one", runID: UUID()))
        let second = try write(storage.archiveURL(bundleID: "com.example.two", runID: UUID()))
        // Not an archive. The sweep is for what the developer chose to keep,
        // and the run folders are the prune's job.
        let log = try write(storage.runFolder(UUID()).appendingPathComponent("run.json"))

        let removed = storage.removeRetainedArchives()

        #expect(removed.count == 2)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: log.path))
        #expect(storage.removeRetainedArchives().isEmpty)
    }
}

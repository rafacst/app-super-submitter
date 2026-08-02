import Foundation
import Testing
@testable import SubmitKit

private func temporaryRoot(_ name: String = UUID().uuidString) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("super-submitter-discovery/\(name)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

private func makeFile(_ url: URL, executable: Bool = false) throws {
    try makeDirectory(url.deletingLastPathComponent())
    FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
    if executable {
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path)
    }
}

// MARK: - Bounded discovery

@Test func discoveryFindsAWorkspaceAndSkipsXcodesInternalOne() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeDirectory(root.appendingPathComponent("App.xcworkspace"))
    try makeDirectory(root.appendingPathComponent("App.xcodeproj"))
    try makeDirectory(root.appendingPathComponent("App.xcodeproj/project.xcworkspace"))

    let result = ProjectDiscovery.scan(root: root)
    let workspaces = result.containers.filter { $0.kind == .workspace }
    #expect(workspaces.count == 1)
    #expect(workspaces[0].name == "App.xcworkspace")
    #expect(result.containers.contains { $0.kind == .project })
}

@Test func discoveryIgnoresGeneratedAndDependencyFolders() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeDirectory(root.appendingPathComponent("Pods/Target.xcodeproj"))
    try makeDirectory(root.appendingPathComponent("DerivedData/Old.xcodeproj"))
    try makeDirectory(root.appendingPathComponent("build/Stale.xcodeproj"))
    try makeDirectory(root.appendingPathComponent("Real.xcodeproj"))

    let result = ProjectDiscovery.scan(root: root)
    #expect(result.containers.map(\.name) == ["Real.xcodeproj"])
}

@Test func aSymlinkThatLeavesTheSelectedFolderIsNotFollowed() throws {
    let root = try temporaryRoot()
    let outside = try temporaryRoot("outside-\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try makeDirectory(outside.appendingPathComponent("Escaped.xcodeproj"))
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("link"), withDestinationURL: outside)

    let result = ProjectDiscovery.scan(root: root)
    #expect(!result.containers.contains { $0.name == "Escaped.xcodeproj" })
}

@Test func aGradleWrapperWithoutSettingsIsNotBuildable() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeFile(root.appendingPathComponent("gradlew"), executable: true)

    let container = try #require(ProjectDiscovery.scan(root: root).containers.first)
    #expect(container.kind == .gradle)
    #expect(!container.isBuildable)
    #expect(container.reasons.contains { $0.contains("settings.gradle") })
}

@Test func aNonExecutableWrapperSaysTheFixAndDoesNotApplyIt() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeFile(root.appendingPathComponent("gradlew"))
    try makeFile(root.appendingPathComponent("settings.gradle"))

    let container = try #require(ProjectDiscovery.scan(root: root).containers.first)
    #expect(!container.isBuildable)
    #expect(container.reasons.contains { $0.contains("chmod +x") })
    // The file is untouched: the app never changes a repository permission.
    #expect(!FileManager.default.isExecutableFile(
        atPath: root.appendingPathComponent("gradlew").path))
}

@Test func aWorkspaceNeverWinsSilentlyAgainstASecondContainer() {
    let workspace = DiscoveryResult.Container(path: "/a/One.xcworkspace", kind: .workspace)
    let second = DiscoveryResult.Container(path: "/a/Two.xcworkspace", kind: .workspace)
    let project = DiscoveryResult.Container(path: "/a/One.xcodeproj", kind: .project)

    #expect(ProjectDiscovery.recommended([workspace, project])?.path == workspace.path)
    #expect(ProjectDiscovery.recommended([workspace, second]) == nil)
    #expect(ProjectDiscovery.recommended([project])?.path == project.path)
    #expect(ProjectDiscovery.recommended([]) == nil)
}

// MARK: - Gradle task parsing

@Test func bundleTasksAreFoundAcrossModulesAndFlavours() {
    let output = """
        Android tasks
        -------------
        :app:assembleRelease - Assembles release
        :app:bundleRelease - Assembles bundle 'release'
        :app:bundleDebug - Assembles bundle 'debug'
        :app:bundleProductionRelease - Assembles bundle 'productionRelease'
        :wear:bundleRelease - Assembles bundle 'release'
        :app:bundleReleaseAndroidTest - Test bundle
        bundle - Assembles bundles for all variants
        """

    let variants = AndroidBuildService.parseBundleTasks(output)
    let ids = variants.map(\.id)

    #expect(ids.contains(":app:bundleRelease"))
    #expect(ids.contains(":app:bundleProductionRelease"))
    #expect(ids.contains(":wear:bundleRelease"))
    // Debug, test, and the aggregate `bundle` never reach a store.
    #expect(!ids.contains { $0.lowercased().contains("debug") })
    #expect(!ids.contains { $0.lowercased().contains("test") })
    #expect(!ids.contains(":bundle"))
    // The module is never assumed to be `app`.
    #expect(variants.contains { $0.module == ":wear" })
}

@Test func theGradleVersionComesFromTheWrapperProperties() {
    let properties = "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-bin.zip"
    #expect(AndroidBuildService.gradleVersion(fromDistributionURL: properties) == "8.7")
    #expect(AndroidBuildService.gradleVersion(fromDistributionURL: "nothing here") == nil)
}

@Test func theJarsignerCertificateSummaryHoldsNoPrivateMaterial() {
    let output = """
        s       1234 Mon Jan 01 00:00:00 UTC 2026 META-INF/MANIFEST.MF
          X.509, CN=Upload Key, O=Example, C=GB
          [certificate is valid from 01/01/26 to 01/01/51]
          Signature algorithm: SHA256withRSA, 2048-bit key
        jar verified.
        """
    let (subject, _) = AndroidBuildService.certificate(from: output)
    #expect(subject == "CN=Upload Key, O=Example, C=GB")
    #expect(!output.contains("PRIVATE KEY"))
}

// MARK: - Storage

@Test func anArchivePathSitsOutsideTheRepositoryAndIsNeverPredictable() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = BuildStorage(root: root)

    let first = try storage.archiveURL(bundleID: "com.example.app", runID: UUID())
    let second = try storage.archiveURL(bundleID: "com.example.app", runID: UUID())

    #expect(first != second)
    #expect(first.pathExtension == "xcarchive")
    #expect(first.path.contains("Archives/com.example.app"))
}

@Test func aScratchSecretUsesRestrictivePermissionsAndIsRemoved() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = BuildStorage(root: root)
    let runID = UUID()

    let file = try storage.writeSecret("-----BEGIN PRIVATE KEY-----", named: "AuthKey.p8",
                                       runID: runID)
    let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
        as? NSNumber
    let folderMode = try FileManager.default.attributesOfItem(
        atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber

    #expect(mode?.int16Value == 0o600)
    #expect(folderMode?.int16Value == 0o700)

    storage.removeScratch(runID: runID)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func theExportOptionsAlwaysDisableXcodeVersionManagement() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = BuildStorage(root: root)
    let runID = UUID()

    let url = try AppleBuildService(runner: FakeToolRunner(), storage: storage)
        .writeExportOptions(runID: runID, platform: .ios, team: "TEAM123",
                            signingStyle: "Automatic", distributionBundleIdentifier: nil)
    let plist = try PropertyListSerialization.propertyList(
        from: try Data(contentsOf: url), format: nil) as? [String: Any]

    #expect(plist?["manageAppVersionAndBuildNumber"] as? Bool == false)
    #expect(plist?["method"] as? String == "app-store-connect")
    #expect(plist?["destination"] as? String == "upload")
    #expect(plist?["teamID"] as? String == "TEAM123")
    #expect(plist?["signingStyle"] as? String == "automatic")
}

@Test func onlyAnUnfinishedRunIsResumedAfterARelaunch() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = BuildStorage(root: root)

    var polling = UploadRun(platform: .ios)
    polling.state = .processingOrValidating
    var done = UploadRun(platform: .ios)
    done.state = .complete
    var stranded = UploadRun(platform: .android)
    stranded.state = .failed
    stranded.cleanupState = .needsAttention

    try storage.save(polling)
    try storage.save(done)
    try storage.save(stranded)

    let unfinished = storage.unfinishedRuns().map(\.id)
    #expect(unfinished.contains(polling.id))
    #expect(unfinished.contains(stranded.id))
    #expect(!unfinished.contains(done.id))
}

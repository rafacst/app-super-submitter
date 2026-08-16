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

@Test func aSiblingWhoseNameStartsWithTheRootNameStillEscapesTheRoot() throws {
    let parent = try temporaryRoot("prefix-\(UUID().uuidString)")
    let root = parent.appendingPathComponent("app")
    let sibling = parent.appendingPathComponent("app-secrets")
    defer { try? FileManager.default.removeItem(at: parent) }
    try makeDirectory(root)
    try makeDirectory(sibling)
    let link = root.appendingPathComponent("linked-secrets")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sibling)

    #expect(ProjectDiscovery.escapesRoot(link, root: root))
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

@Test func bundleTaskParsingUsesGradlesVariantDescriptionAndSuffixes() {
    let output = """
        :app:bundleLatestRelease - Assembles bundle for variant latestRelease
        :app:bundleContestRelease - Assembles bundle for variant contestRelease
        :app:bundleReleaseUnitTest - Assembles bundle for variant releaseUnitTest
        :app:bundleSomething - An unrelated task whose name happens to start with bundle
        """

    let variants = AndroidBuildService.parseBundleTasks(output)

    #expect(variants.map(\.id).contains(":app:bundleLatestRelease"))
    #expect(variants.map(\.id).contains(":app:bundleContestRelease"))
    #expect(!variants.map(\.id).contains(":app:bundleReleaseUnitTest"))
    #expect(!variants.map(\.id).contains(":app:bundleSomething"))
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
    let (subject, fingerprint) = AndroidBuildService.certificate(from: output)
    #expect(subject == "CN=Upload Key, O=Example, C=GB")
    #expect(subject?.contains("PRIVATE KEY") != true)
    #expect(fingerprint?.contains("PRIVATE KEY") != true)
}

@Test func certificateParsingDoesNotMistakeTheSignatureAlgorithmForAFingerprint() {
    let output = """
        X.509, CN=Upload Key
        Signature algorithm: SHA256withRSA, 2048-bit key
        SHA-256 digest: AA:BB:CC:DD
        jar verified.
        """

    let (_, fingerprint) = AndroidBuildService.certificate(from: output)

    #expect(fingerprint == "AA:BB:CC:DD")
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

@Test func appleBuildSettingsFindBothNativePlatforms() {
    var settings = AppleBuildSettings()
    settings.values["SUPPORTED_PLATFORMS"] = "macosx iphoneos iphonesimulator"

    #expect(settings.supportsBothApplePlatforms)
}

@Test func appleBuildSettingsDoNotMistakeTheSimulatorForASecondPlatform() {
    var settings = AppleBuildSettings()
    settings.values["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"

    #expect(!settings.supportsBothApplePlatforms)
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

@Test func storageNamesCannotResolveToTheCurrentOrParentDirectory() {
    #expect(BuildStorage.safe(".") == "unknown")
    #expect(BuildStorage.safe("..") == "unknown")
    #expect(BuildStorage.safe("com.example.app") == "com.example.app")
}

@Test func pruningOldDataPreservesRunsThatNeedResumeOrCleanup() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = BuildStorage(root: root)
    var run = UploadRun(platform: .ios)
    run.state = .processingOrValidating
    try storage.save(run)
    let folder = storage.runFolder(run.id)
    let old = Date(timeIntervalSinceNow: -90 * 24 * 60 * 60)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.path)

    let removed = storage.prune(olderThan: 30 * 24 * 60 * 60)

    #expect(!removed.contains(folder))
    #expect(FileManager.default.fileExists(atPath: folder.path))
}

// MARK: - 9.6 What the module says it builds

/// Four preflight rows read "Not read" on every Android project, over values
/// that sit as literals in `build.gradle` in almost all of them. The developer
/// learnt the version the build carried after the build.
@Test func theModuleBuildFileAnswersTheIdentityRows() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeDirectory(root.appendingPathComponent("app"))
    try Data("""
    plugins { id("com.android.application") }
    android {
        namespace = "com.example.other"
        defaultConfig {
            applicationId = "com.rafacst.receitorio"
            versionCode = 7
            versionName = "1.4.1"
            versionNameSuffix = "-beta"
        }
    }
    """.utf8).write(to: root.appendingPathComponent("app/build.gradle.kts"))
    try makeDirectory(root.appendingPathComponent("app/src/main/res/values"))
    try Data("""
    <resources>
        <string name="app_name">Receitório</string>
    </resources>
    """.utf8).write(to: root.appendingPathComponent("app/src/main/res/values/strings.xml"))

    let identity = AndroidBuildService.identity(root: root, module: ":app")

    // `applicationId` and not `namespace`. The namespace is the fallback for
    // a module that names no application id at all.
    #expect(identity.applicationID == "com.rafacst.receitorio")
    #expect(identity.versionCode == "7")
    // And not `-beta`. `versionNameSuffix` starts with `versionName` and is a
    // different setting.
    #expect(identity.versionName == "1.4.1")
    #expect(identity.appName == "Receitório")
}

/// Groovy writes the same settings without the `=`, and a module that names
/// no application id ships under its namespace.
@Test func theGroovyFormAndTheNamespaceFallbackBothRead() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeDirectory(root.appendingPathComponent("app"))
    try Data("""
    android {
        namespace 'com.example.app'
        defaultConfig {
            // applicationId "com.example.old"
            versionCode 12
            versionName '2.0'
        }
    }
    """.utf8).write(to: root.appendingPathComponent("app/build.gradle"))

    let identity = AndroidBuildService.identity(root: root, module: ":app")

    // The commented line is not an assignment. A version left behind under
    // `//` is the one most likely to be read by a parser that ignores it.
    #expect(identity.applicationID == "com.example.app")
    #expect(identity.versionCode == "12")
    #expect(identity.versionName == "2.0")
}

/// A value Gradle computes is absent, and the row says so rather than
/// inventing one. A version catalog reference is not a version.
@Test func aComputedValueStaysUnread() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeDirectory(root.appendingPathComponent("app"))
    try Data("""
    android {
        defaultConfig {
            applicationId = "com.example.app"
            versionName = libs.versions.appVersion.get()
            versionCode = gitCommitCount()
        }
    }
    """.utf8).write(to: root.appendingPathComponent("app/build.gradle.kts"))

    let identity = AndroidBuildService.identity(root: root, module: ":app")

    #expect(identity.applicationID == "com.example.app")
    #expect(identity.versionName == nil)
    #expect(identity.versionCode == nil)
    #expect(identity.appName == nil)
}

/// `:feature:login` is a folder path and not a name.
@Test func aNestedModuleIsANestedFolder() {
    let root = URL(fileURLWithPath: "/tmp/project")
    #expect(AndroidBuildService.moduleFolder(root: root, module: ":feature:login").path
        == "/tmp/project/feature/login")
    #expect(AndroidBuildService.moduleFolder(root: root, module: nil).path == "/tmp/project")
}

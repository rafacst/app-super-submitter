import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// One app, two projects.
///
/// The gap this closes: an app that ships an Xcode project and a Gradle project
/// could hold one link at a time. The lookup matched on the app alone and took
/// the last one whatever store it built for, and the save deduped on the folder,
/// so linking the second folder deleted the first. A monorepo fared no better:
/// discovery finds both containers in one scan, but one link carries one
/// container path and one selection, so every switch was a re-pick that lost
/// the scheme.
///
/// The record already carried the app and the platform. Only the two functions
/// that read and wrote it did not use them.
@MainActor
struct TwoStoreLinkTests {

    /// A storage root of this test's own. These tests write the linked-project
    /// list, and that list is one file for the whole Mac: writing the real one
    /// unlinked every project the developer had, on every run of the suite.
    private func flow(_ root: URL) -> (BuildFlow, AppState) {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)",
                             buildStorage: BuildStorage(
                                root: root.appendingPathComponent("Storage")))
        state.manifestURL = root.appendingPathComponent("store.yaml")
        return (state.buildFlow, state)
    }

    private func link(_ platform: BuildPlatform, root: URL, container: String,
                      manifest: URL) -> LinkedSourceProject {
        LinkedSourceProject(
            platform: platform, rootPath: root.path,
            containerPath: root.appendingPathComponent(container).path,
            containerKind: platform == .android ? .gradle : .project,
            manifestPath: manifest.standardizedFileURL.path)
    }

    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ss-links-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Two folders, one app. Both links survive and each store finds its own.
    @Test func eachStoreKeepsItsOwnFolder() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = flow(root)
        let manifest = try #require(state.manifestURL)
        let apple = link(.ios, root: root.appendingPathComponent("ios"),
                         container: "App.xcodeproj", manifest: manifest)
        let google = link(.android, root: root.appendingPathComponent("android"),
                          container: "gradlew", manifest: manifest)
        try flow.storage.saveProjects([apple, google])

        #expect(flow.savedProjectsForOpenApp().count == 2)
        #expect(flow.savedProject(for: .apple)?.id == apple.id)
        #expect(flow.savedProject(for: .google)?.id == google.id)
    }

    /// The monorepo. One folder, two containers, and the save used to dedup on
    /// the folder, so writing either link deleted the other.
    @Test func oneFolderHoldsTwoLinks() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = flow(root)
        let manifest = try #require(state.manifestURL)
        let apple = link(.macos, root: root, container: "App.xcodeproj", manifest: manifest)
        let google = link(.android, root: root, container: "gradlew", manifest: manifest)
        try flow.storage.saveProjects([apple, google])

        #expect(flow.savedProject(for: .apple)?.containerPath.hasSuffix("App.xcodeproj") == true)
        #expect(flow.savedProject(for: .google)?.containerPath.hasSuffix("gradlew") == true)
    }

    /// iOS and macOS are one App Store app archiving from one project. Two
    /// links for them would make the platform switch lose the scheme.
    @Test func theTwoApplePlatformsShareOneLink() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = flow(root)
        let manifest = try #require(state.manifestURL)
        try flow.storage.saveProjects([link(.ios, root: root, container: "App.xcodeproj",
                                            manifest: manifest)])

        #expect(flow.savedProjectsForOpenApp().count == 1)
        #expect(flow.savedProject(for: .apple)?.platform == .ios)
        #expect(flow.savedProject(for: .google) == nil)
    }

    /// A store with no folder yet is a state and not a failure. The tab shows
    /// the link card, and the switch back has to still be there.
    @Test func aStoreWithNoFolderIsAnEmptyAnswer() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = flow(root)
        let manifest = try #require(state.manifestURL)
        try flow.storage.saveProjects([link(.ios, root: root, container: "App.xcodeproj",
                                            manifest: manifest)])

        #expect(flow.savedProject(for: .google) == nil)
        #expect(flow.savedProject(for: .apple) != nil)
    }

    /// The switch must be reachable from the screen it lands on, or a developer
    /// who picks the store with no folder cannot get back.
    @Test func theStoreSwitchSitsAboveTheLinkCard() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/SuperSubmitter/Build/BuildFromProjectView.swift"),
            encoding: .utf8)
        let row = try #require(source.range(of: "storeRow"))
        let card = try #require(source.range(of: "linkCard"))

        #expect(row.lowerBound < card.lowerBound)
        #expect(source.contains("Text(\"Google Play\").tag(Store.google)"))
    }

    @Test func aNativeMultiplatformProjectOffersBothAppleBuilds() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = flow(root)
        let manifest = try #require(state.manifestURL)
        var project = link(.ios, root: root, container: "App.xcodeproj", manifest: manifest)
        project.selection.scheme = "App"
        flow.project = project
        flow.run = UploadRun(platform: .ios, linkedProjectID: project.id,
                             state: .readyToBuild)
        flow.supportedApplePlatforms = [.ios, .macos]

        #expect(flow.canBuildBothApplePlatforms)
    }

    @Test func aSinglePlatformProjectOffersOneAppleBuild() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = flow(root)
        let manifest = try #require(state.manifestURL)
        var project = link(.ios, root: root, container: "App.xcodeproj", manifest: manifest)
        project.selection.scheme = "App"
        flow.project = project
        flow.run = UploadRun(platform: .ios, linkedProjectID: project.id,
                             state: .readyToBuild)
        flow.supportedApplePlatforms = [.ios]

        #expect(!flow.canBuildBothApplePlatforms)
    }

    @Test func bothAppleBuildsStartWithIOSAndQueueMacOS() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (flow, state) = flow(root)
        let manifest = try #require(state.manifestURL)
        var project = link(.macos, root: root, container: "App.xcodeproj", manifest: manifest)
        project.selection.scheme = "App"
        flow.project = project
        flow.run = UploadRun(platform: .macos, linkedProjectID: project.id,
                             state: .readyToBuild)
        flow.supportedApplePlatforms = [.ios, .macos]

        flow.buildBothApplePlatforms()

        #expect(flow.run.platform == .ios)
        #expect(flow.run.state == .building)
        #expect(flow.queuedApplePlatform == .macos)
        flow.task?.cancel()
    }
}

import Foundation
import Testing
@testable import SubmitKit

/// The build number the store already holds had no answer inside the app.
///
/// App Store Connect refuses a build number it has seen, the preflight blocked
/// on it, and the only way on was Xcode: raise the number in the project, come
/// back, press Recheck. The number now reaches `xcodebuild` as a command-line
/// setting override, which is the one way to change what the archive carries
/// without opening the developer's project file.
@Suite struct BuildNumberOverrideTests {

    @Test func aNumberBecomesASettingOverride() {
        #expect(AppleBuildService.buildNumberArguments("42") == ["CURRENT_PROJECT_VERSION=42"])
    }

    /// Nil is the usual state: the project decides. Everything that is not a
    /// plain number says the same, because a build number is what the store
    /// counts with and the value goes into an argument array unquoted.
    @Test func anythingThatIsNotANumberChangesNothing() {
        for value in [nil, "", " ", "42; rm -rf /", "1.2.3", "v42", "CURRENT_PROJECT_VERSION=1"] {
            #expect(AppleBuildService.buildNumberArguments(value).isEmpty,
                    "\(value ?? "nil") reached the command line")
        }
    }

    @Test func theArchiveCarriesTheChosenNumber() async throws {
        let runner = FakeToolRunner(outcome: ToolOutcome(status: 0))
        let service = AppleBuildService(runner: runner)
        let archivePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("override-\(UUID().uuidString).xcarchive")
        try FileManager.default.createDirectory(at: archivePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archivePath) }

        _ = try await service.archive(
            container: URL(fileURLWithPath: "/tmp/App.xcodeproj"), kind: .project,
            scheme: "App", configuration: "Release", platform: .ios,
            archivePath: archivePath, authentication: nil,
            allowProvisioningUpdates: false, buildNumber: "9", onLine: { _, _ in })

        let arguments = try #require(runner.invocations.last?.arguments)
        #expect(arguments.contains("CURRENT_PROJECT_VERSION=9"))
        // The setting is one argument, never spliced into another one.
        #expect(!arguments.contains { $0.contains(" ") && $0.contains("CURRENT_PROJECT_VERSION") })
    }

    /// The preflight has to read what the build will use, or the screen states
    /// one number, the conflict check asks the store about it, and the archive
    /// carries another.
    @Test func thePreflightReadsTheSettingsWithTheSameNumber() async throws {
        let runner = FakeToolRunner(outcome: ToolOutcome(status: 0, standardOutput: "[]"))
        let service = AppleBuildService(runner: runner)

        _ = try await service.settings(
            container: URL(fileURLWithPath: "/tmp/App.xcodeproj"), kind: .project,
            scheme: "App", configuration: "Release", platform: .ios, buildNumber: "9")

        #expect(runner.invocations.last?.arguments.contains("CURRENT_PROJECT_VERSION=9") == true)
    }

    /// A link saved before the override existed still decodes, and comes back
    /// meaning "the project decides".
    @Test func anOlderLinkStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","platform":"ios","rootPath":"/tmp/App",
         "containerPath":"/tmp/App/App.xcodeproj","containerKind":"project",
         "selection":{"scheme":"App","allowProvisioningUpdates":false},
         "createdAt":0}
        """
        let project = try JSONDecoder().decode(LinkedSourceProject.self,
                                               from: Data(json.utf8))
        #expect(project.selection.buildNumberOverride == nil)
        #expect(project.selection.scheme == "App")
    }
}

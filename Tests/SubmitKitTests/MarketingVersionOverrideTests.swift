import Foundation
import Testing
@testable import SubmitKit

/// The release version in `store.yaml`, reaching the build.
///
/// The bug this guards: the release version was typed as 1.6 and the preflight
/// read 1.5 off the project, so the screen showed 1.5 with a green tick beside
/// it and said nothing. The disagreement was caught only after the archive
/// existed, where `store.yaml version` is a blocking mismatch, so a whole build
/// was spent to learn it. The version now travels to `xcodebuild` the way the
/// build number does, and the project file is neither opened nor written.
struct MarketingVersionOverrideTests {

    @Test func aVersionBecomesASettingOverride() {
        #expect(AppleBuildService.marketingVersionArguments("1.6")
                == ["MARKETING_VERSION=1.6"])
        #expect(AppleBuildService.marketingVersionArguments("1.6.2")
                == ["MARKETING_VERSION=1.6.2"])
    }

    /// Nil is the usual state: the project decides. Everything that is not a
    /// dotted number says the same, because the value goes into an argument
    /// array unquoted.
    @Test func anythingThatIsNotADottedNumberChangesNothing() {
        #expect(AppleBuildService.marketingVersionArguments(nil).isEmpty)
        #expect(AppleBuildService.marketingVersionArguments("").isEmpty)
        #expect(AppleBuildService.marketingVersionArguments("1.6 beta").isEmpty)
        #expect(AppleBuildService.marketingVersionArguments("1.6; rm -rf /").isEmpty)
        #expect(AppleBuildService.marketingVersionArguments("$(whoami)").isEmpty)
    }

    /// The two overrides are separate arguments and separate settings. One
    /// spliced into the other would set neither.
    @Test func theVersionAndTheBuildNumberStayApart() {
        let arguments = AppleBuildService.buildNumberArguments("191")
            + AppleBuildService.marketingVersionArguments("1.6")

        #expect(arguments == ["CURRENT_PROJECT_VERSION=191", "MARKETING_VERSION=1.6"])
    }

    /// A link saved before the override existed still decodes, and comes back
    /// meaning "the project decides".
    @Test func anOlderLinkStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","platform":"ios","rootPath":"/tmp/app",
         "containerPath":"/tmp/app/App.xcodeproj","containerKind":"project",
         "selection":{"scheme":"App","allowProvisioningUpdates":false},
         "createdAt":0}
        """

        let project = try JSONDecoder().decode(LinkedSourceProject.self,
                                               from: Data(json.utf8))

        #expect(project.selection.marketingVersionOverride == nil)
        #expect(AppleBuildService.marketingVersionArguments(
            project.selection.marketingVersionOverride).isEmpty)
    }
}

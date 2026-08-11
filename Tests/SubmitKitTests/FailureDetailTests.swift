import Foundation
import Testing
@testable import SubmitKit

/// What a failure panel shows when a build fails.
///
/// The bug this guards: the panel took the standard error alone, and that is
/// the wrong half for the two tools this app runs. `xcodebuild` prints compile
/// errors and the reason for exit status 65 on standard output; Gradle splits
/// its failure across both. So the panel reported an exit status and offered an
/// empty Diagnostics box, on the one screen a developer opens to find out what
/// broke.
@Suite struct FailureDetailTests {

    @Test func standardOutputIsUsedWhenTheToolSaidNothingOnStandardError() {
        let outcome = ToolOutcome(status: 65,
                                  standardOutput: "error: no such module 'Foo'")
        #expect(outcome.failureDetail == "error: no such module 'Foo'")
    }

    @Test func standardErrorAloneStaysWhatItWas() {
        let outcome = ToolOutcome(status: 65, standardError: "xcodebuild: error: no scheme")
        #expect(outcome.failureDetail == "xcodebuild: error: no scheme")
    }

    /// Both, each named. "The following build commands failed" on one stream
    /// and the command itself on the other is one answer in two places.
    @Test func bothStreamsAreNamedWhenBothSpoke() {
        let outcome = ToolOutcome(status: 65, standardOutput: "CompileSwift failed",
                                  standardError: "** ARCHIVE FAILED **")
        let detail = outcome.failureDetail

        #expect(detail.contains("Standard error\n** ARCHIVE FAILED **"))
        #expect(detail.contains("Standard output\nCompileSwift failed"))
    }

    @Test func aToolThatSaidNothingHasNothingToShow() {
        #expect(ToolOutcome(status: 65).failureDetail.isEmpty)
        #expect(ToolOutcome(status: 65, standardOutput: "  \n \n").failureDetail.isEmpty)
    }

    /// A failure is at the end. The head of a build log is a thousand lines of
    /// compiling, and the panel is a box six lines tall.
    @Test func onlyTheTailIsKept() {
        let long = (1...400).map { "line \($0)" }.joined(separator: "\n")
        let detail = ToolOutcome(status: 65, standardError: long).failureDetail

        #expect(detail.contains("line 400"))
        #expect(!detail.contains("line 299\n"))
        #expect(detail.hasPrefix("[300 earlier lines."))
    }
}

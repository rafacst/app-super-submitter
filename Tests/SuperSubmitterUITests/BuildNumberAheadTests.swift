import Foundation
import Testing
@testable import SuperSubmitter

/// A build number the artifact carries against the one the run asked for.
///
/// The bug this guards: the block was `buildNumberOverride != nil`, so any
/// difference at all stopped the upload once a number had been chosen here.
/// A project that stamps its own `CFBundleVersion` from a script phase came
/// out at 215 where the run asked for 191, the store's highest was 190, and
/// the app refused an upload App Store Connect would have taken. There was no
/// way past it but another build, which produced the same artifact again.
struct BuildNumberAheadTests {

    /// The reported case. Higher clears the same conflict the override was
    /// chosen to clear.
    @Test func anArtifactAboveTheChosenNumberDoesNotBlock() {
        #expect(!BuildFlow.buildNumberFallsShort(asked: "191", built: "215"))
    }

    /// The one it must still catch: the project ignored the setting and built
    /// the number the store already holds.
    @Test func anArtifactBelowTheChosenNumberBlocks() {
        #expect(BuildFlow.buildNumberFallsShort(asked: "191", built: "190"))
    }

    @Test func theNumberThatWasAskedForIsNoMismatchAtAll() {
        #expect(!BuildFlow.buildNumberFallsShort(asked: "191", built: "191"))
    }

    /// Nothing was asked for, so nothing falls short. The project decides, and
    /// a script that bumps the number is ordinary.
    @Test func noOverrideNeverBlocks() {
        #expect(!BuildFlow.buildNumberFallsShort(asked: nil, built: "215"))
        #expect(!BuildFlow.buildNumberFallsShort(asked: "", built: "1"))
    }

    /// Counting, not text. "99" against "100" is the comparison a string
    /// ordering gets backwards, and it is the one the store makes.
    @Test func theComparisonIsNumericAndNotAlphabetical() {
        #expect(!BuildFlow.buildNumberFallsShort(asked: "99", built: "100"))
        #expect(BuildFlow.buildNumberFallsShort(asked: "100", built: "99"))
    }

    /// A dotted `CFBundleVersion` cannot be ranked against a plain number, so
    /// the difference blocks and the developer decides.
    @Test func aNumberThatIsNotPlainStillBlocks() {
        #expect(BuildFlow.buildNumberFallsShort(asked: "191", built: "1.2.3"))
    }
}

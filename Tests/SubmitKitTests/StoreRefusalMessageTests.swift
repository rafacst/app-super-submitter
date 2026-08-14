import Foundation
import Testing
@testable import SubmitKit

/// What the run banner says when a store refuses a call.
///
/// The bug this guards: the store's own sentence was dropped whenever it ran
/// past 240 characters. Apple refused a screenshot set with the reason spelled
/// out and then forty enum values after it, so the whole answer went in the bin
/// and the developer read "The store already holds something that conflicts
/// with this" over a run that had stopped for a named, fixable reason.
///
/// A wall of enum values is the machine talking to itself. The first sentence
/// is the reason, and it is short.

/// The response that stopped a real run, to the character.
private let appleScreenshotRefusal = """
'APP_IPHONE_69' is not a valid value for the attribute 'screenshotDisplayType'. \
Expected one of: 'APP_DESKTOP', 'APP_WATCH_SERIES_3', 'APP_WATCH_SERIES_4', \
'APP_IPAD_105', 'APP_IPAD_PRO_129', 'IMESSAGE_APP_IPHONE_55', \
'APP_WATCH_SERIES_7', 'APP_IPHONE_61', 'IMESSAGE_APP_IPHONE_58', \
'APP_WATCH_ULTRA', 'IMESSAGE_APP_IPAD_PRO_3GEN_129', 'APP_IPHONE_65', \
'APP_IPHONE_40', 'APP_IPHONE_67', 'IMESSAGE_APP_IPAD_PRO_129'
"""

@Test func aLongRefusalKeepsTheSentenceThatNamesTheReason() {
    let message = ConnectionError.explain(status: 409, detail: appleScreenshotRefusal)

    #expect(message.contains("The store already holds something that conflicts with this."))
    #expect(message.contains(
        "'APP_IPHONE_69' is not a valid value for the attribute 'screenshotDisplayType'."))
    // And not the forty values after it.
    #expect(!message.contains("IMESSAGE_APP_IPAD_PRO_129"))
    #expect(!message.contains("Expected one of"))
}

@Test func aShortRefusalIsPassedThroughWhole() {
    let message = ConnectionError.explain(
        status: 422, detail: "The version string must be greater than the previous version")

    #expect(message.hasSuffix("greater than the previous version."))
}

/// A raw payload says nothing to a developer, so it is still dropped rather
/// than printed at them.
@Test func aWallOfJSONIsNotASentence() {
    #expect(ConnectionError.explain(status: 400, detail: "{\"errors\":[{\"code\":\"X\"}]}")
        == "The store refused this as it stands.")
    #expect(ConnectionError.explain(status: 400, detail: "<html><body>Gateway</body></html>")
        == "The store refused this as it stands.")
    #expect(ConnectionError.explain(status: 400, detail: "   ")
        == "The store refused this as it stands.")
}

/// One long sentence with no full stop in it is cut rather than dropped. Half
/// an answer beats none, and the ellipsis says it was cut.
@Test func oneUnbrokenSentenceIsCutAndMarked() {
    let message = ConnectionError.explain(status: 400,
                                          detail: String(repeating: "word ", count: 100))

    #expect(message.hasSuffix("…"))
    #expect(message.count < 320)
}

/// A full stop inside a file name or a version number does not end the
/// sentence, so the reason is not cut off at "1".
@Test func aFullStopInsideAValueDoesNotEndTheSentence() {
    let detail = "The build 1.2.3 for shot-1.png was refused because the pixel size "
        + String(repeating: "does not match any accepted size ", count: 8)
    let message = ConnectionError.explain(status: 409, detail: detail)

    #expect(message.contains("The build 1.2.3 for shot-1.png was refused"))
}

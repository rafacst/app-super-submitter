import AppKit

/// The trackpad, for the two moments in this app that are direct manipulation.
///
/// A `.p8` key, a service-account JSON, an `.ipa` and a screenshot all arrive
/// by being dragged out of Downloads or the Finder. Four drop targets in the
/// app already brighten when the pointer enters them, and until this existed
/// none of them confirmed the drop itself: the file simply appeared, or did
/// not, and the developer looked back at the well to check.
///
/// Three rules, all from the report:
///
/// - Only on a user-initiated drop or snap, never on arrival at a target and
///   never on anything the app did by itself.
/// - Always beside visible feedback. The haptic is the second channel, never
///   the only one. Every call site here already changes on screen.
/// - Never required. Force Touch trackpads are the only hardware that performs
///   these, and `NSHapticFeedbackManager` is a no-op everywhere else, so a
///   Mac with a mouse loses nothing.
///
/// `// ponytail: one enum, no protocol, no injected performer. The system
/// // performer is already a no-op on hardware that cannot do this.`
@MainActor
enum Haptic {
    /// A file, or a tile, landed somewhere it was accepted.
    ///
    /// `.alignment` and not `.generic`. Alignment is the pattern macOS uses
    /// when something snaps into a position the user aimed at, which is what
    /// every drop in this app is: into a well, or in front of one tile of a
    /// row whose order both stores publish.
    ///
    /// `.drawCompleted` and not `.now`. The tick then lands on the frame the
    /// highlight resolves, so the trackpad and the screen agree; `.now` fires
    /// a frame or two early and reads as a tick for the wrong thing.
    static func drop() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment,
                                                         performanceTime: .drawCompleted)
    }
}

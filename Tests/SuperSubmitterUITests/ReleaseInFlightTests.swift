import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// What the screen says while a submission is with a store.
///
/// The bug this guards: `releasing` was set for the whole length of the call
/// and no view read it. The confirmation sheet dismisses itself the moment it
/// is confirmed, so the tab underneath looked exactly as it had before the
/// press, for as long as Apple took to answer. The one irreversible button in
/// the app appeared to have done nothing, which is the state that invites a
/// second press.
@MainActor
struct ReleaseInFlightTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source() throws -> String {
        try String(contentsOf: Self.root.appending(path: "Sources/SuperSubmitter/Tabs/ReleaseTab.swift"),
                   encoding: .utf8)
    }

    /// The state that made the button silent still exists, and is now read.
    @Test func theTabReadsTheFlagTheCallSets() throws {
        let tab = try source()

        #expect(tab.contains("state.releasing == store"),
                "the release tab does not read the flag the call sets")
    }

    /// A spinner and a disabled button. Either alone leaves the press
    /// ambiguous: a dead button with no motion reads as a button that failed.
    @Test func theButtonShowsMotionAndRefusesASecondPress() throws {
        let tab = try source()

        #expect(tab.contains("if sending { Spinner() }"))
        #expect(tab.contains("done || blocked || sending"),
                "a second press is still possible while the first is in flight")
    }

    /// The take-back runs through the same flag, so the direction has to be
    /// told apart. Announcing a cancel as a send is worse than saying nothing.
    @Test func aCancelIsNotAnnouncedAsASend() throws {
        let tab = try source()

        #expect(tab.contains("state.releasing == store && !released"))
        #expect(tab.contains("state.releasing == store && released"))
        #expect(tab.contains("if undoing { Spinner() }"),
                "the take-back is as silent as the send used to be")
    }

    // MARK: - The flag itself

    /// The model's own guard, which is what makes the disabled button belt and
    /// braces rather than the only defence.
    @Test func aSecondReleaseWhileOneIsInFlightDoesNothing() async {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.releasing = .apple

        // No app id, no version: this would set `releaseError` if it ran past
        // the guard, and reaching the network is impossible from a test.
        await state.release(.apple)

        #expect(state.releaseError == nil, "a second release ran while one was in flight")
        #expect(state.releasing == .apple)
    }
}

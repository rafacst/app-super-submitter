import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

private let mediaReviewRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func mediaReviewSource(_ relativePath: String) throws -> String {
    try String(contentsOf: mediaReviewRepositoryRoot.appendingPathComponent(relativePath),
               encoding: .utf8)
}

// MARK: - Each store's sets, under that store's name

/// The tab was one column of seven device classes with nothing saying which
/// store asked for which. Small tablet is Play's alone, Desktop and Vision are
/// Apple's alone, and the rest go to both, and a developer had to know that
/// already to read the page.
@Test func theSetsStandUnderTheStoreThatTakesThem() throws {
    let tab = try mediaReviewSource("Sources/SuperSubmitter/Tabs/MediaTab.swift")

    #expect(tab.contains("private func storeBand"))
    #expect(tab.contains("takers"))
}

/// Which store takes a device class is a fact of the two catalogues, not a
/// layout choice, so it is answered once and in one place.
@Test func everyDeviceClassNamesItsStores() {
    #expect(MediaTab.takers(.desktop) == [.apple])
    #expect(MediaTab.takers(.vision) == [.apple])
    #expect(MediaTab.takers(.tablet7) == [.google])
    #expect(MediaTab.takers(.phone) == [.apple, .google])
    #expect(MediaTab.takers(.tablet10) == [.apple, .google])
}

/// The lock message takes a place in the column instead of floating over it.
///
/// As an overlay it was drawn on top of the first card, centred, across the
/// sentence that says what the tab is for. Two messages in one place, and the
/// one that says why the whole tab is dim was the one underneath. It also has
/// to sit outside `.disabled`, because it is the reason for the dimming and it
/// has to stay legible to say so.
@Test func theReviewLockStandsAboveTheTabAndNotOnTopOfIt() throws {
    let tab = try mediaReviewSource("Sources/SuperSubmitter/Tabs/MediaTab.swift")

    #expect(tab.contains("if mediaLockedByReview { lockNote }"))
    #expect(tab.contains("private var lockNote"))
    // The whole tab still refuses a swap while Apple is reading the pictures.
    #expect(tab.contains(".disabled(mediaLockedByReview)"))
    #expect(!tab.contains("overlay(alignment: .top)"))
}

/// Nothing the tab already did may leave with the rearrangement: the drop
/// wells, the live strip, the two Google graphics and the YouTube URL all stay.
@Test func theTilesAndTheGraphicsSurvive() throws {
    let tab = try mediaReviewSource("Sources/SuperSubmitter/Tabs/MediaTab.swift")

    #expect(tab.contains("googleGraphics"))
    #expect(tab.contains("videoSection"))
    #expect(tab.contains("mediaPaths(deviceClass:"))
    #expect(tab.contains("DirectApplyBar(target: .media)"))
    #expect(tab.contains("liveScreenshots"))
}

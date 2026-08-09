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

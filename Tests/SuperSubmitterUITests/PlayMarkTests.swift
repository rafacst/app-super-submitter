import CoreGraphics
import Testing
@testable import SuperSubmitter

/// The mark is hand-transcribed SVG. A wrong arc centre or a wrong sweep pushes
/// a wedge outside the artboard, and the union of the four wedges catches it.
@MainActor
@Test func thePlayMarkFillsItsArtboardAndNoMore() {
    let bounds = PlayMark.wedges.dropFirst().reduce(PlayMark.wedges[0].path.boundingRect) {
        $0.union($1.path.boundingRect)
    }
    #expect(abs(bounds.minX) < 0.05)
    #expect(abs(bounds.minY) < 0.05)
    #expect(abs(bounds.maxX - PlayMark.artboard.width) < 0.05)
    #expect(abs(bounds.maxY - PlayMark.artboard.height) < 0.05)
}

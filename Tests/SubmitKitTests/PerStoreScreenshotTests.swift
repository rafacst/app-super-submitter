import Foundation
import Testing
@testable import SubmitKit

/// Screenshots per store.
///
/// The two stores accept different sizes and, more often, different pictures:
/// a Play listing and an App Store listing of the same app are rarely the same
/// eight images. The manifest held one list per size and sent it to both.
///
/// The shape is an override and not a second model, so every `store.yaml`
/// written before this keeps working: no override means both stores read the
/// shared list, exactly as they did.
@Suite struct PerStoreScreenshotTests {

    private func manifest(shared: [String], apple: [String]? = nil,
                          google: [String]? = nil) -> Manifest {
        var media = Manifest.Media(screenshots: ["en-US": ["phone": shared]])
        if let apple { media.appleScreenshots = ["en-US": ["phone": apple]] }
        if let google { media.googleScreenshots = ["en-US": ["phone": google]] }
        var manifest = Manifest()
        manifest.media = media
        return manifest
    }

    @Test func withNoOverrideBothStoresReadTheSharedList() {
        let m = manifest(shared: ["a.png", "b.png"])

        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone) == ["a.png", "b.png"])
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .apple)
                == ["a.png", "b.png"])
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
                == ["a.png", "b.png"])
    }

    @Test func anOverrideAnswersForItsStoreAlone() {
        let m = manifest(shared: ["a.png"], google: ["g1.png", "g2.png"])

        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .apple) == ["a.png"])
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
                == ["g1.png", "g2.png"])
        // The shared list is what a caller with no store in hand still reads.
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone) == ["a.png"])
    }

    /// An override present and empty is a decision: send this store nothing for
    /// this size. It may not fall back to the shared list.
    @Test func anEmptyOverrideIsAnAnswerAndNotAnAbsence() {
        let m = manifest(shared: ["a.png"], google: [])

        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google).isEmpty)
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .apple) == ["a.png"])
    }

    /// Splitting copies what both stores hold today into both columns, so the
    /// first edit after a split changes one store and never both.
    @Test func splittingCopiesTheSharedListIntoBoth() {
        var m = manifest(shared: ["a.png", "b.png"])
        m.splitMedia(locale: "en-US", deviceClass: .phone)

        #expect(m.hasStoreScreenshots(locale: "en-US", deviceClass: .phone, store: .apple))
        #expect(m.hasStoreScreenshots(locale: "en-US", deviceClass: .phone, store: .google))
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .apple)
                == ["a.png", "b.png"])
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
                == ["a.png", "b.png"])
    }

    /// Merging is lossy, and it says which of the two it keeps: the App Store
    /// list becomes the shared one and both overrides go.
    @Test func mergingKeepsTheAppleListAndDropsBothOverrides() {
        var m = manifest(shared: ["old.png"], apple: ["a.png"], google: ["g.png"])
        m.mergeMedia(locale: "en-US", deviceClass: .phone)

        #expect(!m.hasStoreScreenshots(locale: "en-US", deviceClass: .phone, store: .apple))
        #expect(!m.hasStoreScreenshots(locale: "en-US", deviceClass: .phone, store: .google))
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone) == ["a.png"])
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google) == ["a.png"])
    }

    /// A write to one store's column lands in that store's list and leaves the
    /// other store alone.
    @Test func addingToOneStoreLeavesTheOtherAlone() {
        var m = manifest(shared: ["a.png"])
        m.splitMedia(locale: "en-US", deviceClass: .phone)
        m.addMediaPaths(["g.png"], locale: "en-US", deviceClass: .phone, store: .google)

        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .apple) == ["a.png"])
        #expect(m.mediaPaths(locale: "en-US", deviceClass: .phone, store: .google)
                == ["a.png", "g.png"])
    }

    /// Previews are Apple's alone, so a store never changes what they answer.
    @Test func previewsIgnoreTheStore() {
        var manifest = Manifest()
        manifest.media = Manifest.Media(previews: ["en-US": ["phone": ["p.mov"]]])

        #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone,
                                    previews: true, store: .apple) == ["p.mov"])
        #expect(manifest.mediaPaths(locale: "en-US", deviceClass: .phone,
                                    previews: true, store: .google) == ["p.mov"])
    }
}

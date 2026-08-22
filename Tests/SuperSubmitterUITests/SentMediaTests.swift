import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// The bug these guard: a screenshot that has been sent stayed in `store.yaml`.
///
/// The tab went on drawing it as a local file waiting to go, and the next plan
/// read the same list as an upload still to make. What the store holds is the
/// store's to answer for.
@MainActor
struct SentMediaTests {

    private func state(stores: Set<Store>) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "sent-\(UUID().uuidString)")
        if stores.contains(.apple) {
            state.manifest.apps.apple = Manifest.Apps.Apple(
                appId: "123", platforms: [.ios], bundleId: "com.example.app")
        }
        if stores.contains(.google) {
            state.manifest.apps.google = Manifest.Apps.Google(packageName: "com.example.app")
        }
        state.manifest.addLocale("en-US")
        state.locale = "en-US"
        return state
    }

    private func step(_ id: String) -> PlanStep {
        PlanStep(id: id, system: id.hasPrefix("apple") ? .apple : .google, kind: .add,
                 summary: "", title: "", requests: [],
                 operation: .appleScreenshots(locale: "en-US", deviceClass: "phone", files: []))
    }

    @Test func aSentSizeLosesItsLocalList() {
        let state = self.state(stores: [.apple])
        state.manifest.addMediaPaths(["a.png", "b.png"], locale: "en-US", deviceClass: .phone)
        state.manifest.addMediaPaths(["tablet.png"], locale: "en-US", deviceClass: .tablet10)

        #expect(state.adoptSentMedia([step("apple.media.en-US.phone")]))

        #expect(state.mediaPaths(deviceClass: .phone).isEmpty)
        #expect(state.manifest.mediaPaths(locale: "en-US", deviceClass: .phone,
                                          store: .apple).isEmpty)
        // The size nobody sent keeps every picture it was given.
        #expect(state.mediaPaths(deviceClass: .tablet10) == ["tablet.png"])
    }

    /// One shared list feeds both stores. An App Store send may not throw away
    /// pictures Google has never been given.
    @Test func theOtherStoreKeepsWhatItHasNotBeenSent() {
        let state = self.state(stores: [.apple, .google])
        state.manifest.addMediaPaths(["a.png", "b.png"], locale: "en-US", deviceClass: .phone)

        state.adoptSentMedia([step("apple.media.en-US.phone")])

        #expect(state.manifest.mediaPaths(locale: "en-US", deviceClass: .phone,
                                          store: .apple).isEmpty)
        #expect(state.manifest.mediaPaths(locale: "en-US", deviceClass: .phone,
                                          store: .google) == ["a.png", "b.png"])

        // And once Google has them too, nothing local is left anywhere.
        state.adoptSentMedia([step("google.media.en-US.phone")])
        #expect(state.manifest.mediaPaths(locale: "en-US", deviceClass: .phone,
                                          store: .google).isEmpty)
        #expect(state.mediaPaths(deviceClass: .phone).isEmpty)
    }

    @Test func previewsGoTheSameWay() {
        let state = self.state(stores: [.apple])
        state.manifest.addMediaPaths(["clip.mp4"], locale: "en-US", deviceClass: .phone,
                                     previews: true)
        state.manifest.addMediaPaths(["a.png"], locale: "en-US", deviceClass: .phone)

        state.adoptSentMedia([step("apple.preview.en-US.phone")])

        #expect(state.mediaPaths(deviceClass: .phone, previews: true).isEmpty)
        // A preview step says nothing about the screenshots beside it.
        #expect(state.mediaPaths(deviceClass: .phone) == ["a.png"])
    }

    /// Every other step in a run leaves the pictures alone, including the two
    /// Google media ids that name no size at all.
    @Test func onlyAMediaStepClearsAnything() {
        #expect(AppState.sentMedia(stepID: "apple.media.en-US.phone")?.locale == "en-US")
        #expect(AppState.sentMedia(stepID: "apple.preview.en-US.phone")?.previews == true)
        #expect(AppState.sentMedia(stepID: "google.media.pt-BR.tablet7")?.store == .google)
        #expect(AppState.sentMedia(stepID: "google.media.icon") == nil)
        #expect(AppState.sentMedia(stepID: "google.media.featureGraphic") == nil)
        #expect(AppState.sentMedia(stepID: "google.media.delete.en-US.phone") == nil)
        #expect(AppState.sentMedia(stepID: "apple.media.en-US.watchOS") == nil)
        #expect(AppState.sentMedia(stepID: "apple.version.locale.en-US") == nil)

        let state = self.state(stores: [.apple])
        state.manifest.addMediaPaths(["a.png"], locale: "en-US", deviceClass: .phone)
        #expect(!state.adoptSentMedia([step("apple.versionLocale.en-US")]))
        #expect(state.mediaPaths(deviceClass: .phone) == ["a.png"])
    }

    /// The other half of the same story, on the plan side.
    ///
    /// "One store has screenshots and the other has none" is a warning about a
    /// listing that would go out bare. A size the App Store has already been
    /// sent is empty here on purpose, so the warning has to ask the store
    /// before it fires or every dual-store app wears it between its two sends.
    @Test func aSizeTheStoreHoldsIsNotAStoreWithNoScreenshots() {
        var apple = ActualState.Apple()
        apple.screenshotURLs = [
            "en-US/APP_IPHONE_67": [URL(string: "https://apple.example/1.png")!],
            "pt-BR/APP_IPHONE_67": [],
        ]
        var actual = ActualState()
        actual.apple = apple

        #expect(Validator.storeHoldsScreenshots(.apple, locale: "en-US", deviceClass: .phone,
                                                actual: actual))
        // A different size, a different language, and a bucket the store
        // returned empty are all "no".
        #expect(!Validator.storeHoldsScreenshots(.apple, locale: "en-US", deviceClass: .tablet10,
                                                 actual: actual))
        #expect(!Validator.storeHoldsScreenshots(.apple, locale: "de-DE", deviceClass: .phone,
                                                 actual: actual))
        #expect(!Validator.storeHoldsScreenshots(.apple, locale: "pt-BR", deviceClass: .phone,
                                                 actual: actual))
        // Google keys the same way under its own bucket names.
        var google = ActualState.Google()
        google.imageURLs = ["en-US/phoneScreenshots": [URL(string: "https://play.example/1.png")!]]
        actual.google = google
        #expect(Validator.storeHoldsScreenshots(.google, locale: "en-US", deviceClass: .phone,
                                                actual: actual))
        #expect(!Validator.storeHoldsScreenshots(.google, locale: "en-US", deviceClass: .tablet7,
                                                actual: actual))
    }

    /// The developer filled that list by hand, so one Command-Z brings it back.
    @Test func theSendIsOneUndoStep() {
        let state = self.state(stores: [.apple])
        state.manifest.addMediaPaths(["a.png"], locale: "en-US", deviceClass: .phone)
        state.saveManifestReportingErrors()

        state.adoptSentMedia([step("apple.media.en-US.phone")])
        #expect(state.mediaPaths(deviceClass: .phone).isEmpty)

        state.undoManager.undo()
        #expect(state.mediaPaths(deviceClass: .phone) == ["a.png"])
    }
}

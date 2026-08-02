import Foundation
import Testing
@testable import SubmitKit

private func temporaryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("super-submitter-artifacts/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeFile(_ root: URL, _ name: String) throws -> String {
    let url = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
    return name
}

private func sampleManifest() -> Manifest {
    var manifest = Manifest()
    manifest.setGoogleApp(packageName: "com.example.app")
    manifest.addLocale("en-US", name: "Example")
    manifest.setListingText("A long description.", locale: "en-US", field: .description)
    manifest.setReleaseVersionName("1.2.0")
    return manifest
}

private func input(_ manifest: Manifest, root: URL? = nil,
                   actual: ActualState = ActualState()) -> Planner.Input {
    Planner.Input(manifest: manifest, actual: actual, stores: [.google], root: root)
}

// MARK: - The track list

@Test func theTrackListFallsBackToOneProductionTrack() {
    let manifest = sampleManifest()

    #expect(manifest.googleTracks == ["production"])
    #expect(manifest.googlePrimaryTrack == "production")
}

@Test func theTrackListReplacesTheSingleTrackWhenItExists() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        track: "beta", tracks: ["internal", "beta"])

    #expect(manifest.googleTracks == ["internal", "beta"])
    #expect(manifest.googlePrimaryTrack == "beta")
}

@Test func theFirstListedTrackLeadsWhenNoPrimaryTrackExists() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(tracks: ["internal", "beta"])

    #expect(manifest.googlePrimaryTrack == "internal")
}

@Test func anEmptyCountryListSendsNoTargeting() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(includeRestOfWorld: true)

    #expect(manifest.googleCountryTargeting == nil)
}

@Test func theCountryListCarriesTheRestOfTheWorldFlag() throws {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        countries: ["US", "DE"], includeRestOfWorld: true)

    let targeting = try #require(manifest.googleCountryTargeting)
    #expect(targeting["countries"] as? [String] == ["US", "DE"])
    #expect(targeting["includeRestOfWorld"] as? Bool == true)
}

// MARK: - The plan

@Test func everyTrackTakesItsOwnWriteInsideOneEdit() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        track: "production", tracks: ["internal", "production"])

    let steps = Planner.plan(input(manifest)).steps(for: .google)

    #expect(steps.contains { $0.id == "google.track.internal" })
    #expect(steps.contains { $0.id == "google.track.production" })
    #expect(steps.first?.id == "google.openEdit")
    #expect(steps.last?.id == "google.commit")
}

@Test func onlyAnUnknownTrackTakesACreateStep() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        track: "qa-team", tracks: ["beta", "qa-team"])

    let steps = Planner.plan(input(manifest)).steps(for: .google)

    #expect(steps.contains { $0.id == "google.createTrack.qa-team" })
    #expect(!steps.contains { $0.id == "google.createTrack.beta" })
}

@Test func aTrackThatTheStoreAlreadyHoldsTakesNoCreateStep() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(tracks: ["qa-team"])
    var actual = ActualState()
    var google = ActualState.Google()
    google.tracks["qa-team"] = ActualState.Google.Track()
    actual.google = google

    let steps = Planner.plan(input(manifest, actual: actual)).steps(for: .google)

    #expect(!steps.contains { $0.id == "google.createTrack.qa-team" })
}

@Test func theCreateStepRunsBeforeTheTrackWrite() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(tracks: ["qa-team"])

    let steps = Planner.plan(input(manifest)).steps(for: .google)
    let create = steps.firstIndex { $0.id == "google.createTrack.qa-team" }
    let write = steps.firstIndex { $0.id == "google.track.qa-team" }

    #expect(create != nil)
    #expect(write != nil)
    #expect(create! < write!)
}

@Test func theArtifactStepsAppearOnlyForFilesThatExist() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var manifest = sampleManifest()
    manifest.release?.build = Manifest.Release.Build(
        androidApk: try makeFile(root, "app.apk"))
    manifest.release?.google = Manifest.Release.GoogleRelease(
        mappingFile: try makeFile(root, "mapping.txt"),
        nativeDebugSymbols: try makeFile(root, "symbols.zip"),
        expansionFileMain: try makeFile(root, "main.obb"))

    let steps = Planner.plan(input(manifest, root: root)).steps(for: .google)

    #expect(steps.contains { $0.id == "google.apk" })
    #expect(steps.contains { $0.id == "google.deobfuscation.proguard" })
    #expect(steps.contains { $0.id == "google.deobfuscation.nativeCode" })
    #expect(steps.contains { $0.id == "google.expansion.main" })
    #expect(!steps.contains { $0.id == "google.expansion.patch" })
}

@Test func everyArtifactUploadRunsBeforeTheTrackWrite() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var manifest = sampleManifest()
    manifest.release?.build = Manifest.Release.Build(
        androidApk: try makeFile(root, "app.apk"))
    manifest.release?.google = Manifest.Release.GoogleRelease(
        mappingFile: try makeFile(root, "mapping.txt"))

    let steps = Planner.plan(input(manifest, root: root)).steps(for: .google)
    let track = try #require(steps.firstIndex { $0.id == "google.track.production" })

    // The mapping file attaches to a version code, so the upload must land
    // first. The expansion file has the same rule.
    #expect(try #require(steps.firstIndex { $0.id == "google.apk" }) < track)
    #expect(try #require(steps.firstIndex { $0.id == "google.deobfuscation.proguard" }) < track)
}

@Test func theExternallyHostedApkTakesOneStep() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        externalApk: Manifest.Release.ExternalApk(
            url: "https://example.com/app.apk", applicationLabel: "Example",
            versionCode: 7, versionName: "1.2.0", minimumSdk: 24,
            certificateBase64s: ["AAAA"]))

    let steps = Planner.plan(input(manifest)).steps(for: .google)

    #expect(steps.contains { $0.id == "google.externalApk" })
}

// MARK: - The rules

@Test func anExpansionFileWithoutAnApkIsAnError() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        expansionFileMain: try makeFile(root, "main.obb"))

    let findings = Validator.findings(input(manifest, root: root))

    #expect(findings.contains { $0.id == "build.expansionNeedsApk" && $0.severity == .error })
}

@Test func aMissingArtifactFileIsAnError() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(mappingFile: "no/such/mapping.txt")

    let findings = Validator.findings(input(manifest))

    #expect(findings.contains { $0.id == "build.google.mapping" && $0.severity == .error })
}

@Test func aReleaseTrackOutsideTheTrackListIsAnError() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        track: "production", tracks: ["internal", "beta"])

    let findings = Validator.findings(input(manifest))

    #expect(findings.contains { $0.id == "build.trackNotListed" && $0.severity == .error })
}

@Test func aDuplicateTrackIsAnError() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(tracks: ["beta", "beta"])

    #expect(Validator.findings(input(manifest)).contains { $0.id == "build.trackDuplicate" })
}

@Test func aMalformedCountryCodeIsAnError() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(countries: ["US", "germany"])

    let findings = Validator.findings(input(manifest))

    #expect(findings.contains { $0.id == "build.country.germany" && $0.severity == .error })
    #expect(!findings.contains { $0.id == "build.country.US" })
}

@Test func anExternallyHostedApkNeedsHttpsAndACertificate() {
    var manifest = sampleManifest()
    manifest.release?.google = Manifest.Release.GoogleRelease(
        externalApk: Manifest.Release.ExternalApk(
            url: "http://example.com/app.apk", applicationLabel: "Example",
            versionCode: 0, versionName: "1.2.0", minimumSdk: 24,
            certificateBase64s: []))

    let findings = Validator.findings(input(manifest))

    #expect(findings.contains { $0.id == "build.externalApk.url" && $0.severity == .error })
    #expect(findings.contains { $0.id == "build.externalApk.certificate" })
    #expect(findings.contains { $0.id == "build.externalApk.versionCode" })
    #expect(findings.contains { $0.id == "build.externalApk.private" && $0.severity == .warning })
}

// MARK: - The manifest

@Test func everyNewGoogleKeySurvivesAYAMLRoundTrip() throws {
    let yaml = """
        version: 1
        apps:
          google:
            packageName: com.example.app
        release:
          versionName: "1.2.0"
          build:
            android: build/app.aab
            androidApk: build/app.apk
          google:
            track: production
            tracks: [internal, production]
            countries: [US, DE]
            includeRestOfWorld: true
            mappingFile: build/mapping.txt
            nativeDebugSymbols: build/symbols.zip
            expansionFileMain: build/main.obb
            expansionFilePatch: build/patch.obb
            externalApk:
              url: https://example.com/app.apk
              applicationLabel: Example
              versionCode: 7
              versionName: "1.2.0"
              minimumSdk: 24
              certificateBase64s: [AAAA]
        """

    let manifest = try ManifestFile.decode(yaml)
    let google = try #require(manifest.release?.google)

    #expect(manifest.release?.build?.androidApk == "build/app.apk")
    #expect(google.tracks == ["internal", "production"])
    #expect(google.countries == ["US", "DE"])
    #expect(google.includeRestOfWorld == true)
    #expect(google.mappingFile == "build/mapping.txt")
    #expect(google.nativeDebugSymbols == "build/symbols.zip")
    #expect(google.expansionFileMain == "build/main.obb")
    #expect(google.expansionFilePatch == "build/patch.obb")
    #expect(google.externalApk?.versionCode == 7)
    #expect(google.externalApk?.certificateBase64s == ["AAAA"])

    // The encoder writes what the decoder read, so a save loses no new key.
    let again = try ManifestFile.decode(try ManifestFile.encode(manifest))
    #expect(again == manifest)
}

@Test func theApplyNeverWritesAnAppleStepForAGoogleArtifact() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var manifest = sampleManifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.release?.build = Manifest.Release.Build(
        androidApk: try makeFile(root, "app.apk"))

    let plan = Planner.plan(Planner.Input(manifest: manifest, actual: ActualState(),
                                          stores: [.apple, .google], root: root))

    #expect(plan.steps(for: .apple).allSatisfy { !$0.id.hasPrefix("google.") })
    #expect(plan.steps(for: .google).contains { $0.id == "google.apk" })
}

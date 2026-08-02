import Foundation
import Testing
@testable import SubmitKit

// The fixtures are real archives, built here with the same tools a developer
// uses. A hand-written byte blob would prove nothing about `unzip` or about
// `pkgutil`.

@Test func anIPAGivesEveryFieldOfTheInfoPlist() throws {
    let ipa = try Fixture.ipa()
    defer { Fixture.clean(ipa) }

    let package = try PackageReader().read(ipa)

    #expect(package.kind == .ipa)
    #expect(package.kind.store == .apple)
    #expect(package.identifier == "com.fastbillsplit.app")
    #expect(package.versionName == "3.2.0")
    #expect(package.buildNumber == "412")
    #expect(package.appName == "Fast Bill Split")
    #expect(package.locales == ["en", "pt-BR"])
    #expect(package.minimumOS == "17.0")
    #expect(package.deviceClasses == ["iPhone", "iPad"])
    #expect(package.usesNonExemptEncryption == false)
    #expect(package.privacyHints == ["NSCameraUsageDescription"])
    #expect(package.filledFieldCount == 9)
}

@Test func aPKGReadsTheAppInsideTheInstaller() throws {
    let pkg = try Fixture.pkg()
    defer { Fixture.clean(pkg) }

    let package = try PackageReader().read(pkg)

    #expect(package.kind == .pkg)
    #expect(package.identifier == "com.fastbillsplit.app")
    #expect(package.versionName == "3.2.0")
    #expect(package.buildNumber == "412")
    #expect(package.minimumOS == "14.0")
    #expect(package.deviceClasses == ["Mac"])
}

@Test func anAABReadsTheProtobufManifest() throws {
    let aab = try Fixture.aab()
    defer { Fixture.clean(aab) }

    let package = try PackageReader().read(aab)

    #expect(package.kind == .aab)
    #expect(package.kind.store == .google)
    #expect(package.identifier == "com.fastbillsplit.app")
    #expect(package.versionName == "3.2.0")
    #expect(package.buildNumber == "412")
    #expect(package.minimumOS == "26")
    #expect(package.appName == "Fast Bill Split")
    #expect(package.privacyHints == ["android.permission.CAMERA",
                                     "android.permission.INTERNET"])
}

@Test func anAABTakesItsLanguagesFromTheResourceFolders() throws {
    let aab = try Fixture.aab()
    defer { Fixture.clean(aab) }

    let package = try PackageReader().read(aab)

    // `values/` names no language. `values-night` and `values-v26` are not
    // languages either, and the reader must not offer them as one.
    #expect(package.locales == ["fr", "pt-BR"])
}

@Test func anUnknownFileTypeSaysWhatItReads() throws {
    let url = URL(fileURLWithPath: "/tmp/build.zip")
    #expect(throws: PackageError.unknownType("zip")) {
        try PackageReader().read(url)
    }
}

@Test func anArchiveWithNoAppInsideNamesTheFile() throws {
    let empty = try Fixture.emptyZip(named: "Broken.ipa")
    defer { Fixture.clean(empty) }

    #expect(throws: PackageError.noAppInside("Broken.ipa")) {
        try PackageReader().read(empty)
    }
}

// MARK: - The fixtures

private enum Fixture {
    static func clean(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("submitkit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func ipa() throws -> URL {
        let root = try scratch()
        let app = root.appendingPathComponent("stage/Payload/FastBillSplit.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try infoPlist(iOS: true).write(to: app.appendingPathComponent("Info.plist"))
        return try zip(root.appendingPathComponent("stage"), to: root.appendingPathComponent("FastBillSplit.ipa"))
    }

    static func pkg() throws -> URL {
        let root = try scratch()
        let app = root.appendingPathComponent("stage/Applications/FastBillSplit.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try infoPlist(iOS: false).write(to: app.appendingPathComponent("Info.plist"))

        let out = root.appendingPathComponent("FastBillSplit.pkg")
        let result = try ProcessRunner().run("/usr/bin/pkgbuild", [
            "--quiet",
            "--root", root.appendingPathComponent("stage").path,
            "--identifier", "com.fastbillsplit.app",
            "--version", "3.2.0",
            out.path,
        ])
        guard result.status == 0 else {
            throw PackageError.unreadable("pkgbuild", result.error)
        }
        return out
    }

    static func aab() throws -> URL {
        let root = try scratch()
        let stage = root.appendingPathComponent("stage")
        let manifest = stage.appendingPathComponent("base/manifest")
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: true)

        let proto = try #require(Bundle.module.url(forResource: "Fixtures/AndroidManifest",
                                                   withExtension: "pb"))
        try Data(contentsOf: proto).write(to: manifest.appendingPathComponent("AndroidManifest.xml"))

        for folder in ["values", "values-fr", "values-pt-rBR", "values-night", "values-v26"] {
            let url = stage.appendingPathComponent("base/res/\(folder)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("<resources/>".utf8).write(to: url.appendingPathComponent("strings.xml"))
        }
        return try zip(stage, to: root.appendingPathComponent("FastBillSplit.aab"))
    }

    static func emptyZip(named name: String) throws -> URL {
        let root = try scratch()
        let stage = root.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try Data("nothing".utf8).write(to: stage.appendingPathComponent("readme.txt"))
        return try zip(stage, to: root.appendingPathComponent(name))
    }

    private static func zip(_ directory: URL, to output: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", output.path, "."]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PackageError.unreadable(output.lastPathComponent, "zip failed")
        }
        return output
    }

    private static func infoPlist(iOS: Bool) throws -> Data {
        var plist: [String: Any] = [
            "CFBundleIdentifier": "com.fastbillsplit.app",
            "CFBundleShortVersionString": "3.2.0",
            "CFBundleVersion": "412",
            "CFBundleDisplayName": "Fast Bill Split",
            "CFBundleLocalizations": ["pt-BR", "en"],
            "NSCameraUsageDescription": "Scan a receipt.",
        ]
        if iOS {
            plist["MinimumOSVersion"] = "17.0"
            plist["UIDeviceFamily"] = [1, 2]
            plist["ITSAppUsesNonExemptEncryption"] = false
        } else {
            plist["LSMinimumSystemVersion"] = "14.0"
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

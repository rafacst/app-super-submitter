import Foundation

/// Reads a build and reports what tab 3 can fill in. Spec section 16.3, tab 2.
///
/// It uses the tools that every Mac ships: `unzip` for the two zip formats,
/// and `pkgutil` for the installer package. It needs no Xcode and no Android
/// SDK, so it runs on the machine that submits, not on the machine that
/// builds.
public struct PackageReader: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func read(_ url: URL) throws -> AppPackage {
        switch url.pathExtension.lowercased() {
        case "ipa": try readIPA(url)
        case "pkg": try readPKG(url)
        case "aab": try readAAB(url)
        case let other: throw PackageError.unknownType(other)
        }
    }

    // MARK: - .ipa

    private func readIPA(_ url: URL) throws -> AppPackage {
        let entries = try zipEntries(url)
        // Payload/<name>.app/Info.plist, and no deeper. A deeper hit is a
        // framework or an app extension, never the app.
        guard let entry = entries.first(where: {
            $0.hasPrefix("Payload/") && $0.hasSuffix(".app/Info.plist")
                && $0.split(separator: "/").count == 3
        }) else {
            throw PackageError.noAppInside(url.lastPathComponent)
        }

        var package = AppPackage(kind: .ipa, url: url)
        try fillFromInfoPlist(try zipEntry(url, entry), into: &package)
        return package
    }

    // MARK: - .pkg

    private func readPKG(_ url: URL) throws -> AppPackage {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("super-submitter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        // `--expand-full` unpacks the payload too, so the .app comes out whole.
        let result = try runner.run("/usr/sbin/pkgutil",
                                    ["--expand-full", url.path, scratch.path])
        guard result.status == 0 else {
            throw PackageError.unreadable(url.lastPathComponent, result.error.trimmed)
        }

        guard let plist = shallowestInfoPlist(in: scratch) else {
            throw PackageError.noAppInside(url.lastPathComponent)
        }

        var package = AppPackage(kind: .pkg, url: url)
        try fillFromInfoPlist(try Data(contentsOf: plist), into: &package)
        if package.deviceClasses.isEmpty { package.deviceClasses = ["Mac"] }
        return package
    }

    /// The shallowest `.app` wins. A deeper one is a helper inside it.
    private func shallowestInfoPlist(in root: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return nil }

        var best: URL?
        var bestDepth = Int.max
        for case let url as URL in walker where url.lastPathComponent == "Info.plist" {
            let parts = url.pathComponents
            guard parts.contains(where: { $0.hasSuffix(".app") }) else { continue }
            if parts.count < bestDepth {
                bestDepth = parts.count
                best = url
            }
        }
        return best
    }

    // MARK: - .aab

    private func readAAB(_ url: URL) throws -> AppPackage {
        let entries = try zipEntries(url)
        let manifestPath = "base/manifest/AndroidManifest.xml"
        guard entries.contains(manifestPath) else {
            throw PackageError.noAppInside(url.lastPathComponent)
        }

        let root = try ProtoManifest.parse(try zipEntry(url, manifestPath))
        var package = AppPackage(kind: .aab, url: url)
        package.identifier = root.attributes["package"]
        package.versionName = root.attributes["versionName"]
        package.buildNumber = root.attributes["versionCode"]
        package.minimumOS = root.firstChild("uses-sdk")?.attributes["minSdkVersion"]
        package.privacyHints = root.childrenNamed("uses-permission")
            .compactMap { $0.attributes["name"] }
            .sorted()

        // A literal `android:label` reads. A `@string/app_name` reference does
        // not, because the value then lives in the resource table. The
        // developer types the name, and tab 3 says where the rest came from.
        if let label = root.firstChild("application")?.attributes["label"],
           !label.hasPrefix("@"), !label.isEmpty {
            package.appName = label
        }

        // The resource folders name the languages. `values/` with no qualifier
        // is the default language, and the bundle does not say which it is.
        package.locales = Set(entries.compactMap(localeFromResourcePath)).sorted()
        return package
    }

    private func localeFromResourcePath(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count > 2, parts[0] == "base", parts[1] == "res" else { return nil }
        let folder = String(parts[2])
        guard folder.hasPrefix("values-") else { return nil }

        // `values-pt-rBR` is `pt-BR`. `values-night` is not a language.
        let qualifier = String(folder.dropFirst("values-".count))
        let pieces = qualifier.split(separator: "-").map(String.init)
        guard let language = pieces.first, language.count == 2 || language.count == 3,
              language.allSatisfy(\.isLowercase) else { return nil }

        if pieces.count > 1, pieces[1].hasPrefix("r"), pieces[1].count == 3 {
            return "\(language)-\(pieces[1].dropFirst())"
        }
        return language
    }

    // MARK: - Info.plist

    private func fillFromInfoPlist(_ data: Data, into package: inout AppPackage) throws {
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, format: nil) as? [String: Any] else {
            throw PackageError.unreadable(package.url.lastPathComponent, "Info.plist is not a dictionary.")
        }

        package.identifier = plist["CFBundleIdentifier"] as? String
        package.versionName = plist["CFBundleShortVersionString"] as? String
        package.buildNumber = plist["CFBundleVersion"] as? String
        package.appName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
        package.locales = (plist["CFBundleLocalizations"] as? [String] ?? []).sorted()
        package.minimumOS = (plist["MinimumOSVersion"] as? String)
            ?? (plist["LSMinimumSystemVersion"] as? String)
        package.usesNonExemptEncryption = plist["ITSAppUsesNonExemptEncryption"] as? Bool
        package.deviceClasses = (plist["UIDeviceFamily"] as? [Int] ?? []).compactMap(Self.deviceName)
        package.privacyHints = plist.keys
            .filter { $0.hasSuffix("UsageDescription") }
            .sorted()
    }

    /// `UIDeviceFamily`, from the Information Property List reference.
    private static func deviceName(_ family: Int) -> String? {
        switch family {
        case 1: "iPhone"
        case 2: "iPad"
        case 3: "Apple TV"
        case 4: "Apple Watch"
        case 6: "CarPlay"
        case 7: "Apple Vision Pro"
        default: nil
        }
    }

    // MARK: - zip

    private func zipEntries(_ url: URL) throws -> [String] {
        let result = try runner.run("/usr/bin/unzip", ["-Z1", url.path])
        guard result.status == 0 else {
            throw PackageError.unreadable(url.lastPathComponent, result.error.trimmed)
        }
        return result.lines
    }

    private func zipEntry(_ url: URL, _ entry: String) throws -> Data {
        let result = try runner.run("/usr/bin/unzip", ["-p", url.path, entry])
        guard result.status == 0, !result.output.isEmpty else {
            throw PackageError.unreadable(url.lastPathComponent,
                                          "The entry \(entry) did not come out.")
        }
        return result.output
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

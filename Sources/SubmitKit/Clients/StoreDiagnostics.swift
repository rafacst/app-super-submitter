import Foundation

/// The reads that answer a question and change nothing.
///
/// None of these belongs in the plan. The plan compares a desired state to an
/// actual state, and none of these is a desired state: they report what a
/// store built, not what the developer asked for.
///
/// `// ponytail: one read-only service. A plan step for a read would show a
/// // diff row that no apply can ever close.`
public struct StoreDiagnostics: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - Google

    public struct GeneratedApk: Sendable, Equatable, Identifiable {
        public var id: String
        public var downloadId: String
        public var kind: String
        public var sizeBytes: Int64?

        public init(id: String, downloadId: String, kind: String, sizeBytes: Int64? = nil) {
            self.id = id
            self.downloadId = downloadId
            self.kind = kind
            self.sizeBytes = sizeBytes
        }
    }

    /// What Google actually built from one App Bundle. The developer reads it
    /// to confirm the split APKs before a release.
    public func generatedApks(packageName: String,
                              versionCode: Int) async throws -> [GeneratedApk] {
        let path = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
            + "/generatedApks/\(versionCode)"
        return Self.parseGeneratedApks(JSON(data: try await api.google("GET", path).data))
    }

    /// Google reports four shapes in one payload. Three are lists and the
    /// universal APK is a single object, so the parser reads both forms.
    static func parseGeneratedApks(_ payload: JSON) -> [GeneratedApk] {
        var result: [GeneratedApk] = []
        for variant in payload["generatedApks"].array {
            for (kind, node) in [("split", variant["generatedSplitApks"]),
                                 ("standalone", variant["generatedStandaloneApks"]),
                                 ("assetPack", variant["generatedAssetPackSlices"]),
                                 ("universal", variant["generatedUniversalApk"])] {
                for entry in node.array {
                    guard let download = entry["downloadId"].string else { continue }
                    result.append(GeneratedApk(
                        id: "\(kind)/\(entry["moduleName"].string ?? download)",
                        downloadId: download, kind: kind))
                }
                if let download = node["downloadId"].string {
                    result.append(GeneratedApk(id: kind, downloadId: download, kind: kind))
                }
            }
        }
        return result
    }

    /// Writes one generated APK to disk and answers where it landed.
    @discardableResult
    public func downloadGeneratedApk(packageName: String, versionCode: Int,
                                     downloadId: String, to directory: URL) async throws -> URL {
        let path = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
            + "/generatedApks/\(versionCode)/downloads/\(StateReader.escape(downloadId)):download"
        let result = try await api.google("GET", path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(downloadId).apk")
        try result.data.write(to: url, options: .atomic)
        return url
    }

    public struct DeviceTierConfig: Sendable, Equatable, Identifiable {
        public var id: String
        public var groupCount: Int

        public init(id: String, groupCount: Int) {
            self.id = id
            self.groupCount = groupCount
        }
    }

    /// The newest device tier configurations. The apply creates a new one
    /// only when the manifest file differs from the newest, and this read is
    /// what tells it.
    public func deviceTierConfigs(packageName: String) async throws -> [DeviceTierConfig] {
        let path = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
            + "/deviceTierConfigs?pageSize=20"
        let payload = JSON(data: try await api.google("GET", path).data)
        return payload["deviceTierConfigs"].array.compactMap { item in
            guard let id = item["deviceTierConfigId"].string
                ?? item["deviceTierConfigId"].int.map(String.init) else { return nil }
            return DeviceTierConfig(id: id,
                                    groupCount: item["deviceGroups"].array.count)
        }
    }

    // MARK: - Apple

    public struct BuildBundle: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String?
        public var kind: String?
        public var fileSizeBytes: Int64?
        public var usesNonExemptEncryption: Bool?

        public init(id: String, name: String? = nil, kind: String? = nil,
                    fileSizeBytes: Int64? = nil, usesNonExemptEncryption: Bool? = nil) {
            self.id = id
            self.name = name
            self.kind = kind
            self.fileSizeBytes = fileSizeBytes
            self.usesNonExemptEncryption = usesNonExemptEncryption
        }
    }

    /// What is inside one processed build: the app bundle, every extension,
    /// the download size, and the icons that Apple extracted.
    public func buildBundles(buildID: String) async throws -> [BuildBundle] {
        let bundles = JSON(data: try await api.apple(
            "GET", "/v1/builds/\(buildID)/buildBundles?limit=200").data)
        var result: [BuildBundle] = []
        for item in bundles["data"].array {
            guard let id = item["id"].string else { continue }
            let attributes = item["attributes"]
            let icons = JSON(data: try await api.apple(
                "GET", "/v1/buildBundles/\(id)/buildBundleFileSizes?limit=200").data)
            let sizes = icons["data"].array
                .compactMap { $0["attributes"]["downloadBytes"].int }
            result.append(BuildBundle(
                id: id,
                name: attributes["bundleId"].string,
                kind: attributes["bundleType"].string,
                fileSizeBytes: sizes.max().map(Int64.init),
                usesNonExemptEncryption: attributes["usesNonExemptEncryption"].bool))
        }
        return result
    }

    /// Every icon that Apple extracted from a build.
    public func buildIcons(buildID: String) async throws -> [String] {
        let icons = JSON(data: try await api.apple(
            "GET", "/v1/builds/\(buildID)/icons?limit=200").data)
        return icons["data"].array.compactMap { $0["attributes"]["iconAsset"]["templateUrl"].string }
    }

    public struct Territory: Sendable, Equatable, Identifiable {
        public var id: String
        public var currency: String?

        public init(id: String, currency: String? = nil) {
            self.id = id
            self.currency = currency
        }
    }

    public struct AppCategory: Sendable, Equatable, Identifiable {
        public var id: String
        public var platform: String?
        public var parentId: String?

        public init(id: String, platform: String? = nil, parentId: String? = nil) {
            self.id = id
            self.platform = platform
            self.parentId = parentId
        }
    }

    public func appCategories(platform: String? = nil) async throws -> [AppCategory] {
        var path = "/v1/appCategories?limit=200"
        if let platform, !platform.isEmpty {
            path += "&filter%5Bplatforms%5D=\(platform)"
        }
        let payload = JSON(data: try await api.apple("GET", path).data)
        return payload["data"].array.compactMap { item in
            guard let id = item["id"].string else { return nil }
            return AppCategory(
                id: id,
                platform: item["attributes"]["platforms"].array.first?.string,
                parentId: item["relationships"]["parent"]["data"]["id"].string)
        }
    }

    /// Every App Store territory. The availability block, the licence
    /// agreement, and the price territory all name one of these ids, and the
    /// developer has no other list to check a code against.
    public func territories() async throws -> [Territory] {
        var path: String? = "/v1/territories?limit=200"
        var result: [Territory] = []
        var seen: Set<String> = []
        while let current = path, seen.insert(current).inserted, result.count < 400 {
            let payload = JSON(data: try await api.apple("GET", current).data)
            for item in payload["data"].array {
                guard let id = item["id"].string else { continue }
                result.append(Territory(id: id,
                                        currency: item["attributes"]["currency"].string))
            }
            path = payload["links"]["next"].string.flatMap(Self.appleNextPath)
        }
        return result
    }

    static func appleNextPath(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              components.host == "api.appstoreconnect.apple.com" else { return nil }
        var path = components.percentEncodedPath
        if let query = components.percentEncodedQuery { path += "?\(query)" }
        return path
    }
}

import Foundation

/// The Google calls that answer a question or take one direct action.
///
/// None of these belongs in the plan. The plan compares a desired state to an
/// actual state, and none of these is a desired state. A review reply, an
/// internal share, and a recovery action each happen once, on a button, and
/// the manifest holds no record of them.
///
/// Two calls here reach real users, and both say so in their own comment. The
/// caller confirms them, the same rule that `ReleaseClient` follows.
///
/// `// ponytail: one client for three small areas. Three clients would repeat
/// // the same package path helper three times.`
public struct GoogleActionsClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - The reviews

    public struct Review: Sendable, Equatable, Identifiable {
        public var id: String
        public var authorName: String?
        public var text: String?
        public var starRating: Int?
        public var lastModified: Date?
        public var developerReply: String?

        public init(id: String, authorName: String? = nil, text: String? = nil,
                    starRating: Int? = nil, lastModified: Date? = nil,
                    developerReply: String? = nil) {
            self.id = id
            self.authorName = authorName
            self.text = text
            self.starRating = starRating
            self.lastModified = lastModified
            self.developerReply = developerReply
        }
    }

    /// The newest reviews. Google returns the reviews of the last week only,
    /// and it returns none for an app that nobody reviewed.
    public func reviews(packageName: String, limit: Int = 100,
                        translationLanguage: String? = nil) async throws -> [Review] {
        var query = [URLQueryItem(name: "maxResults", value: String(min(max(limit, 1), 100)))]
        if let translationLanguage, !translationLanguage.isEmpty {
            query.append(URLQueryItem(name: "translationLanguage", value: translationLanguage))
        }
        let payload = JSON(data: try await api.google(
            "GET", "\(Self.base(packageName))/reviews", query: query).data)
        return payload["reviews"].array.compactMap(Self.parseReview)
    }

    /// One review by its id.
    public func review(packageName: String, reviewId: String,
                       translationLanguage: String? = nil) async throws -> Review? {
        var query: [URLQueryItem] = []
        if let translationLanguage, !translationLanguage.isEmpty {
            query.append(URLQueryItem(name: "translationLanguage", value: translationLanguage))
        }
        let path = "\(Self.base(packageName))/reviews/\(StateReader.escape(reviewId))"
        do {
            return Self.parseReview(JSON(data: try await api.google("GET", path,
                                                                    query: query).data))
        } catch ConnectionError.http(let status, _) where status == 404 {
            return nil
        }
    }

    /// **This publishes public text under the app listing.** Every Play Store
    /// visitor reads it, and a second reply replaces the first one. Confirm
    /// the text with the developer before this runs.
    @discardableResult
    public func replyToReview(packageName: String, reviewId: String,
                              text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConnectionError.http(400, "A review reply cannot be empty.")
        }
        guard trimmed.count <= 350 else {
            throw ConnectionError.http(
                400, "Google accepts 350 characters in a review reply. This one has \(trimmed.count).")
        }
        let payload = JSON(data: try await api.google(
            "POST", "\(Self.base(packageName))/reviews/\(StateReader.escape(reviewId)):reply",
            body: ["replyText": trimmed]).data)
        return payload["result"]["replyText"].string ?? trimmed
    }

    static func parseReview(_ item: JSON) -> Review? {
        guard let id = item["reviewId"].string else { return nil }
        let comment = item["comments"].array.first
        let user = comment?["userComment"] ?? JSON(nil)
        var review = Review(id: id)
        review.authorName = item["authorName"].string
        review.text = user["text"].string
        review.starRating = user["starRating"].int
        if let seconds = user["lastModified"]["seconds"].int {
            review.lastModified = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        review.developerReply = item["comments"].array
            .compactMap { $0["developerComment"]["text"].string }.first
        return review
    }

    // MARK: - Internal app sharing

    public struct SharedArtifact: Sendable, Equatable {
        public var downloadUrl: String
        public var sha256: String?
        public var certificateFingerprint: String?

        public init(downloadUrl: String, sha256: String? = nil,
                    certificateFingerprint: String? = nil) {
            self.downloadUrl = downloadUrl
            self.sha256 = sha256
            self.certificateFingerprint = certificateFingerprint
        }
    }

    /// Uploads an artifact to internal app sharing and answers its download
    /// link.
    ///
    /// This needs no edit, no track, and no version code, so it never collides
    /// with a release. Google keeps the artifact off the store.
    ///
    /// - Parameter isBundle: true for an App Bundle, false for an APK.
    public func shareInternally(packageName: String, artifact: URL,
                                isBundle: Bool) async throws -> SharedArtifact {
        let path = "/upload/androidpublisher/v3/applications/internalappsharing/"
            + "\(StateReader.escape(packageName))/artifacts/\(isBundle ? "bundle" : "apk")"
        let contentType = isBundle
            ? "application/octet-stream"
            : "application/vnd.android.package-archive"
        let payload = JSON(data: try await api.googleUpload(
            path, contentType: contentType, file: artifact).data)
        guard let url = payload["downloadUrl"].string else {
            throw ConnectionError.http(
                502, "Google accepted the artifact and returned no download link.")
        }
        return SharedArtifact(downloadUrl: url,
                              sha256: payload["sha256"].string,
                              certificateFingerprint: payload["certificateFingerprint"].string)
    }

    // MARK: - App recovery

    public struct RecoveryAction: Sendable, Equatable, Identifiable {
        public var id: String
        public var status: String?
        public var createTime: String?
        public var deployTime: String?
        public var cancelTime: String?
        public var targetedVersionCodes: [Int] = []

        public init(id: String, status: String? = nil, createTime: String? = nil,
                    deployTime: String? = nil, cancelTime: String? = nil,
                    targetedVersionCodes: [Int] = []) {
            self.id = id
            self.status = status
            self.createTime = createTime
            self.deployTime = deployTime
            self.cancelTime = cancelTime
            self.targetedVersionCodes = targetedVersionCodes
        }
    }

    /// The recovery actions of one app, or of one version code.
    public func recoveryActions(packageName: String,
                                versionCode: Int? = nil) async throws -> [RecoveryAction] {
        var query: [URLQueryItem] = []
        if let versionCode {
            query.append(URLQueryItem(name: "versionCode", value: String(versionCode)))
        }
        let payload = JSON(data: try await api.google(
            "GET", "\(Self.base(packageName))/appRecoveries", query: query).data)
        return payload["recoveryActions"].array.compactMap(Self.parseRecovery)
    }

    /// Creates a **draft** recovery action. A draft reaches nobody. The
    /// deploy call below is what sends it, and that call is separate for
    /// exactly that reason.
    public func createRecoveryDraft(packageName: String,
                                    versionCodes: [Int]) async throws -> RecoveryAction {
        guard !versionCodes.isEmpty else {
            throw ConnectionError.http(400, "A recovery action needs at least one version code.")
        }
        let payload = JSON(data: try await api.google(
            "POST", "\(Self.base(packageName))/appRecoveries",
            body: [
                "remoteInAppUpdate": ["isRemoteInAppUpdateRequested": true],
                "targeting": ["versionList": ["versionCodes": versionCodes.map(String.init)]],
            ]).data)
        guard let action = Self.parseRecovery(payload) else {
            throw ConnectionError.invalidResponse
        }
        return action
    }

    /// Widens the reach of a draft recovery action. Google adds to the
    /// targeting and never narrows it, so this call only grows the audience.
    public func addRecoveryTargeting(packageName: String, recoveryId: String,
                                     versionCodes: [Int] = [],
                                     regions: [String] = [],
                                     allUsers: Bool = false) async throws {
        var update: [String: Any] = [:]
        if allUsers {
            update["allUsers"] = ["isAllUsersRequested": true]
        } else {
            if !versionCodes.isEmpty {
                update["androidSdks"] = ["sdkLevels": versionCodes.map(String.init)]
            }
            if !regions.isEmpty { update["regions"] = ["regionCode": regions] }
        }
        guard !update.isEmpty else { return }
        try await api.google(
            "POST",
            "\(Self.base(packageName))/appRecoveries/\(StateReader.escape(recoveryId)):addTargeting",
            body: ["targetingUpdate": update])
    }

    /// **This reaches every targeted device.** Google sends the recovery to
    /// real installations, and no call takes it back. `cancelRecovery` stops
    /// a further rollout, and it restores nothing that already landed.
    /// Confirm with the developer before this runs.
    public func deployRecovery(packageName: String, recoveryId: String) async throws {
        try await api.google(
            "POST",
            "\(Self.base(packageName))/appRecoveries/\(StateReader.escape(recoveryId)):deploy",
            body: [:])
    }

    /// Stops a deployed recovery action. Every device that already received
    /// it keeps it.
    public func cancelRecovery(packageName: String, recoveryId: String) async throws {
        try await api.google(
            "POST",
            "\(Self.base(packageName))/appRecoveries/\(StateReader.escape(recoveryId)):cancel",
            body: [:])
    }

    static func parseRecovery(_ item: JSON) -> RecoveryAction? {
        guard let id = item["appRecoveryId"].string
            ?? item["appRecoveryId"].int.map(String.init) else { return nil }
        var action = RecoveryAction(id: id)
        action.status = item["status"].string
        action.createTime = item["createTime"].string
        action.deployTime = item["deployTime"].string
        action.cancelTime = item["cancelTime"].string
        action.targetedVersionCodes = item["targeting"]["versionList"]["versionCodes"].array
            .compactMap { $0.int }
        return action
    }

    // MARK: - The artifacts Google signs

    /// One APK that Google generated from an App Bundle.
    ///
    /// Play signs the APKs it serves, so the file a device installs is never
    /// the one the developer uploaded. These are the ones a developer needs to
    /// reproduce a crash from the store.
    public struct GeneratedAPK: Sendable, Equatable, Identifiable {
        public var id: String
        public var versionCode: Int
        /// `split` names the slice, for example `base` or `config.arm64_v8a`.
        public var kind: String
        public var downloadPath: String

        public init(id: String, versionCode: Int, kind: String, downloadPath: String) {
            self.id = id
            self.versionCode = versionCode
            self.kind = kind
            self.downloadPath = downloadPath
        }
    }

    /// Every APK that Google generated for one version code.
    ///
    /// Google answers 404 for a version code it never generated APKs for,
    /// which is a state and not a failure.
    public func generatedAPKs(packageName: String, versionCode: Int) async throws
        -> [GeneratedAPK] {
        let base = "\(Self.base(packageName))/generatedApks/\(versionCode)"
        let payload: JSON
        do {
            payload = JSON(data: try await api.google("GET", base).data)
        } catch ConnectionError.http(let status, _) where status == 404 {
            return []
        }
        return Self.parseGeneratedAPKs(payload, packageName: packageName,
                                       versionCode: versionCode)
    }

    static func parseGeneratedAPKs(_ payload: JSON, packageName: String,
                                   versionCode: Int) -> [GeneratedAPK] {
        let base = "\(Self.base(packageName))/generatedApks/\(versionCode)"
        func path(_ id: String) -> String {
            "\(base)/downloads/\(StateReader.escape(id)):download"
        }
        var result: [GeneratedAPK] = []
        for item in payload["generatedApks"].array {
            for split in item["generatedSplitApks"].array {
                guard let id = split["downloadId"].string else { continue }
                let module = split["moduleName"].string ?? "base"
                let variant = split["splitId"].string
                result.append(GeneratedAPK(
                    id: id, versionCode: versionCode,
                    kind: variant.map { "\(module).\($0)" } ?? module,
                    downloadPath: path(id)))
            }
            if let id = item["generatedUniversalApk"]["downloadId"].string {
                result.append(GeneratedAPK(id: id, versionCode: versionCode,
                                           kind: "universal", downloadPath: path(id)))
            }
        }
        return result
    }

    /// Downloads one generated APK to `destination` and returns the file.
    ///
    /// The download is a plain read. It writes to the folder the caller names
    /// and it touches nothing in the store.
    @discardableResult
    public func downloadGeneratedAPK(_ apk: GeneratedAPK,
                                     into destination: URL) async throws -> URL {
        let data = try await api.google("GET", apk.downloadPath).data
        try FileManager.default.createDirectory(at: destination,
                                                withIntermediateDirectories: true)
        let file = destination.appendingPathComponent(
            "\(apk.versionCode)-\(apk.kind).apk")
        try data.write(to: file, options: .atomic)
        return file
    }

    static func base(_ packageName: String) -> String {
        "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
    }
}

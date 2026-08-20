import Foundation

/// The remote half of a build and upload. upload-spec 8.8, 8.16, 9.8, 9.14.
///
/// Two rules run through everything here. The app matches a remote build by
/// app, platform, version, and build number, never by "the newest one". And a
/// lost response is never treated as a failure: the app queries the actual
/// state before it acts again.
public struct UploadService: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - Apple

    public struct AppleRemoteCheck: Sendable, Equatable {
        public var appExists = false
        public var appName: String?
        public var bundleIdentifierMatches = false
        public var remoteBundleIdentifier: String?
        public var highestBuildNumber: Int?
        /// The exact build, when it is already there. Then nothing uploads.
        public var existingBuildID: String?
        public var existingBuildProcessed = false
        public var blocking: String?
    }

    /// upload-spec 8.8. Runs before the build and again immediately before the
    /// upload. It never changes a build number.
    public func checkApple(appID: String, platform: BuildPlatform, bundleIdentifier: String,
                           marketingVersion: String,
                           buildVersion: String?) async throws -> AppleRemoteCheck {
        var result = AppleRemoteCheck()
        let app = JSON(data: try await api.apple("GET", "/v1/apps/\(appID)").data)
        result.appExists = app["data"]["id"].string != nil
        result.appName = app["data"]["attributes"]["name"].string
        result.remoteBundleIdentifier = app["data"]["attributes"]["bundleId"].string
        result.bundleIdentifierMatches = result.remoteBundleIdentifier == bundleIdentifier

        guard result.appExists else {
            result.blocking = "App Store Connect holds no app with the id \(appID)."
            return result
        }
        guard result.bundleIdentifierMatches else {
            result.blocking = "The App Store app is \(result.remoteBundleIdentifier ?? "unknown"), and this build is \(bundleIdentifier)."
            return result
        }

        var highest = 0
        for build in try await appleBuilds(appID: appID) {
            let attributes = build["attributes"]
            let version = attributes["version"].string ?? ""
            highest = max(highest, Int(version) ?? 0)
            // The exact object: this app, this marketing version, this build.
            guard let buildVersion, version == buildVersion,
                  build["relationships"]["preReleaseVersion"].exists
                    || attributes["expired"].bool != true else { continue }
            let preRelease = JSON(data: try await api.apple(
                "GET", "/v1/builds/\(build["id"].string ?? "")/preReleaseVersion").data)
            guard Self.applePreReleaseMatches(
                preRelease, marketingVersion: marketingVersion, platform: platform) else {
                continue
            }
            result.existingBuildID = build["id"].string
            result.existingBuildProcessed = attributes["processingState"].string == "VALID"
        }
        result.highestBuildNumber = highest > 0 ? highest : nil

        if result.existingBuildID != nil {
            result.blocking = "Build \(buildVersion ?? "") of \(marketingVersion) already exists in App Store Connect."
        }
        return result
    }

    public enum AppleProcessing: Sendable, Equatable {
        case waitingToAppear
        case processing(buildID: String)
        case processed(buildID: String)
        case failed(buildID: String, detail: String)
    }

    /// Polls for the **exact** app, platform, version, and build number.
    /// It never assumes the newest remote build is this run's build.
    public func appleProcessingState(appID: String, platform: BuildPlatform,
                                     marketingVersion: String,
                                     buildVersion: String) async throws -> AppleProcessing {
        for build in try await appleBuilds(appID: appID)
        where build["attributes"]["version"].string == buildVersion {
            guard let id = build["id"].string else { continue }
            let preRelease = JSON(data: try await api.apple(
                "GET", "/v1/builds/\(id)/preReleaseVersion").data)
            guard Self.applePreReleaseMatches(
                preRelease, marketingVersion: marketingVersion, platform: platform) else {
                continue
            }
            switch build["attributes"]["processingState"].string ?? "PROCESSING" {
            case "VALID": return .processed(buildID: id)
            case "FAILED", "INVALID":
                return .failed(buildID: id,
                               detail: "App Store Connect rejected the build during processing.")
            default: return .processing(buildID: id)
            }
        }
        return .waitingToAppear
    }

    /// Poll fast at first, then back off with jitter. upload-spec 8.16.
    public static func pollDelay(attempt: Int) -> TimeInterval {
        let base = min(300.0, 10.0 * pow(1.6, Double(max(0, attempt - 1))))
        return base + Double.random(in: 0...(base * 0.2))
    }

    /// One build of this app, as the picker on the Build tab draws it.
    public struct RemoteBuild: Sendable, Equatable, Identifiable {
        public var id: String
        /// The build number, which Apple counts inside `version` below.
        public var number: String
        /// The marketing version this build belongs to: its train.
        public var version: String
        public var processed: Bool
        public var state: String
        public var expired: Bool
        public var uploaded: Date?
        /// The state of the App Store version this build is attached to, or nil
        /// when no version holds it.
        ///
        /// Processing is what the store did to the file, and it is all a build
        /// row used to say: every build that finished processing read "Ready",
        /// including the one that shipped a year ago. What a developer wants
        /// from this list is what became of each build, and that is a fact
        /// about the version holding it, not about the file.
        public var versionState: String?

        public init(id: String, number: String, version: String, processed: Bool,
                    state: String, expired: Bool, uploaded: Date? = nil,
                    versionState: String? = nil) {
            self.id = id
            self.number = number
            self.version = version
            self.processed = processed
            self.state = state
            self.expired = expired
            self.uploaded = uploaded
            self.versionState = versionState
        }
    }

    /// Every build App Store Connect holds for one app and one platform.
    ///
    /// The store keeps them and a version takes one, which is what Apple's own
    /// console offers as Add Build. Nothing here writes: the choice lands in
    /// the manifest, and the plan attaches it.
    public func appleBuildChoices(appID: String,
                                  platform: BuildPlatform) async throws -> [RemoteBuild] {
        let wanted = platform == .macos ? "MAC_OS" : "IOS"
        var result: [RemoteBuild] = []
        for page in try await appleBuildPages(appID: appID) {
            // The trains of this page name the marketing version of every
            // build on it, and they drop the other platform's builds.
            let trains = StateReader.appleTrains(page, platform: wanted)
            let versionStates = Self.appleVersionStates(page)
            for build in page["data"].array {
                guard let id = build["id"].string,
                      let train = build["relationships"]["preReleaseVersion"]["data"]["id"]
                        .string.flatMap({ trains[$0] }) else { continue }
                let attributes = build["attributes"]
                let date = attributes["uploadedDate"].string
                result.append(RemoteBuild(
                    id: id,
                    number: attributes["version"].string ?? "",
                    version: train,
                    processed: attributes["processingState"].string == "VALID",
                    state: attributes["processingState"].string ?? "PROCESSING",
                    expired: attributes["expired"].bool == true,
                    uploaded: Date.iso8601(date),
                    versionState: build["relationships"]["appStoreVersion"]["data"]["id"]
                        .string.flatMap { versionStates[$0] }))
            }
        }
        return result
    }

    /// The App Store version id to its state, off the `included` of one page.
    ///
    /// `appVersionState` first and `appStoreState` behind it, which is the
    /// fallback every other reader in this app uses: Apple deprecated the
    /// second and still answers with it on older records.
    static func appleVersionStates(_ page: JSON) -> [String: String] {
        page["included"].array
            .filter { $0["type"].string == "appStoreVersions" }
            .reduce(into: [:]) { result, item in
                guard let id = item["id"].string else { return }
                let attributes = item["attributes"]
                guard let state = attributes["appVersionState"].string
                    ?? attributes["appStoreState"].string else { return }
                result[id] = state
            }
    }

    private func appleBuilds(appID: String) async throws -> [JSON] {
        try await appleBuildPages(appID: appID).flatMap { $0["data"].array }
    }

    /// The pages themselves, because the train of a build lives in the
    /// `included` of the page that carried it.
    private func appleBuildPages(appID: String) async throws -> [JSON] {
        // Both relationships in one request. The train names the marketing
        // version of the build, and the App Store version says what became of
        // it: shipped, in review, or sitting on a draft nobody has sent.
        var path: String? = "/v1/builds?filter%5Bapp%5D=\(appID)"
            + "&include=preReleaseVersion,appStoreVersion&limit=200"
        var pages = 0
        var seen: Set<String> = []
        var result: [JSON] = []
        while let pagePath = path, pages < 100, seen.insert(pagePath).inserted {
            pages += 1
            let page = JSON(data: try await api.apple("GET", pagePath).data)
            result.append(page)
            path = page["links"]["next"].string.flatMap(Self.appleNextPagePath)
        }
        return result
    }

    static func appleNextPagePath(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              components.host == "api.appstoreconnect.apple.com",
              components.path == "/v1/builds" else { return nil }
        var path = components.percentEncodedPath
        if let query = components.percentEncodedQuery { path += "?\(query)" }
        return path
    }

    static func applePreReleaseMatches(_ payload: JSON, marketingVersion: String,
                                       platform: BuildPlatform) -> Bool {
        let attributes = payload["data"]["attributes"]
        let expectedPlatform = platform == .macos ? "MAC_OS" : "IOS"
        return attributes["version"].string == marketingVersion
            && attributes["platform"].string == expectedPlatform
    }

    // MARK: - Google

    public struct GoogleRemoteCheck: Sendable, Equatable {
        public var packageExists = false
        public var trackExists = false
        public var highestVersionCode: Int?
        public var versionCodesInTrack: [Int] = []
        public var blocking: String?
        /// Set when a preflight edit could not be deleted.
        public var strandedEditID: String?
    }

    /// upload-spec 9.8. A read needs an edit, so this opens one and deletes it
    /// in unconditional cleanup.
    public func checkGoogle(packageName: String, track: String,
                            versionCode: Int?) async throws -> GoogleRemoteCheck {
        var result = GoogleRemoteCheck()
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else {
            result.blocking = "Google Play refused an edit for \(packageName)."
            return result
        }
        result.packageExists = true
        let editBase = "\(base)/edits/\(editID)"

        do {
            let tracks = JSON(data: try await api.google("GET", "\(editBase)/tracks").data)
            var codes: [Int] = []
            for item in tracks["tracks"].array {
                let versions = item["releases"].array
                    .flatMap { $0["versionCodes"].array.compactMap(\.int) }
                codes += versions
                if item["track"].string == track {
                    result.trackExists = true
                    result.versionCodesInTrack = versions
                }
            }
            let bundles = JSON(data: try await api.google("GET", "\(editBase)/bundles").data)
            codes += bundles["bundles"].array.compactMap { $0["versionCode"].int }
            // The APKs too. An app that ships a plain APK and has not released
            // it to a track yet showed no version code at all here, so the
            // collision check below waved a duplicate through and Google
            // refused it at the upload instead.
            let apks = JSON(data: try await api.google("GET", "\(editBase)/apks").data)
            codes += apks["apks"].array.compactMap { $0["versionCode"].int }
            result.highestVersionCode = codes.max()

            if let versionCode {
                if codes.contains(versionCode) {
                    result.blocking = "Version code \(versionCode) already exists in Google Play."
                } else if let highest = result.highestVersionCode, versionCode <= highest {
                    result.blocking = "Version code \(versionCode) is not greater than \(highest). Change versionCode in the project; Super Submitter never changes it."
                }
            }
            try await deleteEdit(editBase)
        } catch {
            do { try await deleteEdit(editBase) }
            catch { result.strandedEditID = editID }
            throw error
        }
        return result
    }

    public struct GoogleUploadResult: Sendable, Equatable {
        public var versionCode: Int
        public var editID: String
        public var committed: Bool
    }

    /// upload-spec 9.14. One edit is the transaction. Before a confirmed
    /// commit the edit is disposable, and the cleanup path always runs.
    ///
    /// - Parameter access: the paywall boundary, asked here rather than in the
    ///   view, so the edit is never opened for an account that cannot finish
    ///   the upload.
    public func uploadGoogleBundle(packageName: String, track: String, bundle: URL,
                                   expectedVersionCode: Int, versionName: String?,
                                   access: any AccessGate,
                                   onEditCreated: @Sendable (String) async -> Void = { _ in },
                                   onProgress: @Sendable (Double) -> Void) async throws
        -> GoogleUploadResult {
        try await access.authorize(.storeUpload)
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { throw RunError.missingEdit }
        let editBase = "\(base)/edits/\(editID)"
        await onEditCreated(editID)
        var commitAttempted = false

        do {
            onProgress(0.1)
            let uploadPath = "/upload/androidpublisher/v3/applications/"
                + "\(StateReader.escape(packageName))/edits/\(editID)/bundles"
            let response = JSON(data: try await api.googleUpload(
                uploadPath, contentType: "application/octet-stream", file: bundle).data)
            onProgress(0.7)

            guard let returned = response["versionCode"].int else {
                throw BuildFailure(
                    category: .upload, stage: "Upload the bundle",
                    message: "Google Play accepted the bundle and returned no version code.",
                    retainedRemoteEdit: editID)
            }
            // The returned code must equal the inspected bundle's code.
            guard returned == expectedVersionCode else {
                throw BuildFailure(
                    category: .artifactValidation, stage: "Upload the bundle",
                    message: "Google Play recorded version code \(returned) and the bundle holds \(expectedVersionCode).",
                    recovery: "Build again and upload the exact bundle that this run inspected.",
                    retainedRemoteEdit: editID)
            }

            var release: [String: Any] = [
                "status": "draft",
                "versionCodes": [String(returned)],
            ]
            if let versionName { release["name"] = versionName }
            try await api.google("PATCH", "\(editBase)/tracks/\(track)",
                                 body: ["track": track, "releases": [release]])
            onProgress(0.85)

            try await api.google("POST", "\(editBase):validate", body: [:])
            onProgress(0.95)
            commitAttempted = true
            try await api.google("POST", "\(editBase):commit", body: [:],
                                 query: [URLQueryItem(name: "changesNotSentForReview",
                                                      value: "true")])
            onProgress(1)
            return GoogleUploadResult(versionCode: returned, editID: editID, committed: true)
        } catch {
            // The commit can throw after the server already committed, so a
            // lost response is not a failure. Query the actual state before
            // anything is repeated. upload-spec 9.15.
            if commitAttempted,
               let reconciled = try? await reconcileGoogle(packageName: packageName,
                                                           track: track,
                                                           versionCode: expectedVersionCode),
               reconciled {
                return GoogleUploadResult(versionCode: expectedVersionCode, editID: editID,
                                          committed: true)
            }
            do { try await deleteEdit(editBase) }
            catch {
                throw BuildFailure(
                    category: .cleanup, stage: "Clean up the Google edit",
                    message: "The upload failed and the temporary edit could not be deleted.",
                    underlying: error.localizedDescription,
                    recovery: "Press Retry cleanup. An uncommitted edit is invisible and it expires by itself in about 7 days.",
                    retainedRemoteEdit: editID)
            }
            throw error
        }
    }

    /// True when the version code is present in committed state. Then the
    /// operation succeeded even though its response was lost.
    public func reconcileGoogle(packageName: String, track: String,
                                versionCode: Int) async throws -> Bool {
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { return false }
        let editBase = "\(base)/edits/\(editID)"
        do {
            let tracks = JSON(data: try await api.google("GET", "\(editBase)/tracks").data)
            let landed = Self.googleTrackContainsCommittedVersion(
                tracks, track: track, versionCode: versionCode)
            try await deleteEdit(editBase)
            return landed
        } catch {
            do { try await deleteEdit(editBase) } catch {
                throw BuildFailure(
                    category: .cleanup, stage: "Clean up the reconciliation edit",
                    message: "The Google Play state check opened an edit that could not be deleted.",
                    underlying: error.localizedDescription,
                    retainedRemoteEdit: editID)
            }
            throw error
        }
    }

    static func googleTrackContainsCommittedVersion(_ payload: JSON, track: String,
                                                     versionCode: Int) -> Bool {
        payload["tracks"].array
            .filter { $0["track"].string == track }
            .flatMap { $0["releases"].array }
            .contains { release in
                release["status"].string == "draft"
                    && release["versionCodes"].array.contains { code in
                        code.int == versionCode || code.string.flatMap(Int.init) == versionCode
                    }
            }
    }

    public func deleteEdit(_ editBase: String) async throws {
        try await api.google("DELETE", editBase)
    }

    /// Deletes a stranded edit by its id. The retry is idempotent: an edit
    /// that no longer exists counts as cleaned.
    public func deleteEdit(packageName: String, editID: String) async throws {
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        do {
            try await api.google("DELETE", "\(base)/edits/\(editID)")
        } catch ConnectionError.http(let status, _) where status == 404 || status == 410 {
            return
        }
    }
}

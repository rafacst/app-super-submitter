import Foundation

/// What went wrong in the app, in the two places Apple keeps it.
///
/// `StoreVitalsClient` answers how the shipped app is doing as a number. This
/// answers the question the number raises: which code did it. Apple keeps two
/// separate records of that, and they are not the same thing.
///
/// A **diagnostic signature** is aggregate. Apple groups the hangs, the launch
/// times, and the disk writes of a released build by the call stack that caused
/// them, and each signature carries the anonymized backtraces behind it. It
/// needs a build that enough devices have run, so a fresh build answers with
/// nothing, which is a state and not a failure.
///
/// A **beta feedback submission** is one tester. It arrives the moment somebody
/// on TestFlight sends a screenshot or crashes the app, and it carries their own
/// words with it.
///
/// Every call here is a read. Nothing in this file deletes a submission or
/// changes a build.
public struct AppleDiagnosticsClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - The aggregate signatures of a released build

    /// The three kinds Apple groups a signature under. It publishes no other
    /// value, and no filter is the whole list.
    public static let diagnosticTypes = ["HANGS", "LAUNCHES", "DISK_WRITES"]

    /// One recurring pattern, and how much of the total it accounts for.
    public struct Signature: Sendable, Equatable, Identifiable {
        public var id: String
        /// `HANGS`, `LAUNCHES`, or `DISK_WRITES`.
        public var diagnosticType: String?
        /// The frame Apple blames, as it names it.
        public var signature: String
        /// 0 to 1. Apple's own share of the total, so 0.85 is most of it.
        public var weight: Double?

        public init(id: String, diagnosticType: String? = nil, signature: String,
                    weight: Double? = nil) {
            self.id = id
            self.diagnosticType = diagnosticType
            self.signature = signature
            self.weight = weight
        }

        /// What the row shows beside the name.
        public var share: String? {
            guard let weight else { return nil }
            return String(format: "%.0f %%", weight * 100)
        }
    }

    /// One log behind a signature: the device it came off, and the call stack.
    public struct Log: Sendable, Equatable, Identifiable {
        public var id: String
        public var event: String?
        public var osVersion: String?
        public var appVersion: String?
        public var deviceType: String?
        /// Apple's own one-line summary, for example `Total of 1073.76 MB of
        /// disk writes`.
        public var detail: String?
        /// The call stack, outermost frame first, as Apple already formatted
        /// each line. Only the frames Apple blames on this app are kept: a
        /// backtrace is 40 frames deep and 35 of them are system libraries.
        public var frames: [String] = []

        public init(id: String, event: String? = nil, osVersion: String? = nil,
                    appVersion: String? = nil, deviceType: String? = nil,
                    detail: String? = nil, frames: [String] = []) {
            self.id = id
            self.event = event
            self.osVersion = osVersion
            self.appVersion = appVersion
            self.deviceType = deviceType
            self.detail = detail
            self.frames = frames
        }
    }

    /// The signatures of one build, heaviest first.
    ///
    /// Apple sorts by nothing in particular, and the whole point of the weight
    /// is that one signature is usually most of the problem, so this sorts.
    public func signatures(buildID: String, diagnosticType: String? = nil,
                           limit: Int = 50) async throws -> [Signature] {
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))]
        if let diagnosticType, !diagnosticType.isEmpty {
            query.append(URLQueryItem(name: "filter[diagnosticType]", value: diagnosticType))
        }
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/builds/\(buildID)/diagnosticSignatures", query: query).data)
        return payload["data"].array.compactMap(Self.parseSignature)
            .sorted { ($0.weight ?? 0) > ($1.weight ?? 0) }
    }

    /// The logs behind one signature, parsed to what a developer reads.
    ///
    /// Apple answers this one outside the JSON:API shape: no `data` array, a
    /// `productData` list instead, and the call stack nested arbitrarily deep.
    public func logs(signatureID: String, limit: Int = 5) async throws -> [Log] {
        Self.parseLogs(JSON(data: try await logData(signatureID: signatureID, limit: limit)))
    }

    /// The same answer, untouched, for the developer who wants the file. The
    /// symbol names and the addresses that this app drops on the way to a row
    /// are the half a crash report is read for.
    public func logJSON(signatureID: String, limit: Int = 20) async throws -> Data {
        let data = try await logData(signatureID: signatureID, limit: limit)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .withoutEscapingSlashes]) else { return data }
        return pretty
    }

    private func logData(signatureID: String, limit: Int) async throws -> Data {
        try await api.apple(
            "GET", "/v1/diagnosticSignatures/\(signatureID)/logs",
            query: [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))]).data
    }

    // MARK: - What a TestFlight tester sent

    /// One piece of feedback from one tester.
    ///
    /// Apple keeps the crashes and the screenshots on two resources that carry
    /// the same twenty attributes, so one model reads both.
    public struct Feedback: Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: Kind
        /// What the tester typed. A crash submission usually carries none.
        public var comment: String?
        public var deviceModel: String?
        public var osVersion: String?
        public var appVersion: String?
        public var createdDate: Date?
        public var testerEmail: String?
        /// The screenshots the tester attached. Apple serves each one from a
        /// URL that expires, so nothing here is cached.
        public var screenshots: [URL] = []

        public init(id: String, kind: Kind, comment: String? = nil,
                    deviceModel: String? = nil, osVersion: String? = nil,
                    appVersion: String? = nil, createdDate: Date? = nil,
                    testerEmail: String? = nil, screenshots: [URL] = []) {
            self.id = id
            self.kind = kind
            self.comment = comment
            self.deviceModel = deviceModel
            self.osVersion = osVersion
            self.appVersion = appVersion
            self.createdDate = createdDate
            self.testerEmail = testerEmail
            self.screenshots = screenshots
        }

        public enum Kind: String, Sendable, Equatable { case crash, screenshot }
    }

    /// Every crash and every screenshot a tester sent, newest first.
    ///
    /// One resource that answers an error contributes nothing and never costs
    /// the other one its rows: an account whose key predates the TestFlight
    /// feedback API answers 404 on both, which is a permission state.
    public func feedback(appID: String, limit: Int = 25) async throws
        -> (items: [Feedback], failures: [String]) {
        var items: [Feedback] = []
        var failures: [String] = []
        for (path, kind) in [("betaFeedbackCrashSubmissions", Feedback.Kind.crash),
                             ("betaFeedbackScreenshotSubmissions", .screenshot)] {
            do {
                let payload = JSON(data: try await api.apple(
                    "GET", "/v1/apps/\(appID)/\(path)",
                    query: [URLQueryItem(name: "limit",
                                         value: String(min(max(limit, 1), 200))),
                            URLQueryItem(name: "include", value: "tester"),
                            URLQueryItem(name: "sort", value: "-createdDate")]).data)
                let testers = Self.testerEmails(payload["included"])
                items += payload["data"].array.compactMap {
                    Self.parseFeedback($0, kind: kind, testers: testers)
                }
            } catch {
                failures.append("\(kind == .crash ? "Crashes" : "Screenshots"): \(error.localizedDescription)")
            }
        }
        return (items.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) },
                failures)
    }

    /// The crash log a tester's submission carries.
    ///
    /// Apple puts the whole report in `logText` rather than behind a download
    /// URL, so one call is the file. A submission with no log answers nil,
    /// which is what a screenshot submission does.
    public func crashLog(submissionID: String) async throws -> String? {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/betaFeedbackCrashSubmissions/\(submissionID)/crashLog").data)
        return payload["data"]["attributes"]["logText"].string
    }

    // MARK: - The parsers

    static func parseSignature(_ item: JSON) -> Signature? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Signature(id: id,
                         diagnosticType: attributes["diagnosticType"].string,
                         signature: attributes["signature"].string ?? id,
                         weight: attributes["weight"].double)
    }

    /// `productData[].diagnosticLogs[]`, each one flattened to a row.
    ///
    /// The id comes from the position, because Apple stamps none on a log.
    static func parseLogs(_ payload: JSON) -> [Log] {
        var result: [Log] = []
        for product in payload["productData"].array {
            let signature = product["signatureId"].string ?? ""
            for (index, entry) in product["diagnosticLogs"].array.enumerated() {
                let meta = entry["diagnosticMetaData"]
                result.append(Log(
                    id: "\(signature).\(index)",
                    event: meta["event"].string,
                    osVersion: meta["osVersion"].string,
                    appVersion: meta["appVersion"].string,
                    deviceType: meta["deviceType"].string,
                    detail: meta["eventDetail"].string,
                    frames: blameFrames(entry["callStackTree"])))
            }
        }
        return result
    }

    /// The frames Apple blames on this app, in the order they were called.
    ///
    /// A backtrace is 40 frames deep and most of them are `libdispatch` and
    /// `libsystem`. `isBlameFrame` is Apple's own answer to which line is the
    /// developer's, so the rest are dropped and the whole file stays one
    /// button away.
    static func blameFrames(_ tree: JSON, limit: Int = 12) -> [String] {
        var result: [String] = []
        var stack = tree.array.flatMap { $0["callStacks"].array }
            .flatMap { $0["callStackRootFrames"].array }
        while let frame = stack.first {
            stack.removeFirst()
            if frame["isBlameFrame"].bool == true, result.count < limit {
                result.append(frame["rawFrame"].string
                    ?? frame["symbolName"].string
                    ?? frame["binaryName"].string ?? "")
            }
            stack.append(contentsOf: frame["subFrames"].array)
        }
        return result.filter { !$0.isEmpty }
    }

    /// The tester behind each submission, by the tester's own id.
    static func testerEmails(_ included: JSON) -> [String: String] {
        included.array.reduce(into: [:]) { result, item in
            guard item["type"].string == "betaTesters", let id = item["id"].string,
                  let email = item["attributes"]["email"].string else { return }
            result[id] = email
        }
    }

    static func parseFeedback(_ item: JSON, kind: Feedback.Kind,
                              testers: [String: String]) -> Feedback? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        var feedback = Feedback(id: id, kind: kind)
        feedback.comment = attributes["comment"].string
        feedback.deviceModel = attributes["deviceModel"].string
        feedback.osVersion = attributes["osVersion"].string
        feedback.appVersion = attributes["appVersionString"].string
            ?? attributes["buildBundleId"].string
        feedback.createdDate = attributes["createdDate"].string
            .flatMap(AppleActionsClient.date)
        feedback.testerEmail = attributes["email"].string
            ?? item["relationships"]["tester"]["data"]["id"].string.flatMap { testers[$0] }
        feedback.screenshots = attributes["screenshots"].array
            .compactMap { $0["url"].string.flatMap(URL.init(string:)) }
        return feedback
    }
}

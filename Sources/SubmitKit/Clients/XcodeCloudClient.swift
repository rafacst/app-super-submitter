import Foundation

/// Xcode Cloud. The build service that App Store Connect runs.
///
/// The app already builds locally through `AppleBuildService`. This is the
/// other way to get a build: ask Apple to make one. It belongs beside the
/// local build, not in the plan, because a build run is an action and not a
/// desired state.
///
/// Starting a run costs compute minutes on the developer's account, so the
/// caller confirms it, the same rule the recovery deploy follows.
public struct XcodeCloudClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    public struct Workflow: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var productName: String
        public var enabled: Bool

        public init(id: String, name: String, productName: String, enabled: Bool) {
            self.id = id
            self.name = name
            self.productName = productName
            self.enabled = enabled
        }
    }

    public struct BuildRun: Sendable, Equatable, Identifiable {
        public var id: String
        public var number: Int?
        /// `COMPLETE`, `RUNNING`, `PENDING`.
        public var executionProgress: String?
        /// `SUCCEEDED`, `FAILED`, `ERRORED`, `CANCELED`.
        public var completionStatus: String?
        public var startedAt: Date?

        public init(id: String, number: Int? = nil, executionProgress: String? = nil,
                    completionStatus: String? = nil, startedAt: Date? = nil) {
            self.id = id
            self.number = number
            self.executionProgress = executionProgress
            self.completionStatus = completionStatus
            self.startedAt = startedAt
        }

        /// One word for the row, whichever field carries the answer.
        public var state: String {
            completionStatus ?? executionProgress ?? "unknown"
        }
    }

    /// Every workflow of the products that build this app.
    ///
    /// A team with no Xcode Cloud product answers with an empty list, which is
    /// a state and not a failure.
    public func workflows(appID: String) async throws -> [Workflow] {
        let products = JSON(data: try await api.apple(
            "GET", "/v1/ciProducts?limit=200&include=app").data)
        var result: [Workflow] = []
        for product in products["data"].array {
            guard let productID = product["id"].string,
                  product["relationships"]["app"]["data"]["id"].string == appID else {
                continue
            }
            let name = product["attributes"]["name"].string ?? productID
            guard let response = try? await api.apple(
                "GET", "/v1/ciProducts/\(productID)/workflows?limit=200") else { continue }
            for item in JSON(data: response.data)["data"].array {
                guard let workflow = Self.parseWorkflow(item, productName: name) else {
                    continue
                }
                result.append(workflow)
            }
        }
        return result
    }

    /// **This starts a build on the developer's account and spends compute
    /// minutes.** Nothing takes the minutes back, so the caller confirms it.
    @discardableResult
    public func startBuild(workflowID: String) async throws -> BuildRun {
        let created = JSON(data: try await api.apple("POST", "/v1/ciBuildRuns", body: [
            "data": [
                "type": "ciBuildRuns",
                "relationships": [
                    "workflow": ["data": ["type": "ciWorkflows", "id": workflowID]],
                ],
            ],
        ]).data)
        guard let run = Self.parseRun(created["data"]) else {
            throw ConnectionError.invalidResponse
        }
        return run
    }

    /// The newest runs of one workflow.
    public func recentRuns(workflowID: String, limit: Int = 10) async throws -> [BuildRun] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/ciWorkflows/\(workflowID)/buildRuns?limit=\(min(max(limit, 1), 200))"
                + "&sort=-number").data)
        return payload["data"].array.compactMap(Self.parseRun)
    }

    /// One run, for the poll after a start.
    public func run(id: String) async throws -> BuildRun? {
        let payload = JSON(data: try await api.apple("GET", "/v1/ciBuildRuns/\(id)").data)
        return Self.parseRun(payload["data"])
    }

    // MARK: - Why a run failed

    /// One step inside a run: the build, the tests, the archive, the analysis.
    ///
    /// A run says `FAILED` and nothing else. The action says which step failed
    /// and how many issues it found, which is the first thing a developer
    /// needs and the reason this panel existed only half way before.
    public struct Action: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// `BUILD`, `TEST`, `ARCHIVE`, `ANALYZE`.
        public var actionType: String?
        public var completionStatus: String?
        public var executionProgress: String?
        public var errorCount: Int?
        public var warningCount: Int?
        public var testFailureCount: Int?

        public init(id: String, name: String, actionType: String? = nil,
                    completionStatus: String? = nil, executionProgress: String? = nil,
                    errorCount: Int? = nil, warningCount: Int? = nil,
                    testFailureCount: Int? = nil) {
            self.id = id
            self.name = name
            self.actionType = actionType
            self.completionStatus = completionStatus
            self.executionProgress = executionProgress
            self.errorCount = errorCount
            self.warningCount = warningCount
            self.testFailureCount = testFailureCount
        }

        public var state: String { completionStatus ?? executionProgress ?? "unknown" }

        /// The one line a row shows when a step went wrong. Nil means nothing
        /// is worth saying, which is what a clean step looks like.
        public var issues: String? {
            var parts: [String] = []
            if let errorCount, errorCount > 0 { parts.append("\(errorCount) errors") }
            if let testFailureCount, testFailureCount > 0 {
                parts.append("\(testFailureCount) test failures")
            }
            if let warningCount, warningCount > 0 { parts.append("\(warningCount) warnings") }
            return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
        }
    }

    /// One file the run produced: the archive, the logs, the test products.
    public struct Artifact: Sendable, Equatable, Identifiable {
        public var id: String
        public var fileName: String
        /// `ARCHIVE`, `LOG_BUNDLE`, `RESULT_BUNDLE`, and the rest.
        public var fileType: String?
        public var fileSize: Int?
        /// Apple serves it from a URL that expires, so nothing is cached here
        /// and the panel opens it in a browser.
        public var downloadURL: URL?

        public init(id: String, fileName: String, fileType: String? = nil,
                    fileSize: Int? = nil, downloadURL: URL? = nil) {
            self.id = id
            self.fileName = fileName
            self.fileType = fileType
            self.fileSize = fileSize
            self.downloadURL = downloadURL
        }
    }

    /// One test that did not pass. A test that passed is not news.
    public struct TestFailure: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var className: String?
        public var status: String?
        public var message: String?

        public init(id: String, name: String, className: String? = nil,
                    status: String? = nil, message: String? = nil) {
            self.id = id
            self.name = name
            self.className = className
            self.status = status
            self.message = message
        }
    }

    /// The steps of one run, in the order Xcode Cloud performed them.
    public func actions(runID: String) async throws -> [Action] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/ciBuildRuns/\(runID)/actions",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseAction)
    }

    public func artifacts(actionID: String) async throws -> [Artifact] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/ciBuildActions/\(actionID)/artifacts",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseArtifact)
    }

    /// The failing tests of one action.
    ///
    /// A green run returns hundreds of passes, and none of them is why anybody
    /// opened this panel, so the passes are dropped here rather than drawn.
    public func testFailures(actionID: String) async throws -> [TestFailure] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/ciBuildActions/\(actionID)/testResults",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseTestResult)
            .filter { ($0.status ?? "SUCCESS") != "SUCCESS" }
    }

    // MARK: - What the workflow is wired to

    /// One connected repository, with the branch or the pull request that a
    /// run would build.
    public struct Repository: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var owner: String?
        /// The branches and the tags, and the open pull requests.
        public var references: [String] = []
        public var pullRequests: [String] = []

        public init(id: String, name: String, owner: String? = nil,
                    references: [String] = [],
                    pullRequests: [String] = []) {
            self.id = id
            self.name = name
            self.owner = owner
            self.references = references
            self.pullRequests = pullRequests
        }
    }

    /// Every repository App Store Connect can see, with its branches and its
    /// open pull requests.
    ///
    /// A team with no source-control connection answers an empty list, which
    /// is a state and not a failure.
    public func repositories(limit: Int = 20) async throws -> [Repository] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/scmRepositories",
            query: [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))]).data)
        var result: [Repository] = []
        for item in payload["data"].array {
            guard var repository = Self.parseRepository(item),
                  let id = item["id"].string else { continue }
            if let response = try? await api.apple(
                "GET", "/v1/scmRepositories/\(id)/gitReferences",
                query: [URLQueryItem(name: "limit", value: "50")]) {
                repository.references = JSON(data: response.data)["data"].array
                    .compactMap { $0["attributes"]["name"].string }
            }
            if let response = try? await api.apple(
                "GET", "/v1/scmRepositories/\(id)/pullRequests",
                query: [URLQueryItem(name: "limit", value: "50")]) {
                repository.pullRequests = JSON(data: response.data)["data"].array
                    .filter { $0["attributes"]["isClosed"].bool != true }
                    .compactMap { item in
                        let title = item["attributes"]["title"].string ?? ""
                        guard let number = item["attributes"]["number"].int else { return title }
                        return "#\(number)  \(title)"
                    }
            }
            result.append(repository)
        }
        return result
    }

    /// Turns a workflow on, or off again.
    ///
    /// This is the whole of the workflow write. Creating one takes the Xcode
    /// version, the macOS version, the actions, the start conditions, the
    /// repository, and the branch, which is a form that belongs in Xcode where
    /// the developer is already standing.
    ///
    /// `// ponytail: the switch, not the form. Add POST /v1/ciWorkflows when
    /// // somebody wants to author a workflow away from Xcode.`
    public func setWorkflowEnabled(workflowID: String, _ enabled: Bool) async throws {
        try await api.apple("PATCH", "/v1/ciWorkflows/\(workflowID)", body: [
            "data": ["type": "ciWorkflows", "id": workflowID,
                     "attributes": ["isEnabled": enabled]],
        ])
    }

    // MARK: - The parsers

    static func parseAction(_ item: JSON) -> Action? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        let counts = attributes["issueCounts"]
        return Action(id: id,
                      name: attributes["name"].string ?? id,
                      actionType: attributes["actionType"].string,
                      completionStatus: attributes["completionStatus"].string,
                      executionProgress: attributes["executionProgress"].string,
                      errorCount: counts["errors"].int,
                      warningCount: counts["warnings"].int,
                      testFailureCount: counts["testFailures"].int)
    }

    static func parseArtifact(_ item: JSON) -> Artifact? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Artifact(id: id,
                        fileName: attributes["fileName"].string ?? id,
                        fileType: attributes["fileType"].string,
                        fileSize: attributes["fileSize"].int,
                        downloadURL: attributes["downloadUrl"].string
                            .flatMap(URL.init(string:)))
    }

    static func parseTestResult(_ item: JSON) -> TestFailure? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return TestFailure(id: id,
                           name: attributes["name"].string ?? id,
                           className: attributes["className"].string,
                           status: attributes["status"].string,
                           message: attributes["message"].string)
    }

    static func parseRepository(_ item: JSON) -> Repository? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return Repository(id: id,
                          name: attributes["repositoryName"].string ?? id,
                          owner: attributes["ownerName"].string)
    }

    static func parseWorkflow(_ item: JSON, productName: String) -> Workflow? {
        let attributes = item["attributes"]
        guard let id = item["id"].string, let name = attributes["name"].string else {
            return nil
        }
        return Workflow(id: id, name: name, productName: productName,
                        enabled: attributes["isEnabled"].bool ?? true)
    }

    static func parseRun(_ item: JSON) -> BuildRun? {
        guard let id = item["id"].string else { return nil }
        let attributes = item["attributes"]
        return BuildRun(
            id: id,
            number: attributes["number"].int,
            executionProgress: attributes["executionProgress"].string,
            completionStatus: attributes["completionStatus"].string,
            startedAt: attributes["startedDate"].string.flatMap(AppleActionsClient.date))
    }
}

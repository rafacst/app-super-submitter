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

    // MARK: - The parsers

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

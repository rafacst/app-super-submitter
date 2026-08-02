import Foundation

/// The two irreversible calls. Spec section 7.9.
///
/// Each method releases **one** store. There is no method here that releases
/// both, and nothing chains the two, because a failure between two
/// irreversible calls leaves one store in review and one store not.
public struct ReleaseClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// Step 4 is the point of no return. Steps 1 to 3 are reversible.
    public func releaseApple(appID: String, platform: String,
                             versionID: String) async throws -> String {
        let submission = JSON(data: try await api.apple("POST", "/v1/reviewSubmissions", body: [
            "data": [
                "type": "reviewSubmissions",
                "attributes": ["platform": platform],
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
            ],
        ]).data)
        guard let submissionID = submission["data"]["id"].string else {
            throw ConnectionError.invalidResponse
        }

        try await api.apple("POST", "/v1/reviewSubmissionItems", body: [
            "data": [
                "type": "reviewSubmissionItems",
                "relationships": [
                    "reviewSubmission": ["data": ["type": "reviewSubmissions",
                                                  "id": submissionID]],
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]],
                ],
            ],
        ])

        // The purchases join the same submission, so one Apple review covers
        // the version and the purchases together.
        let purchases = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/inAppPurchasesV2?limit=200").data)
        for purchase in purchases["data"].array {
            guard let versionId = purchase["relationships"]["inAppPurchaseVersion"]["data"]["id"]
                .string else { continue }
            // A purchase that Apple refuses to add is not a reason to abandon
            // the version submission. Step 4 still holds the whole decision.
            _ = try? await api.apple("POST", "/v1/reviewSubmissionItems", body: [
                "data": [
                    "type": "reviewSubmissionItems",
                    "relationships": [
                        "reviewSubmission": ["data": ["type": "reviewSubmissions",
                                                      "id": submissionID]],
                        "inAppPurchaseV2": ["data": ["type": "inAppPurchases", "id": versionId]],
                    ],
                ],
            ])
        }

        try await api.apple("PATCH", "/v1/reviewSubmissions/\(submissionID)", body: [
            "data": ["type": "reviewSubmissions", "id": submissionID,
                     "attributes": ["submitted": true]],
        ])
        return submissionID
    }

    /// The recovery, and its limit: this works only before the review starts.
    public func cancelAppleSubmission(id: String) async throws {
        try await api.apple("PATCH", "/v1/reviewSubmissions/\(id)", body: [
            "data": ["type": "reviewSubmissions", "id": id, "attributes": ["canceled": true]],
        ])
    }

    /// Step 3 is the point of no return.
    ///
    /// Google treats `versionCodes` as the complete list, not as an addition.
    /// A missing code drops that build from the track, so the app reads the
    /// track first and carries the full list back.
    public func releaseGoogle(packageName: String, track: String, status: String,
                              userFraction: Double?, versionName: String?) async throws -> String {
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { throw ConnectionError.invalidResponse }
        let editBase = "\(base)/edits/\(editID)"

        do {
            let current = JSON(data: try await api.google("GET", "\(editBase)/tracks/\(track)").data)
            let release = current["releases"].array.first
            let codes = release?["versionCodes"].array.compactMap(\.int) ?? []
            guard !codes.isEmpty else {
                throw ConnectionError.http(409, "The \(track) track holds no draft release.")
            }

            var body: [String: Any] = [
                "status": status,
                "versionCodes": codes.map(String.init),
            ]
            if status == "inProgress", let userFraction {
                body["userFraction"] = userFraction
            }
            if let name = versionName { body["name"] = name }
            if let notes = release?["releaseNotes"].array, !notes.isEmpty {
                body["releaseNotes"] = notes.map { note in
                    ["language": note["language"].string ?? "en-US",
                     "text": note["text"].string ?? ""]
                }
            }
            try await api.google("PATCH", "\(editBase)/tracks/\(track)",
                                 body: ["track": track, "releases": [body]])

            // No `changesNotSentForReview` this time. That is the difference
            // between an apply and a release.
            try await api.google("POST", "\(editBase):commit", body: [:])
            return editID
        } catch {
            _ = try? await api.google("DELETE", editBase)
            throw error
        }
    }

    /// The Google recovery, and its limit: a staged rollout only.
    public func haltGoogleRollout(packageName: String, track: String) async throws {
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        let edit = JSON(data: try await api.google("POST", "\(base)/edits", body: [:]).data)
        guard let editID = edit["id"].string else { throw ConnectionError.invalidResponse }
        let editBase = "\(base)/edits/\(editID)"
        do {
            let current = JSON(data: try await api.google("GET", "\(editBase)/tracks/\(track)").data)
            let codes = current["releases"][0]["versionCodes"].array.compactMap(\.int)
            try await api.google("PATCH", "\(editBase)/tracks/\(track)", body: [
                "track": track,
                "releases": [["status": "halted", "versionCodes": codes.map(String.init)]],
            ])
            try await api.google("POST", "\(editBase):commit", body: [:])
        } catch {
            _ = try? await api.google("DELETE", editBase)
            throw error
        }
    }
}

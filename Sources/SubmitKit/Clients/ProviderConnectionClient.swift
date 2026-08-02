import Foundation

public struct ProviderConnectionClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func testRevenueCat(apiKey: String, projectID: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderConnectionError.missingAPIKey }
        guard !projectID.isEmpty else { throw ProviderConnectionError.missingProjectID }
        guard let url = URL(string: "https://api.revenuecat.com/v2/projects/\(projectID)/apps") else {
            throw ProviderConnectionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["message"] as? String }
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ProviderConnectionError.http(http.statusCode, message)
        }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let count = (object?["items"] as? [Any])?.count ?? 0
        return "Authenticated · \(count) \(count == 1 ? "app" : "apps") visible; write scopes not yet verified"
    }
}

public struct AdaptyCLIClient: Sendable {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessRunner()) { self.runner = runner }

    public func status() throws -> String {
        let lookup = try runner.run("/usr/bin/which", ["adapty"])
        guard lookup.status == 0, let executable = lookup.lines.first else {
            throw ProviderConnectionError.adaptyMissing
        }
        let status = try runner.run(executable, ["auth", "status", "--json"])
        guard status.status == 0 else {
            throw ProviderConnectionError.adapty(status.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let who = try runner.run(executable, ["auth", "whoami", "--json"])
        guard who.status == 0 else {
            throw ProviderConnectionError.adapty(who.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let json = try? JSONSerialization.jsonObject(with: who.output) as? [String: Any],
           let email = json["email"] as? String ?? json["user"] as? String {
            return "Logged in as \(email)"
        }
        let text = who.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Logged in" : text
    }
}

public enum ProviderConnectionError: Error, LocalizedError {
    case missingAPIKey
    case missingProjectID
    case invalidResponse
    case http(Int, String)
    case adaptyMissing
    case adapty(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Enter the RevenueCat secret v2 API key."
        case .missingProjectID: "Enter the RevenueCat project id."
        case .invalidResponse: "The provider returned an invalid response."
        case .http(let status, let message): "RevenueCat returned HTTP \(status): \(message)"
        case .adaptyMissing: "The adapty CLI is not installed or is not on PATH."
        case .adapty(let message): message.isEmpty ? "The adapty CLI is not logged in." : message
        }
    }
}

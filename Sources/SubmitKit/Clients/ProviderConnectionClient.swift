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

    /// What the plan needs to know about the Adapty catalog. Spec 7.8.2,
    /// steps 2 to 8. Every command here is a `list` or a `get`.
    public struct Catalog: Sendable {
        public var productIds: [String: String] = [:]
        public var accessLevels: Set<String> = []
        public var placements: Set<String> = []
        public var paywalls: [String: String] = [:]
        public var appIdentifiers: [String: String] = [:]
    }

    public func catalog(appID: String) throws -> Catalog {
        var result = Catalog()
        let app = try json(["apps", "get", appID])
        result.appIdentifiers["apple"] = app["apple-bundle-id"].string
            ?? app["apple_bundle_id"].string
        result.appIdentifiers["google"] = app["google-bundle-id"].string
            ?? app["google_bundle_id"].string

        for level in items(try json(["access-levels", "list", "--app", appID])) {
            guard let key = level["sdk_id"].string ?? level["sdk-id"].string else { continue }
            result.accessLevels.insert(key)
        }
        for product in items(try json(["products", "list", "--app", appID])) {
            guard let id = product["id"].string else { continue }
            for key in [product["ios_product_id"].string, product["android_product_id"].string,
                        product["ios-product-id"].string, product["android-product-id"].string] {
                guard let key, !key.isEmpty else { continue }
                result.productIds[key] = id
            }
        }
        for paywall in items(try json(["paywalls", "list", "--app", appID])) {
            guard let id = paywall["id"].string else { continue }
            result.paywalls[paywall["title"].string ?? id] = id
        }
        for placement in items(try json(["placements", "list", "--app", appID])) {
            guard let key = placement["developer_id"].string ?? placement["id"].string else {
                continue
            }
            result.placements.insert(key)
        }
        return result
    }

    /// Runs one Adapty command and returns its JSON. Spec section 14: the app
    /// never retries an Adapty command, because a repeated create duplicates.
    @discardableResult
    public func json(_ arguments: [String]) throws -> JSON {
        let lookup = try runner.run("/usr/bin/which", ["adapty"])
        guard lookup.status == 0, let executable = lookup.lines.first else {
            throw ProviderConnectionError.adaptyMissing
        }
        var full = arguments
        if !full.contains("--json") { full.append("--json") }
        if arguments.contains("list"), !full.contains("--page-size") {
            full += ["--page-size", "100"]
        }
        let result = try runner.run(executable, full)
        guard result.status == 0 else {
            throw ProviderConnectionError.adapty(
                result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return JSON(data: result.output)
    }

    private func items(_ json: JSON) -> [JSON] {
        json["data"].array.isEmpty
            ? (json["items"].array.isEmpty ? json.array : json["items"].array)
            : json["data"].array
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
        case .invalidResponse:
            "RevenueCat answered with something this app could not read. Try again in a moment."
        case .http(let status, let message):
            // The same three questions the stores get: who you are, what you
            // asked for, or the service itself. Not the number.
            switch status {
            case 401, 403:
                "RevenueCat did not accept the API key. Check the secret v2 key in Settings."
            case 404:
                "RevenueCat holds no record of this. Check the project id in Settings."
            case 429:
                "RevenueCat is holding this account back for a moment. Wait a minute and try again."
            case 500...599:
                "RevenueCat is having trouble on its own side. Try again in a few minutes."
            default:
                "RevenueCat refused this. "
                    + ConnectionError.sentence(from: message)
            }
        case .adaptyMissing: "The adapty CLI is not installed or is not on PATH."
        case .adapty(let message): message.isEmpty ? "The adapty CLI is not logged in." : message
        }
    }
}

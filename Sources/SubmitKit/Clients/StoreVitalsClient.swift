import Foundation

/// How the shipped app is doing, from both stores.
///
/// Every call here is a read. Nothing in this file changes a listing, a price,
/// a build, or a customer record. It answers one question that the rest of the
/// app cannot: the release landed, so is it healthy.
///
/// Google keeps this on the Play Developer Reporting API, which is a different
/// host and a different scope from the Publishing API. Apple keeps it on the
/// build, and it answers 404 for a build with no report yet, which is a state
/// and not a failure.
public struct StoreVitalsClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    /// One measured value, with the window it covers.
    public struct Metric: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        /// The formatted value, for example `0.42 %` or `112 ms`.
        public var value: String
        public var detail: String?

        public init(name: String, value: String, detail: String? = nil) {
            self.name = name
            self.value = value
            self.detail = detail
        }
    }

    // MARK: - Google Play

    /// The crash rate and the ANR rate of the last 28 days.
    ///
    /// Google returns one row per day, so this averages the rows it gets and
    /// says how many days it covered.
    public func googleVitals(packageName: String) async throws -> [Metric] {
        var result: [Metric] = []
        for (set, label) in [("crashRateMetricSet", "User-perceived crash rate"),
                             ("anrRateMetricSet", "User-perceived ANR rate")] {
            let metric = set == "crashRateMetricSet"
                ? "userPerceivedCrashRate" : "userPerceivedAnrRate"
            guard let response = try? await api.googleReporting(
                "POST", "/v1beta1/apps/\(StateReader.escape(packageName))/\(set):query",
                body: [
                    "metrics": [metric],
                    "dimensions": [],
                    "pageSize": 100,
                ]) else { continue }
            let rows = JSON(data: response.data)["rows"].array
            guard let average = Self.average(rows, metric: metric) else { continue }
            result.append(Metric(name: label,
                                 value: Self.percent(average),
                                 detail: "\(rows.count) days"))
        }
        return result
    }

    /// The mean of one metric across the returned rows.
    static func average(_ rows: [JSON], metric: String) -> Double? {
        let values = rows.compactMap { row -> Double? in
            guard let entry = row["metrics"].array
                .first(where: { $0["metric"].string == metric }) else { return nil }
            return entry["decimalValue"]["value"].string.flatMap(Double.init)
                ?? entry["decimalValue"]["value"].double
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Google reports a rate as a fraction, and a reader wants a percentage.
    static func percent(_ value: Double) -> String {
        String(format: "%.2f %%", value * 100)
    }

    // MARK: - The App Store

    /// The power and performance metrics of one build.
    ///
    /// Apple reports these once enough devices have sent data, so a fresh
    /// build answers with nothing. That is a state, not a failure.
    public func appleVitals(buildID: String) async throws -> [Metric] {
        guard let response = try? await api.apple(
            "GET", "/v1/builds/\(buildID)/perfPowerMetrics") else { return [] }
        return Self.parseAppleMetrics(JSON(data: response.data))
    }

    static func parseAppleMetrics(_ payload: JSON) -> [Metric] {
        var result: [Metric] = []
        for item in payload["productData"].array {
            for metric in item["metricCategories"].array {
                guard let category = metric["identifier"].string else { continue }
                for measure in metric["metrics"].array {
                    guard let unit = measure["unit"].string else { continue }
                    let value = measure["datasets"].array.first?["points"]
                        .array.first?["value"].double
                    guard let value else { continue }
                    result.append(Metric(
                        name: "\(Self.title(category))  \(Self.title(measure["identifier"].string ?? ""))",
                        value: "\(Self.trim(value)) \(unit)",
                        detail: measure["goalKeys"].array.first?["goalKey"].string))
                }
            }
        }
        return result
    }

    /// `LAUNCH_TIME` becomes `Launch time`, which is what a reader wants.
    static func title(_ identifier: String) -> String {
        let words = identifier.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func trim(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.2f", value)
    }

    // MARK: - The refunds Google already issued

    /// The purchases that Google voided: a refund, a chargeback, or a
    /// developer cancellation.
    ///
    /// This is a read, and it is the whole of the commerce surface this app
    /// touches. Issuing a refund moves real money to a customer, so the app
    /// never sends that call and the developer does it in the Play Console.
    public func googleVoidedPurchases(packageName: String,
                                      limit: Int = 100) async throws -> [Voided] {
        let payload = JSON(data: try await api.google(
            "GET",
            "/androidpublisher/v3/applications/\(StateReader.escape(packageName))/purchases/voidedpurchases",
            query: [URLQueryItem(name: "maxResults", value: String(min(max(limit, 1), 1000)))]).data)
        return payload["voidedPurchases"].array.compactMap(Self.parseVoided)
    }

    public struct Voided: Sendable, Equatable, Identifiable {
        public var id: String
        public var orderId: String?
        public var voidedAt: Date?
        /// `Other`, `Remorse`, `Not received`, `Defective`, `Accidental
        /// purchase`, `Fraud`, `Friendly fraud`, or `Chargeback`.
        public var reason: String?
        public var source: String?

        public init(id: String, orderId: String? = nil, voidedAt: Date? = nil,
                    reason: String? = nil, source: String? = nil) {
            self.id = id
            self.orderId = orderId
            self.voidedAt = voidedAt
            self.reason = reason
            self.source = source
        }
    }

    static let voidedReasons = ["Other", "Remorse", "Not received", "Defective",
                                "Accidental purchase", "Fraud", "Friendly fraud",
                                "Chargeback"]
    static let voidedSources = ["User", "Developer", "Google"]

    static func parseVoided(_ item: JSON) -> Voided? {
        guard let token = item["purchaseToken"].string ?? item["orderId"].string else {
            return nil
        }
        var result = Voided(id: token)
        result.orderId = item["orderId"].string
        if let millis = item["voidedTimeMillis"].string.flatMap(Double.init) {
            result.voidedAt = Date(timeIntervalSince1970: millis / 1000)
        }
        if let reason = item["voidedReason"].int, voidedReasons.indices.contains(reason) {
            result.reason = voidedReasons[reason]
        }
        if let source = item["voidedSource"].int, voidedSources.indices.contains(source) {
            result.source = voidedSources[source]
        }
        return result
    }
}

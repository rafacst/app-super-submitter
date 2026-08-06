import Foundation

/// The three report families that App Store Connect publishes: the analytics
/// reports, the sales reports, and the finance reports.
///
/// Everything here is a read except one call. `requestAnalytics` creates an
/// analytics report request, which is how Apple starts a report feed for an
/// app. It writes nothing to a listing, it reaches no customer, and deleting
/// the request stops the feed again, so it is the mildest write in the app.
///
/// None of this is a desired state. A report is what the store measured, and
/// the manifest holds what the developer wants, so nothing here reaches
/// `store.yaml` or a plan row.
public struct AppleReportsClient: Sendable {
    private let api: StoreAPI

    public init(api: StoreAPI) {
        self.api = api
    }

    // MARK: - The analytics report feed

    /// One report feed. Apple fills it in the background and the first
    /// instance appears a day or two later, which is a state and not a fault.
    public struct Feed: Sendable, Equatable, Identifiable {
        public var id: String
        /// `ONE_TIME_SNAPSHOT` or `ONGOING`.
        public var accessType: String
        /// Apple stops an ongoing feed that nobody reads.
        public var stoppedDueToInactivity: Bool

        public init(id: String, accessType: String,
                    stoppedDueToInactivity: Bool = false) {
            self.id = id
            self.accessType = accessType
            self.stoppedDueToInactivity = stoppedDueToInactivity
        }
    }

    public struct Report: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// `APP_USAGE`, `APP_STORE_ENGAGEMENT`, `COMMERCE`, `FRAMEWORK_USAGE`,
        /// or `PERFORMANCE`.
        public var category: String?

        public init(id: String, name: String, category: String? = nil) {
            self.id = id
            self.name = name
            self.category = category
        }
    }

    public struct Instance: Sendable, Equatable, Identifiable {
        public var id: String
        /// `DAILY`, `WEEKLY`, or `MONTHLY`.
        public var granularity: String?
        public var processingDate: String?

        public init(id: String, granularity: String? = nil,
                    processingDate: String? = nil) {
            self.id = id
            self.granularity = granularity
            self.processingDate = processingDate
        }
    }

    /// One downloadable piece of one instance. Apple splits a large report
    /// across several, and each carries its own URL.
    public struct Segment: Sendable, Equatable, Identifiable {
        public var id: String
        public var url: String?
        public var sizeInBytes: Int
        public var checksum: String?

        public init(id: String, url: String? = nil, sizeInBytes: Int = 0,
                    checksum: String? = nil) {
            self.id = id
            self.url = url
            self.sizeInBytes = sizeInBytes
            self.checksum = checksum
        }
    }

    /// The report feeds that already exist for this app.
    public func analyticsFeeds(appID: String) async throws -> [Feed] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appID)/analyticsReportRequests",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseFeed)
    }

    /// **This creates a report feed on the account.** The panel confirms it
    /// first. It is reversible: `stopAnalytics` deletes the request and Apple
    /// stops filling it.
    ///
    /// `ongoing` asks Apple to keep the feed current. The alternative is one
    /// snapshot of the last year.
    @discardableResult
    public func requestAnalytics(appID: String, ongoing: Bool) async throws -> Feed? {
        let payload = JSON(data: try await api.apple(
            "POST", "/v1/analyticsReportRequests", body: [
                "data": [
                    "type": "analyticsReportRequests",
                    "attributes": [
                        "accessType": ongoing ? "ONGOING" : "ONE_TIME_SNAPSHOT",
                    ],
                    "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
                ],
            ]).data)
        return Self.parseFeed(payload["data"])
    }

    /// Stops a feed. Apple keeps every report it already produced.
    public func stopAnalytics(feedID: String) async throws {
        try await api.apple("DELETE", "/v1/analyticsReportRequests/\(feedID)")
    }

    public func reports(feedID: String) async throws -> [Report] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/analyticsReportRequests/\(feedID)/reports",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseReport)
    }

    public func instances(reportID: String) async throws -> [Instance] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/analyticsReports/\(reportID)/instances",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseInstance)
    }

    public func segments(instanceID: String) async throws -> [Segment] {
        let payload = JSON(data: try await api.apple(
            "GET", "/v1/analyticsReportInstances/\(instanceID)/segments",
            query: [URLQueryItem(name: "limit", value: "200")]).data)
        return payload["data"].array.compactMap(Self.parseSegment)
    }

    // MARK: - The sales and the finance reports

    /// One sales report, unpacked to text.
    ///
    /// Apple answers 404 for a date it has no report for, which is a state and
    /// not a failure: the daily report of today does not exist yet.
    ///
    /// `reportDate` is `YYYY-MM-DD` for a daily report, `YYYY-MM-DD` of any day
    /// in the week for a weekly one, `YYYY-MM` for a monthly one, and `YYYY`
    /// for a yearly one.
    public func salesReport(vendorNumber: String,
                            reportType: String = "SALES",
                            reportSubType: String = "SUMMARY",
                            frequency: String = "DAILY",
                            reportDate: String? = nil,
                            version: String = "1_0") async throws -> String {
        var query = [
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[reportType]", value: reportType),
            URLQueryItem(name: "filter[reportSubType]", value: reportSubType),
            URLQueryItem(name: "filter[frequency]", value: frequency),
            URLQueryItem(name: "filter[version]", value: version),
        ]
        if let reportDate {
            query.append(URLQueryItem(name: "filter[reportDate]", value: reportDate))
        }
        let result = try await api.apple("GET", "/v1/salesReports", query: query)
        return try Gzip.unpackText(result.data)
    }

    /// The first rows of a report, which is what a panel shows. The whole
    /// report belongs in a spreadsheet and not in a window.
    public static func preview(_ text: String, rows: Int = 12) -> [[String]] {
        let separator: Character = text.contains("\t") ? "\t" : ","
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(rows)
            .map { $0.split(separator: separator, omittingEmptySubsequences: false)
                .map(String.init) }
    }

    // MARK: - The parsers

    static func parseFeed(_ item: JSON) -> Feed? {
        guard let id = item["id"].string else { return nil }
        return Feed(id: id,
                    accessType: item["attributes"]["accessType"].string ?? "ONGOING",
                    stoppedDueToInactivity:
                        item["attributes"]["stoppedDueToInactivity"].bool ?? false)
    }

    static func parseReport(_ item: JSON) -> Report? {
        guard let id = item["id"].string else { return nil }
        return Report(id: id,
                      name: item["attributes"]["name"].string ?? id,
                      category: item["attributes"]["category"].string)
    }

    static func parseInstance(_ item: JSON) -> Instance? {
        guard let id = item["id"].string else { return nil }
        return Instance(id: id,
                        granularity: item["attributes"]["granularity"].string,
                        processingDate: item["attributes"]["processingDate"].string)
    }

    static func parseSegment(_ item: JSON) -> Segment? {
        guard let id = item["id"].string else { return nil }
        return Segment(id: id,
                       url: item["attributes"]["url"].string,
                       sizeInBytes: item["attributes"]["sizeInBytes"].int ?? 0,
                       checksum: item["attributes"]["checksum"].string)
    }
}

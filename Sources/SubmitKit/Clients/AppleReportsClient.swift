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

    // MARK: - The bytes

    /// One segment, unpacked to text.
    ///
    /// The last call of the feed, and the one it used to stop short of: the
    /// four reads above could name a segment and nothing ever fetched one, so a
    /// feed that Apple had filled produced no number in this app.
    ///
    /// The URL is Apple's own and signed, so `StoreAPI.download` sends no
    /// bearer token with it. See the comment there.
    public func segmentText(_ segment: Segment) async throws -> String {
        guard let url = segment.url, !url.isEmpty else {
            throw ConnectionError.invalidResponse
        }
        let data = try await api.download(url, path: "analyticsReportSegment")
        // Apple gzips a segment. A reader that throws on a plain file shows
        // nothing for a file it could have read.
        return (try? Gzip.unpackText(data)) ?? String(decoding: data, as: UTF8.self)
    }

    /// The whole of one instance, in the order Apple splits it.
    ///
    /// Every segment after the first repeats the header row, so only the first
    /// one keeps it. A reader that concatenated them counted the header as a
    /// row of data once per segment.
    public func instanceText(instanceID: String) async throws -> String {
        let parts = try await segments(instanceID: instanceID)
        var out: [String] = []
        for (index, segment) in parts.enumerated() {
            let text = try await segmentText(segment)
            out.append(index == 0 ? text : Self.dropHeader(text))
        }
        return out.joined()
    }

    // MARK: - What the account actually returns

    /// The columns that could identify one product page experiment treatment.
    ///
    /// Nothing in the API reference names such a dimension in any analytics
    /// report, and `AppStoreVersionExperimentTreatment` carries no id that
    /// appears in one. So this looks for a column instead of assuming one, and
    /// an empty answer is the honest report that the account returned none.
    public static func treatmentColumns(_ columns: [String]) -> [String] {
        columns.filter {
            let lowered = $0.lowercased()
            return lowered.contains("treatment") || lowered.contains("experiment")
        }
    }

    /// The reports whose numbers describe the store page, picked by Apple's own
    /// category rather than by a report name this app invented.
    public static func engagement(_ reports: [Report]) -> [Report] {
        reports.filter { $0.category == "APP_STORE_ENGAGEMENT" }
    }

    /// The newest instance of one granularity.
    ///
    /// A report carries a daily, a weekly and a monthly instance at once, and
    /// the monthly one always has the latest `processingDate`. Picking the
    /// newest of all three answered a nine-day question with last month.
    public static func newest(_ instances: [Instance], granularity: String) -> Instance? {
        instances
            .filter { $0.granularity == granularity }
            .max { ($0.processingDate ?? "") < ($1.processingDate ?? "") }
    }

    private static func dropHeader(_ text: String) -> String {
        guard let newline = text.firstIndex(of: "\n") else { return "" }
        return String(text[text.index(after: newline)...])
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

    /// One finance report, unpacked to text.
    ///
    /// The sales report answers "what sold". This answers "what Apple paid",
    /// which is a different number: it is net of Apple's commission, it is in
    /// the currency of each region, and it only exists for a month Apple has
    /// closed. The shape is the same gzipped, tab-separated file.
    ///
    /// `reportDate` is `YYYY-MM` and Apple requires it, because a finance
    /// report is monthly and there is no "latest". The newest closed month
    /// appears a few weeks after it ends, and Apple answers 404 until then,
    /// which is a state and not a failure.
    ///
    /// `regionCode` is Apple's own finance region, and `ZZ` is the one that
    /// consolidates every region into a single report. `FINANCIAL` is the
    /// summary; `FINANCE_DETAIL` is the transaction-level file behind it.
    public func financeReport(vendorNumber: String,
                              reportDate: String,
                              regionCode: String = "ZZ",
                              reportType: String = "FINANCIAL") async throws -> String {
        let result = try await api.apple("GET", "/v1/financeReports", query: [
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[regionCode]", value: regionCode),
            URLQueryItem(name: "filter[reportDate]", value: reportDate),
            URLQueryItem(name: "filter[reportType]", value: reportType),
        ])
        return try Gzip.unpackText(result.data)
    }

    /// The last `days` daily sales reports, joined into one table.
    ///
    /// One request answers one period. A daily report is a single day, so the
    /// panel could show that day's rows and no trend at all, and the question a
    /// developer opens a sales report to ask is which way the line is going.
    /// Apple publishes no range filter, so a range is a request per day.
    ///
    /// The days run in parallel, a few at a time. Apple rate-limits per hour
    /// and a burst of thirty is the kind of thing that spends the budget the
    /// rest of the app needs.
    ///
    /// A day Apple holds no report for answers 404, which is a state and not a
    /// failure: the newest day or two are usually missing, and a day with no
    /// sales is missing for the whole of a small app's history. Those days are
    /// skipped, and `missing` counts them so the panel can say so rather than
    /// drawing a gap nobody can explain.
    public func salesHistory(vendorNumber: String, days: Int = 30,
                             endingAt now: Date = Date())
        -> AsyncThrowingStream<(text: String, date: String), Error> {
        let dates = Self.reportDates(days: days, endingAt: now)
        return AsyncThrowingStream { continuation in
            let task = Task {
                await withTaskGroup(of: (String, String?).self) { group in
                    var next = 0
                    // Four at a time. Enough to make thirty days quick and few
                    // enough to leave the account's rate budget alone.
                    let width = min(4, dates.count)
                    func submit() {
                        guard next < dates.count else { return }
                        let date = dates[next]
                        next += 1
                        group.addTask {
                            (date, try? await self.salesReport(vendorNumber: vendorNumber,
                                                               frequency: "DAILY",
                                                               reportDate: date))
                        }
                    }
                    for _ in 0..<width { submit() }
                    while let (date, text) = await group.next() {
                        if let text { continuation.yield((text, date)) }
                        submit()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The days a daily report can exist for, newest last.
    ///
    /// Yesterday and back. Today's report does not exist: Apple closes a day
    /// and publishes it the day after.
    public static func reportDates(days: Int, endingAt now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return (1...max(days, 1)).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: now).map(formatter.string(from:))
        }
    }

    /// Every fetched day, read as one table.
    ///
    /// The header of the first day wins and the rest are dropped, the same rule
    /// `instanceText` follows for segments. Apple ships the same columns for
    /// every day of one report type, and a day whose header disagrees is a day
    /// this app cannot line up, so it is left out rather than shifted into the
    /// wrong columns.
    public static func join(_ reports: [String]) -> ReportTable {
        var joined = ReportTable()
        for text in reports {
            let table = ReportTable.parse(text)
            guard !table.isEmpty else { continue }
            if joined.columns.isEmpty {
                joined = table
            } else if table.columns == joined.columns {
                joined.rows += table.rows
            }
        }
        return joined
    }

    /// The month a finance report can actually exist for.
    ///
    /// Apple closes a month several weeks after it ends, so "this month" and
    /// usually "last month" are both 404. The default is two months back,
    /// which is the newest one that is normally there.
    public static func defaultFinanceMonth(from now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let month = calendar.date(byAdding: .month, value: -2, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month], from: month)
        return String(format: "%04d-%02d", parts.year ?? 1970, parts.month ?? 1)
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

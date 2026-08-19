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

    /// One day of one metric.
    public struct SeriesPoint: Sendable, Equatable, Identifiable {
        public var date: Date
        public var value: Double

        public var id: Date { date }

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// One metric across the days the store answered for, oldest first.
    public struct MetricSeries: Sendable, Equatable, Identifiable {
        public var name: String
        public var points: [SeriesPoint]

        public var id: String { name }

        public init(name: String, points: [SeriesPoint]) {
            self.name = name
            self.points = points
        }

        public var highest: Double { points.map(\.value).max() ?? 0 }
        public var newest: SeriesPoint? { points.last }

        /// Whether the second half of the window sits above the first.
        ///
        /// Two halves and not the last two days. A daily rate moves on its own,
        /// and a line drawn from yesterday to today reports the noise.
        public var isRising: Bool? {
            guard points.count >= 4 else { return nil }
            let half = points.count / 2
            let older = points.prefix(half).map(\.value)
            let newer = points.suffix(points.count - half).map(\.value)
            let before = older.reduce(0, +) / Double(older.count)
            let after = newer.reduce(0, +) / Double(newer.count)
            // A hundredth of a point either way is the same rate twice.
            guard abs(after - before) * 100 >= 0.01 else { return nil }
            return after > before
        }
    }

    /// What the vitals read answers with: the numbers, and their shape.
    public struct GoogleVitals: Sendable, Equatable {
        public var metrics: [Metric] = []
        public var trends: [MetricSeries] = []

        public init(metrics: [Metric] = [], trends: [MetricSeries] = []) {
            self.metrics = metrics
            self.trends = trends
        }
    }

    /// The crash rate and the ANR rate of the last 28 days.
    ///
    /// Google returns one row per day, so this averages the rows it gets and
    /// says how many days it covered.
    ///
    /// The days themselves come back too, off the same request and the same
    /// rows. An average is the honest summary of a month and it hides the one
    /// thing a developer opens this panel to see: 0.4 % flat for four weeks and
    /// 0.1 % climbing to 0.9 % are the same number. Nothing extra is asked of
    /// the store to draw it.
    public func googleVitals(packageName: String) async throws -> GoogleVitals {
        var result = GoogleVitals()
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
            result.metrics.append(Metric(name: label,
                                         value: Self.percent(average),
                                         detail: "\(rows.count) days"))
            // Two points are a line and one is a dot. A single day draws
            // nothing, and the number above already says it.
            let points = Self.series(rows, metric: metric)
            if points.count > 1 {
                result.trends.append(MetricSeries(name: label, points: points))
            }
        }
        return result
    }

    /// One point per day, oldest first.
    ///
    /// A row that names no day belongs to no day, and is dropped rather than
    /// stacked onto whichever date sorts first.
    static func series(_ rows: [JSON], metric: String) -> [SeriesPoint] {
        rows.compactMap { row -> SeriesPoint? in
            guard let date = Self.day(row["startTime"]),
                  let value = Self.value(row, metric: metric) else { return nil }
            return SeriesPoint(date: date, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    /// The day a row covers.
    ///
    /// The Reporting API sends a date as its parts and not as a string, so this
    /// reads them and answers nil for a row that carries none. UTC, because the
    /// store counts a day in its own zone and not in the developer's.
    static func day(_ time: JSON) -> Date? {
        guard let year = time["year"].int, let month = time["month"].int,
              let day = time["day"].int else { return nil }
        return Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                 year: year, month: month, day: day))
    }

    /// The number one row carries for one metric.
    ///
    /// Google sends a decimal as a string inside `decimalValue`, and sometimes
    /// as a number. Three readers wanted the same two lines, so they are here.
    static func value(_ row: JSON, metric: String) -> Double? {
        guard let entry = row["metrics"].array
            .first(where: { $0["metric"].string == metric }) else { return nil }
        return entry["decimalValue"]["value"].string.flatMap(Double.init)
            ?? entry["decimalValue"]["value"].double
    }

    /// One version's rate, for the comparison a single number cannot make.
    public struct VersionRate: Sendable, Equatable, Identifiable {
        public var version: String
        public var rate: Double

        public var id: String { version }

        public init(version: String, rate: Double) {
            self.version = version
            self.rate = rate
        }
    }

    /// What the strip above the cards says, or nil when there is nothing worth
    /// saying.
    public struct RateChange: Sendable, Equatable {
        public var isWorse: Bool
        public var line: String
    }

    /// The user-perceived crash rate per app version, newest version first.
    ///
    /// The same metric set as `googleVitals`, split by the dimension that says
    /// which build a day belongs to. A crash rate on its own is a number nobody
    /// can act on: 1.2% is bad after 0.8% and good after 2%.
    ///
    /// ponytail: never run against a real account. The Play Developer Reporting
    /// API is not among the references in `docs/`, so the dimension name and
    /// the row shape come from the API's own documentation online rather than
    /// from a file on disk. Everything below the request is a pure function, so
    /// a wrong shape is one fix in one place. A failed or unrecognised answer
    /// returns nothing, and the strip then says nothing rather than a number it
    /// cannot stand behind.
    public func googleCrashRateByVersion(packageName: String) async throws -> [VersionRate] {
        guard let response = try? await api.googleReporting(
            "POST", "/v1beta1/apps/\(StateReader.escape(packageName))/crashRateMetricSet:query",
            body: [
                "metrics": ["userPerceivedCrashRate"],
                "dimensions": ["versionCode"],
                "pageSize": 1000,
            ]) else { return [] }
        return Self.versionRates(JSON(data: response.data)["rows"].array,
                                 metric: "userPerceivedCrashRate")
    }

    /// One rate per version, newest first.
    ///
    /// Google answers a row per day per version, so a version's rate is the
    /// mean of its days. A row that names no version belongs to no version and
    /// is dropped rather than folded into whichever one sorts first.
    static func versionRates(_ rows: [JSON], metric: String) -> [VersionRate] {
        var byVersion: [String: [Double]] = [:]
        for row in rows {
            guard let version = row["dimensions"].array
                .first(where: { $0["dimension"].string == "versionCode" })
                .flatMap({ $0["stringValue"].string ?? $0["int64Value"].string
                    ?? $0["int64Value"].int.map(String.init) }),
                !version.isEmpty,
                let value = Self.value(row, metric: metric)
            else { continue }
            byVersion[version, default: []].append(value)
        }
        return byVersion
            .map { VersionRate(version: $0.key,
                               rate: $0.value.reduce(0, +) / Double($0.value.count)) }
            // Newest first. A version code is a number, so it compares as one:
            // "9" sorts above "10" as text and below it as a build.
            .sorted { (Int($0.version) ?? 0, $0.version) > (Int($1.version) ?? 0, $1.version) }
    }

    /// Whether the newest version moved the crash rate, in the words the strip
    /// uses.
    ///
    /// A first release compares to nothing, so it says nothing. A change under
    /// a tenth of a point is noise, and the strip exists for the one fact worth
    /// reading before the cards.
    public static func crashRateChange(_ rates: [VersionRate]) -> RateChange? {
        guard rates.count > 1 else { return nil }
        let points = (rates[0].rate - rates[1].rate) * 100
        guard abs(points) >= 0.1 else { return nil }
        let size = String(format: "%.1f", abs(points))
        return RateChange(
            isWorse: points > 0,
            line: "Play's crash rate is \(points > 0 ? "up" : "down") \(size) points since \(rates[1].version)")
    }

    /// The mean of one metric across the returned rows.
    static func average(_ rows: [JSON], metric: String) -> Double? {
        let values = rows.compactMap { Self.value($0, metric: metric) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Google reports a rate as a fraction, and a reader wants a percentage.
    public static func percent(_ value: Double) -> String {
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
    static func title(_ identifier: String) -> String { AppleWords.title(identifier) }

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

    // MARK: - What one customer actually bought

    /// The other half of support. The refunds above answer "what did Google
    /// already take back"; this answers "is this person subscribed, to what,
    /// until when, and what did this order contain".
    ///
    /// Every call here is a read. The money-moving twins of these endpoints
    /// exist, and this app sends none of them: a refund, a cancellation, a
    /// revocation, and a deferral all reach a paying customer, so they belong
    /// to a person in the Play Console.
    ///
    /// `// ponytail: one entry point, not four. A support ticket carries one
    /// // string, and which of the four endpoints answers it is a fact about
    /// // the string, not a decision the developer should have to make.`
    public struct PurchaseLookup: Sendable, Equatable {
        /// One block per thing Google answered.
        public var blocks: [Block] = []
        /// What the lookup could not answer, in a sentence a developer reads.
        public var notes: [String] = []

        public struct Block: Sendable, Equatable, Identifiable {
            /// Its own value, because one order may carry the same product on
            /// two line items and two blocks that shared an id would fight
            /// over one row on screen.
            public var id: String
            public var title: String
            public var rows: [Metric]

            public init(id: String? = nil, title: String, rows: [Metric]) {
                self.id = id ?? title
                self.title = title
                self.rows = rows
            }
        }

        public init(blocks: [Block] = [], notes: [String] = []) {
            self.blocks = blocks
            self.notes = notes
        }
    }

    /// Resolves whatever the customer sent: an order id, several order ids, or
    /// a purchase token.
    ///
    /// Google splits the answer across four endpoints and never says which one
    /// fits. An order id is the one shape that announces itself, so the ids go
    /// to the order endpoints and everything else is treated as a token.
    ///
    /// - Parameter productId: only a one-time purchase needs it, because
    ///   Google puts the product in the path of that endpoint and in no other.
    ///   An empty one reads the token as a subscription.
    public func googlePurchaseLookup(packageName: String, query: String,
                                     productId: String = "") async throws -> PurchaseLookup {
        let terms = Self.terms(query)
        guard !terms.isEmpty else { return PurchaseLookup() }
        let orderIds = terms.filter(Self.looksLikeAnOrderId)
        let tokens = terms.filter { !Self.looksLikeAnOrderId($0) }
        var result = PurchaseLookup()

        let orders = try await googleOrders(packageName: packageName, orderIds: orderIds)
        result.blocks += orders.flatMap { $0 }
        if orders.count < orderIds.count {
            result.notes.append(
                "Google answered about \(orders.count) of the \(orderIds.count) order ids. It knows one from this app and this developer account only.")
        }

        // One token is one customer. A second would answer a second question,
        // and the product id below could only fit one of them.
        if let token = tokens.first {
            if tokens.count > 1 {
                result.notes.append(
                    "One purchase token at a time. This looked up the first one.")
            }
            let trimmed = productId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if let block = try await googleSubscription(packageName: packageName,
                                                            token: token) {
                    result.blocks.append(block)
                } else {
                    result.notes.append(
                        "Google knows no subscription for this purchase token. Enter the product id beside it to read it as a one-time purchase.")
                }
            } else if let block = try await googleProductPurchase(
                packageName: packageName, productId: trimmed, token: token) {
                result.blocks.append(block)
            } else {
                result.notes.append(
                    "Google knows no purchase of \(trimmed) for this token. Check the product id, and clear it to read the token as a subscription.")
            }
        }
        return result
    }

    /// One order, or up to a thousand of them. Google publishes a batch read,
    /// and one call beats twenty.
    func googleOrders(packageName: String,
                      orderIds: [String]) async throws -> [[PurchaseLookup.Block]] {
        guard !orderIds.isEmpty else { return [] }
        let base = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
        if orderIds.count == 1 {
            let path = "\(base)/orders/\(StateReader.escape(orderIds[0]))"
            guard let payload = try await Self.readOrNothing({
                JSON(data: try await api.google("GET", path).data)
            }) else { return [] }
            return [Self.orderBlocks(payload)]
        }
        // Google caps the batch at a thousand ids, which no support ticket
        // reaches, so a paste that long is refused rather than silently cut.
        guard orderIds.count <= 1000 else {
            throw ConnectionError.http(
                400, "Google reads 1000 order ids at once. This asked about \(orderIds.count).")
        }
        let payload = JSON(data: try await api.google(
            "GET", "\(base)/orders:batchGet",
            query: orderIds.map { URLQueryItem(name: "orderIds", value: $0) }).data)
        return payload["orders"].array.map(Self.orderBlocks)
    }

    func googleSubscription(packageName: String,
                            token: String) async throws -> PurchaseLookup.Block? {
        let path = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
            + "/purchases/subscriptionsv2/tokens/\(StateReader.escape(token))"
        guard let payload = try await Self.readOrNothing({
            JSON(data: try await api.google("GET", path).data)
        }) else { return nil }
        return Self.subscriptionBlock(payload)
    }

    func googleProductPurchase(packageName: String, productId: String,
                               token: String) async throws -> PurchaseLookup.Block? {
        let path = "/androidpublisher/v3/applications/\(StateReader.escape(packageName))"
            + "/purchases/products/\(StateReader.escape(productId))"
            + "/tokens/\(StateReader.escape(token))"
        guard let payload = try await Self.readOrNothing({
            JSON(data: try await api.google("GET", path).data)
        }) else { return nil }
        return Self.productPurchaseBlock(payload, productId: productId)
    }

    /// Google answers 404 for a token it does not recognise and 400 for one it
    /// cannot parse. Both mean "not this shape", which the caller turns into a
    /// sentence. Every other status is a real failure and stays thrown.
    static func readOrNothing(_ read: () async throws -> JSON) async throws -> JSON? {
        do {
            return try await read()
        } catch ConnectionError.http(let status, _) where status == 404 || status == 400 {
            return nil
        }
    }

    // MARK: - Reading the three answers

    static func orderBlocks(_ payload: JSON) -> [PurchaseLookup.Block] {
        let id = payload["orderId"].string ?? "unknown"
        var rows = [Metric(name: "State", value: title(payload["state"].string ?? "unknown"))]
        if let created = time(payload["createTime"]) {
            rows.append(Metric(name: "Bought", value: created))
        }
        if let last = time(payload["lastEventTime"]) {
            rows.append(Metric(name: "Last change", value: last))
        }
        if let total = GoogleCatalogClient.money(payload["total"]) {
            rows.append(Metric(name: "Total", value: total,
                               detail: GoogleCatalogClient.money(payload["tax"])
                                   .map { "\($0) tax" }))
        }
        if let revenue = GoogleCatalogClient.money(payload["developerRevenue"]) {
            rows.append(Metric(name: "Your share", value: revenue))
        }
        if let token = payload["purchaseToken"].string {
            rows.append(Metric(name: "Purchase token", value: token))
        }
        var blocks = [PurchaseLookup.Block(title: "Order \(id)", rows: rows)]

        for (index, item) in payload["lineItems"].array.enumerated() {
            let product = item["productId"].string ?? "item \(index + 1)"
            var lines: [Metric] = []
            if let name = item["productTitle"].string {
                lines.append(Metric(name: "Name", value: name))
            }
            if let listed = GoogleCatalogClient.money(item["listingPrice"]) {
                lines.append(Metric(name: "Listed at", value: listed))
            }
            if let paid = GoogleCatalogClient.money(item["total"]) {
                lines.append(Metric(name: "Paid", value: paid,
                                    detail: GoogleCatalogClient.money(item["tax"])
                                        .map { "\($0) tax" }))
            }
            let plan = item["subscriptionDetails"]
            if let basePlan = plan["basePlanId"].string {
                lines.append(Metric(name: "Base plan", value: basePlan,
                                    detail: plan["offerId"].string))
            }
            if let from = time(plan["servicePeriodStartTime"]),
               let to = time(plan["servicePeriodEndTime"]) {
                lines.append(Metric(name: "Covers", value: "\(from) to \(to)"))
            }
            let kind = plan.exists ? "Subscription"
                : item["oneTimePurchaseDetails"].exists ? "One-time purchase"
                : item["paidAppDetails"].exists ? "Paid app" : nil
            if let kind { lines.append(Metric(name: "Kind", value: kind)) }
            blocks.append(PurchaseLookup.Block(id: "\(id).\(index)",
                                               title: "Line item \(product)", rows: lines))
        }
        return blocks
    }

    static func subscriptionBlock(_ payload: JSON) -> PurchaseLookup.Block {
        var rows = [Metric(name: "State",
                           value: title(payload["subscriptionState"].string
                               .map { $0.replacingOccurrences(of: "SUBSCRIPTION_STATE_",
                                                              with: "") } ?? "unknown"))]
        if payload["testPurchase"].exists {
            rows.append(Metric(name: "Test purchase", value: "Yes",
                               detail: "It paid nothing and it renews on the test clock."))
        }
        if let start = time(payload["startTime"]) {
            rows.append(Metric(name: "Started", value: start))
        }
        // One subscription carries one line item today, and Google models it
        // as a list because a plan change puts two there for a moment.
        for (index, item) in payload["lineItems"].array.enumerated() {
            let suffix = index == 0 ? "" : " \(index + 1)"
            if let product = item["productId"].string {
                rows.append(Metric(name: "Product\(suffix)", value: product,
                                   detail: item["offerDetails"]["basePlanId"].string))
            }
            if let offer = item["offerDetails"]["offerId"].string {
                rows.append(Metric(name: "Offer\(suffix)", value: offer))
            }
            if let expiry = time(item["expiryTime"]) {
                let renews = item["autoRenewingPlan"]["autoRenewEnabled"].bool ?? false
                rows.append(Metric(name: renews ? "Renews\(suffix)" : "Ends\(suffix)",
                                   value: expiry,
                                   detail: renews ? nil : "Auto-renew is off."))
            }
            if let price = GoogleCatalogClient.money(
                item["autoRenewingPlan"]["recurringPrice"]) {
                rows.append(Metric(name: "Renewal price\(suffix)", value: price))
            }
            if let resume = time(item["prepaidPlan"]["allowExtendAfterTime"]) {
                rows.append(Metric(name: "Prepaid, toppable from\(suffix)", value: resume))
            }
        }
        if let reason = cancelReason(payload["canceledStateContext"]) {
            rows.append(Metric(name: "Cancelled by", value: reason))
        }
        if let resume = time(payload["pausedStateContext"]["autoResumeTime"]) {
            rows.append(Metric(name: "Resumes", value: resume))
        }
        if let state = payload["acknowledgementState"].string {
            rows.append(Metric(name: "Acknowledged",
                               value: state.hasSuffix("ACKNOWLEDGED") ? "Yes" : "Not yet",
                               detail: state.hasSuffix("ACKNOWLEDGED") ? nil
                                   : "Your app has three days to acknowledge a purchase. Google refunds it after that."))
        }
        if let region = payload["regionCode"].string {
            rows.append(Metric(name: "Bought in", value: region))
        }
        if let order = payload["latestOrderId"].string {
            rows.append(Metric(name: "Latest order", value: order))
        }
        if let linked = payload["linkedPurchaseToken"].string {
            rows.append(Metric(name: "Replaces token", value: linked,
                               detail: "This subscription upgraded or downgraded from that one."))
        }
        return PurchaseLookup.Block(title: "Subscription", rows: rows)
    }

    static func productPurchaseBlock(_ payload: JSON,
                                     productId: String) -> PurchaseLookup.Block {
        var rows: [Metric] = []
        if let state = payload["purchaseState"].int, purchaseStates.indices.contains(state) {
            rows.append(Metric(name: "State", value: purchaseStates[state]))
        }
        if let kind = payload["purchaseType"].int, purchaseKinds.indices.contains(kind) {
            rows.append(Metric(name: "Kind", value: purchaseKinds[kind],
                               detail: "It paid nothing."))
        }
        if let millis = payload["purchaseTimeMillis"].string.flatMap(Double.init) {
            rows.append(Metric(
                name: "Bought",
                value: Date(timeIntervalSince1970: millis / 1000)
                    .formatted(date: .abbreviated, time: .shortened)))
        }
        if let quantity = payload["quantity"].int, quantity > 1 {
            rows.append(Metric(name: "Quantity", value: String(quantity),
                               detail: payload["refundableQuantity"].int
                                   .map { "\($0) still refundable" }))
        }
        if let consumed = payload["consumptionState"].int {
            rows.append(Metric(name: "Consumed", value: consumed == 1 ? "Yes" : "Not yet"))
        }
        if let acknowledged = payload["acknowledgementState"].int {
            rows.append(Metric(name: "Acknowledged",
                               value: acknowledged == 1 ? "Yes" : "Not yet",
                               detail: acknowledged == 1 ? nil
                                   : "Your app has three days to acknowledge a purchase. Google refunds it after that."))
        }
        if let region = payload["regionCode"].string {
            rows.append(Metric(name: "Bought in", value: region))
        }
        if let order = payload["orderId"].string {
            rows.append(Metric(name: "Order", value: order))
        }
        return PurchaseLookup.Block(title: "One-time purchase \(productId)", rows: rows)
    }

    static let purchaseStates = ["Bought", "Cancelled", "Pending"]
    static let purchaseKinds = ["Test purchase", "Promo code", "Rewarded"]

    /// Who ended the subscription. Google models each cause as its own empty
    /// object, so the presence of the key is the whole answer.
    static func cancelReason(_ context: JSON) -> String? {
        guard context.exists else { return nil }
        if context["userInitiatedCancellation"].exists {
            let survey = context["userInitiatedCancellation"]["cancelSurveyResult"]
            let reason = survey["reason"].string ?? survey["reasonUserInput"].string
            return reason.map { "the customer, who said: \(title($0))" } ?? "the customer"
        }
        if context["developerInitiatedCancellation"].exists { return "you" }
        if context["replacementCancellation"].exists {
            return "a plan change, which replaced it"
        }
        if context["systemInitiatedCancellation"].exists {
            return "Google, after the payment failed"
        }
        return nil
    }

    /// An RFC 3339 stamp, as a date a person reads. Google writes the same
    /// shape App Store Connect does, so this reads it with the same parser.
    static func time(_ node: JSON) -> String? {
        guard let text = node.string, !text.isEmpty else { return nil }
        guard let date = Date.iso8601(text) else { return text }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// A pasted support ticket carries commas, newlines, and spaces. Each is a
    /// separator, and none of them appears inside an order id or a token.
    static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Google stamps every order id it issues with `GPA.`, including the
    /// `..0`-suffixed ones a subscription renewal produces. A purchase token
    /// carries no such prefix, so the prefix is the whole test.
    static func looksLikeAnOrderId(_ value: String) -> Bool {
        value.uppercased().hasPrefix("GPA.")
    }
}

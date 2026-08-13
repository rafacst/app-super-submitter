import SubmitKit
import SwiftUI

/// What App Store Connect measured and what it paid.
///
/// Everything here is a read except one call. "Start a report feed" creates an
/// analytics report request, which is how Apple starts producing reports for an
/// app. It writes nothing to a listing, it reaches no customer, and stopping
/// the feed deletes the request again.
///
/// A report is what the store measured, so none of it is a desired state and
/// none of it reaches `store.yaml` or a plan row.
struct ReportsPanel: View {
    @Environment(AppState.self) private var state
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var feeds: [AppleReportsClient.Feed] = []
    @State private var reports: [String: [AppleReportsClient.Report]] = [:]
    @State private var confirmingRequest = false
    @State private var stopping: AppleReportsClient.Feed?
    /// What one report turned out to hold, keyed by its id. See `reportRow`.
    @State private var samples: [String: ReportSample] = [:]

    struct ReportSample {
        var note: String
        var table = ReportTable()
    }

    @State private var frequency = "DAILY"
    @State private var salesTable = ReportTable()
    @State private var salesNote: String?
    /// The last thirty days, which is a request per day. See `loadSalesHistory`.
    @State private var salesHistory = ReportTable()
    @State private var salesHistoryNote: String?

    @State private var financeMonth = AppleReportsClient.defaultFinanceMonth()
    @State private var financeRegion = "ZZ"
    @State private var financeType = "FINANCIAL"
    @State private var financeTable = ReportTable()
    @State private var financeNote: String?

    var body: some View {
        Section_("Reports", icon: "chart.bar.doc.horizontal", tint: Theme.teal) {
            VStack(alignment: .leading, spacing: 12) {
                analytics
                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                sales
                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                finance
            }
            .storePanel(padding: 14)
        }
        .confirmationDialog("Start a report feed?", isPresented: $confirmingRequest) {
            Button("Start an ongoing feed") { request(ongoing: true) }
            Button("Take one snapshot") { request(ongoing: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple starts producing analytics reports for this app. The first one appears a day or two later. Stopping the feed later removes the request and keeps every report Apple already made.")
        }
        .confirmationDialog("Stop this feed?", isPresented: $stopping.isPresent,
                            presenting: stopping) { feed in
            Button("Stop the feed", role: .destructive) { stop(feed) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Apple stops producing new reports and keeps every report it already made.")
        }
    }

    // MARK: - The analytics feed

    @ViewBuilder private var analytics: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Apple produces an analytics report only after you ask for a feed. The first report appears a day or two later, which is a state and not a fault.")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            QuietButton(title: busy ? "Fetching…" : "Fetch the feeds") { load() }
                .disabled(busy || state.appleActionAppID == nil)
        }

        if let error { ErrorLine(text: error) }
        if loaded, feeds.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("This app has no report feed.")
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                Spacer(minLength: 8)
                Button("Start a report feed") { confirmingRequest = true }
                    .controlSize(.small)
                    .disabled(busy)
            }
        }
        ForEach(feeds) { feed in feedRow(feed) }
    }

    private func feedRow(_ feed: AppleReportsClient.Feed) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Text(feed.accessType == "ONGOING" ? "Ongoing" : "One snapshot")
                    .font(Theme.font(size: 12, weight: .medium))
                if feed.stoppedDueToInactivity {
                    StatePill(text: "STOPPED", foreground: Theme.orange,
                              background: Theme.sunken)
                }
                Spacer(minLength: 8)
                Button("Stop") { stopping = feed }
                    .controlSize(.small)
                    .disabled(busy)
            }
            if feed.stoppedDueToInactivity {
                Text("Apple stopped this feed because nothing read it. Start a new one to resume.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(reports[feed.id] ?? []) { report in
                reportRow(report)
            }
        }
        .padding(.vertical, 5)
    }

    /// One report, and what it actually carries.
    ///
    /// The API reference names five categories and no column, so the report
    /// name alone says nothing about what is in the file. The button fetches
    /// the newest daily instance and prints the header row that came back.
    private func reportRow(_ report: AppleReportsClient.Report) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(report.name).font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                if let category = report.category {
                    Text(AppleWords.title(category))
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                }
                QuietButton(title: "Columns") { loadColumns(report) }
                    .disabled(busy)
            }
            if let sample = samples[report.id] {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample.note)
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !sample.table.columns.isEmpty {
                        Text(sample.table.columns.joined(separator: " · "))
                            .font(Theme.mono(10)).foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if !sample.table.isEmpty {
                        ReportChartBlock(table: sample.table)
                        table(preview(sample.table))
                    }
                }
                .padding(.leading, 10)
            }
        }
    }

    // MARK: - The sales report

    @ViewBuilder private var sales: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 8) {
            Text("Sales")
                .font(Theme.font(size: 12, weight: .semibold))
            Text("The vendor number is on the Payments and Financial Reports page of App Store Connect. It belongs to the account and not to the app, so it stays out of store.yaml.")
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Vendor number", text: $state.appleVendorNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Picker("", selection: $frequency) {
                    Text("Daily").tag("DAILY")
                    Text("Weekly").tag("WEEKLY")
                    Text("Monthly").tag("MONTHLY")
                    Text("Yearly").tag("YEARLY")
                }
                .labelsHidden()
                .frame(width: 110)
                QuietButton(title: busy ? "Fetching…" : "Fetch the report") { loadSales() }
                    .disabled(busy)
                Spacer(minLength: 0)
            }
            if let salesNote {
                Text(salesNote)
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !salesTable.isEmpty {
                ReportChartBlock(table: salesTable)
                table(preview(salesTable))
            }

            // The trend, which one request cannot answer.
            //
            // A daily report is one day. The panel could show that day and no
            // direction at all, and which way the line is going is the question
            // a sales report gets opened for. Apple publishes no range filter,
            // so a range is a request per day and it says so before it starts.
            Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                .padding(.vertical, 2)
            HStack(spacing: 8) {
                QuietButton(title: busy ? "Reading…" : "Read the last 30 days") {
                    loadSalesHistory()
                }
                .disabled(busy)
                Text("One request per day, four at a time. Apple publishes no way to ask for a range.")
                    .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let salesHistoryNote {
                Text(salesHistoryNote)
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !salesHistory.isEmpty { ReportChartBlock(table: salesHistory) }
        }
    }

    // MARK: - The finance report

    /// What Apple paid, which is not what the sales report counts. The sales
    /// report counts units; this one counts money after Apple's commission,
    /// and only for a month Apple has closed.
    @ViewBuilder private var finance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finance").font(Theme.font(size: 12, weight: .semibold))
            Text("The same vendor number as the sales report above. A finance report is monthly, and Apple closes a month a few weeks after it ends, so the newest one is usually two months back.")
                .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("YYYY-MM", text: $financeMonth)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11.5))
                    .frame(width: 100)
                TextField("Region", text: $financeRegion)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11.5))
                    .frame(width: 70)
                Picker("", selection: $financeType) {
                    Text("Summary").tag("FINANCIAL")
                    Text("Every transaction").tag("FINANCE_DETAIL")
                }
                .labelsHidden()
                .frame(width: 150)
                QuietButton(title: busy ? "Fetching…" : "Fetch the report") { loadFinance() }
                    .disabled(busy)
                Spacer(minLength: 0)
            }
            Text("ZZ is the one region code that consolidates every region into a single report. A three-letter code, for example USA, gives that region on its own.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let financeNote {
                Text(financeNote)
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !financeTable.isEmpty {
                ReportChartBlock(table: financeTable)
                table(preview(financeTable))
            }
        }
    }

    /// The header and the first rows, which is what the table below a chart
    /// prints. A whole report belongs in a spreadsheet and not in a window.
    private func preview(_ table: ReportTable, rows: Int = 11) -> [[String]] {
        [table.columns] + table.rows.prefix(rows)
    }

    /// The first rows only. A whole report belongs in a spreadsheet and not in
    /// a window.
    private func table(_ rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(Theme.mono(10))
                                .foregroundStyle(index == 0 ? Theme.text2 : Theme.text3)
                                .frame(width: Theme.scaled(92), alignment: .leading)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 220)
    }

    // MARK: - The work

    private func load() {
        track($busy, $error) {
            feeds = try await state.appleAnalyticsFeeds()
            for feed in feeds {
                reports[feed.id] = try? await state.appleReports().reports(feedID: feed.id)
            }
            loaded = true
        }
    }

    /// Fetches one report and says what came back.
    ///
    /// It names no column it has not seen. If a column identifies a product
    /// page experiment treatment, the line says which one; if none does, it
    /// says that, because the reference documents no such dimension and the
    /// only honest answer is the one the account gave.
    private func loadColumns(_ report: AppleReportsClient.Report) {
        busy = true
        samples[report.id] = ReportSample(note: "Fetching…")
        Task {
            do {
                guard let sample = try await state.appleAnalyticsSample(reportID: report.id) else {
                    samples[report.id] = ReportSample(
                        note: "Apple has produced no daily instance of this report yet. The first one appears a day or two after the feed starts.")
                    busy = false
                    return
                }
                let treatment = AppleReportsClient.treatmentColumns(sample.table.columns)
                let verdict = treatment.isEmpty
                    ? "No column here identifies a product page experiment treatment."
                    : "Treatment column: \(treatment.joined(separator: ", "))."
                samples[report.id] = ReportSample(
                    note: "\(sample.table.columns.count) columns, \(sample.table.rows.count) rows, processed \(sample.date). \(verdict)",
                    table: sample.table)
            } catch ConnectionError.http(404, _) {
                samples[report.id] = ReportSample(
                    note: "Apple holds no instance of this report yet.")
            } catch {
                samples[report.id] = ReportSample(note: error.localizedDescription)
            }
            busy = false
        }
    }

    private func request(ongoing: Bool) {
        track($busy, $error) {
            try await state.requestAppleAnalytics(ongoing: ongoing)
            feeds = try await state.appleAnalyticsFeeds()
        }
    }

    private func stop(_ feed: AppleReportsClient.Feed) {
        track($busy, $error) {
            try await state.stopAppleAnalytics(feedID: feed.id)
            feeds = try await state.appleAnalyticsFeeds()
        }
    }

    /// Apple answers 404 for a date it holds no report for. Today's daily
    /// report does not exist yet, so that reads as a state and not a failure.
    private func loadSales() {
        busy = true
        salesNote = nil
        salesTable = ReportTable()
        Task {
            do {
                let text = try await state.appleSalesReport(frequency: frequency,
                                                            reportDate: nil)
                salesTable = ReportTable.parse(text)
                if salesTable.isEmpty { salesNote = "The report came back empty." }
            } catch ConnectionError.http(404, _) {
                salesNote = "Apple holds no \(frequency.lowercased()) report for that period yet. The newest one appears a day after the period closes."
            } catch {
                salesNote = error.localizedDescription
            }
            busy = false
        }
    }

    /// Thirty daily reports, for the one chart a single report cannot draw.
    ///
    /// A day Apple holds nothing for is skipped rather than failing the read: a
    /// small app has days with no sales at all, and the newest day or two are
    /// normally not published yet. The note says how many days actually came
    /// back, so a short line is explained rather than just short.
    private func loadSalesHistory() {
        busy = true
        salesHistoryNote = "Reading…"
        salesHistory = ReportTable()
        Task {
            do {
                let result = try await state.appleSalesHistory(days: 30) { done in
                    salesHistoryNote = "Reading… \(done) days"
                }
                salesHistory = result.table
                salesHistoryNote = result.days == 0
                    ? "Apple holds no daily report for any of the last 30 days."
                    : "\(result.days) of the last 30 days came back. A day Apple holds no report for is a day with no sales, or one it has not published yet."
            } catch {
                salesHistoryNote = error.localizedDescription
            }
            busy = false
        }
    }

    /// The same 404 rule as the sales report, for a different reason: Apple
    /// has not closed that month yet.
    private func loadFinance() {
        busy = true
        financeNote = nil
        financeTable = ReportTable()
        Task {
            do {
                let text = try await state.appleFinanceReport(
                    month: financeMonth.trimmingCharacters(in: .whitespacesAndNewlines),
                    regionCode: financeRegion.trimmingCharacters(in: .whitespacesAndNewlines),
                    reportType: financeType)
                financeTable = ReportTable.parse(text)
                if financeTable.isEmpty { financeNote = "The report came back empty." }
            } catch ConnectionError.http(404, _) {
                financeNote = "Apple has not closed \(financeMonth) for that region yet, or it paid nothing there. A closed month appears a few weeks after it ends."
            } catch {
                financeNote = error.localizedDescription
            }
            busy = false
        }
    }
}

/// The chart of a report, drawn from what the file turned out to hold.
///
/// It names no column, because Apple names none either: the API reference
/// documents the transport of these reports and never their contents, so the
/// only honest chart is one built from the header the account actually sent.
/// `ReportTable` works out which columns hold dates and which hold numbers by
/// reading the values, this offers what it found, and the developer picks.
///
/// Which chart depends on what the report is. Several days is a line of days.
/// One day is not a trend, and the question a single day answers is where its
/// numbers came from, so that draws a breakdown instead.
struct ReportChartBlock: View {
    let table: ReportTable

    @State private var measure: Int?
    @State private var group: Int?

    private var measures: [Int] { table.numericColumns }
    private var groups: [Int] { table.labelColumns }
    private var chosenMeasure: Int? { measure ?? measures.first }
    private var chosenGroup: Int? { group ?? groups.first }

    var body: some View {
        if measures.isEmpty {
            Text("No column here holds a number to draw. The rows are below.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
        } else if let index = chosenMeasure {
            // Once, at the top, and handed to everything below it. Both the
            // menus and the chart need to know whether this report has more
            // than one day in it, and a report is thousands of rows: working
            // that out again in every branch of every render pass walks the
            // whole file each time.
            let points = table.series(column: index)
            VStack(alignment: .leading, spacing: 8) {
                pickers(overTime: points.count > 1)
                // Two days are a line and one is a dot. A daily report is one
                // day, and the breakdown is what it can answer.
                if points.count > 1 {
                    ReportSeriesChart(column: table.columns[index], points: points)
                    Text("Summed per day across every row. That is right for a count and wrong for a rate, and this app does not know which one you picked.")
                        .font(Theme.font(size: 10)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let label = chosenGroup {
                    ReportShareChart(column: table.columns[index],
                                     by: table.columns[label],
                                     shares: table.breakdown(column: index, by: label))
                    Text("This report covers one period, so there is no line to draw. The rows are the biggest ten, summed.")
                        .font(Theme.font(size: 10)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// One menu per choice, and each is drawn only when there is a choice to
    /// make. A report with a single number column offers no pick, and one that
    /// covers several days is not grouped by anything but the day.
    @ViewBuilder private func pickers(overTime: Bool) -> some View {
        HStack(spacing: 8) {
            if measures.count > 1, let index = chosenMeasure {
                Menu(table.columns[index]) {
                    ForEach(measures, id: \.self) { column in
                        Button(table.columns[column]) { measure = column }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
            }
            if !overTime, groups.count > 1, let index = chosenGroup {
                Text("by").font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                Menu(table.columns[index]) {
                    ForEach(groups, id: \.self) { column in
                        Button(table.columns[column]) { group = column }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }
}

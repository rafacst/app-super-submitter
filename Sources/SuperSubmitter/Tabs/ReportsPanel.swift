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

    @State private var frequency = "DAILY"
    @State private var salesRows: [[String]] = []
    @State private var salesNote: String?

    var body: some View {
        Section_("Reports", icon: "chart.bar.doc.horizontal", tint: Theme.teal) {
            VStack(alignment: .leading, spacing: 12) {
                analytics
                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
                sales
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
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            QuietButton(title: busy ? "Fetching…" : "Fetch the feeds") { load() }
                .disabled(busy || state.appleActionAppID == nil)
        }

        if let error { ErrorLine(text: error) }
        if loaded, feeds.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("This app has no report feed.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
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
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(reports[feed.id] ?? []) { report in
                HStack(spacing: 8) {
                    Text(report.name).font(.system(size: 11)).foregroundStyle(Theme.text2)
                    Spacer(minLength: 8)
                    if let category = report.category {
                        Text(AppleWords.title(category))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - The sales report

    @ViewBuilder private var sales: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 8) {
            Text("Sales")
                .font(.system(size: 12, weight: .semibold))
            Text("The vendor number is on the Payments and Financial Reports page of App Store Connect. It belongs to the account and not to the app, so it stays out of store.yaml.")
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
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
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !salesRows.isEmpty { table }
        }
    }

    /// The first rows only. A whole sales report belongs in a spreadsheet and
    /// not in a window.
    private var table: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(salesRows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(Theme.mono(10))
                                .foregroundStyle(index == 0 ? Theme.text2 : Theme.text3)
                                .frame(width: 92, alignment: .leading)
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
        salesRows = []
        Task {
            do {
                let text = try await state.appleSalesReport(frequency: frequency,
                                                            reportDate: nil)
                salesRows = AppleReportsClient.preview(text)
                if salesRows.isEmpty { salesNote = "The report came back empty." }
            } catch ConnectionError.http(404, _) {
                salesNote = "Apple holds no \(frequency.lowercased()) report for that period yet. The newest one appears a day after the period closes."
            } catch {
                salesNote = error.localizedDescription
            }
            busy = false
        }
    }
}

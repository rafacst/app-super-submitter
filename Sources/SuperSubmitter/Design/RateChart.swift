import Charts
import SubmitKit
import SwiftUI

/// The shape behind a number, for the two vitals the stores report daily.
///
/// The panel showed an average and the days it covered, which is the honest
/// summary of a month and hides the one thing the developer opened the panel
/// to find out. A rate of 0.4 % held flat for four weeks and a rate climbing
/// from 0.1 % to 0.9 % are the same average, and only one of them is a
/// release worth stopping.
///
/// Nothing extra is asked of the store to draw this. Google answers a row per
/// day already, and `StoreVitalsClient.googleVitals` used to average those rows
/// and drop them.
///
/// `Charts` ships with the system and the app targets macOS 14, so this adds no
/// dependency and no drawing code.
struct RateChart: View {
    let series: StoreVitalsClient.MetricSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Chart(series.points) { point in
                AreaMark(x: .value("Day", point.date),
                         y: .value("Rate", point.value * 100))
                    .foregroundStyle(.linearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", point.date),
                         y: .value("Rate", point.value * 100))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.sep)
                    AxisValueLabel {
                        if let rate = value.as(Double.self) {
                            Text(Self.axisRate(rate))
                                .font(Theme.font(size: 9.5))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.day().month(.abbreviated))
                                .font(Theme.font(size: 9.5))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            // The floor stays at zero. A chart scaled to its own smallest value
            // draws a molehill as a mountain, and every one of these rates is
            // read against zero and not against last Tuesday.
            .chartYScale(domain: 0...(max(series.highest * 100, 0.01) * 1.25))
            .frame(height: 92)
            .accessibilityLabel(Self.spoken(series))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(series.name)
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            if let rising = series.isRising {
                // Up is bad here. Both metrics count failures, so the arrow
                // and the colour agree with the reading and not with the
                // direction: a falling crash rate is good news in green.
                Label(rising ? "Rising" : "Falling",
                      systemImage: rising ? "arrow.up.right" : "arrow.down.right")
                    .font(Theme.font(size: 10.5, weight: .medium))
                    .foregroundStyle(rising ? Theme.orange : Theme.green)
            }
            if let newest = series.newest {
                Text(StoreVitalsClient.percent(newest.value))
                    .font(Theme.mono(11))
            }
        }
    }

    /// Orange once the line is worth a second look.
    ///
    /// Play publishes a bad behaviour threshold per metric, 1.09 % for crashes
    /// and 0.47 % for ANRs, and this takes the lower of the two for both: a
    /// chart that only turns at the crash threshold says nothing on the ANR
    /// card beside it.
    ///
    /// ponytail: one constant, not a table. The Reporting API is not among the
    /// references in `docs/`, so these two numbers come from Play's published
    /// thresholds rather than from a file on disk. The colour is a hint over a
    /// number the reader can see, so a stale threshold misleads nobody. Split
    /// it per metric if Play moves them apart.
    private var tint: Color {
        (series.newest?.value ?? 0) >= 0.0047 ? Theme.orange : Theme.teal
    }

    /// A rate axis reads in percent, and a hundredth of a point is noise.
    static func axisRate(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%.2f%%", value)
    }

    /// One sentence for VoiceOver, because a chart is a picture of a list.
    static func spoken(_ series: StoreVitalsClient.MetricSeries) -> String {
        let days = series.points.count
        let latest = series.newest.map { StoreVitalsClient.percent($0.value) } ?? "no value"
        let direction = series.isRising.map { $0 ? ", rising" : ", falling" } ?? ""
        return "\(series.name) over \(days) days, latest \(latest)\(direction)"
    }
}

/// One column of a store report over the days it covers.
///
/// It names no column. `ReportTable` works out which columns hold dates and
/// which hold numbers by reading the values, the panel offers what it found,
/// and the developer picks. Apple documents the transport of these reports and
/// never their contents, so a chart that hardcoded "Units" would draw nothing
/// the day Apple ships "Units Sold".
struct ReportSeriesChart: View {
    let column: String
    let points: [ReportPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(column)
                    .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                Text(Self.compact(points.reduce(0) { $0 + $1.value }))
                    .font(Theme.mono(11))
            }
            Chart(points) { point in
                BarMark(x: .value("Day", point.date, unit: .day),
                        y: .value(column, point.value))
                    .foregroundStyle(Theme.teal)
                    .cornerRadius(2)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.sep)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(Self.compact(number))
                                .font(Theme.font(size: 9.5))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.day().month(.abbreviated))
                                .font(Theme.font(size: 9.5))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .frame(height: 92)
            .accessibilityLabel("\(column) over \(points.count) days")
        }
    }

    /// Whole numbers stay whole and thousands lose their tail. A units column
    /// counts things, and "1,240.00" is two lies about a count.
    static func compact(_ value: Double) -> String {
        let rounded = value.rounded()
        guard abs(value - rounded) < 0.005 else {
            return String(format: "%.2f", value)
        }
        return Int(rounded).formatted(.number)
    }
}

/// One column of a store report, split by another column of the same report.
///
/// What a single day can answer on its own. A daily sales report is one day, so
/// it has no line to draw, and the question it does answer is where the day's
/// numbers came from: which countries, which products, which page.
struct ReportShareChart: View {
    let column: String
    let by: String
    let shares: [ReportShare]

    /// A row each, and not a `Chart`.
    ///
    /// This was a horizontal `BarMark` and the categorical axis fought it: a
    /// custom label closure lays out inside the plot area, so every name landed
    /// on the bar above it, `centered` dropped the labels, and the built-in
    /// label took its space out of the band and left a five point bar. A
    /// ranked top ten needs no axis, no scale and no gridlines. It needs a
    /// name, a bar and a number, which is three views in a row.
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(column) by \(by)")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(shares) { share in
                    HStack(spacing: 8) {
                        Text(share.label)
                            .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text2)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: Theme.scaled(96), alignment: .leading)
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.teal)
                                .frame(width: max(2, proxy.size.width * Self.fraction(
                                    share.value, of: shares.first?.value)))
                        }
                        .frame(height: 11)
                        Text(ReportSeriesChart.compact(share.value))
                            .font(Theme.mono(10)).foregroundStyle(Theme.text3)
                            .frame(width: Theme.scaled(64), alignment: .trailing)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(column) by \(by), \(shares.count) values, "
                + "largest \(shares.first?.label ?? "none")")
        }
    }

    /// Against the biggest bar, so the top row always fills the width and the
    /// rest read against it. A share of the total instead would draw ten
    /// slivers for an app that sells in forty countries.
    static func fraction(_ value: Double, of largest: Double?) -> Double {
        guard let largest, largest > 0, value > 0 else { return 0 }
        return min(1, value / largest)
    }
}

/// The crash rate of each version, against the one before it.
///
/// The rates were already read and already compared: `crashRateChange` turned
/// them into one sentence about the newest two and dropped the rest. The
/// comparison a developer actually makes is across every version that is still
/// out there, and that is a picture and not a sentence.
struct VersionRateChart: View {
    let rates: [StoreVitalsClient.VersionRate]

    /// Oldest first, so the bars read left to right the way releases happened.
    /// `googleCrashRateByVersion` answers newest first, for a strip that names
    /// the newest two.
    private var ordered: [StoreVitalsClient.VersionRate] {
        rates.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Crash rate by version")
                .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
            Chart(ordered) { rate in
                BarMark(x: .value("Version", rate.version),
                        y: .value("Rate", rate.rate * 100))
                    .foregroundStyle(rate.id == rates.first?.id ? Theme.teal : Theme.text3)
                    .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.sep)
                    AxisValueLabel {
                        if let rate = value.as(Double.self) {
                            Text(RateChart.axisRate(rate))
                                .font(Theme.font(size: 9.5))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let version = value.as(String.self) {
                            Text(version)
                                .font(Theme.font(size: 9.5))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .frame(height: 92)
            .accessibilityLabel(
                "Crash rate by version, \(rates.count) versions, newest \(rates.first?.version ?? "none")")
            Text("The newest version is highlighted. A version code, not a version name: Play reports the number the build carries.")
                .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

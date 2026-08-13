import Foundation
import Testing
@testable import SubmitKit

/// The shape behind the average.
///
/// Google answers a row per day and the vitals read averaged every one of them
/// into a single number. The average is the honest summary of a month and it
/// hides the one thing worth opening the panel for: a rate held flat at 0.4 %
/// and a rate climbing from 0.1 % to 0.9 % are the same average, and only one
/// of them is a release worth stopping. The days were in hand the whole time.
///
/// ponytail: the Reporting API is not among the references in `docs/`, so the
/// parsing here is written against the shape the API documents online and has
/// never run against a real account. Everything below is a pure function over a
/// payload, so a wrong shape is one fix in one place, and an unreadable answer
/// draws nothing rather than a line nobody can stand behind.
struct VitalsSeriesTests {

    private let metric = "userPerceivedCrashRate"

    /// A day the Reporting API sends as its parts, which is how it sends one.
    private func rows(_ days: [(Int, Double)]) -> JSON {
        JSON(["rows": days.map { day, rate in
            ["startTime": ["year": 2026, "month": 8, "day": day],
             "metrics": [["metric": self.metric,
                          "decimalValue": ["value": String(rate)]]]]
        }])
    }

    private func date(_ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                 year: 2026, month: 8, day: day))!
    }

    @Test func everyDayBecomesAPointAndTheyRunOldestFirst() {
        let points = StoreVitalsClient.series(rows([(3, 0.012), (1, 0.008), (2, 0.010)])["rows"].array,
                                              metric: metric)

        #expect(points.map(\.value) == [0.008, 0.010, 0.012])
        #expect(points.first?.date == date(1))
        #expect(points.last?.date == date(3))
    }

    /// A row that names no day belongs to no day. Stacking it onto whichever
    /// date sorts first would draw a spike on a day that never had one.
    @Test func aRowWithNoDayIsDropped() {
        let payload = JSON(["rows": [
            ["metrics": [["metric": metric, "decimalValue": ["value": "0.02"]]]],
            ["startTime": ["year": 2026, "month": 8],
             "metrics": [["metric": metric, "decimalValue": ["value": "0.03"]]]],
        ]])
        #expect(StoreVitalsClient.series(payload["rows"].array, metric: metric).isEmpty)
    }

    /// The store counts a day in its own zone. Reading one in the developer's
    /// would move every point by a day for half the world.
    @Test func aDayIsReadInUTC() throws {
        let day = try #require(StoreVitalsClient.day(
            JSON(["year": 2026, "month": 8, "day": 12])))
        #expect(day == date(12))
        #expect(StoreVitalsClient.day(JSON(["year": 2026])) == nil)
    }

    /// Google sends a decimal as a string inside `decimalValue`, and sometimes
    /// as a number. Three readers wanted the same two lines.
    @Test func aValueIsReadAsTextOrAsANumber() {
        let text = JSON(["metrics": [["metric": metric,
                                      "decimalValue": ["value": "0.015"]]]])
        let number = JSON(["metrics": [["metric": metric,
                                        "decimalValue": ["value": 0.015]]]])
        #expect(StoreVitalsClient.value(text, metric: metric) == 0.015)
        #expect(StoreVitalsClient.value(number, metric: metric) == 0.015)
        #expect(StoreVitalsClient.value(text, metric: "userPerceivedAnrRate") == nil)
    }

    // MARK: - What the header over the chart says

    /// Two halves and not the last two days. A daily rate moves on its own, and
    /// a line drawn from yesterday to today reports the noise.
    @Test func theTrendComparesTwoHalvesOfTheWindow() throws {
        let rising = StoreVitalsClient.MetricSeries(name: "Crashes", points: [
            .init(date: date(1), value: 0.001), .init(date: date(2), value: 0.001),
            .init(date: date(3), value: 0.009), .init(date: date(4), value: 0.009),
        ])
        #expect(try #require(rising.isRising))

        let falling = StoreVitalsClient.MetricSeries(name: "Crashes", points: [
            .init(date: date(1), value: 0.009), .init(date: date(2), value: 0.009),
            .init(date: date(3), value: 0.001), .init(date: date(4), value: 0.001),
        ])
        #expect(!(try #require(falling.isRising)))
    }

    /// A rate that barely moved is the same rate twice, and too few days is not
    /// a trend at all. Both say nothing rather than pointing an arrow.
    @Test func aFlatOrShortWindowClaimsNoDirection() {
        let flat = StoreVitalsClient.MetricSeries(name: "Crashes", points: [
            .init(date: date(1), value: 0.01000), .init(date: date(2), value: 0.01000),
            .init(date: date(3), value: 0.01002), .init(date: date(4), value: 0.01001),
        ])
        #expect(flat.isRising == nil)

        let short = StoreVitalsClient.MetricSeries(name: "Crashes", points: [
            .init(date: date(1), value: 0.001), .init(date: date(2), value: 0.009),
        ])
        #expect(short.isRising == nil)
    }

    @Test func theSeriesNamesItsNewestPointAndItsPeak() {
        let series = StoreVitalsClient.MetricSeries(name: "Crashes", points: [
            .init(date: date(1), value: 0.004),
            .init(date: date(2), value: 0.012),
            .init(date: date(3), value: 0.006),
        ])
        #expect(series.highest == 0.012)
        #expect(series.newest?.value == 0.006)
        #expect(series.newest?.date == date(3))
    }
}

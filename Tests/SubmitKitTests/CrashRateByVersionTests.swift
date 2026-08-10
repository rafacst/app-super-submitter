import Foundation
import Testing
@testable import SubmitKit

/// Whether the release made things worse.
///
/// A crash rate on its own is a number nobody can act on: 1.2% is bad if the
/// version before it was 0.8% and good if it was 2%. The Play Developer
/// Reporting API splits a metric set by dimension, so the same query that
/// answers "what is the rate" answers "what was it before" when it is asked per
/// version code.
///
/// ponytail: the Reporting API is not among the references in `docs/`, so the
/// parsing below is written against the shape the API documents online and has
/// never run against a real account. Everything here is therefore a pure
/// function over a payload, so the day somebody presses the button on a real
/// app, a wrong shape is a fix in one place.
struct CrashRateByVersionTests {

    private func rows(_ pairs: [(String, Double)], metric: String) -> JSON {
        JSON(["rows": pairs.map { version, rate in
            ["dimensions": [["dimension": "versionCode", "stringValue": version]],
             "metrics": [["metric": metric,
                          "decimalValue": ["value": String(rate)]]]]
        }])
    }

    @Test func aRateIsReadPerVersionAndSortedNewestFirst() {
        let payload = rows([("2408", 0.008), ("2410", 0.012), ("2409", 0.010)],
                           metric: "userPerceivedCrashRate")
        let rates = StoreVitalsClient.versionRates(payload["rows"].array,
                                                   metric: "userPerceivedCrashRate")

        #expect(rates.map(\.version) == ["2410", "2409", "2408"])
        #expect(rates.first?.rate == 0.012)
    }

    /// A row without a version code belongs to no version, so it is dropped
    /// rather than folded into whichever one sorts first.
    @Test func aRowWithNoVersionIsDropped() {
        let payload = JSON(["rows": [
            ["metrics": [["metric": "userPerceivedCrashRate",
                          "decimalValue": ["value": "0.02"]]]],
        ]])
        #expect(StoreVitalsClient.versionRates(payload["rows"].array,
                                               metric: "userPerceivedCrashRate").isEmpty)
    }

    /// Google returns one row per day per version, so the rate of a version is
    /// the mean of its days and not whichever day came last.
    @Test func theDaysOfOneVersionAverageIntoOneRate() {
        let payload = rows([("2410", 0.010), ("2410", 0.014)],
                           metric: "userPerceivedCrashRate")
        let rates = StoreVitalsClient.versionRates(payload["rows"].array,
                                                   metric: "userPerceivedCrashRate")

        #expect(rates.count == 1)
        #expect(rates.first?.rate == 0.012)
    }

    // MARK: - What the strip says

    @Test func theDeltaNamesTheDirectionAndTheVersionItIsAgainst() throws {
        let worse = try #require(StoreVitalsClient.crashRateChange([
            .init(version: "2410", rate: 0.012),
            .init(version: "2409", rate: 0.008),
        ]))
        #expect(worse.isWorse)
        #expect(worse.line.contains("2409"))
        #expect(worse.line.contains("0.4"))

        let better = try #require(StoreVitalsClient.crashRateChange([
            .init(version: "2410", rate: 0.008),
            .init(version: "2409", rate: 0.012),
        ]))
        #expect(!better.isWorse)
    }

    /// One version is the first release, and a first release is not a
    /// regression. It says nothing rather than comparing itself to zero.
    @Test func oneVersionSaysNothing() {
        #expect(StoreVitalsClient.crashRateChange([
            .init(version: "2410", rate: 0.012),
        ]) == nil)
        #expect(StoreVitalsClient.crashRateChange([]) == nil)
    }

    /// A change too small to act on is noise. The strip is for the one fact
    /// worth reading before the cards, so a rate that barely moved says
    /// nothing at all.
    @Test func aChangeTooSmallToActOnIsNotReported() {
        #expect(StoreVitalsClient.crashRateChange([
            .init(version: "2410", rate: 0.01002),
            .init(version: "2409", rate: 0.01),
        ]) == nil)
    }
}

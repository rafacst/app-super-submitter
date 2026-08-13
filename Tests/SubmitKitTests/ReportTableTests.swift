import Foundation
import Testing
@testable import SubmitKit

/// A report read as a table, because Apple documents no schema.
///
/// The App Store Connect reference documents the transport of these reports and
/// never their contents: five categories, and no report name, no column and no
/// dimension. So nothing here names a column. It reads the header the file
/// carries and works out which columns hold dates and which hold numbers by
/// looking at the values.
///
/// A chart built on a hardcoded "Units" draws nothing the day Apple ships
/// "Units Sold", and draws a wrong number the day another report has a column
/// by that name meaning something else.
struct ReportTableTests {

    /// The sales report shape, cut down. Two days, two countries, and the
    /// columns Apple actually puts around them.
    private let sales = """
        Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tUnits\tDeveloper Proceeds\tBegin Date\tEnd Date\tCountry Code
        APPLE\tUS\tcom.example\tRafael\tExample\t1.4\t10\t7.00\t08/01/2026\t08/01/2026\tUS
        APPLE\tUS\tcom.example\tRafael\tExample\t1.4\t4\t2.80\t08/01/2026\t08/01/2026\tBR
        APPLE\tUS\tcom.example\tRafael\tExample\t1.4\t7\t4.90\t08/02/2026\t08/02/2026\tUS
        APPLE\tUS\tcom.example\tRafael\tExample\t1.4\t2\t1.40\t08/02/2026\t08/02/2026\tBR
        """

    private func date(_ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                 year: 2026, month: month, day: day))!
    }

    @Test func aReportSplitsIntoItsHeaderAndItsRows() {
        let table = ReportTable.parse(sales)
        #expect(table.columns.count == 11)
        #expect(table.rows.count == 4)
        #expect(table.columns.first == "Provider")
    }

    /// A short row is padded and kept. A trailing empty field is a real answer,
    /// and dropping the row over it loses the numbers beside it.
    @Test func aShortRowIsPaddedRatherThanDropped() {
        let table = ReportTable.parse("a\tb\tc\n1\t2")
        #expect(table.rows == [["1", "2", ""]])
    }

    @Test func aCommaSeparatedReportIsReadToo() {
        let table = ReportTable.parse("Day,Units\n2026-08-01,5")
        #expect(table.columns == ["Day", "Units"])
        #expect(table.rows == [["2026-08-01", "5"]])
    }

    // MARK: - Which column is which

    /// The leftmost date column wins the tie. A sales report carries a begin
    /// date and an end date and both parse for every row; the begin date is the
    /// one a row belongs to, and it is the one Apple puts first.
    @Test func theDateColumnIsFoundAndTheLeftmostWinsATie() throws {
        let table = ReportTable.parse(sales)
        let index = try #require(table.dateColumn)
        #expect(table.columns[index] == "Begin Date")
    }

    /// A column of numbers is a measure. The date is not one, and a column
    /// holding the same value in every row draws a rectangle.
    @Test func theNumericColumnsExcludeTheDateAndTheConstants() {
        let table = ReportTable.parse(sales)
        let names = table.numericColumns.map { table.columns[$0] }

        #expect(names.contains("Units"))
        #expect(names.contains("Developer Proceeds"))
        // The date belongs to the dates.
        #expect(!names.contains("Begin Date"))
        // One value in every row. Nothing to see.
        #expect(!names.contains("Version"))
    }

    /// A breakdown groups by something that names rather than measures, and a
    /// column with a different answer in every row is not a grouping either.
    @Test func theLabelColumnsAreTheOnesWorthGroupingBy() {
        let table = ReportTable.parse(sales)
        let names = table.labelColumns.map { table.columns[$0] }

        #expect(names.contains("Country Code"))
        // One value throughout: grouping by it makes one bar.
        #expect(!names.contains("Provider"))
        #expect(!names.contains("Units"))
    }

    // MARK: - The two shapes

    /// A store report is one row per dimension per day, so the day's number is
    /// the total of its rows.
    @Test func aColumnSumsPerDay() throws {
        let table = ReportTable.parse(sales)
        let units = try #require(table.columns.firstIndex(of: "Units"))
        let points = table.series(column: units)

        #expect(points.count == 2)
        #expect(points[0].date == date(8, 1))
        #expect(points[0].value == 14)
        #expect(points[1].value == 9)
    }

    /// The chart a single day can answer on its own: not which way the line is
    /// going, but where the day's numbers came from.
    @Test func aColumnSumsPerLabelBiggestFirst() throws {
        let table = ReportTable.parse(sales)
        let units = try #require(table.columns.firstIndex(of: "Units"))
        let country = try #require(table.columns.firstIndex(of: "Country Code"))
        let shares = table.breakdown(column: units, by: country)

        #expect(shares.map(\.label) == ["US", "BR"])
        #expect(shares[0].value == 17)
        #expect(shares[1].value == 6)
    }

    @Test func aBreakdownKeepsOnlyTheBiggestFew() {
        let rows = (1...20).map { "row\($0)\t\($0)" }.joined(separator: "\n")
        let table = ReportTable.parse("Name\tCount\n\(rows)")
        let shares = table.breakdown(column: 1, by: 0, limit: 3)

        #expect(shares.count == 3)
        #expect(shares.map(\.value) == [20, 19, 18])
    }

    // MARK: - Reading one cell

    @Test func theDateFormatsTheStoresShipAreAllRead() {
        #expect(ReportTable.day("2026-08-12") == date(8, 12))
        #expect(ReportTable.day("08/12/2026") == date(8, 12))
        #expect(ReportTable.day("20260812") == date(8, 12))
        #expect(ReportTable.day("2026-08") == date(8, 1))
    }

    /// The ranges are checked before the date is built. `Calendar` turns a
    /// thirteenth month into the next January rather than refusing it, and an
    /// eight-digit identifier would sail through as a day.
    @Test func aNumberThatIsNotADateIsRefused() {
        #expect(ReportTable.day("6775815750") == nil)
        #expect(ReportTable.day("12345678") == nil)
        #expect(ReportTable.day("2026-13-01") == nil)
        #expect(ReportTable.day("2026-08-32") == nil)
        #expect(ReportTable.day("") == nil)
        #expect(ReportTable.day("1.4") == nil)
    }

    /// Apple writes a negative proceed in parentheses in some reports.
    @Test func aNumberIsReadIncludingApplesParentheses() {
        #expect(ReportTable.number("7.00") == 7)
        #expect(ReportTable.number("(2.50)") == -2.5)
        #expect(ReportTable.number("-3") == -3)
        #expect(ReportTable.number("") == nil)
        #expect(ReportTable.number("US") == nil)
    }

    // MARK: - Many days, one table

    /// One request answers one period, so a range is a request per day and the
    /// days have to line up afterwards.
    @Test func theDaysJoinIntoOneTableOnMatchingColumns() {
        let dayOne = "Day\tUnits\n2026-08-01\t5"
        let dayTwo = "Day\tUnits\n2026-08-02\t8"
        // A different shape cannot be lined up, so it is left out rather than
        // shifted into the wrong columns.
        let stranger = "Day\tUnits\tExtra\n2026-08-03\t9\tx"

        let joined = AppleReportsClient.join([dayOne, dayTwo, stranger])
        #expect(joined.columns == ["Day", "Units"])
        #expect(joined.rows.count == 2)
        #expect(joined.series(column: 1).map(\.value) == [5, 8])
    }

    /// Yesterday and back. Today's report does not exist: Apple closes a day
    /// and publishes it the day after.
    @Test func theReportDatesStopAtYesterdayAndRunOldestFirst() throws {
        let now = try #require(Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                 year: 2026, month: 8, day: 12)))
        let dates = AppleReportsClient.reportDates(days: 3, endingAt: now)
        #expect(dates == ["2026-08-09", "2026-08-10", "2026-08-11"])
    }
}

import Foundation

/// A store report, read as a table rather than as a schema.
///
/// Apple documents the transport of its reports and never their contents: the
/// API reference names five report categories and no report name, no column and
/// no dimension. Nothing here names a column either. It reads the header the
/// file carries, works out which columns hold dates and which hold numbers by
/// looking at the values, and offers what it found.
///
/// This replaced two readers of the same file. `AppleReportsClient` had a
/// `columns` that split the header and a `preview` that split the first twelve
/// rows, each with its own copy of the separator rule, and the charts needed
/// the values as well. Two readers of one format drift.
///
/// That is the only approach that survives Apple adding a report, renaming a
/// column, or shipping a schema this app has never seen. A chart built on a
/// hardcoded "Units" draws nothing the day Apple ships "Units Sold", and worse,
/// draws a wrong number the day some other report has a column by that name
/// meaning something else.
public struct ReportTable: Sendable, Equatable {
    public var columns: [String]
    public var rows: [[String]]

    public init(columns: [String] = [], rows: [[String]] = []) {
        self.columns = columns
        self.rows = rows
    }

    public var isEmpty: Bool { columns.isEmpty || rows.isEmpty }

    /// Splits a report into its header and every one of its rows.
    ///
    /// Apple ships these tab separated and a few comma separated, so the
    /// separator is whatever the header actually uses. A short row is padded
    /// rather than dropped: a trailing empty field is a real answer and losing
    /// the whole row over it loses the numbers beside it.
    public static func parse(_ text: String) -> ReportTable {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
        guard let header = lines.first else { return ReportTable() }
        let separator: Character = header.contains("\t") ? "\t" : ","
        func cells(_ line: String) -> [String] {
            line.split(separator: separator, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let columns = cells(header)
        guard !columns.isEmpty else { return ReportTable() }
        let rows = lines.dropFirst().map { line -> [String] in
            var row = cells(line)
            if row.count < columns.count {
                row += Array(repeating: "", count: columns.count - row.count)
            }
            return Array(row.prefix(columns.count))
        }
        return ReportTable(columns: columns, rows: rows)
    }

    /// The values of one column, by its position.
    public func values(at index: Int) -> [String] {
        guard columns.indices.contains(index) else { return [] }
        return rows.map { $0[index] }
    }

    // MARK: - What the columns turned out to hold

    /// The column that holds the day each row belongs to, or nil for a report
    /// that carries no date at all.
    ///
    /// The leftmost wins a tie on purpose. A sales report carries a begin date
    /// and an end date and both parse for every row; the begin date is the one
    /// a row belongs to, and it is the one Apple puts first.
    public var dateColumn: Int? {
        var best: (index: Int, count: Int)?
        for index in columns.indices {
            let parsed = values(at: index).filter { Self.day($0) != nil }.count
            // Most of the column, not one lucky row. An id column with a single
            // value that happens to read as a date is not a date column.
            guard parsed > rows.count / 2, parsed > 0 else { continue }
            if best == nil || parsed > best!.count { best = (index, parsed) }
        }
        return best?.index
    }

    /// Every column whose values are numbers worth adding up.
    ///
    /// The date column is excluded because it is a date, and a column holding
    /// one repeated value is excluded because a chart of it is a rectangle. No
    /// column is excluded for what it is called: this app does not know what
    /// Apple's columns mean, and a developer reading their own report does.
    public var numericColumns: [Int] {
        let date = dateColumn
        return columns.indices.filter { index in
            guard index != date else { return false }
            let raw = values(at: index).filter { !$0.isEmpty }
            guard raw.count > rows.count / 2, !raw.isEmpty else { return false }
            guard raw.allSatisfy({ Self.number($0) != nil }) else { return false }
            return Set(raw).count > 1
        }
    }

    /// Every column that names something rather than measuring it, which is
    /// what a breakdown groups by.
    public var labelColumns: [Int] {
        let numeric = Set(numericColumns)
        let date = dateColumn
        return columns.indices.filter { index in
            guard index != date, !numeric.contains(index) else { return false }
            let raw = values(at: index).filter { !$0.isEmpty }
            // More than one answer, and not a free-text column with a different
            // answer in every row. Either extreme draws an unreadable chart.
            let distinct = Set(raw).count
            return distinct > 1 && distinct <= max(40, rows.count / 2)
        }
    }

    // MARK: - The two shapes a report can be drawn as

    /// One column summed per day.
    ///
    /// Summed, because a store report is one row per dimension per day and the
    /// day's number is the total of its rows. That is right for a count and
    /// wrong for a rate, and the panel says so rather than guessing which one
    /// the developer picked.
    public func series(column index: Int) -> [ReportPoint] {
        guard let dateIndex = dateColumn, columns.indices.contains(index) else { return [] }
        var byDay: [Date: Double] = [:]
        for row in rows {
            guard let day = Self.day(row[dateIndex]),
                  let value = Self.number(row[index]) else { continue }
            byDay[day, default: 0] += value
        }
        return byDay.map { ReportPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// One column summed per value of another, biggest first.
    ///
    /// The chart a single report can answer on its own. A daily sales report is
    /// one day, so it has no line to draw, and the question it does answer is
    /// which countries or which products the day's numbers came from.
    public func breakdown(column index: Int, by label: Int,
                          limit: Int = 10) -> [ReportShare] {
        guard columns.indices.contains(index), columns.indices.contains(label)
        else { return [] }
        var byLabel: [String: Double] = [:]
        for row in rows {
            let key = row[label]
            guard !key.isEmpty, let value = Self.number(row[index]) else { continue }
            byLabel[key, default: 0] += value
        }
        return byLabel.map { ReportShare(label: $0.key, value: $0.value) }
            .sorted { ($0.value, $1.label) > ($1.value, $0.label) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Reading one cell

    /// The day a cell names, in the formats the stores actually ship:
    /// `2026-08-12`, `08/12/2026`, `20260812`, and `2026-08`.
    ///
    /// Read digit by digit rather than through a `DateFormatter`. A formatter
    /// is expensive, a report asks for one per cell of every column while it
    /// works out which column is the date, and one held in a `static` is shared
    /// mutable state that this module compiles with strict concurrency against.
    ///
    /// The ranges are checked before the date is built, which is what keeps an
    /// eight-digit identifier from reading as a day. `Calendar` normalises a
    /// thirteenth month into the next year rather than refusing it.
    ///
    /// UTC throughout. A store counts a day in its own zone, and reading one in
    /// the developer's moves every point by a day for half the world.
    public static func day(_ value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 6 else { return nil }

        func parts(_ separator: Character) -> [Int]? {
            let pieces = text.split(separator: separator, omittingEmptySubsequences: false)
            let numbers = pieces.compactMap { Int($0) }
            guard numbers.count == pieces.count else { return nil }
            return numbers
        }

        var year = 0, month = 0, day = 1
        if text.contains("-") {
            guard let numbers = parts("-") else { return nil }
            switch numbers.count {
            case 3: (year, month, day) = (numbers[0], numbers[1], numbers[2])
            case 2: (year, month) = (numbers[0], numbers[1])
            default: return nil
            }
        } else if text.contains("/") {
            // Apple writes the American order in the sales reports.
            guard let numbers = parts("/"), numbers.count == 3 else { return nil }
            (month, day, year) = (numbers[0], numbers[1], numbers[2])
        } else if text.count == 8, let packed = Int(text) {
            year = packed / 10_000
            month = (packed / 100) % 100
            day = packed % 100
        } else {
            return nil
        }

        guard (1970...2200).contains(year), (1...12).contains(month),
              (1...31).contains(day) else { return nil }
        return Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                 year: year, month: month, day: day))
    }

    /// The number a cell holds.
    ///
    /// POSIX, so a report written with a decimal point is read with one
    /// wherever the developer lives. Apple writes a negative proceed in
    /// parentheses in some reports, and a thousands separator in none of them,
    /// so the parentheses are read and a comma is left to fail.
    public static func number(_ value: String) -> Double? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var negative = false
        if text.hasPrefix("("), text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }
        guard let parsed = Double(text) else { return nil }
        return negative ? -parsed : parsed
    }
}

/// One day of one column.
public struct ReportPoint: Sendable, Equatable, Identifiable {
    public var date: Date
    public var value: Double

    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// One value of a grouping column, and what it added up to.
public struct ReportShare: Sendable, Equatable, Identifiable {
    public var label: String
    public var value: Double

    public var id: String { label }

    public init(label: String, value: Double) {
        self.label = label
        self.value = value
    }
}

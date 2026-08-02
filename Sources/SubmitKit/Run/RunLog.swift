import Foundation

/// One API call, as the run log records it. Spec section 11.4.
///
/// The record holds no token, no body, and no header. A run log sits in a
/// repository, so it must be safe to commit and safe to paste into a ticket.
public struct APICall: Sendable, Codable, Equatable {
    public var system: String
    public var method: String
    public var path: String
    public var status: Int?
    public var durationMs: Int
    public var requestId: String?
    public var error: String?
    public var dryRun: Bool

    public init(system: String, method: String, path: String, status: Int? = nil,
                durationMs: Int = 0, requestId: String? = nil, error: String? = nil,
                dryRun: Bool = false) {
        self.system = system
        self.method = method
        self.path = path
        self.status = status
        self.durationMs = durationMs
        self.requestId = requestId
        self.error = error
        self.dryRun = dryRun
    }

    /// The line that tab 8 shows, and the shape the mockup asked for.
    public func line(at date: Date) -> String {
        let time = APICall.clock.string(from: date)
        let method = method.padding(toLength: max(5, method.count), withPad: " ", startingAt: 0)
        let path = self.path.count > 40
            ? String(self.path.prefix(39)) + "…"
            : self.path.padding(toLength: 40, withPad: " ", startingAt: 0)
        let result = dryRun ? "dry" : (error != nil ? "ERR" : "\(status ?? 0)")
        return "\(time)  \(method) \(path) \(result.leftPadded(to: 4))  \(durationMs)ms"
    }

    // `DateFormatter` is documented thread-safe for formatting once it is
    // configured, and nothing here reconfigures it.
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// Appends one JSON line per API call to `.super-submitter/runs/<stamp>.jsonl`.
///
/// The log opens the file once and keeps the handle, because a run makes
/// hundreds of calls and a re-open per line is the wrong cost.
public actor RunLog {
    /// The file this run writes. It never changes, so a caller reads it
    /// without hopping onto the actor.
    public nonisolated let url: URL
    private let handle: FileHandle
    private let encoder = JSONEncoder()

    /// - Parameter root: the folder that holds `store.yaml`.
    public init(root: URL, date: Date = Date()) throws {
        let folder = root.appendingPathComponent(".super-submitter/runs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = RunLog.stamp.string(from: date)
        let file = folder.appendingPathComponent("\(stamp).jsonl")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        url = file
    }

    public func append(_ call: APICall, at date: Date = Date()) {
        struct Line: Encodable {
            let time: String
            let call: APICall
        }
        guard let data = try? encoder.encode(
            Line(time: RunLog.iso(date), call: call)) else { return }
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data("\n".utf8))
    }

    public func close() {
        try? handle.close()
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}

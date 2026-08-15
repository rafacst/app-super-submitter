import Darwin
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
        self.path = Self.sanitizedPath(path)
        self.status = status
        self.durationMs = durationMs
        self.requestId = requestId
        self.error = error.map(Self.sanitizedError)
        self.dryRun = dryRun
    }

    /// The path as it was called, query string and all.
    ///
    /// The query used to be cut off here, so `?include=`, `?limit=` and every
    /// filter were absent from the screen, from the pasteboard and from the
    /// file. Those are the diagnostic half of a route: the bug where a run
    /// asked for no `include=territory` was invisible in its own log.
    ///
    /// `Redactor` masks a named secret in it, the same guard `sanitizedError`
    /// has. Nothing else about a request is recorded: no token, no header, no
    /// body.
    private static func sanitizedPath(_ path: String) -> String {
        let withoutFragment = String(path.split(separator: "#", maxSplits: 1,
                                                omittingEmptySubsequences: false)[0])
        return Redactor().redact(withoutFragment)
    }

    private static func sanitizedError(_ error: String) -> String {
        let redacted = Redactor().redact(error)
        var result = ""
        result.reserveCapacity(min(2_048, redacted.utf8.count))
        for character in redacted {
            guard result.utf8.count + String(character).utf8.count <= 2_048 else { break }
            result.append(character)
        }
        return result
    }

    /// The line that tab 8 shows, and the shape the mockup asked for.
    ///
    /// It is cut to the width of a box, so it is the wrong line to keep. Use
    /// `fullLine(at:)` for the pasteboard: the copy used to hand over these
    /// display lines, and a path arrived in the ticket as
    /// `/v2/appAvailabilities/6790568884/territ…`.
    public func line(at date: Date) -> String {
        let time = APICall.clock.string(from: date)
        let method = method.padding(toLength: max(5, method.count), withPad: " ", startingAt: 0)
        let path = self.path.count > 40
            ? String(self.path.prefix(39)) + "…"
            : self.path.padding(toLength: 40, withPad: " ", startingAt: 0)
        return "\(time)  \(method) \(path) \(outcome.leftPadded(to: 4))  \(durationMs)ms"
    }

    /// The whole call, for the pasteboard and for a ticket. Nothing is cut.
    ///
    /// The status and the error both, which is where this parts from the box
    /// line: a refusal is a number and a sentence, and the box has room for
    /// one of them. A call that failed before an answer has no number and
    /// says `ERR` in its place.
    public func fullLine(at date: Date) -> String {
        let result = dryRun ? "dry" : (status.map(String.init) ?? "ERR")
        var line = "\(APICall.clock.string(from: date))  \(method) \(path)"
            + "  \(result)  \(durationMs)ms"
        if let requestId, !requestId.isEmpty { line += "  request \(requestId)" }
        // Last, because it is the one part that runs to a paragraph.
        if let error, !error.isEmpty { line += "  \(error)" }
        return line
    }

    /// `200`, `ERR`, or `dry` for a call the dry run never made.
    private var outcome: String {
        dryRun ? "dry" : (error != nil ? "ERR" : "\(status ?? 0)")
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
    private var handle: FileHandle?
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
        url = file
        handle = try Self.openHandle(at: file)
    }

    public func append(_ call: APICall, at date: Date = Date()) {
        struct Line: Encodable {
            let time: String
            let call: APICall
        }
        guard let data = try? encoder.encode(
            Line(time: RunLog.iso(date), call: call)) else { return }
        if handle == nil { handle = try? Self.openHandle(at: url) }
        guard let handle else { return }
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data("\n".utf8))
    }

    public func close() {
        if let handle { try? handle.close() }
        handle = nil
    }

    private static func openHandle(at file: URL) throws -> FileHandle {
        let descriptor = Darwin.open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        _ = Darwin.fchmod(descriptor, 0o600)
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
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

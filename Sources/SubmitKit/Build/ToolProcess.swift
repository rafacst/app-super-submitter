import Foundation

/// One local tool run. upload-spec section 6.
///
/// The executable and the arguments stay separate values from construction to
/// launch. Nothing here builds a command string, so a project folder named
/// `; rm -rf ~` is one argument and never a second command.
public struct ToolInvocation: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var workingDirectory: URL?
    /// Names only. The values come from the sanitized environment at launch.
    public var environment: [String: String]
    public var timeout: TimeInterval?
    /// What the developer sees. Presentation only: it is never executed.
    public var phase: String

    public init(executable: URL, arguments: [String], workingDirectory: URL? = nil,
                environment: [String: String] = [:], timeout: TimeInterval? = nil,
                phase: String = "") {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.phase = phase
    }

    /// A readable preview. **It must never be copied into a shell**, and the
    /// quoting here exists to make that visible, not to make it runnable.
    public func preview(_ redactor: Redactor = Redactor()) -> String {
        let parts = [executable.path] + arguments.map { argument in
            argument.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
                ? argument
                : "\"\(argument)\""
        }
        return redactor.redact(parts.joined(separator: " "))
    }
}

public struct ToolOutcome: Sendable, Equatable {
    public var status: Int32
    /// The signal that ended the process, when one did.
    public var signal: Int32?
    public var standardOutput: String
    public var standardError: String
    public var timedOut: Bool

    public var succeeded: Bool { status == 0 && signal == nil && !timedOut }

    public init(status: Int32, signal: Int32? = nil, standardOutput: String = "",
                standardError: String = "", timedOut: Bool = false) {
        self.status = status
        self.signal = signal
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }
}

public enum ToolStream: String, Sendable {
    case standardOutput, standardError
}

/// The seam. The real runner starts a process; a test runner returns a fixture
/// and records the argument array, which is how the "no shell" rule is proved.
public protocol ToolRunning: Sendable {
    func run(_ invocation: ToolInvocation,
             onLine: @escaping @Sendable (ToolStream, String) -> Void) async throws -> ToolOutcome
}

public enum ToolError: Error, LocalizedError, Equatable {
    case notExecutable(String)
    case launchFailed(String, String)
    case timedOut(String, TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .notExecutable(let path):
            "\(path) is not an executable file."
        case .launchFailed(let path, let reason):
            "\(path) could not start. \(reason)"
        case .timedOut(let phase, let seconds):
            "\(phase) did not finish within \(Int(seconds)) seconds."
        }
    }
}

/// Launches one child process and streams its two channels as lines.
///
/// `// ponytail: one owned child, interrupt then terminate then its own
/// // children. Never a machine-wide pkill, because another window's Gradle
/// // daemon is not this run's process.`
public actor ToolProcess: ToolRunning {
    private let redactor: Redactor
    /// The grace period between the interrupt and the terminate.
    private let grace: TimeInterval

    public init(redactor: Redactor = Redactor(), grace: TimeInterval = 5) {
        self.redactor = redactor
        self.grace = grace
    }

    public func run(_ invocation: ToolInvocation,
                    onLine: @escaping @Sendable (ToolStream, String) -> Void) async throws
        -> ToolOutcome {
        guard FileManager.default.isExecutableFile(atPath: invocation.executable.path) else {
            throw ToolError.notExecutable(invocation.executable.path)
        }

        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory
        process.environment = Self.sanitized(invocation.environment)
        // Standard input is closed, so a tool that asks for a password fails
        // visibly instead of hanging forever. upload-spec section 9.4.
        process.standardInput = FileHandle.nullDevice

        let out = Pipe(), error = Pipe()
        process.standardOutput = out
        process.standardError = error

        let collector = LineCollector(redactor: redactor, onLine: onLine)
        out.fileHandleForReading.readabilityHandler = { handle in
            collector.take(handle.availableData, from: .standardOutput)
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            collector.take(handle.availableData, from: .standardError)
        }

        do {
            try process.run()
        } catch {
            throw ToolError.launchFailed(invocation.executable.path,
                                         error.localizedDescription)
        }

        let pid = process.processIdentifier
        let expired = Flag()
        let deadline = invocation.timeout.map { timeout in
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                expired.set()
                await self.stop(process, pid: pid)
            }
        }

        await withTaskCancellationHandler {
            await Self.wait(for: process)
        } onCancel: {
            Task { await self.stop(process, pid: pid) }
        }
        deadline?.cancel()

        // A short command can exit before its readability handler ever fires,
        // so the remaining bytes are drained after the handlers are cleared.
        out.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        collector.take(out.fileHandleForReading.readDataToEndOfFile(), from: .standardOutput)
        collector.take(error.fileHandleForReading.readDataToEndOfFile(), from: .standardError)
        collector.finish()

        if Task.isCancelled { throw CancellationError() }
        if expired.isSet, let timeout = invocation.timeout {
            throw ToolError.timedOut(invocation.phase.isEmpty ? invocation.executable.lastPathComponent
                                     : invocation.phase, timeout)
        }

        return ToolOutcome(
            status: process.terminationStatus,
            signal: process.terminationReason == .uncaughtSignal
                ? process.terminationStatus : nil,
            standardOutput: collector.text(.standardOutput),
            standardError: collector.text(.standardError),
            timedOut: expired.isSet)
    }

    /// Foundation does not call `terminationHandler` for a process that has
    /// already exited, so the check after the assignment is required.
    private static func wait(for process: Process) async {
        await withCheckedContinuation { continuation in
            let once = Flag()
            process.terminationHandler = { _ in
                if once.setIfClear() { continuation.resume() }
            }
            if !process.isRunning, once.setIfClear() { continuation.resume() }
        }
    }

    /// Interrupt, wait the grace period, then terminate this run's own tree.
    private func stop(_ process: Process, pid: Int32) async {
        guard process.isRunning else { return }
        process.interrupt()
        try? await Task.sleep(for: .seconds(grace))
        guard process.isRunning else { return }
        for child in Self.descendants(of: pid) { kill(child, SIGTERM) }
        process.terminate()
    }

    /// The children of one pid, found with `pgrep -P`. Bounded, and scoped to
    /// this run's own process.
    static func descendants(of pid: Int32, depth: Int = 0) -> [Int32] {
        guard depth < 4 else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let children = String(decoding: data, as: UTF8.self)
            .split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        return children + children.flatMap { descendants(of: $0, depth: depth + 1) }
    }

    /// upload-spec section 6.2. Keep the toolchain inputs, drop the secrets.
    ///
    /// The app never injects a credential into an environment when the tool
    /// takes a file or an API instead.
    static func sanitized(_ extra: [String: String]) -> [String: String] {
        var result = ProcessInfo.processInfo.environment
        for name in result.keys where Redactor.isSecretName(name) {
            result.removeValue(forKey: name)
        }
        for (name, value) in extra {
            result[name] = value
        }
        return result
    }

    /// The toolchain inputs that a preflight screen reports.
    public static func toolchainEnvironment() -> [String: String] {
        let names = ["PATH", "HOME", "LANG", "TMPDIR", "DEVELOPER_DIR", "JAVA_HOME",
                     "ANDROID_HOME", "ANDROID_SDK_ROOT"]
        let environment = ProcessInfo.processInfo.environment
        return names.reduce(into: [:]) { result, name in
            if let value = environment[name] { result[name] = value }
        }
    }
}

/// A one-way flag that two threads may set.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() { lock.withLock { value = true } }

    /// Sets the flag and reports whether this call is the one that set it.
    func setIfClear() -> Bool {
        lock.withLock {
            guard !value else { return false }
            value = true
            return true
        }
    }
}

/// Splits two byte streams into redacted lines, under one lock.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var partial: [ToolStream: String] = [:]
    private var full: [ToolStream: String] = [:]
    private let redactor: Redactor
    private let onLine: @Sendable (ToolStream, String) -> Void
    /// A build log can reach hundreds of megabytes. The retained text is
    /// bounded; the streamed lines are not.
    private let limit = 512 * 1_024

    init(redactor: Redactor, onLine: @escaping @Sendable (ToolStream, String) -> Void) {
        self.redactor = redactor
        self.onLine = onLine
    }

    func take(_ data: Data, from stream: ToolStream) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        var emit: [String] = []
        lock.withLock {
            var buffer = (partial[stream] ?? "") + chunk
            while let index = buffer.firstIndex(of: "\n") {
                let line = redactor.redact(String(buffer[..<index]))
                emit.append(line)
                append(line, to: stream)
                buffer = String(buffer[buffer.index(after: index)...])
            }
            partial[stream] = buffer
        }
        for line in emit { onLine(stream, line) }
    }

    func finish() {
        var emit: [(ToolStream, String)] = []
        lock.withLock {
            for (stream, rest) in partial where !rest.isEmpty {
                let line = redactor.redact(rest)
                emit.append((stream, line))
                append(line, to: stream)
            }
            partial = [:]
        }
        for (stream, line) in emit { onLine(stream, line) }
    }

    func text(_ stream: ToolStream) -> String {
        lock.withLock { full[stream] ?? "" }
    }

    private func append(_ line: String, to stream: ToolStream) {
        var value = (full[stream] ?? "") + line + "\n"
        if value.count > limit { value = String(value.suffix(limit)) }
        full[stream] = value
    }
}

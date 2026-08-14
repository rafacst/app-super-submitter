import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: Data
    public let error: String

    public var text: String { String(decoding: output, as: UTF8.self) }
    public var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Both pipes drain at the same time. One pipe that fills its 64 KB
        // buffer stops the child, and the child then never exits.
        let captured = PipeOutputs()
        let group = DispatchGroup()
        for (handle, isOut) in [(out.fileHandleForReading, true), (err.fileHandleForReading, false)] {
            DispatchQueue.global().async(group: group) {
                let data = handle.readDataToEndOfFile()
                captured.store(data, isStandardOutput: isOut)
            }
        }
        group.wait()
        process.waitUntilExit()

        let (outData, errData) = captured.snapshot()

        return CommandResult(
            status: process.terminationStatus,
            output: outData,
            error: String(decoding: errData, as: UTF8.self)
        )
    }
}

/// Dispatch requires a sendable capture, while the pipe readers need shared
/// storage. All access to this reference is serialized by its lock.
private final class PipeOutputs: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func store(_ data: Data, isStandardOutput: Bool) {
        lock.withLock {
            if isStandardOutput {
                standardOutput = data
            } else {
                standardError = data
            }
        }
    }

    func snapshot() -> (Data, Data) {
        lock.withLock { (standardOutput, standardError) }
    }
}

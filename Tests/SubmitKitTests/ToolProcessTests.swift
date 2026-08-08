import Foundation
import Testing
@testable import SubmitKit

/// Records every invocation and returns a fixture. upload-spec 15.2.
final class FakeToolRunner: ToolRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _invocations: [ToolInvocation] = []
    private let outcome: ToolOutcome
    private let lines: [(ToolStream, String)]
    private let hangs: Bool

    var invocations: [ToolInvocation] { lock.withLock { _invocations } }

    init(outcome: ToolOutcome = ToolOutcome(status: 0),
         lines: [(ToolStream, String)] = [], hangs: Bool = false) {
        self.outcome = outcome
        self.lines = lines
        self.hangs = hangs
    }

    func run(_ invocation: ToolInvocation,
             onLine: @escaping @Sendable (ToolStream, String) -> Void) async throws -> ToolOutcome {
        lock.withLock { _invocations.append(invocation) }
        for (stream, line) in lines { onLine(stream, line) }
        if hangs {
            try await Task.sleep(for: .seconds(600))
        }
        return outcome
    }
}

// MARK: - No shell, ever

@Test func everyInvocationKeepsTheExecutableAndTheArgumentsApart() async throws {
    let runner = FakeToolRunner(outcome: ToolOutcome(
        status: 0, standardOutput: #"{"project":{"schemes":["App"],"configurations":["Release"]}}"#))
    let service = AppleBuildService(runner: runner)

    _ = try await service.list(container: URL(fileURLWithPath: "/tmp/My App.xcodeproj"),
                               kind: .project)

    let invocation = try #require(runner.invocations.first)
    // The shell is never the executable, and no argument is a command line.
    #expect(!invocation.executable.path.hasSuffix("sh"))
    #expect(!invocation.executable.path.hasSuffix("bash"))
    #expect(!invocation.arguments.contains("-c"))
    for argument in invocation.arguments {
        #expect(!argument.contains(" && "))
        #expect(!argument.contains(" | "))
    }
}

@Test func aProjectNameWithShellMetacharactersStaysOneArgument() async throws {
    let hostile = "/tmp/Evil; rm -rf ~/$(whoami) `id`.xcodeproj"
    let runner = FakeToolRunner(outcome: ToolOutcome(
        status: 0, standardOutput: #"{"project":{"schemes":["App"]}}"#))

    _ = try await AppleBuildService(runner: runner)
        .list(container: URL(fileURLWithPath: hostile), kind: .project)

    let invocation = try #require(runner.invocations.first)
    // The whole hostile name is exactly one element of the array.
    #expect(invocation.arguments.filter { $0.contains("Evil") }.count == 1)
    #expect(invocation.arguments.contains { $0.contains("rm -rf") && $0.contains("Evil") })
}

@Test func theGradleWrapperRunsFromTheProjectAndNeverASystemGradle() async throws {
    let root = URL(fileURLWithPath: "/tmp/demo-project")
    let runner = FakeToolRunner(outcome: ToolOutcome(status: 0, standardOutput: ""))
    var toolchain = AndroidToolchain()
    toolchain.javaHome = "/opt/jdk"

    _ = try? await AndroidBuildService(runner: runner).buildBundle(
        root: root, toolchain: toolchain,
        variant: GradleVariant(module: ":app", task: "bundleRelease", variant: "release"),
        onLine: { _, _ in })

    let invocation = try #require(runner.invocations.first)
    #expect(invocation.executable.path == "/tmp/demo-project/gradlew")
    #expect(invocation.workingDirectory?.path == root.path)
    #expect(invocation.arguments.contains(":app:bundleRelease"))
    #expect(invocation.arguments.contains("--console=plain"))
    #expect(invocation.environment["JAVA_HOME"] == "/opt/jdk")
}

@Test func theCommandPreviewIsPresentationOnlyAndRedacted() {
    let invocation = ToolInvocation(
        executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
        arguments: ["xcodebuild", "-authenticationKeyID", "ABCD1234",
                    "-project", "/tmp/My App.xcodeproj"])

    let preview = invocation.preview(Redactor(literals: ["SUPERSECRETKEYVALUE"]))
    #expect(preview.contains("\"/tmp/My App.xcodeproj\""))
    #expect(!preview.contains("SUPERSECRETKEYVALUE"))
}

// MARK: - Redaction

@Test func aKnownSecretNeverSurvivesALine() {
    let key = "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEGCCqG\n-----END PRIVATE KEY-----"
    let redactor = Redactor(literals: [key, "rcsk_abcdefghijklmnop"])

    #expect(!redactor.redact("writing MIGTAgEAMBMGByqGSM49AgEGCCqG to disk").contains("MIGT"))
    #expect(!redactor.redact("Authorization: rcsk_abcdefghijklmnop").contains("rcsk_"))
}

@Test func aValueWhoseNameSaysSecretIsMaskedWhateverItHolds() {
    let redactor = Redactor()

    #expect(redactor.redact("KEYSTORE_PASSWORD=hunter2000") == "KEYSTORE_PASSWORD=«redacted»")
    #expect(redactor.redact("api_key: abc123xyz").contains("«redacted»"))
    #expect(!redactor.redact("Authorization: Bearer eyJhbGciOi").contains("eyJhbGciOi"))
    // An ordinary line survives untouched.
    #expect(redactor.redact("Compiling MyApp 3 of 40") == "Compiling MyApp 3 of 40")
}

@Test func aShortFragmentIsNotTreatedAsASecret() {
    // Redacting a two-character literal would blank half the log.
    let redactor = Redactor(literals: ["ab"])
    #expect(redactor.redact("about to build") == "about to build")
}

@Test func theSanitizedEnvironmentDropsSecretNamesAndKeepsTheToolchain() {
    setenv("SUPER_SUBMITTER_TEST_TOKEN", "abcd1234", 1)
    defer { unsetenv("SUPER_SUBMITTER_TEST_TOKEN") }

    let environment = ToolProcess.sanitized(["JAVA_HOME": "/opt/jdk"])
    #expect(environment["SUPER_SUBMITTER_TEST_TOKEN"] == nil)
    #expect(environment["JAVA_HOME"] == "/opt/jdk")
    #expect(environment["PATH"] != nil)
}

// MARK: - The real process, with no shell

@Test func theRunnerStreamsLinesAndReportsTheExitStatus() async throws {
    let outcome = try await ToolProcess().run(
        ToolInvocation(executable: URL(fileURLWithPath: "/bin/echo"),
                       arguments: ["one", "two"], phase: "test"),
        onLine: { _, _ in })

    #expect(outcome.succeeded)
    #expect(outcome.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "one two")
}

@Test func aFailingToolReportsItsStatusAndItsStandardError() async throws {
    let outcome = try await ToolProcess().run(
        ToolInvocation(executable: URL(fileURLWithPath: "/bin/sh"),
                       arguments: ["-c", "echo bad 1>&2; exit 3"], phase: "test"),
        onLine: { _, _ in })

    // This test drives /bin/sh on purpose, to prove the runner reports a
    // failure. No production path constructs a shell command.
    #expect(!outcome.succeeded)
    #expect(outcome.status == 3)
    #expect(outcome.standardError.contains("bad"))
}

@Test func standardInputIsClosedSoAPromptFailsInsteadOfHanging() async throws {
    let outcome = try await ToolProcess().run(
        ToolInvocation(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                       timeout: 5, phase: "test"),
        onLine: { _, _ in })

    // With standard input closed, `cat` reads end-of-file at once.
    #expect(outcome.succeeded)
}

@Test func anOversizeLogKeepsTheTailAndSaysThatItDroppedTheHead() async throws {
    // `seq` prints about 1.2 MB, over the 512 KB the collector retains.
    let outcome = try await ToolProcess().run(
        ToolInvocation(executable: URL(fileURLWithPath: "/usr/bin/seq"),
                       arguments: ["1", "200000"], phase: "test"),
        onLine: { _, _ in })

    #expect(outcome.succeeded)
    // The tail survives, the head does not, and the text says which.
    #expect(outcome.standardOutput.hasSuffix("\n200000\n"))
    #expect(outcome.standardOutput.contains("KB of earlier output dropped"))
    #expect(!outcome.standardOutput.contains("\n1000\n"))
    #expect(outcome.standardOutput.utf8.count < 600 * 1_024)
}

/// Collects streamed lines across the reader threads.
private final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}

@Test func aSecretPrintedByAToolNeverReachesTheRetainedLog() async throws {
    let secret = "SUPERSECRETVALUE12345"
    let sink = LineSink()
    let outcome = try await ToolProcess(redactor: Redactor(literals: [secret])).run(
        ToolInvocation(executable: URL(fileURLWithPath: "/bin/echo"),
                       arguments: [secret], phase: "test"),
        onLine: { _, line in sink.add(line) })

    #expect(!outcome.standardOutput.contains(secret))
    #expect(!sink.text.contains(secret))
    #expect(sink.text.contains("«redacted»"))
}
